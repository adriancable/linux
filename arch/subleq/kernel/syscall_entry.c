// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq syscall C handler — dispatches syscalls from the assembly trampoline.
 *
 * pt_regs values are stored NEGATED; all access uses PT_REG_GET/SET.
 * NOMMU — no generic entry infrastructure, no syscall tracing/seccomp.
 * Signal handling and syscall restart are fully implemented.
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
	 * pt_regs->pc/fp/sp/ra are filled in by the assembly entry code
	 * BEFORE calling us, avoiding a race where an interrupt could
	 * overwrite globals between save and copy.
	 */
	regs = task_pt_regs(current);

	/*
	 * Save original syscall number and all 6 arguments for restart.
	 * Signal handling needs these to restart syscalls after the handler.
	 */
	PT_REG_SET_SIGNED(regs, syscall_nr, nr);
	PT_REG_SET(regs, orig_r21, nr);  /* Syscall number (for lookup) */
	PT_REG_SET(regs, orig_a1, a1);   /* First arg to syscall function */
	PT_REG_SET(regs, orig_a2, a2);   /* Second arg */
	PT_REG_SET(regs, orig_a3, a3);   /* Third arg */
	PT_REG_SET(regs, orig_a4, a4);   /* Fourth arg */
	PT_REG_SET(regs, orig_a5, a5);   /* Fifth arg */
	PT_REG_SET(regs, orig_a6, a6);   /* Sixth arg */

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
	 * Restart loop: some syscalls (e.g., wait_for_vfork_done) return
	 * -ERESTARTNOINTR when interrupted. We loop here rather than
	 * modifying PC, which is complex on Subleq.
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
	 * If do_signal() set up a handler, return to userspace immediately.
	 * Restart (if SA_RESTART) happens when the handler returns via sigreturn.
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
	 * sys_rt_sigreturn sets syscall_nr to -1 to prevent restart.
	 * Without this check, a restored r20 with a restart code would
	 * incorrectly restart sigreturn with the wrong SP.
	 */
	if (!in_syscall(regs)) {
		/* Sigreturn completed - do not attempt restart */
		goto out;
	}

	switch (ret) {
	case -ERESTARTNOINTR:
		/*
		 * Always restart — used by wait_for_vfork_done().
		 * Must yield so the child gets to run and complete.
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
	 * ERESTARTSYS/ERESTARTNOHAND are handled by do_signal() ->
	 * handle_restart(), which converts them to ERESTARTNOINTR
	 * when no handler is present. They won't reach here.
	 */

	case -ERESTART_RESTARTBLOCK: {
		/*
		 * Call restart_block instead of the original syscall.
		 * Used by nanosleep/futex to handle remaining time.
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
	 * Check pending work before returning to userspace.
	 * Without this, a timer tick during syscall execution would not
	 * cause a reschedule until the next interrupt.
	 */
	if (need_resched())
		schedule();

	/*
	 * Re-check signals after schedule() - a higher-priority task may
	 * have sent us a signal, or schedule() itself may have set flags.
	 */
	if (test_thread_flag(TIF_SIGPENDING) ||
	    test_thread_flag(TIF_NOTIFY_SIGNAL))
		do_signal(regs);

	/*
	 * Drain task_work (TIF_NOTIFY_RESUME). Without this, deferred
	 * fput() calls leak f_cred references indefinitely.
	 */
	if (test_thread_flag(TIF_NOTIFY_RESUME))
		resume_user_mode_work(regs);

	/* Return the final value */
	return PT_REG_GET_SIGNED(regs, r20);
}


/*
 * Set subleq_kernel_sp for a task. The assembly trampoline uses this
 * to switch to the kernel stack. Must leave enough headroom for the
 * deepest kernel call chain (do_signal path needs ~1KB).
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
	 * functions, requiring at least 1024 bytes of stack headroom.
	 */
	subleq_kernel_sp = (unsigned long)task_stack_page(tsk) + THREAD_SIZE 
			   - sizeof(struct pt_regs) - 1024;
}
