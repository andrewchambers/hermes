#include <janet.h>
#include "hermes.h"

static int pkg_gcmark(void *p, size_t s) {
    (void)s;
    Pkg *pkg = p;
    janet_mark(pkg->builder);
    janet_mark(pkg->name);
    janet_mark(pkg->out_hash);
    janet_mark(pkg->hash);
    janet_mark(pkg->path);
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
    } else if (janet_keyeq(key, "out-hash")) {
        *out = pkg->out_hash;
        return 1;
    } else {
        return 0;
    }
}

static void validate_pkg_types(Pkg *pkg) {
    if (!janet_checktypes(pkg->builder, JANET_TFLAG_NIL|JANET_TFLAG_FUNCTION))
        janet_panicf("builder must be a function or nil, got %v", pkg->builder);

    if (!janet_checktypes(pkg->name, JANET_TFLAG_NIL|JANET_TFLAG_STRING))
        janet_panicf("name must be a string or nil, got %v", pkg->name);

    if (!janet_checktypes(pkg->out_hash, JANET_TFLAG_NIL|JANET_TFLAG_STRING))
        janet_panicf("out-hash must be a string or nil, got %v", pkg->out_hash);

    if (!janet_checktypes(pkg->path, JANET_TFLAG_NIL|JANET_TFLAG_STRING))
        janet_panicf("path must be a string or nil, got %v", pkg->path);

    if (!janet_checktypes(pkg->hash, JANET_TFLAG_NIL|JANET_TFLAG_STRING))
        janet_panicf("hash must be a string or nil, got %v", pkg->hash);
}

static void pkg_marshal(void *p, JanetMarshalContext *ctx) {
    Pkg *pkg = p;
    janet_marshal_abstract(ctx, p);
    janet_marshal_janet(ctx, pkg->builder);
    janet_marshal_janet(ctx, pkg->name);
    janet_marshal_janet(ctx, pkg->out_hash);
    janet_marshal_janet(ctx, pkg->hash);
    janet_marshal_janet(ctx, pkg->path);
}

static void* pkg_unmarshal(JanetMarshalContext *ctx) {
    Pkg *pkg = janet_unmarshal_abstract(ctx, sizeof(Pkg));
    pkg->builder = janet_unmarshal_janet(ctx);
    pkg->name = janet_unmarshal_janet(ctx);
    pkg->out_hash = janet_unmarshal_janet(ctx);
    pkg->hash = janet_unmarshal_janet(ctx);
    pkg->path = janet_unmarshal_janet(ctx);
    validate_pkg_types(pkg);
    return pkg;
}

static Janet pkg(int argc, Janet *argv) {
    unsigned char hbuf[HASH_SZ];

    janet_fixarity(argc, 3);

    Pkg *pkg = janet_abstract(&pkg_type, sizeof(Pkg));
    pkg->builder = argv[0];
    pkg->name = argv[1];
    pkg->out_hash = argv[2];
    pkg->hash = janet_wrap_nil();
    pkg->path = janet_wrap_nil();

    validate_pkg_types(pkg);

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
