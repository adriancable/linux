/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Thread info for Subleq architecture
 */

#ifndef _ASM_SUBLEQ_THREAD_INFO_H
#define _ASM_SUBLEQ_THREAD_INFO_H

#ifdef __KERNEL__

#include <asm/page.h>

/* Thread stack size - 8KB (two pages) for sufficient stack space */
#define THREAD_SHIFT (PAGE_SHIFT + 1)
#define THREAD_SIZE (PAGE_SIZE * 2)
#define THREAD_SIZE_ORDER 1

#ifndef __ASSEMBLY__

#include <linux/types.h>

/*
 * Low level thread information structure
 * Located at the bottom of the kernel stack
 */
struct task_struct; /* forward declaration */

struct thread_info {
	unsigned long flags; /* thread flags */
	int preempt_count; /* preemption counter */
	__u32 cpu; /* current CPU */
	struct task_struct *task; /* pointer to owning task */
};

#define INIT_THREAD_INFO(tsk)                        \
	{                                            \
		.flags = 0,                          \
		.preempt_count = INIT_PREEMPT_COUNT, \
		.cpu = 0,                            \
	}

/*
 * Get current thread info - stored at bottom of kernel stack.
 * We use the stack pointer to find it by masking off the stack offset.
 * The stack pointer is stored at memory location 16 (word 4) in Subleq.
 */
static inline struct thread_info *current_thread_info(void)
{
	/* Read stack pointer from the well-known location */
	unsigned long sp = *(volatile unsigned long *)16;
	return (struct thread_info *)(sp & ~(THREAD_SIZE - 1));
}

#endif /* !__ASSEMBLY__ */

/*
 * Thread information flags
 */
#define TIF_SYSCALL_TRACE 0 /* syscall trace active */
#define TIF_NOTIFY_RESUME 1 /* callback before returning to user */
#define TIF_SIGPENDING 2 /* signal pending */
#define TIF_NEED_RESCHED 3 /* rescheduling necessary */
#define TIF_SINGLESTEP 4 /* single stepping */
#define TIF_NOTIFY_SIGNAL 5 /* signal notifications exist */
#define TIF_MEMDIE 17 /* OOM killer killed process */

#define _TIF_SYSCALL_TRACE (1 << TIF_SYSCALL_TRACE)
#define _TIF_NOTIFY_RESUME (1 << TIF_NOTIFY_RESUME)
#define _TIF_SIGPENDING (1 << TIF_SIGPENDING)
#define _TIF_NEED_RESCHED (1 << TIF_NEED_RESCHED)
#define _TIF_SINGLESTEP (1 << TIF_SINGLESTEP)
#define _TIF_NOTIFY_SIGNAL (1 << TIF_NOTIFY_SIGNAL)

/* Work to do on return from interrupt/exception */
#define _TIF_WORK_MASK (0x0000FFFF & ~_TIF_SYSCALL_TRACE)
#define _TIF_ALLWORK_MASK 0x0000FFFF

#endif /* __KERNEL__ */

#endif /* _ASM_SUBLEQ_THREAD_INFO_H */
