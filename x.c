#include "sha1.h"
#include <alloca.h>
#include <janet.h>

typedef struct {
  JanetFunction *builder;
} Pkg;

static int pkg_gc(void *p, size_t s) {
  (void)s;
  Pkg *pkg = p;
  janet_mark(janet_wrap_function(pkg->builder));
  return 0;
}

static const JanetAbstractType pkg_type = {"x/pkg", pkg_gc, NULL, NULL, NULL,
                                           NULL,    NULL,   NULL, NULL, NULL};

static Janet pkg(int argc, Janet *argv) {
  janet_fixarity(argc, 1);
  JanetFunction *func = janet_getfunction(argv, 0);
  Pkg *pkg = janet_abstract(&pkg_type, sizeof(Pkg));
  pkg->builder = func;
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

static void hash_add(HashContext *ctx, JanetTable *hash_cache, Janet v);

static void hash_funcdef(HashContext *ctx, JanetTable *hash_cache,
                         JanetFuncDef *def) {
  int32_t i;
  for (i = 0; i < def->constants_length; i++) {
    hash_add(ctx, hash_cache, def->constants[i]);
  }

  for (i = 0; i < def->defs_length; ++i) {
    hash_funcdef(ctx, hash_cache, def->defs[i]);
  }

  sha1_update(&ctx->hash_ctx, (char *)&def->flags, sizeof(def->flags));
  sha1_update(&ctx->hash_ctx, (char *)&def->arity, sizeof(def->arity));
  sha1_update(&ctx->hash_ctx, (char *)&def->min_arity, sizeof(def->min_arity));
  sha1_update(&ctx->hash_ctx, (char *)&def->max_arity, sizeof(def->max_arity));

  for (i = 0; i < def->bytecode_length; i++) {
    sha1_update(&ctx->hash_ctx, (char *)&def->bytecode[i], sizeof(uint32_t));
  }
}

static void hash_add(HashContext *ctx, JanetTable *hash_cache, Janet v) {
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
      hash_add(ctx, hash_cache, kv->key);
      hash_add(ctx, hash_cache, kv->value);
    }
    break;
  }
  case JANET_TUPLE: {
    sha1_update(&ctx->hash_ctx, "t", 1);
    const Janet *t = janet_unwrap_tuple(v);
    int32_t len = janet_tuple_length(t);
    for (int32_t i = 0; i < len; i++) {
      hash_add(ctx, hash_cache, t[i]);
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
          hash_add(ctx, hash_cache, env->as.values[j]);
        }
      }
    }

    hash_funcdef(ctx, hash_cache, func->def);
    break;
  }
  case JANET_CFUNCTION: {
    sha1_update(&ctx->hash_ctx, "c", 1);
    // XXX TODO:
    // We need a table of authorized c functions to names we hash.
    break;
  }
  case JANET_ABSTRACT: {
    sha1_update(&ctx->hash_ctx, "a", 1);
    if (janet_checkabstract(v, &pkg_type)) {
      sha1_update(&ctx->hash_ctx, "p", 1);
      Pkg *pkg = janet_unwrap_abstract(v);
      hash_add(ctx, hash_cache, janet_wrap_function(pkg->builder));
      break;
    } else {
      // XXX TODO:
      // Some builtins are so valuable, we must be able to hash them...
      // PEG, int/s64 int/u64
      // marshal may be a way to cheat, but it doesn't solve the problem
      // of walking the embedded rules...
      break;
    }
  }
  default:
    janet_panicf("cannot hash %v", v);
    break;
  }
}

static Janet hash2(HashContext *ctx, JanetTable *hash_cache, Janet v) {
  hash_add(ctx, hash_cache, v);
  JanetBuffer *b = janet_buffer(HASH_SZ);
  janet_buffer_setcount(b, HASH_SZ);
  sha1_final(&ctx->hash_ctx, b->data);
  janet_sfree(ctx);
  return janet_wrap_buffer(b);
}

static Janet hash(int argc, Janet *argv) {
  janet_fixarity(argc, 2);
  HashContext *ctx = new_hash_context();
  JanetTable *hash_cache = janet_gettable(argv, 0);
  Janet v = argv[1];
  // TODO
  // We must add the build architecture,
  // Janet version and store path to the hash.
  // These invalidate the hash cache.
  return hash2(ctx, hash_cache, v);
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
        janet_panic("cannot hash function with a stack env");
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
                                 {"hash", hash, "(x/hash cache v)\n"},
                                 {"direct-dependencies", direct_dependencies,
                                  "(x/direct-dependencies pkg)\n"},
                                 {NULL, NULL, NULL}};

JANET_MODULE_ENTRY(JanetTable *env) { janet_cfuns(env, "x", cfuns); }
