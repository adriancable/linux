/* SPDX-License-Identifier: GPL-2.0 */
/*
 * System call definitions for Subleq
 */

#ifndef _ASM_SUBLEQ_SYSCALL_H
#define _ASM_SUBLEQ_SYSCALL_H

struct task_struct;
struct pt_regs;

/* Get syscall number from saved registers */
static inline int syscall_get_nr(struct task_struct *task, struct pt_regs *regs)
{
	return regs->r20; /* Syscall number in R20 (first arg register) */
}

/* Get syscall return value */
static inline long syscall_get_return_value(struct task_struct *task,
					    struct pt_regs *regs)
{
	return regs->r20;
}

/* Get architecture for seccomp/audit - return 0 for generic/unknown */
static inline int syscall_get_arch(struct task_struct *task)
{
	return 0;
}

#endif /* _ASM_SUBLEQ_SYSCALL_H */
