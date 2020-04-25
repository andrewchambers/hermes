#define  _POSIX_C_SOURCE 200809L
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/types.h>
#include <errno.h>
#include <string.h>
#include <sys/stat.h>
#include <signal.h>
#include "fts.h"


static void die(const char *msg) {
    perror(msg);
    exit(1);
}

static void cleanup(const char *dir)
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
        case FTS_SL:
        case FTS_SLNONE:
            TRY(unlink(curr->fts_accpath));
            break;
        case FTS_F:
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



static volatile sig_atomic_t interrupted = 0;

static void sighandler(int signo, siginfo_t *siginfo, void *context) {
    if (signo != SIGALRM) {
        interrupted = 1;
    }
}

int main()
{
    umask(0077);

    struct sigaction act;
    memset (&act, 0, sizeof(act));
 
    act.sa_sigaction = &sighandler;
    act.sa_flags = SA_SIGINFO;
 
    if ((sigaction(SIGINT, &act, NULL) < 0)
        || (sigaction(SIGHUP, &act, NULL) < 0)
        || (sigaction(SIGQUIT, &act, NULL) < 0)
        || (sigaction(SIGPIPE, &act, NULL) < 0)
        || (sigaction(SIGTERM, &act, NULL) < 0)
        || (sigaction(SIGALRM, &act, NULL) < 0)) {
        die("sigaction");
    }

    char template[] = "/tmp/hermes-tmpdir.XXXXXX";
    char *dir_name = mkdtemp(template);
    if (!dir_name) {
        die("mkdtemp");
    }
    if (printf("%s\n", dir_name) < 0)
        die("printf");
    if (fflush(stdout) != 0)
        die("fflush");
    char buf[1];
    while (!interrupted) {
        // alarm ensures cleanup happens
        // even when term interrupts happened in window
        // between mkdir and read.
        alarm(5);
        errno = 0;
        int rc = read(STDIN_FILENO, buf, 1);
        if (rc == 1)
            break;
        if (rc != 1 && errno != EINTR)
            break;
    }
    cleanup(dir_name);
    return 0;
}