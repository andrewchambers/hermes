#include <stdlib.h>
#include <inttypes.h>

typedef struct Sha1ctx Sha1ctx;

struct Sha1ctx {
    uint32_t h[5];
    unsigned char buf[64];
    short len;
    uint64_t total;
};

/* Exported functions. */
void sha1_init(Sha1ctx *);
void sha1_update(Sha1ctx *, char *, size_t);
void sha1_final(Sha1ctx *, unsigned char * /* [20] */);
