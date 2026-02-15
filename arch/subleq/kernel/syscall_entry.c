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
 *
 * NOTE: pt_regs values are stored NEGATED. All access uses PT_REG_GET/SET macros.
 *
 * Architecture notes:
 * - This is a NOMMU architecture, so we don't use the full generic entry
 *   infrastructure (enter_from_user_mode/exit_to_user_mode/context_tracking).
 * - We don't support syscall tracing (strace), seccomp, or audit currently.
 * - Signal handling and syscall restart are fully implemented.
 */

#include <linux/syscalls.h>
#include <linux/errno.h>
#include <linux/sched.h>
#include <linux/sched/task_stack.h>
#include <linux/restart_block.h>
#include <asm/unistd.h>
#include <asm/ptrace.h>
#include <linux/resume_user_mode.h>

/* Import the syscall table */
extern void *sys_call_table[];

/* Signal handling - for syscall restart */
extern bool do_signal(struct pt_regs *regs);

/* Syscall function type */
typedef long (*syscall_fn_t)(long, long, long, long, long, long);

/* Forward declarations for functions called from assembly */
asmlinkage long __subleq_syscall_c(long nr, long a1, long a2, long a3, long a4, long a5, long a6);
void subleq_init_kernel_sp(struct task_struct *tsk);

/* sys_ni_syscall for unimplemented syscalls */
extern long sys_ni_syscall(void);

/* Debug output */


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
	 * - Signal handling uses these to restart syscalls after handler returns
	 *
	 * fn(a1, a2, a3, a4, a5, a6) - we save a1-a4 (register args)
	 * a5-a6 are on stack and will be restored from the signal frame's SP
	 */
	PT_REG_SET_SIGNED(regs, syscall_nr, nr);
	PT_REG_SET(regs, orig_r21, nr);  /* Syscall number (for lookup) */
	PT_REG_SET(regs, orig_a1, a1);   /* First arg to syscall function */
	PT_REG_SET(regs, orig_a2, a2);   /* Second arg */
	PT_REG_SET(regs, orig_a3, a3);   /* Third arg */
	PT_REG_SET(regs, orig_a4, a4);   /* Fourth arg */

	/* Dispatch the syscall */
	if (nr < 0 || nr >= __NR_syscalls) {
		pr_warn("SUBLEQ_SYSCALL: nr=%ld out of range (max=%d)\n",
			nr, __NR_syscalls);
		ret = -ENOSYS;
		PT_REG_SET_SIGNED(regs, r20, ret);
		goto out;
	}

	fn = (syscall_fn_t)sys_call_table[nr];
	if (!fn || sys_call_table[nr] == (void *)sys_ni_syscall) {
		pr_warn("SUBLEQ_SYSCALL: syscall %ld not implemented\n", nr);
		ret = -ENOSYS;
		PT_REG_SET_SIGNED(regs, r20, ret);
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
	PT_REG_SET_SIGNED(regs, r20, ret);

	/*
	 * Handle signal delivery and syscall restart.
	 *
	 * do_signal() returns true if a signal handler was set up.
	 * In that case, we must NOT perform the restart logic below -
	 * instead, we return to userspace to run the signal handler.
	 * The restart (if SA_RESTART) happens when the handler returns
	 * via sigreturn.
	 */
	if (do_signal(regs)) {
		/* Signal handler was set up - return to userspace */
		goto out;
	}

	/*
	 * No signal was delivered.
	 * Check if we need to restart the syscall.
	 */
	ret = PT_REG_GET_SIGNED(regs, r20);

	/*
	 * CRITICAL: sys_rt_sigreturn sets syscall_nr to -1 to indicate
	 * that the syscall has been handled and should NOT be restarted.
	 * If we don't check this, and the restored R20 happens to be a
	 * restart error code (like -ERESTARTNOINTR), we would incorrectly
	 * restart the sigreturn syscall with the wrong SP, causing a crash.
	 */
	if (!in_syscall(regs)) {
		/* Sigreturn completed - do not attempt restart */
		goto out;
	}

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
			PT_REG_SET_SIGNED(regs, r20, ret);
			break;
		}
		/*
		 * Yield to the scheduler before retrying.
		 * This is essential - without this, the vfork child
		 * never gets to run and complete, so the parent waits forever.
		 */
		cond_resched();
		goto restart_syscall;

	/*
	 * Note: ERESTARTSYS and ERESTARTNOHAND are NOT handled here.
	 * do_signal() -> handle_restart() converts these codes:
	 * - If a signal handler exists: may convert to EINTR or keep for SA_RESTART
	 * - If no handler: converts to ERESTARTNOINTR to trigger restart
	 * So by the time we reach this switch, these codes have already
	 * been transformed and will hit the ERESTARTNOINTR case above.
	 */

	case -ERESTART_RESTARTBLOCK: {
		/*
		 * ERESTART_RESTARTBLOCK requires calling the restart_block
		 * function instead of the original syscall. This is used by
		 * nanosleep/futex to handle remaining time correctly.
		 *
		 * Example: nanosleep(3s) interrupted after 1s by SIGALRM
		 * - nanosleep sets up restart_block with remaining 2s
		 * - Returns -ERESTART_RESTARTBLOCK
		 * - We call restart_block.fn() which sleeps the remaining 2s
		 * - Total sleep time = 3s as expected
		 */
		struct restart_block *restart = &current->restart_block;
		ret = restart->fn(restart);
		PT_REG_SET_SIGNED(regs, r20, ret);
		/*
		 * The restart function may have been interrupted again.
		 * Handle any pending signals first.
		 */
		if (do_signal(regs))
			goto out;
		ret = PT_REG_GET_SIGNED(regs, r20);
		/*
		 * If we got another restart code (e.g. ERESTARTNOINTR),
		 * we need to actually restart the original syscall.
		 * handle_restart() in signal.c converts ERESTARTSYS/ERESTARTNOHAND
		 * to ERESTARTNOINTR when there's no handler, so check for that.
		 */
		if (ret == -ERESTARTNOINTR)
			goto restart_syscall;
		/* For other restart codes or success, fall through to exit */
		break;
	}
	}

out:
	/* Mark that we're no longer in a syscall */
	syscall_wont_restart(regs);

	/*
	 * Process TIF_NOTIFY_RESUME task_work before returning to userspace.
	 *
	 * CRITICAL: fput() defers file close via task_work_add(), which sets
	 * TIF_NOTIFY_RESUME. Without draining these callbacks here, files
	 * opened during exec (e.g., the executable itself) are never properly
	 * closed, leaking their f_cred reference and causing struct cred to
	 * accumulate indefinitely.
	 *
	 * This matches what other architectures do in their syscall exit path
	 * via exit_to_user_mode_loop() -> resume_user_mode_work().
	 */
	if (test_thread_flag(TIF_NOTIFY_RESUME))
		resume_user_mode_work(regs);

	/* Return the final value */
	return PT_REG_GET_SIGNED(regs, r20);
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
