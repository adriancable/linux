// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq syscall C handler - called from assembly trampoline
 *
 * The trampoline in entry.S handles:
 *   - Saving return address to a global (avoids userspace stack corruption)
 *   - Switching to kernel stack
 *   - Calling this function
 *   - Returning via the saved return address
 *
 * This function just dispatches to the appropriate syscall.
 */

#include <linux/syscalls.h>
#include <linux/errno.h>
#include <linux/sched.h>
#include <linux/sched/task_stack.h>
#include <asm/unistd.h>
#include <asm/ptrace.h>

/* Import the syscall table */
extern void *sys_call_table[];

/* Signal handling - for syscall restart */
extern void do_signal(struct pt_regs *regs);

/* Syscall function type */
typedef long (*syscall_fn_t)(long, long, long, long, long, long);

/* Forward declarations for functions called from assembly */
asmlinkage long __subleq_syscall_c(long nr, long a1, long a2, long a3, long a4, long a5, long a6);
void subleq_init_kernel_sp(struct task_struct *tsk);

/* sys_ni_syscall for unimplemented syscalls */
extern long sys_ni_syscall(void);

/*
 * Globals for saving userspace context - set by assembly trampoline.
 * These are defined in entry.S.
 */
extern unsigned long subleq_syscall_saved_sp;
extern unsigned long subleq_syscall_saved_fp;
extern unsigned long subleq_syscall_saved_ra;

/*
 * __subleq_syscall_c - C syscall handler
 *
 * Called from the assembly trampoline after stack has been switched
 * to the kernel stack. Returns to the trampoline which handles the
 * userspace return.
 */
asmlinkage long __subleq_syscall_c(long nr, long a1, long a2, long a3, long a4, long a5, long a6)
{
	syscall_fn_t fn;
	struct pt_regs *regs;
	long ret;

	/*
	 * pt_regs->pc, fp, sp, ra are now filled in by the assembly entry code
	 * (in __subleq_syscall) BEFORE calling us. This is critical to avoid
	 * a race condition: if we copied from globals here, an interrupt between
	 * the assembly saving to globals and us copying to pt_regs could allow
	 * another task to overwrite the globals, corrupting our return state.
	 *
	 * Assembly now saves directly to pt_regs atomically after switching
	 * to the kernel stack, eliminating this race window.
	 */
	regs = task_pt_regs(current);

	/*
	 * Save original syscall number and arguments for restart.
	 * This is critical for proper syscall restart support:
	 * - If the syscall is interrupted and needs restart, we need these
	 * - Future signal handling will use these to restart after handler
	 */
	regs->syscall_nr = nr;
	regs->orig_r21 = nr;  /* R21 = syscall number */
	regs->orig_r22 = a2;
	regs->orig_r23 = a3;
	regs->orig_r24 = a4;

	/* Dispatch the syscall */
	if (nr < 0 || nr >= __NR_syscalls) {
		pr_warn("SUBLEQ_SYSCALL: nr=%ld out of range (max=%d)\n",
			nr, __NR_syscalls);
		ret = -ENOSYS;
		regs->r20 = ret;  /* MUST set r20 before goto out */
		goto out;
	}

	fn = (syscall_fn_t)sys_call_table[nr];
	if (!fn || sys_call_table[nr] == (void *)sys_ni_syscall) {
		pr_warn("SUBLEQ_SYSCALL: syscall %ld not implemented\n", nr);
		ret = -ENOSYS;
		regs->r20 = ret;  /* MUST set r20 before goto out */
		goto out;
	}

	/*
	 * Syscall execution with restart loop.
	 *
	 * Some syscalls (like wait_for_vfork_done) return -ERESTARTNOINTR
	 * when interrupted. The kernel expects the architecture to
	 * automatically restart these syscalls.
	 *
	 * We implement restart by looping here. This is architecturally
	 * correct because:
	 * 1. We're still in the kernel, so context is preserved
	 * 2. When signals are implemented, do_signal() will deliver them
	 *    first and only set up restart for those that need it
	 * 3. The loop breaks on success or non-restartable errors
	 *
	 * This matches the behavior of the "restart block" mechanism
	 * but without needing to modify PC (which is complex for Subleq).
	 */
	int restart_count = 0;

restart_syscall:
	ret = fn(a1, a2, a3, a4, a5, a6);

	/*
	 * Store return value in pt_regs for do_signal to potentially modify.
	 * do_signal handles:
	 * - Checking for pending signals
	 * - Converting restart codes based on signal state
	 * - Setting up for restart or converting to -EINTR
	 */
	regs->r20 = ret;

	/*
	 * Handle signal delivery and syscall restart.
	 * After do_signal returns:
	 * - If signal was delivered, regs->r20 may be -EINTR or unchanged
	 * - If restart is needed (no signal), regs->r20 will be set to
	 *   a special value or left as the restart code
	 */
	do_signal(regs);

	/*
	 * Check if we need to restart the syscall.
	 *
	 * do_signal() sets regs->r20 based on restart codes:
	 * - ERESTARTNOINTR: Always restart (used by vfork wait)
	 * - ERESTARTSYS: Restart if no signal or SA_RESTART (for future)
	 * - ERESTARTNOHAND: Restart if no signal pending
	 * - ERESTART_RESTARTBLOCK: Use restart_block (not yet supported)
	 *
	 * For now, if regs->r20 still contains a restart code after
	 * do_signal, we restart the syscall. When signal delivery is
	 * implemented, do_signal will convert to -EINTR when appropriate.
	 */
	ret = regs->r20;

	switch (ret) {
	case -ERESTARTNOINTR:
		/*
		 * Always restart - this is used by wait_for_vfork_done().
		 * The vfork parent must wait for the child to exec/exit,
		 * so interruption should be transparent.
		 *
		 * CRITICAL: We must call cond_resched() to give the child
		 * process a chance to run! Otherwise we spin here forever
		 * because the child (which needs to call exec/exit to wake
		 * us up) never gets scheduled.
		 */
		restart_count++;
		if (restart_count > 10000) {
			/* Too many restarts - something is wrong, bail out */
			pr_warn("SUBLEQ_SYSCALL: syscall %ld stuck in restart loop\n", nr);
			ret = -EINTR;
			regs->r20 = ret;
			break;
		}
		/*
		 * Yield to the scheduler before retrying.
		 * This is essential - without this, the vfork child
		 * never gets to run and complete, so the parent waits forever.
		 */
		cond_resched();
		goto restart_syscall;

	case -ERESTARTSYS:
	case -ERESTARTNOHAND:
		/*
		 * IMPORTANT: These restart codes REQUIRE proper signal handling!
		 *
		 * ERESTARTSYS means: "restart if SA_RESTART or no signal to deliver"
		 * ERESTARTNOHAND means: "restart if no signal handler"
		 *
		 * The problem is that the syscall returns these because TIF_SIGPENDING
		 * is set (e.g., by timer interrupt). Without proper signal delivery:
		 * - The "pending signal" is never cleared
		 * - The syscall immediately sees TIF_SIGPENDING again
		 * - Returns ERESTARTSYS again → infinite loop!
		 *
		 * The correct fix requires implementing signal delivery so that:
		 * 1. do_signal() checks for real pending signals
		 * 2. If none, clears TIF_SIGPENDING and restarts
		 * 3. If signal exists, delivers it (possibly with restart after)
		 *
		 * For now, convert to EINTR. This may cause some syscalls to
		 * fail that would otherwise restart, but it prevents hangs.
		 * When signal delivery is implemented, this can be changed.
		 */
		ret = -EINTR;
		regs->r20 = ret;
		break;

	case -ERESTART_RESTARTBLOCK:
		/*
		 * TODO: This requires calling the restart_block function
		 * instead of the original syscall. For now, convert to EINTR.
		 * This affects nanosleep/clock_nanosleep time remaining.
		 */
		ret = -EINTR;
		regs->r20 = ret;
		break;
	}

out:
	/* Mark that we're no longer in a syscall */
	regs->syscall_nr = -1;

	/* Return the final value */
	return regs->r20;
}


/*
 * subleq_init_kernel_sp - Initialize kernel stack pointer for a task
 *
 * Called during context switch to set up subleq_kernel_sp for the new task.
 * The assembly trampoline uses this to switch to the kernel stack.
 */
extern unsigned long subleq_kernel_sp;

void subleq_init_kernel_sp(struct task_struct *tsk)
{
	/*
	 * Reserve space for kernel C handler stack frames.
	 * 
	 * IMPORTANT: This margin must be large enough for the deepest kernel
	 * call chain. The do_signal() -> get_signal() path in particular
	 * allocates large structures (struct ksignal) and calls many nested
	 * functions. 256 bytes may have been too small so we increased to
	 * 1024.
	 */
	subleq_kernel_sp = (unsigned long)task_stack_page(tsk) + THREAD_SIZE 
			   - sizeof(struct pt_regs) - 1024;
}
