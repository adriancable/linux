// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq interrupt handling
 */

#include <linux/init.h>
#include <linux/irq.h>
#include <linux/interrupt.h>
#include <linux/hardirq.h>

#include <asm/irq.h>

/*
 * Subleq has a single timer interrupt source.
 * It fires every 10000 instruction cycles.
 */

/* Forward declaration */
extern void subleq_timer_interrupt(void);

/*
 * Interrupt handler entry point - called from timer handler
 */
void subleq_do_IRQ(void)
{
	/* Just tick the timer for now */
	subleq_timer_interrupt();
}

/*
 * Initialize the interrupt system
 */
void __init init_IRQ(void)
{
	/* Minimal initialization - nothing to do yet */
}

/*
 * Architecture-specific IRQ setup stub
 */
int arch_setup_irq_generic(unsigned int irq)
{
	return 0;
}
