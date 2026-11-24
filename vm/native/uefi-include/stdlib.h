#ifndef SAMALTAK_UEFI_STDLIB_H
#define SAMALTAK_UEFI_STDLIB_H
#include <stddef.h>
void *malloc(size_t n);
void *calloc(size_t n, size_t size);
void *realloc(void *p, size_t n);
/* UefiLibC's free */
void uefi_lib_c_free(void *p);
#define free uefi_lib_c_free
_Noreturn void abort(void);
#endif
