#define _POSIX_C_SOURCE 200112L
#include <janet.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <limits.h>
#include <dirent.h>
#include <unistd.h>
#include <errno.h>
#include "hermes.h"

typedef struct {
    enum scan_state {
        ST_PREFIX1,
        ST_PREFIX2,
        ST_HASH,
    } state;
    JanetString store_path;
    size_t store_path_len;
    JanetTable *hashes;
    size_t path_sz;
    size_t n_matched;
    char hash[HASH_SZ*2];
} Scanner;

static void init_scanner(Scanner *s, JanetString store_path, JanetTable *hashes) {
    s->state = ST_PREFIX1;
    s->hashes = hashes;
    s->store_path = store_path;
    s->store_path_len = janet_string_length(store_path);
    s->n_matched = 0;
}

static void scan_buf(Scanner *s, char *buf, size_t n) {
    static char prefix2[6] = "/hpkg/";

    for (size_t i = 0; i < n; i++) {
again:
        switch (s->state) {
        case ST_PREFIX1:
            if (!s->store_path_len) {
                /* If the store path is "", then nothing to do. */
                s->n_matched = 0;
                s->state = ST_PREFIX2;
                goto again;
            }
            if (buf[i] == s->store_path[s->n_matched]) {
                s->n_matched++;
            } else {
                s->n_matched = 0;
                break;
            }
            if (s->n_matched == s->store_path_len) {
                s->n_matched = 0;
                s->state = ST_PREFIX2;
            }
            break;
        case ST_PREFIX2: {
            if (buf[i] == (prefix2[s->n_matched])) {
                s->n_matched++;
            } else {
                s->n_matched = 0;
                s->state = ST_PREFIX1;
                goto again;
            }
            if (s->n_matched == sizeof(prefix2)) {
                s->n_matched = 0;
                s->state = ST_HASH;
            }
            break;
        }
        case ST_HASH: {
            char c = buf[i];
            if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
                s->hash[s->n_matched++] = c;
            } else {
                s->n_matched = 0;
                s->state = ST_PREFIX1;
                goto again;
            }
            if (s->n_matched == sizeof(s->hash)) {
                s->n_matched = 0;
                s->state = ST_PREFIX1;
                janet_table_put(s->hashes, janet_stringv((const uint8_t*)s->hash, sizeof(s->hash)), janet_wrap_boolean(1));
            }
            break;
        }
        default:
            abort();
        }
    }
}

static void scan_file(Scanner *s, FILE *f) {
    char buf[8192];

    while (1) {
        size_t n = fread(buf, 1, sizeof(buf), f);
        if (n == 0)
            break;
        scan_buf(s, buf, n);
    }

    if (ferror(f))
        janet_panic("io error while scanning for package references");
}

static void finalize_file (void *p) {
    FILE **f = p;
    if (*f) fclose(*f);
}

static void finalize_dir (void *p) {
    DIR **d = p;
    if (*d) closedir(*d);
}

void hash_scan_path2(JanetString store_path, const char *path, JanetTable *hashes, int rec) {
    struct stat statbuf;

    if (rec > 1000)
        janet_panicf("directory recursion limit reached");

    if(lstat((char *)path, &statbuf) != 0)
        janet_panicf("unable to stat %s", path);

    if (S_ISLNK(statbuf.st_mode)) {
        char *lnkbuf = janet_smalloc(statbuf.st_size);
        ssize_t nchars = readlink((char *)path, lnkbuf, statbuf.st_size);
        if (nchars < 0) {
            janet_panicf("unable to read link at %s", path);
        }
        Scanner s;
        init_scanner(&s, store_path, hashes);
        scan_buf(&s, lnkbuf, nchars);
        janet_sfree(lnkbuf);
    } else if (S_ISREG(statbuf.st_mode)) {
        FILE **f = janet_smalloc(sizeof(FILE*));
        *f = NULL;
        janet_sfinalizer(f, finalize_file);
        *f = fopen((char *)path, "rb");
        if (!*f)
            janet_panicf("unable to open %s", path);

        Scanner s;
        init_scanner(&s, store_path, hashes);
        scan_file(&s, *f);
        janet_sfree(f);
    } else if (S_ISDIR(statbuf.st_mode)) {
        struct dirent *de;
        DIR **dr = janet_smalloc(sizeof(DIR*));
        *dr = NULL;
        janet_sfinalizer(dr, finalize_dir);
        *dr = opendir(path);
        if (*dr == NULL)
            janet_panicf("unable to open directory %s", path);

        while (1) {
            errno = 0;
            de = readdir(*dr);
            if (de == NULL)  {
                if (errno != 0)
                    janet_panicf("error reading directory");
                break;
            }
            if ((strcmp(de->d_name, ".") == 0) || (strcmp(de->d_name, "..") == 0))
                continue;

            int npath = snprintf(NULL, 0, "%s/%s", path, de->d_name) + 1;
            char *child_path = janet_smalloc(npath+1);
            snprintf(child_path, npath+1, "%s/%s", path, de->d_name);
            hash_scan_path2(store_path, child_path, hashes, rec+1);
            janet_sfree(child_path);
        }
        janet_sfree(dr);
    } else {
        janet_panicf("unsupported scan file type at %s", path);
    };
}

Janet hash_scan(int argc, Janet *argv) {
    janet_fixarity(argc, 3);
    JanetString store_path = janet_getstring(argv, 0);
    Pkg *pkg = janet_getabstract(argv, 1, &pkg_type);
    if (!janet_checktype(pkg->path, JANET_STRING))
        janet_panic("package does not have a valid path");
    JanetString path = janet_unwrap_string(pkg->path);
    JanetTable *hashes = janet_gettable(argv, 2);
    if (janet_string_length(store_path) == 0)
        janet_panic("unable to scan for empty store path");
    hash_scan_path2(store_path, (const char *)path, hashes, 0);
    janet_table_put(hashes, pkg->path, janet_wrap_nil());
    return janet_wrap_table(hashes);
}
