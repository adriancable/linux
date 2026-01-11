/* SPDX-License-Identifier: GPL-2.0 */
/*
 * System call numbers for Subleq
 */

#ifndef _ASM_SUBLEQ_UNISTD_H
#define _ASM_SUBLEQ_UNISTD_H

#include <uapi/asm/unistd.h>

/*
 * Kernel-internal flags - these enable internal syscall handling features,
 * NOT syscall table entries (which are controlled in syscall_table.h).
 */
#define __ARCH_WANT_SYS_CLONE
#define __ARCH_WANT_SYS_CLONE3

#define NR_syscalls (__NR_syscalls)

#endif /* _ASM_SUBLEQ_UNISTD_H */

