/* Object, string and byte-access primitives. */
#include "core.h"
#include <string.h>
#include <math.h>

static oop arg0(void) { return prim_argc() > 0 ? prim_arg(0) : nil_oop; }

static bool index_arg(oop o, size_t limit, size_t *k)
{
    if (!is_int(o) || int_val(o) < 1 || (uint64_t)int_val(o) > limit) return false;
    *k = (size_t)int_val(o) - 1;
    return true;
}

void p_class(void) { prim_return(class_of(prim_argc() > 0 ? prim_arg(0) : prim_receiver())); }
void p_identical(void) { prim_return(prim_receiver() == arg0() ? true_oop : false_oop); }

void p_identity_hash(void)
{
    oop r = prim_receiver();
    if (is_ptr(r)) prim_return(int_oop(hash_of(r)));
    else if (is_int(r)) prim_return(r);
    else if (is_char(r)) prim_return(int_oop(char_val(r)));
    else prim_return(int_oop((int64_t)((r >> 3) & 0x3FFFFFFF)));
}

void p_basic_new(void)
{
    int err;
    oop o = instantiate(prim_receiver(), 0, &err);
    if (err) return err > 0 ? prim_fail_code(err) : prim_fail();
    prim_return(o);
}

/* A size no object can have (a LargePositiveInteger too) fails with PRIM_ERR_NO_MEMORY. */
void p_basic_new_size(void)
{
    oop n = arg0();
    uint64_t u;
    if (!u64_of(n, &u)) {
        if (!is_ptr(n) || raw_class(n) != special(SO_LARGEPOS)) return prim_fail();
        u = UINT64_MAX;
    }
    int err;
    oop o = instantiate(prim_receiver(), u > SIZE_MAX ? SIZE_MAX : (size_t)u, &err);
    if (err) return err > 0 ? prim_fail_code(err) : prim_fail();
    prim_return(o);
}

void p_basic_size(void) { prim_return(int_oop((int64_t)indexable_size(prim_receiver()))); }

void p_at(void)
{
    oop r = prim_receiver();
    size_t k;
    if (!is_ptr(r) || !index_arg(arg0(), indexable_size(r), &k)) return prim_fail();
    int f = format_of(r);
    if (fmt_has_pointers(f)) prim_return(load_ref(r, fixed_fields(r) + (uint32_t)k));
    else if (f == F_W64) {
        uint64_t v = slots(r)[k];
        prim_return(v <= (uint64_t)VM_INT_MAX ? int_oop((int64_t)v) : large_int_from_u64(v, false));
    } else if (f == 10 || f == 11) prim_return(int_oop(words32_of(r)[k]));
    else if (f >= F_BYTES) prim_return(int_oop(bytes_of(r)[k]));
    else prim_fail();
}

void p_at_put(void)
{
    oop r = prim_receiver();
    size_t k;
    if (prim_argc() < 2 || !is_ptr(r) || is_immutable(r) || !index_arg(prim_arg(0), indexable_size(r), &k))
        return prim_fail();
    oop v = prim_arg(1);
    int f = format_of(r);
    uint64_t u;
    if (fmt_has_pointers(f)) store_ref(r, fixed_fields(r) + (uint32_t)k, v);
    else if (f == F_W64) {
        if (!u64_of(v, &u)) return prim_fail();
        slots(r)[k] = u;
    } else if (f == 10 || f == 11) {
        if (!is_int(v) || int_val(v) < 0 || int_val(v) > 0xFFFFFFFFll) return prim_fail();
        words32_of(r)[k] = (uint32_t)int_val(v);
    } else if (f >= F_BYTES) {
        if (!is_int(v) || int_val(v) < 0 || int_val(v) > 255) return prim_fail();
        bytes_of(r)[k] = (uint8_t)int_val(v);
    } else return prim_fail();
    prim_return(v);
}

void p_inst_var_at(void)
{
    oop r = prim_receiver();
    size_t k;
    if (!is_ptr(r) || !fmt_has_pointers(format_of(r)) || !index_arg(arg0(), num_slots(r), &k)) return prim_fail();
    prim_return(load_ref(r, (uint32_t)k));
}

void p_inst_var_at_put(void)
{
    oop r = prim_receiver();
    size_t k;
    if (prim_argc() < 2 || !is_ptr(r) || is_immutable(r) || !fmt_has_pointers(format_of(r)) ||
        !index_arg(prim_arg(0), num_slots(r), &k))
        return prim_fail();
    oop v = prim_arg(1);
    store_ref(r, (uint32_t)k, v);
    prim_return(v);
}

void p_shallow_copy(void)
{
    oop r = prim_receiver();
    if (!is_ptr(r)) return prim_return(r);
    oop c = alloc_obj_try(raw_class(r), format_of(r), num_slots(r));
    if (!c) return prim_fail_code(PRIM_ERR_NO_MEMORY);
    r = prim_receiver();
    memcpy(slots(c), slots(r), (size_t)num_slots(r) * 8);
    if (fmt_has_pointers(format_of(r))) remember_if_old(c);
    prim_return(c);
}

void p_is_immutable(void)
{
    oop r = prim_receiver();
    prim_return(!is_ptr(r) || is_immutable(r) ? true_oop : false_oop);
}

void p_set_immutable(void)
{
    oop r = prim_receiver(), v = arg0();
    if (v != true_oop && v != false_oop) return prim_fail();
    if (!is_ptr(r)) {
        if (v == true_oop) return prim_return(true_oop);
        return prim_fail();
    }
    bool old = is_immutable(r);
    if (v == true_oop) *hdr_ptr(r) |= H_IMMUTABLE;
    else *hdr_ptr(r) &= ~H_IMMUTABLE;
    prim_return(old ? true_oop : false_oop);
}

void p_change_class_to(void)
{
    oop r = prim_receiver(), c = arg0();
    if (!is_ptr(r) || !is_ptr(c) || num_slots(c) <= BEH_FORMAT || !is_int(load_ref(c, BEH_FORMAT))) return prim_fail();
    int64_t spec = int_val(load_ref(c, BEH_FORMAT)) >> CLS_SPEC_SHIFT, isize = int_val(load_ref(c, BEH_FORMAT)) & CLS_INSTSIZE_MASK;
    int f = format_of(r), nf = f;
    switch (spec) {
    case 0:
    case 1:
        if (f > 1 || num_slots(r) != isize) return prim_fail();
        nf = isize ? 1 : 0;
        break;
    case 2:
    case 3:
    case 4:
        if (f < 2 || f > 4 || fixed_fields(r) != isize) return prim_fail();
        nf = spec == 2 && isize ? 3 : (int)spec;
        break;
    case 9:
        if (f != 9) return prim_fail();
        break;
    case 10:
        if (f != 10 && f != 11) return prim_fail();
        break;
    case 16:
        if (f < 16) return prim_fail();
        break;
    default: return prim_fail();
    }
    *hdr_ptr(r) = (vm_hdr(r) & ~(0x1Full << H_FMT_SHIFT)) | ((uint64_t)nf << H_FMT_SHIFT);
    ((oop *)r)[1] = c;
    if (vm_is_young(c)) remember_if_old(r);
    prim_return(r);
}

typedef struct {
    oop cls, result;
    size_t n;
} instances_state;

static void count_instance(oop o, void *d)
{
    instances_state *s = d;
    if (raw_class(o) == s->cls && o != s->result) {
        if (s->result && s->n >= num_slots(s->result)) return;
        if (s->result) store_ref(s->result, (uint32_t)s->n, o);
        s->n++;
    }
}

void p_all_instances(void)
{
    full_gc();
    instances_state s = {prim_receiver(), 0, 0};
    walk_old_space(count_instance, &s);
    size_t n = s.n;
    oop a = alloc_old(cls_array, F_VAR, (uint32_t)n);
    s.cls = prim_receiver();
    s.result = a;
    s.n = 0;
    walk_old_space(count_instance, &s);
    prim_return(a);
}

void p_become_forward(void)
{
    if (!is_ptr(prim_receiver()) || !is_ptr(arg0()) || prim_receiver() == nil_oop) return prim_fail();
    full_gc();
    become_forward(prim_receiver(), arg0());
    prim_return(prim_receiver());
}

/* ---- strings ---- */

static bool is_string_like(oop o)
{
    if (!is_ptr(o)) return false;
    int f = format_of(o);
    return f >= F_BYTES || f == 10 || f == 11;
}

void p_string_at(void)
{
    oop r = prim_receiver();
    size_t k;
    if (!is_string_like(r) || !index_arg(arg0(), string_size(r), &k)) return prim_fail();
    prim_return(char_oop(string_char_at(r, k)));
}

void p_string_at_put(void)
{
    oop r = prim_receiver();
    size_t k;
    if (prim_argc() < 2 || !is_string_like(r) || is_immutable(r) || !index_arg(prim_arg(0), string_size(r), &k))
        return prim_fail();
    oop c = prim_arg(1);
    if (!is_char(c)) return prim_fail();
    if (format_of(r) >= F_BYTES) {
        if (char_val(c) > 255) return prim_fail();
        bytes_of(r)[k] = (uint8_t)char_val(c);
    } else {
        words32_of(r)[k] = char_val(c);
    }
    prim_return(c);
}

void p_string_hash(void)
{
    oop s = prim_argc() > 0 ? prim_arg(0) : prim_receiver();
    if (!is_string_like(s)) return prim_fail();
    prim_return(int_oop(string_hash(s)));
}

void p_string_compare(void)
{
    oop a = prim_receiver(), b = arg0();
    if (!is_string_like(a) || !is_string_like(b)) return prim_fail();
    size_t na = string_size(a), nb = string_size(b), n = na < nb ? na : nb;
    for (size_t i = 0; i < n; i++) {
        uint32_t x = string_char_at(a, i), y = string_char_at(b, i);
        if (x != y) return prim_return(int_oop(x < y ? -1 : 1));
    }
    prim_return(int_oop(na < nb ? -1 : na > nb ? 1 : 0));
}

static int elem_kind(oop o)
{
    int f = format_of(o);
    if (fmt_has_pointers(f)) return 1;
    if (f == F_W64) return 2;
    if (f == 10 || f == 11) return 3;
    if (f >= F_BYTES) return 4;
    return 0;
}

void p_replace_from_to(void)
{
    if (prim_argc() < 4) return prim_fail();
    oop r = prim_receiver(), src = prim_arg(2), so = prim_arg(0), eo = prim_arg(1), ro = prim_arg(3);
    if (!is_ptr(r) || !is_ptr(src) || is_immutable(r) || !is_int(so) || !is_int(eo) || !is_int(ro)) return prim_fail();
    int kind = elem_kind(r);
    if (!kind || kind != elem_kind(src)) return prim_fail();
    int64_t start = int_val(so), stop = int_val(eo), rstart = int_val(ro), n = stop - start + 1;
    if (n == 0 && start >= 1) return prim_return(r);
    if (start < 1 || n < 0 || stop > (int64_t)indexable_size(r) || rstart < 1 ||
        rstart + n - 1 > (int64_t)indexable_size(src))
        return prim_fail();
    switch (kind) {
    case 1: {
        uint32_t fr = fixed_fields(r), fs = fixed_fields(src);
        oop *d = slots(r) + fr + start - 1, *s = slots(src) + fs + rstart - 1;
        memmove(d, s, (size_t)n * 8);
        remember_if_old(r);
        break;
    }
    case 2: memmove(slots(r) + start - 1, slots(src) + rstart - 1, (size_t)n * 8); break;
    case 3: memmove(words32_of(r) + start - 1, words32_of(src) + rstart - 1, (size_t)n * 4); break;
    case 4: memmove(bytes_of(r) + start - 1, bytes_of(src) + rstart - 1, (size_t)n); break;
    }
    prim_return(r);
}

/* ---- byte access ---- */

static size_t raw_byte_size(oop o)
{
    int f = format_of(o);
    if (f >= F_BYTES) return byte_size(o);
    if (f == 10 || f == 11) return word32_size(o) * 4;
    if (f == F_W64) return (size_t)num_slots(o) * 8;
    return 0;
}

static uint8_t *byte_at(size_t width, bool put)
{
    oop r = prim_receiver();
    if (!is_ptr(r) || (put && is_immutable(r))) return NULL;
    size_t n = raw_byte_size(r);
    oop i = arg0();
    if (!is_int(i) || int_val(i) < 1 || (uint64_t)int_val(i) - 1 + width > n) return NULL;
    return bytes_of(r) + int_val(i) - 1;
}

void p_bytes_uint16_at(void)
{
    uint8_t *p = byte_at(2, false);
    if (!p) return prim_fail();
    prim_return(int_oop(p[0] | (p[1] << 8)));
}

void p_bytes_int16_at(void)
{
    uint8_t *p = byte_at(2, false);
    if (!p) return prim_fail();
    prim_return(int_oop((int16_t)(p[0] | (p[1] << 8))));
}

void p_bytes_uint32_at(void)
{
    uint8_t *p = byte_at(4, false);
    if (!p) return prim_fail();
    uint32_t v;
    memcpy(&v, p, 4);
    prim_return(int_oop(v));
}

void p_bytes_uint32_at_put(void)
{
    uint8_t *p = byte_at(4, true);
    if (!p || prim_argc() < 2) return prim_fail();
    oop v = prim_arg(1);
    if (!is_int(v) || int_val(v) < 0 || int_val(v) > 0xFFFFFFFFll) return prim_fail();
    uint32_t w = (uint32_t)int_val(v);
    memcpy(p, &w, 4);
    prim_return(v);
}

void p_bytes_float32_at(void)
{
    uint8_t *p = byte_at(4, false);
    if (!p) return prim_fail();
    float f;
    memcpy(&f, p, 4);
    prim_return(float_oop(f));
}

void p_bytes_float32_at_put(void)
{
    uint8_t *p = byte_at(4, true);
    if (!p || prim_argc() < 2) return prim_fail();
    oop v = prim_arg(1);
    float f;
    if (is_float(v)) f = (float)float_val(v);
    else if (is_int(v)) f = (float)int_val(v);
    else return prim_fail();
    memcpy(p, &f, 4);
    prim_return(v);
}

void p_bytes_float64_at(void)
{
    uint8_t *p = byte_at(8, false);
    if (!p) return prim_fail();
    double d;
    memcpy(&d, p, 8);
    prim_return(float_oop(d));
}

void p_bytes_float64_at_put(void)
{
    uint8_t *p = byte_at(8, true);
    if (!p || prim_argc() < 2) return prim_fail();
    oop v = prim_arg(1);
    double d;
    if (is_float(v)) d = float_val(v);
    else if (is_int(v)) d = (double)int_val(v);
    else return prim_fail();
    memcpy(p, &d, 8);
    prim_return(v);
}

void p_bytes_uint16_be_at(void)
{
    uint8_t *p = byte_at(2, false);
    if (!p) return prim_fail();
    prim_return(int_oop((p[0] << 8) | p[1]));
}

void p_bytes_int16_be_at(void)
{
    uint8_t *p = byte_at(2, false);
    if (!p) return prim_fail();
    prim_return(int_oop((int16_t)((p[0] << 8) | p[1])));
}

void p_bytes_uint32_be_at(void)
{
    uint8_t *p = byte_at(4, false);
    if (!p) return prim_fail();
    prim_return(int_oop(((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]));
}


