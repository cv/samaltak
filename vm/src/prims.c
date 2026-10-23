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
