/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
/*
 * Signal context for Subleq
 */

#ifndef _UAPI_ASM_SUBLEQ_SIGCONTEXT_H
#define _UAPI_ASM_SUBLEQ_SIGCONTEXT_H

struct sigcontext {
	unsigned long sc_regs[32]; /* Saved registers */
	unsigned long sc_pc; /* Saved PC */
	/* Syscall restart information */
	unsigned long sc_orig_r21;  /* Original syscall number */
	unsigned long sc_orig_a1;   /* Original arg1 */
	unsigned long sc_orig_a2;   /* Original arg2 */
	unsigned long sc_orig_a3;   /* Original arg3 */
	unsigned long sc_orig_a4;   /* Original arg4 */
	long sc_syscall_nr;         /* Syscall number (-1 if not in syscall) */
};

#endif /* _UAPI_ASM_SUBLEQ_SIGCONTEXT_H */
