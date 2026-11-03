// Linux/glibc adaptations for building Clover's POSIX test configuration (rEFIt_UEFI/PlatformPOSIX/include/
// Platform.h, written for Xcode/macOS) with clang. Force-included before every source (-include Platform.h) and
// shadows that header via #include_next. The real sources are untouched.
#ifndef MAYHEM_CLOVER_SHIM_PLATFORM_H
#define MAYHEM_CLOVER_SHIM_PLATFORM_H

#include <stdint.h>
#include <inttypes.h>
#include <wchar.h>
#ifdef __cplusplus
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <string>
#include <vector>
#include <locale>
#include <codecvt>
#endif

// With -fshort-wchar libc's wide-string functions are wrong; Clover maps them to PosixCompilation/xcode_utf_fixed.cpp.
// (Defined only after the libc/libstdc++ headers above, which declare the real names.)
#define wcscmp __wcscmp_is_disabled__
#define wcslen wcslen_fixed
#define wcsncmp wcsncmp_fixed
#define wcsstr wcsstr_fixed

// The PosixCompilation Platform.h typedefs uintptr_t as 'unsigned long long'; glibc's is 'unsigned long'.
#define uintptr_t clover_posix_uintptr_t

// XStringAbstract.h calls these from a template before Efi.h includes MemoryAllocationLib.h; clang on Linux
// (unlike Apple's) needs them declared at that point. Same signatures as MemoryAllocationLib.h.
#ifdef __cplusplus
extern "C" {
void* AllocatePool(unsigned long long AllocationSize);
void* ReallocatePool(unsigned long long OldSize, unsigned long long NewSize, void* OldBuffer);
}
#endif

#include_next <Platform.h>

#undef uintptr_t
// ProcessorBind.h leaves '#pragma GCC visibility push(hidden)' open (UEFI): keep later libc redeclarations default-visibility.
#pragma GCC visibility push(default)
#endif
