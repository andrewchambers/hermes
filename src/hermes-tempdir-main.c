#define  _POSIX_C_SOURCE 200809L
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fts.h>
#include <signal.h>

void cleanup(const char *dir)
{
    FTS *ftsp = NULL;
    FTSENT *curr;

    char *files[] = { (char *) dir, NULL };
    ftsp = fts_open(files, FTS_NOCHDIR | FTS_PHYSICAL | FTS_XDEV, NULL);
    if (!ftsp) {
        goto finish;
    }

#define TRY(X) if(X != 0) { goto finish; }

    while ((curr = fts_read(ftsp))) {
        switch (curr->fts_info) {
        case FTS_NS:
        case FTS_DNR:
        case FTS_ERR:
            break;
        case FTS_D:
            TRY(chmod(curr->fts_accpath, 0700));
            break;
        case FTS_DP:
            TRY(rmdir(curr->fts_accpath));
            break;
        case FTS_F:
        case FTS_SL:
        case FTS_SLNONE:
        case FTS_DEFAULT:
            TRY(chmod(curr->fts_accpath, 0700));
            TRY(unlink(curr->fts_accpath));
            break;
        }
    }

#undef TRY

finish:
    if (ftsp)
        fts_close(ftsp);
}


int main()
{
    signal(SIGINT,SIG_IGN);
    signal(SIGHUP,SIG_IGN);
    signal(SIGQUIT,SIG_IGN);
    signal(SIGPIPE,SIG_IGN);
    signal(SIGTERM,SIG_IGN);

    char template[] = "/tmp/hermes-tmpdir.XXXXXX";
    char *dir_name = mkdtemp(template);
    if (!dir_name) {
        perror("mkdtemp");
        exit(1);
    }
    if (printf("%s\n", dir_name) < 0)
        exit(1);
    getchar();
    cleanup(dir_name);
    return 0;
}