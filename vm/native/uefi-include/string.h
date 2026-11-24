/* The C library mbedTLS needs on UEFI, which has none: VM-UEFI's UefiLibC and vm/native/uefi_libc.c. */
#ifndef SAMALTAK_UEFI_STRING_H
#define SAMALTAK_UEFI_STRING_H
#include <stddef.h>
void *memcpy(void *dst, const void *src, size_t n);
void *memmove(void *dst, const void *src, size_t n);
void *memset(void *p, int c, size_t n);
int memcmp(const void *a, const void *b, size_t n);
void *memchr(const void *p, int c, size_t n);
size_t strlen(const char *s);
int strcmp(const char *a, const char *b);
int strncmp(const char *a, const char *b, size_t n);
char *strchr(const char *s, int c);
char *strrchr(const char *s, int c);
char *strstr(const char *s, const char *t);
#endif
