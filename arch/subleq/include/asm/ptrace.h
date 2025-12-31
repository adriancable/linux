/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Register save structure for Subleq
 */

#ifndef _ASM_SUBLEQ_PTRACE_H
#define _ASM_SUBLEQ_PTRACE_H

#ifndef __ASSEMBLY__

/*
 * Subleq register save structure
 *
 * This represents the saved state when entering the kernel.
 * Subleq doesn't have hardware registers - these are memory locations.
 */
struct pt_regs {
	unsigned long r3; /* General purpose / return value high */
	unsigned long r4; /* General purpose / return value low */
	unsigned long r5;
	unsigned long r6;
	unsigned long r7;
	unsigned long r8;
	unsigned long r9;
	unsigned long r10;
	unsigned long r11;
	unsigned long r12;
	unsigned long r13;
	unsigned long r14;
	unsigned long r15;
	unsigned long r16;
	unsigned long r17;
	unsigned long r18;
	unsigned long r19;
	unsigned long r20; /* Return value */
	unsigned long r21; /* Arg 1 */
	unsigned long r22; /* Arg 2 */
	unsigned long r23; /* Arg 3 */
	unsigned long r24; /* Arg 4 */
	unsigned long sp; /* Stack pointer */
	unsigned long ra; /* Return address (link register) */
	unsigned long pc; /* Program counter */
	unsigned long orig_r20; /* Original R20 for syscall restart */
};

#define user_mode(regs) (0) /* Always kernel mode for now */
#define kernel_mode(regs) (1)

#define instruction_pointer(regs) ((regs)->pc)
#define user_stack_pointer(regs) ((regs)->sp)
#define profile_pc(regs) instruction_pointer(regs)

#define MAX_REG_OFFSET (offsetof(struct pt_regs, orig_r20))

#endif /* !__ASSEMBLY__ */

#endif /* _ASM_SUBLEQ_PTRACE_H */
