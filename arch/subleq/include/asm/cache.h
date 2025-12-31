/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Cache definitions for Subleq
 *
 * Subleq has no hardware cache.
 */

#ifndef _ASM_SUBLEQ_CACHE_H
#define _ASM_SUBLEQ_CACHE_H

/* Arbitrary cache line size for alignment purposes */
#define L1_CACHE_SHIFT 5
#define L1_CACHE_BYTES (1 << L1_CACHE_SHIFT)

/* SMP cache bytes - same as L1 */
#define SMP_CACHE_BYTES L1_CACHE_BYTES

/* No hardware cache, so these are all NOPs */
#define cache_line_size() L1_CACHE_BYTES

#endif /* _ASM_SUBLEQ_CACHE_H */
