/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Processor definitions for Subleq architecture
 */

#ifndef _ASM_SUBLEQ_PROCESSOR_H
#define _ASM_SUBLEQ_PROCESSOR_H

#ifndef __ASSEMBLY__

#include <asm/ptrace.h>

/* Task size - 1GB total address space, kernel takes some */
#define TASK_SIZE (0x30000000UL) /* 768MB for user */

/* Where to search for free VM space during mmap */
#define TASK_UNMAPPED_BASE (TASK_SIZE / 3)

/*
 * Thread state structure - minimal for Subleq
 * Only need to save stack pointer for context switch
 */
struct thread_struct {
	unsigned long sp; /* Saved stack pointer */
};

#define INIT_THREAD      \
	{                \
		.sp = 0, \
	}

/*
 * cpu_relax - hint to the processor that we're spinning
 * Subleq has no yield instruction, so this is a no-op
 */
#define cpu_relax() barrier()

/*
 * Get saved registers from a stopped task
 */
#define task_pt_regs(task) \
	((struct pt_regs *)(task_stack_page(task) + THREAD_SIZE) - 1)

/*
 * Saved instruction pointer and stack pointer
 */
#define KSTK_EIP(tsk) (task_pt_regs(tsk)->pc)
#define KSTK_ESP(tsk) (task_pt_regs(tsk)->sp)

/*
 * Get wait channel for sleeping task
 */
extern unsigned long __get_wchan(struct task_struct *p);

/*
 * Start a new thread at given entry point with given stack
 */
extern void start_thread(struct pt_regs *regs, unsigned long pc,
			 unsigned long sp);

/* Default I/O bitmap */
#define INIT_THREAD_FLAGS 0

#endif /* !__ASSEMBLY__ */

#endif /* _ASM_SUBLEQ_PROCESSOR_H */
