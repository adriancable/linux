/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
/*
 * Signal context for Subleq
 */

#ifndef _UAPI_ASM_SUBLEQ_SIGCONTEXT_H
#define _UAPI_ASM_SUBLEQ_SIGCONTEXT_H

struct sigcontext {
	unsigned long sc_regs[32]; /* Saved registers */
	unsigned long sc_pc; /* Saved PC */
};

#endif /* _UAPI_ASM_SUBLEQ_SIGCONTEXT_H */
