/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Context switch for Subleq
 */

#ifndef _ASM_SUBLEQ_SWITCH_TO_H
#define _ASM_SUBLEQ_SWITCH_TO_H

struct task_struct;
struct thread_struct;

extern struct task_struct *__switch_to(struct task_struct *prev,
				       struct task_struct *next);

/*
 * Initialize the kernel stack pointer for syscall entry.
 * Called before switching to set up subleq_kernel_sp for the new task.
 */
extern void subleq_init_kernel_sp(struct task_struct *tsk);

#define switch_to(prev, next, last)                   \
	do {                                          \
		subleq_init_kernel_sp(next);          \
		(last) = __switch_to((prev), (next)); \
	} while (0)

#endif /* _ASM_SUBLEQ_SWITCH_TO_H */

