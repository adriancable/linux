/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Compare and exchange for Subleq
 *
 * Uniprocessor - disable interrupts for atomic operations.
 */

#ifndef _ASM_SUBLEQ_CMPXCHG_H
#define _ASM_SUBLEQ_CMPXCHG_H

#include <linux/types.h>
#include <asm/irqflags.h>

/*
 * Atomic exchange - disable interrupts to ensure atomicity
 */
static inline unsigned long __xchg(unsigned long x, volatile void *ptr,
				   int size)
{
	unsigned long ret, flags;

	flags = arch_local_irq_save();

	switch (size) {
	case 1:
		ret = *(volatile u8 *)ptr;
		*(volatile u8 *)ptr = x;
		break;
	case 2:
		ret = *(volatile u16 *)ptr;
		*(volatile u16 *)ptr = x;
		break;
	case 4:
		ret = *(volatile u32 *)ptr;
		*(volatile u32 *)ptr = x;
		break;
	default:
		ret = 0;
		break;
	}

	arch_local_irq_restore(flags);
	return ret;
}

#define arch_xchg(ptr, x) \
	((__typeof__(*(ptr)))__xchg((unsigned long)(x), (ptr), sizeof(*(ptr))))

/*
 * Compare and exchange
 */
static inline unsigned long __cmpxchg(volatile void *ptr, unsigned long old,
				      unsigned long new, int size)
{
	unsigned long prev, flags;

	flags = arch_local_irq_save();

	switch (size) {
	case 1:
		prev = *(volatile u8 *)ptr;
		if (prev == old)
			*(volatile u8 *)ptr = new;
		break;
	case 2:
		prev = *(volatile u16 *)ptr;
		if (prev == old)
			*(volatile u16 *)ptr = new;
		break;
	case 4:
		prev = *(volatile u32 *)ptr;
		if (prev == old)
			*(volatile u32 *)ptr = new;
		break;
	default:
		prev = 0;
		break;
	}

	arch_local_irq_restore(flags);
	return prev;
}

#define arch_cmpxchg(ptr, o, n)                                   \
	((__typeof__(*(ptr)))__cmpxchg((ptr), (unsigned long)(o), \
				       (unsigned long)(n), sizeof(*(ptr))))

#define arch_cmpxchg_local(ptr, o, n) arch_cmpxchg((ptr), (o), (n))

/* Don't include asm-generic/cmpxchg.h - we provide our own complete implementation */

#endif /* _ASM_SUBLEQ_CMPXCHG_H */
