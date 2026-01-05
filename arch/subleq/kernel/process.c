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
	/* Print 'I' once on first idle entry to confirm we reach idle */
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
 *
 * IMPORTANT: We must call schedule_tail(prev) first to finish the context
 * switch. The prev pointer is passed in R21 (first argument) by ret_from_fork.
 */
extern asmlinkage void schedule_tail(struct task_struct *prev);

void kernel_thread_helper(struct task_struct *prev)
{
	struct pt_regs *regs = task_pt_regs(current);
	int (*fn)(void *) = (int (*)(void *))regs->r3;
	void *arg = (void *)regs->r21;

	/*
	 * CRITICAL: Must call schedule_tail() first!
	 * This calls finish_task_switch(prev) which clears prev->on_cpu.
	 * Without this, try_to_wake_up() will spin forever waiting for
	 * on_cpu to become 0 when trying to wake up the previous task.
	 */
	schedule_tail(prev);

	/* Call the kernel thread function */
	fn(arg);

	/*
	 * The kernel thread function has returned. There are two cases:
	 *
	 * 1. Normal kernel thread completion: The thread did its work and is done.
	 *    In this case, we should call do_exit(0).
	 *
	 * 2. kernel_execve() was called: The thread called kernel_execve() to
	 *    transform into a user process (e.g., init). In this case, start_thread()
	 *    was called which set regs->r3 = 0 (user thread marker), and we should
	 *    NOT call do_exit(). Instead, we should return to userspace by setting
	 *    SP and jumping to PC.
	 *
	 * We check regs->r3: if it's 0, this is now a user thread and we should
	 * transition to userspace. Otherwise, it's a completed kernel thread.
	 */
	regs = task_pt_regs(current); /* Re-read in case it changed */

	if (regs->r3 == 0) {
		/*
		 * This thread called kernel_execve() and is now a user thread.
		 * Jump to userspace using an assembly helper that does a RAW jump
		 * without pushing a return address (which would corrupt the user stack).
		 */
		pr_info("kernel_thread_helper: transitioning to userspace pc=0x%lx sp=0x%lx\n",
			regs->pc, regs->sp);

		/*
		 * Call the assembly helper which will:
		 * 1. Set SP to regs->sp
		 * 2. Jump to regs->pc WITHOUT pushing a return address
		 *
		 * We pass pc in R21 (first arg) and sp in R22 (second arg).
		 */
		extern void __noreturn jump_to_userspace(unsigned long pc,
							 unsigned long sp);
		jump_to_userspace(regs->pc, regs->sp);
	}

	/* Normal kernel thread completion - call do_exit */
	do_exit(0);
}

/*
 * ret_to_user_prep - Prepare for return to userspace (called from ret_from_fork in asm)
 *
 * This is called when a user thread is scheduled for the first time after
 * fork or execve. It calls schedule_tail to complete the context switch,
 * then stores pc and sp in R20/R21 for the assembly code to use.
 *
 * Arguments:
 *   prev (R21) - previous task pointer (for schedule_tail)
 *
 * On return:
 *   R20 (memory location 96) = pc (userspace entry point)
 *   R21 (memory location 100) = sp (userspace stack pointer)
 *
 * In Subleq, "registers" are just fixed memory locations, so we write directly
 * to addresses 96 (R20) and 100 (R21).
 */
void ret_to_user_prep(struct task_struct *prev)
{
	struct pt_regs *regs = task_pt_regs(current);
	volatile unsigned long *r20 = (volatile unsigned long *)96;
	volatile unsigned long *r21 = (volatile unsigned long *)100;

	/*
	 * CRITICAL: Must call schedule_tail() first!
	 * This calls finish_task_switch(prev) which clears prev->on_cpu.
	 */
	schedule_tail(prev);

	/*
	 * Store user pc and sp directly into the Subleq register memory locations.
	 * After this function returns, the assembly code in ret_from_fork
	 * will read R20 (pc) and R21 (sp), set the stack pointer, and jump to pc.
	 */
	*r20 = regs->pc;
	*r21 = regs->sp;
}

/*
 * Start a new thread (called after execve)
 *
 * This is called by the binary format handlers (e.g., binfmt_flat) after
 * loading a new executable. It sets up the registers for the new program.
 *
 * IMPORTANT: We must set r3 = 0 to mark this as a user thread!
 * When a kernel thread calls kernel_execve(), the old kernel thread had
 * r3 = fn (non-zero). We need to clear it so ret_from_fork knows this is
 * now a user thread that should return to userspace.
 */
void start_thread(struct pt_regs *regs, unsigned long pc, unsigned long sp)
{
	/* Clear all registers to start with a clean slate */
	memset(regs, 0, sizeof(*regs));

	regs->pc = pc;
	regs->sp = sp;
	/* r3 = 0 is already set by memset, marking this as a user thread */
}

/*
 * Copy thread state for fork/clone
 *
 * For kernel threads, we set up the stack so that when __switch_to
 * switches to this thread for the first time:
 *   1. It pops the "return address" which is ret_from_fork
 *   2. ret_from_fork checks r3: if non-zero, it's a kernel thread
 *   3. For kernel threads: ret_from_fork calls kernel_thread_helper
 *      which reads pt_regs.r3 (the fn) and pt_regs.r21 (the arg)
 *   4. For user threads: ret_from_fork restores regs and jumps to pc
 *
 * r3 serves as the kernel/user thread flag:
 *   - r3 != 0: kernel thread (r3 = thread function pointer)
 *   - r3 == 0: user thread (should return to userspace via pc)
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

		/*
		 * Store thread function in r3 (kernel thread marker)
		 * and arg in r21 for kernel_thread_helper.
		 * pc is set to 0 (unused for kernel threads since we call fn directly).
		 */
		childregs->r3 = (unsigned long)args->fn;
		childregs->r21 = (unsigned long)args->fn_arg;
		childregs->pc = 0;

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
	childregs->r3 = 0; /* Mark as user thread (ret_from_fork checks this) */

	/*
	 * For user forks, set up stack similarly.
	 * The return address should be ret_from_fork which will
	 * restore pt_regs and return to userspace.
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
