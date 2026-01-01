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

/*
 * Memory-mapped interrupt registers
 */
#define INT_HANDLER_ADDR ((volatile unsigned long *)0)
#define INT_SAVED_PC_ADDR ((volatile unsigned long *)4)
#define INT_SAVED_HANDLER ((volatile unsigned long *)8)

/* Assembly entry point from entry.S */
extern void subleq_irq_entry(void);

/* Forward declaration */
extern void subleq_timer_interrupt(void);

/*
 * C-level interrupt handler - called from assembly entry.S
 */
extern void __subleq_putchar(int c);

void subleq_do_IRQ(void)
{
	subleq_timer_interrupt();
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

	pr_info("Subleq IRQ: handler installed at %p\n", subleq_irq_entry);
}

/*
 * Architecture-specific IRQ setup stub
 */
int arch_setup_irq_generic(unsigned int irq)
{
	return 0;
}
