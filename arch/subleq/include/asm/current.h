/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Current task pointer for Subleq
 */

#ifndef _ASM_SUBLEQ_CURRENT_H
#define _ASM_SUBLEQ_CURRENT_H

#include <linux/thread_info.h>

struct task_struct;

/*
 * Get current task - stored in a global variable (no per-CPU for uniprocessor)
 */
extern struct task_struct *subleq_current_task;

static inline struct task_struct *get_current(void)
{
	return subleq_current_task;
}

#define current get_current()

#endif /* _ASM_SUBLEQ_CURRENT_H */
