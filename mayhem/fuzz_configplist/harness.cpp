// Fuzzes Clover's config.plist parser: the same XmlLiteParser + ConfigPlistClass::parse path that the
// shipped CloverConfigPlistValidator (Xcode/CloverConfigPlistValidator/src/main.cpp) runs on a user's file.
#include <Platform.h>
#include "../../rEFIt_UEFI/Settings/ConfigPlist/ConfigPlistClass.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
  char* buf = (char*)malloc(size + 1);
  if ( buf == NULL ) return 0;
  memcpy(buf, data, size);
  buf[size] = 0;

  {
    ConfigPlistClass configPlist;
    XmlLiteParser xmlLiteParser;
    xmlLiteParser.init(buf, size);
    configPlist.parse(&xmlLiteParser, LString8(""));
    for ( size_t idx = 0 ; idx < xmlLiteParser.getXmlParserMessageArray().size() ; idx++ ) {
      (void)xmlLiteParser.getXmlParserMessageArray()[idx].getFormattedMsg();
    }
  }

  free(buf);
  return 0;
}
