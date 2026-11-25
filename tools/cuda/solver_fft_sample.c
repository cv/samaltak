/* The cuSOLVER and cuFFT numbers of docs/cuda.md in C, beside CPU references: a 4096 x 4096 LU and solve
   (cusolverDnSgetrf + Sgetrs; LAPACK's sgetrf_ + sgetrs_ on the CPU), the singular values and vectors of a
   2048 x 1024 matrix (cusolverDnSgesvd, thin; LAPACK's sgesvd_), and a 4096 x 4096 real-to-complex 2-D FFT
   (cufftExecR2C with a plan made once; FFTW's fftwf_plan_dft_r2c_2d, one thread and all), float32 throughout.
   CudaBenchmark measures the same from Smalltalk; the difference is the bindings' cost.

   cc -O2 -o /tmp/solver_fft_sample tools/cuda/solver_fft_sample.c -I/usr/local/cuda/include \
      -L/usr/local/cuda/lib64 -Wl,-rpath,/usr/local/cuda/lib64 -lcusolver -lcufft -lcudart \
      -l:liblapack.so.3 -l:libfftw3f.so.3 -l:libfftw3f_threads.so.3 -lm
   /tmp/solver_fft_sample [cpu]     (cpu: also the LAPACK and FFTW references; LAPACK here is the reference
                                     implementation on the reference BLAS, a minute or two) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>
#include <cuda_runtime.h>
#include <cusolverDn.h>
#include <cufft.h>

void sgetrf_(const int *m, const int *n, float *a, const int *lda, int *ipiv, int *info);
void sgetrs_(const char *trans, const int *n, const int *nrhs, const float *a, const int *lda, const int *ipiv,
             float *b, const int *ldb, int *info);
void sgesvd_(const char *jobu, const char *jobvt, const int *m, const int *n, float *a, const int *lda, float *s,
             float *u, const int *ldu, float *vt, const int *ldvt, float *work, const int *lwork, int *info);
typedef struct fftwf_plan_s *fftwf_plan;
typedef float fftwf_complex[2];
fftwf_plan fftwf_plan_dft_r2c_2d(int n0, int n1, float *in, fftwf_complex *out, unsigned flags);
void fftwf_execute(fftwf_plan p);
void fftwf_destroy_plan(fftwf_plan p);
int fftwf_init_threads(void);
void fftwf_plan_with_nthreads(int n);
#define FFTW_ESTIMATE (1U << 6)

#define CK(x) do { int e_ = (int)(x); if (e_) { fprintf(stderr, "%s: %d\n", #x, e_); exit(1); } } while (0)

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec * 1e-9;
}

static float *randoms(size_t n, unsigned seed) {
    float *a = malloc(n * sizeof(float));
    srand(seed);
    for (size_t i = 0; i < n; i++) a[i] = (float)rand() / RAND_MAX - 0.5f;
    return a;
}

static float gpu_ms(cudaEvent_t a, cudaEvent_t b) {
    float ms;
    cudaEventSynchronize(b);
    cudaEventElapsedTime(&ms, a, b);
    return ms;
}

int main(int argc, char **argv) {
    int cpu = argc > 1 && !strcmp(argv[1], "cpu");
    cusolverDnHandle_t h;
    cudaEvent_t e0, e1, e2;
    CK(cusolverDnCreate(&h));
    cudaEventCreate(&e0); cudaEventCreate(&e1); cudaEventCreate(&e2);

    /* LU and solve, n = 4096 */
    {
        int n = 4096, lwork, info, one = 1;
        float *a = randoms((size_t)n * n, 1), *b = randoms(n, 2), *da, *db, *dw;
        int *dpiv, *dinfo;
        for (int i = 0; i < n; i++) a[(size_t)i * n + i] += n / 8.0f;
        CK(cudaMalloc((void **)&da, (size_t)n * n * 4)); CK(cudaMalloc((void **)&db, n * 4));
        CK(cudaMalloc((void **)&dpiv, n * 4)); CK(cudaMalloc((void **)&dinfo, 4));
        CK(cusolverDnSgetrf_bufferSize(h, n, n, da, n, &lwork));
        CK(cudaMalloc((void **)&dw, (size_t)lwork * 4));
        for (int rep = 0; rep < 3; rep++) {
            cudaMemcpy(da, a, (size_t)n * n * 4, cudaMemcpyHostToDevice);
            cudaMemcpy(db, b, n * 4, cudaMemcpyHostToDevice);
            cudaEventRecord(e0, 0);
            CK(cusolverDnSgetrf(h, n, n, da, n, dw, dpiv, dinfo));
            cudaEventRecord(e1, 0);
            CK(cusolverDnSgetrs(h, CUBLAS_OP_N, n, 1, da, n, dpiv, db, n, dinfo));
            cudaEventRecord(e2, 0);
            cudaMemcpy(&info, dinfo, 4, cudaMemcpyDeviceToHost);
            if (rep == 2) printf("GPU LU %d: getrf %.2f ms (%.0f GFLOPS), getrs %.3f ms, info %d\n", n, gpu_ms(e0, e1),
                                 2.0 / 3 * n * (double)n * n / gpu_ms(e0, e1) / 1e6, gpu_ms(e1, e2), info);
        }
        if (cpu) {
            int *piv = malloc(n * sizeof(int));
            double t = now();
            sgetrf_(&n, &n, a, &n, piv, &info);
            double t1 = now();
            sgetrs_("N", &n, &one, a, &n, piv, b, &n, &info);
            printf("CPU LAPACK (reference) LU %d: sgetrf %.2f s (%.2f GFLOPS), sgetrs %.1f ms\n", n, t1 - t,
                   2.0 / 3 * n * (double)n * n / (t1 - t) / 1e9, (now() - t1) * 1e3);
            free(piv);
        }
        cudaFree(da); cudaFree(db); cudaFree(dw); cudaFree(dpiv); cudaFree(dinfo); free(a); free(b);
    }

    /* SVD of 2048 x 1024 (column-major m x n, m >= n), thin vectors */
    {
        int m = 2048, n = 1024, lwork, info;
        float *a = randoms((size_t)m * n, 3), *da, *ds, *du, *dvt, *dw, *drw;
        int *dinfo;
        CK(cudaMalloc((void **)&da, (size_t)m * n * 4)); CK(cudaMalloc((void **)&ds, n * 4));
        CK(cudaMalloc((void **)&du, (size_t)m * n * 4)); CK(cudaMalloc((void **)&dvt, (size_t)n * n * 4));
        CK(cudaMalloc((void **)&drw, n * 4)); CK(cudaMalloc((void **)&dinfo, 4));
        CK(cusolverDnSgesvd_bufferSize(h, m, n, &lwork));
        CK(cudaMalloc((void **)&dw, (size_t)lwork * 4));
        for (int rep = 0; rep < 2; rep++) {
            cudaMemcpy(da, a, (size_t)m * n * 4, cudaMemcpyHostToDevice);
            cudaEventRecord(e0, 0);
            CK(cusolverDnSgesvd(h, 'S', 'S', m, n, da, m, ds, du, m, dvt, n, dw, lwork, drw, dinfo));
            cudaEventRecord(e1, 0);
            cudaMemcpy(da, a, (size_t)m * n * 4, cudaMemcpyHostToDevice);
            CK(cusolverDnSgesvd(h, 'N', 'N', m, n, da, m, ds, du, m, dvt, n, dw, lwork, drw, dinfo));
            cudaEventRecord(e2, 0);
            cudaMemcpy(&info, dinfo, 4, cudaMemcpyDeviceToHost);
            if (rep == 1) printf("GPU SVD %dx%d: with vectors %.1f ms, values only %.1f ms, info %d\n", m, n,
                                 gpu_ms(e0, e1), gpu_ms(e1, e2) - 0.0, info);
        }
        if (cpu) {
            float *s = malloc(n * 4), *u = malloc((size_t)m * n * 4), *vt = malloc((size_t)n * n * 4), q;
            int query = -1;
            sgesvd_("S", "S", &m, &n, a, &m, s, u, &m, vt, &n, &q, &query, &info);
            int lw = (int)q;
            float *w = malloc((size_t)lw * 4);
            double t = now();
            sgesvd_("S", "S", &m, &n, a, &m, s, u, &m, vt, &n, w, &lw, &info);
            printf("CPU LAPACK (reference) SVD %dx%d: sgesvd with vectors %.2f s, info %d\n", m, n, now() - t, info);
            free(s); free(u); free(vt); free(w);
        }
        cudaFree(da); cudaFree(ds); cudaFree(du); cudaFree(dvt); cudaFree(dw); cudaFree(drw); cudaFree(dinfo); free(a);
    }

    /* 2-D real-to-complex FFT, 4096 x 4096 */
    {
        int n = 4096, reps = 20;
        size_t real = (size_t)n * n, half = (size_t)n * (n / 2 + 1);
        float *a = randoms(real, 4), *da;
        cufftComplex *dc;
        cufftHandle plan;
        CK(cudaMalloc((void **)&da, real * 4)); CK(cudaMalloc((void **)&dc, half * 8));
        cudaMemcpy(da, a, real * 4, cudaMemcpyHostToDevice);
        double t = now();
        CK(cufftPlan2d(&plan, n, n, CUFFT_R2C));
        double tp = now() - t;
        CK(cufftExecR2C(plan, da, dc));
        cudaDeviceSynchronize();
        cudaEventRecord(e0, 0);
        for (int i = 0; i < reps; i++) CK(cufftExecR2C(plan, da, dc));
        cudaEventRecord(e1, 0);
        float ms = gpu_ms(e0, e1) / reps;
        printf("GPU FFT R2C %dx%d: %.3f ms (%.0f GFLOPS by 2.5 N log2 N), plan %.1f ms\n", n, n, ms,
               2.5 * real * log2((double)real) / ms / 1e6, tp * 1e3);
        cufftDestroy(plan);
        if (cpu) {
            fftwf_complex *c = malloc(half * sizeof(fftwf_complex));
            fftwf_init_threads();
            for (int threads = 1; threads <= 20; threads += 19) {
                fftwf_plan_with_nthreads(threads);
                fftwf_plan p = fftwf_plan_dft_r2c_2d(n, n, a, c, FFTW_ESTIMATE);
                fftwf_execute(p);
                t = now();
                fftwf_execute(p);
                printf("CPU FFTW R2C %dx%d, %d thread%s: %.1f ms\n", n, n, threads, threads > 1 ? "s" : "", (now() - t) * 1e3);
                fftwf_destroy_plan(p);
            }
            free(c);
        }
        cudaFree(da); cudaFree(dc); free(a);
    }
    cusolverDnDestroy(h);
    return 0;
}
