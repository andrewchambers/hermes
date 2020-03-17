#include "sha1.h"
#include <alloca.h>
#include <assert.h>
#include <janet.h>
#include <unistd.h>

#define HASH_SZ 20

typedef struct {
    struct sha1_context hash_ctx;
    /* Table of Pointer -> name */
    JanetTable *value_names;
    /* Ordered array of names we have encountered */
    JanetArray *Names;
} HashContext;

typedef struct {
    JanetFunction *builder;
    JanetString hash;
    JanetString path;
    JanetString name;
    JanetString out_hash;
} Pkg;


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
    if (pkg->name) {
        janet_mark(janet_wrap_string(pkg->name));
    }
    if (pkg->out_hash) {
        janet_mark(janet_wrap_string(pkg->out_hash));
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
    } else if (janet_keyeq(key, "builder")) {
        *out = janet_wrap_function(pkg->builder);
        return 1;
    } else if (janet_keyeq(key, "name")) {
        if (pkg->name) {
            *out = janet_wrap_string(pkg->name);
        }
        return 1;
    } else if (janet_keyeq(key, "out-hash")) {
        if (pkg->out_hash) {
            *out = janet_wrap_string(pkg->out_hash);
        }
        return 1;
    } else {
        return 0;
    }
}

static const JanetAbstractType pkg_type = {
    "x/pkg", NULL, pkg_gcmark, pkg_get, NULL, NULL, NULL, NULL, NULL, NULL
};

static HashContext *new_hash_context() {
    HashContext *ctx = janet_smalloc(sizeof(HashContext));
    sha1_init(&ctx->hash_ctx);
    return ctx;
}

static JanetString base16_encode(uint8_t *bytes, size_t nbytes) {
    size_t ntmp = nbytes * 2;
    uint8_t *tmp = janet_smalloc(ntmp);
    char *chartab = "0123456789abcdef";
    for (size_t i = 0; i < nbytes; i++) {
        uint8_t c = bytes[i];
        tmp[2 * i] = chartab[(c & 0xf0) >> 4];
        tmp[2 * i + 1] = chartab[c & 0x0f];
    }
    JanetString r = janet_string(tmp, ntmp);
    janet_sfree(tmp);
    return r;
}

static Janet pkg(int argc, Janet *argv) {
    unsigned char hbuf[HASH_SZ];

    janet_fixarity(argc, 3);

    Pkg *pkg = janet_abstract(&pkg_type, sizeof(Pkg));

    pkg->builder = janet_getfunction(argv, 0);
    pkg->hash = NULL;
    pkg->path = NULL;
    pkg->name = NULL;
    pkg->out_hash = NULL;

    if (janet_checktype(argv[1], JANET_STRING)) {
        pkg->name = janet_unwrap_string(argv[1]);
        // XXX validate name? must be valid path?
        // Must be under a certain length.
        // Some of these restrictions would automatically
        // be exposed in failed builds.
    } else {
        if (!janet_checktype(argv[1], JANET_NIL)) {
            janet_panicf("expected package name to be a string, got %v", argv[1]);
        }
    }

    if (janet_checktype(argv[2], JANET_STRING)) {
        pkg->out_hash = janet_unwrap_string(argv[2]);
    } else {
        if (!janet_checktype(argv[2], JANET_NIL)) {
            janet_panicf("expected package out-hash to be a string, got %v", argv[2]);
        }
    }

    abort();
}

static void direct_dependencies2(JanetTable *deps, Janet v);

static void direct_dependencies_funcdef(JanetTable *deps, JanetFuncDef *def) {
    int32_t i;
    for (i = 0; i < def->constants_length; i++) {
        direct_dependencies2(deps, def->constants[i]);
    }

    for (i = 0; i < def->defs_length; ++i) {
        direct_dependencies_funcdef(deps, def->defs[i]);
    }
}

static void direct_dependencies2(JanetTable *deps, Janet v) {
    switch (janet_type(v)) {
    case JANET_NIL:
    case JANET_NUMBER:
    case JANET_STRING:
    case JANET_KEYWORD:
    case JANET_SYMBOL:
    case JANET_CFUNCTION:
        break;
    case JANET_STRUCT: {
        const JanetKV *kvs = NULL, *kv = NULL;
        int32_t len, cap;
        // FIXME XXX This should be sorted order.
        janet_dictionary_view(v, &kvs, &len, &cap);
        while ((kv = janet_dictionary_next(kvs, cap, kv))) {
            direct_dependencies2(deps, kv->key);
            direct_dependencies2(deps, kv->value);
        }
        break;
    }
    case JANET_TUPLE: {
        const Janet *t = janet_unwrap_tuple(v);
        int32_t len = janet_tuple_length(t);
        for (int32_t i = 0; i < len; i++) {
            direct_dependencies2(deps, t[i]);
        }
        break;
    }
    case JANET_FUNCTION: {
        int32_t i, j;
        JanetFunction *func = janet_unwrap_function(v);

        for (i = 0; i < func->def->environments_length; ++i) {
            JanetFuncEnv *env = func->envs[i];
            if (env->offset) {
                /* On stack */
                janet_panic(
                    "cannot extract dependencies from closures with stack envs");
            } else {
                /* Not on stack */
                for (j = 0; j < env->length; j++) {
                    direct_dependencies2(deps, env->as.values[j]);
                }
            }
        }

        direct_dependencies_funcdef(deps, func->def);
        break;
    }
    case JANET_ABSTRACT: {
        if (janet_checkabstract(v, &pkg_type)) {
            janet_table_put(deps, v, janet_wrap_boolean(1));
            break;
        } else if (janet_checkabstract(v, &janet_peg_type)) {
            JanetPeg *peg = janet_unwrap_abstract(v);
            for (size_t i = 0; i < peg->num_constants; i++) {
                direct_dependencies2(deps, peg->constants[i]);
            }
            break;
        } else if (janet_checkabstract(v, &janet_file_type)) {
            break;
        }
    }
    default:
        janet_panicf("cannot extract package dependencies from %v", v);
    }
}

static Janet direct_dependencies(int argc, Janet *argv) {
    janet_fixarity(argc, 1);
    JanetTable *deps = janet_table(0);
    Pkg *p = janet_getabstract(argv, 0, &pkg_type);
    direct_dependencies2(deps, janet_wrap_function(p->builder));
    return janet_wrap_table(deps);
}

Janet hash(int32_t argc, Janet *argv);

static const JanetReg cfuns[] = {
    {"hash", hash, NULL},
    {"pkg", pkg, "(x/pkg builder)\n"},
    {   "direct-dependencies", direct_dependencies,
        "(x/direct-dependencies pkg)\n"
    },
    {NULL, NULL, NULL}
};

JANET_MODULE_ENTRY(JanetTable *env) {
    janet_cfuns(env, "x", cfuns);
}
