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

#endif /* _ASM_SUBLEQ_STRING_H */
