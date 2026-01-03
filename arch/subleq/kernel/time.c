// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq timer and timekeeping
 *
 * The Subleq VM fires a timer interrupt every ~10000 instruction cycles.
 * We use legacy_timer_tick() for timekeeping, following the pattern of
 * m68k coldfire (arch/m68k/coldfire/timers.c).
 */

#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/interrupt.h>
#include <linux/clocksource.h>
#include <linux/clockchips.h>
#include <linux/delay.h>
#include <linux/timekeeping.h>

#include <asm/irq.h>

/*
 * Subleq timer counter - incremented on each tick.
 * Also used as the clocksource value.
 */
static unsigned long subleq_ticks;

/*
 * Timer interrupt handler - called from subleq_do_IRQ() in irq.c
 *
 * NOTE: irq_enter()/irq_exit() are called by subleq_do_IRQ(),
 * so this function should NOT call them again.
 *
 * This follows the m68k coldfire pattern - see mcftmr_tick() in
 * arch/m68k/coldfire/timers.c which just calls legacy_timer_tick(1).
 */
void subleq_timer_interrupt(void)
{
	subleq_ticks++;
	legacy_timer_tick(1);
}

/*
 * Read current timer value (just return ticks count)
 */
static u64 subleq_read_clock(struct clocksource *cs)
{
	return subleq_ticks;
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
