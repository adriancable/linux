/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Spinlock for Subleq
 *
 * Uniprocessor - spinlocks are NOPs (just disable interrupts).
 */

#ifndef _ASM_SUBLEQ_SPINLOCK_H
#define _ASM_SUBLEQ_SPINLOCK_H

/* Use generic ticket spinlock implementation */
#include <asm-generic/spinlock.h>

#endif /* _ASM_SUBLEQ_SPINLOCK_H */
