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

#ifndef SAMALTAK_UEFI
/* The elements a column-major rows x cols matrix with leading dimension ld spans; -1 if ld < rows or it overflows. */
static inline int64_t samaltak_cuda_mat(int64_t ld, int64_t rows, int64_t cols) {
    int64_t r;
    if (cols <= 0 || rows <= 0) return 0;
    if (ld < rows || __builtin_mul_overflow(ld, cols - 1, &r) || __builtin_add_overflow(r, rows, &r)) return -1;
    return r;
}
#define SAMALTAK_CUDA_MAT(ld, rows, cols) samaltak_cuda_mat((int64_t)(ld), (int64_t)(rows), (int64_t)(cols))

extern const char *const *const cudalib_sonames[];
extern const char *const cudalib_names[];
extern const char *const cudalib_handle_names[];

int cudalib_load(int lib);
void *cudalib_symbol(int lib, const char *name);
int64_t cudalib_missing(int lib);

int64_t cudalib_handle_new(int type, void *p, int64_t tag);
int cudalib_handle_get(int type, int64_t id, int nullable, void **p, int64_t *tag);
void cudalib_handle_drop(int64_t id);
void cudalib_handle_drop_tagged(int type, int64_t tag);

int cudalib_device_room(void);
void cudalib_device_add(uint64_t base, uint64_t size);
int cudalib_device_is_base(uint64_t p);
int cudalib_device_ok(uint64_t p, uint64_t bytes);
/* n elements of size bytes from p lie in one live allocation (n >= 0, no overflow). */
int cudalib_device_span(uint64_t p, int64_t n, uint64_t size);
/* The bytes of n elements of a cudaDataType (CUDA_R_32F, R_64F, C_32F, C_64F); -1 for another type, n < 0 or overflow. */
int64_t cudalib_dtype_bytes(int64_t n, int64_t dataType);
void cudalib_device_drop(uint64_t p);

/* A pack: count (offset, length) pairs of uint64_t, then the arrays, each at an offset that is a multiple of 8. */
int cudalib_pack_ok(const uint8_t *pack, uint64_t len, int count);
void cudalib_pack_get(const uint8_t *pack, int i, const uint8_t **p, uint64_t *len);

char *cudalib_cstring(const uint8_t *s, uint64_t len);
int64_t cudalib_text(const char *s, uint8_t *out, uint64_t len);
void cudalib_put_i64(uint8_t *outs, int k, int64_t v);
void cudalib_put_u64(uint8_t *outs, int k, uint64_t v);
void cudalib_put_f64(uint8_t *outs, int k, double v);

/* An image cuModuleLoadData may read: a CUDA ELF (cubin) whose headers, sections and segments lie within len bytes,
   or PTX (printable text, NUL-terminated within them). */
int cudalib_module_image_ok(const uint8_t *p, uint64_t len);

/* A CSR matrix of rows rows: offsets from 0, never decreasing, column indices in [0, cols). */
int cudalib_csr_ok(const int32_t *offsets, int64_t rows, const int32_t *columns, int64_t cols);

/* A cuFFT plan's tag: its type, the elements of its full arrays (n: reals or complex values) and of its half-spectrum
   arrays (half: real-to-complex output, complex-to-real input), as type << 56 | half << 28 | n. outer is the product of
   the dimensions but the last, last the last (the fastest-varying), batch the transforms; -1 for a type cuFFT does not
   have, a dimension below 1 or an array of 2^28 elements or more. */
int64_t cudalib_fft_tag(int64_t type, int64_t outer, int64_t last, int64_t batch);
int64_t cudalib_fft_many_tag(int64_t type, int64_t rank, const int32_t *dims, int64_t batch);
#define CUDALIB_FFT_TYPE(tag) ((int64_t)(tag) >> 56)
#define CUDALIB_FFT_HALF(tag) (((int64_t)(tag) >> 28) & ((1 << 28) - 1))
#define CUDALIB_FFT_N(tag) ((int64_t)(tag) & ((1 << 28) - 1))
#endif

#endif
