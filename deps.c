#include <janet.h>
#include "hermes.h"

static void pkg_dependencies2(JanetTable *deps, Janet v);

static void pkg_dependencies_funcdef(JanetTable *deps, JanetFuncDef *def) {
    int32_t i;
    for (i = 0; i < def->constants_length; i++) {
        pkg_dependencies2(deps, def->constants[i]);
    }

    for (i = 0; i < def->defs_length; ++i) {
        pkg_dependencies_funcdef(deps, def->defs[i]);
    }
}

static void pkg_dependencies2(JanetTable *deps, Janet v) {
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
            pkg_dependencies2(deps, kv->key);
            pkg_dependencies2(deps, kv->value);
        }
        break;
    }
    case JANET_TUPLE: {
        const Janet *t = janet_unwrap_tuple(v);
        int32_t len = janet_tuple_length(t);
        for (int32_t i = 0; i < len; i++) {
            pkg_dependencies2(deps, t[i]);
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
                // XXX TODO, we should be able to handle this.
                janet_panic(
                    "cannot extract dependencies from closures with stack envs");
            } else {
                /* Not on stack */
                for (j = 0; j < env->length; j++) {
                    pkg_dependencies2(deps, env->as.values[j]);
                }
            }
        }

        pkg_dependencies_funcdef(deps, func->def);
        break;
    }
    case JANET_ABSTRACT: {
        if (janet_checkabstract(v, &pkg_type)) {
            janet_table_put(deps, v, janet_wrap_boolean(1));
            break;
        } else if (janet_checkabstract(v, &janet_peg_type)) {
            JanetPeg *peg = janet_unwrap_abstract(v);
            for (size_t i = 0; i < peg->num_constants; i++) {
                pkg_dependencies2(deps, peg->constants[i]);
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

Janet pkg_dependencies(int argc, Janet *argv) {
    janet_fixarity(argc, 1);
    JanetTable *deps = janet_table(0);
    Pkg *p = janet_getabstract(argv, 0, &pkg_type);
    pkg_dependencies2(deps, janet_wrap_function(p->builder));
    return janet_wrap_table(deps);
}
