/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Register save structure for Subleq
 *
 * IMPORTANT: pt_regs values are stored NEGATED for efficient SUBLEQ assembly.
 * SUBLEQ's natural store pattern is: dest -= src (which stores -src).
 * By storing values negated, we eliminate the double-negation overhead
 * in the interrupt entry/exit paths (~100 instructions saved per interrupt).
 *
 * All C code MUST use the PT_REG_GET/PT_REG_SET macros to access pt_regs
 * fields. Direct field access will give wrong (negated) values!
 */

#ifndef _ASM_SUBLEQ_PTRACE_H
#define _ASM_SUBLEQ_PTRACE_H

#ifndef __ASSEMBLY__

/*
 * Subleq register save structure
 *
 * This represents the saved state when entering the kernel.
 * Subleq doesn't have hardware registers - these are memory locations.
 *
 * NOTE: All values are stored NEGATED. Use PT_REG_GET/PT_REG_SET macros!
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

/*
 * pt_regs accessor macros
 *
 * Values are stored NEGATED in pt_regs. These macros handle the conversion:
 * - PT_REG_GET: reads a field and negates to get the logical value
 * - PT_REG_SET: negates the value before storing
 *
 * For signed values (like syscall_nr or error codes), negation preserves sign.
 * For addresses (like pc, sp), negation is just bit manipulation that reverses.
 */
#define PT_REG_GET(regs, field)       ((unsigned long)(-(long)(regs)->field))
#define PT_REG_SET(regs, field, val)  ((regs)->field = (unsigned long)(-(long)(val)))

/* Signed version for fields that can be negative (like syscall_nr, r20 errors) */
#define PT_REG_GET_SIGNED(regs, field)       (-(long)(regs)->field)
#define PT_REG_SET_SIGNED(regs, field, val)  ((regs)->field = (unsigned long)(-(long)(val)))

/* Check if we're returning from a syscall (vs interrupt/exception) */
#define in_syscall(regs)	(PT_REG_GET_SIGNED(regs, syscall_nr) >= 0)

/* Mark that syscall restart should NOT happen (e.g., after sigreturn) */
#define syscall_wont_restart(regs)	PT_REG_SET_SIGNED(regs, syscall_nr, -1)

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
	(PT_REG_GET(regs, pc) < (unsigned long)_stext || \
	 PT_REG_GET(regs, pc) >= (unsigned long)_end)
#define kernel_mode(regs) (!user_mode(regs))

#define instruction_pointer(regs) PT_REG_GET(regs, pc)
#define user_stack_pointer(regs) PT_REG_GET(regs, sp)
#define profile_pc(regs) instruction_pointer(regs)

#define MAX_REG_OFFSET (offsetof(struct pt_regs, orig_a4) + sizeof(unsigned long))

#endif /* !__ASSEMBLY__ */

#endif /* _ASM_SUBLEQ_PTRACE_H */
