/*
 * SHA-1 home brewed implementation.
 * Because that was not so hard.
 */
#include <assert.h>
#include <limits.h>
#include <string.h>
#include "sha1.h"

struct dummy_test { /* Compile time test of the poor. */
  int check_0 : sizeof(uint32_t) * CHAR_BIT == 32;
  int check_1 : sizeof(uint64_t) * CHAR_BIT == 64;
};

static uint32_t magic[] = {
  0x67452301, 0xefcdab89,
  0x98badcfe, 0x10325476,
  0xc3d2e1f0
};

static inline uint32_t
ldbe32(unsigned char *p)
{
  return
    ((uint32_t)p[0] << 24) +
    ((uint32_t)p[1] << 16) +
    ((uint32_t)p[2] << 8) +
    (uint32_t)p[3];
}

static inline void
stbe32(unsigned char *p, uint32_t x)
{
  p[0] = (x >> 24) & 0xff;
  p[1] = (x >> 16) & 0xff;
  p[2] = (x >> 8) & 0xff;
  p[3] = x & 0xff;
}

static inline uint32_t
lrot(uint32_t x, int count)
{
  return (x << count) | (x >> (32 - count));
}

#define X(k) do {                                      \
  tmp = lrot(a, 5) + f + e + k + *pw++;          \
  e = d; d = c; c = lrot(b, 30); b = a; a = tmp; \
} while (0)
#define F1 f = (b & c) | (~b & d)
#define F2 f = b ^ c ^ d
#define F3 f = (b & c) | (b & d) | (c & d)

static void
munch(struct sha1_context *ctx, unsigned char *bytes)
{
  uint32_t w[80], *pw;
  uint32_t a, b, c, d, e, f, tmp;
  int i;

  for (i = 0; i < 16; i++)
    w[i] = ldbe32(&bytes[i*4]);

  for (; i < 80; i++)
    w[i] = lrot(w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16], 1);

  pw = w;
  a = ctx->h[0];
  b = ctx->h[1];
  c = ctx->h[2];
  d = ctx->h[3];
  e = ctx->h[4];

  F1; X(0x5a827999); F1; X(0x5a827999);
  F1; X(0x5a827999); F1; X(0x5a827999);
  F1; X(0x5a827999); F1; X(0x5a827999);
  F1; X(0x5a827999); F1; X(0x5a827999);
  F1; X(0x5a827999); F1; X(0x5a827999);
  F1; X(0x5a827999); F1; X(0x5a827999);
  F1; X(0x5a827999); F1; X(0x5a827999);
  F1; X(0x5a827999); F1; X(0x5a827999);
  F1; X(0x5a827999); F1; X(0x5a827999);
  F1; X(0x5a827999); F1; X(0x5a827999);
  F2; X(0x6ed9eba1); F2; X(0x6ed9eba1);
  F2; X(0x6ed9eba1); F2; X(0x6ed9eba1);
  F2; X(0x6ed9eba1); F2; X(0x6ed9eba1);
  F2; X(0x6ed9eba1); F2; X(0x6ed9eba1);
  F2; X(0x6ed9eba1); F2; X(0x6ed9eba1);
  F2; X(0x6ed9eba1); F2; X(0x6ed9eba1);
  F2; X(0x6ed9eba1); F2; X(0x6ed9eba1);
  F2; X(0x6ed9eba1); F2; X(0x6ed9eba1);
  F2; X(0x6ed9eba1); F2; X(0x6ed9eba1);
  F2; X(0x6ed9eba1); F2; X(0x6ed9eba1);
  F3; X(0x8f1bbcdc); F3; X(0x8f1bbcdc);
  F3; X(0x8f1bbcdc); F3; X(0x8f1bbcdc);
  F3; X(0x8f1bbcdc); F3; X(0x8f1bbcdc);
  F3; X(0x8f1bbcdc); F3; X(0x8f1bbcdc);
  F3; X(0x8f1bbcdc); F3; X(0x8f1bbcdc);
  F3; X(0x8f1bbcdc); F3; X(0x8f1bbcdc);
  F3; X(0x8f1bbcdc); F3; X(0x8f1bbcdc);
  F3; X(0x8f1bbcdc); F3; X(0x8f1bbcdc);
  F3; X(0x8f1bbcdc); F3; X(0x8f1bbcdc);
  F3; X(0x8f1bbcdc); F3; X(0x8f1bbcdc);
  F2; X(0xca62c1d6); F2; X(0xca62c1d6);
  F2; X(0xca62c1d6); F2; X(0xca62c1d6);
  F2; X(0xca62c1d6); F2; X(0xca62c1d6);
  F2; X(0xca62c1d6); F2; X(0xca62c1d6);
  F2; X(0xca62c1d6); F2; X(0xca62c1d6);
  F2; X(0xca62c1d6); F2; X(0xca62c1d6);
  F2; X(0xca62c1d6); F2; X(0xca62c1d6);
  F2; X(0xca62c1d6); F2; X(0xca62c1d6);
  F2; X(0xca62c1d6); F2; X(0xca62c1d6);
  F2; X(0xca62c1d6); F2; X(0xca62c1d6);

  ctx->h[0] += a;
  ctx->h[1] += b;
  ctx->h[2] += c;
  ctx->h[3] += d;
  ctx->h[4] += e;
}

/* Exported functions. */

void
sha1_init(struct sha1_context *ctx)
{
  memcpy(ctx->h, magic, sizeof magic);
  ctx->len = 0;
  ctx->total = 0;
}

void
sha1_update(struct sha1_context *ctx, char *buf, size_t size)
{
  size_t rem;

  ctx->total += size;
  rem = 64 - ctx->len;

  if (ctx->len != 0 && size >= rem) {
    memcpy(ctx->buf + ctx->len, buf, rem);
    munch(ctx, ctx->buf);
    buf += rem;
    size -= rem;
    ctx->len = 0;
  }
  while (size >= 64) {
    munch(ctx, (unsigned char *)buf);
    buf += 64;
    size -= 64;
  }
  memcpy(ctx->buf + ctx->len, buf, size);
  ctx->len += size;
}

void sha1_final(struct sha1_context *ctx, unsigned char *hash)
{
  if (ctx->len >= 64) { /* This should not happen. */
    munch(ctx, ctx->buf);
    ctx->len = 0;
  }

  ctx->buf[ctx->len++] = 0x80;

  if (ctx->len > 56) {
    memset(ctx->buf + ctx->len, 0, 64 - ctx->len);
    munch(ctx, ctx->buf);
    ctx->len = 0;
  }

  memset(ctx->buf + ctx->len, 0, 64 - ctx->len);
  ctx->total *= 8;
  stbe32(&ctx->buf[56], ctx->total >> 32);
  stbe32(&ctx->buf[60], ctx->total & 0xffffffff);
  munch(ctx, ctx->buf);

  stbe32(&hash[0], ctx->h[0]);
  stbe32(&hash[4], ctx->h[1]);
  stbe32(&hash[8], ctx->h[2]);
  stbe32(&hash[12], ctx->h[3]);
  stbe32(&hash[16], ctx->h[4]);
}
