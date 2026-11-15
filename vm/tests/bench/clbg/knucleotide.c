/* CLBG k-nucleotide on fasta 75,000 as KNucleotide (RealWorld.st): sequence THREE in upper case, the 1- and
   2-nucleotide frequencies sorted, the counts of five sequences; a table of all k-mers for each k (a hash table
   of positions in the sequence, open addressing). */
#define NAME "KNucleotide"
#define EXPECTED 13126
#include "harness.h"
#include "fasta.h"

static Buf input;

typedef struct { int64_t pos; int64_t count; } Entry;
typedef struct { Entry *e; int64_t cap, size; const char *seq; int k; } Table;

static uint64_t hash(const char *s, int k)
{
    uint64_t h = 1469598103934665603ull;
    for (int i = 0; i < k; i++) h = (h ^ (unsigned char)s[i]) * 1099511628211ull;
    return h;
}

static Entry *find(Table *t, const char *key)
{
    uint64_t i = hash(key, t->k) & (uint64_t)(t->cap - 1);
    for (;;) {
        Entry *e = &t->e[i];
        if (e->count == 0 || memcmp(t->seq + e->pos, key, (size_t)t->k) == 0) return e;
        i = (i + 1) & (uint64_t)(t->cap - 1);
    }
}

static void frequencies(Table *t, const char *seq, int64_t n, int k)
{
    t->cap = 1;
    while (t->cap < 2 * n) t->cap *= 2;
    t->e = calloc((size_t)t->cap, sizeof(Entry));
    t->size = 0;
    t->seq = seq;
    t->k = k;
    for (int64_t i = 0; i + k <= n; i++) {
        Entry *e = find(t, seq + i);
        if (e->count == 0) {
            e->pos = i;
            t->size++;
        }
        e->count++;
    }
}

static const Table *sort_table;

static int by_count_then_key(const void *a, const void *b)
{
    const Entry *x = a, *y = b;
    if (x->count != y->count) return x->count > y->count ? -1 : 1;
    return memcmp(sort_table->seq + x->pos, sort_table->seq + y->pos, (size_t)sort_table->k);
}

static int64_t setup(void)
{
    fasta(&input, 75000);
    return 0;
}

static int64_t run(void)
{
    /* sequence THREE, upper case, without line ends */
    Buf seq = {0};
    const char *p = input.p, *end = input.p + input.n;
    int found = 0;
    while (p < end) {
        const char *nl = memchr(p, '\n', (size_t)(end - p));
        const char *line_end = nl ? nl : end;
        size_t len = (size_t)(line_end - p);
        if (!found) {
            if (len >= 6 && memcmp(p, ">THREE", 6) == 0) found = 1;
        } else {
            if (len == 0 || p[0] == '>') break;
            for (size_t i = 0; i < len; i++) buf_put(&seq, (char)(p[i] >= 'a' && p[i] <= 'z' ? p[i] - 32 : p[i]));
        }
        p = nl ? nl + 1 : end;
    }
    Buf out = {0};
    char line[64];
    for (int k = 1; k <= 2; k++) {
        int64_t total = (int64_t)seq.n - k + 1;
        Table t;
        frequencies(&t, seq.p, (int64_t)seq.n, k);
        Entry *entries = malloc((size_t)t.size * sizeof(Entry));
        int64_t m = 0;
        for (int64_t i = 0; i < t.cap; i++)
            if (t.e[i].count > 0) entries[m++] = t.e[i];
        sort_table = &t;
        qsort(entries, (size_t)m, sizeof(Entry), by_count_then_key);
        for (int64_t i = 0; i < m; i++) {
            buf_puts(&out, seq.p + entries[i].pos, (size_t)k);
            int n = snprintf(line, sizeof line, " %.3f\n", entries[i].count * 100.0 / total);
            buf_puts(&out, line, (size_t)n);
        }
        buf_put(&out, '\n');
        free(entries);
        free(t.e);
    }
    static const char *const queries[] = {"GGT", "GGTA", "GGTATT", "GGTATTTTAATT", "GGTATTTTAATTTATAGT"};
    for (int q = 0; q < 5; q++) {
        int k = (int)strlen(queries[q]);
        Table t;
        frequencies(&t, seq.p, (int64_t)seq.n, k);
        Entry *e = find(&t, queries[q]);
        int n = snprintf(line, sizeof line, "%lld\t%s\n", (long long)e->count, queries[q]);
        buf_puts(&out, line, (size_t)n);
        free(t.e);
    }
    int64_t sum = checksum(out.p, out.n);
    free(out.p);
    free(seq.p);
    return sum;
}
