/* Basic C versions of the Shootout (CLBG) programs the benchmark suites run, doing the work of their
   Smalltalk versions (awfy/RealWorld.st, awfy/Mandelbrot.st, awfy/NBody.st): same sizes, same algorithm,
   same checksum. Each iteration's CPU time is printed as the Smalltalk harness prints it: name,iteration,us.
   A program defines NAME, EXPECTED, setup() (untimed, like a benchmark's initialize) and run(). */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int64_t setup(void);
static int64_t run(void);

static int64_t cpu_us(void)
{
    struct timespec t;
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t);
    return (int64_t)t.tv_sec * 1000000 + t.tv_nsec / 1000;
}

/* A growable byte buffer: the WriteStream of the Smalltalk versions. */
typedef struct { char *p; size_t n, cap; } Buf;

static void buf_put(Buf *b, char c)
{
    if (b->n == b->cap) {
        b->cap = b->cap ? b->cap * 2 : 1024;
        b->p = realloc(b->p, b->cap);
    }
    b->p[b->n++] = c;
}

static void buf_puts(Buf *b, const char *s, size_t n)
{
    while (b->n + n > b->cap) {
        b->cap = b->cap ? b->cap * 2 : 1024;
        b->p = realloc(b->p, b->cap);
    }
    memcpy(b->p + b->n, s, n);
    b->n += n;
}

/* Fasta's checksum: the size plus every character's code. */
static int64_t checksum(const char *s, size_t n)
{
    int64_t sum = (int64_t)n;
    for (size_t i = 0; i < n; i++) sum += (unsigned char)s[i];
    return sum;
}

int main(int argc, char **argv)
{
    int iterations = argc > 1 ? atoi(argv[1]) : 10;
    setup();
    for (int i = 1; i <= iterations; i++) {
        int64_t t0 = cpu_us();
        int64_t result = run();
        int64_t t1 = cpu_us();
        if (result != EXPECTED) {
            fprintf(stderr, "%s: wrong result %lld (expected %lld)\n", NAME, (long long)result, (long long)EXPECTED);
            return 1;
        }
        printf("%s,%d,%lld\n", NAME, i, (long long)(t1 - t0));
        fflush(stdout);
    }
    return 0;
}
