// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq signal handling
 */

#include <linux/kernel.h>
#include <linux/signal.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/syscalls.h>
#include <linux/errno.h>

#include <asm/ptrace.h>

/* Forward declarations */
void do_signal(struct pt_regs *regs);
asmlinkage long sys_rt_sigreturn(void);

/*
 * Handle syscall restart and signal delivery
 *
 * This is called from the syscall return path when returning to userspace.
 * It handles:
 * 1. Syscall restart (ERESTARTSYS, etc.) - convert to -EINTR or restart
 * 2. Signal delivery (TODO)
 */
void do_signal(struct pt_regs *regs)
{
	long syscall_ret = regs->r20;  /* R20 holds return value */

	/*
	 * Handle syscall restart.
	 *
	 * When a syscall is interrupted (e.g., by a signal), the kernel returns
	 * -ERESTARTSYS (512) or similar. These should NEVER reach userspace.
	 *
	 * For now, we don't have full signal support, so we convert these
	 * to -EINTR (4) which is a valid userspace errno meaning "interrupted".
	 */
	switch (syscall_ret) {
	case -ERESTARTSYS:
	case -ERESTARTNOINTR:
	case -ERESTARTNOHAND:
	case -ERESTART_RESTARTBLOCK:
		/*
		 * Without proper signal handling, convert to -EINTR.
		 * This lets userspace retry the syscall if desired.
		 *
		 * TODO: When signal delivery is implemented, some of these
		 * should trigger syscall restart instead.
		 */
		regs->r20 = -EINTR;
		break;
	}

	/*
	 * TODO: Check for pending signals and deliver them.
	 * For now, we just return to userspace.
	 */
}

asmlinkage long sys_rt_sigreturn(void)
{
	/* TODO: Implement sigreturn */
	return -ENOSYS;
}
