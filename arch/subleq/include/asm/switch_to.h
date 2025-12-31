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

#define switch_to(prev, next, last)                   \
	do {                                          \
		(last) = __switch_to((prev), (next)); \
	} while (0)

#endif /* _ASM_SUBLEQ_SWITCH_TO_H */
