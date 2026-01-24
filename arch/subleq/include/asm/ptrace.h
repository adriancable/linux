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
	unsigned long r21; /* Arg 1 / syscall number */
	unsigned long r22; /* Arg 2 */
	unsigned long r23; /* Arg 3 */
	unsigned long r24; /* Arg 4 */
	unsigned long r25; /* General purpose */
	unsigned long r26;
	unsigned long r27;
	unsigned long r28;
	unsigned long r29;
	unsigned long r30;
	unsigned long r31;
	unsigned long fp;  /* Frame pointer - CRITICAL for fork! */
	unsigned long sp;  /* Stack pointer */
	unsigned long ra;  /* Return address (link register) */
	unsigned long pc;  /* Program counter */
	unsigned long orig_r20; /* Original R20 for syscall restart */
	long syscall_nr;        /* Syscall number, -1 if not in syscall */
	unsigned long orig_r21; /* Original R21 (syscall nr) for restart */
	unsigned long orig_a1;  /* Original arg1 for syscall restart */
	unsigned long orig_a2;  /* Original arg2 for syscall restart */
	unsigned long orig_a3;  /* Original arg3 for syscall restart */
	unsigned long orig_a4;  /* Original arg4 for syscall restart */
};

/* Check if we're returning from a syscall (vs interrupt/exception) */
#define in_syscall(regs)	((regs)->syscall_nr >= 0)

/* Mark that syscall restart should NOT happen (e.g., after sigreturn) */
#define syscall_wont_restart(regs)	((regs)->syscall_nr = -1)

/*
 * user_mode - Check if interrupted context was in user mode
 *
 * For NOMMU Subleq, we detect user mode by checking if the saved PC
 * is within the kernel text range. If PC is outside kernel text,
 * we were in userspace.
 *
 * This is critical for signal delivery - we should only deliver signals
 * when returning to userspace, not when returning to kernel code.
 */
extern char _stext[], _end[];
#define user_mode(regs) \
	((unsigned long)(regs)->pc < (unsigned long)_stext || \
	 (unsigned long)(regs)->pc >= (unsigned long)_end)
#define kernel_mode(regs) (!user_mode(regs))

#define instruction_pointer(regs) ((regs)->pc)
#define user_stack_pointer(regs) ((regs)->sp)
#define profile_pc(regs) instruction_pointer(regs)

#define MAX_REG_OFFSET (offsetof(struct pt_regs, orig_r24))

#endif /* !__ASSEMBLY__ */

#endif /* _ASM_SUBLEQ_PTRACE_H */
