// CloverConfigPlistValidator's main.cpp reaches two globals that Clover defines in Platform/Settings.cpp
// (rEFIt_UEFI/Platform/Settings.cpp:57 and :80), a file that is not part of this build.
#include <Platform.h>
#include "../../rEFIt_UEFI/Settings/ConfigPlist/ConfigPlistClass.h"

XStringWArray SmbiosList;
INTN OldChosenSmbios = 0;
