/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Current task pointer for Subleq
 */

#ifndef _ASM_SUBLEQ_CURRENT_H
#define _ASM_SUBLEQ_CURRENT_H

#include <linux/thread_info.h>

/*
 * Get current task
 *
 * We derive the current task from the stack pointer instead of using a
 * global variable. This is immune to compiler caching across context
 * switches, fixing elusive Heisenbugs where 'current' points to the wrong
 * task.
 */
#define get_current() (current_thread_info()->task)

#define current get_current()

#endif /* _ASM_SUBLEQ_CURRENT_H */
