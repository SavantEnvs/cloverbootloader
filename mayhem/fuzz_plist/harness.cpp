// Fuzzes Clover's generic plist reader ParseXML() (rEFIt_UEFI/Platform/plist/plist.cpp), which Clover runs on
// theme.plist (libeg/XTheme.cpp), kext Info.plist (Platform/KextList.cpp) and the macOS loader plists
// (entry_scan/loader.cpp).
#include <Platform.h>
#include "../../rEFIt_UEFI/Platform/plist/plist.h"

#include <stdint.h>
#include <stdlib.h>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
  if ( size == 0 ) return 0;
  TagDict* dict = NULL;
  ParseXML(data, &dict, size);
  if ( dict != NULL ) dict->ReleaseTag();
  return 0;
}
