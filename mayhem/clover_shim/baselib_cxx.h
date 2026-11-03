// Force-included only when building Xcode/cpp_tests/src/BaseLib.c as C++ (it is built that way by Clover's
// Xcode project): StrLen() passes a wchar_t* to the char16_t* overload, which clang only treats as the
// same type in C.
#include <stddef.h>
#include "../../rEFIt_UEFI/cpp_foundation/unicode_conversions.h"
static inline size_t wchar_size_of_utf16_string(const wchar_t* s) { return wchar_size_of_utf16_string((const char16_t*)s); }
