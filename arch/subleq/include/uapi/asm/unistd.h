/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
/*
 * System call definitions for Subleq
 */

#ifndef _UAPI_ASM_SUBLEQ_UNISTD_H
#define _UAPI_ASM_SUBLEQ_UNISTD_H

/* Enable new stat syscalls (fstat, fstatat, etc.) */
#define __ARCH_WANT_NEW_STAT
#define __ARCH_WANT_STAT64

/* Enable 32-bit time syscalls (ppoll, pselect6, etc.) */
#define __ARCH_WANT_TIME32_SYSCALLS

/* Enable legacy syscalls that are superseded but still useful */
#define __ARCH_WANT_RENAMEAT

/* Use the generic system call table */
#include <asm-generic/unistd.h>

#endif /* _UAPI_ASM_SUBLEQ_UNISTD_H */
