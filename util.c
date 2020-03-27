#include <janet.h>
#include "hermes.h"

static void safe_memcpy(void *dest, const void *src, size_t len) {
    if (!len) return;
    memcpy(dest, src, len);
}

/* Grow the buffer dynamically. Used for push operations. */
void *scratch_v_grow(void *v, int32_t increment, int32_t itemsize) {
    int32_t dbl_cur = (NULL != v) ? 2 * scratch_v__cap(v) : 0;
    int32_t min_needed = scratch_v_count(v) + increment;
    int32_t m = dbl_cur > min_needed ? dbl_cur : min_needed;
    size_t newsize = ((size_t) itemsize) * m + sizeof(int32_t) * 2;
    int32_t *p = (int32_t *) janet_srealloc(v ? scratch_v__raw(v) : 0, newsize);
    if (!v) p[1] = 0;
    p[0] = m;
    return p + 2;
}

/* Convert a buffer to normal allocated memory (forget capacity) */
void *scratch_v_flattenmem(void *v, int32_t itemsize) {
    int32_t *p;
    if (NULL == v) return NULL;
    size_t size = (size_t) itemsize * scratch_v__cnt(v);
    p = malloc(size);
    if (NULL != p) {
        safe_memcpy(p, v, size);
        return p;
    } else {
        abort();
    }
}

