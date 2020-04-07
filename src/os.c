#define _POSIX_C_SOURCE 200112L
#include <janet.h>
#include <unistd.h>
#include <pwd.h>
#include <grp.h>
#include <errno.h>
#include <alloca.h>
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

Janet jgetgrnam(int argc, Janet *argv) {
    JanetTable *info;
    janet_arity(argc, 1, 2);
    JanetString name = janet_getstring(argv, 0);
    struct group *gr = getgrnam((const char*)name);
    if (!gr)
      janet_panicf("no group named %v found", janet_wrap_string(name));
    if (argc >= 2) {
        info = janet_gettable(argv, 1);
    } else {
        info = janet_table(3);
    }
    janet_table_put(info, janet_ckeywordv("name"), janet_wrap_string(name));
    janet_table_put(info, janet_ckeywordv("gid"), janet_wrap_number(gr->gr_gid));
    JanetArray *memb_array = janet_array(8);
    char **membs = gr->gr_mem;
    while(*membs) {
      janet_array_push(memb_array, janet_cstringv(*(membs++)));
    }
    janet_table_put(info, janet_ckeywordv("members"), janet_wrap_array(memb_array));
    return janet_wrap_table(info);
}

Janet jgetgroups(int argc, Janet *argv) {
    (void)argv;
    janet_fixarity(argc, 0);

    int ngroups = 0;
    gid_t *groups = NULL;

    ngroups = getgroups(ngroups, groups);
    if(ngroups == -1)
      janet_panicf("unable to get group list size - %s", strerror(errno));
    
    if (ngroups > 1000)
      janet_panicf("user has too many groups");

    groups = alloca(ngroups * sizeof(gid_t));
    
    if (getgroups(ngroups, groups) == -1)
        janet_panicf("unable to get group list - %s", strerror(errno));

    JanetArray *v = janet_array(ngroups);
    for (int i = 0; i < ngroups; i++) {
      janet_array_push(v, janet_wrap_number(groups[i]));
    }

    return janet_wrap_array(v);
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

Janet jsetegid(int argc, Janet *argv) {
    janet_fixarity(argc, 1);
    if (setegid(janet_getinteger(argv, 0)) != 0)
        janet_panicf("unable to set effective group id - %s", strerror(errno));
    return janet_wrap_nil();
}
