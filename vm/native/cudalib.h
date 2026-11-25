/* The runtime of Samaltak's CUDA library exports (cuda_*, FFIPrimitives-cuda; docs/cuda.md). The wrappers themselves
   are generated (cudalib_gen.c, by tools/cuda/bindgen.py from NVIDIA's headers); this file loads the libraries with
   dlopen on first use (no build dependency: a VM without them answers unavailable; stubs on UEFI) and keeps what lets
   the wrappers check every argument before the call: a table of the handles the libraries made (the image holds an
   id, never a pointer) and a table of live device allocations (a device pointer must lie inside one, with the extent
   the call will touch). */
#ifndef SAMALTAK_NATIVE_CUDALIB_H
#define SAMALTAK_NATIVE_CUDALIB_H
#include <stddef.h>
#include <stdint.h>

/* A wrapper's results below zero: the call did not reach the library (its own statuses are >= 0). */
#define SAMALTAK_CUDA_REJECT_UNAVAILABLE (-1) /* the library is not installed (or no such export here) */
#define SAMALTAK_CUDA_REJECT_SYMBOL (-2)      /* the library has no such function */
#define SAMALTAK_CUDA_REJECT_HANDLE (-3)      /* not a live handle of that type */
#define SAMALTAK_CUDA_REJECT_DEVICE (-4)      /* a device pointer outside the live allocations, or the extent past one */
#define SAMALTAK_CUDA_REJECT_SLICE (-5)       /* a host ByteArray too short */
#define SAMALTAK_CUDA_REJECT_FULL (-6)        /* the handle or allocation table is full, or no memory */
#define SAMALTAK_CUDA_REJECT_ARGUMENT (-7)    /* an argument the declared requirements refuse */

#define SAMALTAK_CUDA_HANDLES 4096
#define SAMALTAK_CUDA_ALLOCATIONS 4096

/* The elements a column-major rows x cols matrix with leading dimension ld spans; -1 if ld < rows. */
#define SAMALTAK_CUDA_MAT(ld, rows, cols) \
    ((int64_t)(cols) <= 0 || (int64_t)(rows) <= 0 ? (int64_t)0 \
     : (int64_t)(ld) < (int64_t)(rows) ? (int64_t)-1 : (int64_t)(ld) * ((int64_t)(cols) - 1) + (int64_t)(rows))

#ifndef SAMALTAK_UEFI
extern const char *const *const cudalib_sonames[];
extern const char *const cudalib_names[];
extern const char *const cudalib_handle_names[];

int cudalib_load(int lib);
void *cudalib_symbol(int lib, const char *name);
int64_t cudalib_missing(int lib);

int64_t cudalib_handle_new(int type, void *p, int64_t tag);
int cudalib_handle_get(int type, int64_t id, int nullable, void **p, int64_t *tag);
void cudalib_handle_drop(int64_t id);

int cudalib_device_room(void);
void cudalib_device_add(uint64_t base, uint64_t size);
int cudalib_device_is_base(uint64_t p);
int cudalib_device_ok(uint64_t p, uint64_t bytes);
void cudalib_device_drop(uint64_t p);

/* A pack: count (offset, length) pairs of uint64_t, then the arrays, each at an offset that is a multiple of 8. */
int cudalib_pack_ok(const uint8_t *pack, uint64_t len, int count);
void cudalib_pack_get(const uint8_t *pack, int i, const uint8_t **p, uint64_t *len);

char *cudalib_cstring(const uint8_t *s, uint64_t len);
int64_t cudalib_text(const char *s, uint8_t *out, uint64_t len);
void cudalib_put_i64(uint8_t *outs, int k, int64_t v);
void cudalib_put_u64(uint8_t *outs, int k, uint64_t v);
void cudalib_put_f64(uint8_t *outs, int k, double v);

/* A CSR matrix of rows rows: offsets from 0, never decreasing, column indices in [0, cols). */
int cudalib_csr_ok(const int32_t *offsets, int64_t rows, const int32_t *columns, int64_t cols);
#endif

#endif
