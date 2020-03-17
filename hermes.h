
#define HASH_SZ 20
#include "sha1.h"

/* types */

typedef struct {
    struct sha1_context sha1_ctx;
    JanetTable seen;
    JanetTable *rreg;
    JanetFuncEnv **seen_envs;
    JanetFuncDef **seen_defs;
    int32_t nextid;
} HashState;

typedef struct {
    JanetString hash;
    JanetFunction *builder;
    JanetString frozen_builder;
    JanetString path;
    JanetString name;
} Pkg;


/* hermes.c */

extern const JanetAbstractType pkg_type;

/* pkg_hash.c */

Janet pkg_hash(int32_t argc, Janet *argv);

/* deps.c */

Janet pkg_dependencies(int argc, Janet *argv);

/*  util.c */

#define scratch_v_free(v)         (((v) != NULL) ? (janet_sfree(scratch_v__raw(v)), 0) : 0)
#define scratch_v_push(v, x)      (scratch_v__maybegrow(v, 1), (v)[scratch_v__cnt(v)++] = (x))
#define scratch_v_pop(v)          (scratch_v_count(v) ? scratch_v__cnt(v)-- : 0)
#define scratch_v_count(v)        (((v) != NULL) ? scratch_v__cnt(v) : 0)
#define scratch_v_last(v)         ((v)[scratch_v__cnt(v) - 1])
#define scratch_v_empty(v)        (((v) != NULL) ? (scratch_v__cnt(v) = 0) : 0)
#define scratch_v_flatten(v)      (scratch_v_flattenmem((v), sizeof(*(v))))

#define scratch_v__raw(v) ((int32_t *)(v) - 2)
#define scratch_v__cap(v) scratch_v__raw(v)[0]
#define scratch_v__cnt(v) scratch_v__raw(v)[1]

#define scratch_v__needgrow(v, n)  ((v) == NULL || scratch_v__cnt(v) + (n) >= scratch_v__cap(v))
#define scratch_v__maybegrow(v, n) (scratch_v__needgrow((v), (n)) ? scratch_v__grow((v), (n)) : 0)
#define scratch_v__grow(v, n)      ((v) = scratch_v_grow((v), (n), sizeof(*(v))))

static void safe_memcpy(void *dest, const void *src, size_t len) {
    if (!len) return;
    memcpy(dest, src, len);
}

void *scratch_v_grow(void *v, int32_t increment, int32_t itemsize);
void *scratch_v_flattenmem(void *v, int32_t itemsize);

