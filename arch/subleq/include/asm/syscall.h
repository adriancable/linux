/* SPDX-License-Identifier: GPL-2.0 */
/*
 * System call definitions for Subleq
 */

#ifndef _ASM_SUBLEQ_SYSCALL_H
#define _ASM_SUBLEQ_SYSCALL_H

#include <asm/ptrace.h>

struct task_struct;

/*
 * Get syscall number from saved registers.
 *
 * NOTE: pt_regs values are stored NEGATED. Must use PT_REG_GET macros.
 * The syscall number is stored in the dedicated syscall_nr field,
 * NOT in r20 (which is the return value register).
 */
static inline int syscall_get_nr(struct task_struct *task, struct pt_regs *regs)
{
	return PT_REG_GET_SIGNED(regs, syscall_nr);
}

/* Get syscall return value (in R20) */
static inline long syscall_get_return_value(struct task_struct *task,
					    struct pt_regs *regs)
{
	return PT_REG_GET_SIGNED(regs, r20);
}

/* Get architecture for seccomp/audit - return 0 for generic/unknown */
static inline int syscall_get_arch(struct task_struct *task)
{
	return 0;
}

#endif /* _ASM_SUBLEQ_SYSCALL_H */
