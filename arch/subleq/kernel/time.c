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
 * Cache the (seconds * NSEC_PER_SEC) product to avoid expensive 64-bit
 * multiply on every clock read. Seconds changes at most once per second,
 * so most reads are a comparison + addition.
 */
static u64 cached_seconds_val;  /* Last seen seconds value */
static u64 cached_seconds_ns;   /* cached_seconds_val * NSEC_PER_SEC */

static inline u64 subleq_seconds_to_ns(u64 seconds)
{
	if (likely(seconds == cached_seconds_val))
		return cached_seconds_ns;
	/*
	 * Write cached_seconds_ns before cached_seconds_val.
	 * On 32-bit Subleq, u64 writes are non-atomic. This ordering
	 * ensures an interrupt reader always sees a consistent pair:
	 * old val + old ns (cache miss, recomputes) or new val + new ns.
	 */
	cached_seconds_ns = seconds * NSEC_PER_SEC;
	cached_seconds_val = seconds;
	return cached_seconds_ns;
}

/*
 * Read current time from VM clock registers as nanoseconds.
 */
static u64 subleq_read_clock(struct clocksource *cs)
{
	u32 lo, hi, ns;
	u64 seconds;

	lo = readl((void __iomem *)SUBLEQ_CLOCK_S_LO);
	hi = readl((void __iomem *)SUBLEQ_CLOCK_S_HI);
	ns = readl((void __iomem *)SUBLEQ_CLOCK_NS);

	seconds = ((u64)hi << 32) | lo;
	return subleq_seconds_to_ns(seconds) + ns;
}

static struct clocksource subleq_clocksource = {
	.name = "subleq",
	.rating = 400,  /* High rating - this is our primary accurate clock */
	.read = subleq_read_clock,
	.mask = CLOCKSOURCE_MASK(64),
	.flags = CLOCK_SOURCE_IS_CONTINUOUS,
};

/*
 * sched_clock — nanoseconds since boot for printk timestamps and scheduling.
 */
static u64 boot_ns;

unsigned long long notrace sched_clock(void)
{
	u32 lo, hi, ns;
	u64 seconds, now_ns;

	lo = readl((void __iomem *)SUBLEQ_CLOCK_S_LO);
	hi = readl((void __iomem *)SUBLEQ_CLOCK_S_HI);
	ns = readl((void __iomem *)SUBLEQ_CLOCK_NS);

	seconds = ((u64)hi << 32) | lo;
	now_ns = subleq_seconds_to_ns(seconds) + ns;

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
	 * Seed the CRNG from nanosecond clock values. Each read has
	 * slightly different nanosecond precision. With
	 * random.trust_bootloader=on, this credits the entropy.
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
 * Delay functions using fixed-point arithmetic.
 * __const_udelay: xloops is pre-multiplied by 2^32/time_unit.
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
