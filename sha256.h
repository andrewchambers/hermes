#include <stddef.h>
#include <inttypes.h>

typedef struct Sha256ctx Sha256ctx;

struct Sha256ctx {
    uint8_t buf[64];
    uint64_t count;
    uint32_t val[8];
};


void sha256_update(Sha256ctx *ctx, uint8_t *buf, size_t len);
void sha256_init(Sha256ctx *ctx);
void sha256_finish(Sha256ctx *ctx, uint8_t dst[32]);