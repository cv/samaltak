/* Generational GC: eden + survivor scavenger with a remembered set, copying full GC
 * between two old-space reservations. */
#include "core.h"
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

char *vm_young_lo, *vm_young_hi;
char *eden_lo, *eden_hi, *eden_top, *alloc_limit;
char *surv_lo, *surv_top, *surv_hi;
static char *surv_other_lo, *surv_other_hi;
char *old_lo, *old_top, *old_hi;
static char *old_alt_lo, *old_alt_hi;
size_t old_budget, max_heap_bytes;
static size_t old_reserve;
uint64_t gc_epoch;
uint64_t stat_scavenges, stat_full_gcs, stat_scavenge_us, stat_full_us, stat_allocated, stat_tenured;

static oop *remset;
size_t remset_count;
static size_t remset_cap;

#define TENURE_AGE 2
#define MIN_BUDGET ((size_t)64 << 20)

static char *reserve(size_t n)
{
    void *p = mmap(NULL, n, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (p == MAP_FAILED) fatal("cannot reserve %zu bytes", n);
    return p;
}

static void discard(char *p, size_t n)
{
    n = (n + 16383) & ~(size_t)16383;
    if (n) mmap(p, n, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0);
}

void gc_init(size_t eden_bytes, size_t max_heap)
{
    size_t surv = eden_bytes / 4;
    size_t young = eden_bytes + 2 * surv;
    vm_young_lo = reserve(young);
    vm_young_hi = vm_young_lo + young;
    eden_lo = eden_top = vm_young_lo;
    eden_hi = alloc_limit = eden_lo + eden_bytes;
    surv_lo = surv_top = eden_hi;
    surv_hi = surv_lo + surv;
    surv_other_lo = surv_hi;
    surv_other_hi = surv_other_lo + surv;
    max_heap_bytes = max_heap;
    old_reserve = max_heap + young + (1 << 20);
    old_lo = old_top = reserve(old_reserve);
    old_hi = old_lo + old_reserve;
    old_alt_lo = reserve(old_reserve);
    old_alt_hi = old_alt_lo + old_reserve;
    old_budget = MIN_BUDGET;
}

void vm_remember(oop o)
{
    *hdr_ptr(o) |= H_REMEMBERED;
    if (remset_count == remset_cap) {
        remset_cap = remset_cap ? remset_cap * 2 : 4096;
        remset = realloc(remset, remset_cap * sizeof(oop));
        if (!remset) fatal("out of memory growing the remembered set to %zu entries", remset_cap);
    }
    remset[remset_count++] = o;
}

void remember_if_old(oop o)
{
    if (is_ptr(o) && !vm_is_young(o) && !(vm_hdr(o) & H_REMEMBERED)) vm_remember(o);
}

static void for_each_root(void (*fn)(oop *))
{
    fn(&specials_oop);
    fn(&active_ctx);
    fn(&last_preempted);
    fn(&alloc_sample_class);
    fn(&prim_result);
    fn(&resend_selector);
    for (int i = 0; i < 4; i++) fn(&vm_tmp_root[i]);
    for (int i = 0; i < root_count; i++) fn(root_stack[i]);
    interp_roots(fn);
}

/* ---- verification (SAMALTAK_VERIFY_GC=1) ---- */

static uint8_t *start_bits;
static char *vlo;

static void mark_starts(char *lo, char *hi)
{
    for (char *p = lo; p < hi; p += obj_bytes((oop)p)) {
        size_t k = (size_t)(p - vlo) / 8;
        start_bits[k / 8] |= (uint8_t)(1 << (k % 8));
    }
}

static bool valid_ref(oop v)
{
    if (!is_ptr(v)) return true;
    bool in_old = (char *)v >= old_lo && (char *)v < old_top, in_surv = (char *)v >= surv_lo && (char *)v < surv_top,
         in_eden = (char *)v >= eden_lo && (char *)v < eden_top;
    if (in_eden) return true; /* eden is only verified by walking it */
    if (!in_old && !in_surv) return false;
    size_t k = (size_t)((char *)v - vlo) / 8;
    return start_bits[k / 8] & (1 << (k % 8));
}

static void verify_space(char *lo, char *hi, bool old)
{
    for (char *p = lo; p < hi; p += obj_bytes((oop)p)) {
        oop o = (oop)p;
        if (vm_hdr(o) & H_FORWARDED) fatal("verify: forwarded object %p", (void *)o);
        if (!is_ptr(raw_class(o)) || !valid_ref(raw_class(o))) fatal("verify: bad class in %p", (void *)o);
        bool young = vm_is_young(raw_class(o));
        if (fmt_has_pointers(format_of(o)))
            for (uint32_t i = 0; i < num_slots(o); i++) {
                oop v = slots(o)[i];
                if (!valid_ref(v)) fatal("verify: bad slot %u in %p: %p", i, (void *)o, (void *)v);
                if (is_ptr(v) && vm_is_young(v)) young = true;
            }
        if (old && young && !(vm_hdr(o) & H_REMEMBERED)) fatal("verify: unremembered old object %p", (void *)o);
    }
}

static void verify_heap(void)
{
    char *lo = old_lo < vm_young_lo ? old_lo : vm_young_lo;
    char *hi = old_top > vm_young_hi ? old_top : vm_young_hi;
    vlo = lo;
    size_t n = (size_t)(hi - lo) / 64 + 1;
    start_bits = calloc(n, 1);
    if (!start_bits) fatal("verify: out of memory");
    mark_starts(old_lo, old_top);
    mark_starts(surv_lo, surv_top);
    verify_space(old_lo, old_top, true);
    verify_space(surv_lo, surv_top, false);
    if (!valid_ref(specials_oop) || !valid_ref(active_ctx)) fatal("verify: bad root");
    if (!interp_frames_valid(valid_ref)) fatal("verify: bad frame slot");
    free(start_bits);
}

static void after_gc(void)
{
    static int verify = -1;
    if (verify < 0) verify = getenv("SAMALTAK_VERIFY_GC") != NULL;
    if (verify) verify_heap();
    gc_epoch++;
    refresh_specials();
    flush_method_cache();
    interp_after_gc();
    reset_alloc_limit();
}

/* ---- scavenge ---- */

static char *to_lo, *to_top, *to_hi;

static oop scav_copy(oop o)
{
    uint64_t h = vm_hdr(o);
    if (h & H_FORWARDED) return ((oop *)o)[1];
    size_t bytes = obj_bytes(o);
    unsigned age = (unsigned)((h >> H_AGE_SHIFT) & 3) + 1;
    char *dst;
    if (age >= TENURE_AGE || to_top + bytes > to_hi) {
        dst = old_top;
        old_top += bytes;
        stat_tenured += bytes;
        memcpy(dst, (void *)o, bytes);
        *(uint64_t *)dst = h & ~H_GCBITS;
    } else {
        dst = to_top;
        to_top += bytes;
        memcpy(dst, (void *)o, bytes);
        *(uint64_t *)dst = (h & ~H_GCBITS) | ((uint64_t)age << H_AGE_SHIFT);
    }
    *hdr_ptr(o) = h | H_FORWARDED;
    ((oop *)o)[1] = (oop)dst;
    return (oop)dst;
}

static void scav_root(oop *p)
{
    oop v = *p;
    if (is_ptr(v) && vm_is_young(v)) *p = scav_copy(v);
}

/* ---- weak objects: indexable slots of format 4 are not traced; after tracing, slots whose
 * referents died are set to nil ---- */

static oop *weak_list;
static size_t weak_count, weak_cap;
bool finalization_pending;
uint64_t stat_weak_cleared;

static bool is_context(oop o)
{
    oop c = raw_class(o);
    return c == cls_context || ((vm_hdr(cls_context) & H_FORWARDED) && c == ((oop *)cls_context)[1]);
}

/* Number of leading slots the collector traces. A context's slots above stackp are stale and
 * are cleared (the interpreter writes back stackp before anything can allocate); a weak
 * object's indexable slots are left for clear_weak_slots. */
static uint32_t traced_slots(oop o)
{
    int f = format_of(o);
    if (!fmt_has_pointers(f)) return 0;
    if (f == F_FIXVAR && is_context(o)) {
        oop sp = slots(o)[CTX_STACKP];
        uint32_t n = num_slots(o);
        if (!is_int(sp) || int_val(sp) < 0 || int_val(sp) > n - CTX_FIXED) return n;
        uint32_t live = CTX_FIXED + (uint32_t)int_val(sp);
        for (uint32_t i = live; i < n; i++) slots(o)[i] = nil_oop;
        return live;
    }
    if (f != F_WEAK) return num_slots(o);
    if (weak_count == weak_cap) {
        weak_cap = weak_cap ? weak_cap * 2 : 256;
        weak_list = realloc(weak_list, weak_cap * sizeof(oop));
        if (!weak_list) fatal("out of memory growing the weak object list to %zu entries", weak_cap);
    }
    weak_list[weak_count++] = o;
    return fixed_fields(o);
}

static bool refers_to_young(oop o)
{
    if (vm_is_young(raw_class(o))) return true;
    for (uint32_t i = 0, n = num_slots(o); i < n; i++)
        if (is_ptr(slots(o)[i]) && vm_is_young(slots(o)[i])) return true;
    return false;
}

/* is_dead(v) answers whether v was not reached; *v is updated to its new address otherwise. */
static void clear_weak_slots(bool (*is_dead)(oop *v))
{
    oop nl = nil_oop;
    for (size_t k = 0; k < weak_count; k++) {
        oop w = weak_list[k];
        oop *s = slots(w);
        for (uint32_t i = fixed_fields(w), n = num_slots(w); i < n; i++) {
            if (!is_ptr(s[i]) || !s[i]) continue;
            if (is_dead(&s[i])) {
                s[i] = nl;
                stat_weak_cleared++;
                finalization_pending = true;
            }
        }
    }
    if (finalization_pending) request_interrupt_check();
}

static bool scav_dead(oop *v)
{
    if (!vm_is_young(*v) || ((char *)*v >= to_lo && (char *)*v < to_hi)) return false;
    if (!(vm_hdr(*v) & H_FORWARDED)) return true;
    *v = ((oop *)*v)[1];
    return false;
}

/* Copies young referents of o; answers whether o still refers to young objects (weak slots excluded). */
static bool scav_scan(oop o)
{
    bool young = false;
    oop *c = &((oop *)o)[1];
    if (vm_is_young(*c)) {
        *c = scav_copy(*c);
        young |= vm_is_young(*c);
    }
    oop *s = slots(o);
    for (uint32_t i = 0, n = traced_slots(o); i < n; i++) {
        oop v = s[i];
        if (is_ptr(v) && vm_is_young(v)) {
            v = s[i] = scav_copy(v);
            young |= vm_is_young(v);
        }
    }
    return young;
}

void scavenge(void)
{
    interp_before_gc();
    int64_t t0 = now_us();
    stat_scavenges++;
    stat_allocated += (size_t)(eden_top - eden_lo);
    to_lo = to_top = surv_other_lo;
    to_hi = surv_other_hi;
    char *tenure_scan = old_top;

    weak_count = 0;
    for_each_root(scav_root);

    size_t kept = 0;
    for (size_t i = 0; i < remset_count; i++) {
        oop o = remset[i];
        *hdr_ptr(o) &= ~H_REMEMBERED;
        if (scav_scan(o) && format_of(o) != F_WEAK) {
            *hdr_ptr(o) |= H_REMEMBERED;
            remset[kept++] = o;
        }
    }
    remset_count = kept;

    char *scan = to_lo;
    while (scan < to_top || tenure_scan < old_top) {
        while (scan < to_top) {
            scav_scan((oop)scan);
            scan += obj_bytes((oop)scan);
        }
        while (tenure_scan < old_top) {
            oop o = (oop)tenure_scan;
            if (scav_scan(o) && !(vm_hdr(o) & H_REMEMBERED)) vm_remember(o);
            tenure_scan += obj_bytes(o);
        }
    }
    clear_weak_slots(scav_dead);
    for (size_t k = 0; k < weak_count; k++) {
        oop w = weak_list[k];
        if (!vm_is_young(w) && !(vm_hdr(w) & H_REMEMBERED) && refers_to_young(w)) vm_remember(w);
    }

    surv_other_lo = surv_lo;
    surv_other_hi = surv_hi;
    surv_lo = to_lo;
    surv_top = to_top;
    surv_hi = to_hi;
    eden_top = eden_lo;
    remember_if_old(active_ctx);
    after_gc();
    stat_scavenge_us += (uint64_t)(now_us() - t0);
}

/* ---- full GC ---- */

static char *ft_top;

static oop full_copy(oop o)
{
    uint64_t h = vm_hdr(o);
    if (h & H_FORWARDED) return ((oop *)o)[1];
    size_t bytes = obj_bytes(o);
    char *dst = ft_top;
    ft_top += bytes;
    memcpy(dst, (void *)o, bytes);
    *(uint64_t *)dst = h & ~H_GCBITS;
    *hdr_ptr(o) = h | H_FORWARDED;
    ((oop *)o)[1] = (oop)dst;
    return (oop)dst;
}

static void full_root(oop *p)
{
    oop v = *p;
    if (is_ptr(v) && v) *p = full_copy(v);
}

static bool full_dead(oop *v)
{
    if (!(vm_hdr(*v) & H_FORWARDED)) return true;
    *v = ((oop *)*v)[1];
    return false;
}

void full_gc(void)
{
    interp_before_gc();
    int64_t t0 = now_us();
    stat_full_gcs++;
    stat_allocated += (size_t)(eden_top - eden_lo);
    size_t old_used = (size_t)(old_top - old_lo);
    ft_top = old_alt_lo;
    weak_count = 0;
    full_root(&nil_oop); /* collectors store nil into cleared slots while copying */
    for_each_root(full_root);
    char *scan = old_alt_lo;
    while (scan < ft_top) {
        oop o = (oop)scan;
        full_root(&((oop *)o)[1]);
        oop *s = slots(o);
        for (uint32_t i = 0, n = traced_slots(o); i < n; i++) full_root(&s[i]);
        scan += obj_bytes(o);
    }
    clear_weak_slots(full_dead);
    discard(old_lo, old_used);
    char *lo = old_lo, *hi = old_hi;
    old_lo = old_alt_lo;
    old_hi = old_alt_hi;
    old_top = ft_top;
    old_alt_lo = lo;
    old_alt_hi = hi;
    eden_top = eden_lo;
    surv_top = surv_lo;
    remset_count = 0;
    size_t live = (size_t)(old_top - old_lo);
    old_budget = live * 2 > MIN_BUDGET ? live * 2 : MIN_BUDGET;
    if (old_budget > max_heap_bytes) old_budget = max_heap_bytes;
    remember_if_old(active_ctx);
    after_gc();
    stat_full_us += (uint64_t)(now_us() - t0);
    if (live > max_heap_bytes) fatal("out of memory (%zu MB live, limit %zu MB)", live >> 20, max_heap_bytes >> 20);
}

void collect_garbage(size_t need)
{
    (void)need;
    size_t young_used = (size_t)(eden_top - eden_lo) + (size_t)(surv_top - surv_lo);
    size_t old_used = (size_t)(old_top - old_lo);
    if (old_used + young_used > old_budget) {
        full_gc();
    } else {
        scavenge();
        if ((size_t)(old_top - old_lo) > old_budget) full_gc();
    }
}

char *old_alloc_try(size_t bytes)
{
    if (bytes > max_heap_bytes) return NULL;
    if ((size_t)(old_top - old_lo) + bytes > old_budget) {
        full_gc();
        size_t want = 2 * ((size_t)(old_top - old_lo) + bytes);
        if (want > old_budget) old_budget = want < max_heap_bytes ? want : max_heap_bytes;
    }
    if ((size_t)(old_top - old_lo) + bytes > max_heap_bytes) return NULL;
    char *p = old_top;
    old_top += bytes;
    return p;
}

char *old_alloc_raw(size_t bytes)
{
    char *p = old_alloc_try(bytes);
    if (!p) fatal("out of memory allocating %zu bytes", bytes);
    return p;
}

static oop become_from, become_to;

static void become_root(oop *p)
{
    if (*p == become_from) *p = become_to;
}

/* One-way become; call right after full_gc (no young objects). */
void become_forward(oop from, oop to)
{
    interp_before_gc();
    become_from = from;
    become_to = to;
    for_each_root(become_root);
    for (char *p = old_lo; p < old_top; p += obj_bytes((oop)p)) {
        oop o = (oop)p;
        become_root(&((oop *)o)[1]);
        if (fmt_has_pointers(format_of(o))) {
            oop *s = slots(o);
            for (uint32_t i = 0, n = num_slots(o); i < n; i++)
                if (s[i] == from) s[i] = to;
        }
    }
    after_gc();
}

void walk_old_space(obj_visitor fn, void *data)
{
    char *end = old_top;
    for (char *p = old_lo; p < end; p += obj_bytes((oop)p)) fn((oop)p, data);
}
