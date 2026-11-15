/* CLBG spectral-norm, n = 1000, as SpectralNorm (RealWorld.st): the norm times 10^9, rounded. */
#define NAME "SpectralNorm"
#define EXPECTED 1274224148
#include "harness.h"
#include <math.h>

static double a(int64_t i, int64_t j)
{
    /* the matrix element, 1-based */
    int64_t ij = i + j - 2;
    return 1.0 / (ij * (ij + 1) / 2 + i);
}

static void multiply_av(int n, const double *v, double *av)
{
    for (int i = 1; i <= n; i++) {
        double sum = 0.0;
        for (int j = 1; j <= n; j++) sum += a(i, j) * v[j - 1];
        av[i - 1] = sum;
    }
}

static void multiply_atv(int n, const double *v, double *atv)
{
    for (int i = 1; i <= n; i++) {
        double sum = 0.0;
        for (int j = 1; j <= n; j++) sum += a(j, i) * v[j - 1];
        atv[i - 1] = sum;
    }
}

static void multiply_atav(int n, const double *v, double *out, double *tmp)
{
    multiply_av(n, v, tmp);
    multiply_atv(n, tmp, out);
}

static int64_t setup(void) { return 0; }

static int64_t run(void)
{
    const int n = 1000;
    double *u = malloc(n * sizeof(double)), *v = malloc(n * sizeof(double)), *tmp = malloc(n * sizeof(double));
    for (int i = 0; i < n; i++) u[i] = 1.0;
    for (int k = 0; k < 10; k++) {
        multiply_atav(n, u, v, tmp);
        multiply_atav(n, v, u, tmp);
    }
    double vbv = 0.0, vv = 0.0;
    for (int i = 0; i < n; i++) {
        vbv += u[i] * v[i];
        vv += v[i] * v[i];
    }
    int64_t result = llround(sqrt(vbv / vv) * 1000000000);
    free(u);
    free(v);
    free(tmp);
    return result;
}
