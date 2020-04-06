
#define HASH_SZ 20
#include "sha1.h"

/* types */

typedef struct {
    Sha1ctx sha1_ctx;
    JanetTable seen;
    JanetTable *rreg;
    JanetFuncEnv **seen_envs;
    JanetFuncDef **seen_defs;
    int32_t nextid;
} HashState;

typedef struct {
    Janet hash;  // nil or string
    Janet builder; // nil function
    Janet path; // nil or string
    Janet name; // nil or string
    Janet content; // nil or string or struct
    Janet extra_refs; // nil or [Pkg]
    Janet forced_refs; // nil or [Pkg]
    Janet weak_refs; // nil or [Pkg]
} Pkg;

/* hermes.c */

extern const JanetAbstractType pkg_type;

/* pkghash.c */

Janet pkg_hash(int32_t argc, Janet *argv);

/* pathhash.c */

Janet sha256_dir_hash(int argc, Janet *argv);
Janet sha256_file_hash(int argc, Janet *argv);

/* hashscan.c */

Janet hash_scan(int32_t argc, Janet *argv);

/* deps.c */

Janet pkg_dependencies(int argc, Janet *argv);

/* base16.c */

void base16_encode(char *outbuf, char *inbuf, size_t in_length);

/*  scratchvec.c */

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

void *scratch_v_grow(void *v, int32_t increment, int32_t itemsize);
void *scratch_v_flattenmem(void *v, int32_t itemsize);

/* os.c */

Janet jgetpwnam(int argc, Janet *argv);
Janet jgetpwuid(int argc, Janet *argv);
Janet jsetuid(int argc, Janet *argv);
Janet jseteuid(int argc, Janet *argv);
Janet jsetegid(int argc, Janet *argv);
Janet jgetuid(int argc, Janet *argv);
Janet jgeteuid(int argc, Janet *argv);
Janet jgetgid(int argc, Janet *argv);
Janet jgetegid(int argc, Janet *argv);


