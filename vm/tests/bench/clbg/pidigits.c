/* CLBG pidigits, 4000 digits, as Pidigits (RealWorld.st): the spigot on GMP integers; the digits' sum plus the
   last ten digits as an integer. */
#define NAME "Pidigits"
#define EXPECTED 7211184236
#include "harness.h"
#include <gmp.h>

static int64_t setup(void) { return 0; }

static int64_t run(void)
{
    const int n = 4000;
    char *digits = malloc(n + 1);
    mpz_t numer, accum, denom, t1, t2;
    mpz_init_set_ui(numer, 1);
    mpz_init_set_ui(accum, 0);
    mpz_init_set_ui(denom, 1);
    mpz_init(t1);
    mpz_init(t2);
    int i = 0;
    unsigned long k = 0;
    while (i < n) {
        k++;
        unsigned long k2 = k * 2 + 1;
        /* accum := accum + (numer * 2) * k2; denom := denom * k2; numer := numer * k */
        mpz_addmul_ui(accum, numer, 2);
        mpz_mul_ui(accum, accum, k2);
        mpz_mul_ui(denom, denom, k2);
        mpz_mul_ui(numer, numer, k);
        if (mpz_cmp(numer, accum) > 0) continue;
        /* d := numer * 3 + accum // denom */
        mpz_mul_ui(t1, numer, 3);
        mpz_add(t1, t1, accum);
        mpz_fdiv_q(t1, t1, denom);
        /* d = (numer * 4 + accum // denom) */
        mpz_mul_ui(t2, numer, 4);
        mpz_add(t2, t2, accum);
        mpz_fdiv_q(t2, t2, denom);
        if (mpz_cmp(t1, t2) != 0) continue;
        unsigned long d = mpz_get_ui(t1);
        digits[i++] = (char)('0' + d);
        /* accum := accum - (denom * d) * 10; numer := numer * 10 */
        mpz_submul_ui(accum, denom, d);
        mpz_mul_ui(accum, accum, 10);
        mpz_mul_ui(numer, numer, 10);
    }
    digits[n] = 0;
    int64_t sum = 0;
    for (int j = 0; j < n; j++) sum += digits[j] - '0';
    int64_t last10 = strtoll(digits + n - 10, NULL, 10);
    mpz_clear(numer);
    mpz_clear(accum);
    mpz_clear(denom);
    mpz_clear(t1);
    mpz_clear(t2);
    free(digits);
    return sum + last10;
}
