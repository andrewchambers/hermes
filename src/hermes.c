#include <janet.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include "hermes.h"


static int pkg_gcmark(void *p, size_t s) {
    (void)s;
    Pkg *pkg = p;
    janet_mark(pkg->builder);
    janet_mark(pkg->name);
    janet_mark(pkg->content);
    janet_mark(pkg->hash);
    janet_mark(pkg->path);
    janet_mark(pkg->forced_refs);
    janet_mark(pkg->extra_refs);
    janet_mark(pkg->weak_refs);
    return 0;
}

static int pkg_get(void *ptr, Janet key, Janet *out) {
    Pkg *pkg = ptr;
    if (janet_keyeq(key, "hash")) {
        *out = pkg->hash;
        return 1;
    } else if (janet_keyeq(key, "path")) {
        *out = pkg->path;
        return 1;
    } else if (janet_keyeq(key, "builder")) {
        *out = pkg->builder;
        return 1;
    } else if (janet_keyeq(key, "name")) {
        *out = pkg->name;
        return 1;
    } else if (janet_keyeq(key, "content")) {
        *out = pkg->content;
        return 1;
    } else if (janet_keyeq(key, "force-refs")) {
        *out = pkg->forced_refs;
        return 1;
    } else if (janet_keyeq(key, "weak-refs")) {
        *out = pkg->weak_refs;
        return 1;
    } else if (janet_keyeq(key, "extra-refs")) {
        *out = pkg->extra_refs;
        return 1;
    } else {
        return 0;
    }
}

static void validate_pkg(Pkg *pkg) {
    if (!janet_checktypes(pkg->builder, JANET_TFLAG_NIL|JANET_TFLAG_FUNCTION))
        janet_panicf("builder must be a function or nil, got %v", pkg->builder);

    if (!janet_checktypes(pkg->name, JANET_TFLAG_NIL|JANET_TFLAG_STRING))
        janet_panicf("name must be a string or nil, got %v", pkg->name);

    if janet_checktype(pkg->name, JANET_STRING) {
        JanetString name = janet_unwrap_string(pkg->name);
        size_t name_len = janet_string_length(name);
        if (name_len > 64) {
            janet_panicf("name %v is too long, must be less than 64 chars", pkg->name);
        }

        for (size_t i = 0; i < name_len; i++) {
            if (name[i] == '/') {
                janet_panicf("name %v contains path separator.", pkg->name);
            }
        }
    }

    if (!janet_checktypes(pkg->content, JANET_TFLAG_NIL|JANET_TFLAG_STRING|JANET_TFLAG_STRUCT))
        janet_panicf("content must be a string, nil or a struct, got %v", pkg->content);
    // XXX We could recursively check the struct, but this is somewhat duplicated by the
    // normal checking code.

    if (!janet_checktypes(pkg->path, JANET_TFLAG_NIL|JANET_TFLAG_STRING))
        janet_panicf("path must be a string or nil, got %v", pkg->path);

    if (!janet_checktypes(pkg->hash, JANET_TFLAG_NIL|JANET_TFLAG_STRING))
        janet_panicf("hash must be a string or nil, got %v", pkg->hash);

#define CHECK_PKG_TUPLE(NAME, V) \
    do {  \
      if (janet_checktype(V, JANET_TUPLE)) { \
        const Janet *vs = janet_unwrap_tuple(V); \
        size_t n_vs = janet_tuple_length(vs); \
        for (size_t i = 0; i < n_vs; i++) { \
          if (!janet_checkabstract(vs[i], &pkg_type)) { \
            janet_panicf(NAME "[%d] must be a package, got %v", i, vs[i]); \
          } \
        } \
      } else if (janet_checktype(V, JANET_NIL)) { \
        ; \
      } else { \
        janet_panicf(NAME " must be a tuple or nil, got %v", V); \
      } \
    } while (0);

    CHECK_PKG_TUPLE("force-refs", pkg->forced_refs);
    CHECK_PKG_TUPLE("extra-refs", pkg->extra_refs);
    CHECK_PKG_TUPLE("weak-refs", pkg->weak_refs);

#undef CHECK_PKG_TUPLE

}

static void pkg_marshal(void *p, JanetMarshalContext *ctx) {
    Pkg *pkg = p;
    janet_marshal_abstract(ctx, p);
    janet_marshal_janet(ctx, pkg->builder);
    janet_marshal_janet(ctx, pkg->name);
    janet_marshal_janet(ctx, pkg->hash);
    janet_marshal_janet(ctx, pkg->path);
    if (pkg->frozen) {
        janet_marshal_janet(ctx, janet_wrap_nil());
        janet_marshal_janet(ctx, janet_wrap_nil());
        janet_marshal_janet(ctx, janet_wrap_nil());
        janet_marshal_janet(ctx, janet_wrap_nil());
    } else {
        janet_marshal_janet(ctx, pkg->content);
        janet_marshal_janet(ctx, pkg->forced_refs);
        janet_marshal_janet(ctx, pkg->extra_refs);
        janet_marshal_janet(ctx, pkg->weak_refs);
    }
}

static void* pkg_unmarshal(JanetMarshalContext *ctx) {
    Pkg *pkg = janet_unmarshal_abstract(ctx, sizeof(Pkg));
    pkg->builder = janet_unmarshal_janet(ctx);
    pkg->name = janet_unmarshal_janet(ctx);
    pkg->hash = janet_unmarshal_janet(ctx);
    pkg->path = janet_unmarshal_janet(ctx);
    pkg->content = janet_unmarshal_janet(ctx);
    pkg->forced_refs = janet_unmarshal_janet(ctx);
    pkg->extra_refs = janet_unmarshal_janet(ctx);
    pkg->weak_refs = janet_unmarshal_janet(ctx);
    pkg->frozen = !janet_checktype(pkg->hash, JANET_NIL);
    validate_pkg(pkg);
    return pkg;
}

static Janet pkg(int argc, Janet *argv) {
    janet_fixarity(argc, 6);

    Pkg *pkg = janet_abstract(&pkg_type, sizeof(Pkg));
    pkg->frozen = 0;
    pkg->builder = argv[0];
    pkg->name = argv[1];
    pkg->content = argv[2];
    pkg->forced_refs = argv[3];
    pkg->extra_refs = argv[4];
    pkg->weak_refs = argv[5];
    pkg->hash = janet_wrap_nil();
    pkg->path = janet_wrap_nil();

    validate_pkg(pkg);

    return janet_wrap_abstract(pkg);
}

const JanetAbstractType pkg_type = {
    "hermes/pkg", NULL, pkg_gcmark, pkg_get, NULL, pkg_marshal, pkg_unmarshal, NULL, NULL, NULL, NULL, NULL,
};

static const JanetReg cfuns[] = {
    {"pkg", pkg, NULL},
    {"pkg-freeze", pkg_freeze, NULL},
    {"sha256-dir-hash", sha256_dir_hash, NULL},
    {"sha256-file-hash", sha256_file_hash, NULL},
    {"pkg-dependencies", pkg_dependencies, NULL},
    {"storify", storify, NULL},
    {"primitive-unpack", primitive_unpack, NULL},
    {"hash-scan", hash_scan, NULL},
    {"getgrnam", jgetgrnam, NULL},
    {"getpwnam", jgetpwnam, NULL},
    {"getpwuid", jgetpwuid, NULL},
    {"getgid", jgetgid, NULL},
    {"getegid", jgetegid, NULL},
    {"getuid", jgetuid, NULL},
    {"geteuid", jgeteuid, NULL},
    {"setuid", jsetuid, NULL},
    {"setgid", jsetgid, NULL},
    {"seteuid", jseteuid, NULL},
    {"setegid", jsetegid, NULL},
    {"chown", jchown, NULL},
    {"exit", jexit, NULL},
    {"chroot", jchroot, NULL},
    {"getgroups", jgetgroups, NULL},
    {"cleargroups", jcleargroups, NULL},
    {"unix-listen", unix_listen, NULL},
    {"unix-connect", unix_connect, NULL},
    {NULL, NULL, NULL}
};

JANET_MODULE_ENTRY(JanetTable *env) {
    janet_register_abstract_type(&pkg_type);
    janet_cfuns(env, "_hermes", cfuns);
}
