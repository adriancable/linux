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
extern void *memset(void *s, int c, __kernel_size_t n);

#define __HAVE_ARCH_MEMCPY
extern void *memcpy(void *dest, const void *src, __kernel_size_t n);

#define __HAVE_ARCH_MEMMOVE
extern void *memmove(void *dest, const void *src, __kernel_size_t n);

#endif /* _ASM_SUBLEQ_STRING_H */
