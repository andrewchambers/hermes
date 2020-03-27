/*
* Copyright (c) 2020 Calvin Rose
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to
* deal in the Software without restriction, including without limitation the
* rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
* sell copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
* IN THE SOFTWARE.
*/

#include <alloca.h>
#include <janet.h>
#include "hermes.h"

/* Lead bytes in hashing protocol */
enum {
    LB_REAL = 200,
    LB_NIL,
    LB_FALSE,
    LB_TRUE,
    LB_FIBER,
    LB_INTEGER,
    LB_STRING,
    LB_SYMBOL,
    LB_KEYWORD,
    LB_ARRAY,
    LB_TUPLE,
    LB_TABLE,
    LB_TABLE_PROTO,
    LB_STRUCT,
    LB_BUFFER,
    LB_FUNCTION,
    LB_REGISTRY,
    LB_ABSTRACT,
    LB_REFERENCE,
    LB_FUNCENV_REF,
    LB_FUNCDEF_REF
} LeadBytes;

/* Marshal an integer onto the buffer */
static void pushint(HashState *st, int32_t x) {
    if (x >= 0 && x < 128) {
        uint8_t buf[1] = {(uint8_t)x};
        sha1_update(&st->sha1_ctx, (char*)buf, 1);
    } else if (x <= 8191 && x >= -8192) {
        uint8_t intbuf[2];
        intbuf[0] = ((x >> 8) & 0x3F) | 0x80;
        intbuf[1] = x & 0xFF;
        sha1_update(&st->sha1_ctx, (char*)intbuf, 2);
    } else {
        uint8_t intbuf[5];
        intbuf[0] = LB_INTEGER;
        intbuf[1] = (x >> 24) & 0xFF;
        intbuf[2] = (x >> 16) & 0xFF;
        intbuf[3] = (x >> 8) & 0xFF;
        intbuf[4] = x & 0xFF;
        sha1_update(&st->sha1_ctx, (char*)intbuf, 5);
    }
}

static void pushbyte(HashState *st, uint8_t b) {
    uint8_t buf[1] = {b};
    sha1_update(&st->sha1_ctx, (char*)buf, 1);
}

static void pushbytes(HashState *st, const uint8_t *bytes, int32_t len) {
    sha1_update(&st->sha1_ctx, (char*)bytes, len);
}

/* Forward declaration to enable mutual recursion. */
static void hash_one(HashState *st, Janet x, int flags);
static void hash_one_fiber(HashState *st, JanetFiber *fiber, int flags);
static void hash_one_def(HashState *st, JanetFuncDef *def, int flags);
static void hash_one_env(HashState *st, JanetFuncEnv *env, int flags);

/* Prevent stack overflows */
#define HASH_STACKCHECK if ((flags & 0xFFFF) > JANET_RECURSION_GUARD) janet_panic("stack overflow")

/* Hash a function env */
static void hash_one_env(HashState *st, JanetFuncEnv *env, int flags) {
    HASH_STACKCHECK;
    for (int32_t i = 0; i < scratch_v_count(st->seen_envs); i++) {
        if (st->seen_envs[i] == env) {
            pushbyte(st, LB_FUNCENV_REF);
            pushint(st, i);
            return;
        }
    }
    scratch_v_push(st->seen_envs, env);
    if (env->offset && (JANET_STATUS_ALIVE == janet_fiber_status(env->as.fiber))) {
        janet_panic("cannot hash closure referencing current fiber frame.");
    } else {
        pushint(st, env->offset);
        pushint(st, env->length);
        if (env->offset) {
            /* On stack variant */
            hash_one(st, janet_wrap_fiber(env->as.fiber), flags + 1);
        } else {
            /* Off stack variant */
            for (int32_t i = 0; i < env->length; i++)
                hash_one(st, env->as.values[i], flags + 1);
        }
    }
}

/* Add function flags to janet functions */
static void janet_func_addflags(JanetFuncDef *def) {
    if (def->name) def->flags |= JANET_FUNCDEF_FLAG_HASNAME;
    if (def->source) def->flags |= JANET_FUNCDEF_FLAG_HASSOURCE;
    if (def->defs) def->flags |= JANET_FUNCDEF_FLAG_HASDEFS;
    if (def->environments) def->flags |= JANET_FUNCDEF_FLAG_HASENVS;
    if (def->sourcemap) def->flags |= JANET_FUNCDEF_FLAG_HASSOURCEMAP;
}

/* Marshal a function def */
static void hash_one_def(HashState *st, JanetFuncDef *def, int flags) {
    HASH_STACKCHECK;
    for (int32_t i = 0; i < scratch_v_count(st->seen_defs); i++) {
        if (st->seen_defs[i] == def) {
            pushbyte(st, LB_FUNCDEF_REF);
            pushint(st, i);
            return;
        }
    }
    janet_func_addflags(def);
    /* Add to lookup */
    scratch_v_push(st->seen_defs, def);
    pushint(st, def->flags);
    pushint(st, def->slotcount);
    pushint(st, def->arity);
    pushint(st, def->min_arity);
    pushint(st, def->max_arity);
    pushint(st, def->constants_length);
    pushint(st, def->bytecode_length);
    if (def->flags & JANET_FUNCDEF_FLAG_HASENVS)
        pushint(st, def->environments_length);
    if (def->flags & JANET_FUNCDEF_FLAG_HASDEFS)
        pushint(st, def->defs_length);
    if (def->flags & JANET_FUNCDEF_FLAG_HASNAME)
        hash_one(st, janet_wrap_string(def->name), flags);

    /* hash constants */
    for (int32_t i = 0; i < def->constants_length; i++)
        hash_one(st, def->constants[i], flags);

    /* hash the bytecode */
    for (int32_t i = 0; i < def->bytecode_length; i++) {
        pushbyte(st, def->bytecode[i] & 0xFF);
        pushbyte(st, (def->bytecode[i] >> 8) & 0xFF);
        pushbyte(st, (def->bytecode[i] >> 16) & 0xFF);
        pushbyte(st, (def->bytecode[i] >> 24) & 0xFF);
    }

    /* hash the environments if needed */
    for (int32_t i = 0; i < def->environments_length; i++)
        pushint(st, def->environments[i]);

    /* hash the sub funcdefs if needed */
    for (int32_t i = 0; i < def->defs_length; i++)
        hash_one_def(st, def->defs[i], flags);
}

#define JANET_FIBER_FLAG_HASCHILD (1 << 29)
#define JANET_FIBER_FLAG_HASENV (1 << 28)
#define JANET_STACKFRAME_HASENV (1 << 30)

/* Marshal a fiber */
static void hash_one_fiber(HashState *st, JanetFiber *fiber, int flags) {
    HASH_STACKCHECK;
    int32_t fflags = fiber->flags;
    if (fiber->child) fflags |= JANET_FIBER_FLAG_HASCHILD;
    if (fiber->env) fflags |= JANET_FIBER_FLAG_HASENV;
    if (janet_fiber_status(fiber) == JANET_STATUS_ALIVE)
        janet_panic("cannot hash alive fiber");
    pushint(st, fflags);
    pushint(st, fiber->frame);
    pushint(st, fiber->stackstart);
    pushint(st, fiber->stacktop);
    pushint(st, fiber->maxstack);
    /* Do frames */
    int32_t i = fiber->frame;
    int32_t j = fiber->stackstart - JANET_FRAME_SIZE;
    while (i > 0) {
        JanetStackFrame *frame = (JanetStackFrame *)(fiber->data + i - JANET_FRAME_SIZE);
        if (frame->env) frame->flags |= JANET_STACKFRAME_HASENV;
        if (!frame->func) janet_panic("cannot hash fiber with c stackframe");
        pushint(st, frame->flags);
        pushint(st, frame->prevframe);
        int32_t pcdiff = (int32_t)(frame->pc - frame->func->def->bytecode);
        pushint(st, pcdiff);
        hash_one(st, janet_wrap_function(frame->func), flags + 1);
        if (frame->env) hash_one_env(st, frame->env, flags + 1);
        /* Marshal all values in the stack frame */
        for (int32_t k = i; k < j; k++)
            hash_one(st, fiber->data[k], flags + 1);
        j = i - JANET_FRAME_SIZE;
        i = frame->prevframe;
    }
    if (fiber->env) {
        hash_one(st, janet_wrap_table(fiber->env), flags + 1);
    }
    if (fiber->child)
        hash_one(st, janet_wrap_fiber(fiber->child), flags + 1);
}

#define MARK_SEEN() \
    janet_table_put(&st->seen, x, janet_wrap_integer(st->nextid++))

static void hash_one_abstract(HashState *st, Janet x, int flags) {
    void *abstract = janet_unwrap_abstract(x);
    const JanetAbstractType *at = janet_abstract_type(abstract);
    pushbyte(st, LB_ABSTRACT);
    hash_one(st, janet_csymbolv(at->name), flags + 1);
    if (at == &pkg_type) {
        Pkg *pkg = abstract;
        if (!janet_checktype(pkg->hash, JANET_STRING)) {
            janet_panic("package does not have computed hash");
        }
        JanetString hash = janet_unwrap_string(pkg->hash);
        pushbytes(st, hash, janet_string_length(hash));
    } else {
        janet_panicf("unable to hash %v", x);
    }
}

/* The main body of the hashing function. Is the main
 * entry point for the mutually recursive functions. */
static void hash_one(HashState *st, Janet x, int flags) {
    HASH_STACKCHECK;
    JanetType type = janet_type(x);

    /* Check simple primitives (non reference types, no benefit from memoization) */
    switch (type) {
    default:
        break;
    case JANET_NIL:
        pushbyte(st, LB_NIL);
        return;
    case JANET_BOOLEAN:
        pushbyte(st, janet_unwrap_boolean(x) ? LB_TRUE : LB_FALSE);
        return;
    case JANET_NUMBER: {
        double xval = janet_unwrap_number(x);
        if (janet_checkintrange(xval)) {
            pushint(st, (int32_t) xval);
            return;
        }
        break;
    }
    }

    /* Check reference and registry value */
    {
        Janet check = janet_table_get(&st->seen, x);
        if (janet_checkint(check)) {
            pushbyte(st, LB_REFERENCE);
            pushint(st, janet_unwrap_integer(check));
            return;
        }
        if (st->rreg) {
            check = janet_table_get(st->rreg, x);
            if (janet_checktype(check, JANET_SYMBOL)) {
                MARK_SEEN();
                const uint8_t *regname = janet_unwrap_symbol(check);
                pushbyte(st, LB_REGISTRY);
                pushint(st, janet_string_length(regname));
                pushbytes(st, regname, janet_string_length(regname));
                return;
            }
        }
    }

    /* Reference types */
    switch (type) {
    case JANET_NUMBER: {
        union {
            double d;
            uint8_t bytes[8];
        } u;
        u.d = janet_unwrap_number(x);
#ifdef JANET_BIG_ENDIAN
        /* Swap byte order */
        uint8_t temp;
        temp = u.bytes[7];
        u.bytes[7] = u.bytes[0];
        u.bytes[0] = temp;
        temp = u.bytes[6];
        u.bytes[6] = u.bytes[1];
        u.bytes[1] = temp;
        temp = u.bytes[5];
        u.bytes[5] = u.bytes[2];
        u.bytes[2] = temp;
        temp = u.bytes[4];
        u.bytes[4] = u.bytes[3];
        u.bytes[3] = temp;
#endif
        pushbyte(st, LB_REAL);
        pushbytes(st, u.bytes, 8);
        MARK_SEEN();
        return;
    }
    case JANET_STRING:
    case JANET_SYMBOL:
    case JANET_KEYWORD: {
        const uint8_t *str = janet_unwrap_string(x);
        int32_t length = janet_string_length(str);
        /* Record reference */
        MARK_SEEN();
        uint8_t lb = (type == JANET_STRING) ? LB_STRING :
                     (type == JANET_SYMBOL) ? LB_SYMBOL :
                     LB_KEYWORD;
        pushbyte(st, lb);
        pushint(st, length);
        pushbytes(st, str, length);
        return;
    }
    case JANET_BUFFER: {
        JanetBuffer *buffer = janet_unwrap_buffer(x);
        /* Record reference */
        MARK_SEEN();
        pushbyte(st, LB_BUFFER);
        pushint(st, buffer->count);
        pushbytes(st, buffer->data, buffer->count);
        return;
    }
    case JANET_ARRAY: {
        int32_t i;
        JanetArray *a = janet_unwrap_array(x);
        MARK_SEEN();
        pushbyte(st, LB_ARRAY);
        pushint(st, a->count);
        for (i = 0; i < a->count; i++)
            hash_one(st, a->data[i], flags + 1);
        return;
    }
    case JANET_TUPLE: {
        int32_t i, count, flag;
        const Janet *tup = janet_unwrap_tuple(x);
        count = janet_tuple_length(tup);
        flag = janet_tuple_flag(tup) >> 16;
        pushbyte(st, LB_TUPLE);
        pushint(st, count);
        pushint(st, flag);
        for (i = 0; i < count; i++)
            hash_one(st, tup[i], flags + 1);
        /* Mark as seen AFTER hashing */
        MARK_SEEN();
        return;
    }
    case JANET_TABLE: {
        JanetTable *t = janet_unwrap_table(x);
        MARK_SEEN();
        pushbyte(st, t->proto ? LB_TABLE_PROTO : LB_TABLE);
        pushint(st, t->count);
        if (t->proto)
            hash_one(st, janet_wrap_table(t->proto), flags + 1);
        for (int32_t i = 0; i < t->capacity; i++) {
            if (janet_checktype(t->data[i].key, JANET_NIL))
                continue;
            hash_one(st, t->data[i].key, flags + 1);
            hash_one(st, t->data[i].value, flags + 1);
        }
        return;
    }
    case JANET_STRUCT: {
        int32_t count;
        const JanetKV *struct_ = janet_unwrap_struct(x);
        count = janet_struct_length(struct_);
        pushbyte(st, LB_STRUCT);
        pushint(st, count);
        for (int32_t i = 0; i < janet_struct_capacity(struct_); i++) {
            if (janet_checktype(struct_[i].key, JANET_NIL))
                continue;
            hash_one(st, struct_[i].key, flags + 1);
            hash_one(st, struct_[i].value, flags + 1);
        }
        /* Mark as seen AFTER hashing */
        MARK_SEEN();
        return;
    }
    case JANET_ABSTRACT: {
        hash_one_abstract(st, x, flags);
        return;
    }
    case JANET_FUNCTION: {
        pushbyte(st, LB_FUNCTION);
        JanetFunction *func = janet_unwrap_function(x);
        hash_one_def(st, func->def, flags);
        /* Mark seen after reading def, but before envs */
        MARK_SEEN();
        for (int32_t i = 0; i < func->def->environments_length; i++)
            hash_one_env(st, func->envs[i], flags + 1);
        return;
    }
    case JANET_FIBER: {
        MARK_SEEN();
        pushbyte(st, LB_FIBER);
        hash_one_fiber(st, janet_unwrap_fiber(x), flags + 1);
        return;
    }
    default: {
        janet_panicf("no registry value and cannot hash %p", x);
        return;
    }
    }
#undef MARK_SEEN
}

static void init_pkg_hash_state(HashState *st, JanetTable *rreg) {
    sha1_init(&st->sha1_ctx);
    st->nextid = 0;
    st->seen_defs = NULL;
    st->seen_envs = NULL;
    st->rreg = rreg;
    janet_table_init(&st->seen, 0);
    pushbytes(st, (const uint8_t *)JANET_VERSION, strlen(JANET_VERSION));
}

static void base16_encode(char *outbuf, char *inbuf, size_t in_length) {
    const char *chartab = "0123456789abcdef";
    for (size_t i = 0; i < in_length; i++) {
        uint8_t c = inbuf[i];
        outbuf[2 * i] = chartab[(c & 0xf0) >> 4];
        outbuf[2 * i + 1] = chartab[c & 0x0f];
    }
}

static JanetString finalize_pkg_hash_state(HashState *st) {
    uint8_t buf[HASH_SZ];
    uint8_t hexbuf[HASH_SZ*2];
    sha1_final(&st->sha1_ctx, &buf[0]);
    base16_encode((char*)hexbuf, (char*)buf, sizeof(buf));
    janet_table_deinit(&st->seen);
    scratch_v_free(st->seen_envs);
    scratch_v_free(st->seen_defs);
    return janet_string(hexbuf, sizeof(hexbuf));
}

static Janet make_pkg_path(JanetString store_path, JanetString hash, Janet name) {
    size_t name_len = 0;
    JanetString name_str = NULL;

    if (janet_checktype(name, JANET_STRING)) {
        name_str = janet_unwrap_string(name);
        name_len = janet_string_length(name_str);
    }

    size_t prefix_sz = janet_string_length(store_path) + 5;
    size_t ntmp = prefix_sz + janet_string_length(hash) + (name_str ? name_len + 1 : 0);
    uint8_t *tmp = alloca(ntmp);
    memcpy(tmp, store_path, janet_string_length(store_path));
    memcpy(tmp + janet_string_length(store_path), "/pkg/", 5);
    uint8_t *hashout = tmp + prefix_sz;
    size_t hash_len = janet_string_length(hash);
    memcpy(hashout, hash, hash_len);
    uint8_t *nameout = hashout + hash_len;
    if (name_str) {
        nameout[0] = '-';
        memcpy(nameout+1, name_str, name_len);
    }
    return janet_stringv(tmp, ntmp);
}

// XXX Maybe this should be called 'freeze', 'finalize', or some other word.
// Not only do we hash he package, we compute and cache it's path on disk.
Janet pkg_hash(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 3);

    if (!janet_checktypes(argv[0], JANET_TFLAG_STRING))
        janet_panicf("store-path must be a string, got %v", argv[0]);

    if (!janet_checktypes(argv[1], JANET_TFLAG_TABLE))
        janet_panicf("registry must be a table, got %v", argv[1]);

    if (!janet_checkabstract(argv[2], &pkg_type))
        janet_panicf("expected a pkg object, got %v", argv[2]);

    JanetString store_path = janet_unwrap_string(argv[0]);
    JanetTable *rreg = janet_unwrap_table(argv[1]);
    Pkg *pkg = janet_unwrap_abstract(argv[2]);
    HashState st;
    init_pkg_hash_state(&st, rreg);
    hash_one(&st, janet_wrap_string(store_path), 0);
    hash_one(&st, pkg->name, 0);
    hash_one(&st, pkg->builder, 0);

    JanetString hash = finalize_pkg_hash_state(&st);
    pkg->hash = janet_wrap_string(hash);
    pkg->path = make_pkg_path(store_path, hash, pkg->name);

    return pkg->hash;
}
