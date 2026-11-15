/* CLBG reverse-complement on fasta 1,000,000 as ReverseComplement (RealWorld.st): line by line, each sequence
   reversed through the complement table, 60 characters to a line. */
#define NAME "ReverseComplement"
#define EXPECTED 739054574
#include "harness.h"
#include "fasta.h"

static Buf input;
static char table[256];

static void write_complement(Buf *out, const Buf *seq)
{
    char *complement = malloc(seq->n + 1);
    for (size_t i = 0; i < seq->n; i++) complement[i] = table[(unsigned char)seq->p[seq->n - 1 - i]];
    for (size_t i = 0; i < seq->n; i += 60) {
        size_t len = seq->n - i < 60 ? seq->n - i : 60;
        buf_puts(out, complement + i, len);
        buf_put(out, '\n');
    }
    free(complement);
}

static int64_t setup(void)
{
    fasta(&input, 1000000);
    return 0;
}

static int64_t run(void)
{
    static const char from[] = "ACGTUMRWSYKVHDBN", to[] = "TGCAAKYWSRMBDHVN";
    for (int i = 0; i < 256; i++) table[i] = (char)i;
    for (int i = 0; from[i]; i++) {
        table[(unsigned char)from[i]] = to[i];
        table[(unsigned char)from[i] + 32] = to[i];
    }
    Buf out = {0}, seq = {0};
    const char *p = input.p, *end = input.p + input.n;
    while (p < end) {
        const char *nl = memchr(p, '\n', (size_t)(end - p));
        const char *line_end = nl ? nl : end;
        size_t len = (size_t)(line_end - p);
        if (len > 0 && p[0] == '>') {
            write_complement(&out, &seq);
            seq.n = 0;
            buf_puts(&out, p, len);
            buf_put(&out, '\n');
        } else {
            buf_puts(&seq, p, len);
        }
        p = nl ? nl + 1 : end;
    }
    write_complement(&out, &seq);
    int64_t sum = checksum(out.p, out.n);
    free(out.p);
    free(seq.p);
    return sum;
}
