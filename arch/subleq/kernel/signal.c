// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq signal handling
 */

#include <linux/kernel.h>
#include <linux/signal.h>
#include <linux/sched.h>

#include <asm/ptrace.h>

/*
 * Signal handling stubs - minimal implementation
 */

void do_signal(struct pt_regs *regs)
{
	/* TODO: Implement signal delivery */
}

asmlinkage long sys_rt_sigreturn(void)
{
	/* TODO: Implement sigreturn */
	return -ENOSYS;
}
