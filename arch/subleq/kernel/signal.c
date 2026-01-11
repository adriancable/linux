// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq signal handling
 *
 * Based on m68k/kernel/signal.c signal handling patterns for NOMMU.
 */

#include <linux/kernel.h>
#include <linux/signal.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/syscalls.h>
#include <linux/errno.h>
#include <linux/resume_user_mode.h>

#include <asm/ptrace.h>

/* Forward declarations */
void do_signal(struct pt_regs *regs);
asmlinkage long sys_rt_sigreturn(void);

/*
 * handle_restart - Handle syscall restart based on error code and signal state
 *
 * @regs: Current pt_regs
 * @ka:   Signal action (NULL if no signal to deliver)
 * @has_handler: True if a signal handler is about to be invoked
 *
 * This follows the m68k pattern for handling restart codes.
 */
static inline void
handle_restart(struct pt_regs *regs, struct k_sigaction *ka, int has_handler)
{
	switch (regs->r20) {
	case -ERESTARTNOHAND:
		/*
		 * ERESTARTNOHAND: Restart only if there's no handler.
		 * If we have a handler, convert to EINTR.
		 */
		if (!has_handler)
			goto do_restart;
		regs->r20 = -EINTR;
		break;

	case -ERESTART_RESTARTBLOCK:
		/*
		 * ERESTART_RESTARTBLOCK: Use the restart_block mechanism.
		 * TODO: Implement properly by changing syscall to __NR_restart_syscall.
		 * For now, convert to EINTR or restart if no handler.
		 */
		if (!has_handler)
			goto do_restart;
		regs->r20 = -EINTR;
		break;

	case -ERESTARTSYS:
		/*
		 * ERESTARTSYS: Restart unless there's a handler without SA_RESTART.
		 */
		if (has_handler && !(ka->sa.sa_flags & SA_RESTART)) {
			regs->r20 = -EINTR;
			break;
		}
		fallthrough;

	case -ERESTARTNOINTR:
		/*
		 * ERESTARTNOINTR: Always restart, regardless of signals.
		 * This is used by vfork's wait_for_vfork_done().
		 *
		 * To restart the syscall:
		 * 1. Restore original syscall number to R21 (from orig_r21)
		 * 2. Set R20 to 0 (will be replaced by syscall return)
		 *
		 * The syscall will be re-invoked when we call the syscall
		 * function again. Since we're still in the kernel, the
		 * restart happens when the caller (syscall_entry.c) sees
		 * that we set up for restart.
		 */
	do_restart:
		regs->r21 = regs->orig_r21;
		/* Signal to syscall_entry.c that restart should happen */
		regs->r20 = -ERESTARTNOINTR;  /* Keep the restart code */
		break;
	}
}

/*
 * do_signal - Handle signal delivery and syscall restart
 *
 * This is called from the syscall return path. It:
 * 1. Checks for pending signals using get_signal()
 * 2. If a signal is pending, handles restart and delivers the signal
 * 3. If no signal, handles restart for interrupted syscalls
 *
 * Following the m68k pattern for proper NOMMU signal handling.
 */
void do_signal(struct pt_regs *regs)
{
	struct ksignal ksig;
	int got_sig;

	/*
	 * Check if there's a signal to deliver.
	 * get_signal() returns true if a signal needs to be delivered.
	 * It also handles signal stopping, coredumps, and sets up ksig.
	 */
	got_sig = get_signal(&ksig);

	if (got_sig) {
		/*
		 * A signal wants to be delivered.
		 *
		 * If we came from a syscall, handle restart codes first.
		 * Then set up the signal frame to execute the handler.
		 */
		if (in_syscall(regs))
			handle_restart(regs, &ksig.ka, 1);

		/*
		 * TODO: Actually deliver the signal by setting up a signal frame.
		 *
		 * For now, we don't have signal frame setup implemented.
		 * The signal will be "delivered" by just returning.
		 * This means signal handlers won't actually run, but at least
		 * the restart codes are handled correctly.
		 *
		 * To properly implement:
		 * - setup_rt_frame(&ksig, sigmask_to_save(), regs);
		 * - signal_setup_done(err, &ksig, 0);
		 */
		return;
	}

	/*
	 * No signal to deliver.
	 *
	 * If we came from a syscall and got a restart code, handle it.
	 * With no signal handler, ERESTARTSYS and ERESTARTNOHAND should
	 * both result in syscall restart.
	 */
	if (in_syscall(regs))
		handle_restart(regs, NULL, 0);

	/*
	 * If there's no signal to deliver, restore the saved sigmask.
	 * This is used by sigsuspend() and related calls.
	 */
	restore_saved_sigmask();
}

asmlinkage long sys_rt_sigreturn(void)
{
	/*
	 * TODO: Implement sigreturn
	 *
	 * This should:
	 * 1. Restore saved registers from signal frame on user stack
	 * 2. Restore signal mask
	 * 3. Mark that syscall restart should NOT happen (regs->syscall_nr = -1)
	 * 4. Return to the interrupted code
	 */
	return -ENOSYS;
}
