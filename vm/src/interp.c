/* Bytecode interpreter: dispatch, sends, returns, stack frames, method cache, primitive plumbing.
 *
 * Activations live in frames on a C stack (cstack: arguments, temps and operand stacks of all frames, contiguous;
 * frames[]: one record per frame) above a heap Context, the base (active_ctx). A Context for a frame is created
 * only when Smalltalk could observe it: thisContext, closure creation (outerContext), non-local return through an
 * unwind marker, process switch, snapshot, stack overflow. Then every frame is flushed into a Context (sender
 * chain intact) and execution continues in the top Context, so Smalltalk only ever sees real Contexts. With no
 * frames (nframes == 0) the interpreter executes active_ctx itself; a send pushes a frame. */
#include "core.h"
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

oop active_ctx;
oop vm_tmp_root[4];
int prim_status, prim_error_code, prim_nargs;
oop prim_result, resend_selector;
int resend_argc;

/* ---- frames ---- */

typedef struct {
    oop method, closure, receiver; /* GC roots; closure is nil for method activations */
    oop *fp;                       /* first argument/temp in cstack; for a send, fp[-1] holds the receiver */
    uint8_t *bcs;                  /* method bytecodes and literals, refreshed after every GC */
    oop *lits;
    int32_t pc, sp;                /* pc offset, used slots from fp: saved when the frame is not executing */
    int32_t fsize;                 /* frameSize, for the Context it may become */
} frame_t;

#define CSTACK_SLOTS (256 * 1024)
#define MAX_FRAMES 8192
static oop cstack[CSTACK_SLOTS];
static frame_t frames[MAX_FRAMES];
int nframes;
static size_t cstack_used; /* live cstack slots when externalized */
#define CSTACK_END (cstack + CSTACK_SLOTS)

void interp_roots(void (*fn)(oop *))
{
    for (int i = 0; i < nframes; i++) {
        fn(&frames[i].method);
        fn(&frames[i].closure);
        fn(&frames[i].receiver);
    }
    for (size_t i = 0; i < cstack_used; i++) fn(&cstack[i]);
}

void interp_after_gc(void)
{
    for (int i = 0; i < nframes; i++) {
        frames[i].bcs = bytes_of(load_ref(frames[i].method, CM_BYTECODES));
        frames[i].lits = slots(load_ref(frames[i].method, CM_LITERALS));
    }
}

bool interp_frames_valid(bool (*valid)(oop))
{
    for (int i = 0; i < nframes; i++)
        if (!valid(frames[i].method) || !valid(frames[i].closure) || !valid(frames[i].receiver)) return false;
    for (size_t i = 0; i < cstack_used; i++)
        if (!valid(cstack[i])) return false;
    return true;
}

/* Flushes every frame into a Context (bottom up, so senders exist first); afterwards active_ctx is the top one.
 * The caller has externalized the top frame. */
uint64_t stat_materialized, stat_flushes;

void materialize_all(void)
{
    if (nframes) stat_flushes++;
    stat_materialized += (uint64_t)nframes;
    for (int i = 0; i < nframes; i++) {
        int32_t n = frames[i].fsize + CTX_SLACK;
        if (n < frames[i].sp) n = frames[i].sp;
        oop ctx = alloc_context((uint32_t)n);
        frame_t *f = &frames[i];
        oop *s = slots(ctx);
        s[CTX_SENDER] = active_ctx;
        s[CTX_PC] = int_oop(f->pc);
        s[CTX_STACKP] = int_oop(f->sp);
        s[CTX_METHOD] = f->method;
        s[CTX_CLOSURE] = f->closure;
        s[CTX_RECEIVER] = f->receiver;
        memcpy(s + CTX_FIXED, f->fp, (size_t)f->sp * sizeof(oop));
        remember_if_old(ctx);
        active_ctx = ctx;
    }
    nframes = 0;
    cstack_used = 0;
    gc_epoch++; /* tells the interpreter to reload its registers */
}

/* ---- method cache ---- */

typedef struct {
    oop cls, sel, method;
    prim_fn prim;
    uint8_t *bcs; /* raw pointers into the method: valid until the next GC, which flushes the cache */
    oop *lits;
    int32_t ntemps, fsize;
    int quick; /* >= 0: the method is "^instVar quick" (push inst var quick, return top): answer that slot without a frame */
    int nset;  /* > 0: a setter, "ivar1 := arg1. ... ivarN := argN" (and ^self): stores the arguments without a frame */
    uint8_t set_ivar[4];
} cache_entry;
#define CACHE_SIZE 4096
static cache_entry cache[CACHE_SIZE];
#define CACHE_INDEX(c, s) ((((c) >> 3) ^ ((s) >> 3) ^ ((s) >> 12)) & (CACHE_SIZE - 1))

void flush_method_cache(void) { memset(cache, 0, sizeof cache); }

void flush_method_cache_selector(oop sel)
{
    for (int i = 0; i < CACHE_SIZE; i++)
        if (cache[i].sel == sel) cache[i].cls = cache[i].sel = 0;
}

oop lookup_method(oop cls, oop sel)
{
    uint32_t h = hash_of(sel);
    while (is_ptr(cls) && cls != nil_oop) {
        oop md = load_ref(cls, BEH_METHODDICT);
        if (is_ptr(md) && md != nil_oop) {
            oop keys = load_ref(md, MD_KEYS), vals = load_ref(md, MD_VALUES);
            uint32_t cap = num_slots(keys);
            if (cap && is_ptr(vals) && num_slots(vals) >= cap) {
                uint32_t mask = cap - 1, i = h & mask;
                for (uint32_t n = 0; n < cap; n++, i = (i + 1) & mask) {
                    oop k = load_ref(keys, i);
                    if (k == sel) return load_ref(vals, i);
                    if (k == nil_oop) break;
                }
            }
        }
        cls = load_ref(cls, BEH_SUPERCLASS);
    }
    return 0;
}

static inline int64_t method_prim(oop m)
{
    oop p = load_ref(m, CM_PRIMITIVE);
    return is_int(p) ? int_val(p) : 0;
}

static cache_entry *fill_cache(oop cls, oop sel)
{
    oop m = lookup_method(cls, sel);
    if (!m) return NULL;
    cache_entry *e = &cache[CACHE_INDEX(cls, sel)];
    e->cls = cls;
    e->sel = sel;
    e->method = m;
    int64_t p = method_prim(m) & CM_PRIM_MASK;
    e->prim = (p && p != PRIM_ENSURE_MARKER && p != PRIM_ONDO_MARKER) ? prim_lookup(p) : NULL;
    oop bc = load_ref(m, CM_BYTECODES), na = load_ref(m, CM_NUMARGS), nt = load_ref(m, CM_NUMTEMPS);
    e->bcs = bytes_of(bc);
    e->lits = slots(load_ref(m, CM_LITERALS));
    e->ntemps = (int32_t)int_val(nt);
    e->fsize = (int32_t)int_val(load_ref(m, CM_FRAMESIZE));
    if (e->fsize < int_val(na) + e->ntemps) e->fsize = (int32_t)(int_val(na) + e->ntemps);
    /* Quick methods (as in Smalltalk-80 and Squeak): a unary method whose bytecodes are exactly "push inst var i,
       return top" answers the receiver's slot i without activating a frame. */
    e->quick = -1;
    e->nset = 0;
    if (!p && na == int_oop(0) && is_ptr(bc) && format_of(bc) >= F_BYTES && byte_size(bc) == 2) {
        uint8_t *b = bytes_of(bc);
        if (b[0] >= 0x10 && b[0] <= 0x1F && b[1] == 0x79) e->quick = b[0] - 0x10;
    }
    /* Setters: for each argument k in order "push temp k, store inst var i, pop", then "return self", no temps. */
    if (!p && is_int(na) && int_val(na) >= 1 && int_val(na) <= 4 && nt == int_oop(0) && is_ptr(bc) && format_of(bc) >= F_BYTES
        && byte_size(bc) == (size_t)(4 * int_val(na) + 1)) {
        uint8_t *b = bytes_of(bc);
        int n = (int)int_val(na), ok = b[4 * n] == 0x7A;
        for (int k = 0; ok && k < n; k++)
            ok = b[4 * k] == k && b[4 * k + 1] == 0x85 && b[4 * k + 3] == 0x78;
        if (ok) {
            for (int k = 0; k < n; k++) e->set_ivar[k] = b[4 * k + 2];
            e->nset = n;
        }
    }
    return e;
}

int selector_argc(oop sel)
{
    if (!is_ptr(sel) || format_of(sel) < F_BYTES) return -1;
    size_t n = byte_size(sel);
    uint8_t *b = bytes_of(sel);
    if (!n) return 0;
    if (!((b[0] >= 'a' && b[0] <= 'z') || (b[0] >= 'A' && b[0] <= 'Z') || b[0] == '_')) return 1;
    int c = 0;
    for (size_t i = 0; i < n; i++) c += b[i] == ':';
    return c;
}

/* ---- the active activation (frame or Context), externalized ---- */

int64_t ctx_stackp(oop ctx) { return int_val(load_ref(ctx, CTX_STACKP)); }
void ctx_set_stackp(oop ctx, int64_t sp) { slots(ctx)[CTX_STACKP] = int_oop(sp); }

oop ctx_home(oop ctx)
{
    oop cl;
    while ((cl = load_ref(ctx, CTX_CLOSURE)) != nil_oop) ctx = load_ref(cl, BC_OUTER);
    return ctx;
}

oop *active_slots(void) { return nframes ? frames[nframes - 1].fp : slots(active_ctx) + CTX_FIXED; }
int64_t active_stackp(void) { return nframes ? frames[nframes - 1].sp : ctx_stackp(active_ctx); }

void active_set_stackp(int64_t n)
{
    if (nframes) {
        frames[nframes - 1].sp = (int32_t)n;
        cstack_used = (size_t)(frames[nframes - 1].fp + n - cstack);
    } else {
        ctx_set_stackp(active_ctx, n);
    }
}

int64_t active_capacity(void)
{
    return nframes ? frames[nframes - 1].fsize + CTX_SLACK : (int64_t)num_slots(active_ctx) - CTX_FIXED;
}

oop *prim_stack_base(void) { return active_slots() + active_stackp() - 1 - prim_nargs; }

int prim_argc(void) { return prim_nargs; }
oop prim_receiver(void) { return prim_stack_base()[0]; }
oop prim_arg(int i) { return prim_stack_base()[1 + i]; }
void prim_return(oop v)
{
    prim_result = v;
    prim_status = PS_OK;
}
void prim_fail(void)
{
    prim_status = PS_FAIL;
    prim_error_code = -1;
}
void prim_fail_code(int code)
{
    prim_status = PS_FAIL;
    prim_error_code = code;
}
bool prim_failed(void) { return prim_status == PS_FAIL; }

void prim_commit(oop result)
{
    oop *b = prim_stack_base();
    b[0] = result;
    active_set_stackp(active_stackp() - prim_nargs);
    prim_nargs = 0;
    prim_status = PS_SWITCHED;
}

void prim_switched(void) { prim_status = PS_SWITCHED; }

/* Pushes a frame for the closure at the stack base (argc args above it, or one Array when from_array).
 * The caller has externalized. */
static void block_activate(int argc, bool from_array)
{
    int64_t base = active_stackp() - 1 - (from_array ? 1 : argc);
    oop *b = active_slots() + base, cl = b[0], arr = from_array ? b[1] : 0;
    if (from_array) argc = (int)num_slots(arr);
    int64_t ntemps = int_val(load_ref(cl, BC_NUMTEMPS)), fsize = int_val(load_ref(cl, BC_FRAMESIZE));
    if (fsize < argc + ntemps) fsize = argc + ntemps;
    oop *nfp;
    if (nframes) {
        nfp = b + 1;
        if (nframes >= MAX_FRAMES || nfp + fsize + CTX_SLACK > CSTACK_END) {
            materialize_all();
            block_activate(from_array ? 0 : argc, from_array);
            return;
        }
        frames[nframes - 1].sp = (int32_t)base;
        if (from_array)
            for (int i = 0; i < argc; i++) nfp[i] = load_ref(arr, (uint32_t)i);
    } else {
        cstack[0] = cl;
        for (int i = 0; i < argc; i++) cstack[1 + i] = from_array ? load_ref(arr, (uint32_t)i) : b[1 + i];
        ctx_set_stackp(active_ctx, base);
        nfp = cstack + 1;
    }
    oop outer = load_ref(cl, BC_OUTER), m = load_ref(outer, CTX_METHOD);
    frame_t *f = &frames[nframes++];
    f->method = m;
    f->closure = cl;
    f->receiver = load_ref(outer, CTX_RECEIVER);
    f->fp = nfp;
    f->bcs = bytes_of(load_ref(m, CM_BYTECODES));
    f->lits = slots(load_ref(m, CM_LITERALS));
    f->pc = (int32_t)int_val(load_ref(cl, BC_STARTPC));
    f->sp = (int32_t)(argc + ntemps);
    f->fsize = (int32_t)fsize;
    for (int64_t i = argc; i < argc + ntemps; i++) nfp[i] = nil_oop;
    cstack_used = (size_t)(nfp + argc + ntemps - cstack);
}

void activate_block(int argc) { block_activate(argc, false); }
void activate_block_with_array(void) { block_activate(0, true); }

/* ---- diagnostics ---- */

static void print_class_name(FILE *f, oop cls)
{
    if (!is_ptr(cls) || cls == nil_oop) {
        fputs("nil", f);
        return;
    }
    oop cc = raw_class(cls);
    if (num_slots(cls) > CLS_NAME && is_ptr(load_ref(cls, CLS_NAME)) && format_of(load_ref(cls, CLS_NAME)) >= F_BYTES &&
        raw_class(load_ref(cls, CLS_NAME)) == special(SO_BYTESYMBOL)) {
        oop n = load_ref(cls, CLS_NAME);
        fprintf(f, "%.*s", (int)byte_size(n), (char *)bytes_of(n));
        return;
    }
    if (num_slots(cls) > META_THISCLASS && is_ptr(load_ref(cls, META_THISCLASS)) && cc != cls) {
        oop t = load_ref(cls, META_THISCLASS);
        if (num_slots(t) > CLS_NAME) {
            print_class_name(f, t);
            fputs(" class", f);
            return;
        }
    }
    fputs("?", f);
}

static void print_symbol(FILE *f, oop s)
{
    if (is_ptr(s) && format_of(s) >= F_BYTES) fprintf(f, "%.*s", (int)byte_size(s), (char *)bytes_of(s));
    else fputs("?", f);
}

static void print_activation(FILE *f, oop m, oop r, oop closure)
{
    if (closure != nil_oop) fputs("[] in ", f);
    oop rc = class_of(r), mc = is_ptr(m) ? load_ref(m, CM_CLASS) : nil_oop;
    print_class_name(f, rc);
    if (mc != rc) {
        fputc('(', f);
        print_class_name(f, mc);
        fputc(')', f);
    }
    fputs(">>", f);
    print_symbol(f, is_ptr(m) ? load_ref(m, CM_SELECTOR) : nil_oop);
    fputc('\n', f);
}

/* Prints the frames, then the sender chain of ctx; deep stacks show the top 40 and bottom 10 activations. */
void print_stack(FILE *f, oop ctx)
{
    long depth = nframes, i = 0;
    for (oop c = ctx; is_ptr(c) && c != nil_oop; c = load_ref(c, CTX_SENDER)) depth++;
    for (int k = nframes - 1; k >= 0; k--, i++) {
        if (depth > 60 && i == 40) fprintf(f, "... %ld more frames ...\n", depth - 50);
        if (depth <= 60 || i < 40 || i >= depth - 10) print_activation(f, frames[k].method, frames[k].receiver, frames[k].closure);
    }
    for (; is_ptr(ctx) && ctx != nil_oop; ctx = load_ref(ctx, CTX_SENDER), i++) {
        if (depth > 60 && i == 40) fprintf(f, "... %ld more frames ...\n", depth - 50);
        if (depth <= 60 || i < 40 || i >= depth - 10)
            print_activation(f, load_ref(ctx, CTX_METHOD), load_ref(ctx, CTX_RECEIVER), load_ref(ctx, CTX_CLOSURE));
    }
}

_Noreturn void fatal(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    fputs("samaltak: fatal: ", stderr);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
    fflush(stdout);
    if (is_ptr(active_ctx) && active_ctx && specials_oop) {
        fputs("Smalltalk stack:\n", stderr);
        print_stack(stderr, active_ctx);
    }
    exit(70);
}

/* ---- the interpreter ---- */

static int special_argc[32];

static inline uint64_t rotr1(uint64_t x) { return (x >> 1) | (x << 63); }

static inline bool float_imm(double d, oop *out)
{
    uint64_t b;
    memcpy(&b, &d, 8);
    if ((b << 1) == 0) {
        *out = ((b >> 63) << 3) | 4;
        return true;
    }
    unsigned e = (unsigned)(b >> 52) & 0x7FF;
    if (e > 896 && e < 1151) {
        *out = ((((b << 1) | (b >> 63)) - (896ull << 53)) << 3) | 4;
        return true;
    }
    return false;
}

/* SmallInteger, SmallFloat64 or BoxedFloat64 as a double */
static inline bool num_val(oop o, double *d)
{
    uint64_t b;
    if ((o & 7) == 4) {
        uint64_t r = o >> 3;
        b = r <= 1 ? r << 63 : rotr1(r + (896ull << 53));
    } else if (o & 1) {
        *d = (double)int_val(o);
        return true;
    } else if (is_ptr(o) && raw_class(o) == cls_boxedfloat) {
        b = slots(o)[0];
    } else {
        return false;
    }
    memcpy(d, &b, 8);
    return true;
}

/* both numbers, at least one a Float (the SmallInteger pair is handled before) */
static inline bool num_pair(oop a, oop b, double *x, double *y)
{
    if ((a & b & 1)) return false;
    return num_val(a, x) && num_val(b, y);
}

static inline int64_t floor_div(int64_t a, int64_t b)
{
    int64_t q = a / b;
    if ((a % b != 0) && ((a < 0) != (b < 0))) q--;
    return q;
}

static inline int64_t floor_mod(int64_t a, int64_t b)
{
    int64_t r = a % b;
    if (r != 0 && ((r < 0) != (b < 0))) r += b;
    return r;
}

void interpret(void)
{
    static void *ops[256];
    uint8_t *ip, *bcs;
    oop *sp, *fp, *lits, rcvr, method, sel, cls, result;
    int argc, op;
    uint64_t epoch;

    if (!ops[0]) {
        for (int i = 0; i < 256; i++) ops[i] = &&op_bad;
        for (int i = 0x00; i <= 0x0F; i++) ops[i] = &&op_push_temp;
        for (int i = 0x10; i <= 0x1F; i++) ops[i] = &&op_push_ivar;
        for (int i = 0x20; i <= 0x3F; i++) ops[i] = &&op_push_lit;
        for (int i = 0x40; i <= 0x5F; i++) ops[i] = &&op_push_litvar;
        for (int i = 0x60; i <= 0x67; i++) ops[i] = &&op_popstore_temp;
        ops[0x70] = &&op_push_self;
        ops[0x71] = &&op_push_true;
        ops[0x72] = &&op_push_false;
        ops[0x73] = &&op_push_nil;
        ops[0x74] = &&op_push_zero;
        ops[0x75] = &&op_push_one;
        ops[0x76] = &&op_push_ctx;
        ops[0x77] = &&op_dup;
        ops[0x78] = &&op_pop;
        ops[0x79] = &&op_return_top;
        ops[0x7A] = &&op_return_self;
        ops[0x7B] = &&op_return_top;
        ops[0x7C] = &&op_nonlocal_return;
        ops[0x80] = &&op_push_temp_x;
        ops[0x81] = &&op_push_ivar_x;
        ops[0x82] = &&op_push_lit_x;
        ops[0x83] = &&op_push_litvar_x;
        ops[0x84] = &&op_store_temp_x;
        ops[0x85] = &&op_store_ivar_x;
        ops[0x86] = &&op_store_litvar_x;
        ops[0x87] = &&op_popstore_temp_x;
        ops[0x89] = &&op_popstore_litvar_x;
        ops[0x8A] = &&op_push_outer;
        ops[0x8B] = &&op_store_outer;
        ops[0x8C] = &&op_popstore_outer;
        ops[0x8D] = &&op_send;
        ops[0x8E] = &&op_super_send;
        ops[0x8F] = &&op_closure;
        ops[0x90] = &&op_jump;
        ops[0x91] = &&op_jump_true;
        ops[0x92] = &&op_jump_false;
        ops[0x93] = &&op_push_int;
        ops[0x94] = &&op_make_array;
        for (int i = 0xA0; i <= 0xBF; i++) ops[i] = &&op_special_send;
        ops[0xA0] = &&op_add;
        ops[0xA1] = &&op_sub;
        ops[0xA2] = &&op_lt;
        ops[0xA3] = &&op_gt;
        ops[0xA4] = &&op_le;
        ops[0xA5] = &&op_ge;
        ops[0xA6] = &&op_eq;
        ops[0xA7] = &&op_ne;
        ops[0xA8] = &&op_mul;
        ops[0xA9] = &&op_div;
        ops[0xAA] = &&op_mod;
        ops[0xAC] = &&op_bitshift;
        ops[0xAD] = &&op_floordiv;
        ops[0xAE] = &&op_bitand;
        ops[0xAF] = &&op_bitor;
        ops[0xB0] = &&op_at;
        ops[0xB1] = &&op_at_put;
        ops[0xB2] = &&op_size;
        ops[0xB3] = &&op_identical;
        ops[0xB4] = &&op_not_identical;
        ops[0xB5] = &&op_value;
        ops[0xB6] = &&op_value;
        ops[0xBE] = &&op_value;
        ops[0xBB] = &&op_point_x;
        ops[0xBC] = &&op_point_y;
        ops[0xBD] = &&op_class;
        for (int i = 0xC0; i <= 0xEF; i++) ops[i] = &&op_send_short;
    }
    {
        oop ss = special(SO_SPECIAL_SELECTORS);
        for (int i = 0; i < 32; i++) special_argc[i] = is_ptr(ss) && i < (int)num_slots(ss) ? selector_argc(load_ref(ss, (uint32_t)i)) : 0;
    }

#define LOAD_CTX()                                                                                                     \
    do {                                                                                                               \
        oop *s_ = slots(active_ctx);                                                                                   \
        method = s_[CTX_METHOD];                                                                                       \
        bcs = bytes_of(slots(method)[CM_BYTECODES]);                                                                   \
        lits = slots(slots(method)[CM_LITERALS]);                                                                      \
        fp = s_ + CTX_FIXED;                                                                                           \
        sp = fp + int_val(s_[CTX_STACKP]) - 1;                                                                         \
        if (!is_int(s_[CTX_PC])) fatal("resuming a dead context");                                                     \
        ip = bcs + int_val(s_[CTX_PC]);                                                                                \
        rcvr = s_[CTX_RECEIVER];                                                                                       \
    } while (0)
#define SAVE_CTX()                                                                                                     \
    do {                                                                                                               \
        oop *s_ = slots(active_ctx);                                                                                   \
        s_[CTX_PC] = int_oop(ip - bcs);                                                                                \
        s_[CTX_STACKP] = int_oop(sp - fp + 1);                                                                         \
    } while (0)
#define LOAD_FRAME()                                                                                                   \
    do {                                                                                                               \
        frame_t *f_ = &frames[nframes - 1];                                                                            \
        method = f_->method;                                                                                           \
        bcs = f_->bcs;                                                                                                 \
        lits = f_->lits;                                                                                               \
        fp = f_->fp;                                                                                                   \
        sp = fp + f_->sp - 1;                                                                                          \
        ip = bcs + f_->pc;                                                                                             \
        rcvr = f_->receiver;                                                                                           \
    } while (0)
#define SAVE_FRAME()                                                                                                   \
    do {                                                                                                               \
        frame_t *f_ = &frames[nframes - 1];                                                                            \
        f_->pc = (int32_t)(ip - bcs);                                                                                  \
        f_->sp = (int32_t)(sp - fp + 1);                                                                               \
        cstack_used = (size_t)(sp + 1 - cstack);                                                                       \
    } while (0)
#define EXTERNALIZE()                                                                                                  \
    do {                                                                                                               \
        if (nframes) SAVE_FRAME();                                                                                     \
        else SAVE_CTX();                                                                                               \
    } while (0)
#define RELOAD()                                                                                                       \
    do {                                                                                                               \
        if (nframes) LOAD_FRAME();                                                                                     \
        else LOAD_CTX();                                                                                               \
    } while (0)
/* frames into Contexts: from here on the top activation runs in active_ctx */
#define TO_CONTEXT()                                                                                                   \
    do {                                                                                                               \
        if (nframes) {                                                                                                 \
            SAVE_FRAME();                                                                                              \
            materialize_all();                                                                                         \
            LOAD_CTX();                                                                                                \
        }                                                                                                              \
    } while (0)
#define NEXT goto *ops[op = *ip++]
#define PUSH(v) (*++sp = (v))
#define CHECK_INTERRUPTS()                                                                                             \
    do {                                                                                                               \
        if (__builtin_expect(atomic_load_explicit(&interrupt_pending, memory_order_relaxed), 0)) {                     \
            EXTERNALIZE();                                                                                             \
            handle_interrupts();                                                                                       \
            RELOAD();                                                                                                  \
        }                                                                                                              \
    } while (0)
#define INT16() ((int16_t)(ip[0] | (ip[1] << 8)))
/* A comparison followed by a conditional jump branches directly (the Boolean is never pushed). */
#define BOOL_RESULT(c)                                                                                                 \
    do {                                                                                                               \
        bool c_ = (c);                                                                                                 \
        int nx_ = *ip;                                                                                                 \
        if (nx_ == 0x92 || nx_ == 0x91) {                                                                              \
            int16_t o_ = (int16_t)(ip[1] | (ip[2] << 8));                                                              \
            sp -= 2;                                                                                                   \
            ip += 3;                                                                                                   \
            if (c_ == (nx_ == 0x91)) {                                                                                 \
                ip += o_;                                                                                              \
                if (o_ < 0) CHECK_INTERRUPTS();                                                                        \
            }                                                                                                          \
            NEXT;                                                                                                      \
        }                                                                                                              \
        *--sp = c_ ? true_oop : false_oop;                                                                             \
        NEXT;                                                                                                          \
    } while (0)
#define RET1(v)                                                                                                        \
    do {                                                                                                               \
        *--sp = (v);                                                                                                   \
        NEXT;                                                                                                          \
    } while (0)

    cstack_used = 0;
    nframes = 0;
    LOAD_CTX();
    NEXT;

op_bad:
    EXTERNALIZE();
    fatal("unknown bytecode 0x%02X at pc %ld", op, (long)(ip - bcs - 1));
op_push_temp:
    PUSH(fp[op & 15]);
    NEXT;
op_push_ivar:
    PUSH(slots(rcvr)[op & 15]);
    NEXT;
op_push_lit:
    PUSH(lits[op & 31]);
    NEXT;
op_push_litvar:
    PUSH(slots(lits[op & 31])[ASSOC_VALUE]);
    NEXT;
op_popstore_temp:
    fp[op & 7] = *sp--;
    NEXT;
op_push_self:
    PUSH(rcvr);
    NEXT;
op_push_true:
    PUSH(true_oop);
    NEXT;
op_push_false:
    PUSH(false_oop);
    NEXT;
op_push_nil:
    PUSH(nil_oop);
    NEXT;
op_push_zero:
    PUSH(int_oop(0));
    NEXT;
op_push_one:
    PUSH(int_oop(1));
    NEXT;
op_push_ctx:
    TO_CONTEXT();
    PUSH(active_ctx);
    SAVE_CTX();
    NEXT;
op_dup:
    sp[1] = sp[0];
    sp++;
    NEXT;
op_pop:
    sp--;
    NEXT;
op_push_temp_x:
    PUSH(fp[*ip++]);
    NEXT;
op_push_ivar_x:
    PUSH(slots(rcvr)[*ip++]);
    NEXT;
op_push_lit_x:
    PUSH(lits[*ip++]);
    NEXT;
op_push_litvar_x:
    PUSH(slots(lits[*ip++])[ASSOC_VALUE]);
    NEXT;
op_store_temp_x:
    fp[*ip++] = *sp;
    NEXT;
op_store_ivar_x: {
    int i = *ip++;
    if (is_immutable(rcvr)) {
        oop v = *sp;
        *sp = rcvr;
        PUSH(v);
        PUSH(int_oop(i + 1));
        sel = special(SO_SEL_ATTEMPTTOASSIGN);
        argc = 2;
        goto do_send;
    }
    store_ref(rcvr, (uint32_t)i, *sp);
    NEXT;
}
op_store_litvar_x:
    store_ref(lits[*ip++], ASSOC_VALUE, *sp);
    NEXT;
op_popstore_temp_x:
    fp[*ip++] = *sp--;
    NEXT;
op_popstore_litvar_x:
    store_ref(lits[*ip++], ASSOC_VALUE, *sp--);
    NEXT;
op_push_outer:
op_store_outer:
op_popstore_outer: {
    int d = ip[0], i = ip[1];
    ip += 2;
    oop cl = nframes ? frames[nframes - 1].closure : load_ref(active_ctx, CTX_CLOSURE);
    oop c = load_ref(cl, BC_OUTER);
    while (--d > 0) c = load_ref(load_ref(c, CTX_CLOSURE), BC_OUTER);
    if (op == 0x8A) PUSH(load_ref(c, CTX_FIXED + (uint32_t)i));
    else store_ref(c, CTX_FIXED + (uint32_t)i, op == 0x8B ? *sp : *sp--);
    NEXT;
}
op_jump: {
    int16_t o = INT16();
    ip += 2 + o;
    if (o < 0) CHECK_INTERRUPTS();
    NEXT;
}
op_jump_true:
op_jump_false: {
    oop v = *sp--;
    int16_t o = INT16();
    ip += 2;
    if (v == (op == 0x91 ? true_oop : false_oop)) {
        ip += o;
        if (o < 0) CHECK_INTERRUPTS();
    } else if (v != (op == 0x91 ? false_oop : true_oop)) {
        ip -= 3;
        PUSH(v);
        sel = special(SO_SEL_MUSTBEBOOLEAN);
        argc = 0;
        goto do_send;
    }
    NEXT;
}
op_push_int:
    PUSH(int_oop(INT16()));
    ip += 2;
    NEXT;
op_make_array: {
    int n = *ip++;
    EXTERNALIZE();
    oop a = alloc_obj(cls_array, F_VAR, (uint32_t)n);
    RELOAD();
    sp -= n;
    memcpy(slots(a), sp + 1, (size_t)n * sizeof(oop));
    remember_if_old(a);
    PUSH(a);
    NEXT;
}
op_closure: {
    int na = ip[0], nt = ip[1], fs = ip[2], size = (ip[3] << 8) | ip[4];
    ip += 5;
    TO_CONTEXT();
    SAVE_CTX();
    oop bc = cls_block;
    int64_t isize = int_val(load_ref(bc, BEH_FORMAT)) & CLS_INSTSIZE_MASK;
    oop b = alloc_obj(bc, F_FIXED, (uint32_t)(isize < 5 ? 5 : isize));
    LOAD_CTX();
    oop *s = slots(b);
    s[BC_OUTER] = active_ctx;
    s[BC_STARTPC] = int_oop(ip - bcs);
    s[BC_NUMARGS] = int_oop(na);
    s[BC_NUMTEMPS] = int_oop(nt);
    s[BC_FRAMESIZE] = int_oop(fs);
    remember_if_old(b);
    PUSH(b);
    ip += size;
    NEXT;
}
op_send:
    sel = lits[ip[0]];
    argc = ip[1];
    ip += 2;
    goto do_send;
op_send_short:
    sel = lits[op & 15];
    argc = (op - 0xC0) >> 4;
    goto do_send;
op_super_send:
    sel = lits[ip[0]];
    argc = ip[1];
    ip += 2;
    cls = load_ref(load_ref(method, CM_CLASS), BEH_SUPERCLASS);
    goto do_lookup;

    /* ---- special selectors: fast paths, else a normal send ---- */
    {
        oop a, b, f;
        int64_t r;
        double x, y;
    op_add:
        a = sp[-1], b = sp[0];
        if (is_int(a) && is_int(b) && !__builtin_add_overflow((int64_t)a, (int64_t)b - 1, &r)) RET1((oop)r);
        if (num_pair(a, b, &x, &y) && float_imm(x + y, &f)) RET1(f);
        goto op_special_send;
    op_sub:
        a = sp[-1], b = sp[0];
        if (is_int(a) && is_int(b) && !__builtin_sub_overflow((int64_t)a, (int64_t)b - 1, &r)) RET1((oop)r);
        if (num_pair(a, b, &x, &y) && float_imm(x - y, &f)) RET1(f);
        goto op_special_send;
    op_mul:
        a = sp[-1], b = sp[0];
        if (is_int(a) && is_int(b) && !__builtin_mul_overflow(int_val(a), int_val(b), &r) && int_fits(r)) RET1(int_oop(r));
        if (num_pair(a, b, &x, &y) && float_imm(x * y, &f)) RET1(f);
        goto op_special_send;
    op_div:
        a = sp[-1], b = sp[0];
        if (is_int(a) && is_int(b) && int_val(b) != 0 && int_val(a) % int_val(b) == 0 && int_fits(int_val(a) / int_val(b)))
            RET1(int_oop(int_val(a) / int_val(b)));
        if (num_pair(a, b, &x, &y) && y != 0.0 && float_imm(x / y, &f)) RET1(f);
        goto op_special_send;
#define COMPARE(OP)                                                                                                    \
    a = sp[-1], b = sp[0];                                                                                             \
    if (is_int(a) && is_int(b)) BOOL_RESULT((int64_t)a OP(int64_t) b);                                                 \
    if (num_pair(a, b, &x, &y)) BOOL_RESULT(x OP y);                                                                   \
    goto op_special_send
    op_lt:
        COMPARE(<);
    op_gt:
        COMPARE(>);
    op_le:
        COMPARE(<=);
    op_ge:
        COMPARE(>=);
    op_eq:
        COMPARE(==);
    op_ne:
        COMPARE(!=);
    op_mod:
        a = sp[-1], b = sp[0];
        if (is_int(a) && is_int(b) && int_val(b) != 0) RET1(int_oop(floor_mod(int_val(a), int_val(b))));
        goto op_special_send;
    op_floordiv:
        a = sp[-1], b = sp[0];
        if (is_int(a) && is_int(b) && int_val(b) != 0 && int_fits(floor_div(int_val(a), int_val(b))))
            RET1(int_oop(floor_div(int_val(a), int_val(b))));
        goto op_special_send;
    op_bitshift:
        a = sp[-1], b = sp[0];
        if (is_int(a) && is_int(b)) {
            int64_t v = int_val(a), s = int_val(b);
            if (s >= 0) {
                if (s < 62 && int_fits(v << s) && ((v << s) >> s) == v) RET1(int_oop(v << s));
                if (v == 0) RET1(a);
            } else {
                RET1(int_oop(s <= -63 ? (v < 0 ? -1 : 0) : v >> -s));
            }
        }
        goto op_special_send;
    op_bitand:
        a = sp[-1], b = sp[0];
        if (is_int(a) && is_int(b)) RET1(a & b);
        goto op_special_send;
    op_bitor:
        a = sp[-1], b = sp[0];
        if (is_int(a) && is_int(b)) RET1(a | b);
        goto op_special_send;
    op_identical:
        a = sp[-1], b = sp[0];
        BOOL_RESULT(a == b);
    op_not_identical:
        a = sp[-1], b = sp[0];
        BOOL_RESULT(a != b);
    op_at:
        a = sp[-1], b = sp[0];
        if (is_int(b) && is_ptr(a)) {
            oop c = raw_class(a);
            uint64_t k = (uint64_t)int_val(b) - 1;
            if (c == cls_array) {
                if (k < num_slots(a)) RET1(slots(a)[k]);
            } else if (c == cls_bytestring) {
                if (k < byte_size(a)) RET1(char_oop(bytes_of(a)[k]));
            } else if (c == cls_bytearray) {
                if (k < byte_size(a)) RET1(int_oop(bytes_of(a)[k]));
            }
        }
        goto op_special_send;
    op_at_put: {
        oop o = sp[-2], v = sp[0];
        a = sp[-1];
        if (is_int(a) && is_ptr(o) && !is_immutable(o)) {
            oop c = raw_class(o);
            uint64_t k = (uint64_t)int_val(a) - 1;
            if (c == cls_array && k < num_slots(o)) {
                store_ref(o, (uint32_t)k, v);
                goto ret_v3;
            } else if (c == cls_bytestring && is_char(v) && char_val(v) < 256 && k < byte_size(o)) {
                bytes_of(o)[k] = (uint8_t)char_val(v);
                goto ret_v3;
            } else if (c == cls_bytearray && is_int(v) && (uint64_t)int_val(v) < 256 && k < byte_size(o)) {
                bytes_of(o)[k] = (uint8_t)int_val(v);
                goto ret_v3;
            }
        }
        goto op_special_send;
    ret_v3:
        sp -= 2;
        *sp = v;
        NEXT;
    }
    op_size:
        b = sp[0];
        if (is_ptr(b)) {
            oop c = raw_class(b);
            if (c == cls_array) {
                *sp = int_oop(num_slots(b));
                NEXT;
            }
            if (c == cls_bytestring || c == cls_bytearray) {
                *sp = int_oop((int64_t)byte_size(b));
                NEXT;
            }
        }
        goto op_special_send;
    op_value: {
        int n = op == 0xB5 ? 0 : op == 0xB6 ? 1 : 2;
        oop bl = sp[-n];
        if (is_ptr(bl) && raw_class(bl) == cls_block && load_ref(bl, BC_NUMARGS) == int_oop(n)) {
            EXTERNALIZE();
            block_activate(n, false);
            LOAD_FRAME();
            CHECK_INTERRUPTS();
            NEXT;
        }
        goto op_special_send;
    }
    op_point_x:
    op_point_y:
        b = sp[0];
        if (is_ptr(b) && raw_class(b) == cls_point) {
            *sp = slots(b)[op - 0xBB];
            NEXT;
        }
        goto op_special_send;
    op_class:
        *sp = class_of(sp[0]);
        NEXT;
    op_special_send:
        sel = load_ref(special(SO_SPECIAL_SELECTORS), (uint32_t)(op - 0xA0));
        argc = special_argc[op - 0xA0];
        goto do_send;
    }

do_send:
    cls = class_of(sp[-argc]);
do_lookup: {
    cache_entry *e = &cache[CACHE_INDEX(cls, sel)];
    if (__builtin_expect(e->cls != cls || e->sel != sel, 0)) {
        e = fill_cache(cls, sel);
        if (!e) goto do_dnu;
    }
    oop m = e->method;
    uint8_t *mbcs = e->bcs;
    oop *mlits = e->lits;
    int32_t ntemps = e->ntemps, fsize = e->fsize;
    if (__builtin_expect(e->nset != 0, 0) && e->nset == argc) {
        oop r = sp[-argc];
        if (is_ptr(r) && r != active_ctx && !is_immutable(r) && format_of(r) <= F_FIXVAR) {
            uint32_t ns = num_slots(r);
            int ok = 1;
            for (int k = 0; k < argc; k++) ok &= e->set_ivar[k] < ns;
            if (ok) {
                for (int k = 0; k < argc; k++) store_ref(r, e->set_ivar[k], sp[-argc + 1 + k]);
                sp -= argc;
                NEXT;
            }
        }
    }
    if (__builtin_expect(e->quick >= 0, 0) && argc == 0) {
        oop r = sp[0];
        /* not the active Context: its pc and stack pointer live in registers until a real send saves them */
        if (is_ptr(r) && r != active_ctx && format_of(r) <= F_FIXVAR && num_slots(r) > (uint32_t)e->quick) {
            *sp = load_ref(r, (uint32_t)e->quick);
            NEXT;
        }
    }
    prim_status = PS_NONE;
    if (e->prim) {
        EXTERNALIZE();
        prim_nargs = argc;
        epoch = gc_epoch;
        vm_tmp_root[0] = m;
        e->prim();
        switch (prim_status) {
        case PS_OK:
            if (gc_epoch != epoch) RELOAD();
            sp -= argc;
            *sp = prim_result;
            prim_result = vm_tmp_root[0] = nil_oop;
            NEXT;
        case PS_SWITCHED:
            vm_tmp_root[0] = nil_oop;
            RELOAD();
            NEXT;
        case PS_RESEND:
            vm_tmp_root[0] = nil_oop;
            RELOAD();
            sel = resend_selector;
            argc = resend_argc;
            goto do_send;
        default:
            if (gc_epoch != epoch) RELOAD();
            m = vm_tmp_root[0];
            vm_tmp_root[0] = nil_oop;
            mbcs = bytes_of(load_ref(m, CM_BYTECODES));
            mlits = slots(load_ref(m, CM_LITERALS));
        }
    }

    /* activate m in a new frame */
    oop *nfp;
    if (nframes) {
        nfp = sp - argc + 1;
        if (__builtin_expect(nframes >= MAX_FRAMES || nfp + fsize + CTX_SLACK > CSTACK_END, 0)) {
            /* stack full: flush the frames into Contexts and start a new stack */
            SAVE_FRAME();
            vm_tmp_root[0] = m;
            materialize_all();
            m = vm_tmp_root[0];
            vm_tmp_root[0] = nil_oop;
            mbcs = bytes_of(load_ref(m, CM_BYTECODES));
            mlits = slots(load_ref(m, CM_LITERALS));
            LOAD_CTX();
            goto push_from_context;
        }
        frame_t *c = &frames[nframes - 1];
        c->pc = (int32_t)(ip - bcs);
        c->sp = (int32_t)(nfp - 1 - fp);
    } else {
    push_from_context: {
        oop *src = sp - argc;
        cstack[0] = src[0];
        for (int k = 1; k <= argc; k++) cstack[k] = src[k];
        sp = src - 1;
        SAVE_CTX();
        nfp = cstack + 1;
    }
    }
    frame_t *f = &frames[nframes++];
    f->method = m;
    f->closure = nil_oop;
    f->receiver = rcvr = nfp[-1];
    f->fp = fp = nfp;
    f->bcs = bcs = ip = mbcs;
    f->lits = lits = mlits;
    f->fsize = fsize;
    method = m;
    sp = nfp + argc - 1;
    for (int32_t k = 0; k < ntemps; k++) *++sp = nil_oop;
    if (__builtin_expect(prim_status == PS_FAIL, 0) && prim_error_code >= 0 && ntemps > 0 &&
        (method_prim(m) & CM_PRIM_ERROR_FLAG))
        nfp[argc] = int_oop(prim_error_code);
    CHECK_INTERRUPTS();
    NEXT;
}

do_dnu: {
    oop dnu = special(SO_SEL_DNU);
    if (sel == dnu) {
        EXTERNALIZE();
        oop msg = sp[0];
        fprintf(stderr, "samaltak: doesNotUnderstand: not understood (");
        print_class_name(stderr, cls);
        fputs(">>", stderr);
        print_symbol(stderr, is_ptr(msg) && num_slots(msg) > 0 ? load_ref(msg, MSG_SELECTOR) : nil_oop);
        fputs(")\n", stderr);
        fatal("recursive doesNotUnderstand:");
    }
    EXTERNALIZE();
    vm_tmp_root[1] = sel;
    vm_tmp_root[2] = cls;
    oop args = alloc_obj(cls_array, F_VAR, (uint32_t)argc);
    RELOAD();
    memcpy(slots(args), sp - argc + 1, (size_t)argc * sizeof(oop));
    remember_if_old(args);
    vm_tmp_root[3] = args;
    oop mc = cls_message;
    int64_t isize = int_val(load_ref(mc, BEH_FORMAT)) & CLS_INSTSIZE_MASK;
    oop msg = alloc_obj(mc, F_FIXED, (uint32_t)(isize < 2 ? 2 : isize));
    RELOAD();
    store_ref(msg, MSG_SELECTOR, vm_tmp_root[1]);
    store_ref(msg, MSG_ARGS, vm_tmp_root[3]);
    cls = vm_tmp_root[2];
    vm_tmp_root[1] = vm_tmp_root[2] = vm_tmp_root[3] = nil_oop;
    sp -= argc;
    PUSH(msg);
    sel = special(SO_SEL_DNU);
    argc = 1;
    goto do_lookup;
}

op_return_self:
    PUSH(rcvr);
op_return_top:
    result = *sp;
    if (nframes) {
        if (nframes > 1) {
            frame_t *f = &frames[--nframes];
            sp = f->fp - 1;
            *sp = result;
            f--;
            method = f->method;
            bcs = f->bcs;
            lits = f->lits;
            fp = f->fp;
            ip = bcs + f->pc;
            rcvr = f->receiver;
            NEXT;
        }
        if (!is_int(slots(active_ctx)[CTX_PC])) {
            /* returning into a dead Context: let the Context path send cannotReturn: */
            SAVE_FRAME();
            materialize_all();
            LOAD_CTX();
            goto context_return;
        }
        nframes = 0;
        cstack_used = 0;
        remember_if_old(active_ctx);
        LOAD_CTX();
        PUSH(result);
        NEXT;
    }
context_return: {
    oop *s = slots(active_ctx);
    oop sender = s[CTX_SENDER];
    if (sender == nil_oop || !is_int(slots(sender)[CTX_PC])) goto cannot_return;
    s[CTX_PC] = nil_oop;
    s[CTX_SENDER] = nil_oop;
    active_ctx = sender;
    remember_if_old(sender);
    LOAD_CTX();
    PUSH(result);
    NEXT;
}

op_nonlocal_return: {
    result = *sp;
    if (nframes) {
        /* The home Context is below the frames (the block's creation flushed them). Without an unwind marker on
           the way, drop the frames and return from home directly. */
        oop home = ctx_home(load_ref(frames[nframes - 1].closure, BC_OUTER));
        bool fast = is_int(load_ref(home, CTX_PC));
        for (int k = nframes - 1; fast && k >= 0; k--)
            if ((method_prim(frames[k].method) & CM_PRIM_MASK) == PRIM_ENSURE_MARKER) fast = false;
        oop c = active_ctx;
        for (; fast; c = load_ref(c, CTX_SENDER)) {
            if (c == nil_oop || (method_prim(load_ref(c, CTX_METHOD)) & CM_PRIM_MASK) == PRIM_ENSURE_MARKER) fast = false;
            else if (c == home) break;
        }
        oop hs = fast ? load_ref(home, CTX_SENDER) : nil_oop;
        if (!fast || hs == nil_oop || !is_int(load_ref(hs, CTX_PC))) {
            SAVE_FRAME();
            materialize_all();
            LOAD_CTX();
            goto context_nonlocal_return;
        }
        nframes = 0;
        cstack_used = 0;
        c = active_ctx;
        for (;;) {
            oop next = load_ref(c, CTX_SENDER);
            slots(c)[CTX_PC] = nil_oop;
            slots(c)[CTX_SENDER] = nil_oop;
            if (c == home) break;
            c = next;
        }
        active_ctx = hs;
        remember_if_old(hs);
        LOAD_CTX();
        PUSH(result);
        NEXT;
    }
context_nonlocal_return: {
    oop home = ctx_home(active_ctx);
    if (!is_int(load_ref(home, CTX_PC))) goto cannot_return;
    oop hs = load_ref(home, CTX_SENDER);
    if (hs == nil_oop || !is_int(load_ref(hs, CTX_PC))) goto cannot_return;
    oop c = active_ctx, marked = 0;
    for (;;) {
        if (c == nil_oop) goto cannot_return;
        if (!marked && (method_prim(load_ref(c, CTX_METHOD)) & CM_PRIM_MASK) == PRIM_ENSURE_MARKER) marked = c;
        if (c == home) break;
        c = load_ref(c, CTX_SENDER);
    }
    if (marked) {
        *sp = active_ctx;
        PUSH(result);
        PUSH(marked);
        sel = special(SO_SEL_ABOUTTORETURN);
        argc = 2;
        goto do_send;
    }
    c = active_ctx;
    for (;;) {
        oop next = load_ref(c, CTX_SENDER);
        slots(c)[CTX_PC] = nil_oop;
        slots(c)[CTX_SENDER] = nil_oop;
        if (c == home) break;
        c = next;
    }
    active_ctx = hs;
    remember_if_old(hs);
    LOAD_CTX();
    PUSH(result);
    NEXT;
}
}

cannot_return:
    *sp = active_ctx;
    PUSH(result);
    sel = special(SO_SEL_CANNOTRETURN);
    argc = 1;
    goto do_send;
}
