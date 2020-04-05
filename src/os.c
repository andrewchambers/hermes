#define _POSIX_C_SOURCE 200112L
#include <janet.h>
#include <unistd.h>
#include <pwd.h>
#include <errno.h>
#include <sys/types.h>
#include "hermes.h"

static void passwd_into_table(struct passwd *pw, JanetTable *t) {
    janet_table_put(t, janet_ckeywordv("name"), janet_cstringv(pw->pw_name));
    janet_table_put(t, janet_ckeywordv("uid"), janet_wrap_number(pw->pw_uid));
    janet_table_put(t, janet_ckeywordv("gid"), janet_wrap_number(pw->pw_gid));
    janet_table_put(t, janet_ckeywordv("gecos"), janet_cstringv(pw->pw_gecos));
    janet_table_put(t, janet_ckeywordv("dir"), janet_cstringv(pw->pw_dir));
    janet_table_put(t, janet_ckeywordv("shell"), janet_cstringv(pw->pw_shell));
}

Janet jgetpwnam(int argc, Janet *argv) {
    JanetTable *info;
    janet_arity(argc, 1, 2);
    struct passwd *pw = getpwnam((const char*)janet_getstring(argv, 0));
    if (argc >= 2) {
        info = janet_gettable(argv, 1);
    } else {
        info = janet_table(8);
    }
    passwd_into_table(pw, info);
    return janet_wrap_table(info);
}

Janet jgetpwuid(int argc, Janet *argv) {
    JanetTable *info;
    janet_arity(argc, 1, 2);
    struct passwd *pw = getpwuid(janet_getinteger(argv, 0));
    if (argc >= 2) {
        info = janet_gettable(argv, 1);
    } else {
        info = janet_table(8);
    }
    passwd_into_table(pw, info);
    return janet_wrap_table(info);
}

Janet jgetuid(int argc, Janet *argv) {
    (void)argv;
    janet_fixarity(argc, 0);
    return janet_wrap_integer(getuid());
}

Janet jgeteuid(int argc, Janet *argv) {
    (void)argv;
    janet_fixarity(argc, 0);
    return janet_wrap_integer(geteuid());
}

Janet jgetgid(int argc, Janet *argv) {
    (void)argv;
    janet_fixarity(argc, 0);
    return janet_wrap_integer(getgid());
}

Janet jgetegid(int argc, Janet *argv) {
    (void)argv;
    janet_fixarity(argc, 0);
    return janet_wrap_integer(getegid());
}

Janet jsetuid(int argc, Janet *argv) {
    janet_fixarity(argc, 1);
    if (setuid(janet_getinteger(argv, 0)) != 0)
        janet_panicf("unable to set user id - %s", strerror(errno));
    return janet_wrap_nil();
}

Janet jseteuid(int argc, Janet *argv) {
    janet_fixarity(argc, 1);
    if (seteuid(janet_getinteger(argv, 0)) != 0)
        janet_panicf("unable to set effective user id - %s", strerror(errno));
    return janet_wrap_nil();
}
