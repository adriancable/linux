/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Atomic operations for Subleq
 *
 * Subleq is uniprocessor with no SMP, so atomic operations are trivial.
 */

#ifndef _ASM_SUBLEQ_ATOMIC_H
#define _ASM_SUBLEQ_ATOMIC_H

#include <linux/types.h>
#include <asm/barrier.h>

/* Use generic atomic implementation for uniprocessor */
#include <asm-generic/atomic.h>

#endif /* _ASM_SUBLEQ_ATOMIC_H */
