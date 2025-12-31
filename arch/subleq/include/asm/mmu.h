/* SPDX-License-Identifier: GPL-2.0 */
/*
 * MMU definitions for Subleq
 *
 * Subleq has no MMU - this file provides stubs for NOMMU mode.
 */

#ifndef _ASM_SUBLEQ_MMU_H
#define _ASM_SUBLEQ_MMU_H

/* NOMMU - no per-process memory context needed */
typedef struct {
	unsigned long end_brk;
} mm_context_t;

#endif /* _ASM_SUBLEQ_MMU_H */
