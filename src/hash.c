#define _POSIX_C_SOURCE 200809L
#include <sys/types.h>
#include <sys/stat.h>
#include <string.h>
#include <unistd.h>
#include <janet.h>
#include <errno.h>
#include "hermes.h"
#include "sha256.h"
#include "fts.h"

typedef struct {
    enum {
        kind_sha256,
    } kind;
    union {
        Sha256ctx *sha256;
    } ctx;
} Hasher;

static void hasher_add(Hasher *h, char *b, size_t n) {
    switch (h->kind) {
    case kind_sha256:
        sha256_update(h->ctx.sha256, (uint8_t*)b, n);
        break;
    default:
        abort();
    }
}

static void hasher_add_byte(Hasher *h, char b) {
    hasher_add(h, &b, 1);
}

static void hasher_add_int32(Hasher *h, int x) {
    char buf[4];
    buf[0] = (x >> 24) & 0xff;
    buf[1] = (x >> 16) & 0xff;
    buf[2] = (x >>  8) & 0xff;
    buf[3] = (x      ) & 0xff;
    hasher_add(h, buf, sizeof(buf));
}

static void hasher_add_int64(Hasher *h, int64_t x) {
    char buf[8];
    buf[0] = (x >> 56) & 0xff;
    buf[1] = (x >> 48) & 0xff;
    buf[2] = (x >> 40) & 0xff;
    buf[3] = (x >> 32) & 0xff;
    buf[4] = (x >> 24) & 0xff;
    buf[5] = (x >> 16) & 0xff;
    buf[6] = (x >>  8) & 0xff;
    buf[7] = (x      ) & 0xff;
    hasher_add(h, buf, sizeof(buf));
}

static int hasher_add_file(Hasher *h, FILE *f) {
    char buf[4096];
    while (1) {
        int n = fread(buf, 1, sizeof(buf), f);
        if (n > 0) {
            hasher_add(h, buf, n);
        }
        if (n == 0)
            break;
    }
    return !ferror(f);
}

static void hasher_add_file_contents_at_path(Hasher *h, const char *path) {

    FILE *f = fopen(path, "rb");
    if (!f)
        janet_panicf("unable to open %s: %s", path, strerror(errno));
    int ok = hasher_add_file(h, f);
    fclose(f);
    if (!ok)
        janet_panicf("io error while hashing %s", path);
}

static int fcompare(const FTSENT** one, const FTSENT** two)
{
    return (strcmp((*one)->fts_name, (*two)->fts_name));
}

static void finalize_fts(void *p) {
    FTS **pfs = p;
    if (*pfs) fts_close(*pfs);
};

static void
dir_hash(Hasher *h, const char *fpath)
{
    FTS** pfs = NULL;
    FTSENT* fent = NULL;
    errno = 0;

    pfs = janet_smalloc(sizeof(FTS*));
    *pfs = NULL;
    janet_sfinalizer(pfs, finalize_fts);
    // XXX we should probably add gc pressure, but how much?

    const char *paths[] = {fpath, NULL};

    *pfs = fts_open((char * const *)paths, FTS_NOCHDIR|FTS_PHYSICAL, &fcompare);
    if (!*pfs)
        janet_panicf("unable to open directory");

    while(1) {
        fent = fts_read(*pfs);
        if (!fent) {
            if (errno != 0)
                janet_panicf("%s", strerror(errno));
            break;
        }
        switch (fent->fts_info) {
        case FTS_DP:
            if (fent->fts_level) {
                hasher_add_byte(h, 0);
                hasher_add_int32(h, fent->fts_level);
                hasher_add(h, fent->fts_name, fent->fts_namelen);
                hasher_add_int32(h, fent->fts_statp->st_mode & 0111);
            }
            break;
        case FTS_D:
            /* hashed above */
            break;
        case FTS_F: {
            hasher_add_byte(h, 1);
            hasher_add(h, fent->fts_name, fent->fts_namelen);
            hasher_add_int32(h, fent->fts_level);
            hasher_add_int32(h, fent->fts_statp->st_mode & 0111);
            hasher_add_int64(h, fent->fts_statp->st_size);
            hasher_add_file_contents_at_path(h, fent->fts_accpath);
            break;
        }
        case FTS_SL: {
            hasher_add_byte(h, 2);
            char *lnkbuf = janet_smalloc(fent->fts_statp->st_size);
            ssize_t nchars = readlink((char *)fent->fts_accpath, lnkbuf, fent->fts_statp->st_size);
            if (nchars < 0)
                janet_panicf("unable to read link at %s: %s", fent->fts_accpath, strerror(errno));
            hasher_add(h, lnkbuf, nchars);
            janet_sfree(lnkbuf);
            break;
        }
        default:
            janet_panicf("unsupported file at %s%s", fent->fts_path, fent->fts_name);
        }
    }

    janet_sfree(pfs);
}

Janet sha256_dir_hash(int argc, Janet *argv) {
    janet_fixarity(argc, 1);
    const char *p = (const char*)janet_getstring(argv, 0);
    Sha256ctx ctx;
    sha256_init(&ctx);
    Hasher h;
    h.kind = kind_sha256;
    h.ctx.sha256 = &ctx;
    dir_hash(&h, p);
    uint8_t buf[32];
    uint8_t hexbuf[sizeof(buf)*2];
    sha256_finish(&ctx, buf);
    base16_encode((char*)hexbuf, (char*)buf, sizeof(buf));
    return janet_stringv(hexbuf, sizeof(hexbuf));
}

Janet sha256_file_hash(int argc, Janet *argv) {
    janet_fixarity(argc, 1);
    Sha256ctx ctx;
    sha256_init(&ctx);
    Hasher h;
    h.kind = kind_sha256;
    h.ctx.sha256 = &ctx;
    if (janet_checkabstract(argv[0], &janet_file_type)) {
        FILE *f = janet_unwrapfile(argv[0], NULL);
        if (!hasher_add_file(&h, f))
            janet_panicf("error hashing file");
    } else if (janet_checktype(argv[0], JANET_STRING)) {
        hasher_add_file_contents_at_path(&h, (const char *)janet_unwrap_string(argv[0]));
    } else {
        janet_panicf("file hash expects a file object or path, got %v", argv[0]);
    }
    uint8_t buf[32];
    uint8_t hexbuf[sizeof(buf)*2];
    sha256_finish(&ctx, buf);
    base16_encode((char*)hexbuf, (char*)buf, sizeof(buf));
    return janet_stringv(hexbuf, sizeof(hexbuf));
}
