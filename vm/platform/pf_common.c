/* Handle tables, error string, clock. */
#include "platform.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static char last_error[1024];

const char *pf_last_error(void) { return last_error; }

void pf_set_error(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(last_error, sizeof last_error, fmt, ap);
    va_end(ap);
}

int64_t pf_now_ms(void)
{
    static int64_t base = -1;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    int64_t ms = (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
    if (base < 0) base = ms;
    return ms - base;
}

/* Slot 0 is never used so 0 can mean "no handle". Free slots form a list
 * through pf_obj.i. */
int pf_table_add(pf_table *t, int kind, void *ptr)
{
    int h;
    if (t->free_head) {
        h = t->free_head;
        t->free_head = (int)t->v[h].i;
    } else {
        if (t->n == 0) t->n = 1;
        if (t->n >= t->cap) {
            int cap = t->cap ? t->cap * 2 : 64;
            pf_obj *v = realloc(t->v, sizeof *v * cap);
            if (!v) return 0;
            t->v = v;
            t->cap = cap;
        }
        h = t->n++;
    }
    memset(&t->v[h], 0, sizeof t->v[h]);
    t->v[h].kind = kind;
    t->v[h].ptr = ptr;
    return h;
}

pf_obj *pf_table_get(pf_table *t, int h, int kind)
{
    if (h <= 0 || h >= t->n || t->v[h].kind == 0) return NULL;
    if (kind >= 0 && t->v[h].kind != kind) return NULL;
    return &t->v[h];
}

void pf_table_remove(pf_table *t, int h)
{
    if (h <= 0 || h >= t->n || t->v[h].kind == 0) return;
    t->v[h].kind = 0;
    t->v[h].ptr = NULL;
    t->v[h].i = t->free_head;
    t->free_head = h;
}

int pf_table_count(const pf_table *t, int kind)
{
    int n = 0;
    for (int h = 1; h < t->n; h++)
        if (t->v[h].kind && (kind < 0 || t->v[h].kind == kind)) n++;
    return n;
}

void pf_handle_counts(int64_t out[PF_HANDLE_COUNTS])
{
    out[0] = pf_file_handle_count();
    out[1] = pf_socket_handle_count();
    out[2] = pf_window_handle_count();
    pf_gpu_handle_counts(out + 3);
}
