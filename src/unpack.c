#include <sys/types.h>
#include <sys/stat.h>
#include <archive.h>
#include <archive_entry.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <janet.h>


static int
copy_data(struct archive *ar, struct archive *aw)
{
    int r;
    const void *buff;
    size_t size;
#if ARCHIVE_VERSION_NUMBER >= 3000000
    int64_t offset;
#else
    off_t offset;
#endif

    for (;;) {
        r = archive_read_data_block(ar, &buff, &size, &offset);
        if (r == ARCHIVE_EOF)
            return (ARCHIVE_OK);
        if (r != ARCHIVE_OK)
            return r;
        r = archive_write_data_block(aw, buff, size, offset);
        if (r != ARCHIVE_OK) {
            janet_panicf("copying data failed - %s", archive_error_string(aw));
            return r;
        }
    }
}

static void finalize_read(void *p) {
    struct archive **pa = p;
    archive_read_close(*pa);
    archive_read_free(*pa);
};

static void finalize_write(void *p) {
    struct archive **pa = p;
    archive_write_close(*pa);
    archive_write_free(*pa);
};

Janet primitive_unpack(int argc, Janet *argv)
{
    struct archive **pa;
    struct archive *a;
    struct archive **pext;
    struct archive *ext;
    struct archive_entry *entry;
    int flags;
    int r;

    flags = ARCHIVE_EXTRACT_TIME;
    flags |= ARCHIVE_EXTRACT_PERM;
    flags |= ARCHIVE_EXTRACT_ACL;
    flags |= ARCHIVE_EXTRACT_FFLAGS;

    janet_fixarity(argc, 1);
    const char *filename = (const char*)janet_getstring(argv, 0);

    pa = janet_smalloc(sizeof(struct archive *));
    pext = janet_smalloc(sizeof(struct archive *));
    *pa = NULL;
    *pext = NULL;

    *pa = archive_read_new();
    janet_sfinalizer(pa, finalize_read);
    a = *pa;
    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);

    *pext = archive_write_disk_new();
    janet_sfinalizer(pext, finalize_write);
    ext = *pext;
    archive_write_disk_set_options(ext, flags);
    archive_write_disk_set_standard_lookup(ext);
#define FAIL janet_panic("unpack failed")
    if ((r = archive_read_open_filename(a, filename, 10240)))
        FAIL;
    for (;;) {
        r = archive_read_next_header(a, &entry);
        if (r == ARCHIVE_EOF)
            break;
        if (r < ARCHIVE_OK)
            fprintf(stderr, "%s\n", archive_error_string(a));
        if (r < ARCHIVE_WARN)
            FAIL;
        r = archive_write_header(ext, entry);
        if (r < ARCHIVE_OK)
            fprintf(stderr, "%s\n", archive_error_string(ext));
        else if (r < ARCHIVE_WARN) {
            FAIL;
        } else if (archive_entry_size(entry) > 0) {
            r = copy_data(a, ext);
            if (r < ARCHIVE_OK)
                fprintf(stderr, "%s\n", archive_error_string(ext));
            if (r < ARCHIVE_WARN)
                FAIL;
        }
        r = archive_write_finish_entry(ext);
        if (r < ARCHIVE_OK)
            fprintf(stderr, "%s\n", archive_error_string(ext));
        if (r < ARCHIVE_WARN)
            FAIL;
    }
#undef FAIL
    janet_sfree(pa);
    janet_sfree(pext);
    return janet_wrap_nil();
}