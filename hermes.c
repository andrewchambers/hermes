#include <janet.h>
#include "hermes.h"

static int pkg_gcmark(void *p, size_t s) {
    (void)s;
    Pkg *pkg = p;
    if (pkg->hash) {
        janet_mark(janet_wrap_string(pkg->hash));
    }
    if (pkg->path) {
        janet_mark(janet_wrap_string(pkg->path));
    }
    if (pkg->builder) {
        janet_mark(janet_wrap_function(pkg->builder));
    }
    if (pkg->frozen_builder) {
        janet_mark(janet_wrap_string(pkg->frozen_builder));
    }
    if (pkg->name) {
        janet_mark(janet_wrap_string(pkg->name));
    }
    return 0;
}

static int pkg_get(void *ptr, Janet key, Janet *out) {
    Pkg *pkg = ptr;
    if (janet_keyeq(key, "hash")) {
        *out = janet_wrap_string(pkg->hash);
        return 1;
    } else if (janet_keyeq(key, "path")) {
        *out = janet_wrap_string(pkg->path);
        return 1;
    } else if (janet_keyeq(key, "frozen-builder")) {
        *out = janet_wrap_string(pkg->frozen_builder);
        return 1;
    } else if (janet_keyeq(key, "name")) {
        *out = janet_wrap_string(pkg->name);
        return 1;
    } else {
        return 0;
    }
}

static void pkg_marshal(void *p, JanetMarshalContext *ctx) {
    Pkg *pkg = p;
    janet_marshal_abstract(ctx, p);
    janet_marshal_janet(ctx, janet_wrap_string(pkg->hash));
    janet_marshal_janet(ctx, janet_wrap_string(pkg->frozen_builder));
    janet_marshal_janet(ctx, janet_wrap_string(pkg->name));
    janet_marshal_janet(ctx, janet_wrap_string(pkg->path));
}

static void* pkg_unmarshal(JanetMarshalContext *ctx) {
    Pkg *pkg = janet_unmarshal_abstract(ctx, sizeof(Pkg));
    Janet hash = janet_unmarshal_janet(ctx);
    Janet frozen_builder = janet_unmarshal_janet(ctx);
    Janet name = janet_unmarshal_janet(ctx);
    Janet path = janet_unmarshal_janet(ctx);
    pkg->builder = NULL;

    if (!janet_checktype(hash, JANET_STRING) ||
            !janet_checktype(frozen_builder, JANET_STRING) ||
            !janet_checktype(name, JANET_STRING) ||
            !janet_checktype(path, JANET_STRING))
        janet_panic("cannot unmarshal corrupt pkg");

    pkg->hash = janet_unwrap_string(hash);
    pkg->frozen_builder = janet_unwrap_string(frozen_builder);
    pkg->name = janet_unwrap_string(name);
    return pkg;
}

static Janet pkg(int argc, Janet *argv) {
    unsigned char hbuf[HASH_SZ];

    janet_fixarity(argc, 5);

    Pkg *pkg = janet_abstract(&pkg_type, sizeof(Pkg));
    pkg->hash = janet_getstring(argv, 0);
    pkg->builder = janet_getfunction(argv, 1);
    pkg->frozen_builder = janet_getstring(argv, 2);
    pkg->name = janet_getstring(argv, 3);
    pkg->path = janet_getstring(argv, 4);

    return janet_wrap_abstract(pkg);
}


const JanetAbstractType pkg_type = {
    "hermes/pkg", NULL, pkg_gcmark, pkg_get, NULL, pkg_marshal, pkg_unmarshal, NULL, NULL, NULL
};


static const JanetReg cfuns[] = {
    {"pkg", pkg, NULL},
    {"pkg-hash", pkg_hash, NULL},
    {"pkg-dependencies", pkg_dependencies, NULL},
    {NULL, NULL, NULL}
};

JANET_MODULE_ENTRY(JanetTable *env) {
    janet_cfuns(env, "_hermes", cfuns);
}
