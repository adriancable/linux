// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq-specific syscall implementations
 */

#include <linux/syscalls.h>
#include <linux/mm.h>
#include <asm/page.h>

/*
 * sys_mmap2 - mmap2 implementation for 32-bit Subleq
 *
 * The offset is specified in 4KB page units (not bytes).
 */
SYSCALL_DEFINE6(mmap2, unsigned long, addr, unsigned long, len,
		unsigned long, prot, unsigned long, flags, unsigned long, fd,
		unsigned long, pgoff)
{
	if (pgoff & (~PAGE_MASK >> 12))
		return -EINVAL;

	return ksys_mmap_pgoff(addr, len, prot, flags, fd,
			       pgoff >> (PAGE_SHIFT - 12));
}
