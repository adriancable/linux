// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq process management
 */

#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/sched/task.h>
#include <linux/sched/task_stack.h>
#include <linux/ptrace.h>
#include <linux/cpu.h>

#include <asm/processor.h>
#include <asm/ptrace.h>
#include <asm/current.h>
#include <asm/switch_context.h>

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

	/* Debug traces commented out
	pr_info("kernel_thread_helper: entry, PID=%d current=%p prev=%p\n",
		task_tgid_vnr(current), current, prev);
	*/

	/*
	 * CRITICAL: Must call schedule_tail() first!
	 * This calls finish_task_switch(prev) which clears prev->on_cpu.
	 * Without this, try_to_wake_up() will spin forever waiting for
	 * on_cpu to become 0 when trying to wake up the previous task.
	 */
	schedule_tail(prev);

	/* Debug traces commented out
	pr_info("kernel_thread_helper: after schedule_tail, PID=%d current=%p\n",
		task_tgid_vnr(current), current);
	*/

	/* Call the kernel thread function */
	fn(arg);

	/* Debug traces commented out
	pr_info("kernel_thread_helper: after fn(), PID=%d current=%p\n",
		task_tgid_vnr(current), current); */

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
		/* Debug trace commented out
		pr_info("kernel_thread_helper: transitioning to userspace PID=%d pc=0x%lx sp=0x%lx\n",
			task_tgid_vnr(current), regs->pc, regs->sp);
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
		jump_to_userspace(regs->pc, regs->sp);
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
 */
void start_thread(struct pt_regs *regs, unsigned long pc, unsigned long sp)
{
	/* Clear all registers to start with a clean slate */
	memset(regs, 0, sizeof(*regs));

	regs->pc = pc;
	regs->sp = sp;
	/* r3 = 0 is already set by memset, marking this as a user thread */
	
	/*
	 * CRITICAL: Mark that we're NOT in a syscall.
	 * Hazard 1342: memset sets syscall_nr=0, which makes in_syscall()
	 * return true (syscall 0 = read). do_signal() would then incorrectly
	 * try to handle syscall restart, corrupting the return context.
	 */
	regs->syscall_nr = -1;
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
 */
int copy_thread(struct task_struct *p, const struct kernel_clone_args *args)
{
	unsigned long usp = args->stack;
	struct pt_regs *childregs;
	struct switch_stack *childstack;
	unsigned long *retpc_slot;

	/* Debug traces commented out
	pr_info("COPY_THREAD: parent=%px parent->stack=%px, child=%px child->stack=%px\n",
		current, current->stack, p, p->stack);
	pr_info("COPY_THREAD: parent stack range [%px - %px], child stack range [%px - %px]\n",
		current->stack, (void *)((unsigned long)current->stack + THREAD_SIZE),
		p->stack, (void *)((unsigned long)p->stack + THREAD_SIZE));
	*/

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
		memset(childregs, 0, sizeof(struct pt_regs));

		/*
		 * Store thread function in r3 (kernel thread marker)
		 * and arg in r21 for kernel_thread_helper.
		 * pc is set to 0 (unused for kernel threads since we call fn directly).
		 */
		childregs->r3 = (unsigned long)args->fn;
		childregs->r21 = (unsigned long)args->fn_arg;
		childregs->pc = 0;
		/* Mark not in syscall (Hazard 1342) */
		childregs->syscall_nr = -1;

		return 0;
	}

	/* User thread (fork) - copy parent's regs */
	*childregs = *task_pt_regs(current);
	if (usp)
		childregs->sp = usp;
	childregs->r20 = 0; /* Return 0 in child */
	childregs->r3 = 0; /* Mark as user thread (ret_from_fork checks this) */
	/*
	 * Mark not in syscall for the child.
	 * Even though the parent is in clone/fork syscall, the child is
	 * starting fresh and should not inherit the syscall restart state.
	 * Hazard 1342: without this, in_syscall() returns true and
	 * do_signal() corrupts the return context.
	 */
	childregs->syscall_nr = -1;

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
