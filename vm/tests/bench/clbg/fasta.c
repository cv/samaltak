/* CLBG fasta, n = 1,000,000, into a growing buffer: as Fasta (RealWorld.st). */
#define NAME "Fasta"
#define EXPECTED 971412559
#include "harness.h"
#include "fasta.h"

static int64_t setup(void) { return 0; }

static int64_t run(void)
{
    Buf out = {0};
    fasta(&out, 1000000);
    int64_t sum = checksum(out.p, out.n);
    free(out.p);
    return sum;
}
