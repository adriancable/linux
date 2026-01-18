/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Memory barriers for Subleq
 *
 * Subleq is uniprocessor with in-order execution, so barriers are NOPs.
 */

#ifndef _ASM_SUBLEQ_BARRIER_H
#define _ASM_SUBLEQ_BARRIER_H

/* Compiler barrier only - no hardware reordering */
#define mb() barrier()
#define rmb() barrier()
#define wmb() barrier()

/* SMP barriers - same as regular since no SMP */
#define smp_mb() barrier()
#define smp_rmb() barrier()
#define smp_wmb() barrier()

/* Read/write barriers with ordering */
#define __smp_mb() barrier()
#define __smp_rmb() barrier()
#define __smp_wmb() barrier()

#include <asm-generic/barrier.h>

#endif /* _ASM_SUBLEQ_BARRIER_H */
