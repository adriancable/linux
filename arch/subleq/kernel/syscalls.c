// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq system call table
 */

#include <linux/syscalls.h>
#include <asm/syscall.h>

/* Use generic system call table */
#undef __SYSCALL
#define __SYSCALL(nr, call) [nr] = (call),

void *sys_call_table[__NR_syscalls] = {
	[0 ... __NR_syscalls - 1] = sys_ni_syscall,
#include <asm/unistd.h>
};
