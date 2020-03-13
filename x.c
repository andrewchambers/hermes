#include "sha1.h"
#include <alloca.h>
#include <assert.h>
#include <janet.h>

typedef struct {
  JanetFunction *builder;
  JanetString hash;
} Pkg;

static int pkg_gcmark(void *p, size_t s) {
  (void)s;
  Pkg *pkg = p;
  if (pkg->hash) {
    janet_mark(janet_wrap_string(pkg->hash));
  }
  if (pkg->builder) {
    janet_mark(janet_wrap_function(pkg->builder));
  }
  return 0;
}

static const JanetAbstractType pkg_type = {
    "x/pkg", NULL, pkg_gcmark, NULL, NULL, NULL, NULL, NULL, NULL, NULL};

static Janet pkg(int argc, Janet *argv) {
  janet_fixarity(argc, 1);
  JanetFunction *func = janet_getfunction(argv, 0);
  Pkg *pkg = janet_abstract(&pkg_type, sizeof(Pkg));
  pkg->builder = func;
  pkg->hash = NULL;
  return janet_wrap_abstract(pkg);
}

#define HASH_SZ 20

typedef struct {
  struct sha1_context hash_ctx;
} HashContext;

static HashContext *new_hash_context() {
  HashContext *ctx = janet_smalloc(sizeof(HashContext));
  sha1_init(&ctx->hash_ctx);
  return ctx;
}

static Janet hash(int argc, Janet *argv);
static JanetString hash2(Janet v);
static void hash_add(HashContext *ctx, Janet v);

static void hash_funcdef(HashContext *ctx, JanetFuncDef *def) {
  int32_t i;
  for (i = 0; i < def->constants_length; i++) {
    hash_add(ctx, def->constants[i]);
  }

  for (i = 0; i < def->defs_length; ++i) {
    hash_funcdef(ctx, def->defs[i]);
  }

  sha1_update(&ctx->hash_ctx, (char *)&def->flags, sizeof(def->flags));
  sha1_update(&ctx->hash_ctx, (char *)&def->arity, sizeof(def->arity));
  sha1_update(&ctx->hash_ctx, (char *)&def->min_arity, sizeof(def->min_arity));
  sha1_update(&ctx->hash_ctx, (char *)&def->max_arity, sizeof(def->max_arity));

  for (i = 0; i < def->bytecode_length; i++) {
    sha1_update(&ctx->hash_ctx, (char *)&def->bytecode[i], sizeof(uint32_t));
  }
}

static void hash_add(HashContext *ctx, Janet v) {
  switch (janet_type(v)) {
  case JANET_NIL:
    sha1_update(&ctx->hash_ctx, "n", 1);
    break;
  case JANET_NUMBER: {
    sha1_update(&ctx->hash_ctx, "N", 1);
    double n = janet_unwrap_number(v);
    sha1_update(&ctx->hash_ctx, (char *)&n, sizeof(n));
    break;
  }
  case JANET_STRING: {
    JanetString s = janet_unwrap_string(v);
    sha1_update(&ctx->hash_ctx, "s", 1);
    sha1_update(&ctx->hash_ctx, (char *)s, janet_string_length(s));
    break;
  }
  case JANET_KEYWORD: {
    JanetString s = janet_unwrap_string(v);
    sha1_update(&ctx->hash_ctx, "k", 1);
    sha1_update(&ctx->hash_ctx, (char *)s, janet_string_length(s));
    break;
  }
  case JANET_SYMBOL: {
    JanetString s = janet_unwrap_string(v);
    sha1_update(&ctx->hash_ctx, "S", 1);
    sha1_update(&ctx->hash_ctx, (char *)s, janet_string_length(s));
    break;
  }
  case JANET_STRUCT: {
    sha1_update(&ctx->hash_ctx, "d", 1);
    const JanetKV *kvs = NULL, *kv = NULL;
    int32_t len, cap;
    // FIXME XXX This should be sorted order.
    janet_dictionary_view(v, &kvs, &len, &cap);
    while ((kv = janet_dictionary_next(kvs, cap, kv))) {
      hash_add(ctx, kv->key);
      hash_add(ctx, kv->value);
    }
    break;
  }
  case JANET_TUPLE: {
    sha1_update(&ctx->hash_ctx, "t", 1);
    const Janet *t = janet_unwrap_tuple(v);
    int32_t len = janet_tuple_length(t);
    for (int32_t i = 0; i < len; i++) {
      hash_add(ctx, t[i]);
    }
    break;
  }
  case JANET_FUNCTION: {
    int32_t i, j;
    sha1_update(&ctx->hash_ctx, "f", 1);
    JanetFunction *func = janet_unwrap_function(v);

    for (i = 0; i < func->def->environments_length; ++i) {
      JanetFuncEnv *env = func->envs[i];
      if (env->offset) {
        /* On stack */
        janet_panic("cannot hash function with a stack env");
      } else {
        /* Not on stack */
        for (j = 0; j < env->length; j++) {
          hash_add(ctx, env->as.values[j]);
        }
      }
    }

    hash_funcdef(ctx, func->def);
    break;
  }
  case JANET_CFUNCTION: {
    sha1_update(&ctx->hash_ctx, "c", 1);
    // XXX TODO:
    // We need a table of authorized c functions to names we hash.
    break;
  }
  case JANET_ABSTRACT: {
    if (janet_checkabstract(v, &pkg_type)) {
      sha1_update(&ctx->hash_ctx, "p", 1);
      Pkg *pkg = janet_unwrap_abstract(v);
      JanetString hash = hash2(janet_wrap_function(pkg->builder));
      sha1_update(&ctx->hash_ctx, (char *)hash, janet_string_length(hash));
      break;
    } else {
      // Fall through
    }
  }
  default:
    janet_panicf("cannot hash %v", v);
    break;
  }
}

static JanetString hash2(Janet v) {
  if (janet_checkabstract(v, &pkg_type)) {
    Pkg *pkg = janet_unwrap_abstract(v);
    if (!pkg->hash) {
      assert(pkg->builder);
      pkg->hash = hash2(janet_wrap_function(pkg->builder));
    }
    return pkg->hash;
  }

  HashContext *ctx = new_hash_context();
  unsigned char hbuf[HASH_SZ];
  hash_add(ctx, v);
  sha1_final(&ctx->hash_ctx, hbuf);
  janet_sfree(ctx);
  JanetString hash = janet_string(hbuf, HASH_SZ);
  return hash;
}

static Janet hash(int argc, Janet *argv) {
  janet_fixarity(argc, 1);
  Janet v = argv[0];
  return janet_wrap_string(hash2(v));
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
    }
    // Fall through...
  }
  default:
    janet_panicf("Cannot extract package dependencies from %v", v);
  }
}

static Janet direct_dependencies(int argc, Janet *argv) {
  janet_fixarity(argc, 1);
  JanetTable *deps = janet_table(0);
  Pkg *p = janet_getabstract(argv, 0, &pkg_type);
  direct_dependencies2(deps, janet_wrap_function(p->builder));
  return janet_wrap_table(deps);
}

static const JanetReg cfuns[] = {{"pkg", pkg, "(x/pkg builder)\n"},
                                 {"hash", hash, "(x/hash v)\n"},
                                 {"direct-dependencies", direct_dependencies,
                                  "(x/direct-dependencies pkg)\n"},
                                 {NULL, NULL, NULL}};

JANET_MODULE_ENTRY(JanetTable *env) { janet_cfuns(env, "x", cfuns); }
