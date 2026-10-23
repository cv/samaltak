/* Image load (with relocation) and snapshot. */
#include "core.h"
#include <stdlib.h>
#include <string.h>

char *image_path;

typedef struct {
    char magic[8];
    uint64_t version, header_size, heap_bytes, base, specials, hash_seed, reserved;
} image_header;

void load_image(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (!f) fatal("cannot open image %s", path);
    image_header h;
    if (fread(&h, sizeof h, 1, f) != 1 || memcmp(h.magic, "SAMALTK1", 8) || h.version != 1)
        fatal("%s is not a Samaltak image", path);
    if (h.heap_bytes > max_heap_bytes) fatal("image too large for heap limit");
    fseek(f, (long)h.header_size, SEEK_SET);
    if (fread(old_lo, 1, h.heap_bytes, f) != h.heap_bytes) fatal("truncated image %s", path);
    fclose(f);
    int64_t delta = (int64_t)((uint64_t)old_lo - h.base);
    old_top = old_lo + h.heap_bytes;
    for (char *p = old_lo; p < old_top; p += obj_bytes((oop)p)) {
        oop o = (oop)p;
        *hdr_ptr(o) &= ~H_GCBITS;
        ((oop *)o)[1] += (uint64_t)delta;
        if (fmt_has_pointers(format_of(o))) {
            oop *s = slots(o);
            for (uint32_t i = 0, n = num_slots(o); i < n; i++)
                if (is_ptr(s[i]) && s[i]) s[i] += (uint64_t)delta;
        }
    }
    specials_oop = h.specials + (uint64_t)delta;
    hash_seed = h.hash_seed;
    size_t budget = 2 * h.heap_bytes;
    if (budget > old_budget) old_budget = budget < max_heap_bytes ? budget : max_heap_bytes;
    image_path = realpath(path, NULL);
    if (!image_path && !(image_path = strdup(path))) fatal("out of memory");
    refresh_specials();
}

bool write_snapshot(const char *path)
{
    full_gc();
    image_header h = {.version = 1, .header_size = 64};
    memcpy(h.magic, "SAMALTK1", 8);
    h.heap_bytes = (uint64_t)(old_top - old_lo);
    h.base = (uint64_t)old_lo;
    h.specials = specials_oop;
    h.hash_seed = hash_seed;
    FILE *f = fopen(path, "wb");
    if (!f) return false;
    bool ok = fwrite(&h, sizeof h, 1, f) == 1 && fwrite(old_lo, 1, h.heap_bytes, f) == h.heap_bytes;
    return fclose(f) == 0 && ok;
}
