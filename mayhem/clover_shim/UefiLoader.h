// Include/UefiLoader.h typedefs the xnu '__uint64_t' (unsigned long long); glibc's is 'unsigned long'.
#define __uint64_t clover_posix_uint64_t
#include_next <UefiLoader.h>
#undef __uint64_t
