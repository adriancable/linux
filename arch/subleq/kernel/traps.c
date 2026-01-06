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
#include <linux/cpu.h>
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
 * Stack trace display
 *
 * Subleq calling convention: return address is pushed onto the stack
 * before each call. We walk the stack looking for values that could be
 * return addresses (between start of kernel text and end).
 *
 * This is a heuristic - we can't perfectly identify stack frames without
 * frame pointers, but we can print plausible return addresses.
 */
extern char _stext[], _etext[];

void show_stack(struct task_struct *task, unsigned long *sp, const char *loglvl)
{
	unsigned long *stack;
	unsigned long addr;
	int i, max_entries = 20;

	if (sp == NULL) {
		/* Get current SP from memory location 16 (REG_SP) */
		sp = (unsigned long *)*(volatile unsigned long *)16;
	}

	printk("%sStack trace from SP=%px:\n", loglvl, sp);

	stack = sp;
	for (i = 0; i < max_entries; i++) {
		/* Basic bounds check - stack should be above 0x1000 */
		if ((unsigned long)stack < 0x1000)
			break;

		addr = *stack++;

		/* Check if this looks like a kernel text address */
		if (addr >= (unsigned long)_stext &&
		    addr <= (unsigned long)_etext) {
			printk("%s [<%08lx>] (possible return address)\n",
			       loglvl, addr);
		}
	}
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
