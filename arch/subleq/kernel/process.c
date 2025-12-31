// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq process management
 */

#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/sched/task.h>
#include <linux/sched/task_stack.h>
#include <linux/ptrace.h>

#include <asm/processor.h>
#include <asm/ptrace.h>
#include <asm/current.h>

/*
 * The idle thread - just spin
 */
void __cpuidle arch_cpu_idle(void)
{
	raw_local_irq_enable();
	/* Busy wait - Subleq has no halt instruction */
}

/*
 * Context switch implementation
 */
asmlinkage struct task_struct *__switch_to(struct task_struct *prev,
					   struct task_struct *next)
{
	struct thread_struct *prev_thread = &prev->thread;

	/* Save previous stack pointer */
	/* TODO: Get actual SP from memory location */
	prev_thread->sp = 0;

	/* Update current task pointer */
	subleq_current_task = next;

	/* Restore next stack pointer */
	/* TODO: Set SP from next->thread.sp */

	return prev;
}

/*
 * Start a new thread
 */
void start_thread(struct pt_regs *regs, unsigned long pc, unsigned long sp)
{
	regs->pc = pc;
	regs->sp = sp;
}

/*
 * Copy thread state for fork
 */
int copy_thread(struct task_struct *p, const struct kernel_clone_args *args)
{
	unsigned long usp = args->stack;
	struct pt_regs *childregs;

	childregs = task_pt_regs(p);

	if (unlikely(args->fn)) {
		/* Kernel thread */
		memset(childregs, 0, sizeof(struct pt_regs));
		childregs->pc = (unsigned long)args->fn;
		childregs->r21 = (unsigned long)args->fn_arg;
		p->thread.sp = (unsigned long)childregs;
		return 0;
	}

	*childregs = *task_pt_regs(current);
	if (usp)
		childregs->sp = usp;
	childregs->r20 = 0; /* Return 0 in child */

	p->thread.sp = (unsigned long)childregs;

	return 0;
}

/*
 * Get wait channel for sleeping task
 */
unsigned long __get_wchan(struct task_struct *p)
{
	return 0;
}

/*
 * Flush thread state
 */
void flush_thread(void)
{
}

/*
 * Machine power management - required by kernel/reboot.c
 */
void machine_halt(void)
{
	/* Use Subleq HALT instruction: subleq(-4, 0, -4) */
	while (1)
		;
}

void machine_power_off(void)
{
	machine_halt();
}

void machine_restart(char *cmd)
{
	machine_halt();
}
