/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Compiler-specific definitions for Subleq
 *
 * Subleq doesn't support inline asm with GCC register constraints,
 * so we override macros that would use them.
 */

#ifndef _ASM_SUBLEQ_COMPILER_H
#define _ASM_SUBLEQ_COMPILER_H

/*
 * barrier_data - force the compiler to keep a variable in memory
 *
 * The generic definition uses inline asm with register constraints which
 * Subleq doesn't support. Use a plain compiler barrier instead.
 * This is sufficient since Subleq is single-threaded with no speculation.
 */
#define barrier_data(ptr) barrier()

/*
 * OPTIMIZER_HIDE_VAR - prevent the compiler from optimizing a variable
 *
 * Again, the generic version uses inline asm with register constraints.
 */
#define OPTIMIZER_HIDE_VAR(var) barrier()

#endif /* _ASM_SUBLEQ_COMPILER_H */
