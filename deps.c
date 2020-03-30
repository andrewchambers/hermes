#include <janet.h>
#include "hermes.h"

static void pkg_dependencies2(JanetTable *deps, JanetTable *seen, Janet v);

static void pkg_dependencies_funcdef(JanetTable *deps, JanetTable *seen, JanetFuncDef *def) {
    int32_t i;
    for (i = 0; i < def->constants_length; i++) {
        pkg_dependencies2(deps, seen, def->constants[i]);
    }

    for (i = 0; i < def->defs_length; ++i) {
        pkg_dependencies_funcdef(deps, seen, def->defs[i]);
    }
}

static void pkg_dependencies2(JanetTable *deps, JanetTable *seen, Janet v) {
    if (!janet_checktype(janet_table_get(seen, v), JANET_NIL)) {
        return;
    }
    switch (janet_type(v)) {
    case JANET_NIL:
    case JANET_NUMBER:
    case JANET_STRING:
    case JANET_KEYWORD:
    case JANET_SYMBOL:
    case JANET_CFUNCTION:
        return;
    case JANET_TABLE:
    case JANET_STRUCT: {
        janet_table_put(seen, v, janet_wrap_boolean(1));

        const JanetKV *kvs = NULL, *kv = NULL;
        int32_t len, cap;
        janet_dictionary_view(v, &kvs, &len, &cap);
        while ((kv = janet_dictionary_next(kvs, cap, kv))) {
            pkg_dependencies2(deps, seen, kv->key);
            pkg_dependencies2(deps, seen, kv->value);
        }
        return;
    }
    case JANET_ARRAY:
    case JANET_TUPLE: {
        janet_table_put(seen, v, janet_wrap_boolean(1));
        int32_t len;
        const Janet *data;
        janet_indexed_view(v, &data, &len);
        for (int32_t i = 0; i < len; i++) {
            pkg_dependencies2(deps, seen, data[i]);
        }
        return;
    }
    case JANET_FUNCTION: {
        janet_table_put(seen, v, janet_wrap_boolean(1));

        int32_t i, j;
        JanetFunction *func = janet_unwrap_function(v);

        for (i = 0; i < func->def->environments_length; ++i) {
            JanetFuncEnv *env = func->envs[i];
            if (env->offset) {
                janet_panic(
                    "cannot extract dependencies from closure referencing current stack frame");
            } else {
                /* Not on stack */
                for (j = 0; j < env->length; j++) {
                    pkg_dependencies2(deps, seen, env->as.values[j]);
                }
            }
        }

        pkg_dependencies_funcdef(deps, seen, func->def);
        return;
    }
    case JANET_ABSTRACT: {
        janet_table_put(seen, v, janet_wrap_boolean(1));
        if (janet_checkabstract(v, &pkg_type)) {
            janet_table_put(deps, v, janet_wrap_boolean(1));
            return;
        } else if (janet_checkabstract(v, &janet_peg_type)) {
            JanetPeg *peg = janet_unwrap_abstract(v);
            for (size_t i = 0; i < peg->num_constants; i++) {
                pkg_dependencies2(deps, seen, peg->constants[i]);
            }
            return;
        } else if (janet_checkabstract(v, &janet_file_type)) {
            return;
        }
        /* fallthrough */
    }
    }
    janet_panicf("cannot extract package dependencies from %v", v);
}

Janet pkg_dependencies(int argc, Janet *argv) {
    janet_fixarity(argc, 1);
    JanetTable *deps = janet_table(0);
    JanetTable *seen = janet_table(1);
    Pkg *p = janet_getabstract(argv, 0, &pkg_type);
    pkg_dependencies2(deps, seen, p->builder);
    pkg_dependencies2(deps, seen, p->forced_refs);
    pkg_dependencies2(deps, seen, p->extra_refs);
    pkg_dependencies2(deps, seen, p->weak_refs);
    return janet_wrap_table(deps);
}
