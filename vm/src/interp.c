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
int prim_status, prim_error_code, vm_prim_nargs;
oop *vm_prim_base;
static int64_t prim_base_index; /* of vm_prim_base in the active slots, to refresh it */
oop prim_result, resend_selector;
int resend_argc;

/* ---- frames ---- */

typedef struct {
    oop method, closure;           /* GC roots; closure is nil for method activations */
    oop *fp;                       /* first argument/temp in cstack; fp[-1] holds the receiver (as in a Context) */
    uint8_t *ip;                   /* saved when not executing; a pc offset (pc) during GC */
    oop *lits;                     /* refreshed after every GC */
    int32_t pc, sp;                /* sp: used slots from fp, saved when the frame is not executing */
    oop pad[2];                    /* 64-byte records */
} frame_t;
_Static_assert(sizeof(frame_t) == 64, "frame records are 64 bytes");

#define CSTACK_SLOTS (64 * 1024)
#define MAX_FRAMES CSTACK_SLOTS /* a frame takes at least one slot: the C stack fills up first */
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
    }
    for (size_t i = 0; i < cstack_used; i++) fn(&cstack[i]);
}

static void refresh_prim_base(void);

static inline uint8_t *method_bcs(oop m) { return bytes_of(load_ref(m, CM_BYTECODES)); }

/* frames hold raw pointers into their methods' bytecodes and literals: offsets while objects move */
void interp_before_gc(void)
{
    for (int i = 0; i < nframes; i++) frames[i].pc = (int32_t)(frames[i].ip - method_bcs(frames[i].method));
}

/* classes of immediates by tag (low 3 bits); 0 = object pointer */
static oop tag_class[8];

static void refresh_tag_classes(void)
{
    for (int t = 1; t < 8; t++) tag_class[t] = t & 1 ? cls_smallint : t == 2 ? cls_char : t == 4 ? cls_smallfloat : nil_oop;
}

static inline oop receiver_class(oop r) { return (r & 7) ? tag_class[r & 7] : raw_class(r); }

void interp_after_gc(void)
{
    refresh_tag_classes();
    refresh_prim_base();
    for (int i = 0; i < nframes; i++) {
        frames[i].ip = method_bcs(frames[i].method) + frames[i].pc;
        frames[i].lits = slots(load_ref(frames[i].method, CM_LITERALS));
    }
}

/* frameSize of a frame's method or block (at least its args and temps) */
static int64_t frame_size(frame_t *f)
{
    bool blk = f->closure != nil_oop;
    oop src = blk ? f->closure : f->method;
    int64_t fs = int_val(load_ref(src, blk ? BC_FRAMESIZE : CM_FRAMESIZE)),
            min = blk ? int_val(load_ref(src, BC_NUMARGS)) + int_val(load_ref(src, BC_NUMTEMPS))
                      : int_val(load_ref(src, CM_NUMARGS)) + int_val(load_ref(src, CM_NUMTEMPS));
    return fs > min ? fs : min;
}

bool interp_frames_valid(bool (*valid)(oop))
{
    for (int i = 0; i < nframes; i++)
        if (!valid(frames[i].method) || !valid(frames[i].closure)) return false;
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
        int32_t n = (int32_t)frame_size(&frames[i]) + CTX_SLACK;
        if (n < frames[i].sp) n = frames[i].sp;
        oop ctx = alloc_context((uint32_t)n);
        frame_t *f = &frames[i];
        oop *s = slots(ctx);
        s[CTX_SENDER] = active_ctx;
        s[CTX_PC] = int_oop(f->ip - method_bcs(f->method));
        s[CTX_STACKP] = int_oop(f->sp);
        s[CTX_METHOD] = f->method;
        s[CTX_CLOSURE] = f->closure;
        s[CTX_RECEIVER] = f->fp[-1];
        memcpy(s + CTX_FIXED, f->fp, (size_t)f->sp * sizeof(oop));
        remember_if_old(ctx);
        active_ctx = ctx;
    }
    nframes = 0;
    cstack_used = 0;
    refresh_prim_base();
    gc_epoch++; /* tells the interpreter to reload its registers */
}

/* ---- method cache ---- */

typedef struct {
    oop cls, sel;   /* key; in the inline cache, sel holds the send site (ip after the send bytecode) */
    oop method;
    union {
        prim_fn prim;
        oop qconst; /* K_CONST: the method only answers this constant (or self if 0): no frame (Squeak's quick returns) */
    };
    uint8_t *bcs; /* raw pointers into the method: valid until the next GC, which flushes the caches */
    oop *lits;
    int32_t ntemps, fsize;
    uint8_t kind;  /* 0: activate a frame; else K_PRIM, K_QUICK, K_SETTER, K_CONST bits */
    int8_t quick;  /* >= 0: the method is "^instVar quick" (push inst var quick, return top): answer that slot */
    uint8_t nset;  /* > 0: a setter, "ivar1 := arg1. ... ivarN := argN" (and ^self): stores the arguments */
    uint8_t set_ivar[4];
} cache_entry;
enum { K_PRIM = 1, K_QUICK = 2, K_SETTER = 4, K_CONST = 8, K_LEAF = 16 };
#define CACHE_SIZE 4096
static cache_entry cache[CACHE_SIZE];
#define CACHE_INDEX(c, s) ((((c) >> 3) ^ ((s) >> 3) ^ ((s) >> 12)) & (CACHE_SIZE - 1))
/* Monomorphic inline caches, one per send site (direct-mapped by the site's address), filled from the global cache.
   Sends whose selector a site does not determine (doesNotUnderstand:, perform:, cannotReturn:, aboutToReturn:)
   use the global cache only. */
#define ICACHE_SIZE 4096
static cache_entry icache[ICACHE_SIZE];
#define ICACHE_INDEX(site) ((((uintptr_t)(site)) ^ ((uintptr_t)(site) >> 12)) & (ICACHE_SIZE - 1))

void flush_method_cache(void)
{
    memset(cache, 0, sizeof cache);
    memset(icache, 0, sizeof icache);
}

void flush_method_cache_selector(oop sel)
{
    for (int i = 0; i < CACHE_SIZE; i++)
        if (cache[i].sel == sel) cache[i].cls = cache[i].sel = 0;
    memset(icache, 0, sizeof icache);
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
    prim_fn pf = (p && p != PRIM_ENSURE_MARKER && p != PRIM_ONDO_MARKER) ? prim_lookup(p) : NULL;
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
    /* "^self", "^true" / "^false" / "^nil" / "^0" / "^1", "^literal", "^smallInt": answer it without a frame */
    bool qc = false;
    oop qv = 0;
    if (!p && is_ptr(bc) && format_of(bc) >= F_BYTES) {
        uint8_t *b = bytes_of(bc);
        size_t n = byte_size(bc);
        oop lits = load_ref(m, CM_LITERALS);
        if (n == 1 && b[0] == 0x7A) qc = true;
        else if (n == 2 && b[1] == 0x79 && b[0] >= 0x71 && b[0] <= 0x75) {
            static const oop *consts[] = {&true_oop, &false_oop, &nil_oop};
            qv = b[0] <= 0x73 ? *consts[b[0] - 0x71] : int_oop(b[0] - 0x74);
            qc = true;
        } else if (n == 2 && b[1] == 0x79 && b[0] >= 0x20 && b[0] <= 0x3F && is_ptr(lits) && b[0] - 0x20u < num_slots(lits)) {
            qv = load_ref(lits, b[0] - 0x20u); /* the cache is flushed at every GC */
            qc = qv != 0;
        } else if (n == 4 && b[0] == 0x93 && b[3] == 0x79) {
            qv = int_oop((int16_t)(b[1] | (b[2] << 8)));
            qc = true;
        }
    }
    if (qc) e->qconst = qv;
    else e->prim = pf;
    e->kind = (pf ? K_PRIM : 0) | (pf && prim_is_leaf(pf) ? K_LEAF : 0) | (e->quick >= 0 ? K_QUICK : 0) |
              (e->nset ? K_SETTER : 0) | (qc ? K_CONST : 0);
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
    return nframes ? frame_size(&frames[nframes - 1]) + CTX_SLACK : (int64_t)num_slots(active_ctx) - CTX_FIXED;
}

#undef prim_argc
#undef prim_receiver
#undef prim_arg
int prim_argc(void) { return vm_prim_nargs; }
oop prim_receiver(void) { return vm_prim_base[0]; }
oop prim_arg(int i) { return vm_prim_base[1 + i]; }

oop *prim_stack_base(void) { return vm_prim_base; }

void set_prim_base(int argc)
{
    vm_prim_nargs = argc;
    prim_base_index = active_stackp() - 1 - argc;
    vm_prim_base = active_slots() + prim_base_index;
}

static void refresh_prim_base(void) { vm_prim_base = active_slots() + prim_base_index; }
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
    active_set_stackp(active_stackp() - vm_prim_nargs);
    vm_prim_nargs = 0;
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
        b[0] = load_ref(load_ref(cl, BC_OUTER), CTX_RECEIVER);
        if (from_array)
            for (int i = 0; i < argc; i++) nfp[i] = load_ref(arr, (uint32_t)i);
    } else {
        cstack[0] = load_ref(load_ref(cl, BC_OUTER), CTX_RECEIVER);
        for (int i = 0; i < argc; i++) cstack[1 + i] = from_array ? load_ref(arr, (uint32_t)i) : b[1 + i];
        ctx_set_stackp(active_ctx, base);
        nfp = cstack + 1;
    }
    oop outer = load_ref(cl, BC_OUTER), m = load_ref(outer, CTX_METHOD);
    frame_t *f = &frames[nframes++];
    f->method = m;
    f->closure = cl;
    f->fp = nfp;
    f->ip = method_bcs(m) + int_val(load_ref(cl, BC_STARTPC));
    f->lits = slots(load_ref(m, CM_LITERALS));
    f->sp = (int32_t)(argc + ntemps);
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
        if (depth <= 60 || i < 40 || i >= depth - 10) print_activation(f, frames[k].method, frames[k].fp[-1], frames[k].closure);
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

static inline int16_t read_int16(const uint8_t *p)
{
    int16_t v;
    memcpy(&v, p, 2); /* little-endian */
    return v;
}

/* Registers: ip, sp, fp (args/temps; fp[-1] is the receiver, in a frame as in a Context) and lits. */
void interpret(void)
{
    static void *ops[256];
    uint8_t *ip;
    oop *sp, *fp, *lits, sel, cls, result;
    frame_t *fr; /* the top frame, NULL when executing active_ctx; nframes is synced when externalizing */
    int argc;
    uint64_t epoch;

    if (!ops[0]) {
        for (int i = 0; i < 256; i++) ops[i] = &&op_bad;
        ops[0x00] = &&op_push_temp_0;
        ops[0x01] = &&op_push_temp_1;
        ops[0x02] = &&op_push_temp_2;
        ops[0x03] = &&op_push_temp_3;
        ops[0x04] = &&op_push_temp_4;
        ops[0x05] = &&op_push_temp_5;
        ops[0x06] = &&op_push_temp_6;
        ops[0x07] = &&op_push_temp_7;
        ops[0x08] = &&op_push_temp_8;
        ops[0x09] = &&op_push_temp_9;
        ops[0x0A] = &&op_push_temp_10;
        ops[0x0B] = &&op_push_temp_11;
        ops[0x0C] = &&op_push_temp_12;
        ops[0x0D] = &&op_push_temp_13;
        ops[0x0E] = &&op_push_temp_14;
        ops[0x0F] = &&op_push_temp_15;
        ops[0x10] = &&op_push_ivar_0;
        ops[0x11] = &&op_push_ivar_1;
        ops[0x12] = &&op_push_ivar_2;
        ops[0x13] = &&op_push_ivar_3;
        ops[0x14] = &&op_push_ivar_4;
        ops[0x15] = &&op_push_ivar_5;
        ops[0x16] = &&op_push_ivar_6;
        ops[0x17] = &&op_push_ivar_7;
        ops[0x18] = &&op_push_ivar_8;
        ops[0x19] = &&op_push_ivar_9;
        ops[0x1A] = &&op_push_ivar_10;
        ops[0x1B] = &&op_push_ivar_11;
        ops[0x1C] = &&op_push_ivar_12;
        ops[0x1D] = &&op_push_ivar_13;
        ops[0x1E] = &&op_push_ivar_14;
        ops[0x1F] = &&op_push_ivar_15;
        ops[0x20] = &&op_push_lit_0;
        ops[0x21] = &&op_push_lit_1;
        ops[0x22] = &&op_push_lit_2;
        ops[0x23] = &&op_push_lit_3;
        ops[0x24] = &&op_push_lit_4;
        ops[0x25] = &&op_push_lit_5;
        ops[0x26] = &&op_push_lit_6;
        ops[0x27] = &&op_push_lit_7;
        ops[0x28] = &&op_push_lit_8;
        ops[0x29] = &&op_push_lit_9;
        ops[0x2A] = &&op_push_lit_10;
        ops[0x2B] = &&op_push_lit_11;
        ops[0x2C] = &&op_push_lit_12;
        ops[0x2D] = &&op_push_lit_13;
        ops[0x2E] = &&op_push_lit_14;
        ops[0x2F] = &&op_push_lit_15;
        ops[0x30] = &&op_push_lit_16;
        ops[0x31] = &&op_push_lit_17;
        ops[0x32] = &&op_push_lit_18;
        ops[0x33] = &&op_push_lit_19;
        ops[0x34] = &&op_push_lit_20;
        ops[0x35] = &&op_push_lit_21;
        ops[0x36] = &&op_push_lit_22;
        ops[0x37] = &&op_push_lit_23;
        ops[0x38] = &&op_push_lit_24;
        ops[0x39] = &&op_push_lit_25;
        ops[0x3A] = &&op_push_lit_26;
        ops[0x3B] = &&op_push_lit_27;
        ops[0x3C] = &&op_push_lit_28;
        ops[0x3D] = &&op_push_lit_29;
        ops[0x3E] = &&op_push_lit_30;
        ops[0x3F] = &&op_push_lit_31;
        ops[0x40] = &&op_push_litvar_0;
        ops[0x41] = &&op_push_litvar_1;
        ops[0x42] = &&op_push_litvar_2;
        ops[0x43] = &&op_push_litvar_3;
        ops[0x44] = &&op_push_litvar_4;
        ops[0x45] = &&op_push_litvar_5;
        ops[0x46] = &&op_push_litvar_6;
        ops[0x47] = &&op_push_litvar_7;
        ops[0x48] = &&op_push_litvar_8;
        ops[0x49] = &&op_push_litvar_9;
        ops[0x4A] = &&op_push_litvar_10;
        ops[0x4B] = &&op_push_litvar_11;
        ops[0x4C] = &&op_push_litvar_12;
        ops[0x4D] = &&op_push_litvar_13;
        ops[0x4E] = &&op_push_litvar_14;
        ops[0x4F] = &&op_push_litvar_15;
        ops[0x50] = &&op_push_litvar_16;
        ops[0x51] = &&op_push_litvar_17;
        ops[0x52] = &&op_push_litvar_18;
        ops[0x53] = &&op_push_litvar_19;
        ops[0x54] = &&op_push_litvar_20;
        ops[0x55] = &&op_push_litvar_21;
        ops[0x56] = &&op_push_litvar_22;
        ops[0x57] = &&op_push_litvar_23;
        ops[0x58] = &&op_push_litvar_24;
        ops[0x59] = &&op_push_litvar_25;
        ops[0x5A] = &&op_push_litvar_26;
        ops[0x5B] = &&op_push_litvar_27;
        ops[0x5C] = &&op_push_litvar_28;
        ops[0x5D] = &&op_push_litvar_29;
        ops[0x5E] = &&op_push_litvar_30;
        ops[0x5F] = &&op_push_litvar_31;
        ops[0x60] = &&op_popstore_temp_0;
        ops[0x61] = &&op_popstore_temp_1;
        ops[0x62] = &&op_popstore_temp_2;
        ops[0x63] = &&op_popstore_temp_3;
        ops[0x64] = &&op_popstore_temp_4;
        ops[0x65] = &&op_popstore_temp_5;
        ops[0x66] = &&op_popstore_temp_6;
        ops[0x67] = &&op_popstore_temp_7;
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
        ops[0x97] = &&op_push2_send_tt;
        ops[0x98] = &&op_push2_send_tl;
        ops[0x99] = &&op_push2_send_ti;
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
        oop *s_ = slots(active_ctx), m_ = s_[CTX_METHOD];                                                              \
        lits = slots(slots(m_)[CM_LITERALS]);                                                                          \
        fp = s_ + CTX_FIXED;                                                                                           \
        sp = fp + int_val(s_[CTX_STACKP]) - 1;                                                                         \
        if (!is_int(s_[CTX_PC])) fatal("resuming a dead context");                                                     \
        ip = method_bcs(m_) + int_val(s_[CTX_PC]);                                                                     \
        fr = NULL;                                                                                                     \
    } while (0)
#define SAVE_CTX()                                                                                                     \
    do {                                                                                                               \
        oop *s_ = slots(active_ctx);                                                                                   \
        s_[CTX_PC] = int_oop(ip - method_bcs(s_[CTX_METHOD]));                                                         \
        s_[CTX_STACKP] = int_oop(sp - fp + 1);                                                                         \
    } while (0)
#define LOAD_FRAME()                                                                                                   \
    do {                                                                                                               \
        frame_t *f_ = fr = &frames[nframes - 1];                                                                       \
        lits = f_->lits;                                                                                               \
        fp = f_->fp;                                                                                                   \
        sp = fp + f_->sp - 1;                                                                                          \
        ip = f_->ip;                                                                                                   \
    } while (0)
#define SAVE_FRAME()                                                                                                   \
    do {                                                                                                               \
        frame_t *f_ = fr;                                                                                              \
        nframes = (int)(fr - frames) + 1;                                                                              \
        f_->ip = ip;                                                                                                   \
        f_->sp = (int32_t)(sp - fp + 1);                                                                               \
        cstack_used = (size_t)(sp + 1 - cstack);                                                                       \
    } while (0)
#define EXTERNALIZE()                                                                                                  \
    do {                                                                                                               \
        if (fr) SAVE_FRAME();                                                                                          \
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
        if (fr) {                                                                                                      \
            SAVE_FRAME();                                                                                              \
            materialize_all();                                                                                         \
            LOAD_CTX();                                                                                                \
        }                                                                                                              \
    } while (0)
#define NEXT goto *ops[*ip++]
#define PUSH(v) (*++sp = (v))
#define POP() (sp--)
/* Superinstructions (decided at dispatch time; methods keep their bytecodes): a push followed by + - < > <= >=
 * on two SmallIntegers computes right away, and its result goes straight into a following pop-store temp or
 * conditional jump. Straight-line code: each fusion saves whole dispatches. */
#define PUSH_FUSED(v)                                                                                                  \
    do {                                                                                                               \
        oop b_ = (v), a_ = *sp;                                                                                        \
        unsigned nx_ = (unsigned)*ip - 0xA0;                                                                           \
        if (nx_ < 6 && is_int(a_ & b_)) {                                                                     \
            if (nx_ < 2) {                                                                                             \
                int64_t r_;                                                                                            \
                if (!(nx_ ? __builtin_sub_overflow((int64_t)a_, (int64_t)b_ - 1, &r_)                                  \
                          : __builtin_add_overflow((int64_t)a_, (int64_t)b_ - 1, &r_))) {                              \
                    int n_ = *++ip;                                                                                    \
                    if ((n_ & 0xF8) == 0x60) {                                                                         \
                        fp[n_ & 7] = (oop)r_;                                                                          \
                        sp--;                                                                                          \
                        ip++;                                                                                          \
                        NEXT;                                                                                          \
                    }                                                                                                  \
                    *sp = (oop)r_;                                                                                     \
                    NEXT;                                                                                              \
                }                                                                                                      \
            } else {                                                                                                   \
                int64_t x_ = (int64_t)a_, y_ = (int64_t)b_;                                                            \
                bool c_ = nx_ == 2 ? x_ < y_ : nx_ == 3 ? x_ > y_ : nx_ == 4 ? x_ <= y_ : x_ >= y_;                     \
                int j_ = *++ip;                                                                                        \
                if (j_ == 0x92 || j_ == 0x91) {                                                                        \
                    int16_t o_ = read_int16(ip + 1);                                                                   \
                    sp--;                                                                                              \
                    ip += 3;                                                                                           \
                    if (c_ == (j_ == 0x91)) {                                                                          \
                        ip += o_;                                                                                      \
                        if (o_ < 0) CHECK_INTERRUPTS();                                                                \
                    }                                                                                                  \
                    NEXT;                                                                                              \
                }                                                                                                      \
                *sp = c_ ? true_oop : false_oop;                                                                       \
                NEXT;                                                                                                  \
            }                                                                                                          \
        }                                                                                                              \
        *++sp = b_;                                                                                                    \
        NEXT;                                                                                                          \
    } while (0)
#define CHECK_INTERRUPTS()                                                                                             \
    do {                                                                                                               \
        if (__builtin_expect(atomic_load_explicit(&interrupt_pending, memory_order_relaxed), 0)) {                     \
            EXTERNALIZE();                                                                                             \
            handle_interrupts();                                                                                       \
            RELOAD();                                                                                                  \
        }                                                                                                              \
    } while (0)
#define INT16() read_int16(ip)
/* A comparison followed by a conditional jump branches directly (the Boolean is never pushed). */
#define BOOL_RESULT(c)                                                                                                 \
    do {                                                                                                               \
        bool c_ = (c);                                                                                                 \
        int nx_ = *ip;                                                                                                 \
        if (nx_ == 0x92 || nx_ == 0x91) {                                                                              \
            int16_t o_ = read_int16(ip + 1);                                                                           \
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
/* replace the two operands by v; "r := a op b" stores into the temp directly */
#define RET1(v)                                                                                                        \
    do {                                                                                                               \
        oop v_ = (v);                                                                                                  \
        int nx_ = *ip;                                                                                                 \
        if ((nx_ & 0xF8) == 0x60) {                                                                                    \
            fp[nx_ & 7] = v_;                                                                                          \
            sp -= 2;                                                                                                   \
            ip++;                                                                                                      \
            NEXT;                                                                                                      \
        }                                                                                                              \
        *--sp = v_;                                                                                                    \
        NEXT;                                                                                                          \
    } while (0)

    cstack_used = 0;
    nframes = 0;
    refresh_tag_classes();
    LOAD_CTX();
    NEXT;

op_bad:
    EXTERNALIZE();
    fatal("unknown bytecode 0x%02X", ip[-1]);
    /* per-index handlers: the slot offset is an immediate */
op_push_temp_0:
    PUSH(fp[0]);
    NEXT;
op_push_temp_1:
    PUSH(fp[1]);
    NEXT;
op_push_temp_2:
    PUSH(fp[2]);
    NEXT;
op_push_temp_3:
    PUSH(fp[3]);
    NEXT;
op_push_temp_4:
    PUSH(fp[4]);
    NEXT;
op_push_temp_5:
    PUSH(fp[5]);
    NEXT;
op_push_temp_6:
    PUSH(fp[6]);
    NEXT;
op_push_temp_7:
    PUSH(fp[7]);
    NEXT;
op_push_temp_8:
    PUSH(fp[8]);
    NEXT;
op_push_temp_9:
    PUSH(fp[9]);
    NEXT;
op_push_temp_10:
    PUSH(fp[10]);
    NEXT;
op_push_temp_11:
    PUSH(fp[11]);
    NEXT;
op_push_temp_12:
    PUSH(fp[12]);
    NEXT;
op_push_temp_13:
    PUSH(fp[13]);
    NEXT;
op_push_temp_14:
    PUSH(fp[14]);
    NEXT;
op_push_temp_15:
    PUSH(fp[15]);
    NEXT;
op_push_ivar_0:
    PUSH(slots(fp[-1])[0]);
    NEXT;
op_push_ivar_1:
    PUSH(slots(fp[-1])[1]);
    NEXT;
op_push_ivar_2:
    PUSH(slots(fp[-1])[2]);
    NEXT;
op_push_ivar_3:
    PUSH(slots(fp[-1])[3]);
    NEXT;
op_push_ivar_4:
    PUSH(slots(fp[-1])[4]);
    NEXT;
op_push_ivar_5:
    PUSH(slots(fp[-1])[5]);
    NEXT;
op_push_ivar_6:
    PUSH(slots(fp[-1])[6]);
    NEXT;
op_push_ivar_7:
    PUSH(slots(fp[-1])[7]);
    NEXT;
op_push_ivar_8:
    PUSH(slots(fp[-1])[8]);
    NEXT;
op_push_ivar_9:
    PUSH(slots(fp[-1])[9]);
    NEXT;
op_push_ivar_10:
    PUSH(slots(fp[-1])[10]);
    NEXT;
op_push_ivar_11:
    PUSH(slots(fp[-1])[11]);
    NEXT;
op_push_ivar_12:
    PUSH(slots(fp[-1])[12]);
    NEXT;
op_push_ivar_13:
    PUSH(slots(fp[-1])[13]);
    NEXT;
op_push_ivar_14:
    PUSH(slots(fp[-1])[14]);
    NEXT;
op_push_ivar_15:
    PUSH(slots(fp[-1])[15]);
    NEXT;
op_push_lit_0:
    PUSH(lits[0]);
    NEXT;
op_push_lit_1:
    PUSH(lits[1]);
    NEXT;
op_push_lit_2:
    PUSH(lits[2]);
    NEXT;
op_push_lit_3:
    PUSH(lits[3]);
    NEXT;
op_push_lit_4:
    PUSH(lits[4]);
    NEXT;
op_push_lit_5:
    PUSH(lits[5]);
    NEXT;
op_push_lit_6:
    PUSH(lits[6]);
    NEXT;
op_push_lit_7:
    PUSH(lits[7]);
    NEXT;
op_push_lit_8:
    PUSH(lits[8]);
    NEXT;
op_push_lit_9:
    PUSH(lits[9]);
    NEXT;
op_push_lit_10:
    PUSH(lits[10]);
    NEXT;
op_push_lit_11:
    PUSH(lits[11]);
    NEXT;
op_push_lit_12:
    PUSH(lits[12]);
    NEXT;
op_push_lit_13:
    PUSH(lits[13]);
    NEXT;
op_push_lit_14:
    PUSH(lits[14]);
    NEXT;
op_push_lit_15:
    PUSH(lits[15]);
    NEXT;
op_push_lit_16:
    PUSH(lits[16]);
    NEXT;
op_push_lit_17:
    PUSH(lits[17]);
    NEXT;
op_push_lit_18:
    PUSH(lits[18]);
    NEXT;
op_push_lit_19:
    PUSH(lits[19]);
    NEXT;
op_push_lit_20:
    PUSH(lits[20]);
    NEXT;
op_push_lit_21:
    PUSH(lits[21]);
    NEXT;
op_push_lit_22:
    PUSH(lits[22]);
    NEXT;
op_push_lit_23:
    PUSH(lits[23]);
    NEXT;
op_push_lit_24:
    PUSH(lits[24]);
    NEXT;
op_push_lit_25:
    PUSH(lits[25]);
    NEXT;
op_push_lit_26:
    PUSH(lits[26]);
    NEXT;
op_push_lit_27:
    PUSH(lits[27]);
    NEXT;
op_push_lit_28:
    PUSH(lits[28]);
    NEXT;
op_push_lit_29:
    PUSH(lits[29]);
    NEXT;
op_push_lit_30:
    PUSH(lits[30]);
    NEXT;
op_push_lit_31:
    PUSH(lits[31]);
    NEXT;
op_push_litvar_0:
    PUSH(slots(lits[0])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_1:
    PUSH(slots(lits[1])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_2:
    PUSH(slots(lits[2])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_3:
    PUSH(slots(lits[3])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_4:
    PUSH(slots(lits[4])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_5:
    PUSH(slots(lits[5])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_6:
    PUSH(slots(lits[6])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_7:
    PUSH(slots(lits[7])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_8:
    PUSH(slots(lits[8])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_9:
    PUSH(slots(lits[9])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_10:
    PUSH(slots(lits[10])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_11:
    PUSH(slots(lits[11])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_12:
    PUSH(slots(lits[12])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_13:
    PUSH(slots(lits[13])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_14:
    PUSH(slots(lits[14])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_15:
    PUSH(slots(lits[15])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_16:
    PUSH(slots(lits[16])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_17:
    PUSH(slots(lits[17])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_18:
    PUSH(slots(lits[18])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_19:
    PUSH(slots(lits[19])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_20:
    PUSH(slots(lits[20])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_21:
    PUSH(slots(lits[21])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_22:
    PUSH(slots(lits[22])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_23:
    PUSH(slots(lits[23])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_24:
    PUSH(slots(lits[24])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_25:
    PUSH(slots(lits[25])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_26:
    PUSH(slots(lits[26])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_27:
    PUSH(slots(lits[27])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_28:
    PUSH(slots(lits[28])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_29:
    PUSH(slots(lits[29])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_30:
    PUSH(slots(lits[30])[ASSOC_VALUE]);
    NEXT;
op_push_litvar_31:
    PUSH(slots(lits[31])[ASSOC_VALUE]);
    NEXT;
op_popstore_temp_0:
    fp[0] = *sp--;
    NEXT;
op_popstore_temp_1:
    fp[1] = *sp--;
    NEXT;
op_popstore_temp_2:
    fp[2] = *sp--;
    NEXT;
op_popstore_temp_3:
    fp[3] = *sp--;
    NEXT;
op_popstore_temp_4:
    fp[4] = *sp--;
    NEXT;
op_popstore_temp_5:
    fp[5] = *sp--;
    NEXT;
op_popstore_temp_6:
    fp[6] = *sp--;
    NEXT;
op_popstore_temp_7:
    fp[7] = *sp--;
    NEXT;
op_push_self:
    PUSH(fp[-1]);
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
    PUSH_FUSED(int_oop(1));
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
    POP();
    NEXT;
op_push_temp_x:
    PUSH(fp[*ip++]);
    NEXT;
op_push_ivar_x:
    PUSH(slots(fp[-1])[*ip++]);
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
    oop r = fp[-1];
    if (is_immutable(r)) {
        oop v = *sp;
        *sp = r;
        PUSH(v);
        PUSH(int_oop(i + 1));
        sel = special(SO_SEL_ATTEMPTTOASSIGN);
        argc = 2;
        goto do_send;
    }
    store_ref(r, (uint32_t)i, *sp);
    NEXT;
}
op_store_litvar_x:
    store_ref(lits[*ip++], ASSOC_VALUE, *sp);
    NEXT;
op_popstore_temp_x:
    fp[*ip++] = *sp;
    POP();
    NEXT;
op_popstore_litvar_x:
    store_ref(lits[*ip++], ASSOC_VALUE, *sp);
    POP();
    NEXT;
op_push_outer:
op_store_outer:
op_popstore_outer: {
    int op = ip[-1], d = ip[0], i = ip[1];
    ip += 2;
    oop cl = fr ? fr->closure : load_ref(active_ctx, CTX_CLOSURE);
    oop c = load_ref(cl, BC_OUTER);
    while (--d > 0) c = load_ref(load_ref(c, CTX_CLOSURE), BC_OUTER);
    if (op == 0x8A) {
        PUSH(load_ref(c, CTX_FIXED + (uint32_t)i));
    } else {
        store_ref(c, CTX_FIXED + (uint32_t)i, *sp);
        if (op == 0x8C) POP();
    }
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
    int op = ip[-1];
    oop v = *sp;
    POP();
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
op_push_int: {
    oop v_ = int_oop(INT16());
    ip += 2;
    PUSH_FUSED(v_);
}
    /* push temp a, push temp b | literal b | SmallInteger b (signed byte), then the special-selector bytecode op
       (compiler-chosen superinstructions: 0x97 a b op, 0x98 a b op, 0x99 a b op) */
op_push2_send_tt:
    sp[1] = fp[ip[0]];
    sp[2] = fp[ip[1]];
    goto push2_send;
op_push2_send_tl:
    sp[1] = fp[ip[0]];
    sp[2] = lits[ip[1]];
    goto push2_send;
op_push2_send_ti:
    sp[1] = fp[ip[0]];
    sp[2] = int_oop((int8_t)ip[1]);
push2_send:
    sp += 2;
    ip += 3;
    goto *ops[ip[-1]];
op_make_array: {
    int n = *ip++;
    EXTERNALIZE();
    oop a = alloc_obj(cls_array, F_VAR, (uint32_t)n);
    RELOAD();
    sp -= n;
    memcpy(slots(a), sp + 1, (size_t)n * sizeof(oop));
    remember_if_old(a);
    *++sp = a;
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
    s[BC_STARTPC] = int_oop(ip - method_bcs(load_ref(active_ctx, CTX_METHOD)));
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
    sel = lits[ip[-1] & 15];
    argc = (ip[-1] - 0xC0) >> 4;
    goto do_send;
op_super_send:
    sel = lits[ip[0]];
    argc = ip[1];
    ip += 2;
    cls = load_ref(load_ref(fr ? fr->method : load_ref(active_ctx, CTX_METHOD), CM_CLASS),
                   BEH_SUPERCLASS);
    goto do_site_lookup;

    /* ---- special selectors: fast paths, else a normal send ---- */
    {
        oop a, b, f;
        int64_t r;
        double x, y;
    op_add:
        a = sp[-1], b = *sp;
        if (is_int(a & b) && !__builtin_add_overflow((int64_t)a, (int64_t)b - 1, &r)) RET1((oop)r);
        if (num_pair(a, b, &x, &y) && float_imm(x + y, &f)) RET1(f);
        goto op_special_send;
    op_sub:
        a = sp[-1], b = *sp;
        if (is_int(a & b) && !__builtin_sub_overflow((int64_t)a, (int64_t)b - 1, &r)) RET1((oop)r);
        if (num_pair(a, b, &x, &y) && float_imm(x - y, &f)) RET1(f);
        goto op_special_send;
    op_mul:
        a = sp[-1], b = *sp;
        if (is_int(a & b) && !__builtin_mul_overflow(int_val(a), int_val(b), &r) && int_fits(r)) RET1(int_oop(r));
        if (num_pair(a, b, &x, &y) && float_imm(x * y, &f)) RET1(f);
        goto op_special_send;
    op_div:
        a = sp[-1], b = *sp;
        if (is_int(a & b) && int_val(b) != 0 && int_val(a) % int_val(b) == 0 && int_fits(int_val(a) / int_val(b)))
            RET1(int_oop(int_val(a) / int_val(b)));
        if (num_pair(a, b, &x, &y) && y != 0.0 && float_imm(x / y, &f)) RET1(f);
        goto op_special_send;
#define COMPARE(OP)                                                                                                    \
    a = sp[-1], b = *sp;                                                                                               \
    if (is_int(a & b)) BOOL_RESULT((int64_t)a OP(int64_t) b);                                                 \
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
        a = sp[-1], b = *sp;
        if (is_int(a & b) && int_val(b) != 0) RET1(int_oop(floor_mod(int_val(a), int_val(b))));
        goto op_special_send;
    op_floordiv:
        a = sp[-1], b = *sp;
        if (is_int(a & b) && int_val(b) != 0 && int_fits(floor_div(int_val(a), int_val(b))))
            RET1(int_oop(floor_div(int_val(a), int_val(b))));
        goto op_special_send;
    op_bitshift:
        a = sp[-1], b = *sp;
        if (is_int(a & b)) {
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
        a = sp[-1], b = *sp;
        if (is_int(a & b)) RET1(a & b);
        goto op_special_send;
    op_bitor:
        a = sp[-1], b = *sp;
        if (is_int(a & b)) RET1(a | b);
        goto op_special_send;
    op_identical:
        a = sp[-1], b = *sp;
        BOOL_RESULT(a == b);
    op_not_identical:
        a = sp[-1], b = *sp;
        BOOL_RESULT(a != b);
    op_at:
        a = sp[-1], b = *sp;
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
        oop o = sp[-2], v = *sp;
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
        b = *sp;
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
        int op = ip[-1], n = op == 0xB5 ? 0 : op == 0xB6 ? 1 : 2;
        oop bl = n ? sp[-n] : *sp;
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
        b = *sp;
        if (is_ptr(b) && raw_class(b) == cls_point) {
            *sp = slots(b)[ip[-1] - 0xBB];
            NEXT;
        }
        goto op_special_send;
    op_class: {
        oop r_ = *sp;
        *sp = (r_ & 7) == 0 ? raw_class(r_) : (r_ & 1) ? cls_smallint : class_of(r_);
        NEXT;
    }
    op_special_send:
        sel = load_ref(special(SO_SPECIAL_SELECTORS), (uint32_t)(ip[-1] - 0xA0));
        argc = special_argc[ip[-1] - 0xA0];
        goto do_send;
    }

do_send: {
    oop r_ = sp[-argc];
    cls = receiver_class(r_);
}
    {
    cache_entry *e;
do_site_lookup:
    e = &icache[ICACHE_INDEX(ip)];
    if (__builtin_expect(e->cls != cls || e->sel != (oop)ip, 0)) {
        cache_entry *g = &cache[CACHE_INDEX(cls, sel)];
        if (g->cls != cls || g->sel != sel) {
            g = fill_cache(cls, sel);
            if (!g) goto do_dnu;
        }
        *e = *g;
        e->sel = (oop)ip;
    }
    goto have_entry;
do_send_global: {
    oop r_ = sp[-argc];
    cls = receiver_class(r_);
}
do_lookup:
    e = &cache[CACHE_INDEX(cls, sel)];
    if (__builtin_expect(e->cls != cls || e->sel != sel, 0)) {
        e = fill_cache(cls, sel);
        if (!e) goto do_dnu;
    }
have_entry:;
    oop m = e->method;
    uint8_t *mbcs = e->bcs;
    oop *mlits = e->lits;
    int32_t ntemps = e->ntemps, fsize = e->fsize;
    int ecode = -1; /* error code for the method's ec temp after its primitive failed */
    if (__builtin_expect(e->kind == 0, 1)) goto activate;
    if (e->kind & K_LEAF) {
        /* no allocation, no GC: the registers stay valid */
        vm_prim_nargs = argc;
        vm_prim_base = sp - argc;
        prim_status = PS_NONE;
        e->prim();
        if (__builtin_expect(prim_status == PS_OK, 1)) {
            sp -= argc;
            *sp = prim_result;
            prim_result = nil_oop;
            NEXT;
        }
        if (prim_error_code >= 0 && ntemps > 0 && (method_prim(m) & CM_PRIM_ERROR_FLAG)) ecode = prim_error_code;
        goto activate;
    }
    if (e->kind & K_CONST) {
        oop v = e->qconst ? e->qconst : sp[-argc];
        sp -= argc;
        *sp = v;
        CHECK_INTERRUPTS();
        NEXT;
    }
    if (e->nset == argc && argc) {
        oop r = sp[-argc];
        if (is_ptr(r) && r != active_ctx && !is_immutable(r) && format_of(r) <= F_FIXVAR) {
            uint32_t ns = num_slots(r);
            int ok = 1;
            for (int k = 0; k < argc; k++) ok &= e->set_ivar[k] < ns;
            if (ok) {
                for (int k = 0; k < argc; k++) store_ref(r, e->set_ivar[k], sp[-argc + 1 + k]);
                sp -= argc;
                *sp = r;
                CHECK_INTERRUPTS();
                NEXT;
            }
        }
    }
    if (e->quick >= 0 && argc == 0) {
        oop r = *sp;
        /* not the active Context: its pc and stack pointer live in registers until a real send saves them */
        if (is_ptr(r) && r != active_ctx && format_of(r) <= F_FIXVAR && num_slots(r) > (uint32_t)e->quick) {
            *sp = load_ref(r, (uint32_t)e->quick);
            CHECK_INTERRUPTS();
            NEXT;
        }
    }
    prim_status = PS_NONE;
    if (e->prim) {
        EXTERNALIZE();
        vm_prim_nargs = argc;
        vm_prim_base = sp - argc;
        prim_base_index = vm_prim_base - fp;
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
            goto do_send_global;
        default:
            if (gc_epoch != epoch) RELOAD();
            m = vm_tmp_root[0];
            vm_tmp_root[0] = nil_oop;
            mbcs = bytes_of(load_ref(m, CM_BYTECODES));
            mlits = slots(load_ref(m, CM_LITERALS));
            if (prim_error_code >= 0 && ntemps > 0 && (method_prim(m) & CM_PRIM_ERROR_FLAG)) ecode = prim_error_code;
        }
    }

activate:;
    /* activate m in a new frame; receiver and arguments are in memory at sp - argc .. sp */
    oop *nfp;
    if (fr) {
        nfp = sp - argc + 1;
        if (__builtin_expect(nfp + fsize > CSTACK_END - CTX_SLACK, 0)) {
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
        fr->ip = ip;
        fr->sp = (int32_t)(nfp - 1 - fp);
        fr++;
    } else {
    push_from_context: {
        oop *src = sp - argc;
        cstack[0] = src[0];
        for (int k = 1; k <= argc; k++) cstack[k] = src[k];
        sp = src - 1;
        SAVE_CTX();
        nfp = cstack + 1;
        fr = frames;
    }
    }
    frame_t *f = fr;
    f->method = m;
    f->closure = nil_oop;
    f->fp = fp = nfp;
    ip = mbcs;
    f->lits = lits = mlits;
    sp = nfp + argc - 1;
    for (int32_t k = 0; k < ntemps; k++) *++sp = nil_oop;
    if (__builtin_expect(ecode >= 0, 0)) nfp[argc] = int_oop(ecode);
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
    *++sp = msg;
    sel = special(SO_SEL_DNU);
    argc = 1;
    goto do_lookup;
}

op_return_self:
    PUSH(fp[-1]);
op_return_top:
    result = *sp;
    if (fr) {
        if (fr > frames) {
            sp = fr->fp - 1;
            *sp = result;
            fr--;
            lits = fr->lits;
            fp = fr->fp;
            ip = fr->ip;
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
    if (fr) {
        nframes = (int)(fr - frames) + 1;
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
        goto do_send_global;
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
    goto do_send_global;
}
