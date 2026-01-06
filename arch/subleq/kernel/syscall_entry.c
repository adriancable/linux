// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq syscall entry point for userspace
 *
 * This function is exported to userspace ELF binaries via the kernel's
 * symbol resolution mechanism. It provides the single entry point for
 * all system calls from userspace.
 *
 * Calling convention (standard Subleq ABI):
 *   R21 = syscall number
 *   R22 = arg1
 *   R23 = arg2
 *   R24 = arg3
 *   stack = arg4, arg5, arg6
 *   R20 = return value
 */

#include <linux/syscalls.h>
#include <linux/errno.h>
#include <asm/unistd.h>

/* Import the syscall table */
extern void *sys_call_table[];

/* Syscall function type */
typedef long (*syscall_fn_t)(long, long, long, long, long, long);

/*
 * __subleq_syscall - Main syscall entry point for userspace
 * @nr: syscall number
 * @a1-a6: syscall arguments
 *
 * Returns: syscall return value, or -ENOSYS for invalid syscall numbers
 */
long __subleq_syscall(long nr, long a1, long a2, long a3, long a4, long a5, long a6)
{
	syscall_fn_t fn;

	if (nr < 0 || nr >= __NR_syscalls)
		return -ENOSYS;

	fn = (syscall_fn_t)sys_call_table[nr];
	if (!fn || fn == (syscall_fn_t)sys_ni_syscall)
		return -ENOSYS;

	return fn(a1, a2, a3, a4, a5, a6);
}
