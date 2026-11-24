/* What vendored C (mbedTLS) needs on UEFI beyond VM-UEFI's UefiLibC: string search, snprintf, time (the image's, as the
   TLS engine was told it), 128-bit division. Compiled for UEFI only (vm/uefi.mk). */
#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include "tls.h"

int strncmp(const char *a, const char *b, size_t n)
{
    for (; n > 0; a++, b++, n--) {
        if (*a != *b) return (unsigned char)*a - (unsigned char)*b;
        if (*a == 0) return 0;
    }
    return 0;
}
char *strchr(const char *s, int c)
{
    for (;; s++) {
        if (*s == (char)c) return (char *)s;
        if (*s == 0) return NULL;
    }
}
char *strrchr(const char *s, int c)
{
    const char *found = NULL;
    for (;; s++) {
        if (*s == (char)c) found = s;
        if (*s == 0) return (char *)found;
    }
}
char *strstr(const char *s, const char *t)
{
    size_t n = strlen(t);
    if (n == 0) return (char *)s;
    for (; *s; s++) if (*s == *t && strncmp(s, t, n) == 0) return (char *)s;
    return NULL;
}

time_t time(time_t *t)
{
    time_t s = (time_t)samaltak_tls_now();
    if (t) *t = s;
    return s;
}

unsigned __int128 __udivti3(unsigned __int128 n, unsigned __int128 d)
{
    unsigned __int128 q = 0, r = 0;
    if (d == 0) return 0;
    for (int i = 127; i >= 0; i--) {
        r = (r << 1) | ((n >> i) & 1);
        if (r >= d) { r -= d; q |= (unsigned __int128)1 << i; }
    }
    return q;
}

/* vsnprintf: d i u x X o c s p and %%, flags - 0 + space #, width and precision (also *), length hh h l ll z j t.
   Enough for mbedTLS's messages (certificate names and serials, error texts). */
typedef struct { char *s; size_t n, at; } out_t;
static void emit(out_t *o, char c) { if (o->at + 1 < o->n) o->s[o->at] = c; o->at++; }
static void pad(out_t *o, char c, int k) { while (k-- > 0) emit(o, c); }
int vsnprintf(char *s, size_t n, const char *f, va_list ap)
{
    out_t o = { s, n, 0 };
    for (; *f; f++) {
        if (*f != '%') { emit(&o, *f); continue; }
        int left = 0, zero = 0, plus = 0, space = 0, alt = 0, width = 0, prec = -1, len = 0;
        for (;; f++) {
            if (f[1] == '-') left = 1; else if (f[1] == '0') zero = 1; else if (f[1] == '+') plus = 1;
            else if (f[1] == ' ') space = 1; else if (f[1] == '#') alt = 1; else break;
        }
        f++;
        if (*f == '*') { width = va_arg(ap, int); if (width < 0) { left = 1; width = -width; } f++; }
        else while (*f >= '0' && *f <= '9') width = width * 10 + (*f++ - '0');
        if (*f == '.') {
            f++; prec = 0;
            if (*f == '*') { prec = va_arg(ap, int); f++; }
            else while (*f >= '0' && *f <= '9') prec = prec * 10 + (*f++ - '0');
        }
        for (;; f++) {
            if (*f == 'h') len = len == -1 ? -2 : -1;
            else if (*f == 'l') len++;
            else if (*f == 'z' || *f == 'j' || *f == 't') len = 2;
            else break;
        }
        char c = *f, digits[24], *text;
        int k = 0, neg = 0, base = 10, tl;
        uint64_t v = 0;
        const char *prefix = "";
        switch (c) {
        case 0: f--; continue;
        case '%': emit(&o, '%'); continue;
        case 'c': digits[0] = (char)va_arg(ap, int); text = digits; tl = 1; prec = -1; zero = 0; goto out;
        case 's':
            text = va_arg(ap, char *);
            if (!text) text = "(null)";
            for (tl = 0; text[tl] && (prec < 0 || tl < prec); tl++) {}
            prec = -1; zero = 0;
            goto out;
        case 'p': v = (uint64_t)(uintptr_t)va_arg(ap, void *); base = 16; prefix = "0x"; break;
        case 'd': case 'i': {
            int64_t x = len >= 1 ? va_arg(ap, int64_t) : va_arg(ap, int);
            if (len == -1) x = (short)x; else if (len == -2) x = (signed char)x;
            if (x < 0) { neg = 1; v = (uint64_t)0 - (uint64_t)x; } else v = (uint64_t)x;
            prefix = neg ? "-" : plus ? "+" : space ? " " : "";
            break;
        }
        case 'u': case 'x': case 'X': case 'o':
            v = len >= 1 ? va_arg(ap, uint64_t) : va_arg(ap, unsigned);
            if (len == -1) v = (unsigned short)v; else if (len == -2) v = (unsigned char)v;
            base = c == 'o' ? 8 : c == 'u' ? 10 : 16;
            if (alt && v != 0) prefix = c == 'x' ? "0x" : c == 'X' ? "0X" : c == 'o' ? "0" : "";
            break;
        default: emit(&o, '%'); emit(&o, c); continue;
        }
        do { int d = (int)(v % (unsigned)base); digits[k++] = (char)(d < 10 ? '0' + d : (c == 'X' ? 'A' : 'a') + d - 10); v /= (unsigned)base; } while (v);
        if (prec == 0 && k == 1 && digits[0] == '0') k = 0;
        {
            int zeros = prec > k ? prec - k : 0, pl = (int)strlen(prefix), total = pl + zeros + k;
            if (prec >= 0) zero = 0;
            if (!left && !zero) pad(&o, ' ', width - total);
            for (const char *p = prefix; *p; p++) emit(&o, *p);
            if (!left && zero) pad(&o, '0', width - total);
            pad(&o, '0', zeros);
            while (k > 0) emit(&o, digits[--k]);
            if (left) pad(&o, ' ', width - total);
        }
        continue;
    out:
        if (!left) pad(&o, ' ', width - tl);
        for (int i = 0; i < tl; i++) emit(&o, text[i]);
        if (left) pad(&o, ' ', width - tl);
    }
    if (n > 0) s[o.at < n ? o.at : n - 1] = 0;
    return (int)o.at;
}
int snprintf(char *s, size_t n, const char *f, ...)
{
    va_list ap;
    va_start(ap, f);
    int r = vsnprintf(s, n, f, ap);
    va_end(ap);
    return r;
}
