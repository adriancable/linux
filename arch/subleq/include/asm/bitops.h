/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Bitops for Subleq
 *
 * Use generic implementations - Subleq doesn't have native bit instructions.
 */

#ifndef _ASM_SUBLEQ_BITOPS_H
#define _ASM_SUBLEQ_BITOPS_H

#ifndef _LINUX_BITOPS_H
#error only <linux/bitops.h> can be included directly
#endif

#include <asm/barrier.h>

/* Use non-atomic generic implementations (uniprocessor, no SMP) */
#include <asm-generic/bitops/non-atomic.h>

/* Atomic bit operations - lock-based for safety */
#include <asm-generic/bitops/atomic.h>

/* Lock operations */
#include <asm-generic/bitops/lock.h>

/* Find first set bit */
#include <asm-generic/bitops/ffs.h>
#include <asm-generic/bitops/__ffs.h>
#include <asm-generic/bitops/ffz.h>

/* Find last set bit */
#include <asm-generic/bitops/fls.h>
#include <asm-generic/bitops/__fls.h>
#include <asm-generic/bitops/fls64.h>

/* Count bits */
#include <asm-generic/bitops/hweight.h>

/* Byte swapping */
#include <asm-generic/bitops/le.h>

/* Scheduling word support */
#include <asm-generic/bitops/sched.h>

/* Extended bit operations */
#include <asm-generic/bitops/ext2-atomic.h>

#endif /* _ASM_SUBLEQ_BITOPS_H */
