#include <stdlib.h>
#include <inttypes.h>

struct sha1_context {
    uint32_t h[5];
    unsigned char buf[64];
    short len;
    uint64_t total;
};

/* Exported functions. */
void sha1_init(struct sha1_context *);
void sha1_update(struct sha1_context *, char *, size_t);
void sha1_final(struct sha1_context *, unsigned char * /* [20] */);
