/* Time and system primitives. */
#include "core.h"
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

int vm_args_start;

static oop arg0(void) { return prim_argc() > 0 ? prim_arg(0) : nil_oop; }

void p_millisecond_clock(void) { prim_return(int_oop(now_ms())); }
void p_microsecond_clock(void) { prim_return(int_oop(now_us())); }

void p_utc_microseconds(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    prim_return(int_oop((int64_t)tv.tv_sec * 1000000 + tv.tv_usec));
}

void p_quit(void)
{
    oop c = arg0();
    fflush(stdout);
    fflush(stderr);
    platform_shutdown();
    exit(is_int(c) ? (int)int_val(c) : 0);
}

void p_snapshot(void)
{
    if (!is_kind_of_string(arg0())) return prim_fail();
    char *path = utf8_of(arg0());
    if (!path) return prim_fail_code(PRIM_ERR_NO_MEMORY);
    prim_commit(true_oop);
    materialize_all();
    store_ref(active_process(), PROC_SUSPENDED, active_ctx);
    bool ok = write_snapshot(path);
    free(path);
    store_ref(active_process(), PROC_SUSPENDED, nil_oop);
    slots(active_ctx)[CTX_FIXED + ctx_stackp(active_ctx) - 1] = ok ? false_oop : nil_oop;
}

void p_gc(void)
{
    full_gc();
    prim_return(int_oop((int64_t)(old_budget - (size_t)(old_top - old_lo))));
}

void p_scavenge(void)
{
    scavenge();
    prim_return(int_oop(eden_hi - eden_top));
}

void p_vm_stats(void)
{
    int64_t v[] = {(int64_t)stat_scavenges,     (int64_t)stat_full_gcs,          (int64_t)stat_scavenge_us,
                   (int64_t)stat_full_us,       (int64_t)(old_top - old_lo),     (int64_t)old_budget,
                   (int64_t)(eden_hi - eden_lo), (int64_t)(stat_allocated + (size_t)(eden_top - eden_lo)),
                   (int64_t)remset_count,       (int64_t)stat_process_switches, (int64_t)stat_tenured,
                   (int64_t)stat_weak_cleared, (int64_t)stat_materialized, (int64_t)stat_flushes};
    int n = (int)(sizeof v / sizeof v[0]);
    oop a = alloc_obj(cls_array, F_VAR, (uint32_t)n);
    for (int i = 0; i < n; i++) slots(a)[i] = int_oop(v[i]);
    prim_return(a);
}

void p_flush_method_cache(void)
{
    flush_method_cache();
    prim_return(prim_receiver());
}

void p_flush_cache_for_selector(void)
{
    flush_method_cache_selector(prim_argc() > 0 ? prim_arg(0) : prim_receiver());
    prim_return(prim_receiver());
}

static oop strings_array(char **v, int n)
{
    oop a = alloc_obj(cls_array, F_VAR, (uint32_t)n);
    push_root(&a);
    for (int i = 0; i < n; i++) {
        oop s = string_from_utf8(v[i], strlen(v[i]));
        store_ref(a, (uint32_t)i, s);
    }
    pop_root();
    return a;
}

void p_vm_arguments(void) { prim_return(strings_array(vm_argv + vm_args_start, vm_argc - vm_args_start)); }

void p_image_path(void)
{
    const char *p = image_path ? image_path : "";
    prim_return(string_from_utf8(p, strlen(p)));
}

static void write_to(FILE *f)
{
    oop s = prim_argc() > 0 ? prim_arg(0) : prim_receiver();
    if (!is_ptr(s) || !(is_kind_of_string(s) || raw_class(s) == cls_bytearray)) return prim_fail();
    char *u = utf8_of(s);
    if (!u) return prim_fail_code(PRIM_ERR_NO_MEMORY);
    fputs(u, f);
    fflush(f);
    free(u);
    prim_return(prim_receiver());
}

void p_stdout_write(void) { write_to(stdout); }
void p_stderr_write(void) { write_to(stderr); }
void p_special_objects_array(void) { prim_return(specials_oop); }
void p_primitive_names(void) { prim_return(primitive_names_array()); }

void p_getenv(void)
{
    if (!is_kind_of_string(arg0())) return prim_fail();
    char *k = utf8_of(arg0());
    if (!k) return prim_fail_code(PRIM_ERR_NO_MEMORY);
    const char *v = getenv(k);
    free(k);
    prim_return(v ? string_from_utf8(v, strlen(v)) : nil_oop);
}
