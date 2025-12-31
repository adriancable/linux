/* SPDX-License-Identifier: GPL-2.0 */
/*
 * User access for Subleq
 *
 * NOMMU - no user/kernel separation, so access is trivial.
 */

#ifndef _ASM_SUBLEQ_UACCESS_H
#define _ASM_SUBLEQ_UACCESS_H

#include <linux/string.h>

/*
 * NOMMU: User and kernel share the same address space.
 */

typedef struct {
	unsigned long seg;
} mm_segment_t;

#define KERNEL_DS ((mm_segment_t){ 0 })
#define USER_DS ((mm_segment_t){ 0 })

/* Access OK - always true in NOMMU */
#define access_ok(addr, size) (1)

static inline bool __access_ok(const void __user *ptr, unsigned long size)
{
	return true;
}

/*
 * Raw copy functions - the kernel's linux/uaccess.h will wrap these
 */
static inline __must_check unsigned long
raw_copy_from_user(void *to, const void __user *from, unsigned long n)
{
	memcpy(to, (const void __force *)from, n);
	return 0;
}

static inline __must_check unsigned long
raw_copy_to_user(void __user *to, const void *from, unsigned long n)
{
	memcpy((void __force *)to, from, n);
	return 0;
}

#define INLINE_COPY_FROM_USER
#define INLINE_COPY_TO_USER

/*
 * Simple put/get user - works for NOMMU
 */
#define __get_user(x, ptr)                                  \
	({                                                  \
		(x) = *(__typeof__(*(ptr)) __force *)(ptr); \
		0;                                          \
	})

#define __put_user(x, ptr)                                  \
	({                                                  \
		*(__typeof__(*(ptr)) __force *)(ptr) = (x); \
		0;                                          \
	})

#define get_user(x, ptr) __get_user(x, ptr)
#define put_user(x, ptr) __put_user(x, ptr)

/* String functions */
static inline long strnlen_user(const char __user *s, long n)
{
	return strnlen((const char __force *)s, n) + 1;
}

static inline long strncpy_from_user(char *dst, const char __user *src,
				     long count)
{
	const char *s = (const char __force *)src;
	long res = 0;
	while (count-- > 0 && *s) {
		*dst++ = *s++;
		res++;
	}
	*dst = '\0';
	return res;
}

/* Clear user memory */
static inline __must_check unsigned long __must_check
__clear_user(void __user *to, unsigned long n)
{
	memset((void __force *)to, 0, n);
	return 0;
}

static inline __must_check unsigned long clear_user(void __user *to,
						    unsigned long n)
{
	return __clear_user(to, n);
}

#endif /* _ASM_SUBLEQ_UACCESS_H */
