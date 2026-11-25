/* The runtime of the CUDA library exports (cudalib.h). */
#include "cudalib.h"
#include "cudalib_gen.h"

#if !defined(SAMALTAK_UEFI)

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static struct { int tried; void *lib; } libs[SAMALTAK_CUDA_LIBS];

static void *open_in(const char *dir, size_t dirLen, const char *name) {
    char path[4096];
    if (dirLen + strlen(name) + 2 > sizeof path) return NULL;
    memcpy(path, dir, dirLen);
    path[dirLen] = '/';
    strcpy(path + dirLen + 1, name);
    return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}

/* SAMALTAK_CUDA_LIBS's directories (separated by colons) first, then the loader's search, then the toolkit's. */
int cudalib_load(int lib) {
    if (lib < 0 || lib >= SAMALTAK_CUDA_LIBS) return 0;
    if (libs[lib].tried) return libs[lib].lib != NULL;
    libs[lib].tried = 1;
    const char *const *names = cudalib_sonames[lib];
    const char *dirs = getenv("SAMALTAK_CUDA_LIBS");
    void *h = NULL;
    for (const char *d = dirs; d && *d && !h; ) {
        const char *end = strchr(d, ':');
        size_t n = end ? (size_t)(end - d) : strlen(d);
        for (int i = 0; n && names[i] && !h; i++) h = open_in(d, n, names[i]);
        d = end ? end + 1 : d + n;
    }
    for (int i = 0; names[i] && !h; i++) h = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
    for (int i = 0; names[i] && !h; i++) h = open_in("/usr/local/cuda/lib64", 21, names[i]);
    libs[lib].lib = h;
    return h != NULL;
}

void *cudalib_symbol(int lib, const char *name) {
    return cudalib_load(lib) ? dlsym(libs[lib].lib, name) : NULL;
}

int64_t cudalib_missing(int lib) {
    return cudalib_load(lib) ? SAMALTAK_CUDA_REJECT_SYMBOL : SAMALTAK_CUDA_REJECT_UNAVAILABLE;
}

/* Handles: id = serial << 12 | slot, the serial new for each handle, so a stale or forged id names nothing. */
static struct { void *p; int64_t tag; uint32_t serial; int type; } handles[SAMALTAK_CUDA_HANDLES];
static uint32_t handleSerial;
static int liveHandles;

int64_t cudalib_handle_new(int type, void *p, int64_t tag) {
    for (int s = 0; s < SAMALTAK_CUDA_HANDLES; s++) {
        if (handles[s].type) continue;
        if (++handleSerial >= (1u << 30)) handleSerial = 1;
        handles[s].p = p; handles[s].tag = tag; handles[s].serial = handleSerial; handles[s].type = type;
        liveHandles++;
        return ((int64_t)handleSerial << 12) | s;
    }
    return SAMALTAK_CUDA_REJECT_FULL;
}

static int slot_of(int64_t id) {
    if (id <= 0) return -1;
    int s = (int)(id & (SAMALTAK_CUDA_HANDLES - 1));
    if (!handles[s].type || handles[s].serial != (uint64_t)id >> 12) return -1;
    return s;
}

int cudalib_handle_get(int type, int64_t id, int nullable, void **p, int64_t *tag) {
    if (id == 0 && nullable) { *p = NULL; *tag = 0; return 1; }
    int s = slot_of(id);
    if (s < 0 || handles[s].type != type) return 0;
    *p = handles[s].p; *tag = handles[s].tag;
    return 1;
}

void cudalib_handle_drop(int64_t id) {
    int s = slot_of(id);
    if (s < 0) return;
    memset(&handles[s], 0, sizeof handles[s]);
    liveHandles--;
}

/* Device allocations, unordered (a call checks at most a few pointers). */
static struct { uint64_t base, size; } allocations[SAMALTAK_CUDA_ALLOCATIONS];
static int allocationCount;
static uint64_t allocatedBytes;

int cudalib_device_room(void) { return allocationCount < SAMALTAK_CUDA_ALLOCATIONS; }

void cudalib_device_add(uint64_t base, uint64_t size) {
    if (!base || allocationCount >= SAMALTAK_CUDA_ALLOCATIONS) return;
    allocations[allocationCount].base = base;
    allocations[allocationCount].size = size;
    allocationCount++;
    allocatedBytes += size;
}

static int find(uint64_t p) {
    for (int i = 0; i < allocationCount; i++)
        if (p >= allocations[i].base && p - allocations[i].base < allocations[i].size) return i;
    return -1;
}

int cudalib_device_is_base(uint64_t p) {
    int i = find(p);
    return i >= 0 && allocations[i].base == p;
}

int cudalib_device_ok(uint64_t p, uint64_t bytes) {
    int i = find(p);
    return i >= 0 && bytes <= allocations[i].size - (p - allocations[i].base);
}

void cudalib_device_drop(uint64_t p) {
    int i = find(p);
    if (i < 0 || allocations[i].base != p) return;
    allocatedBytes -= allocations[i].size;
    allocations[i] = allocations[--allocationCount];
}

int cudalib_pack_ok(const uint8_t *pack, uint64_t len, int count) {
    uint64_t header = (uint64_t)count * 16;
    if (len < header) return 0;
    for (int i = 0; i < count; i++) {
        uint64_t off, n;
        memcpy(&off, pack + 16 * i, 8);
        memcpy(&n, pack + 16 * i + 8, 8);
        if (off < header || off % 8 || off > len || n > len - off) return 0;
    }
    return 1;
}

void cudalib_pack_get(const uint8_t *pack, int i, const uint8_t **p, uint64_t *len) {
    uint64_t off;
    memcpy(&off, pack + 16 * i, 8);
    memcpy(len, pack + 16 * i + 8, 8);
    *p = pack + off;
}

char *cudalib_cstring(const uint8_t *s, uint64_t len) {
    if (len > (1u << 20)) return NULL;
    char *c = malloc(len + 1);
    if (!c) return NULL;
    if (len) memcpy(c, s, len);
    c[len] = 0;
    return c;
}

int64_t cudalib_text(const char *s, uint8_t *out, uint64_t len) {
    if (!s) return 0;
    uint64_t n = strlen(s);
    memcpy(out, s, n < len ? n : len);
    return (int64_t)n;
}

void cudalib_put_i64(uint8_t *outs, int k, int64_t v) { memcpy(outs + 8 * k, &v, 8); }
void cudalib_put_u64(uint8_t *outs, int k, uint64_t v) { memcpy(outs + 8 * k, &v, 8); }
void cudalib_put_f64(uint8_t *outs, int k, double v) { memcpy(outs + 8 * k, &v, 8); }

int cudalib_csr_ok(const int32_t *offsets, int64_t rows, const int32_t *columns, int64_t cols) {
    if (rows < 0 || offsets[0] != 0) return 0;
    for (int64_t i = 0; i < rows; i++)
        if (offsets[i + 1] < offsets[i]) return 0;
    for (int64_t j = 0; j < offsets[rows]; j++)
        if (columns[j] < 0 || columns[j] >= cols) return 0;
    return 1;
}

/* A number of this VM process, so the image can tell its handles from those of an earlier process. */
int64_t samaltak_cuda_session(void) {
    static int64_t session;
    if (!session) {
        struct timespec t;
        clock_gettime(CLOCK_REALTIME, &t);
        uint64_t x = ((uint64_t)t.tv_sec * 1000000007u) ^ (uint64_t)t.tv_nsec ^ ((uint64_t)getpid() << 32) ^ (uint64_t)(uintptr_t)&t;
        x ^= x >> 33; x *= 0xff51afd7ed558ccdull; x ^= x >> 33;
        session = (int64_t)(x >> 2) | 1;
    }
    return session;
}

/* 0: live device allocations; 1: live handles; 2: bytes allocated. */
int64_t samaltak_cuda_live(int64_t kind) {
    return kind == 0 ? allocationCount : kind == 1 ? liveHandles : kind == 2 ? (int64_t)allocatedBytes : -1;
}

#endif
