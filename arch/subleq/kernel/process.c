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
extern void __subleq_putchar(int c);
static int idle_count = 0;

void __cpuidle arch_cpu_idle(void)
{
	/* Print 'I' once on first idle entry to confirm we reach idle */
	if (idle_count == 0) {
		__subleq_putchar('I');
		idle_count = 1;
	}
	raw_local_irq_enable();
	/* Busy wait - Subleq has no halt instruction */
}

/*
 * __switch_to is now implemented in entry.S
 * It's declared in switch_to.h
 */

/*
 * ret_from_fork is in entry.S - it's the return address for new threads
 */
extern void ret_from_fork(void);

/*
 * kernel_thread_helper - Called by ret_from_fork for new kernel threads
 *
 * When a new kernel thread is first scheduled, __switch_to returns to
 * ret_from_fork, which then calls this function. The thread's function
 * pointer and argument were stored in the pt_regs by copy_thread.
 */
void kernel_thread_helper(void)
{
	struct pt_regs *regs = task_pt_regs(current);
	int (*fn)(void *) = (int (*)(void *))regs->pc;
	void *arg = (void *)regs->r21;

	__subleq_putchar('H'); /* Debug: Helper called */

	/* Debug: Is it kernel_init or kthreadd? */
	/* kernel_init is a static function, but kthreadd is extern */
	extern int kthreadd(void *unused);
	if (fn == (int (*)(void *))kthreadd) {
		__subleq_putchar('k'); /* It's kthreadd */
	}

	/* Call the kernel thread function */
	fn(arg);

	__subleq_putchar('h'); /* Debug: Thread function returned */

	/* Thread function returned - call do_exit */
	do_exit(0);
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
 * Copy thread state for fork/clone
 *
 * For kernel threads, we set up the stack so that when __switch_to
 * switches to this thread for the first time:
 *   1. It pops the "return address" which is ret_from_fork
 *   2. ret_from_fork calls kernel_thread_helper
 *   3. kernel_thread_helper reads pt_regs.pc (the fn) and pt_regs.r21 (the arg)
 *   4. kernel_thread_helper calls fn(arg)
 */
int copy_thread(struct task_struct *p, const struct kernel_clone_args *args)
{
	unsigned long usp = args->stack;
	struct pt_regs *childregs;
	unsigned long *stack_ptr;

	childregs = task_pt_regs(p);

	if (unlikely(args->fn)) {
		/* Kernel thread */
		memset(childregs, 0, sizeof(struct pt_regs));

		/* Store thread function and arg in pt_regs for kernel_thread_helper */
		childregs->pc = (unsigned long)args->fn;
		childregs->r21 = (unsigned long)args->fn_arg;

		/*
		 * Set up the stack for __switch_to:
		 * The stack should have ret_from_fork as the "return address"
		 * that __switch_to will pop.
		 *
		 * Stack layout (growing down):
		 *   [high addr] childregs (pt_regs)
		 *   [low addr]  ret_from_fork address <-- thread.sp points here
		 */
		stack_ptr = (unsigned long *)childregs;
		stack_ptr--; /* Make room for return address */
		*stack_ptr = (unsigned long)ret_from_fork;

		p->thread.sp = (unsigned long)stack_ptr;

		return 0;
	}

	/* User thread (fork) - copy parent's regs */
	*childregs = *task_pt_regs(current);
	if (usp)
		childregs->sp = usp;
	childregs->r20 = 0; /* Return 0 in child */

	/*
	 * For user forks, set up stack similarly.
	 * The return address should be ret_from_fork which will
	 * eventually return to userspace.
	 */
	stack_ptr = (unsigned long *)childregs;
	stack_ptr--;
	*stack_ptr = (unsigned long)ret_from_fork;

	p->thread.sp = (unsigned long)stack_ptr;

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
