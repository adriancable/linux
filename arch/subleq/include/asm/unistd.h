/* SPDX-License-Identifier: GPL-2.0 */
/*
 * System call numbers for Subleq
 */

#ifndef _ASM_SUBLEQ_UNISTD_H
#define _ASM_SUBLEQ_UNISTD_H

/* Use generic system call table */
#include <uapi/asm-generic/unistd.h>

#define __ARCH_WANT_NEW_STAT
#define __ARCH_WANT_SYS_CLONE
#define __ARCH_WANT_SYS_CLONE3

#endif /* _ASM_SUBLEQ_UNISTD_H */
