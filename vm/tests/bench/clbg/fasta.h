/* CLBG fasta as Fasta>>fasta: (RealWorld.st): its text for n, into a Buf. */

static const char ALU[] =
    "GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGGGAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTCGAGACCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAATACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTGTAATCCCAGCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACCCGGGAGGCGGAGGTTGCAGTGAGCCGAGATCGCGCCACTGCACTCCAGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAA";

typedef struct { char c; double p; } Pair;

static const Pair IUB[] = {
    {'a', 0.27}, {'c', 0.12}, {'g', 0.12}, {'t', 0.27}, {'B', 0.02}, {'D', 0.02}, {'H', 0.02}, {'K', 0.02},
    {'M', 0.02}, {'N', 0.02}, {'R', 0.02}, {'S', 0.02}, {'V', 0.02}, {'W', 0.02}, {'Y', 0.02}};

static const Pair HOMO_SAPIENS[] = {
    {'a', 0.3029549426680}, {'c', 0.1979883004921}, {'g', 0.1975473066391}, {'t', 0.3015094502008}};

static int64_t fasta_last;

static double next_random(double max)
{
    fasta_last = (fasta_last * 3877 + 29573) % 139968;
    return max * fasta_last / 139968;
}

static void fasta_repeat(Buf *out, const char *s, int64_t n)
{
    int64_t len = (int64_t)strlen(s), i = 0;
    for (int64_t k = 1; k <= n; k++) {
        i = i % len + 1;
        buf_put(out, s[i - 1]);
        if (k % 60 == 0) buf_put(out, '\n');
    }
    if (n % 60 != 0) buf_put(out, '\n');
}

static void fasta_random(Buf *out, const Pair *pairs, int size, int64_t n)
{
    double cumulative[16], sum = 0.0;
    for (int i = 0; i < size; i++) {
        sum += pairs[i].p;
        cumulative[i] = sum;
    }
    for (int64_t k = 1; k <= n; k++) {
        double r = next_random(1.0);
        int j = 1;
        while (j < size && r >= cumulative[j - 1]) j++;
        buf_put(out, pairs[j - 1].c);
        if (k % 60 == 0) buf_put(out, '\n');
    }
    if (n % 60 != 0) buf_put(out, '\n');
}

static void fasta(Buf *out, int64_t n)
{
    static const char one[] = ">ONE Homo sapiens alu\n", two[] = ">TWO IUB ambiguity codes\n", three[] = ">THREE Homo sapiens frequency\n";
    out->n = 0;
    fasta_last = 42;
    buf_puts(out, one, sizeof one - 1);
    fasta_repeat(out, ALU, n * 2);
    buf_puts(out, two, sizeof two - 1);
    fasta_random(out, IUB, (int)(sizeof IUB / sizeof IUB[0]), n * 3);
    buf_puts(out, three, sizeof three - 1);
    fasta_random(out, HOMO_SAPIENS, (int)(sizeof HOMO_SAPIENS / sizeof HOMO_SAPIENS[0]), n * 5);
}
