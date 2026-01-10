/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Subleq switch_stack structure for context switching
 *
 * This structure holds the callee-saved registers that must be preserved
 * across context switches. The return address is NOT part of this struct -
 * it's pushed by the caller before __switch_to, so it naturally ends up
 * at [SP + SWITCH_STACK_SIZE] after we allocate space for registers.
 *
 * Based on M68k and CSKY NOMMU patterns.
 */

#ifndef _ASM_SUBLEQ_SWITCH_CONTEXT_H
#define _ASM_SUBLEQ_SWITCH_CONTEXT_H

/*
 * Callee-saved registers per Subleq calling convention:
 * R3-R19, R25-R31 (24 registers)
 * 
 * PLUS R20 which is technically caller-saved, but must be preserved
 * across context switches for vfork to work correctly. With CLONE_VM,
 * parent and child share memory including the R20 memory location.
 * By saving R20 in switch_stack, the parent's syscall return value
 * is preserved even when the child clobbers the shared R20.
 *
 * Total: 25 words = 100 bytes
 *
 * The return address (retpc) is at [SP + 100] after we allocate this struct.
 */
struct switch_stack {
	/* Callee-saved registers R3-R19 (17 registers) */
	unsigned long r3;
	unsigned long r4;
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
	
	/* R20 - syscall return value, must be preserved for vfork */
	unsigned long r20;

	/* Callee-saved registers R25-R31 (7 registers) */
	unsigned long r25;
	unsigned long r26;
	unsigned long r27;
	unsigned long r28;
	unsigned long r29;
	unsigned long r30;
	unsigned long r31;
};

#define SWITCH_STACK_SIZE sizeof(struct switch_stack) /* 100 bytes */
#define SWITCH_STACK_RETPC_OFFSET 100  /* retpc is at [SP + 100] after allocation */

/* Offsets for assembly - must match struct layout above */
#define SW_OFF_R3    0
#define SW_OFF_R4    4
#define SW_OFF_R5    8
#define SW_OFF_R6    12
#define SW_OFF_R7    16
#define SW_OFF_R8    20
#define SW_OFF_R9    24
#define SW_OFF_R10   28
#define SW_OFF_R11   32
#define SW_OFF_R12   36
#define SW_OFF_R13   40
#define SW_OFF_R14   44
#define SW_OFF_R15   48
#define SW_OFF_R16   52
#define SW_OFF_R17   56
#define SW_OFF_R18   60
#define SW_OFF_R19   64
#define SW_OFF_R20   68
#define SW_OFF_R25   72
#define SW_OFF_R26   76
#define SW_OFF_R27   80
#define SW_OFF_R28   84
#define SW_OFF_R29   88
#define SW_OFF_R30   92
#define SW_OFF_R31   96

#endif /* _ASM_SUBLEQ_SWITCH_CONTEXT_H */
