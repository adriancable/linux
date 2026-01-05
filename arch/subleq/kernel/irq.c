// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq interrupt handling
 *
 * The VM fires a timer interrupt every 10000 instruction cycles:
 * - Saves current PC to m[1] (byte address 4)
 * - Jumps to handler address in m[0]
 *
 * The low-level assembly entry point is in entry.S (subleq_irq_entry).
 * It calls subleq_do_IRQ() and returns to the interrupted code.
 */

#include <linux/init.h>
#include <linux/irq.h>
#include <linux/interrupt.h>
#include <linux/hardirq.h>

#include <asm/irq.h>
#include <asm/irq_regs.h>
#include <asm/ptrace.h>

/*
 * Memory-mapped interrupt registers
 */
#define INT_HANDLER_ADDR ((volatile unsigned long *)0)
#define INT_SAVED_PC_ADDR ((volatile unsigned long *)4)
#define INT_SAVED_HANDLER ((volatile unsigned long *)8)

/* Assembly entry point from entry.S */
extern void subleq_irq_entry(void);

/* Timer interrupt handler (in time.c) - just calls legacy_timer_tick */
extern void subleq_timer_interrupt(void);

/*
 * Dummy pt_regs for interrupt context.
 * Since Subleq doesn't have hardware registers and we're always in kernel
 * mode, we use a static dummy structure.
 */
static struct pt_regs subleq_irq_regs;

/*
 * C-level interrupt handler - called from assembly entry.S
 *
 * This function wraps the actual interrupt handlers with irq_enter()/irq_exit().
 * Following the m68k do_IRQ() pattern in arch/m68k/kernel/irq.c.
 */
void subleq_do_IRQ(void)
{
	struct pt_regs *old_regs;

	/* Set up irq_regs for get_irq_regs() - must be done BEFORE irq_enter */
	old_regs = set_irq_regs(&subleq_irq_regs);

	/* Enter IRQ context - increments preempt_count hardirq bits */
	irq_enter();

	/* Handle the timer interrupt (the only interrupt we have) */
	subleq_timer_interrupt();

	/* Exit IRQ context - may trigger softirqs */
	irq_exit();

	/* Restore previous irq_regs */
	set_irq_regs(old_regs);
}

/*
 * Initialize the interrupt system
 */
void __init init_IRQ(void)
{
	/*
	 * Install our assembly interrupt handler.
	 * Set m[2] (saved handler) to the handler address.
	 * m[0] stays 0 (disabled) until local_irq_enable() is called.
	 */
	*INT_SAVED_HANDLER = (unsigned long)subleq_irq_entry;

	pr_info("Subleq IRQ: handler installed at 0x%lx\n",
		(unsigned long)subleq_irq_entry);
}

/*
 * Architecture-specific IRQ setup stub
 */
int arch_setup_irq_generic(unsigned int irq)
{
	return 0;
}
