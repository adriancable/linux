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
 * Build the syscall table by redefining __SYSCALL and including
 * the syscall table header (which has no include guard).
 */
#undef __SYSCALL
#define __SYSCALL(nr, call) [nr] = (call),

void *sys_call_table[__NR_syscalls] = {
	[0 ... __NR_syscalls - 1] = sys_ni_syscall,
#include <asm/syscall_table.h>
};
