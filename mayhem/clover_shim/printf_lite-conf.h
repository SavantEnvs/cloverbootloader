// printf_lite.c does not compile on Linux with the stock PosixCompilation configuration:
//  - the timestamp prefix needs getUptimeInMilliseconds() (macOS only): switched off;
//  - vwprintf_with_callback() stores printfParams.emitCr unconditionally, but the member only exists under a bare
//    '#if PRINTF_EMIT_CR_SUPPORT' (not '== 1'): value 2 declares the member without enabling the (broken) '== 1' paths.
#include_next <printf_lite-conf.h>
#undef PRINTF_LITE_TIMESTAMP_SUPPORT
#define PRINTF_LITE_TIMESTAMP_SUPPORT 0
#undef PRINTF_EMIT_CR_SUPPORT
#define PRINTF_EMIT_CR_SUPPORT 2
