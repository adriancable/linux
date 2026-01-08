// SPDX-License-Identifier: GPL-2.0
/*
 * Memory operation wrappers for Subleq
 *
 * These wrap the __subleq_* runtime functions to provide the standard
 * memcpy/memset/memmove symbols that the kernel expects.
 * The __subleq_* versions are the actual implementations in subleq_runtime.S.
 */

#include <linux/types.h>
#include <linux/string.h>
#include <linux/export.h>

/* Declarations for runtime functions */
extern void *__subleq_memcpy(void *dest, const void *src, size_t n);
extern void *__subleq_memset(void *dest, int c, size_t n);
extern void *__subleq_memmove(void *dest, const void *src, size_t n);

void *memcpy(void *dest, const void *src, size_t n)
{
	return __subleq_memcpy(dest, src, n);
}
EXPORT_SYMBOL(memcpy);

void *memset(void *dest, int c, size_t n)
{
	return __subleq_memset(dest, c, n);
}
EXPORT_SYMBOL(memset);

void *memmove(void *dest, const void *src, size_t n)
{
	return __subleq_memmove(dest, src, n);
}
EXPORT_SYMBOL(memmove);
