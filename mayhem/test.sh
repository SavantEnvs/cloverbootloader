#!/usr/bin/env bash
#
# mayhem/test.sh — the functional oracle, two parts, both run against unsanitized binaries that
# mayhem/build.sh produced:
#  * Clover's own code: Clover's CloverConfigPlistValidator (ConfigPlistClass::parse) and a ParseXML dump driver
#    (mayhem/clover_oracle/plist_dump.cpp), built by mayhem/build_clover.sh into mayhem/build/clover. Their output is
#    compared with known answers (parsed tags of fixed plists, zero parser messages for a good config, the exact
#    warning/error text for bad ones), so a no-op or broken ParseXML / ConfigPlistClass::parse fails here.
#  * The vendored OpenSSL: OpenSSL's own unit tests (Library/OpensslLib/openssl/test) and a few known-answer CLI
#    checks (mayhem/build/normal). The test programs run directly (not through the perl harness) and their
#    top-level TAP `ok` / `not ok` lines are counted, so a neutered program (prints nothing) fails.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}


OSSL="$SRC/Library/OpensslLib/openssl"
B="$SRC/mayhem/build/normal"
R="$OSSL/test/recipes"
export OPENSSL_MODULES="$B/providers" OPENSSL_CONF=/dev/null
CB="$SRC/mayhem/build/clover"
CO="$SRC/mayhem/clover_oracle"
for f in "$B/apps/openssl" "$B/test/bntest" "$B/test/evp_test" "$CB/clover-config-validator" "$CB/clover-plist-dump"; do
  [ -x "$f" ] || { echo "missing $f — mayhem/build.sh did not build it" >&2; exit 2; }
done

passed=0; failed=0

# run_tap <name> <program> [args...]: counts top-level TAP result lines; no results or a non-zero exit is a failure.
run_tap() {
  local name="$1"; shift
  local out rc ok nok
  out="$("$@" 2>&1)"; rc=$?
  ok=$(printf '%s\n' "$out" | grep -c '^ok ' || true)
  nok=$(printf '%s\n' "$out" | grep -c '^not ok ' || true)
  passed=$((passed + ok)); failed=$((failed + nok))
  if [ "$rc" -ne 0 ] || [ "$ok" -eq 0 ]; then
    [ "$nok" -gt 0 ] || failed=$((failed + 1))
    echo "FAIL $name (rc=$rc ok=$ok not_ok=$nok)"; printf '%s\n' "$out" | tail -n 15
  else
    echo "PASS $name ($ok)"
  fi
}

# check_eq <name> <expected> <actual>: one asserted known-answer value.
check_eq() {
  if [ "$2" = "$3" ]; then passed=$((passed + 1)); echo "PASS $1"
  else failed=$((failed + 1)); echo "FAIL $1: expected '$2' got '$3'"; fi
}

for t in asn1_internal_test asn1_time_test asn1_string_table_test asn1_decode_test asn1_encode_test \
         x509_time_test x509_internal_test bn_internal_test exptest stack_test sanitytest hmactest bntest; do
  run_tap "$t" "$B/test/$t"
done
for f in bnexp bngcd bnmod bnmul bnshift bnsum; do
  run_tap "bntest $f" "$B/test/bntest" "$R/10-test_bn_data/$f.txt"
done
run_tap "pemtest" "$B/test/pemtest" "$OSSL/test/certs/cert-key-cert.pem"
for f in evpmd_sha evpmd_md evpmd_ripemd evpmac_common evpkdf_hkdf evpkdf_pbkdf2 evpciph_aes_common evpciph_aes_cts \
         evpencod evppkey_rsa evppkey_ecc evppkey_ecdsa evppkey_dsa; do
  run_tap "evp_test $f" "$B/test/evp_test" "$R/30-test_evp_data/$f.txt"
done

# Known-answer checks through the openssl command line (FIPS 180-2 / RFC 4231 / small-prime vectors).
O="$B/apps/openssl"
check_eq "sha256(abc)" "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" \
  "$(printf abc | "$O" dgst -sha256 -r 2>/dev/null | cut -d' ' -f1)"
check_eq "sha1(abc)" "a9993e364706816aba3e25717850c26c9cd0d89d" \
  "$(printf abc | "$O" dgst -sha1 -r 2>/dev/null | cut -d' ' -f1)"
check_eq "hmac-sha256(Jefe)" "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843" \
  "$(printf 'what do ya want for nothing?' | "$O" dgst -sha256 -hmac Jefe -r 2>/dev/null | cut -d' ' -f1)"
check_eq "prime(97)" "61 (97) is prime" "$("$O" prime 97 2>/dev/null)"
check_eq "prime(91)" "5B (91) is not prime" "$("$O" prime 91 2>/dev/null)"
check_eq "asn1parse(INTEGER 5)" "    0:d=0  hl=2 l=   1 prim: INTEGER           :05" \
  "$(printf '\x02\x01\x05' | "$O" asn1parse -inform DER 2>/dev/null)"
cert_subject="$("$O" x509 -in "$OSSL/test/certs/ca-cert.pem" -noout -subject 2>/dev/null)"
check_eq "x509 subject" "subject=CN = CA" "$cert_subject"

# ---- Clover's own code: ParseXML (plist reader) -------------------------------------------------------------
PD="$CB/clover-plist-dump"
check_eq "ParseXML dump.plist: parsed tags" "status=0 dict=yes
keys=6
Name|String8|Clover
Count|Int64|42
Enabled|Bool|true
Disabled|Bool|false
List|Array|3 items
Nested|Dict|2 keys" "$("$PD" "$CO/dump.plist" 2>&1)"
check_eq "ParseXML config-sample.plist: key count" "keys=10" \
  "$("$PD" "$SRC/CloverPackage/CloverV2/EFI/CLOVER/config-sample.plist" 2>&1 | grep '^keys=')"
check_eq "ParseXML config-sample.plist: ACPI tag" "ACPI|Dict|15 keys" \
  "$("$PD" "$SRC/CloverPackage/CloverV2/EFI/CLOVER/config-sample.plist" 2>&1 | grep '^ACPI|')"
check_eq "ParseXML config-sample.plist: Quirks tag" "Quirks|Dict|28 keys" \
  "$("$PD" "$SRC/CloverPackage/CloverV2/EFI/CLOVER/config-sample.plist" 2>&1 | grep '^Quirks|')"
check_eq "ParseXML config-test2.plist: SMBIOS tag" "SMBIOS|Dict|23 keys" \
  "$("$PD" "$SRC/Xcode/CloverConfigPlistValidator/config-test2.plist" 2>&1 | grep '^SMBIOS|')"
trunc="$(mktemp)"; printf '<dict><key>' > "$trunc"
check_eq "ParseXML rejects a truncated plist" "status=3 dict=no" "$("$PD" "$trunc" 2>&1)"
rm -f "$trunc"

# ---- Clover's own code: ConfigPlistClass::parse (config.plist validator) -----------------------------------------
CV="$CB/clover-config-validator"
out="$("$CV" "$CO/config-good.plist" 2>&1)"; rc=$?
check_eq "ConfigPlistClass::parse good config: no parser message" "Your plist looks so wonderful. Well done!" "$out"
check_eq "ConfigPlistClass::parse good config: exit status" "0" "$rc"
out="$("$CV" "$CO/config-bad.plist" 2>&1)"; rc=$?
check_eq "ConfigPlistClass::parse bad config: messages" "Warning: Boolean value contained in a string. Please use <true/> instead of <string>yes</string> for tag '/Boot/Fast:7'
Warning: Unknown key '/Boot/NoSuchBootKey:9'. Skipped." "$out"
check_eq "ConfigPlistClass::parse bad config: exit status" "1" "$rc"
out="$("$CV" "$SRC/Xcode/CloverConfigPlistValidator/config-test1.plist" 2>&1)"; rc=$?
check_eq "ConfigPlistClass::parse config-test1.plist: message count" "14" "$(printf '%s\n' "$out" | wc -l)"
check_eq "ConfigPlistClass::parse config-test1.plist: error text" "Error: Expecting an integer starting with a decimal digit, a minus sign or '0x' for tag '/Quirks/MmioWhitelist[2]/Address:1669'." \
  "$(printf '%s\n' "$out" | grep '^Error:')"
check_eq "ConfigPlistClass::parse config-test1.plist: unknown key" "Warning: Unknown key '/Quirks/ProvideConsoleGopEnable:1681'. Skipped." \
  "$(printf '%s\n' "$out" | grep 'Unknown key')"
check_eq "ConfigPlistClass::parse config-test1.plist: exit status" "1" "$rc"
out="$("$CV" "$SRC/Xcode/CloverConfigPlistValidator/config-test2.plist" 2>&1)"
check_eq "ConfigPlistClass::parse config-test2.plist: messages" "Warning: BiosVersion 'IM191.88Z.F000.B00.0004232100' is before than default ('IM191.88Z.F000.B00.2302212211') -> ignored. Dict '/SMBIOS:4'.
Warning: BiosReleaseDate '04/26/2020' is older than default ('02/21/2023') -> ignored. Dict '/SMBIOS:4'.
Warning: EfiVersion '1037.120.79.0.0' is older than default ('1968.100.16.0.1') -> ignored. Dict '/SMBIOS:4'." "$out"

emit_ctrf "clover-plist-and-openssl" "$passed" "$failed" 0
