/* NVRTC behind dlopen, one thread a compile (nvrtc.h). */
#include "nvrtc.h"

#if defined(SAMALTAK_UEFI)

int64_t samaltak_nvrtc_version(void) { return SAMALTAK_NVRTC_UNAVAILABLE; }
int64_t samaltak_nvrtc_start(const uint8_t *src, uint64_t srcLen, const uint8_t *opts, uint64_t optsLen) {
    (void)src; (void)srcLen; (void)opts; (void)optsLen;
    return SAMALTAK_NVRTC_UNAVAILABLE;
}
int64_t samaltak_nvrtc_poll(int64_t job) { (void)job; return SAMALTAK_NVRTC_UNAVAILABLE; }
int64_t samaltak_nvrtc_output(int64_t job, int64_t kind, uint8_t *out, uint64_t outLen) {
    (void)job; (void)kind; (void)out; (void)outLen;
    return SAMALTAK_NVRTC_UNAVAILABLE;
}
int64_t samaltak_nvrtc_free(int64_t job) { (void)job; return SAMALTAK_NVRTC_UNAVAILABLE; }

#else

#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

/* NVRTC's API (nvrtc.h of CUDA 11.1 and later), declared here so that building needs no toolkit. */
typedef struct _nvrtcProgram *nvrtcProgram;
typedef int (*nvrtcVersion_t)(int *, int *);
typedef int (*nvrtcCreateProgram_t)(nvrtcProgram *, const char *, const char *, int, const char *const *, const char *const *);
typedef int (*nvrtcCompileProgram_t)(nvrtcProgram, int, const char *const *);
typedef int (*nvrtcGetSize_t)(nvrtcProgram, size_t *);
typedef int (*nvrtcGet_t)(nvrtcProgram, char *);
typedef int (*nvrtcDestroyProgram_t)(nvrtcProgram *);

static struct {
    int tried, major, minor;
    nvrtcVersion_t version;
    nvrtcCreateProgram_t create;
    nvrtcCompileProgram_t compile;
    nvrtcGetSize_t logSize, cubinSize;
    nvrtcGet_t log, cubin;
    nvrtcDestroyProgram_t destroy;
} nv;

typedef struct {
    int used, running, detached;
    int64_t result;
    char *src, *opts;
    uint64_t optsLen;
    char *out[2];
    uint64_t outLen[2];
    pthread_t thread;
} Job;

static Job jobs[SAMALTAK_NVRTC_JOBS];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

static int load(void) {
    static const char *const names[] = {
        "libnvrtc.so.13", "libnvrtc.so.12", "libnvrtc.so", "/usr/local/cuda/lib64/libnvrtc.so.13",
        "/usr/local/cuda/lib64/libnvrtc.so.12", "/usr/local/cuda/lib64/libnvrtc.so", NULL };
    void *lib = NULL;
    pthread_mutex_lock(&lock);
    if (nv.tried) { pthread_mutex_unlock(&lock); return nv.compile != NULL; }
    nv.tried = 1;
    const char *path = getenv("SAMALTAK_NVRTC");
    if (path && *path) lib = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    for (int i = 0; !lib && names[i]; i++) lib = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
    if (lib) {
        nv.version = (nvrtcVersion_t)dlsym(lib, "nvrtcVersion");
        nv.create = (nvrtcCreateProgram_t)dlsym(lib, "nvrtcCreateProgram");
        nv.logSize = (nvrtcGetSize_t)dlsym(lib, "nvrtcGetProgramLogSize");
        nv.log = (nvrtcGet_t)dlsym(lib, "nvrtcGetProgramLog");
        nv.cubinSize = (nvrtcGetSize_t)dlsym(lib, "nvrtcGetCUBINSize");
        nv.cubin = (nvrtcGet_t)dlsym(lib, "nvrtcGetCUBIN");
        nv.destroy = (nvrtcDestroyProgram_t)dlsym(lib, "nvrtcDestroyProgram");
        nvrtcCompileProgram_t compile = (nvrtcCompileProgram_t)dlsym(lib, "nvrtcCompileProgram");
        if (nv.version && nv.create && nv.logSize && nv.log && nv.cubinSize && nv.cubin && nv.destroy && compile
            && nv.version(&nv.major, &nv.minor) == 0)
            nv.compile = compile;
    }
    pthread_mutex_unlock(&lock);
    return nv.compile != NULL;
}

int64_t samaltak_nvrtc_version(void) {
    return load() ? (int64_t)nv.major * 100 + nv.minor : SAMALTAK_NVRTC_UNAVAILABLE;
}

static char *take(nvrtcProgram p, nvrtcGetSize_t size, nvrtcGet_t get, uint64_t *len) {
    size_t n = 0;
    *len = 0;
    if (size(p, &n) != 0 || n == 0) return NULL;
    char *b = malloc(n);
    if (b && get(p, b) != 0) { free(b); return NULL; }
    if (b) *len = n;
    return b;
}

static void release(Job *j) {
    free(j->src); free(j->opts); free(j->out[0]); free(j->out[1]);
    memset(j, 0, sizeof *j);
}

static void *run(void *arg) {
    Job *j = arg;
    const char *argv[64];
    int argc = 0;
    for (uint64_t i = 0; i < j->optsLen && argc < 64; ) {
        if (j->opts[i]) argv[argc++] = j->opts + i;
        i += strlen(j->opts + i) + 1;
    }
    nvrtcProgram p = NULL;
    int64_t result = nv.create(&p, j->src, "shader.cu", 0, NULL, NULL);
    char *log = NULL, *cubin = NULL;
    uint64_t logLen = 0, cubinLen = 0;
    if (result == 0) {
        result = nv.compile(p, argc, argv);
        log = take(p, nv.logSize, nv.log, &logLen);
        if (result == 0) {
            cubin = take(p, nv.cubinSize, nv.cubin, &cubinLen);
            if (!cubin) result = 1000;
        }
        nv.destroy(&p);
    }
    pthread_mutex_lock(&lock);
    j->out[SAMALTAK_NVRTC_LOG] = log; j->outLen[SAMALTAK_NVRTC_LOG] = logLen;
    j->out[SAMALTAK_NVRTC_CUBIN] = cubin; j->outLen[SAMALTAK_NVRTC_CUBIN] = cubinLen;
    j->result = result;
    j->running = 0;
    if (j->detached) release(j);
    pthread_mutex_unlock(&lock);
    return NULL;
}

int64_t samaltak_nvrtc_start(const uint8_t *src, uint64_t srcLen, const uint8_t *opts, uint64_t optsLen) {
    if (!load()) return SAMALTAK_NVRTC_UNAVAILABLE;
    if (srcLen == 0 || srcLen > (64u << 20) || optsLen > 65536) return SAMALTAK_NVRTC_REFUSED;
    pthread_mutex_lock(&lock);
    int k = 0;
    while (k < SAMALTAK_NVRTC_JOBS && jobs[k].used) k++;
    if (k == SAMALTAK_NVRTC_JOBS) { pthread_mutex_unlock(&lock); return SAMALTAK_NVRTC_REFUSED; }
    Job *j = &jobs[k];
    memset(j, 0, sizeof *j);
    j->src = malloc(srcLen + 1);
    j->opts = malloc(optsLen + 1);
    if (!j->src || !j->opts) { release(j); pthread_mutex_unlock(&lock); return SAMALTAK_NVRTC_REFUSED; }
    memcpy(j->src, src, srcLen); j->src[srcLen] = 0;
    if (optsLen) memcpy(j->opts, opts, optsLen);
    j->opts[optsLen] = 0;
    j->optsLen = optsLen;
    j->used = j->running = 1;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_attr_setstacksize(&attr, 64u << 20);
    int failed = pthread_create(&j->thread, &attr, run, j);
    pthread_attr_destroy(&attr);
    if (failed) { release(j); pthread_mutex_unlock(&lock); return SAMALTAK_NVRTC_REFUSED; }
    pthread_mutex_unlock(&lock);
    return k + 1;
}

static Job *jobAt(int64_t job) {
    if (job < 1 || job > SAMALTAK_NVRTC_JOBS) return NULL;
    Job *j = &jobs[job - 1];
    return j->used && !j->detached ? j : NULL;
}

int64_t samaltak_nvrtc_poll(int64_t job) {
    pthread_mutex_lock(&lock);
    Job *j = jobAt(job);
    int64_t r = !j ? SAMALTAK_NVRTC_UNAVAILABLE : j->running ? SAMALTAK_NVRTC_RUNNING : j->result;
    pthread_mutex_unlock(&lock);
    return r;
}

int64_t samaltak_nvrtc_output(int64_t job, int64_t kind, uint8_t *out, uint64_t outLen) {
    pthread_mutex_lock(&lock);
    Job *j = jobAt(job);
    int64_t r;
    if (!j || kind < 0 || kind > 1) r = SAMALTAK_NVRTC_UNAVAILABLE;
    else if (j->running) r = SAMALTAK_NVRTC_RUNNING;
    else {
        r = (int64_t)j->outLen[kind];
        uint64_t n = j->outLen[kind] < outLen ? j->outLen[kind] : outLen;
        if (n) memcpy(out, j->out[kind], n);
    }
    pthread_mutex_unlock(&lock);
    return r;
}

int64_t samaltak_nvrtc_free(int64_t job) {
    pthread_mutex_lock(&lock);
    Job *j = jobAt(job);
    int64_t r = SAMALTAK_NVRTC_UNAVAILABLE;
    if (j) {
        if (j->running) j->detached = 1; else release(j);
        r = 0;
    }
    pthread_mutex_unlock(&lock);
    return r;
}

#endif
