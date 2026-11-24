#ifndef SAMALTAK_UEFI_STDIO_H
#define SAMALTAK_UEFI_STDIO_H
#include <stddef.h>
#include <stdarg.h>
typedef struct samaltak_uefi_file FILE;
int snprintf(char *s, size_t n, const char *format, ...) __attribute__((format(printf, 3, 4)));
int vsnprintf(char *s, size_t n, const char *format, va_list args) __attribute__((format(printf, 3, 0)));
#endif
