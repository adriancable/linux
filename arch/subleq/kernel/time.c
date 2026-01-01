// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq timer and timekeeping
 */

#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/interrupt.h>
#include <linux/clocksource.h>
#include <linux/clockchips.h>
#include <linux/delay.h>
#include <linux/hardirq.h>
#include <linux/timekeeping.h>

#include <asm/irq.h>
#include <asm/irqflags.h>
#include <asm/irq_regs.h>
#include <asm/ptrace.h>

/*
 * Subleq timer interrupt fires every 10000 instructions.
 * We use this as our tick source.
 */

/* Jiffies counter */
static unsigned long subleq_jiffies;

/*
 * Dummy pt_regs for timer interrupt
 * Since Subleq doesn't have hardware registers and we're always in kernel
 * mode, we use a static dummy structure.
 */
static struct pt_regs subleq_timer_regs;

/*
 * Timer interrupt handler - called from assembly entry.S
 * 
 * This is the main integration point between the VM's timer interrupt
 * and the Linux kernel scheduler. We use legacy_timer_tick() which is
 * designed for architectures without generic clockevents. It handles:
 * - do_timer() for jiffies/timekeeping
 * - update_wall_time()
 * - update_process_times() which calls sched_tick() for scheduling
 * - profile_tick()
 */
extern void __subleq_putchar(int c);

void subleq_timer_interrupt(void)
{
	struct pt_regs *old_regs;

	/* Set up irq_regs for get_irq_regs() */
	old_regs = set_irq_regs(&subleq_timer_regs);

	irq_enter();

	subleq_jiffies++;
	legacy_timer_tick(1);

	irq_exit();

	set_irq_regs(old_regs);
}

/*
 * Read current timer value (just return jiffies)
 */
static u64 subleq_read_clock(struct clocksource *cs)
{
	return subleq_jiffies;
}

static struct clocksource subleq_clocksource = {
	.name = "subleq",
	.rating = 100,
	.read = subleq_read_clock,
	.mask = CLOCKSOURCE_MASK(32),
	.flags = CLOCK_SOURCE_IS_CONTINUOUS,
};

/*
 * Timer initialization
 */
void __init time_init(void)
{
	/* Register clock source */
	clocksource_register_hz(&subleq_clocksource, HZ);

	pr_info("Subleq timer initialized\n");
}

/*
 * Delay loop calibration
 */
void calibrate_delay(void)
{
	/* Subleq is slow - just set a reasonable value */
	loops_per_jiffy = 1000;
	pr_info("Calibrating delay loop... %lu.%02lu BogoMIPS\n",
		loops_per_jiffy / (500000 / HZ),
		(loops_per_jiffy / (5000 / HZ)) % 100);
}

/*
 * Delay functions
 */
void __delay(unsigned long loops)
{
	/* Simple busy-wait loop */
	volatile unsigned long i;
	for (i = 0; i < loops; i++)
		barrier();
}

void __udelay(unsigned long usecs)
{
	__delay(usecs * loops_per_jiffy / (1000000 / HZ));
}

void __ndelay(unsigned long nsecs)
{
	__delay(nsecs * loops_per_jiffy / (1000000000 / HZ));
}
