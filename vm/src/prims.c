/* Primitive table built from prims.def and, when present, platform/prims_platform.def. */
#include "core.h"
#include <string.h>

#if !defined(SAMALTAK_NO_PLATFORM) && __has_include("../platform/prims_platform.def")
#define HAVE_PLATFORM_PRIMS 1
#endif

#define PRIM(n, name, fn) void fn(void);
#include "prims.def"
#ifdef HAVE_PLATFORM_PRIMS
#include "../platform/prims_platform.def"
#endif
#undef PRIM

static const struct {
    int n;
    const char *name;
    prim_fn fn;
} table[] = {
#define PRIM(n, name, fn) {n, name, fn},
#include "prims.def"
#ifdef HAVE_PLATFORM_PRIMS
#include "../platform/prims_platform.def"
#endif
#undef PRIM
};

#define NTABLE ((int)(sizeof table / sizeof table[0]))
#define MAX_PRIM 1024
static prim_fn by_number[MAX_PRIM];
static const char *names[MAX_PRIM];

static void init_table(void)
{
    static bool done;
    if (done) return;
    done = true;
    for (int i = 0; i < NTABLE; i++) {
        if (table[i].n <= 0 || table[i].n >= MAX_PRIM || by_number[table[i].n])
            fatal("bad or duplicate primitive number %d (%s)", table[i].n, table[i].name);
        by_number[table[i].n] = table[i].fn;
        names[table[i].n] = table[i].name;
    }
}

prim_fn prim_lookup(int64_t n)
{
    init_table();
    return n > 0 && n < MAX_PRIM ? by_number[n] : NULL;
}

const char *prim_name(int64_t n)
{
    init_table();
    return n > 0 && n < MAX_PRIM ? names[n] : NULL;
}

bool prim_tryable(prim_fn f)
{
    static const prim_fn no[] = {p_perform,          p_perform_with_arguments, p_closure_value,
                                 p_closure_value_with_arguments, p_process_resume, p_process_suspend,
                                 p_processor_yield,  p_semaphore_signal,       p_semaphore_wait,
                                 p_snapshot,         p_try_primitive,          p_quit};
    for (size_t i = 0; i < sizeof no / sizeof no[0]; i++)
        if (no[i] == f) return false;
    return true;
}

/* Leaf primitives never allocate, switch processes or inspect Contexts: the interpreter calls them without
   writing back its registers. */
void p_int_add(void), p_int_sub(void), p_int_less(void), p_int_greater(void), p_int_less_eq(void),
    p_int_greater_eq(void), p_int_eq(void), p_int_not_eq(void), p_int_mul(void), p_int_div(void), p_int_quo(void),
    p_int_rem(void), p_int_floor_div(void), p_int_mod(void), p_int_bit_and(void), p_int_bit_or(void),
    p_int_bit_xor(void), p_int_bit_shift(void), p_float_truncated(void), p_char_value(void), p_class(void),
    p_identical(void), p_identity_hash(void), p_basic_size(void), p_string_at(void), p_string_at_put(void),
    p_replace_from_to(void), p_bytes_uint16_at(void), p_bytes_int16_at(void), p_bytes_uint32_at(void),
    p_bytes_uint32_at_put(void), p_bytes_float32_at_put(void), p_bytes_float64_at_put(void),
    p_bytes_uint16_be_at(void), p_bytes_int16_be_at(void), p_bytes_uint32_be_at(void);

bool prim_is_leaf(prim_fn f)
{
    static const prim_fn leaf[] = {
        p_int_add, p_int_sub, p_int_less, p_int_greater, p_int_less_eq, p_int_greater_eq, p_int_eq, p_int_not_eq,
        p_int_mul, p_int_div, p_int_quo, p_int_rem, p_int_floor_div, p_int_mod, p_int_bit_and, p_int_bit_or,
        p_int_bit_xor, p_int_bit_shift, p_float_truncated, p_char_value, p_class, p_identical, p_identity_hash,
        p_basic_size, p_string_at, p_string_at_put, p_replace_from_to, p_bytes_uint16_at, p_bytes_int16_at,
        p_bytes_uint32_at, p_bytes_uint32_at_put, p_bytes_float32_at_put, p_bytes_float64_at_put,
        p_bytes_uint16_be_at, p_bytes_int16_be_at, p_bytes_uint32_be_at};
    for (size_t i = 0; i < sizeof leaf / sizeof leaf[0]; i++)
        if (leaf[i] == f) return true;
    return false;
}

/* Array: element n is the name of primitive n (nil for gaps) */
oop primitive_names_array(void)
{
    int max = 0;
    for (int i = 0; i < NTABLE; i++)
        if (table[i].n > max) max = table[i].n;
    oop a = alloc_obj(cls_array, F_VAR, (uint32_t)max);
    push_root(&a);
    for (int i = 0; i < NTABLE; i++) {
        oop s = string_from_utf8(table[i].name, strlen(table[i].name));
        store_ref(a, (uint32_t)table[i].n - 1, s);
    }
    pop_root();
    return a;
}
