/* The key table of the crypto backends (crypto.h): slots with a generation, the least recently used reused. A
   backend defines key_destroy(slot) before including this. */
#include <stdint.h>
#include <stddef.h>
#include "crypto.h"

typedef struct {
    int kind;          /* 0: free, else the backend's */
    uint32_t gen;
    uint64_t used;
    void *object;
} key_slot;

static key_slot slots[SAMALTAK_CRYPTO_KEYS];
static uint64_t clockTicks;
static void key_destroy(key_slot *s);

/* the slot of handle h, of kind, or NULL (stale or wrong) */
static key_slot *key_get(int64_t h, int kind)
{
    int64_t i = (h & 0xFF) - 1;
    uint32_t gen = (uint32_t)((h >> 8) & 0xFFFF);
    if (i < 0 || i >= SAMALTAK_CRYPTO_KEYS) return NULL;
    key_slot *s = &slots[i];
    if (s->kind != kind || s->gen != gen) return NULL;
    s->used = ++clockTicks;
    return s;
}
/* a slot for a new key: a free one, else the least recently used, emptied */
static key_slot *key_new(int kind, void *object)
{
    key_slot *best = &slots[0];
    for (int i = 0; i < SAMALTAK_CRYPTO_KEYS; i++) {
        if (slots[i].kind == 0) { best = &slots[i]; break; }
        if (slots[i].used < best->used) best = &slots[i];
    }
    if (best->kind != 0) key_destroy(best);
    best->kind = kind;
    best->gen = (best->gen + 1) & 0xFFFF;
    if (best->gen == 0) best->gen = 1;
    best->used = ++clockTicks;
    best->object = object;
    return best;
}
static int64_t key_handle(key_slot *s) { return (int64_t)(s - slots) + 1 + ((int64_t)s->gen << 8); }
