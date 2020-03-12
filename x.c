#include <alloca.h>
#include <janet.h>
#include "sha1.h"

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
    // XXX TODO: 
    // Some builtins are so valuable, we must be able to hash them...
    // PEG, int/s64 int/u64
    // marshal may be a way to cheat, but it doesn't solve the problem
    // of walking the embedded rules...
    break;
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

static const JanetReg cfuns[] = {{"hash", hash, "(x/hash cache v)\n"},
                                 {NULL, NULL, NULL}};

JANET_MODULE_ENTRY(JanetTable *env) { janet_cfuns(env, "x", cfuns); }
