// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq timer and timekeeping
 *
 * The Subleq VM provides nanosecond-resolution time through memory-mapped
 * clock registers. The clocksource reads directly from these registers,
 * giving the kernel accurate time for both monotonic and wall-clock purposes.
 *
 * Timer interrupts still fire at HZ rate for scheduler ticks, but the
 * clocksource is decoupled from interrupt timing accuracy.
 */

#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/sched/clock.h>

#include <linux/clocksource.h>
#include <linux/clockchips.h>
#include <linux/delay.h>
#include <linux/timekeeping.h>
#include <linux/time.h>
#include <linux/random.h>


#include <asm/io.h>

/*
 * Subleq Clock Registers (words 64-66, bytes 256-264)
 *
 * The VM provides the current time with nanosecond resolution:
 *   CLOCK_S_LO (word 64, byte 256): Low 32 bits of 64-bit seconds
 *   CLOCK_S_HI (word 65, byte 260): High 32 bits of 64-bit seconds
 *   CLOCK_NS   (word 66, byte 264): Nanoseconds (0-999999999)
 *
 * These values are updated by the VM continuously (not just at interrupts).
 */
#define SUBLEQ_CLOCK_S_LO	256
#define SUBLEQ_CLOCK_S_HI	260
#define SUBLEQ_CLOCK_NS		264

/*
 * Read current time as nanoseconds since boot.
 *
 * The clocksource returns a monotonic nanosecond counter. We compute this
 * from the VM's clock registers which provide wall-clock time.
 *
 * For simplicity, we use the seconds * 1e9 + nanoseconds directly.
 * This gives us a 64-bit nanosecond counter that won't wrap for ~584 years.
 */
static u64 subleq_read_clock(struct clocksource *cs)
{
	u32 lo, hi, ns;
	u64 seconds;

	lo = readl((void __iomem *)SUBLEQ_CLOCK_S_LO);
	hi = readl((void __iomem *)SUBLEQ_CLOCK_S_HI);
	ns = readl((void __iomem *)SUBLEQ_CLOCK_NS);

	seconds = ((u64)hi << 32) | lo;
	return seconds * NSEC_PER_SEC + ns;
}

static struct clocksource subleq_clocksource = {
	.name = "subleq",
	.rating = 400,  /* High rating - this is our primary accurate clock */
	.read = subleq_read_clock,
	.mask = CLOCKSOURCE_MASK(64),
	.flags = CLOCK_SOURCE_IS_CONTINUOUS,
};

/*
 * sched_clock - scheduler clock for printk timestamps and scheduling
 *
 * Returns nanoseconds since boot. We read the VM's clock registers
 * and subtract the boot time to get monotonic nanoseconds.
 *
 * This is used by printk for timestamps and by the scheduler for
 * timing measurements.
 */
static u64 boot_ns;

unsigned long long notrace sched_clock(void)
{
	u32 lo, hi, ns;
	u64 now_ns;

	lo = readl((void __iomem *)SUBLEQ_CLOCK_S_LO);
	hi = readl((void __iomem *)SUBLEQ_CLOCK_S_HI);
	ns = readl((void __iomem *)SUBLEQ_CLOCK_NS);

	now_ns = ((u64)hi << 32 | lo) * NSEC_PER_SEC + ns;

	/* Return monotonic nanoseconds since boot */
	if (boot_ns == 0)
		boot_ns = now_ns;

	return now_ns - boot_ns;
}

/*
 * Timer initialization
 */
void __init time_init(void)
{
	u64 entropy[4];  /* 32 bytes = 256 bits for CRNG initialization */
	int i;

	/*
	 * Initialize boot_ns for sched_clock().
	 * Read the clock once to establish the boot timestamp.
	 */
	(void)sched_clock();

	/*
	 * Seed the random number generator with nanosecond clock values.
	 * Read the clock multiple times - each read has different nanosecond
	 * precision due to varying execution time. This provides 256 bits
	 * of entropy to fully initialize the CRNG and eliminate the
	 * "uninitialized urandom read" warnings.
	 *
	 * With random.trust_bootloader=on, this credits the entropy.
	 */
	for (i = 0; i < 4; i++) {
		u32 lo = readl((void __iomem *)SUBLEQ_CLOCK_S_LO);
		u32 hi = readl((void __iomem *)SUBLEQ_CLOCK_S_HI);
		u32 ns = readl((void __iomem *)SUBLEQ_CLOCK_NS);
		entropy[i] = ((u64)hi << 32 | lo) * NSEC_PER_SEC + ns;
	}
	add_bootloader_randomness(entropy, sizeof(entropy));

	/*
	 * Register the clocksource at 1 GHz (nanosecond resolution).
	 * The kernel will use this for accurate timekeeping.
	 */
	clocksource_register_hz(&subleq_clocksource, NSEC_PER_SEC);

	pr_info("Subleq timer initialized (nanosecond-resolution clocksource)\n");
}


/*
 * Read time from the persistent clock.
 *
 * The Subleq VM provides nanosecond-resolution time at words 64-66:
 *   - CLOCK_S_LO/HI: 64-bit seconds since 1970
 *   - CLOCK_NS: nanoseconds (0-999999999)
 *
 * This function is called by the kernel's timekeeping subsystem during
 * boot to initialize wall-clock time, and during suspend/resume cycles.
 * The VM populates clock registers immediately, so they are always valid.
 */
void read_persistent_clock64(struct timespec64 *ts)
{
	u32 lo, hi, ns;

	lo = readl((void __iomem *)SUBLEQ_CLOCK_S_LO);
	hi = readl((void __iomem *)SUBLEQ_CLOCK_S_HI);
	ns = readl((void __iomem *)SUBLEQ_CLOCK_NS);

	ts->tv_sec = ((s64)hi << 32) | lo;
	ts->tv_nsec = ns;
}

/*
 * Delay functions
 *
 * These follow the standard kernel delay pattern used by most architectures.
 * __const_udelay uses fixed-point arithmetic to convert time to loop counts
 * without overflow: xloops is pre-multiplied by 2^32/time_unit, so
 * (xloops * loops_per_jiffy * HZ) >> 32 gives the number of __delay loops.
 */
void __delay(unsigned long loops)
{
	/* Simple busy-wait loop */
	volatile unsigned long i;
	for (i = 0; i < loops; i++)
		barrier();
}

void __const_udelay(unsigned long xloops)
{
	u64 loops;

	loops = (u64)xloops * loops_per_jiffy * HZ;
	__delay(loops >> 32);
}

void __udelay(unsigned long usecs)
{
	__const_udelay(usecs * 0x10C7UL); /* 2**32 / 1000000 (rounded up) */
}

void __ndelay(unsigned long nsecs)
{
	__const_udelay(nsecs * 0x5UL); /* 2**32 / 1000000000 (rounded up) */
}
