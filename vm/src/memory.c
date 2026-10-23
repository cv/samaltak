/* Object memory: tagging, allocation, object access, strings, integers. */
#include "core.h"
#include <stdlib.h>
#include <string.h>

oop nil_oop, true_oop, false_oop, specials_oop;
oop cls_smallint, cls_char, cls_smallfloat, cls_boxedfloat, cls_array, cls_context, cls_block, cls_point,
    cls_bytestring, cls_bytearray, cls_message;
uint64_t hash_seed = 0x5A4D414C54414Bull;
oop *root_stack[MAX_ROOTS];
int root_count;

#define LARGE_OBJECT_BYTES (256 * 1024)

void refresh_specials(void)
{
    oop *s = slots(specials_oop);
    nil_oop = s[SO_NIL];
    false_oop = s[SO_FALSE];
    true_oop = s[SO_TRUE];
    cls_smallint = s[SO_SMALLINTEGER];
    cls_char = s[SO_CHARACTER];
    cls_smallfloat = s[SO_SMALLFLOAT];
    cls_boxedfloat = s[SO_BOXEDFLOAT];
    cls_array = s[SO_ARRAY];
    cls_context = s[SO_CONTEXT];
    cls_block = s[SO_BLOCKCLOSURE];
    cls_point = s[SO_POINT];
    cls_bytestring = s[SO_BYTESTRING];
    cls_bytearray = s[SO_BYTEARRAY];
    cls_message = s[SO_MESSAGE];
}

oop special(int index)
{
    if (index < 0 || (uint32_t)index >= num_slots(specials_oop)) return nil_oop;
    return load_ref(specials_oop, (uint32_t)index);
}

void push_root(oop *p)
{
    if (root_count >= MAX_ROOTS) fatal("root stack overflow");
    root_stack[root_count++] = p;
}

void pop_root(void) { root_count--; }

/* ---- floats ---- */

static inline uint64_t rotl1(uint64_t x) { return (x << 1) | (x >> 63); }
static inline uint64_t rotr1(uint64_t x) { return (x >> 1) | (x << 63); }

bool is_float(oop o) { return (o & 7) == 4 || (is_ptr(o) && raw_class(o) == cls_boxedfloat); }

double float_val(oop o)
{
    uint64_t b;
    double d;
    if ((o & 7) == 4) {
        uint64_t r = o >> 3;
        b = r <= 1 ? r << 63 : rotr1(r + (896ull << 53));
    } else {
        b = slots(o)[0];
    }
    memcpy(&d, &b, 8);
    return d;
}

oop float_oop(double d)
{
    uint64_t b;
    memcpy(&b, &d, 8);
    if ((b << 1) == 0) return ((b >> 63) << 3) | 4;
    unsigned e = (unsigned)(b >> 52) & 0x7FF;
    if (e > 896 && e < 1151) return ((rotl1(b) - (896ull << 53)) << 3) | 4;
    oop f = alloc_obj(cls_boxedfloat, F_W64, 1);
    slots(f)[0] = b;
    return f;
}

/* ---- object access ---- */

oop class_of(oop o)
{
    if (o & 1) return cls_smallint;
    switch (o & 7) {
    case 0: return raw_class(o);
    case 2: return cls_char;
    case 4: return cls_smallfloat;
    default: return nil_oop;
    }
}

uint8_t *bytes_of(oop o) { return (uint8_t *)(o + 16); }
uint32_t *words32_of(oop o) { return (uint32_t *)(o + 16); }

size_t byte_size(oop o)
{
    int f = format_of(o);
    if (f >= F_BYTES) return (size_t)num_slots(o) * 8 - (size_t)(f - F_BYTES);
    if (f >= F_W32 && f < F_BYTES) return word32_size(o) * 4;
    return (size_t)num_slots(o) * 8;
}

size_t word32_size(oop o)
{
    int f = format_of(o);
    if (f == 10 || f == 11) return (size_t)num_slots(o) * 2 - (size_t)(f - F_W32);
    return 0;
}

uint32_t fixed_fields(oop o)
{
    int f = format_of(o);
    if (f == F_FIXED) return num_slots(o);
    if (f == F_FIXVAR || f == F_WEAK) return (uint32_t)(int_val(load_ref(raw_class(o), BEH_FORMAT)) & CLS_INSTSIZE_MASK);
    return 0;
}

size_t indexable_size(oop o)
{
    if (!is_ptr(o)) return 0;
    int f = format_of(o);
    switch (f) {
    case F_VAR: return num_slots(o);
    case F_FIXVAR:
    case F_WEAK: return num_slots(o) - fixed_fields(o);
    case F_W64: return num_slots(o);
    case 10:
    case 11: return word32_size(o);
    default: return f >= F_BYTES ? byte_size(o) : 0;
    }
}

/* ---- allocation ---- */

uint32_t next_hash(void)
{
    hash_seed = hash_seed * 6364136223846793005ull + 1442695040888963407ull;
    uint32_t h = (uint32_t)(hash_seed >> 40) & H_HASH_MASK;
    return h ? h : 1;
}

static inline void init_object(char *p, oop cls, int fmt, uint32_t n)
{
    uint64_t *w = (uint64_t *)p;
    w[0] = (uint64_t)n | ((uint64_t)fmt << H_FMT_SHIFT) | ((uint64_t)next_hash() << H_HASH_SHIFT);
    w[1] = cls;
    if (fmt_has_pointers(fmt)) {
        oop *s = (oop *)(p + 16), nl = nil_oop;
        for (uint32_t i = 0; i < n; i++) s[i] = nl;
    } else {
        memset(p + 16, 0, (size_t)n * 8);
    }
}

/* Slow path: account allocation sampling, collect if eden is full. */
static char *sample_mark;

static bool old_over_budget(void) { return (size_t)(old_top - old_lo) > old_budget; }

/* Fast-path limit: eden's end or the next allocation sample; eden_top while old space is over its budget (after the
 * scavenge primitive), so that the next allocation collects. */
void reset_alloc_limit(void)
{
    alloc_limit = eden_hi;
    sample_mark = eden_top;
    if (alloc_sample_interval > 0 && eden_top + alloc_sample_countdown < alloc_limit)
        alloc_limit = eden_top + alloc_sample_countdown;
    if (old_over_budget()) alloc_limit = eden_top;
}

static char *alloc_slow(oop *cls, size_t bytes)
{
    if (alloc_sample_interval > 0) {
        alloc_sample_countdown -= eden_top - sample_mark;
        sample_mark = eden_top;
        if (alloc_sample_countdown <= (int64_t)bytes) {
            alloc_sample_countdown = alloc_sample_interval + (int64_t)bytes;
            alloc_sample_hit(*cls, bytes);
        }
    }
    if (eden_top + bytes > eden_hi || old_over_budget()) {
        push_root(cls);
        collect_garbage(bytes);
        pop_root();
    }
    char *p = eden_top;
    eden_top += bytes;
    if (alloc_sample_interval > 0) alloc_sample_countdown -= (int64_t)bytes;
    reset_alloc_limit();
    return p;
}

static oop alloc_old_try(oop cls, int fmt, uint32_t n)
{
    push_root(&cls);
    char *p = old_alloc_try(16 + 8 * (size_t)n);
    pop_root();
    if (!p) return 0;
    init_object(p, cls, fmt, n);
    stat_allocated += 16 + 8 * (size_t)n;
    if (is_ptr(cls) && vm_is_young(cls)) vm_remember((oop)p);
    return (oop)p;
}

oop alloc_old(oop cls, int fmt, uint32_t n)
{
    oop o = alloc_old_try(cls, fmt, n);
    if (!o) fatal("out of memory allocating %zu bytes", 16 + 8 * (size_t)n);
    return o;
}

oop alloc_obj(oop cls, int fmt, uint32_t n)
{
    size_t bytes = 16 + 8 * (size_t)n;
    if (bytes > LARGE_OBJECT_BYTES) {
        if (alloc_sample_interval > 0) alloc_sample_hit(cls, bytes);
        return alloc_old(cls, fmt, n);
    }
    char *p = eden_top;
    if (p + bytes > alloc_limit) {
        p = alloc_slow(&cls, bytes);
    } else {
        eden_top = p + bytes;
    }
    init_object(p, cls, fmt, n);
    return (oop)p;
}

oop alloc_obj_try(oop cls, int fmt, size_t n)
{
    if (n > UINT32_MAX) return 0;
    size_t bytes = 16 + 8 * n;
    if (bytes <= LARGE_OBJECT_BYTES) return alloc_obj(cls, fmt, (uint32_t)n);
    if (alloc_sample_interval > 0) alloc_sample_hit(cls, bytes);
    return alloc_old_try(cls, fmt, (uint32_t)n);
}

oop alloc_context(uint32_t n)
{
    return alloc_obj(cls_context, F_FIXVAR, CTX_FIXED + n);
}

oop alloc_slots(oop cls, uint32_t n)
{
    int err;
    oop o = instantiate(cls, n, &err);
    return err ? nil_oop : o;
}

oop alloc_bytes(oop cls, size_t n)
{
    return alloc_obj(cls, F_BYTES + (int)((8 - n % 8) % 8), (uint32_t)((n + 7) / 8));
}

oop alloc_words32(oop cls, size_t n)
{
    return alloc_obj(cls, F_W32 + (int)(n & 1), (uint32_t)((n + 1) / 2));
}

oop instantiate(oop cls, size_t n, int *err)
{
    *err = -1;
    if (!is_ptr(cls) || num_slots(cls) <= BEH_FORMAT) return nil_oop;
    oop fo = load_ref(cls, BEH_FORMAT);
    if (!is_int(fo)) return nil_oop;
    int64_t spec = int_val(fo) >> CLS_SPEC_SHIFT, isize = int_val(fo) & CLS_INSTSIZE_MASK;
    int fmt;
    size_t nslots;
    switch (spec) {
    case 0:
    case 1:
        if (n) return nil_oop;
        fmt = isize ? F_FIXED : F_EMPTY, nslots = (size_t)isize;
        break;
    case 2:
    case 3:
    case 4: fmt = isize && spec == 2 ? F_FIXVAR : (int)spec, nslots = (size_t)isize + n; break;
    case 9: fmt = F_W64, nslots = n; break;
    case 10: fmt = F_W32 + (int)(n & 1), nslots = n / 2 + (n & 1); break;
    case 16: fmt = F_BYTES + (int)((8 - n % 8) % 8), nslots = n / 8 + (n % 8 != 0); break;
    default: return nil_oop;
    }
    oop o = n > 0x7FFFFFF0 ? 0 : alloc_obj_try(cls, fmt, nslots);
    *err = o ? 0 : PRIM_ERR_NO_MEMORY;
    return o ? o : nil_oop;
}

/* ---- integers ---- */

oop large_int_from_u64(uint64_t v, bool negative)
{
    int n = 0;
    for (uint64_t t = v; t; t >>= 8) n++;
    if (!n) n = 1;
    oop o = alloc_bytes(special(negative ? SO_LARGENEG : SO_LARGEPOS), (size_t)n);
    for (int i = 0; i < n; i++) bytes_of(o)[i] = (uint8_t)(v >> (8 * i));
    return o;
}

oop int64_oop(int64_t v)
{
    if (int_fits(v)) return int_oop(v);
    return v < 0 ? large_int_from_u64((uint64_t)0 - (uint64_t)v, true) : large_int_from_u64((uint64_t)v, false);
}

static bool large_magnitude(oop o, uint64_t *mag, bool *neg)
{
    if (!is_ptr(o) || format_of(o) < F_BYTES) return false;
    oop c = raw_class(o);
    if (c == special(SO_LARGEPOS)) *neg = false;
    else if (c == special(SO_LARGENEG)) *neg = true;
    else return false;
    size_t n = byte_size(o);
    uint8_t *b = bytes_of(o);
    while (n > 0 && b[n - 1] == 0) n--;
    if (n > 8) return false;
    uint64_t m = 0;
    for (size_t i = 0; i < n; i++) m |= (uint64_t)b[i] << (8 * i);
    *mag = m;
    return true;
}

bool u64_of(oop o, uint64_t *out)
{
    if (is_int(o)) {
        if (int_val(o) < 0) return false;
        *out = (uint64_t)int_val(o);
        return true;
    }
    bool neg;
    return large_magnitude(o, out, &neg) && !neg;
}

bool int64_of(oop o, int64_t *out)
{
    if (is_int(o)) {
        *out = int_val(o);
        return true;
    }
    uint64_t m;
    bool neg;
    if (!large_magnitude(o, &m, &neg)) return false;
    if (!neg && m > (uint64_t)INT64_MAX) return false;
    if (neg && m > (uint64_t)INT64_MAX + 1) return false;
    *out = neg ? (int64_t)(0 - m) : (int64_t)m;
    return true;
}

/* ---- strings ---- */

bool is_kind_of_string(oop o)
{
    if (!is_ptr(o)) return false;
    oop c = raw_class(o);
    return c == cls_bytestring || c == special(SO_BYTESYMBOL) || c == special(SO_WIDESTRING) ||
           c == special(SO_WIDESYMBOL);
}

size_t string_size(oop s)
{
    int f = format_of(s);
    if (f >= F_BYTES) return byte_size(s);
    if (f == 10 || f == 11) return word32_size(s);
    return 0;
}

uint32_t string_char_at(oop s, size_t i)
{
    return format_of(s) >= F_BYTES ? bytes_of(s)[i] : words32_of(s)[i];
}

uint32_t string_hash(oop s)
{
    uint32_t h = 2166136261u;
    size_t n = string_size(s);
    for (size_t i = 0; i < n; i++) h = (h ^ string_char_at(s, i)) * 16777619u;
    return h & 0x3FFFFFFF;
}

static size_t utf8_decode(const unsigned char *s, size_t n, size_t *i)
{
    unsigned c = s[*i];
    int len = c < 0x80 ? 1 : (c >> 5) == 6 ? 2 : (c >> 4) == 14 ? 3 : (c >> 3) == 30 ? 4 : 0;
    if (len <= 1 || *i + (size_t)len > n) {
        (*i)++;
        return c;
    }
    uint32_t cp = c & (0x7F >> len);
    for (int k = 1; k < len; k++) {
        unsigned d = s[*i + (size_t)k];
        if ((d & 0xC0) != 0x80) {
            (*i)++;
            return c;
        }
        cp = (cp << 6) | (d & 0x3F);
    }
    *i += (size_t)len;
    return cp;
}

oop string_from_utf8(const char *str, size_t n)
{
    const unsigned char *s = (const unsigned char *)str;
    size_t count = 0, i = 0;
    uint32_t max = 0;
    while (i < n) {
        uint32_t cp = (uint32_t)utf8_decode(s, n, &i);
        if (cp > max) max = cp;
        count++;
    }
    if (max < 256) {
        oop r = alloc_bytes(cls_bytestring, count);
        uint8_t *b = bytes_of(r);
        for (i = 0; i < n;) *b++ = (uint8_t)utf8_decode(s, n, &i);
        return r;
    }
    oop r = alloc_words32(special(SO_WIDESTRING), count);
    uint32_t *w = words32_of(r);
    for (i = 0; i < n;) *w++ = (uint32_t)utf8_decode(s, n, &i);
    return r;
}

char *utf8_of(oop s)
{
    if (!is_ptr(s)) return strdup("");
    if (raw_class(s) == cls_bytearray) {
        size_t n = byte_size(s);
        char *r = malloc(n + 1);
        if (!r) return NULL;
        memcpy(r, bytes_of(s), n);
        r[n] = 0;
        return r;
    }
    size_t n = string_size(s);
    char *r = malloc(n * 4 + 1), *p = r;
    if (!r) return NULL;
    for (size_t i = 0; i < n; i++) {
        uint32_t c = string_char_at(s, i);
        if (c < 0x80) *p++ = (char)c;
        else if (c < 0x800) *p++ = (char)(0xC0 | (c >> 6)), *p++ = (char)(0x80 | (c & 0x3F));
        else if (c < 0x10000)
            *p++ = (char)(0xE0 | (c >> 12)), *p++ = (char)(0x80 | ((c >> 6) & 0x3F)), *p++ = (char)(0x80 | (c & 0x3F));
        else
            *p++ = (char)(0xF0 | (c >> 18)), *p++ = (char)(0x80 | ((c >> 12) & 0x3F)),
            *p++ = (char)(0x80 | ((c >> 6) & 0x3F)), *p++ = (char)(0x80 | (c & 0x3F));
    }
    *p = 0;
    return r;
}

void memory_init(size_t eden_bytes, size_t max_heap)
{
    gc_init(eden_bytes, max_heap);
    reset_alloc_limit();
}
