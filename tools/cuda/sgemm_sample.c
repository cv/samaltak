/* CUDA's own SGEMM, the baseline for Samaltak's binding (docs/cuda.md): n x n single precision,
   operands filled by cuRAND, timed with CUDA events. Build: cc -O2 -I/usr/local/cuda/include tools/cuda/sgemm_sample.c
   -L/usr/local/cuda/lib64 -lcublas -lcurand -lcudart -o sgemm_sample; run: ./sgemm_sample [n] [reps]. */
#include <cublas_v2.h>
#include <cuda_runtime_api.h>
#include <curand.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define CHECK(x) do { int s_ = (int)(x); if (s_) { fprintf(stderr, "%s: %d\n", #x, s_); exit(1); } } while (0)

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }

int main(int argc, char **argv) {
    int n = argc > 1 ? atoi(argv[1]) : 4096, reps = argc > 2 ? atoi(argv[2]) : 10;
    size_t bytes = (size_t)n * n * sizeof(float);
    float *a, *b, *c, alpha = 1, beta = 0, ms = 0;
    double t0 = now();
    CHECK(cudaFree(0));
    double tInit = now() - t0;
    CHECK(cudaMalloc((void **)&a, bytes)); CHECK(cudaMalloc((void **)&b, bytes)); CHECK(cudaMalloc((void **)&c, bytes));
    curandGenerator_t g;
    CHECK(curandCreateGenerator(&g, CURAND_RNG_PSEUDO_DEFAULT));
    CHECK(curandSetPseudoRandomGeneratorSeed(g, 42));
    CHECK(curandGenerateUniform(g, a, (size_t)n * n)); CHECK(curandGenerateUniform(g, b, (size_t)n * n));
    cublasHandle_t h;
    CHECK(cublasCreate(&h));
    CHECK(cublasSgemm(h, CUBLAS_OP_N, CUBLAS_OP_N, n, n, n, &alpha, a, n, b, n, &beta, c, n));
    CHECK(cudaDeviceSynchronize());
    cudaEvent_t e0, e1;
    CHECK(cudaEventCreate(&e0)); CHECK(cudaEventCreate(&e1));
    double w0 = now();
    CHECK(cudaEventRecord(e0, 0));
    for (int i = 0; i < reps; i++) CHECK(cublasSgemm(h, CUBLAS_OP_N, CUBLAS_OP_N, n, n, n, &alpha, a, n, b, n, &beta, c, n));
    CHECK(cudaEventRecord(e1, 0));
    CHECK(cudaEventSynchronize(e1));
    double wall = now() - w0;
    CHECK(cudaEventElapsedTime(&ms, e0, e1));
    double flops = 2.0 * n * n * (double)n;
    printf("n=%d reps=%d init=%.3fs gpu=%.3fms/gemm wall=%.3fms/gemm tflops=%.2f\n", n, reps, tInit, ms / reps,
           wall * 1e3 / reps, flops / (ms / reps * 1e-3) / 1e12);
    cublasDestroy(h); curandDestroyGenerator(g); cudaFree(a); cudaFree(b); cudaFree(c);
    return 0;
}
