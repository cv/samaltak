/* Samaltak VM: the interface primitives (core and platform) are written against.
 *
 * GC rules: every heap pointer load goes through load_ref, every store through
 * store_ref. Any allocation may move objects: raw oops and bytes_of/words32_of
 * pointers are invalid after it unless the oop is registered with push_root. */
#ifndef SAMALTAK_VM_H
#define SAMALTAK_VM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef uint64_t oop;

/* ---- immediates ---- */
static inline bool is_int(oop o) { return o & 1; }
static inline int64_t int_val(oop o) { return (int64_t)o >> 1; }
static inline oop int_oop(int64_t v) { return ((uint64_t)v << 1) | 1; }
#define VM_INT_MAX ((int64_t)0x3FFFFFFFFFFFFFFF)
#define VM_INT_MIN (-VM_INT_MAX - 1)
static inline bool int_fits(int64_t v) { return v >= VM_INT_MIN && v <= VM_INT_MAX; }
static inline bool is_char(oop o) { return (o & 7) == 2; }
static inline uint32_t char_val(oop o) { return (uint32_t)(o >> 3); }
static inline oop char_oop(uint32_t cp) { return ((oop)cp << 3) | 2; }
static inline bool is_ptr(oop o) { return (o & 7) == 0; }
bool is_float(oop o);           /* SmallFloat64 or BoxedFloat64 */
double float_val(oop o);        /* o must satisfy is_float */
oop float_oop(double d);        /* may allocate */

/* ---- object model constants ----
 * Exported: boot/bootstrap.py parses this block (between the BEGIN/END markers) for the seed image and generates the
 * image's VMConstants class from it, so these are the only definitions. Plain enums and #defines of integer expressions. */
/* BEGIN EXPORTED CONSTANTS */
/* header word 0: numSlots (bits 0-31), format, identity hash, immutable bit, GC bits */
#define H_FMT_SHIFT 32
#define H_FMT_MASK 0x1Full
#define H_HASH_SHIFT 37
#define H_HASH_MASK 0x3FFFFFull
#define H_IMMUTABLE (1ull << 59)
#define H_REMEMBERED (1ull << 60)
#define H_AGE_SHIFT 61
#define H_AGE_MASK (3ull << H_AGE_SHIFT)
#define H_FORWARDED (1ull << 63)
#define H_GCBITS (H_REMEMBERED | H_AGE_MASK | H_FORWARDED)

/* object formats; F_W32 + unused 32-bit units (0-1), F_BYTES + unused bytes (0-7) */
enum { F_EMPTY = 0, F_FIXED = 1, F_VAR = 2, F_FIXVAR = 3, F_WEAK = 4, F_IMMEDIATE = 7, F_W64 = 9, F_W32 = 10, F_BYTES = 16 };

/* class format word: (instSpec << CLS_SPEC_SHIFT) | instSize */
#define CLS_SPEC_SHIFT 16
#define CLS_INSTSIZE_MASK 0xFFFF

/* special objects array, 0-based */
enum {
    SO_NIL, SO_FALSE, SO_TRUE, SO_PROCESSOR, SO_SMALLTALK, SO_SMALLINTEGER, SO_CHARACTER, SO_SMALLFLOAT,
    SO_BOXEDFLOAT, SO_ARRAY, SO_BYTEARRAY, SO_BYTESTRING, SO_BYTESYMBOL, SO_WIDESTRING, SO_COMPILEDMETHOD,
    SO_CONTEXT, SO_BLOCKCLOSURE, SO_PROCESS, SO_SEMAPHORE, SO_POINT, SO_LARGEPOS, SO_LARGENEG, SO_MESSAGE,
    SO_ASSOCIATION, SO_BITMAP, SO_SEL_DNU, SO_SEL_MUSTBEBOOLEAN, SO_SEL_CANNOTRETURN, SO_SEL_ABOUTTORETURN,
    SO_SEL_ATTEMPTTOASSIGN, SO_SPECIAL_SELECTORS, SO_TIMER_SEMAPHORE, SO_EXTERNAL_OBJECTS, SO_WIDESYMBOL,
    SO_SEL_PRIMITIVEFAILED, SO_FINALIZATION_SEMAPHORE, SO_SEL_STACKOVERFLOW, SO_COUNT
};
#define EXTERNAL_OBJECTS_SIZE 64 /* slots of the externalObjects Array */

/* CompiledMethod primitive slot: primitive number | CM_PRIM_ERROR_FLAG when the method declares error: ec */
#define CM_PRIM_MASK 0xFFFF
#define CM_PRIM_ERROR_FLAG 0x10000
/* marker primitives (always fail; Smalltalk finds these contexts by method primitive) */
#define PRIM_ENSURE_MARKER 198 /* ensure: / ifCurtailed: */
#define PRIM_ONDO_MARKER 199   /* on:do: */
/* prim_fail_code values */
#define PRIM_ERR_NO_MEMORY 1 /* the requested object can never fit in the heap, even after a full GC */

#define CTX_SLACK 2 /* extra stack slots above frameSize for VM-synthesized sends */
/* END EXPORTED CONSTANTS */

/* ---- object access ---- */
static inline uint64_t vm_hdr(oop o) { return *(uint64_t *)o; }
static inline uint32_t num_slots(oop o) { return (uint32_t)vm_hdr(o); }
static inline int format_of(oop o) { return (int)((vm_hdr(o) >> H_FMT_SHIFT) & H_FMT_MASK); }
oop class_of(oop o);

extern char *vm_young_lo, *vm_young_hi;
void vm_remember(oop obj);
static inline bool vm_is_young(oop o) { return (uint64_t)(o - (oop)vm_young_lo) < (uint64_t)(vm_young_hi - vm_young_lo); }
static inline oop load_ref(oop obj, uint32_t i) { return ((oop *)(obj + 16))[i]; }
static inline void store_ref(oop obj, uint32_t i, oop v)
{
    ((oop *)(obj + 16))[i] = v;
    if (is_ptr(v) && vm_is_young(v) && !vm_is_young(obj) && !(vm_hdr(obj) & H_REMEMBERED)) vm_remember(obj);
}

uint8_t *bytes_of(oop o);       /* body of a byte/word object */
size_t byte_size(oop o);        /* element count of a byte object (formats 16-23); body bytes otherwise */
uint32_t *words32_of(oop o);
size_t word32_size(oop o);      /* element count of a 32-bit object (formats 10-11) */

/* ---- allocation (may GC) ---- */
oop alloc_slots(oop cls, uint32_t n);   /* n = indexable slot count (0 for non-indexable classes); fields nil */
oop alloc_bytes(oop cls, size_t n);     /* n bytes, zeroed */
oop alloc_words32(oop cls, size_t n);   /* n 32-bit units, zeroed */
oop special(int index);                 /* special objects array, 0-based */
extern oop nil_oop, true_oop, false_oop;
oop string_from_utf8(const char *s, size_t n);   /* ByteString or WideString */
char *utf8_of(oop string);                       /* malloc'd, NUL-terminated (NULL if out of memory);
                                                    ByteString/Symbol/WideString/ByteArray */
oop int64_oop(int64_t v);                        /* SmallInteger or LargeInteger (may allocate) */
bool int64_of(oop o, int64_t *out);              /* SmallInteger or LargeInteger fitting int64 */
void push_root(oop *p);
void pop_root(void);

/* ---- inside a primitive ---- */
int prim_argc(void);
oop prim_receiver(void);
oop prim_arg(int i);            /* i = 0..argc-1 */
void prim_return(oop v);
void prim_fail(void);
void prim_fail_code(int code);  /* method's error temp (<primitive: 'x' error: ec>) gets SmallInteger code */
bool prim_failed(void);
void signal_external_semaphore(int index);  /* 1-based index into externalObjects; VM thread only, queued */
void request_interrupt_check(void);         /* any thread */
void request_periodic_poll(int64_t interval_us); /* while Smalltalk runs, check interrupts (and so platform_poll)
                                                    at least every interval_us; 0 = only on request */

/* ---- VM state the platform may consult ---- */
extern bool vm_headless;
extern int vm_argc;
extern char **vm_argv;

/* Platform hooks: the VM provides weak no-op defaults; vm/platform overrides them. */
void platform_init(void);               /* at startup unless --headless */
void platform_poll(void);               /* at interrupt checks */
void platform_wait(int64_t timeout_us); /* idle wait; < 0 = forever */
void platform_shutdown(void);           /* at quit */

#endif
