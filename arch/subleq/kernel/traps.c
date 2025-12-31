// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq trap/exception handling
 */

#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/sched.h>
#include <linux/sched/debug.h>
#include <linux/bug.h>
#include <linux/stacktrace.h>
#include <asm/ptrace.h>

/*
 * Trap handling stubs
 *
 * Subleq doesn't really have hardware traps/exceptions.
 * Everything is software-implemented.
 */

void __init trap_init(void)
{
	/* No hardware traps to set up */
}

/*
 * Stack trace display - minimal implementation
 */
void show_stack(struct task_struct *task, unsigned long *sp, const char *loglvl)
{
	pr_info("%sStack trace not available on Subleq\n", loglvl);
}

/*
 * Register dump - minimal implementation
 */
void show_regs(struct pt_regs *regs)
{
	pr_info("Registers:\n");
	if (regs) {
		pr_info("  PC: %08lx  SP: %08lx\n", regs->pc, regs->sp);
		pr_info("  R20: %08lx  R21: %08lx\n", regs->r20, regs->r21);
	}
}

/*
 * Check if address is a valid BUG address
 */
int is_valid_bugaddr(unsigned long addr)
{
	return 1; /* All addresses are potentially valid */
}

/*
 * Stack trace capture - minimal implementation
 */
void save_stack_trace(struct stack_trace *trace)
{
	/* Not implemented for Subleq */
	trace->nr_entries = 0;
}
