// Clover pairs every operator new/delete with AllocatePool/FreePool and releases pool memory with `delete`.
// Its own PlatformEFI/operatorNewDelete.cpp defines the sized delete with UINTN (unsigned long long), not the
// global `operator delete(void*, unsigned long)` that libstdc++/libFuzzer call, so ASan's would handle some
// frees and report alloc-dealloc-mismatch. These forward the remaining forms to AllocatePool/FreePool.
#include <Platform.h>

void operator delete(void* ptr, unsigned long) noexcept { FreePool(ptr); }
void operator delete[](void* ptr) noexcept { FreePool(ptr); }
void operator delete[](void* ptr, unsigned long) noexcept { FreePool(ptr); }

// libFuzzer's own containers use the nothrow forms; these keep them on the same allocator as the delete above.
#include <new>
void* operator new(unsigned long count, const std::nothrow_t&) noexcept { return AllocatePool(count); }
void* operator new[](unsigned long count, const std::nothrow_t&) noexcept { return AllocatePool(count); }
void operator delete(void* ptr, const std::nothrow_t&) noexcept { FreePool(ptr); }
void operator delete[](void* ptr, const std::nothrow_t&) noexcept { FreePool(ptr); }
