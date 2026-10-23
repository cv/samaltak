/* VM-internal declarations: layouts, object memory, GC, interpreter, scheduler. */
#ifndef SAMALTAK_CORE_H
#define SAMALTAK_CORE_H

#include "vm.h"
#include <stdatomic.h>
#include <stdio.h>

static inline uint64_t *hdr_ptr(oop o) { return (uint64_t *)o; }
static inline oop *slots(oop o) { return (oop *)(o + 16); }
static inline uint32_t hash_of(oop o) { return (uint32_t)((vm_hdr(o) >> H_HASH_SHIFT) & H_HASH_MASK); }
static inline bool is_immutable(oop o) { return vm_hdr(o) & H_IMMUTABLE; }
static inline oop raw_class(oop o) { return ((oop *)o)[1]; }
static inline size_t obj_bytes(oop o) { return 16 + 8 * (size_t)num_slots(o); }
static inline bool fmt_has_pointers(int f) { return f >= 1 && f <= 4; }

/* ---- special objects ---- */
extern oop specials_oop;
/* cached specials, refreshed after every GC */
extern oop cls_smallint, cls_char, cls_smallfloat, cls_boxedfloat, cls_array, cls_context, cls_block, cls_point,
    cls_bytestring, cls_bytearray, cls_message;

/* ---- VM-known layouts ---- */
enum { BEH_SUPERCLASS, BEH_METHODDICT, BEH_FORMAT, CD_INSTVARS, CD_ORGANIZATION };
enum { CLS_SUBCLASSES = 5, CLS_NAME, CLS_CLASSPOOL };
enum { META_THISCLASS = 5 };
enum { MD_TALLY, MD_KEYS, MD_VALUES };
enum { CM_SELECTOR, CM_CLASS, CM_LITERALS, CM_BYTECODES, CM_NUMARGS, CM_NUMTEMPS, CM_FRAMESIZE, CM_PRIMITIVE };
enum { CTX_SENDER, CTX_PC, CTX_STACKP, CTX_METHOD, CTX_CLOSURE, CTX_RECEIVER, CTX_FIXED };
enum { BC_OUTER, BC_STARTPC, BC_NUMARGS, BC_NUMTEMPS, BC_FRAMESIZE };
enum { PROC_NEXT, PROC_SUSPENDED, PROC_PRIORITY, PROC_MYLIST, PROC_NAME, PROC_CPUTIME };
enum { SCHED_LISTS, SCHED_ACTIVE };
enum { LL_FIRST, LL_LAST };
enum { SEM_EXCESS = 2 };
enum { ASSOC_KEY, ASSOC_VALUE };
enum { MSG_SELECTOR, MSG_ARGS };

/* ---- memory.c ---- */
extern char *eden_lo, *eden_hi, *eden_top, *alloc_limit;
extern uint64_t gc_epoch;
oop alloc_obj(oop cls, int fmt, uint32_t nslots);       /* pointer formats nil-filled, others zeroed */
oop alloc_old(oop cls, int fmt, uint32_t nslots);       /* directly in old space */
oop alloc_obj_try(oop cls, int fmt, size_t nslots);     /* alloc_obj, 0 if it can never fit in the heap */
oop alloc_context(uint32_t nslots);                     /* indexable slots; may GC */
oop instantiate(oop cls, size_t n, int *err);           /* basicNew: semantics; *err 0, PRIM_ERR_NO_MEMORY or -1 */
uint32_t next_hash(void);
extern uint64_t hash_seed;
uint32_t fixed_fields(oop o);                           /* fixed (non-indexable) pointer fields */
size_t indexable_size(oop o);
oop large_int_from_u64(uint64_t v, bool negative);
bool u64_of(oop o, uint64_t *out);                      /* non-negative Integer fitting 64 bits */
bool is_kind_of_string(oop o);
uint32_t string_hash(oop s);
uint32_t string_char_at(oop s, size_t i);               /* 0-based code point */
size_t string_size(oop s);
void memory_init(size_t eden_bytes, size_t max_heap);
void reset_alloc_limit(void);                            /* after GC or sampling changes */
void refresh_specials(void);
#define MAX_ROOTS 1024
extern oop *root_stack[MAX_ROOTS];
extern int root_count;

/* ---- gc.c ---- */
extern char *old_lo, *old_top, *old_hi;
extern size_t old_budget, max_heap_bytes;
extern char *surv_lo, *surv_top, *surv_hi;              /* current (from) survivor space */
extern uint64_t stat_scavenges, stat_full_gcs, stat_scavenge_us, stat_full_us, stat_allocated, stat_tenured;
extern size_t remset_count;
void gc_init(size_t eden_bytes, size_t max_heap);
void collect_garbage(size_t need);                      /* scavenge or full GC so that `need` bytes fit in eden */
void full_gc(void);
void scavenge(void);
char *old_alloc_try(size_t bytes);                      /* may full GC; NULL if it cannot fit in the heap limit */
char *old_alloc_raw(size_t bytes);                      /* old_alloc_try, fatal if exhausted */
void remember_if_old(oop o);
typedef void (*obj_visitor)(oop o, void *data);
void walk_old_space(obj_visitor fn, void *data);
void become_forward(oop from, oop to);
extern bool finalization_pending;                       /* a GC cleared weak slots; signal at the next safepoint */
extern uint64_t stat_weak_cleared;

/* ---- interp.c ---- */
extern oop active_ctx;                                  /* the Context below the frames (the executing one if none) */
extern int nframes;                                     /* frames on the C stack above active_ctx */
extern uint64_t stat_materialized, stat_flushes;        /* frames flushed into Contexts; flushes */
void materialize_all(void);                             /* flush all frames into Contexts (may GC); caller externalized */
void interp_roots(void (*fn)(oop *));                   /* frames and their stack slots */
void interp_before_gc(void);                            /* frames: raw bytecode pointers to offsets */
void interp_after_gc(void);
bool interp_frames_valid(bool (*valid)(oop));
extern oop vm_tmp_root[4];                              /* scratch GC roots */
void interpret(void);
void flush_method_cache(void);
void flush_method_cache_selector(oop sel);
oop lookup_method(oop cls, oop sel);
int selector_argc(oop sel);
void print_stack(FILE *f, oop ctx);
_Noreturn void fatal(const char *fmt, ...);
/* primitive plumbing */
typedef void (*prim_fn)(void);
enum { PS_NONE, PS_OK, PS_FAIL, PS_SWITCHED, PS_RESEND };
extern int prim_status, prim_error_code;
/* core primitives read their arguments directly (vm.h's functions do the same for the platform layer) */
extern oop *vm_prim_base;                               /* receiver slot of the running primitive, kept valid across GC */
extern int vm_prim_nargs;
#define prim_argc() (vm_prim_nargs)
#define prim_receiver() (vm_prim_base[0])
#define prim_arg(i) (vm_prim_base[1 + (i)])
void set_prim_base(int argc);                           /* the primitive's receiver is at the active stack top - argc */
extern oop prim_result, resend_selector;
extern int resend_argc;
oop *prim_stack_base(void);                             /* &receiver slot in the active context */
void prim_commit(oop result);                           /* pop receiver+args, push result now, mark switched */
void prim_switched(void);                               /* stack already arranged by the primitive */
void activate_block(int argc);                          /* closure+args on the active stack: push the block's frame */
void activate_block_with_array(void);                   /* closure+Array on the active stack */
oop *active_slots(void);                                /* args/temps/stack of the active frame or Context */
int64_t active_stackp(void);
void active_set_stackp(int64_t n);
int64_t active_capacity(void);                          /* indexable slots it may use */
void ctx_set_stackp(oop ctx, int64_t sp);
int64_t ctx_stackp(oop ctx);
oop ctx_home(oop ctx);

/* ---- sched.c ---- */
extern atomic_int interrupt_pending;
extern oop last_preempted;
extern oop alloc_sample_class;
extern int64_t alloc_sample_size;
extern int64_t alloc_sample_interval, alloc_sample_countdown;
extern int alloc_sample_sema;
extern bool alloc_sample_unread;                        /* a sample not yet taken by allocationSampleTake */
extern bool sampler_tick_unread;                        /* a CPU sampler tick not yet taken by samplerTickTake */
extern uint64_t stat_process_switches;
void sched_init(void);
void handle_interrupts(void);
void transfer_to(oop proc);
oop active_process(void);
void resume_process(oop proc);
void suspend_active(void);
void semaphore_signal(oop sem);
void semaphore_wait(oop sem);
void processor_yield(void);
oop remove_first_link(oop list);
bool remove_link(oop list, oop link);
void add_last_link(oop list, oop link);
int64_t now_us(void);
int64_t now_ms(void);
void set_timer(int64_t ms);
void set_sampler(int64_t interval_us, int sema);
int64_t process_cpu_time_us(oop proc);                   /* cpuTime, including the running slice if active */
void relinquish(int64_t us);
void alloc_sample_hit(oop cls, size_t bytes);

/* ---- image.c ---- */
extern char *image_path;
void load_image(const char *path);
bool write_snapshot(const char *path);

/* ---- prims_system.c ---- */
extern int vm_args_start;                               /* index of the first image argument in vm_argv */

/* ---- prims.c ---- */
prim_fn prim_lookup(int64_t n);
const char *prim_name(int64_t n);
bool prim_tryable(prim_fn f);
bool prim_is_leaf(prim_fn f);                           /* never allocates, switches or inspects Contexts */
oop primitive_names_array(void);

#endif
