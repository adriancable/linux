/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
/*
 * Signal context for Subleq
 */

#ifndef _UAPI_ASM_SUBLEQ_SIGCONTEXT_H
#define _UAPI_ASM_SUBLEQ_SIGCONTEXT_H

struct sigcontext {
	unsigned long sc_regs[32]; /* Saved GPRs */
	unsigned long sc_pc;       /* Saved PC */
	unsigned long sc_tregs[16]; /* Saved T-registers (T0-T15) */
	unsigned long sc_z;        /* Saved Z register */
	/* Syscall restart information */
	unsigned long sc_orig_r21;  /* Original syscall number */
	unsigned long sc_orig_a1;   /* Original arg1 */
	unsigned long sc_orig_a2;   /* Original arg2 */
	unsigned long sc_orig_a3;   /* Original arg3 */
	unsigned long sc_orig_a4;   /* Original arg4 */
	unsigned long sc_orig_a5;   /* Original arg5 */
	unsigned long sc_orig_a6;   /* Original arg6 */
	long sc_syscall_nr;         /* Syscall number (-1 if not in syscall) */
	/* Debug: checksums for detecting signal corruption */
	unsigned long sc_dbg_gprs_checksum;
	unsigned long sc_dbg_tregs_checksum;
};

#endif /* _UAPI_ASM_SUBLEQ_SIGCONTEXT_H */

