#define _POSIX_C_SOURCE 200809L
#include <sys/types.h>
#include <sys/stat.h>
#include <utime.h>
#include <string.h>
#include <unistd.h>
#include <fts.h>
#include <janet.h>
#include <errno.h>
#include "hermes.h"


static int fcompare(const FTSENT** one, const FTSENT** two)
{
    return (strcmp((*one)->fts_name, (*two)->fts_name));
}

static void finalize_fts(void *p) {
    FTS **pfs = p;
    if (*pfs) fts_close(*pfs);
};

Janet storify(int argc, Janet *argv) {
    janet_fixarity(argc, 3);
    const char *dirpath = (const char*)janet_getstring(argv, 0);
    uid_t uid = janet_getinteger(argv, 1);
    gid_t gid = janet_getinteger(argv, 2);

    FTS** pfs = NULL;
    FTSENT* fent = NULL;
    errno = 0;

    pfs = janet_smalloc(sizeof(FTS*));
    *pfs = NULL;
    janet_sfinalizer(pfs, finalize_fts);

    const char *paths[] = {dirpath, NULL};

    *pfs = fts_open((char * const *)paths, FTS_NOCHDIR|FTS_PHYSICAL, &fcompare);
    if (!*pfs)
        janet_panicf("unable to open directory");


    struct utimbuf t;

    t.actime = 0;
    t.modtime = 0;

    while(1) {
        fent = fts_read(*pfs);
        if (!fent) {
            if (errno != 0)
                janet_panicf("%s", strerror(errno));
            break;
        }
        switch (fent->fts_info) {
        case FTS_F:
        case FTS_SL:
        case FTS_SLNONE:
        case FTS_DEFAULT:
        case FTS_DP:
            if (lchown(fent->fts_accpath, uid, gid) != 0)
                janet_panicf("unable to storify %s - lchown - %s", fent->fts_accpath, strerror(errno));

            if (fent->fts_info != FTS_SL) {
                if (utime(fent->fts_accpath, &t) != 0)
                    janet_panicf("unable to storify %s - utime - %s", fent->fts_accpath, strerror(errno));
                if (chmod(fent->fts_accpath, (fent->fts_statp->st_mode&0111)|0444) != 0)
                    janet_panicf("unable to storify %s - chmod - %s", fent->fts_accpath, strerror(errno));
            }
            break;
        case FTS_D:
            /* handled above above */
            break;
        default:
            janet_panicf("unsupported file at %s%s", fent->fts_path, fent->fts_name);
        }
    }

    janet_sfree(pfs);

    return janet_wrap_nil();
}

