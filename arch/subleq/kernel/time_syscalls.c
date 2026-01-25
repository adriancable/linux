// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq time syscalls
 *
 * These syscalls read the real-time clock directly from the VM's RTC
 * at byte address 24 (word 6), which contains the Unix epoch in seconds.
 *
 * This is necessary because:
 * 1. The VM only updates the RTC during timer interrupts
 * 2. The timer interrupt rate is not guaranteed to be accurate
 * 3. We want gettimeofday/clock_gettime to always return the correct time
 */

#include <linux/kernel.h>
#include <linux/syscalls.h>
#include <linux/time.h>
#include <linux/timekeeping.h>
#include <linux/uaccess.h>
#include <asm/io.h>

/* RTC is at byte address 24 (word 6) */
#define SUBLEQ_RTC_ADDR		24

/*
 * Read the current Unix epoch from the VM's RTC.
 */
static inline time64_t subleq_read_rtc(void)
{
	return (time64_t)readl((void __iomem *)SUBLEQ_RTC_ADDR);
}

/*
 * __subleq_sys_gettimeofday - Subleq implementation
 *
 * Reads the RTC directly instead of using kernel timekeeping.
 */
asmlinkage long __subleq_sys_gettimeofday(
	struct __kernel_old_timeval __user *tv,
	struct timezone __user *tz)
{
	if (tv) {
		struct __kernel_old_timeval ktv;

		ktv.tv_sec = subleq_read_rtc();
		ktv.tv_usec = 0;  /* RTC only has second resolution */

		if (copy_to_user(tv, &ktv, sizeof(ktv)))
			return -EFAULT;
	}

	if (tz) {
		struct timezone ktz = {
			.tz_minuteswest = 0,
			.tz_dsttime = 0,
		};

		if (copy_to_user(tz, &ktz, sizeof(ktz)))
			return -EFAULT;
	}

	return 0;
}

/*
 * __subleq_sys_clock_gettime - Subleq implementation (64-bit timespec)
 *
 * For CLOCK_REALTIME, reads the RTC directly.
 * For other clocks, uses kernel timekeeping.
 */
asmlinkage long __subleq_sys_clock_gettime(
	const clockid_t which_clock,
	struct __kernel_timespec __user *tp)
{
	struct __kernel_timespec kts;

	switch (which_clock) {
	case CLOCK_REALTIME:
	case CLOCK_REALTIME_COARSE:
		kts.tv_sec = subleq_read_rtc();
		kts.tv_nsec = 0;
		break;

	case CLOCK_MONOTONIC:
	case CLOCK_MONOTONIC_COARSE:
	case CLOCK_MONOTONIC_RAW:
	case CLOCK_BOOTTIME: {
		/* Use jiffies-based monotonic time for these */
		struct timespec64 ts;
		ktime_get_ts64(&ts);
		kts.tv_sec = ts.tv_sec;
		kts.tv_nsec = ts.tv_nsec;
		break;
	}

	default:
		return -EINVAL;
	}

	if (copy_to_user(tp, &kts, sizeof(kts)))
		return -EFAULT;

	return 0;
}

/*
 * __subleq_sys_clock_gettime32 - 32-bit time_t version (for TIME32 compat)
 */
asmlinkage long __subleq_sys_clock_gettime32(
	const clockid_t which_clock,
	struct old_timespec32 __user *tp)
{
	struct old_timespec32 kts;

	switch (which_clock) {
	case CLOCK_REALTIME:
	case CLOCK_REALTIME_COARSE:
		kts.tv_sec = (old_time32_t)subleq_read_rtc();
		kts.tv_nsec = 0;
		break;

	case CLOCK_MONOTONIC:
	case CLOCK_MONOTONIC_COARSE:
	case CLOCK_MONOTONIC_RAW:
	case CLOCK_BOOTTIME: {
		struct timespec64 ts;
		ktime_get_ts64(&ts);
		kts.tv_sec = (old_time32_t)ts.tv_sec;
		kts.tv_nsec = ts.tv_nsec;
		break;
	}

	default:
		return -EINVAL;
	}

	if (copy_to_user(tp, &kts, sizeof(kts)))
		return -EFAULT;

	return 0;
}
