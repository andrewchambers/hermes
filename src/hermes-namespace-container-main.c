#define _GNU_SOURCE
#include <sched.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/prctl.h>

static void die(const char *msg) {
    perror(msg);
    exit(1);
}

static void xclose(int fd) {
    int rc;

again:
    rc = close(fd);

    if (rc != 0 && errno == EINTR)
        goto again;

    if (rc != 0)
        die("close");
}

static char xread1(int fd) {
    int rc;
    char c;

again:
    rc = read(fd, &c, 1);

    if (rc < 0 && errno == EINTR)
        goto again;

    if (rc < 0)
        die("read");

    if (rc != 1) {
        fprintf(stderr, "unexpected eof\n");
        exit(1);
    }

    return c;
}

static void xwrite1(int fd, char c) {
    int rc;

again:
    rc = write(fd, &c, 1);

    if (rc < 0 && errno == EINTR)
        goto again;

    if (rc != 1)
        die("write");
}


static void
usage(char *pname)
{
    fprintf(stderr, "Usage: %s [options] program [arg...]\n", pname);
    fprintf(stderr, "Options can be:\n");
    fprintf(stderr, "    -C   unshare cgroup namespace\n");
    fprintf(stderr, "    -i   unshare IPC namespace\n");
    fprintf(stderr, "    -m   unshare mount namespace\n");
    fprintf(stderr, "    -n   unshare network namespace\n");
    fprintf(stderr, "    -p   unshare PID namespace\n");
    fprintf(stderr, "    -u   unshare UTS namespace\n");
    exit(1);
}

static volatile sig_atomic_t SIGINT_ctr = 0;
static volatile sig_atomic_t SIGHUP_ctr = 0;
static volatile sig_atomic_t SIGQUIT_ctr = 0;
static volatile sig_atomic_t SIGTERM_ctr = 0;
static volatile sig_atomic_t SIGUSR1_ctr = 0;
static volatile sig_atomic_t SIGUSR2_ctr = 0;

static void sighandler(int signo, siginfo_t *siginfo, void *context) {
#define SIG_INC_CTR_CASE(X) case X: if (X##_ctr != SIG_ATOMIC_MAX) ++(X##_ctr); break
    switch (signo) {
        SIG_INC_CTR_CASE(SIGINT);
        SIG_INC_CTR_CASE(SIGHUP);
        SIG_INC_CTR_CASE(SIGTERM);
        SIG_INC_CTR_CASE(SIGQUIT);
        SIG_INC_CTR_CASE(SIGUSR1);
        SIG_INC_CTR_CASE(SIGUSR2);
    }
#undef SIG_INC_CTR_CASE
}

static void fork_child_and_forward_signals(void (*child_continuation)(void)) {

    pid_t pid;
    int sync[2];

    if (pipe(sync) < 0)
        die("pipe");

    pid = fork();
    if (pid < 0)
        die("fork");
    else if (pid > 0) {
        xclose(sync[1]);

        // Setup our forwarding signal handler...
        struct sigaction act;
        memset (&act, 0, sizeof(act));

        sigset_t masked_signals;
        sigemptyset(&masked_signals);
        sigaddset(&masked_signals, SIGINT);
        sigaddset(&masked_signals, SIGHUP);
        sigaddset(&masked_signals, SIGQUIT);
        sigaddset(&masked_signals, SIGTERM);
        sigaddset(&masked_signals, SIGALRM);
        sigaddset(&masked_signals, SIGUSR1);
        sigaddset(&masked_signals, SIGUSR2);

        act.sa_sigaction = &sighandler;
        act.sa_flags = SA_SIGINFO;
        act.sa_mask = masked_signals;

        if ((sigaction(SIGINT, &act, NULL) < 0)
                || (sigaction(SIGHUP, &act, NULL) < 0)
                || (sigaction(SIGQUIT, &act, NULL) < 0)
                || (sigaction(SIGTERM, &act, NULL) < 0)
                || (sigaction(SIGALRM, &act, NULL) < 0)
                || (sigaction(SIGUSR1, &act, NULL) < 0)
                || (sigaction(SIGUSR2, &act, NULL) < 0)) {
            die("sigaction");
        }

        xread1(sync[0]);
        xclose(sync[0]);

        while (1) {

            sigset_t restore_mask;
            if(sigprocmask(SIG_BLOCK, &masked_signals, &restore_mask) != 0)
                die("sigprocmask");

#define FWDSIG(X) while (X##_ctr) { kill(pid, X); X##_ctr--; }
            FWDSIG(SIGINT);
            FWDSIG(SIGHUP);
            FWDSIG(SIGQUIT);
            FWDSIG(SIGTERM);
            FWDSIG(SIGUSR1);
            FWDSIG(SIGUSR2);
#undef FWDSIG

            if(sigprocmask(SIG_SETMASK, &restore_mask, NULL) != 0)
                die("sigprocmask");

            // XXX This SIGALRM is used for the case a signal
            // arrived in the window between forwarding signals
            // and waiting. In that cause we could have an unforwarded
            // signal like SIGTERM and everything deadlocks...
            alarm(1);

            while (1) {
                int rc;
                int status;
                rc = waitpid(-1, &status, 0);
                if (rc < 0) {
                    if (errno == EINTR)
                        break;
                    die("waitpid");
                }
                if (rc == pid) {
                    if (WIFEXITED(status)) {
                        exit(WEXITSTATUS(status));
                    } else if (WIFSIGNALED(status)) {
                        // XXX Function of termsig signal?
                        exit(127);
                    }
                }
            }
        }
    } else {
        xclose(sync[0]);
        /* Kill child if we are killed somehow. */
        if (prctl(PR_SET_PDEATHSIG, SIGKILL) < 0)
            die("prctl");
        xwrite1(sync[1], 'x');
        xclose(sync[1]);
        child_continuation();
    }
    exit(1);
}

static char *child_argv0 = NULL;
static char **child_argv = NULL;

static void exec_child(void) {
    execvp(child_argv0, child_argv);
    die("execvp");
}

static void pid1(void) {
    fork_child_and_forward_signals(exec_child);
    exit(1);
}

int
main(int argc, char *argv[])
{
    int flags, opt;

    flags = 0;

    while ((opt = getopt(argc, argv, "Cimnptu")) != -1) {
        switch (opt) {
        case 'C':
            flags |= CLONE_NEWCGROUP;
            break;
        case 'i':
            flags |= CLONE_NEWIPC;
            break;
        case 'm':
            flags |= CLONE_NEWNS;
            break;
        case 'n':
            flags |= CLONE_NEWNET;
            break;
        case 'p':
            flags |= CLONE_NEWPID;
            break;
        case 'u':
            flags |= CLONE_NEWUTS;
            break;
        default:
            usage(argv[0]);
        }
    }
    if (optind >= argc)
        usage(argv[0]);


    child_argv0 = argv[optind];
    child_argv = &argv[optind];

    if (unshare(flags) == -1)
        die("unshare");

    if (flags & CLONE_NEWNS)
      // We don't want mounts to propagate out of our container.
      if (mount("none", "/", NULL, MS_REC|MS_PRIVATE, NULL) == -1)
        die("mount propagatation");

    if ((flags & CLONE_NEWPID))
        fork_child_and_forward_signals(pid1);
    else
        exec_child();
}