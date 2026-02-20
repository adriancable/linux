/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Current task pointer for Subleq
 *
 * With CONFIG_THREAD_INFO_IN_TASK, we use a simple global volatile
 * variable to track the current task. This is updated by __switch_to
 * in entry.S on every context switch.
 *
 * This replaces the old SP-masking approach (current_thread_info()->task)
 * which required an expensive __subleq_and (~200 instructions) on every
 * access. A direct memory load is ~3 instructions.
 */

#ifndef _ASM_SUBLEQ_CURRENT_H
#define _ASM_SUBLEQ_CURRENT_H

#ifndef __ASSEMBLY__

#include <linux/compiler.h>

struct task_struct;

extern struct task_struct *volatile __current_task;

#define current __current_task

#endif /* !__ASSEMBLY__ */

#endif /* _ASM_SUBLEQ_CURRENT_H */
