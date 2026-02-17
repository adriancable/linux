// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq process management
 *
 * NOTE: pt_regs values are stored NEGATED. All access uses PT_REG_GET/SET macros.
 */

#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/sched/task.h>
#include <linux/sched/task_stack.h>
#include <linux/ptrace.h>
#include <linux/cpu.h>
#include <linux/resume_user_mode.h>

#include <asm/processor.h>
#include <asm/ptrace.h>
#include <asm/current.h>
#include <asm/switch_context.h>

/* Signal handling - for ret_to_user_prep work checks */
extern bool do_signal(struct pt_regs *regs);

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
extern char ret_from_fork[];

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
	int (*fn)(void *) = (int (*)(void *))PT_REG_GET(regs, r3);
	void *arg = (void *)PT_REG_GET(regs, r21);

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

	if (PT_REG_GET(regs, r3) == 0) {
		/*
		 * This thread called kernel_execve() and is now a user thread.
		 * Jump to userspace using an assembly helper that does a RAW jump
		 * without pushing a return address (which would corrupt the user stack).
		 */

		/*
		 * Call the assembly helper which will:
		 * 1. Set SP to regs->sp
		 * 2. Jump to regs->pc WITHOUT pushing a return address
		 *
		 * We pass pc in R21 (first arg) and sp in R22 (second arg).
		 */
		extern void __noreturn jump_to_userspace(unsigned long pc,
							 unsigned long sp);
		jump_to_userspace(PT_REG_GET(regs, pc), PT_REG_GET(regs, sp));
	}

	/* Normal kernel thread completion - call do_exit */
	do_exit(0);
}

/*
 * ret_to_user_prep - Prepare for return to userspace (called from ret_from_fork in asm)
 *
 * This is called when a user thread is scheduled for the first time after
 * fork or clone. It ONLY calls schedule_tail to complete the context switch.
 *
 * Arguments:
 *   prev (R21) - previous task pointer (for schedule_tail)
 *
 * Returns:
 *   R20 = pointer to current task's pt_regs
 *
 * IMPORTANT: The assembly code in ret_from_fork will read pc, sp, and r20
 * directly from pt_regs to set up the return to userspace. This ensures
 * no registers are clobbered by C code.
 */
struct pt_regs *ret_to_user_prep(struct task_struct *prev)
{
	struct pt_regs *regs;
	
	/*
	 * CRITICAL: Must call schedule_tail() first!
	 * This calls finish_task_switch(prev) which clears prev->on_cpu.
	 */
	schedule_tail(prev);

	/* Return pointer to pt_regs for assembly to use */
	regs = task_pt_regs(current);

	/*
	 * Process pending work before returning to userspace.
	 *
	 * Like ColdFire/nios2's ret_from_fork -> ret_from_exception path,
	 * we must check all TIF work flags. A signal sent to the child
	 * between fork() and first schedule would otherwise be delayed
	 * until the next interrupt.
	 */
	if (need_resched())
		schedule();

	if (test_thread_flag(TIF_SIGPENDING) ||
	    test_thread_flag(TIF_NOTIFY_SIGNAL))
		do_signal(regs);

	if (test_thread_flag(TIF_NOTIFY_RESUME))
		resume_user_mode_work(regs);

	return regs;
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
 *
 * NOTE: Since pt_regs stores values NEGATED, we use PT_REG_SET for all writes.
 * memset(0) works because -0 = 0.
 */
void start_thread(struct pt_regs *regs, unsigned long pc, unsigned long sp)
{
	/* Clear all registers to start with a clean slate */
	/* NOTE: memset(0) is correct even for negated storage since -0 = 0 */
	memset(regs, 0, sizeof(*regs));

	PT_REG_SET(regs, pc, pc);
	PT_REG_SET(regs, sp, sp);
	/* r3 = 0 is already set by memset, marking this as a user thread */
	
	/*
	 * CRITICAL: Mark that we're NOT in a syscall.
	 * Hazard 1342: memset sets syscall_nr=0, which makes in_syscall()
	 * return true (syscall 0 = read). do_signal() would then incorrectly
	 * try to handle syscall restart, corrupting the return context.
	 */
	syscall_wont_restart(regs);
}

/*
 * Copy thread state for fork/clone
 *
 * For kernel threads, we set up the stack so that when __switch_to
 * switches to this thread for the first time:
 *   1. It restores registers from switch_stack (initially zeroed)
 *   2. It pops the "return address" (retpc) which is ret_from_fork
 *   3. ret_from_fork checks r3: if non-zero, it's a kernel thread
 *   4. For kernel threads: ret_from_fork calls kernel_thread_helper
 *      which reads pt_regs.r3 (the fn) and pt_regs.r21 (the arg)
 *   5. For user threads: ret_from_fork restores regs and jumps to pc
 *
 * r3 serves as the kernel/user thread flag:
 *   - r3 != 0: kernel thread (r3 = thread function pointer)
 *   - r3 == 0: user thread (should return to userspace via pc)
 *
 * Stack layout (growing down):
 *   [high addr]  pt_regs structure
 *   [mid addr]   switch_stack structure  <-- thread.sp points here
 *   [low addr]   ... (more stack space)
 *
 * NOTE: Since pt_regs stores values NEGATED, we use PT_REG_SET for all writes.
 */
int copy_thread(struct task_struct *p, const struct kernel_clone_args *args)
{
	unsigned long usp = args->stack;
	struct pt_regs *childregs;
	struct switch_stack *childstack;
	unsigned long *retpc_slot;

	childregs = task_pt_regs(p);

	/*
	 * Set up stack for __switch_to:
	 *
	 * Stack layout (growing down):
	 *   [high addr]  pt_regs structure
	 *   [mid]        ret_from_fork (return address, 4 bytes)
	 *   [low]        switch_stack (96 bytes)  <-- thread.sp points here
	 *
	 * When __switch_to restores this task:
	 *   1. Restores registers from switch_stack
	 *   2. SP += 96 (now points to retpc slot)
	 *   3. Pops retpc, jumps to ret_from_fork
	 */

	/* First, push ret_from_fork as the "return address" */
	retpc_slot = (unsigned long *)childregs - 1;
	*retpc_slot = (unsigned long)ret_from_fork;

	/* Then allocate switch_stack below the return address */
	childstack = (struct switch_stack *)retpc_slot - 1;
	memset(childstack, 0, sizeof(struct switch_stack));

	/* thread.sp points to switch_stack */
	p->thread.sp = (unsigned long)childstack;

	if (unlikely(args->fn)) {
		/* Kernel thread */
		/* NOTE: memset(0) works for negated storage since -0 = 0 */
		memset(childregs, 0, sizeof(struct pt_regs));

		/*
		 * Store thread function in r3 (kernel thread marker)
		 * and arg in r21 for kernel_thread_helper.
		 * pc is set to 0 (unused for kernel threads since we call fn directly).
		 */
		PT_REG_SET(childregs, r3, (unsigned long)args->fn);
		PT_REG_SET(childregs, r21, (unsigned long)args->fn_arg);
		PT_REG_SET(childregs, pc, 0);
		/* Mark not in syscall (Hazard 1342) */
		syscall_wont_restart(childregs);

		return 0;
	}

	/* User thread (fork) - copy parent's regs */
	*childregs = *task_pt_regs(current);
	if (usp)
		PT_REG_SET(childregs, sp, usp);
	PT_REG_SET(childregs, r20, 0); /* Return 0 in child */
	/* Note: r3 is NOT cleared - we use pc==0 to detect kernel threads */
	/*
	 * Mark not in syscall for the child.
	 * Even though the parent is in clone/fork syscall, the child is
	 * starting fresh and should not inherit the syscall restart state.
	 * Hazard 1342: without this, in_syscall() returns true and
	 * do_signal() corrupts the return context.
	 */
	syscall_wont_restart(childregs);

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
