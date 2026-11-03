// Functional-oracle driver (normal flags, no sanitizer) for Clover's generic plist reader ParseXML():
// parses the file given as argv[1] and prints one line per top-level key, "<key>|<Type>|<value>", plus the
// status and key count. mayhem/test.sh asserts these lines against known plists.
#include <Platform.h>
#include "../../rEFIt_UEFI/Platform/plist/plist.h"

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char** argv)
{
  if ( argc != 2 ) { fprintf(stderr, "usage: plist_dump file.plist\n"); return 2; }
  FILE* f = fopen(argv[1], "rb");
  if ( f == NULL ) { fprintf(stderr, "cannot open %s\n", argv[1]); return 2; }
  fseek(f, 0, SEEK_END);
  long size = ftell(f);
  fseek(f, 0, SEEK_SET);
  UINT8* buf = (UINT8*)malloc(size + 1);
  if ( buf == NULL || fread(buf, 1, size, f) != (size_t)size ) { fprintf(stderr, "cannot read %s\n", argv[1]); return 2; }
  fclose(f);

  TagDict* dict = NULL;
  EFI_STATUS status = ParseXML(buf, &dict, size);
  printf("status=%d dict=%s\n", (int)status, dict != NULL ? "yes" : "no");
  if ( dict == NULL ) return 1;
  printf("keys=%d\n", (int)dict->dictKeyCount());
  for ( INTN i = 0 ; i < dict->dictKeyCount() ; i++ ) {
    const TagKey* key = NULL;
    const TagStruct* value = NULL;
    if ( dict->getKeyAndValueAtIndex(i, &key, &value) != EFI_SUCCESS ) { printf("error at %d\n", (int)i); return 1; }
    printf("%s|%s|", key->keyStringValue().c_str(), value->getTypeAsXString8().c_str());
    if ( value->isString() ) printf("%s", value->getString()->stringValue().c_str());
    else if ( value->isInt64() ) printf("%lld", (long long)value->getInt64()->intValue());
    else if ( value->isBool() ) printf("%s", value->getBool()->boolValue() ? "true" : "false");
    else if ( value->isDict() ) printf("%d keys", (int)value->getDict()->dictKeyCount());
    else if ( value->isArray() ) printf("%d items", (int)value->getArray()->arrayContent().size());
    printf("\n");
  }
  dict->ReleaseTag();
  return 0;
}
