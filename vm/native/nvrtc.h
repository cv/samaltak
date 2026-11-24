/* Samaltak's runtime CUDA compiler exports (core_nvrtc_*, FFIPrimitives-nvrtc): NVIDIA's NVRTC (libnvrtc, the CUDA
   toolkit's runtime compilation library), loaded with dlopen on first use where it is installed, compiles CUDA C++ to a
   cubin for the GPU (-arch=sm_121: the GB10's machine code; no CUDA driver library: System-NV launches it) on a thread
   of its own, so the VM goes on meanwhile. Not linked: a VM without the toolkit has none (version answers -1); none on
   UEFI. Jobs are numbered from 1; at most SAMALTAK_NVRTC_JOBS at once. docs/nv-shaders.md. */
#ifndef SAMALTAK_NATIVE_NVRTC_H
#define SAMALTAK_NATIVE_NVRTC_H
#include <stdint.h>

#define SAMALTAK_NVRTC_JOBS 8
#define SAMALTAK_NVRTC_UNAVAILABLE (-1) /* no NVRTC here; no such job */
#define SAMALTAK_NVRTC_RUNNING (-2)
#define SAMALTAK_NVRTC_REFUSED (-3)     /* arguments refused, or too many jobs */
#define SAMALTAK_NVRTC_LOG 0
#define SAMALTAK_NVRTC_CUBIN 1

/* NVRTC's version as major * 100 + minor (1300 for 13.0), loading it if need be; -1 if there is none. */
int64_t samaltak_nvrtc_version(void);
/* Start compiling the CUDA C++ src with opts (options separated by NUL bytes); a job, or -1 or -3. */
int64_t samaltak_nvrtc_start(const uint8_t *src, uint64_t srcLen, const uint8_t *opts, uint64_t optsLen);
/* -2 while it runs; then 0 if it compiled, NVRTC's error (> 0) if not; -1 for no such job. */
int64_t samaltak_nvrtc_poll(int64_t job);
/* The size of a done job's log (kind 0) or cubin (kind 1), copying as much as fits into out; -1 for no such job, -2 while it runs. */
int64_t samaltak_nvrtc_output(int64_t job, int64_t kind, uint8_t *out, uint64_t outLen);
/* Forget the job (a running one is freed when it ends); 0, or -1 for no such job. */
int64_t samaltak_nvrtc_free(int64_t job);

#endif
