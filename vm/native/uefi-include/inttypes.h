#ifndef SAMALTAK_UEFI_INTTYPES_H
#define SAMALTAK_UEFI_INTTYPES_H
#include <stdint.h>
/* LP64, as both UEFI targets */
#define PRId64 "ld"
#define PRIi64 "li"
#define PRIu64 "lu"
#define PRIx64 "lx"
#define PRIX64 "lX"
#define PRIuPTR "lu"
#define PRIdPTR "ld"
#define PRIxPTR "lx"
#define PRId32 "d"
#define PRIu32 "u"
#define PRIx32 "x"
#endif
