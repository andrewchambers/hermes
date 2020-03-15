#include "sha1.h"
#include <alloca.h>
#include <assert.h>
#include <janet.h>
#include <unistd.h>

#define HASH_SZ 20

typedef struct {
  struct sha1_context hash_ctx;
} HashContext;

typedef struct {
  JanetFunction *builder;
  JanetString hash;
  JanetString path;
  JanetString name;
  JanetString out_hash;
} Pkg;

static JanetString hash(Janet v);
static void hash_add(HashContext *ctx, Janet v);
static Janet pkg_get_hash(int argc, Janet *argv);

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
    "x/pkg", NULL, pkg_gcmark, pkg_get, NULL, NULL, NULL, NULL, NULL, NULL};

static HashContext *new_hash_context() {
  HashContext *ctx = janet_smalloc(sizeof(HashContext));
  sha1_init(&ctx->hash_ctx);
  return ctx;
}

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
      sha1_update(&ctx->hash_ctx, (char *)pkg->hash,
                  janet_string_length(pkg->hash));
      break;
    } else if (janet_checkabstract(v, &janet_peg_type)) {
      JanetPeg *peg = janet_unwrap_abstract(v);
      sha1_update(&ctx->hash_ctx, "b", 1);
      for (size_t i = 0; i < peg->num_constants; i++) {
        hash_add(ctx, peg->constants[i]);
      }
      sha1_update(&ctx->hash_ctx, "c", 1);
      for (size_t i = 0; i < peg->bytecode_len; i++) {
        sha1_update(&ctx->hash_ctx, (char *)&peg->bytecode[i],
                    sizeof(peg->bytecode[i]));
      }
      break;
    } else if (janet_checkabstract(v, &janet_file_type)) {
      sha1_update(&ctx->hash_ctx, "c", 1);

      FILE *f = janet_unwrapfile(v, NULL);

      switch (fileno(f)) {
      case STDIN_FILENO:
        sha1_update(&ctx->hash_ctx, "i", 1);
        break;
      case STDOUT_FILENO:
        sha1_update(&ctx->hash_ctx, "o", 1);
        break;
      case STDERR_FILENO:
        sha1_update(&ctx->hash_ctx, "e", 1);
        break;
      default:
        janet_panicf("cannot file that is not stdin, stderr or stdout %v", v);
      }
      break;
    }
    /* FALLTHROUGH */
  }
  default:
    janet_panicf("cannot hash %v", v);
    break;
  }
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

  HashContext *ctx = new_hash_context();

  sha1_update(&ctx->hash_ctx, "b", 1);
  hash_add(ctx, janet_wrap_function(pkg->builder));
  sha1_update(&ctx->hash_ctx, "n", 1);
  if (pkg->name) {
    hash_add(ctx, janet_wrap_string(pkg->name));
  }
  sha1_update(&ctx->hash_ctx, "o", 1);
  if (pkg->out_hash) {
    hash_add(ctx, janet_wrap_string(pkg->out_hash));
  }
  sha1_final(&ctx->hash_ctx, hbuf);
  janet_sfree(ctx);
  // XXX We probably want a larger base covering more of the ascii range.
  pkg->hash = base16_encode(hbuf, HASH_SZ);

  // XXX configurable.
  char *prefix = "/tmp/xstore/pkgs";
  size_t pathsz = strlen(prefix) + janet_string_length(pkg->hash) + 1;
  char *tmppath = janet_smalloc(pathsz);
  snprintf(tmppath, pathsz, "%s/%s", prefix, pkg->hash);
  pkg->path = janet_string((uint8_t *)tmppath, pathsz - 1);
  janet_sfree(tmppath);
  return janet_wrap_abstract(pkg);
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

static const JanetReg cfuns[] = {{"pkg", pkg, "(x/pkg builder)\n"},
                                 {"direct-dependencies", direct_dependencies,
                                  "(x/direct-dependencies pkg)\n"},
                                 {NULL, NULL, NULL}};

JANET_MODULE_ENTRY(JanetTable *env) { janet_cfuns(env, "x", cfuns); }
