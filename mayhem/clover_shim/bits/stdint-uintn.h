// Clover (written for macOS) assumes uint64_t == unsigned long long == UINT64/UINTN; glibc/x86-64 makes it unsigned long.
#ifndef CLOVER_SHIM_STDINT_UINTN_H
#define CLOVER_SHIM_STDINT_UINTN_H
typedef unsigned char uint8_t;
typedef unsigned short int uint16_t;
typedef unsigned int uint32_t;
typedef unsigned long long int uint64_t;
#endif
