/* SPDX-License-Identifier: GPL-2.0 */
/*
 * String operations for Subleq
 *
 * We provide our own implementations in subleq_runtime.S
 */

#ifndef _ASM_SUBLEQ_STRING_H
#define _ASM_SUBLEQ_STRING_H

/* 
 * Tell the kernel we have our own implementations of these functions
 * They are provided by the Subleq runtime library (subleq_runtime.S)
 */
#define __HAVE_ARCH_MEMSET
#define __HAVE_ARCH_MEMCPY
#define __HAVE_ARCH_MEMMOVE

/* Declarations for runtime functions */
extern void *__subleq_memcpy(void *dest, const void *src, size_t n);
extern void *__subleq_memset(void *dest, int c, size_t n);
extern void *__subleq_memmove(void *dest, const void *src, size_t n);

#ifndef memcpy
#define memcpy __subleq_memcpy
#endif
#ifndef memset
#define memset __subleq_memset
#endif
#ifndef memmove
#define memmove __subleq_memmove
#endif

/*
 * Optimized memset16/memset32: pack halfword stores into word stores.
 * These are provided by the Subleq runtime library (emit_memory_ops.py).
 *
 * On Subleq, halfword stores (__subleq_sh) cost ~80 steps each, while
 * word stores cost ~6 steps.  memset16 packs two u16 into one u32,
 * giving ~27x faster clears for fbcon_scroll's scr_memsetw path.
 */
#define __HAVE_ARCH_MEMSET16
#define __HAVE_ARCH_MEMSET32

extern void *__subleq_memset16(void *s, unsigned short v, size_t count);
extern void *__subleq_memset32(void *s, unsigned int v, size_t count);

#ifndef memset16
#define memset16(s, v, count) __subleq_memset16((s), (v), (count))
#endif
#ifndef memset32
#define memset32(s, v, count) __subleq_memset32((s), (v), (count))
#endif

#endif /* _ASM_SUBLEQ_STRING_H */
