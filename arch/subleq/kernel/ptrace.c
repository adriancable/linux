// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq ptrace support
 */

#include <linux/kernel.h>
#include <linux/ptrace.h>
#include <linux/regset.h>
#include <linux/elf.h>

#include <asm/ptrace.h>

/*
 * Minimal ptrace stubs
 */

void ptrace_disable(struct task_struct *child)
{
}

long arch_ptrace(struct task_struct *child, long request, unsigned long addr,
		 unsigned long data)
{
	return ptrace_request(child, request, addr, data);
}
