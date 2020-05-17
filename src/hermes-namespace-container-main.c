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
    fprintf(stderr, "    -n   unshare network namespace\n");
    exit(1);
}

static volatile sig_atomic_t outside_signal = 0;

static void sighandler(int signo, siginfo_t *siginfo, void *context) {
    if (signo != SIGALRM) {
        outside_signal = 1;
    }
}

static void fork_child(void (*child_continuation)(void)) {

    /* We want to die if the pkgstore process dies
       SIGTERM means we can send SIGKILL to the child.
     */
    if (prctl(PR_SET_PDEATHSIG, SIGTERM) < 0)
        die("prctl");

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
        sigaddset(&masked_signals, SIGCONT);
        sigaddset(&masked_signals, SIGTSTP);
        sigaddset(&masked_signals, SIGTTIN);
        sigaddset(&masked_signals, SIGTTOU);

        act.sa_sigaction = &sighandler;
        act.sa_flags = SA_SIGINFO;
        act.sa_mask = masked_signals;

        if ((sigaction(SIGINT, &act, NULL) < 0)
                || (sigaction(SIGHUP, &act, NULL) < 0)
                || (sigaction(SIGQUIT, &act, NULL) < 0)
                || (sigaction(SIGTERM, &act, NULL) < 0)
                || (sigaction(SIGALRM, &act, NULL) < 0)
                || (sigaction(SIGUSR1, &act, NULL) < 0)
                || (sigaction(SIGUSR2, &act, NULL) < 0)
                || (sigaction(SIGCONT, &act, NULL) < 0)
                || (sigaction(SIGTSTP, &act, NULL) < 0)
                || (sigaction(SIGTTIN, &act, NULL) < 0)
                || (sigaction(SIGTTOU, &act, NULL) < 0)) {
            die("sigaction");
        }

        xread1(sync[0]);
        xclose(sync[0]);

        while (1) {

            if (outside_signal) {
                // If a signal arrived, we should kill the child and wait for it.
                kill(pid, SIGKILL);
            }

            // XXX This SIGALRM is used for the case a signal
            // arrived in the window between last loop iteration and waiting.
            // In that cause we could have an undetected
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
                        int exit_code = WEXITSTATUS(status);
                        // If we got a signal, we should treat
                        // this like a build failure. We can't allow
                        // interactive users to influence builds.
                        if (exit_code == 0 && outside_signal)
                            exit_code = 127;
                        exit(exit_code);
                    } else if (WIFSIGNALED(status)) {
                        // XXX Function of termsig signal?
                        exit(127);
                    }
                }
            }
        }
    } else {
        xclose(sync[0]);
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
    fork_child(exec_child);
    exit(1);
}

int
main(int argc, char *argv[])
{
    int unshare_flags, opt;

    unshare_flags = CLONE_NEWIPC|CLONE_NEWUTS|CLONE_NEWNS|CLONE_NEWPID;

    while ((opt = getopt(argc, argv, "n")) != -1) {
        switch (opt) {
        case 'n':
            unshare_flags |= CLONE_NEWNET;
            break;
        default:
            usage(argv[0]);
        }
    }
    if (optind >= argc)
        usage(argv[0]);


    child_argv0 = argv[optind];
    child_argv = &argv[optind];

    if (unshare(unshare_flags) == -1)
        die("unshare");

    if (mount("none", "/", NULL, MS_REC|MS_PRIVATE, NULL) == -1)
        die("mount propagatation");

    fork_child(pid1);
}