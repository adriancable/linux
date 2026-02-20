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
 * switch_to - context switch macro
 *
 * Note: subleq_kernel_sp is updated by __switch_to in entry.S (STEP 4b),
 * so we don't need to call subleq_init_kernel_sp() here.
 */
#define switch_to(prev, next, last)                   \
	do {                                          \
		(last) = __switch_to((prev), (next)); \
	} while (0)

#endif /* _ASM_SUBLEQ_SWITCH_TO_H */

