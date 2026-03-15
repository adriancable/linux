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
 * Heuristic walk: scan the stack for values in the kernel text range.
 * Also checks -addr since RA-Direct stores negated return addresses.
 */
extern char _stext[], _etext[];

void show_stack(struct task_struct *task, unsigned long *sp, const char *loglvl)
{
	unsigned long *stack;
	unsigned long addr;
	int i, found = 0, max_scan = 128;

	if (sp == NULL) {
		/* Get current SP from memory location 16 (REG_SP) */
		sp = (unsigned long *)*(volatile unsigned long *)16;
	}

	printk("%sStack trace from SP=%px:\n", loglvl, sp);

	stack = sp;
	for (i = 0; i < max_scan && found < 20; i++) {
		/* Basic bounds check - stack should be above 0x1000 */
		if ((unsigned long)stack < 0x1000)
			break;

		addr = *stack++;

		/* Check both addr and -addr (negated RA convention) */
		if (addr >= (unsigned long)_stext &&
		    addr <= (unsigned long)_etext) {
			printk("%s [<%08lx>] %pS\n", loglvl, addr,
			       (void *)addr);
			found++;
		} else if (-addr >= (unsigned long)_stext &&
			   -addr <= (unsigned long)_etext) {
			printk("%s [<%08lx>] %pS (negated RA)\n", loglvl,
			       -addr, (void *)-addr);
			found++;
		}
	}

	if (found == 0)
		printk("%s (no return addresses found on stack)\n", loglvl);
}

/*
 * Register dump
 */
void show_regs(struct pt_regs *regs)
{
	pr_info("Registers:\n");
	if (regs) {
		unsigned long pc = PT_REG_GET(regs, pc);
		unsigned long sp = PT_REG_GET(regs, sp);
		unsigned long ra = PT_REG_GET(regs, ra);

		pr_info("  PC: %08lx (%pS)\n", pc, (void *)pc);
		pr_info("  SP: %08lx  RA: %08lx (%pS)\n", sp, ra,
			(void *)ra);
		pr_info("  R20: %08lx  R21: %08lx\n",
			PT_REG_GET(regs, r20), PT_REG_GET(regs, r21));
	}
}

/*
 * Check if address is a valid BUG address
 */
int is_valid_bugaddr(unsigned long addr)
{
	return addr >= (unsigned long)_stext && addr < (unsigned long)_etext;
}

/*
 * Stack trace capture - minimal implementation
 */
#ifdef CONFIG_STACKTRACE
void save_stack_trace(struct stack_trace *trace)
{
	/* Not implemented for Subleq */
	trace->nr_entries = 0;
}
#endif
