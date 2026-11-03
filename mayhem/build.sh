#!/usr/bin/env bash
#
# mayhem/build.sh — build the fuzz harnesses for CloverBootloader: Clover's own config.plist / plist parsers
# (mayhem/build_clover.sh) and the OpenSSL harnesses vendored in Library/OpensslLib/openssl/fuzz, plus the
# OpenSSL unit tests used as the functional oracle.
# Runs in the commit image as `mayhem` in /mayhem. Idempotent and offline (no fetches).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
OSSL="$SRC/Library/OpensslLib/openssl"
BUILD="$SRC/mayhem/build"
FUZZ_B="$BUILD/fuzz"       # sanitized, fuzz-configured libcrypto/libssl
TEST_B="$BUILD/normal"     # project's normal flags: libcrypto + apps/openssl + unit tests
mkdir -p "$BUILD"

# The vendored tree has no tools/ directory, but the top-level build.info lists it as a SUBDIR, so
# Configure aborts. Present the tree through a symlink farm with an empty tools/build.info added
# (upstream files stay untouched, edits to the real tree are still picked up by make).
OSSL_REAL="$OSSL"
OSSL="$BUILD/src"
mkdir -p "$OSSL/tools"
[ -e "$OSSL/tools/build.info" ] || : > "$OSSL/tools/build.info"
for e in "$OSSL_REAL"/* "$OSSL_REAL"/.[!.]*; do
  [ -e "$e" ] || continue
  # leave existing links alone: touching them would make make re-run Configure
  [ "$(readlink "$OSSL/$(basename "$e")" 2>/dev/null)" = "$e" ] || ln -sfn "$e" "$OSSL/$(basename "$e")"
done

# CloverBootloader's vendored copy of OpenSSL calls the EDK2 CryptoPkg allocator (crypto/mem.c,
# crypto/conf/conf_lib.c). On Linux those are plain libc malloc/realloc/free.
EDK2_SHIMS=(-DCryptoPkg_BaseMemAllocation_malloc=malloc -DCryptoPkg_BaseMemAllocation_realloc=realloc
            -DCryptoPkg_BaseMemAllocation_free=free)

# configure_once <builddir> <stamp> <configure args...>: skip when already configured with the same args,
# so a re-run does not regenerate headers and rebuild the world.
configure_once() {
  local dir="$1" stamp="$2"; shift 2
  mkdir -p "$dir"
  if [ -f "$dir/Makefile" ] && [ "$(cat "$dir/.configure-stamp" 2>/dev/null)" = "$stamp" ]; then
    return 0
  fi
  (cd "$dir" && perl "$OSSL/Configure" "$@")
  printf '%s' "$stamp" > "$dir/.configure-stamp"
}

# ---- 1) sanitized libcrypto/libssl for the fuzz harnesses -------------------------------------------------
# -fno-sanitize=alignment,function: OpenSSL does benign unaligned loads (its own fuzz build disables
# alignment too) and calls typed LHASH/STACK callbacks through generic pointer types (UBSan "function").
FUZZ_ARGS=(linux-x86_64 no-shared no-asm no-tests
  enable-fuzz-libfuzzer -DPEDANTIC -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION
  enable-tls1_3 enable-rc5 enable-md2 enable-ec_nistp_64_gcc_128 enable-ssl3 enable-ssl3-method
  enable-nextprotoneg enable-weak-ssl-ciphers "${EDK2_SHIMS[@]}"
  CC="$CC" $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link -fno-sanitize=alignment,function)
configure_once "$FUZZ_B" "${FUZZ_ARGS[*]}" "${FUZZ_ARGS[@]}"
make -C "$FUZZ_B" -j"$MAYHEM_JOBS" build_generated
make -C "$FUZZ_B" -j"$MAYHEM_JOBS" libcrypto.a libssl.a

# ---- 2) harnesses: libFuzzer binary + run-once standalone reproducer ---------------------------------------
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$BUILD/lsan_off.o"
$CC  $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$BUILD/standalone_main.o"

INC=(-I"$FUZZ_B/include" -I"$OSSL/include" -I"$OSSL" -I"$FUZZ_B")
LIBS=("$FUZZ_B/libssl.a" "$FUZZ_B/libcrypto.a" -ldl -pthread)
CFLG=($SANITIZER_FLAGS $DEBUG_FLAGS -fno-sanitize=alignment,function -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION)

# harness name -> extra sources next to it
declare -A EXTRA=( [asn1]="fuzz_rand.c" [asn1parse]="" [bignum]="" [bndiv]="" [client]="fuzz_rand.c"
                   [cmp]="fuzz_rand.c" [cms]="" [conf]="" [crl]="" [ct]="" [server]="fuzz_rand.c" [x509]="fuzz_rand.c" )
for h in "${!EXTRA[@]}"; do
  srcs=("$OSSL/fuzz/$h.c" "$OSSL/fuzz/driver.c")
  for e in ${EXTRA[$h]}; do srcs+=("$OSSL/fuzz/$e"); done
  $CC "${CFLG[@]}" "${INC[@]}" "${srcs[@]}" "$BUILD/lsan_off.o" "${LIBS[@]}" $LIB_FUZZING_ENGINE \
      -o "$SRC/fuzz_$h"
  # driver.c only forwards LLVMFuzzerTestOneInput -> FuzzerTestOneInput; the run-once main calls it once.
  $CC "${CFLG[@]}" "${INC[@]}" "${srcs[@]}" "$BUILD/standalone_main.o" "$BUILD/lsan_off.o" "${LIBS[@]}" \
      -o "$SRC/fuzz_$h-standalone"
done

# ---- 2b) Clover's own parsers: fuzz_configplist, fuzz_plist (+ -standalone) ----------------------------------
bash "$SRC/mayhem/build_clover.sh"

# ---- 3) functional oracle: normal flags, no sanitizers ------------------------------------------------------
TEST_ARGS=(linux-x86_64 no-shared CC="$CC" "${EDK2_SHIMS[@]}" $COVERAGE_FLAGS)
configure_once "$TEST_B" "${TEST_ARGS[*]}" "${TEST_ARGS[@]}"
make -C "$TEST_B" -j"$MAYHEM_JOBS" build_generated
make -C "$TEST_B" -j"$MAYHEM_JOBS" libcrypto.a libssl.a
make -C "$TEST_B" -j"$MAYHEM_JOBS" apps/openssl \
  test/bntest test/evp_test test/pemtest test/asn1_internal_test test/asn1_time_test test/asn1_string_table_test \
  test/asn1_decode_test test/asn1_encode_test test/x509_time_test test/x509_internal_test test/bn_internal_test \
  test/exptest test/stack_test test/sanitytest test/hmactest
