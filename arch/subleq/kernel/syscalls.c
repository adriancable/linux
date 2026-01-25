// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq system call table
 */

#include <linux/linkage.h>
#include <linux/syscalls.h>
#include <asm-generic/syscalls.h>
#include <asm/syscall.h>

/* Forward declarations for 32-bit syscalls that may not be declared
 * in syscalls.h due to conditional compilation */
asmlinkage long sys_fstat64(unsigned long fd, struct stat64 __user *statbuf);
asmlinkage long sys_fstatat64(int dfd, const char __user *filename,
			       struct stat64 __user *statbuf, int flag);

/*
 * Subleq-specific time syscalls that read the RTC directly.
 * These bypass the kernel's timekeeping subsystem since the VM provides
 * the current Unix epoch at byte address 24.
 */
extern asmlinkage long __subleq_sys_gettimeofday(
	struct __kernel_old_timeval __user *tv,
	struct timezone __user *tz);
extern asmlinkage long __subleq_sys_clock_gettime(
	const clockid_t which_clock,
	struct __kernel_timespec __user *tp);
extern asmlinkage long __subleq_sys_clock_gettime32(
	const clockid_t which_clock,
	struct old_timespec32 __user *tp);

/* 
 * Build the syscall table by redefining __SYSCALL and including
 * the syscall table header (which has no include guard).
 *
 * Subleq-specific overrides are placed AFTER the #include so that
 * C's designated initializer rules apply: later initializers for the
 * same index override earlier ones.
 */
#undef __SYSCALL
#define __SYSCALL(nr, call) [nr] = (call),

void *sys_call_table[__NR_syscalls] = {
	[0 ... __NR_syscalls - 1] = sys_ni_syscall,
#include <asm/syscall_table.h>

	/*
	 * Subleq-specific time syscall overrides.
	 * These read the RTC directly from byte address 24 for CLOCK_REALTIME.
	 */
	[__NR_gettimeofday] = __subleq_sys_gettimeofday,
#ifdef __NR_clock_gettime64
	[__NR_clock_gettime64] = __subleq_sys_clock_gettime,
#endif
#ifdef __NR_clock_gettime
	[__NR_clock_gettime] = __subleq_sys_clock_gettime32,
#endif
};
