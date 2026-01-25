/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Subleq interrupt entry/exit code
 */

#include <asm/asm-offsets.h>

.text
.globl subleq_irq_entry
.type subleq_irq_entry, @function

/* Interrupt control addresses */
.set INT_HANDLER, 0
.set INT_SAVED_PC, 4
.set INT_SAVED_HANDLER, 8

/* Source register addresses */
.set REG_Z, 12
.set REG_SP, 16
.set REG_RA, 20
.set ZERO, 24              /* Read-only zero constant */
.set REG_R3, 28
.set REG_R4, 32
.set REG_R5, 36
.set REG_R6, 40
.set REG_R7, 44
.set REG_R8, 48
.set REG_R9, 52
.set REG_R10, 56
.set REG_R11, 60
.set REG_R12, 64
.set REG_R13, 68
.set REG_R14, 72
.set REG_R15, 76
.set REG_R16, 80
.set REG_R17, 84
.set REG_R18, 88
.set REG_R19, 92
.set REG_R20, 96
.set REG_R21, 100
.set REG_R22, 104
.set REG_R23, 108
.set REG_R24, 112
.set REG_R25, 116
.set REG_R26, 120
.set REG_R27, 124
.set REG_R28, 128
.set REG_R29, 132
.set REG_R30, 136
.set REG_R31, 140
.set REG_FP, 148         /* Frame pointer at word 37 */
.set REG_T0, 160
.set REG_T1, 164
.set REG_T2, 168
.set REG_T3, 172
.set REG_T4, 176
.set REG_T5, 180
.set REG_T6, 184
.set REG_T7, 188
.set REG_T8, 192
.set REG_T9, 196
.set REG_T10, 200
.set REG_T11, 204
.set REG_T12, 208
.set REG_T13, 212
.set REG_T14, 216
.set REG_T15, 220

.set INT_Z, 224

/*
 * Kernel scratch/save slots (words 57-64, bytes 228-256)
 * Compact layout placing all kernel registers together.
 */
.set INT_Z2, 228         /* Scratch for address calculations (word 57) */
.set SAVE_SP, 232        /* Saved interrupted SP for current_thread_info (word 58) */
.set INT_SP, 236         /* Interrupt stack pointer (word 59) */
.set SAVE_JMPTGT, 240    /* Return jump target address (word 60) */
.set SW_Z, 244           /* Context switch scratch (word 61) */
.set SW_Z2, 248          /* Context switch second scratch (word 62) */

/*
 * SYSCALL STACK SWITCH SUPPORT
 * Like ColdFire's sw_usp/sw_ksp for NOMMU systems without separate U/S stack pointers.
 * 
 * SUBLEQ_USP: Saves the userspace SP when entering a syscall.
 *             Restored when returning to userspace.
 *
 * SUBLEQ_UFP: Saves the userspace FP when entering a syscall.
 *             Restored when returning to userspace.
 */
.set SUBLEQ_USP, 252    /* Saved userspace stack pointer (word 63) */
.set SUBLEQ_UFP, 256    /* Saved userspace frame pointer (word 64) */

/*
 * INT_SP: Interrupt Stack Pointer
 *
 * This is the running stack pointer for the dedicated IRQ stack.
 * Unlike the fixed SAVE_* slots, this enables multiple interrupt frames
 * to coexist on the IRQ stack - critical for preemptive multitasking.
 *
 * When a task is interrupted and the handler calls schedule(), the task's
 * interrupt frame remains on the IRQ stack (at the current INT_SP position).
 * If the new task also gets interrupted, its frame is pushed BELOW the first
 *
 * INT_SP tracks the IRQ stack position for pushing/popping frames.
 */
/* INT_SP is now at byte 236 (word 59), defined above with other kernel registers */

/*
 * IRQ_FRAME_SIZE: Only Z and T0-T15 are pushed to IRQ stack (17 registers).
 * GPRs (R3-R31, FP) are stored directly to pt_regs to avoid double-storage.
 */
.set IRQ_FRAME_SIZE, 68   /* 17 words × 4 bytes */

/*
 * PUSH_IRQ_REG: Push a register onto the IRQ stack
 *
 * Uses INT_SP as the stack pointer. Decrements INT_SP by 4, then stores
 * the negated register value at [INT_SP].
 *
 * Pattern:
 *   INT_SP -= 4
 *   [INT_SP] = 0
 *   [INT_SP] -= reg  (stores -reg)
 */
.macro PUSH_IRQ_REG reg_addr
        .word   .Lconst_4, INT_SP, .+4                      /* INT_SP -= 4 */
        .word   INT_SP | INDIRECT, INT_SP | INDIRECT, .+4   /* [INT_SP] = 0 */
        .word   \reg_addr, INT_SP | INDIRECT, .+4          /* [INT_SP] = -reg */
.endm

/*
 * POP_IRQ_REG: Pop a register from the IRQ stack
 *
 * Restores the register from [INT_SP], then increments INT_SP by 4.
 * Since PUSH stores -reg, we restore by: reg = 0; reg -= [INT_SP]
 *
 * Pattern:
 *   reg = 0
 *   reg -= [INT_SP]  (reg = -(-reg) = reg)
 *   INT_SP += 4
 */
.macro POP_IRQ_REG reg_addr
        .word   \reg_addr, \reg_addr, .+4                 /* reg = 0 */
        .word   INT_SP | INDIRECT, \reg_addr, .+4          /* reg -= [INT_SP] = -(-orig) = orig */
        .word   .Lconst_neg4, INT_SP, .+4                   /* INT_SP += 4 */
.endm

/*
 * Interrupt entry point
 *
 * CRITICAL: Disable interrupts FIRST to prevent nested re-entry.
 * Then save the interrupted SP (which may be in an invalid state).
 *
 * INT_SP tracks the IRQ stack position for pushing/popping frames.
 */
subleq_irq_entry:
        /*
         * PHASE 0a: DISABLE INTERRUPTS IMMEDIATELY
         *
         * This MUST be first! Otherwise another interrupt could fire
         * before we've finished saving state, corrupting everything.
         *
         * Save m[0] to m[8] (INT_SAVED_HANDLER), then clear m[0].
         * Uses only INT_Z as scratch (address 224).
         */
        .word   INT_Z, INT_Z, .+4                   /* INT_Z = 0 */
        .word   INT_HANDLER, INT_Z, .+4              /* INT_Z = -handler */
        .word   INT_SAVED_HANDLER, INT_SAVED_HANDLER, .+4  /* m[8] = 0 */
        .word   INT_Z, INT_SAVED_HANDLER, .+4        /* m[8] = handler */
        .word   INT_HANDLER, INT_HANDLER, .+4         /* m[0] = 0 (disabled!) */

        /*
         * PHASE 0b: SAVE SP
         *
         * Now safe to save the interrupted SP. It may be garbage
         * (mid-reload), but we capture it as-is. SAVE_SP is at address 232
         * and is used by current_thread_info() to find the task's stack.
         *
         * Pattern: SAVE_SP = -SP (negated, like PUSH stores)
         */
        .word   SAVE_SP, SAVE_SP, .+4                 /* SAVE_SP = 0 */
        .word   REG_SP, SAVE_SP, .+4                  /* SAVE_SP = -SP */



        /*
         * PHASE 1: SAVE TEMPORARIES TO IRQ STACK
         *
         * Only Z and T0-T15 are saved to the IRQ stack. These registers
         * are NOT in pt_regs, so they must be saved/restored separately.
         *
         * GPRs (R3-R31, FP) are stored directly to pt_regs in Phase 2.
         * This eliminates double-storage and saves ~84 instructions.
         */

        /* Push Z (not in pt_regs) */
        PUSH_IRQ_REG REG_Z

        /* Push T0-T15 (not in pt_regs) */
        PUSH_IRQ_REG REG_T0
        PUSH_IRQ_REG REG_T1
        PUSH_IRQ_REG REG_T2
        PUSH_IRQ_REG REG_T3
        PUSH_IRQ_REG REG_T4
        PUSH_IRQ_REG REG_T5
        PUSH_IRQ_REG REG_T6
        PUSH_IRQ_REG REG_T7
        PUSH_IRQ_REG REG_T8
        PUSH_IRQ_REG REG_T9
        PUSH_IRQ_REG REG_T10
        PUSH_IRQ_REG REG_T11
        PUSH_IRQ_REG REG_T12
        PUSH_IRQ_REG REG_T13
        PUSH_IRQ_REG REG_T14
        PUSH_IRQ_REG REG_T15

        /*
         * Set hardware SP = INT_SP so C handler has valid stack.
         * After all pushes, INT_SP points to the top of our saved frame.
         */
        .word   REG_SP, REG_SP, .+4             /* SP = 0 */
        .word   INT_Z, INT_Z, .+4             /* INT_Z = 0 */
        .word   INT_SP, INT_Z, .+4             /* INT_Z = -INT_SP */
        .word   INT_Z, REG_SP, .+4             /* SP = INT_SP */

.Lsave_done:
        /*
         * PHASE 2: BUILD pt_regs ON IRQ STACK
         *
         * We allocate PT_SIZE (160) bytes on the IRQ stack and build a
         * pt_regs structure that C code can read and modify.
         *
         * CRITICAL: C code expects POSITIVE values in pt_regs fields.
         * Subleq's natural store pattern (subleq A, B) stores -A.
         * We use double-negation to store positive values:
         *   TEMP = -value; [dest] = -TEMP = +value
         *
         * The pt_regs is re-entrant because it's on the IRQ stack,
         * which grows with each nested interrupt.
         */

        /* Allocate pt_regs: SP -= PT_SIZE (160 bytes) */
        .word   .Lconst_pt_size, REG_SP, .+4
        /* NOTE: SP now points to pt_regs base. C calling convention preserves SP,
         * so after C calls return, SP still points to pt_regs. This is re-entrant
         * because each interrupt level has its own pt_regs on the IRQ stack. */

        /*
         * Fill pt_regs fields with POSITIVE values using double-negation.
         *
         * CRITICAL: We must populate ALL registers in pt_regs, not just the
         * signal-affected subset. This is because save_sigcontext() reads
         * ALL registers (r3-r31, fp, sp, ra, pc) when delivering a signal.
         * If we only populate a subset, the signal frame will contain garbage
         * for the unpopulated registers, corrupting the interrupted context.
         *
         * pt_regs layout:
         *   r3-r19:     offsets 0-64
         *   r20:        offset 68
         *   r21-r24:    offsets 72-84
         *   r25-r31:    offsets 88-112
         *   fp:         offset 116
         *   sp:         offset 120
         *   ra:         offset 124
         *   pc:         offset 128
         *   orig_r20:   offset 132 (not needed for interrupts)
         *   syscall_nr: offset 136 (set to -1 for interrupts)
         *
         * NOTE: After PUSH_IRQ_REG, the hardware registers still contain their
         * original values (subleq reads but doesn't modify the A operand).
         * So we can read directly from REG_Rx to get the interrupted values.
         */

        /*
         * Use running pointer for pt_regs population.
         * Initialize INT_Z2 = SP (pt_regs base), then increment for each field.
         */

        /* Initialize running pointer: INT_Z2 = SP */
        .word   INT_Z2, INT_Z2, .+4              /* INT_Z2 = 0 */
        .word   INT_Z, INT_Z, .+4                /* INT_Z = 0 */
        .word   REG_SP, INT_Z, .+4               /* INT_Z = -SP */
        .word   INT_Z, INT_Z2, .+4               /* INT_Z2 = SP */

        /* Store r3 = REG_R3 (offset 0) */
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4  /* [ptr] = 0 */
        .word   INT_Z, INT_Z, .+4
        .word   REG_R3, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r4 (offset 4) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R4, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r5 (offset 8) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R5, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r6 (offset 12) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R6, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r7 (offset 16) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R7, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r8 (offset 20) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R8, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r9 (offset 24) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R9, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r10 (offset 28) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R10, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r11 (offset 32) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R11, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r12 (offset 36) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R12, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r13 (offset 40) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R13, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r14 (offset 44) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R14, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r15 (offset 48) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R15, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r16 (offset 52) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R16, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r17 (offset 56) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R17, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r18 (offset 60) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R18, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r19 (offset 64) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R19, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r20 (offset 68) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R20, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r21 (offset 72) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R21, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r22 (offset 76) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R22, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r23 (offset 80) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R23, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r24 (offset 84) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R24, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r25 (offset 88) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R25, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r26 (offset 92) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R26, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r27 (offset 96) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R27, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r28 (offset 100) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R28, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r29 (offset 104) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R29, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r30 (offset 108) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R30, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store r31 (offset 112) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_R31, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store fp (offset 116) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_FP, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store sp = original SP (offset 120) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        /* SAVE_SP contains -original_sp, so store -(-original_sp) = +original_sp */
        .word   SAVE_SP, INT_Z2 | INDIRECT, .+4

        /* Store ra (offset 124) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_RA, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Store pc = INT_SAVED_PC (offset 128) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_SAVED_PC, INT_Z, .+4
        .word   INT_Z, INT_Z2 | INDIRECT, .+4

        /* Skip orig_r20 (offset 132) - not used for interrupts */

        /* Store syscall_nr = -1 (offset 136) to mark as NOT a syscall */
        .word   .Lconst_neg8, INT_Z2, .+4        /* Advance by 8: 128 -> 136 */
        .word   INT_Z2 | INDIRECT, INT_Z2 | INDIRECT, .+4
        .word   .Lconst_1, INT_Z2 | INDIRECT, .+4  /* [addr] = 0 - 1 = -1 */


        /* Set R21 = pt_regs pointer (= SP) for the function call.
         * Using REG_SP directly instead of a global variable for re-entrancy. */
        .word   REG_R21, REG_R21, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_SP, INT_Z, .+4
        .word   INT_Z, REG_R21, .Lirq_call

.Lirq_call:
        /* STACK-BASED CALL to subleq_do_IRQ */
        .word   .Lconst_4, REG_SP, .Lcall_push1

.Lcall_push1:
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .Lcall_push2

.Lcall_push2:
        .word   INT_Z, INT_Z, .Lcall_push3
.Lcall_push3:
        .word   .Lirq_return_addr, INT_Z, .Lcall_push4

.Lcall_push4:
        .word   INT_Z, REG_SP | INDIRECT, .Lcall_jump

.Lcall_jump:
        .word   INT_Z, INT_Z, subleq_do_IRQ

        /*
         * PHASE 2b: WORK LOOP (ColdFire pattern)
         *
         * After subleq_do_IRQ returns, call subleq_do_work(regs) in a loop.
         * subleq_do_work returns:
         *   0 = no work done, safe to return
         *   non-zero = work was done, loop back to check for more
         *
         * R21 still contains pt_regs pointer (preserved by C calling convention).
         * R20 receives the return value from subleq_do_work.
         */
.Lirq_returned:

.Lwork_loop:
        /* Call subleq_do_work(regs) - reload R21 from SP (which is pt_regs).
         * Using REG_SP directly instead of a global variable for re-entrancy.
         * C calling convention preserves SP, so it still points to pt_regs. */
        .word   REG_R21, REG_R21, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_SP, INT_Z, .+4
        .word   INT_Z, REG_R21, .+4   /* R21 = pt_regs pointer */

        /* STACK-BASED CALL to subleq_do_work */
        .word   .Lconst_4, REG_SP, .+4         /* SP -= 4 */
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4  /* [SP] = 0 */
        .word   INT_Z, INT_Z, .+4
        .word   .Lwork_return_addr, INT_Z, .+4
        .word   INT_Z, REG_SP | INDIRECT, .+4  /* [SP] = return addr */
        .word   INT_Z, INT_Z, subleq_do_work

.Lwork_returned:
        /*
         * Check return value in R20.
         * If R20 != 0, loop back to .Lwork_loop
         * If R20 == 0, proceed to register restoration
         *
         * Subleq branch: subleq A, B, C jumps to C if m[B]-m[A] <= 0
         * We want: if R20 > 0 then loop, else continue
         * Equivalently: if R20 <= 0 then continue
         * So: subleq R20, ZERO, .Lno_more_work jumps if 0-R20 <= 0 (i.e., R20 >= 0)
         * But we need strict > 0 vs == 0 check.
         *
         * Simpler approach: if R20 == 0, continue. Otherwise loop.
         * Copy R20 to temp, check if zero.
         * Use: subleq REG_R20, TEMP, ... - if TEMP-R20 <= 0 (where TEMP=0)
         *      means -R20 <= 0, i.e., R20 >= 0. Still not right.
         *
         * Best: copy R20 to INT_Z2, then:
         *   subleq .Lconst_1, INT_Z2, .Lwork_loop
         * This does: INT_Z2 = INT_Z2 - 1
         * If original R20 was 1, INT_Z2 becomes 0, jump to loop (0 <= 0)
         * If original R20 was 0, INT_Z2 becomes -1, jump to loop (-1 <= 0)
         * Hmm, that always jumps.
         *
         * Alternative: use the fact that 0 is the only value where -X = X
         * Copy R20 to INT_Z2: INT_Z2 = -R20
         * Then subleq REG_R20, INT_Z2, .Lno_more_work
         * This does: INT_Z2 = INT_Z2 - R20 = -R20 - R20 = -2*R20
         * If R20=0: -2*0 = 0, jump (0 <= 0) -> correct, continue
         * If R20=1: -2*1 = -2, jump (-2 <= 0) -> wrong, we want to loop
         *
         * Simplest: explicit zero check using subtraction
         * INT_Z2 = 0 - R20 = -R20
         * Then: subleq INT_Z2, .Lconst_zero, ...
         * If R20=0: .Lconst_zero - (-0) = 0-0 = 0, jump
         * If R20=1: .Lconst_zero - (-1) = 0+1 = 1 > 0, no jump -> loop
         * But that modifies .Lconst_zero!
         *
         * Use fresh scratch:
         * SAVE_JMPTGT = 0
         * SAVE_JMPTGT -= (-R20) = +R20
         * subleq .Lconst_1, SAVE_JMPTGT, .Lno_more_work
         * If R20=0: SAVE_JMPTGT = 0, then 0-1 = -1, jump (-1 <= 0)
         * If R20=1: SAVE_JMPTGT = 1, then 1-1 = 0, jump (0 <= 0) -> wrong!
         *
         * Actually, we want to NOT jump if R20 > 0.
         * Subleq always jumps if result <= 0.
         * So to continue when R20 == 0 and loop when R20 > 0:
         *   - When R20 == 0: jump past loop
         *   - When R20 > 0: don't jump (fall through to loop)
         *
         * This is backwards from Subleq's default behavior.
         * 
         * Solution: Check if R20 > 0 by subtracting 1 from R20.
         * TEMP = R20
         * TEMP -= 1
         * If R20 was 0, TEMP = -1, use subleq to detect this
         * If R20 was 1, TEMP = 0
         * If R20 was 2+, TEMP > 0
         *
         * Actually simpler: subleq REG_Z, REG_R20, .Lwork_loop
         * This does: R20 = R20 - 0 = R20
         * Jumps if R20 <= 0.
         * So if R20 == 0, jumps (wrong - we want to continue)
         * If R20 > 0, doesn't jump (falls through) -> but we want to loop!
         *
         * REVERSE the logic:
         * subleq REG_Z, REG_R20, .Lno_more_work
         * If R20 <= 0 (including == 0): jump to .Lno_more_work
         * If R20 > 0: fall through and unconditionally loop
         */

        /* Copy -R20 to INT_Z2 for check */
        .word   INT_Z2, INT_Z2, .+4
        .word   REG_R20, INT_Z2, .+4      /* INT_Z2 = -R20 */

        /* Check: if R20 <= 0 then no more work (R20 should only be 0 or positive) */
        /* We have INT_Z2 = -R20. If R20 >= 0 means -R20 <= 0 */
        /* subleq REG_Z, INT_Z2, .Lno_more_work */
        /* INT_Z2 = INT_Z2 - 0 = -R20, jumps if -R20 <= 0 (R20 >= 0) */
        /* But return is 0 for no work, 1 for work done - both are >= 0! */
        
        /* Different approach: R20 == 0 means done. R20 == 1 means loop. */
        /* INT_Z2 = 0 - R20 - 1 = -(R20+1) */
        /* If R20=0: -(0+1) = -1, jump because -1 <= 0 -> WRONG (should continue) */
        /* If R20=1: -(1+1) = -2, jump because -2 <= 0 -> WRONG (should loop) */

        /* Final approach: Check if -R20 == 0 directly */
        /* If INT_Z2 == 0 (meaning R20 == 0), go to no_more_work */
        /* subleq INT_Z2, REG_Z, C means Z -= INT_Z2, jump if Z <= 0 */
        /* But Z should stay 0. Not good. */

        /* CLEAR approach: Use the sign directly. */
        /* R20 == 0: jump forward to .Lno_more_work using unconditional */
        /* R20 != 0: loop back */
        /* To branch only if zero: check if subtracting 0 from -R20 <= 0 */
        /* That's always true when R20 >= 0. */

        /* Use modified jump target approach: */
        /* If R20 == 0: INT_Z2 = 0, test for zero */
        /* If R20 != 0: INT_Z2 = negative, still <= 0 */
        /* ALL cases would jump. Need a different check. */

        /* FINAL: Use two branches. */
        /* First test if R20 <= 0 (go to no_more_work). */
        /* Otherwise unconditionally loop. */
        /* subleq REG_Z, REG_R20, .Lno_more_work_check */
        /* This: R20 = R20 - 0 = R20, jumps if R20 <= 0 */

        .word   REG_Z, REG_R20, .Lno_more_work  /* If R20 <= 0, go to restore */
        /* R20 > 0, more work was done, loop back */
        .word   INT_Z, INT_Z, .Lwork_loop

.Lno_more_work:


        /*
         * OPTIMIZED: Use running pointer for PC/SP reading.
         * Initialize INT_Z2 = SP + 120, read sp, advance +8, read pc.
         */

        /* Initialize running pointer: INT_Z2 = SP + 120 */
        .word   INT_Z2, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_SP, INT_Z, .+4
        .word   INT_Z, INT_Z2, .+4
        .word   .Lconst_neg120, INT_Z2, .+4

        /* Read pt_regs->sp (offset 120) into SAVE_SP for SP restore */
        /* SAVE_SP needs to contain -sp for the restore (subleq(SAVE_SP, REG_SP) gives +sp) */
        .word   SAVE_SP, SAVE_SP, .+4
        .word   INT_Z2 | INDIRECT, SAVE_SP, .+4  /* SAVE_SP = -sp (correct for restore) */

        /* Advance pointer by 8: INT_Z2 += 8 (120 -> 128) */
        .word   .Lconst_neg8, INT_Z2, .+4

        /* Read pt_regs->pc (offset 128) into SAVE_JMPTGT for return jump */
        /* Using 2-negation pattern: INT_Z = -pc, SAVE_JMPTGT = +pc */
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4       /* INT_Z = -pc (1) */
        .word   SAVE_JMPTGT, SAVE_JMPTGT, .+4
        .word   INT_Z, SAVE_JMPTGT, .+4                   /* SAVE_JMPTGT = +pc (2) */




        /* Read pt_regs->r21 (offset 72) - will be loaded after POP sequence */
        /* Read pt_regs->r22 (offset 76) - will be loaded after POP sequence */
        /* Read pt_regs->r23 (offset 80) - will be loaded after POP sequence */
        /* Read pt_regs->ra (offset 124) - will be loaded after POP sequence */

        /*
         * PHASE 3a: POP TEMPORARIES FROM IRQ STACK
         *
         * Only T0-T15 and Z are restored from the IRQ stack.
         * GPRs (R3-R31, FP, RA) are restored from pt_regs.
         */

        /* Pop T15-T0 (reverse order of push) */
        POP_IRQ_REG REG_T15
        POP_IRQ_REG REG_T14
        POP_IRQ_REG REG_T13
        POP_IRQ_REG REG_T12
        POP_IRQ_REG REG_T11
        POP_IRQ_REG REG_T10
        POP_IRQ_REG REG_T9
        POP_IRQ_REG REG_T8
        POP_IRQ_REG REG_T7
        POP_IRQ_REG REG_T6
        POP_IRQ_REG REG_T5
        POP_IRQ_REG REG_T4
        POP_IRQ_REG REG_T3
        POP_IRQ_REG REG_T2
        POP_IRQ_REG REG_T1
        POP_IRQ_REG REG_T0

        /* Pop Z */
        POP_IRQ_REG REG_Z

        /*
         * PHASE 3b: RESTORE ALL GPRs FROM pt_regs
         *
         * Load r3-r31, fp, ra from pt_regs. These may have been modified
         * by signal delivery (particularly r21-r23, ra for signal handler).
         *
         * Use running pointer starting at offset 0 (r3).
         */

        /* Initialize running pointer: INT_Z2 = SP (pt_regs base) */
        .word   INT_Z2, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   REG_SP, INT_Z, .+4
        .word   INT_Z, INT_Z2, .+4

        /* Load R3 from pt_regs->r3 (offset 0) */
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R3, REG_R3, .+4
        .word   INT_Z, REG_R3, .+4

        /* Load R4 (offset 4) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R4, REG_R4, .+4
        .word   INT_Z, REG_R4, .+4

        /* Load R5 (offset 8) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R5, REG_R5, .+4
        .word   INT_Z, REG_R5, .+4

        /* Load R6 (offset 12) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R6, REG_R6, .+4
        .word   INT_Z, REG_R6, .+4

        /* Load R7 (offset 16) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R7, REG_R7, .+4
        .word   INT_Z, REG_R7, .+4

        /* Load R8 (offset 20) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R8, REG_R8, .+4
        .word   INT_Z, REG_R8, .+4

        /* Load R9 (offset 24) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R9, REG_R9, .+4
        .word   INT_Z, REG_R9, .+4

        /* Load R10 (offset 28) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R10, REG_R10, .+4
        .word   INT_Z, REG_R10, .+4

        /* Load R11 (offset 32) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R11, REG_R11, .+4
        .word   INT_Z, REG_R11, .+4

        /* Load R12 (offset 36) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R12, REG_R12, .+4
        .word   INT_Z, REG_R12, .+4

        /* Load R13 (offset 40) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R13, REG_R13, .+4
        .word   INT_Z, REG_R13, .+4

        /* Load R14 (offset 44) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R14, REG_R14, .+4
        .word   INT_Z, REG_R14, .+4

        /* Load R15 (offset 48) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R15, REG_R15, .+4
        .word   INT_Z, REG_R15, .+4

        /* Load R16 (offset 52) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R16, REG_R16, .+4
        .word   INT_Z, REG_R16, .+4

        /* Load R17 (offset 56) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R17, REG_R17, .+4
        .word   INT_Z, REG_R17, .+4

        /* Load R18 (offset 60) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R18, REG_R18, .+4
        .word   INT_Z, REG_R18, .+4

        /* Load R19 (offset 64) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R19, REG_R19, .+4
        .word   INT_Z, REG_R19, .+4

        /* Load R20 (offset 68) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R20, REG_R20, .+4
        .word   INT_Z, REG_R20, .+4

        /* Load R21 (offset 72) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R21, REG_R21, .+4
        .word   INT_Z, REG_R21, .+4

        /* Load R22 (offset 76) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R22, REG_R22, .+4
        .word   INT_Z, REG_R22, .+4

        /* Load R23 (offset 80) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R23, REG_R23, .+4
        .word   INT_Z, REG_R23, .+4

        /* Load R24 (offset 84) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R24, REG_R24, .+4
        .word   INT_Z, REG_R24, .+4

        /* Load R25 (offset 88) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R25, REG_R25, .+4
        .word   INT_Z, REG_R25, .+4

        /* Load R26 (offset 92) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R26, REG_R26, .+4
        .word   INT_Z, REG_R26, .+4

        /* Load R27 (offset 96) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R27, REG_R27, .+4
        .word   INT_Z, REG_R27, .+4

        /* Load R28 (offset 100) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R28, REG_R28, .+4
        .word   INT_Z, REG_R28, .+4

        /* Load R29 (offset 104) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R29, REG_R29, .+4
        .word   INT_Z, REG_R29, .+4

        /* Load R30 (offset 108) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R30, REG_R30, .+4
        .word   INT_Z, REG_R30, .+4

        /* Load R31 (offset 112) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_R31, REG_R31, .+4
        .word   INT_Z, REG_R31, .+4

        /* Load FP (offset 116) */
        .word   .Lconst_neg4, INT_Z2, .+4
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_FP, REG_FP, .+4
        .word   INT_Z, REG_FP, .+4

        /* Skip SP (offset 120) - already loaded into SAVE_SP above */

        /* Load RA (offset 124) */
        .word   .Lconst_neg8, INT_Z2, .+4    /* Skip SP: 116 -> 124 */
        .word   INT_Z, INT_Z, .+4
        .word   INT_Z2 | INDIRECT, INT_Z, .+4
        .word   REG_RA, REG_RA, .+4
        .word   INT_Z, REG_RA, .+4


        /* Restore SP from SAVE_SP (which contains -(pt_regs->sp)) */
        .word   REG_SP, REG_SP, .+4
        .word   SAVE_SP, REG_SP, .+4



.Lrestore_done:
        /* PHASE 4: RE-ENABLE INTERRUPTS AND RETURN */

        /* SAVE_JMPTGT now contains the (potentially modified) return PC */
.Ldo_jump:
.Lenable_irq:
        .word   INT_Z, INT_Z, .Lenable1
.Lenable1:
        .word   INT_SAVED_HANDLER, INT_Z, .Lenable2
.Lenable2:
        .word   INT_HANDLER, INT_HANDLER, .Lenable3
.Lenable3:
        .word   INT_Z, INT_HANDLER, .Ldo_return



.Ldo_return:
        .word   INT_Z, INT_Z, .Ldo_return2
.Ldo_return2:
        .word   INT_Z
        .word   INT_Z
        .word   SAVE_JMPTGT | INDIRECT

.Ljump_failed:
        .word   -4, .Lconst_char_I, .Lhang
.Lhang:
        .word   INT_Z, INT_Z, .Lhang

.Lirq_return_addr:
        .word   .Lirq_returned

.Lwork_return_addr:
        .word   .Lwork_returned

.Lconst_char_W:
        .word   87              /* 'W' for Work loop debug */

/* Subleq+ indirect addressing flag */
.set INDIRECT, 2

.size subleq_irq_entry, .-subleq_irq_entry


/*
 * ===========================================================================
 * Context Switch Implementation (RE-ENTRANT VERSION)
 * ===========================================================================
 *
 * __switch_to(prev, next) - Switch from prev task to next task
 *
 * Arguments:
 *   R21 = prev (struct task_struct *)
 *   R22 = next (struct task_struct *)
 *
 * Returns:
 *   R20 = prev
 *
 * This function uses Subleq+ indirect addressing to avoid self-modifying code,
 * making it fully re-entrant and safe for use when interrupts are enabled.
 *
 * The key technique is using the indirect flag (|2) on operands:
 *   - A|2 means: use m[A] as the actual A address (dereference)
 *   - B|2 means: use m[B] as the actual B address (dereference)
 *   - C|2 means: jump to m[C] instead of C
 *
 * This function:
 *   1. Pushes RA to prev's stack
 *   2. Saves SP to prev->thread.sp
 *   3. Loads SP from next->thread.sp
 *   4. Pops RA from next's stack
 *   5. Returns (to the return address saved by next's previous switch)
 */

/*
 * TASK_THREAD_SP and TASK_THREAD_FP are now generated in asm-offsets.h
 * and included via #include <asm/asm-offsets.h> at the top of this file.
 * This ensures the offsets are always correct regardless of kernel config
 * (e.g., CONFIG_PREEMPT=y adds fields to task_struct, shifting thread).
 */

/* Subleq+ indirect addressing flag (bit 1) */
.set INDIRECT, 2

.globl __switch_to
.type __switch_to, @function
__switch_to:
        /*
         * __switch_to(prev, next) - Context switch with full register save
         *
         * Arguments: R21 = prev, R22 = next
         * Returns: R20 = prev
         *
         * On entry, caller has pushed return address to stack at [SP].
         *
         * We allocate a switch_stack (96 bytes) BELOW the return address,
         * save all 24 callee-saved registers there, then save SP.
         *
         * On restore, we load SP, restore registers, then pop and jump to
         * the return address.
         *
         * Stack layout after save:
         *   [SP+96] = return address (pushed by caller)
         *   [SP+0..96] = switch_stack (25 registers, including R20)
         */

        /*
         * STEP 1: Allocate switch_stack: SP -= 100
         */
        .word   .Lconst_100, REG_SP, .Lsw_save_regs_start

        /*
         * STEP 2: Save callee-saved registers to switch_stack
         *
         * We save R3-R19 (17 regs) at offsets 0-64
         * then R20 (1 reg, for vfork) at offset 68
         * and R25-R31 (7 regs) at offsets 72-96
         *
         * For each register, we compute SP + offset into SW_Z2,
         * then store the register value there using indirect addressing.
         */
.Lsw_save_regs_start:
        /*
         * OPTIMIZED: Use running pointer in SW_Z2
         * Initialize SW_Z2 = SP - 4, then each save increments by 4
         * Reduces from 9 to 3 instructions per register
         */
        .word   SW_Z2, SW_Z2, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_SP, SW_Z, .+4
        .word   SW_Z, SW_Z2, .+4              /* SW_Z2 = SP */
        .word   .Lconst_4, SW_Z2, .+4       /* SW_Z2 = SP - 4 */

        /* Save R3 at [SP + 0] */
        .word   .Lconst_neg4, SW_Z2, .+4                          /* SW_Z2 += 4 */
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4       /* [SW_Z2] = 0 */
        .word   REG_R3, SW_Z2 | INDIRECT, .+4                  /* [SW_Z2] = -R3 */

        /* Save R4 at [SP + 4] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R4, SW_Z2 | INDIRECT, .+4

        /* Save R5 at [SP + 8] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R5, SW_Z2 | INDIRECT, .+4

        /* Save R6 at [SP + 12] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R6, SW_Z2 | INDIRECT, .+4

        /* Save R7 at [SP + 16] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R7, SW_Z2 | INDIRECT, .+4

        /* Save R8 at [SP + 20] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R8, SW_Z2 | INDIRECT, .+4

        /* Save R9 at [SP + 24] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R9, SW_Z2 | INDIRECT, .+4

        /* Save R10 at [SP + 28] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R10, SW_Z2 | INDIRECT, .+4

        /* Save R11 at [SP + 32] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R11, SW_Z2 | INDIRECT, .+4

        /* Save R12 at [SP + 36] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R12, SW_Z2 | INDIRECT, .+4

        /* Save R13 at [SP + 40] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R13, SW_Z2 | INDIRECT, .+4

        /* Save R14 at [SP + 44] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R14, SW_Z2 | INDIRECT, .+4

        /* Save R15 at [SP + 48] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R15, SW_Z2 | INDIRECT, .+4

        /* Save R16 at [SP + 52] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R16, SW_Z2 | INDIRECT, .+4

        /* Save R17 at [SP + 56] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R17, SW_Z2 | INDIRECT, .+4

        /* Save R18 at [SP + 60] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R18, SW_Z2 | INDIRECT, .+4

        /* Save R19 at [SP + 64] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R19, SW_Z2 | INDIRECT, .+4

        /* Save R20 at [SP + 68] - needed for vfork CLONE_VM fix */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R20, SW_Z2 | INDIRECT, .+4

        /* Save R25 at [SP + 72] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R25, SW_Z2 | INDIRECT, .+4

        /* Save R26 at [SP + 76] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R26, SW_Z2 | INDIRECT, .+4

        /* Save R27 at [SP + 80] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R27, SW_Z2 | INDIRECT, .+4

        /* Save R28 at [SP + 84] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R28, SW_Z2 | INDIRECT, .+4

        /* Save R29 at [SP + 88] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R29, SW_Z2 | INDIRECT, .+4

        /* Save R30 at [SP + 92] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R30, SW_Z2 | INDIRECT, .+4

        /* Save R31 at [SP + 96] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   REG_R31, SW_Z2 | INDIRECT, .Lsw_save_sp

        /*
         * STEP 3: Save SP to prev->thread.sp
         */
.Lsw_save_sp:
        /* Calculate &prev->thread.sp into SW_Z2 */
        .word   SW_Z, SW_Z, .+4
        .word   REG_R21, SW_Z, .+4
        .word   SW_Z2, SW_Z2, .+4
        .word   SW_Z, SW_Z2, .+4              /* SW_Z2 = prev */
        .word   .Lconst_neg_task_thread_sp, SW_Z2, .+4       /* SW_Z2 = &prev->thread.sp */
        /* Clear and store SP */
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_SP, SW_Z, .+4
        .word   SW_Z, SW_Z2 | INDIRECT, .Lsw_save_fp

        /*
         * STEP 3b: Save FP to prev->thread.fp
         */
.Lsw_save_fp:
        .word   SW_Z, SW_Z, .+4
        .word   REG_R21, SW_Z, .+4
        .word   SW_Z2, SW_Z2, .+4
        .word   SW_Z, SW_Z2, .+4
        .word   .Lconst_neg_task_thread_fp, SW_Z2, .+4    /* SW_Z2 = &prev->thread.fp */
        .word   SW_Z2 | INDIRECT, SW_Z2 | INDIRECT, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_FP, SW_Z, .+4
        .word   SW_Z, SW_Z2 | INDIRECT, .Lsw_update_current

        /*
         * STEP 4: Update subleq_current_task = next
         */
.Lsw_update_current:
        .word   SW_Z, SW_Z, .+4
        .word   REG_R22, SW_Z, .+4
        .word   subleq_current_task, subleq_current_task, .+4
        .word   SW_Z, subleq_current_task, .Lsw_update_kernel_sp

        /*
         * STEP 4b: Update subleq_kernel_sp for next task
         *
         * CRITICAL FIX: Without this, all tasks use init_task's kernel stack
         * for syscalls, causing corruption when multiple tasks make syscalls.
         *
         * Formula: subleq_kernel_sp = next->stack + KERNEL_SP_OFFSET
         * where KERNEL_SP_OFFSET = THREAD_SIZE - sizeof(pt_regs) - 1024
         */
.Lsw_update_kernel_sp:
        /* Load next->stack into SW_Z2 */
        .word   SW_Z, SW_Z, .+4
        .word   REG_R22, SW_Z, .+4                            /* SW_Z = -next */
        .word   SW_Z2, SW_Z2, .+4
        .word   SW_Z, SW_Z2, .+4                              /* SW_Z2 = next */
        .word   .Lconst_neg_task_stack, SW_Z2, .+4            /* SW_Z2 = &next->stack */
        /* Load [SW_Z2] (the stack page pointer) into SW_Z */
        .word   SW_Z, SW_Z, .+4
        .word   SW_Z2 | INDIRECT, SW_Z, .+4                   /* SW_Z = -next->stack */
        /* Compute kernel_sp = stack + KERNEL_SP_OFFSET */
        .word   SW_Z2, SW_Z2, .+4
        .word   SW_Z, SW_Z2, .+4                              /* SW_Z2 = next->stack */
        .word   .Lconst_neg_kernel_sp_offset, SW_Z2, .+4      /* SW_Z2 = stack + KERNEL_SP_OFFSET */
        /* Store to subleq_kernel_sp */
        .word   SW_Z, SW_Z, .+4
        .word   SW_Z2, SW_Z, .+4                              /* SW_Z = -kernel_sp */
        .word   subleq_kernel_sp, subleq_kernel_sp, .+4       /* clear */
        .word   SW_Z, subleq_kernel_sp, .Lsw_load_sp          /* store */

        /*
         * STEP 5: Load SP from next->thread.sp
         */
.Lsw_load_sp:
        .word   SW_Z, SW_Z, .+4
        .word   REG_R22, SW_Z, .+4
        .word   SW_Z2, SW_Z2, .+4
        .word   SW_Z, SW_Z2, .+4
        .word   .Lconst_neg_task_thread_sp, SW_Z2, .+4       /* SW_Z2 = &next->thread.sp */
        /* Load [SW_Z2] into SP */
        .word   SW_Z, SW_Z, .+4
        .word   SW_Z2 | INDIRECT, SW_Z, .+4
        .word   REG_SP, REG_SP, .+4
        .word   SW_Z, REG_SP, .Lsw_load_fp

        /*
         * STEP 5b: Load FP from next->thread.fp
         */
.Lsw_load_fp:
        .word   SW_Z, SW_Z, .+4
        .word   REG_R22, SW_Z, .+4
        .word   SW_Z2, SW_Z2, .+4
        .word   SW_Z, SW_Z2, .+4
        .word   .Lconst_neg_task_thread_fp, SW_Z2, .+4    /* SW_Z2 = &next->thread.fp */
        .word   SW_Z, SW_Z, .+4
        .word   SW_Z2 | INDIRECT, SW_Z, .+4
        .word   REG_FP, REG_FP, .+4
        .word   SW_Z, REG_FP, .Lsw_restore_regs_start

        /*
         * STEP 6: Restore callee-saved registers from switch_stack
         *
         * Similar to save, but loading from [SP + offset] into registers.
         */
.Lsw_restore_regs_start:
        /*
         * OPTIMIZED: Use running pointer in SW_Z2
         * Initialize SW_Z2 = SP - 4, then each restore increments by 4
         * Reduces from 9 to 3 instructions per register
         */
        .word   SW_Z2, SW_Z2, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_SP, SW_Z, .+4
        .word   SW_Z, SW_Z2, .+4              /* SW_Z2 = SP */
        .word   .Lconst_4, SW_Z2, .+4       /* SW_Z2 = SP - 4 */

        /* Restore R3 from [SP + 0] */
        .word   .Lconst_neg4, SW_Z2, .+4                          /* SW_Z2 += 4 */
        .word   REG_R3, REG_R3, .+4                             /* R3 = 0 */
        .word   SW_Z2 | INDIRECT, REG_R3, .+4                  /* R3 = -(-R3) = R3 */

        /* Restore R4 from [SP + 4] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R4, REG_R4, .+4
        .word   SW_Z2 | INDIRECT, REG_R4, .+4

        /* Restore R5 from [SP + 8] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R5, REG_R5, .+4
        .word   SW_Z2 | INDIRECT, REG_R5, .+4

        /* Restore R6 from [SP + 12] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R6, REG_R6, .+4
        .word   SW_Z2 | INDIRECT, REG_R6, .+4

        /* Restore R7 from [SP + 16] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R7, REG_R7, .+4
        .word   SW_Z2 | INDIRECT, REG_R7, .+4

        /* Restore R8 from [SP + 20] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R8, REG_R8, .+4
        .word   SW_Z2 | INDIRECT, REG_R8, .+4

        /* Restore R9 from [SP + 24] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R9, REG_R9, .+4
        .word   SW_Z2 | INDIRECT, REG_R9, .+4

        /* Restore R10 from [SP + 28] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R10, REG_R10, .+4
        .word   SW_Z2 | INDIRECT, REG_R10, .+4

        /* Restore R11 from [SP + 32] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R11, REG_R11, .+4
        .word   SW_Z2 | INDIRECT, REG_R11, .+4

        /* Restore R12 from [SP + 36] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R12, REG_R12, .+4
        .word   SW_Z2 | INDIRECT, REG_R12, .+4

        /* Restore R13 from [SP + 40] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R13, REG_R13, .+4
        .word   SW_Z2 | INDIRECT, REG_R13, .+4

        /* Restore R14 from [SP + 44] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R14, REG_R14, .+4
        .word   SW_Z2 | INDIRECT, REG_R14, .+4

        /* Restore R15 from [SP + 48] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R15, REG_R15, .+4
        .word   SW_Z2 | INDIRECT, REG_R15, .+4

        /* Restore R16 from [SP + 52] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R16, REG_R16, .+4
        .word   SW_Z2 | INDIRECT, REG_R16, .+4

        /* Restore R17 from [SP + 56] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R17, REG_R17, .+4
        .word   SW_Z2 | INDIRECT, REG_R17, .+4

        /* Restore R18 from [SP + 60] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R18, REG_R18, .+4
        .word   SW_Z2 | INDIRECT, REG_R18, .+4

        /* Restore R19 from [SP + 64] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R19, REG_R19, .+4
        .word   SW_Z2 | INDIRECT, REG_R19, .+4

        /* Restore R20 from [SP + 68] - needed for vfork CLONE_VM fix */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R20, REG_R20, .+4
        .word   SW_Z2 | INDIRECT, REG_R20, .+4

        /* Restore R25 from [SP + 72] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R25, REG_R25, .+4
        .word   SW_Z2 | INDIRECT, REG_R25, .+4

        /* Restore R26 from [SP + 76] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R26, REG_R26, .+4
        .word   SW_Z2 | INDIRECT, REG_R26, .+4

        /* Restore R27 from [SP + 80] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R27, REG_R27, .+4
        .word   SW_Z2 | INDIRECT, REG_R27, .+4

        /* Restore R28 from [SP + 84] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R28, REG_R28, .+4
        .word   SW_Z2 | INDIRECT, REG_R28, .+4

        /* Restore R29 from [SP + 88] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R29, REG_R29, .+4
        .word   SW_Z2 | INDIRECT, REG_R29, .+4

        /* Restore R30 from [SP + 92] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R30, REG_R30, .+4
        .word   SW_Z2 | INDIRECT, REG_R30, .+4

        /* Restore R31 from [SP + 96] */
        .word   .Lconst_neg4, SW_Z2, .+4
        .word   REG_R31, REG_R31, .+4
        .word   SW_Z2 | INDIRECT, REG_R31, .Lsw_restore_done

.Lsw_restore_done:

        /*
         * STEP 7: Deallocate switch_stack: SP += 100
         */
        .word   .Lconst_neg100, REG_SP, .Lsw_set_retval

        /*
         * STEP 8: Set return value R20 = prev (R21)
         */
.Lsw_set_retval:
        .word   SW_Z, SW_Z, .+4
        .word   REG_R21, SW_Z, .+4
        .word   REG_R20, REG_R20, .+4
        .word   SW_Z, REG_R20, .Lsw_pop_ra

        /*
         * STEP 9: Pop return address and return
         *
         * Now SP points to the return address (at old SP+96 = retpc slot).
         */
.Lsw_pop_ra:
        .word   SW_Z, SW_Z, .+4
        .word   REG_SP | INDIRECT, SW_Z, .+4   /* SW_Z = -[SP] */
        .word   REG_RA, REG_RA, .+4
        .word   SW_Z, REG_RA, .+4              /* RA = [SP] */
        .word   .Lconst_neg4, REG_SP, .Lsw_return  /* SP += 4 */

        /*
         * STEP 10: Jump to return address
         */
.Lsw_return:
        /* Jump directly to [RA] */
        .word   SW_Z, SW_Z, .+4
        .word   SW_Z
        .word   SW_Z
        .word   REG_RA | INDIRECT

.Lsw_ra_copy:
        .word   0       /* Temp storage for RA */
.Lsw_syscall_ret_addr:
        .word   .Lsyscall_c_return   /* Address of syscall return point (BAD if parent returns here) */
.Lsw_ret_from_fork_addr:
        .word   ret_from_fork        /* Address of ret_from_fork (RF if parent returns here) */

.size __switch_to, .-__switch_to

/*
 * ret_from_fork - Entry point for new threads (RE-ENTRANT VERSION)
 *
 * When a new thread is scheduled for the first time, __switch_to returns
 * here. R20 contains the prev task pointer (returned by __switch_to).
 *
 * This function checks pt_regs.r3 to determine if this is a kernel or user thread:
 *   - r3 != 0: Kernel thread - call kernel_thread_helper(prev)
 *   - r3 == 0: User thread - call ret_to_user_prep(prev), then jump to userspace
 *
 * Uses Subleq+ indirect addressing for all memory operations.
 */
.globl ret_from_fork
.type ret_from_fork, @function
ret_from_fork:
        /*
         * R20 contains prev (from __switch_to's return value)
         * We need to pass it as the first argument (R21).
         * 
         * First, check if this is a kernel thread or user thread by reading r3 from pt_regs.
         * pt_regs is at the top of the kernel stack. After __switch_to pops the return
         * address from the stack, SP points to pt_regs (since we push ret_from_fork just
         * below pt_regs in copy_thread).
         *
         * pt_regs.r3 is at offset 0 from pt_regs, so [SP] = r3.
         */

        /* Copy R20 to R21: R21 = R20 (will be used as argument to either function) */
        .word   REG_R21, REG_R21, .Lrff_copy1   /* R21 = 0 */
.Lrff_copy1:
        .word   SW_Z, SW_Z, .Lrff_copy2
.Lrff_copy2:
        .word   REG_R20, SW_Z, .Lrff_copy3     /* SW_Z = -R20 */
.Lrff_copy3:
        .word   SW_Z, REG_R21, .Lrff_check_r3  /* R21 = R20 = prev */

        /*
         * Read pt_regs.r3 from [SP] (offset 0) to check kernel/user thread.
         * SW_Z2 will hold r3 value for comparison.
         */
.Lrff_check_r3:
        .word   SW_Z, SW_Z, .Lrff_check_r3_1
.Lrff_check_r3_1:
        /* Load [SP] into SW_Z using indirect addressing */
        /* subleq(SP|I, SW_Z, next) does: SW_Z -= m[SP] => SW_Z = -r3 */
        .word   REG_SP | INDIRECT, SW_Z, .Lrff_check_r3_2
.Lrff_check_r3_2:
        /* Now SW_Z = -r3. If r3 == 0, SW_Z == 0. */
        /* subleq(A, B, C) branches to C if B <= 0 after subtraction */
        /* We want to branch if r3 == 0, i.e., if SW_Z == 0 */
        /* Test: if SW_Z == 0, then 0 - 0 <= 0, so we branch */
        /* But we need to test SW_Z itself, not subtract something from it */
        
        /* Check if SW_Z == 0 (which means r3 == 0 => user thread) */
        /* We use: subleq(SW_Z, ZERO, user_thread_path) - if SW_Z <= 0, branch */
        /* But since SW_Z = -r3, if r3 > 0 then SW_Z < 0, so always branches! */
        /* We need a different approach. */
        
        /* Alternative: Check if SW_Z != 0 (kernel thread) */
        /* Actually let's be more direct: check if [SP] (r3) is 0 */
        /* Negate back: SW_Z2 = -SW_Z = r3 */
        .word   SW_Z2, SW_Z2, .Lrff_check_r3_3
.Lrff_check_r3_3:
        .word   SW_Z, SW_Z2, .Lrff_check_r3_4    /* SW_Z2 = -SW_Z = r3 */
.Lrff_check_r3_4:
        /* Now SW_Z2 = r3. Test if r3 == 0 (user thread) or r3 != 0 (kernel thread) */
        /* subleq(SW_Z2, ZERO, target) - branches to target if 0 - SW_Z2 <= 0 */
        /* i.e., branches if -SW_Z2 <= 0, i.e., branches if SW_Z2 >= 0 */
        /* This will branch for r3 >= 0, which is always true for valid pointers... */
        
        /* Let's use a simpler approach: test if r3 == 0 using subtraction */
        /* If SW_Z2 == 0, then subleq(SW_Z2, SW_Z2, fallthrough) will NOT branch */
        /* because 0 - 0 = 0, and 0 <= 0, so it DOES branch! */
        
        /* Use the zero_check pattern from SubleqAsmPrinter: */
        /* To check if X == 0: */
        /*   subleq(X, Z, label_if_positive_or_zero)  -- branches if -X <= 0 => X >= 0 */
        /*   subleq(Z, Z, label_if_negative)          -- unconditional (X was negative) */
        /* label_if_positive_or_zero: */
        /*   subleq(Z, X, label_if_zero)              -- branches if X - 0 <= 0 => X <= 0 */
        /*   ; fallthrough means X > 0 */
        /* label_if_zero: (both <= 0 and >= 0 means == 0) */
        
        /* For our purpose: if r3 == 0 => user thread, if r3 != 0 => kernel thread */
        /* SW_Z2 = r3 */
        
        /* Step 1: if r3 < 0, it's a kernel thread (valid function pointer) */
        .word   SW_Z2, SW_Z, .Lrff_check_nonneg   /* Z -= r3; branches if Z <= 0 after, i.e., -r3 <= 0, i.e., r3 >= 0 */
        /* If we get here, r3 < 0. But pointers are positive... this is kernel thread */
        .word   SW_Z, SW_Z, .Lrff_kernel_thread

.Lrff_check_nonneg:
        /* r3 >= 0. Now check if r3 == 0 or r3 > 0 */
        /* Clear SW_Z first */
        .word   SW_Z, SW_Z, .Lrff_check_nonneg2
.Lrff_check_nonneg2:
        /* subleq(Z, r3_copy, target) - branches if r3 - 0 <= 0 => r3 <= 0 */
        /* Since we know r3 >= 0, this branches iff r3 == 0 */
        /* Use SW_Z2 which still holds r3 */
        .word   SW_Z, SW_Z2, .Lrff_user_thread   /* branches if r3 <= 0 (since r3 >= 0, this means r3 == 0) */
        /* Fall through: r3 > 0, it's a kernel thread */

.Lrff_kernel_thread:
        /*
         * KERNEL THREAD PATH
         * Call kernel_thread_helper(prev) - R21 already contains prev
         */
        /* Push return address onto stack using indirect addressing */
        .word   .Lconst_4, REG_SP, .Lrff_kpush1  /* SP -= 4 */

.Lrff_kpush1:
        /* Clear [SP] using indirect addressing */
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .Lrff_kpush2

.Lrff_kpush2:
        /* Store loop address to [SP] (kernel threads should never return) */
        .word   SW_Z, SW_Z, .Lrff_kpush3
.Lrff_kpush3:
        .word   .Lrff_loop_addr, SW_Z, .Lrff_kpush4  /* SW_Z = -loop_addr */
.Lrff_kpush4:
        /* [SP] -= SW_Z => [SP] = loop_addr */
        .word   SW_Z, REG_SP | INDIRECT, .Lrff_kjump

.Lrff_kjump:
        /* Jump to kernel_thread_helper */
        .word   SW_Z, SW_Z, kernel_thread_helper

.Lrff_user_thread:
        /*
         * USER THREAD PATH
         *
         * Call ret_to_user_prep(prev) which will:
         * 1. Call schedule_tail(prev) to finish context switch
         * 2. Return pointer to pt_regs in R20
         *
         * Then we read directly from pt_regs:
         *   pt_regs->r20 at offset 68 = syscall return value (0 for fork child)
         *   pt_regs->sp  at offset 88 = user stack pointer  
         *   pt_regs->pc  at offset 96 = user PC to return to
         *
         * This ensures no C code can clobber these critical values.
         */
        /* Push return address for ret_to_user_prep */
        .word   .Lconst_4, REG_SP, .Lrff_upush1  /* SP -= 4 */

.Lrff_upush1:
        /* Clear [SP] using indirect addressing */
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .Lrff_upush2

.Lrff_upush2:
        /* Store .Lrff_user_return to [SP] */
        .word   SW_Z, SW_Z, .Lrff_upush3
.Lrff_upush3:
        .word   .Lrff_user_ret_addr, SW_Z, .Lrff_upush4  /* SW_Z = -return_addr */
.Lrff_upush4:
        /* [SP] -= SW_Z => [SP] = return_addr */
        .word   SW_Z, REG_SP | INDIRECT, .Lrff_ujump

.Lrff_ujump:
        /* Jump to ret_to_user_prep */
        .word   SW_Z, SW_Z, ret_to_user_prep

.Lrff_user_return:
        /*
         * ret_to_user_prep has returned with R20 = pointer to pt_regs.
         *
         * pt_regs layout (offsets from base, after adding R25-R31):
         *   r3-r19:  offsets 0-64
         *   r20:     offset 68 (return value, 0 for fork child)
         *   r21-r24: offsets 72-84
         *   r25-r31: offsets 88-112
         *   fp:      offset 116
         *   sp:      offset 120
         *   ra:      offset 124
         *   pc:      offset 128
         *
         * We need to restore ALL GPRs (R3-R19, R21-R31) from pt_regs so the
         * child has the same register values as the parent.
         *
         * Order of restoration:
         * 1. First restore R3-R19, R21-R31 while we can still use R20 as the base
         * 2. Load PC into SW_Z2 (we'll jump to this)
         * 3. Load SP, FP
         * 4. Load R20 last (since we're using it as pt_regs pointer)
         * 5. Jump to the saved PC
         */

        /*
         * STEP 0: Restore all GPRs from pt_regs (except R20 which is our base)
         *
         * For each register Rn at offset N:
         *   1. RA = R20 + N (calculate address)
         *   2. Rn = [RA] (load value)
         *
         * We use RA as scratch since it will be overwritten anyway.
         * SW_Z is also available.
         */

        /*
         * OPTIMIZED: Use RA as running pointer
         * Initialize RA = R20 - 4, then increment by 4 for each register
         * Skip R20 (offset 68) by adding 8 instead of 4
         * Reduces from 9 to 5 instructions per register
         */
        .word   SW_Z, SW_Z, .+4
        .word   REG_R20, SW_Z, .+4
        .word   REG_RA, REG_RA, .+4
        .word   SW_Z, REG_RA, .+4                /* RA = R20 */
        .word   .Lconst_4, REG_RA, .+4        /* RA = R20 - 4 */

        /* --- Restore R3 (offset 0) --- */
        .word   .Lconst_neg4, REG_RA, .+4           /* RA += 4 -> R20+0 */
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4     /* SW_Z = -[RA] */
        .word   REG_R3, REG_R3, .+4
        .word   SW_Z, REG_R3, .+4                /* R3 = [RA] */

        /* --- Restore R4 (offset 4) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R4, REG_R4, .+4
        .word   SW_Z, REG_R4, .+4

        /* --- Restore R5 (offset 8) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R5, REG_R5, .+4
        .word   SW_Z, REG_R5, .+4

        /* --- Restore R6 (offset 12) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R6, REG_R6, .+4
        .word   SW_Z, REG_R6, .+4

        /* --- Restore R7 (offset 16) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R7, REG_R7, .+4
        .word   SW_Z, REG_R7, .+4

        /* --- Restore R8 (offset 20) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R8, REG_R8, .+4
        .word   SW_Z, REG_R8, .+4

        /* --- Restore R9 (offset 24) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R9, REG_R9, .+4
        .word   SW_Z, REG_R9, .+4

        /* --- Restore R10 (offset 28) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R10, REG_R10, .+4
        .word   SW_Z, REG_R10, .+4

        /* --- Restore R11 (offset 32) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R11, REG_R11, .+4
        .word   SW_Z, REG_R11, .+4

        /* --- Restore R12 (offset 36) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R12, REG_R12, .+4
        .word   SW_Z, REG_R12, .+4

        /* --- Restore R13 (offset 40) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R13, REG_R13, .+4
        .word   SW_Z, REG_R13, .+4

        /* --- Restore R14 (offset 44) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R14, REG_R14, .+4
        .word   SW_Z, REG_R14, .+4

        /* --- Restore R15 (offset 48) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R15, REG_R15, .+4
        .word   SW_Z, REG_R15, .+4

        /* --- Restore R16 (offset 52) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R16, REG_R16, .+4
        .word   SW_Z, REG_R16, .+4

        /* --- Restore R17 (offset 56) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R17, REG_R17, .+4
        .word   SW_Z, REG_R17, .+4

        /* --- Restore R18 (offset 60) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R18, REG_R18, .+4
        .word   SW_Z, REG_R18, .+4

        /* --- Restore R19 (offset 64) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R19, REG_R19, .+4
        .word   SW_Z, REG_R19, .+4

        /* --- Skip R20 (offset 68) - add 8 to skip it --- */

        /* --- Restore R21 (offset 72) --- */
        .word   .Lconst_neg8, REG_RA, .+4           /* RA += 8 (skip R20) -> R20+72 */
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R21, REG_R21, .+4
        .word   SW_Z, REG_R21, .+4

        /* --- Restore R22 (offset 76) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R22, REG_R22, .+4
        .word   SW_Z, REG_R22, .+4

        /* --- Restore R23 (offset 80) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R23, REG_R23, .+4
        .word   SW_Z, REG_R23, .+4

        /* --- Restore R24 (offset 84) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R24, REG_R24, .+4
        .word   SW_Z, REG_R24, .+4

        /* --- Restore R25 (offset 88) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R25, REG_R25, .+4
        .word   SW_Z, REG_R25, .+4

        /* --- Restore R26 (offset 92) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R26, REG_R26, .+4
        .word   SW_Z, REG_R26, .+4

        /* --- Restore R27 (offset 96) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R27, REG_R27, .+4
        .word   SW_Z, REG_R27, .+4

        /* --- Restore R28 (offset 100) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R28, REG_R28, .+4
        .word   SW_Z, REG_R28, .+4

        /* --- Restore R29 (offset 104) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R29, REG_R29, .+4
        .word   SW_Z, REG_R29, .+4

        /* --- Restore R30 (offset 108) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R30, REG_R30, .+4
        .word   SW_Z, REG_R30, .+4

        /* --- Restore R31 (offset 112) --- */
        .word   .Lconst_neg4, REG_RA, .+4
        .word   SW_Z, SW_Z, .+4
        .word   REG_RA | INDIRECT, SW_Z, .+4
        .word   REG_R31, REG_R31, .+4
        .word   SW_Z, REG_R31, .+4

        /*
         * Step 1: Calculate &pt_regs->pc (R20 + 128) and load into REG_T15
         *
         * CRITICAL: We use REG_T15 (a T-register) instead of SW_Z2 (a global)
         * because T-registers are preserved across interrupts. If a context
         * switch occurs before the final jump, SW_Z2 would be clobbered.
         */
        .word   SW_Z, SW_Z, .Lrff_load_pc1
.Lrff_load_pc1:
        .word   REG_R20, SW_Z, .Lrff_load_pc2        /* SW_Z = -R20 */
.Lrff_load_pc2:
        .word   REG_T15, REG_T15, .Lrff_load_pc3
.Lrff_load_pc3:
        .word   SW_Z, REG_T15, .Lrff_load_pc4         /* T15 = R20 (pt_regs base) */
.Lrff_load_pc4:
        .word   .Lconst_neg128, REG_T15, .Lrff_load_pc5  /* T15 = R20 + 128 = &pt_regs->pc */
.Lrff_load_pc5:
        /* Load [T15] into SW_Z using indirect addressing */
        .word   SW_Z, SW_Z, .Lrff_load_pc6
.Lrff_load_pc6:
        .word   REG_T15 | INDIRECT, SW_Z, .Lrff_load_pc7  /* SW_Z = -pc */
.Lrff_load_pc7:
        .word   REG_T15, REG_T15, .Lrff_load_pc8
.Lrff_load_pc8:
        .word   SW_Z, REG_T15, .Lrff_load_sp          /* T15 = pc (user entry point) */

        /*
         * Step 2: Load pt_regs->sp (R20 + 120) into hardware SP
         */
.Lrff_load_sp:
        .word   SW_Z, SW_Z, .Lrff_load_sp1
.Lrff_load_sp1:
        .word   REG_R20, SW_Z, .Lrff_load_sp2        /* SW_Z = -R20 */
.Lrff_load_sp2:
        /* Calculate R20 + 92 into a temp location - reuse RA as scratch */
        .word   REG_RA, REG_RA, .Lrff_load_sp3
.Lrff_load_sp3:
        .word   SW_Z, REG_RA, .Lrff_load_sp4         /* RA = R20 */
.Lrff_load_sp4:
        .word   .Lconst_neg120, REG_RA, .Lrff_load_sp5   /* RA = R20 + 120 = &pt_regs->sp */
.Lrff_load_sp5:
        /* Load [RA] into SW_Z */
        .word   SW_Z, SW_Z, .Lrff_load_sp6
.Lrff_load_sp6:
        .word   REG_RA | INDIRECT, SW_Z, .Lrff_load_sp7  /* SW_Z = -sp */
.Lrff_load_sp7:
        /* Set hardware SP = -SW_Z = sp */
        .word   REG_SP, REG_SP, .Lrff_load_sp8
.Lrff_load_sp8:
        .word   SW_Z, REG_SP, .Lrff_load_fp          /* SP = user sp */

        /*
         * Step 3: Load pt_regs->fp (R20 + 116) into hardware FP
         * This is CRITICAL - the child needs the parent's frame pointer!
         */
.Lrff_load_fp:
        .word   SW_Z, SW_Z, .Lrff_load_fp1
.Lrff_load_fp1:
        .word   REG_R20, SW_Z, .Lrff_load_fp2        /* SW_Z = -R20 */
.Lrff_load_fp2:
        .word   REG_RA, REG_RA, .Lrff_load_fp3
.Lrff_load_fp3:
        .word   SW_Z, REG_RA, .Lrff_load_fp4         /* RA = R20 */
.Lrff_load_fp4:
        .word   .Lconst_neg116, REG_RA, .Lrff_load_fp5   /* RA = R20 + 116 = &pt_regs->fp */
.Lrff_load_fp5:
        /* Load [RA] into SW_Z */
        .word   SW_Z, SW_Z, .Lrff_load_fp6
.Lrff_load_fp6:
        .word   REG_RA | INDIRECT, SW_Z, .Lrff_load_fp7  /* SW_Z = -fp */
.Lrff_load_fp7:
        /* Set hardware FP = -SW_Z = fp */
        .word   REG_FP, REG_FP, .Lrff_load_fp8
.Lrff_load_fp8:
        .word   SW_Z, REG_FP, .Lrff_load_r20         /* FP = user fp */

        /*
         * Step 4: Load pt_regs->r20 (R20 + 68) into hardware R20
         * This is the fork return value (0 for child)
         */
.Lrff_load_r20:
        /* First save the current R20 (pt_regs pointer) to SW_Z temporarily */
        .word   SW_Z, SW_Z, .Lrff_load_r20_1
.Lrff_load_r20_1:
        .word   REG_R20, SW_Z, .Lrff_load_r20_2      /* SW_Z = -R20 (save pt_regs ptr) */
.Lrff_load_r20_2:
        /* Calculate &pt_regs->r20 using RA as scratch */
        .word   REG_RA, REG_RA, .Lrff_load_r20_3
.Lrff_load_r20_3:
        .word   SW_Z, REG_RA, .Lrff_load_r20_4       /* RA = R20 (pt_regs base) */
.Lrff_load_r20_4:
        .word   .Lconst_neg68, REG_RA, .Lrff_load_r20_5 /* RA = R20 + 68 = &pt_regs->r20 */
.Lrff_load_r20_5:
        /* Load [RA] into SW_Z */
        .word   SW_Z, SW_Z, .Lrff_load_r20_6
.Lrff_load_r20_6:
        .word   REG_RA | INDIRECT, SW_Z, .Lrff_load_r20_7  /* SW_Z = -r20_value */
.Lrff_load_r20_7:
        /* Set hardware R20 = -SW_Z = r20_value (0 for child) */
        .word   REG_R20, REG_R20, .Lrff_load_r20_8
.Lrff_load_r20_8:
        .word   SW_Z, REG_R20, .Lrff_jump_user       /* R20 = fork return value */

        /*
         * Step 5: Jump to user PC (saved in REG_T15)
         *
         * REG_T15 | INDIRECT = 220 | 2 = 222
         */
.Lrff_jump_user:
        /* Indirect jump: subleq(Z, Z, T15|I) jumps to m[T15] */
        .word   SW_Z
        .word   SW_Z
        .word   REG_T15 | INDIRECT

.Lrff_loop:
        /* Infinite loop - should never reach here for kernel threads */
        .word   SW_Z, SW_Z, .Lrff_loop

.Lrff_loop_addr:
        .word   .Lrff_loop
.Lrff_user_ret_addr:
        .word   .Lrff_user_return

.size ret_from_fork, .-ret_from_fork

/*
 * jump_to_userspace - Jump to userspace WITHOUT using the C calling convention
 *
 * This function is called from kernel_thread_helper when a kernel thread
 * has called kernel_execve() and needs to transition to userspace.
 *
 * Unlike a normal C function call, this does NOT push a return address,
 * which would corrupt the user stack that has been set up with argc/argv/envp.
 *
 * Arguments (C calling convention - they were pushed by caller):
 *   R21 = pc (userspace entry point)
 *   R22 = sp (userspace stack pointer)
 *
 * This function never returns.
 */
.globl jump_to_userspace
.type jump_to_userspace, @function
jump_to_userspace:
        /*
         * On entry, the caller has pushed a return address to the stack.
         * We don't need it since we're jumping to userspace.
         * First, pop and discard it: SP += 4
         */
        .word   .Lconst_neg4, REG_SP, .Ljtu_set_ra

        /*
         * Set RA to a halt loop as a safety backstop.
         * If the user binary returns (which it shouldn't), it will
         * jump to this loop instead of crashing on RA=0.
         */
.Ljtu_set_ra:
        .word   REG_RA, REG_RA, .Ljtu_set_ra1
.Ljtu_set_ra1:
        .word   SW_Z, SW_Z, .Ljtu_set_ra2
.Ljtu_set_ra2:
        .word   .Ljtu_halt_addr, SW_Z, .Ljtu_set_ra3  /* SW_Z = -halt_loop_addr */
.Ljtu_set_ra3:
        .word   SW_Z, REG_RA, .Ljtu_set_sp  /* RA = halt_loop_addr */

        /*
         * Set SP = R22 (the user stack pointer)
         */
.Ljtu_set_sp:
        /* Clear SP */
        .word   REG_SP, REG_SP, .Ljtu_set_sp1
.Ljtu_set_sp1:
        /* Get -R22 into SW_Z */
        .word   SW_Z, SW_Z, .Ljtu_set_sp2
.Ljtu_set_sp2:
        .word   REG_R22, SW_Z, .Ljtu_set_sp3  /* SW_Z = -R22 */
.Ljtu_set_sp3:
        /* SP -= SW_Z => SP = R22 */
        .word   SW_Z, REG_SP, .Ljtu_jump

        /*
         * Jump to R21 (the user entry point) using indirect addressing.
         * This is a RAW JUMP - no return address is pushed!
         */
.Ljtu_jump:
        .word   SW_Z, SW_Z, .Ljtu_jump2
.Ljtu_jump2:
        /* Indirect jump: subleq(Z, Z, R21|I) jumps to m[R21] */
        .word   SW_Z
        .word   SW_Z
        .word   REG_R21 | INDIRECT

        /*
         * Halt loop - if user binary returns, it will end up here
         */
.Ljtu_halt_loop:
        .word   SW_Z, SW_Z, .Ljtu_halt_loop

.Ljtu_halt_addr:
        .word   .Ljtu_halt_loop

.size jump_to_userspace, .-jump_to_userspace


/*
 * __subleq_syscall - Frameless syscall entry point
 *
 * This is a FRAMELESS function - it does NOT create a stack frame on the
 * userspace stack. This is critical because vfork children share the parent's
 * userspace stack and would corrupt any frame we create.
 *
 * Instead, we:
 *   1. Immediately save SP, FP, and return address to GLOBAL variables
 *   2. Switch to the kernel stack
 *   3. Call __subleq_syscall_c which runs entirely on kernel stack
 *   4. Restore userspace SP and FP from globals
 *   5. Jump to the saved return address (NOT from stack!)
 *
 * On entry (from userspace caller):
 *   [SP] = return address (caller pushed this before jumping)
 *   FP = caller's frame pointer
 *   R21 = syscall number, R22-R24 = args 1-3
 */
.globl __subleq_syscall
.type __subleq_syscall, @function
__subleq_syscall:
        /*
         * STEP 0: DISABLE INTERRUPTS
         *
         * CRITICAL: We must disable interrupts before saving ANY state.
         * If an interrupt fires during the save sequence, a context switch
         * could allow another task to overwrite our scratch registers (REG_T0)
         * or globals (subleq_syscall_saved_*), corrupting our state.
         *
         * Save m[0] (interrupt handler) to .Lsyscall_saved_handler, then clear m[0].
         *
         * IMPORTANT: We use REG_T0 as scratch here.
         * If an interrupt fires mid-sequence, the interrupt handler saves T0
         * to the IRQ stack and restores it on return. This makes the sequence
         * race-safe even if we're interrupted before m[0] is cleared.
         */
        .word   REG_T0, REG_T0, .+4                         /* T0 = 0 */
        .word   INT_HANDLER, REG_T0, .+4                    /* T0 = -m[0] */
        .word   .Lsyscall_saved_handler, .Lsyscall_saved_handler, .+4  /* clear save slot */
        .word   REG_T0, .Lsyscall_saved_handler, .+4        /* save slot = m[0] */
        .word   INT_HANDLER, INT_HANDLER, .+4               /* m[0] = 0 (disabled!) */

        /*
         * STEP 1: Save SP to global subleq_syscall_saved_sp
         */
        .word   subleq_syscall_saved_sp, subleq_syscall_saved_sp, .+4  /* clear */
        .word   REG_T0, REG_T0, .+4  /* ZZ = 0 */
        .word   REG_SP, REG_T0, .+4       /* ZZ = -SP */
        .word   REG_T0, subleq_syscall_saved_sp, .+4  /* saved_sp = SP */
        
        /*
         * STEP 2: Save FP to global subleq_syscall_saved_fp
         */
        .word   subleq_syscall_saved_fp, subleq_syscall_saved_fp, .+4  /* clear */
        .word   REG_T0, REG_T0, .+4  /* ZZ = 0 */
        .word   REG_FP, REG_T0, .+4       /* ZZ = -FP */
        .word   REG_T0, subleq_syscall_saved_fp, .+4  /* saved_fp = FP */

        /*
         * STEP 3: Save return address from [SP] to global subleq_syscall_saved_ra
         *
         * On entry, the CALLER has already pushed the return address to [SP].
         * The calling convention is: caller does SP -= 4; [SP] = ret; jump func
         *
         * So [SP] contains the return address, NOT [FP+4]!
         * [FP+4] was wrong - FP on entry is the caller's frame pointer.
         */
        /* Clear saved_ra */
        .word   subleq_syscall_saved_ra, subleq_syscall_saved_ra, .+4
        
        /* Load [SP] into saved_ra using indirect addressing */
        .word   .Lsyscall_tmp_addr, .Lsyscall_tmp_addr, .+4  /* tmp = 0 */
        .word   REG_SP | INDIRECT, .Lsyscall_tmp_addr, .+4   /* tmp = -[SP] */
        .word   .Lsyscall_tmp_addr, subleq_syscall_saved_ra, .+4  /* saved_ra = [SP] */

        /*
         * STEP 4: Switch to kernel stack
         *
         * Load subleq_kernel_sp (set by context switch) into hardware SP.
         */
        .word   REG_SP, REG_SP, .+4       /* SP = 0 */
        .word   REG_T0, REG_T0, .+4
        .word   subleq_kernel_sp, REG_T0, .+4  /* ZZ = -kernel_sp */
        .word   REG_T0, REG_SP, .+4   /* SP = kernel_sp */

        /*
         * STEP 4a: Save all GPRs (R3-R31) to pt_regs
         *
         * pt_regs is at subleq_kernel_sp + 1024.
         * We need to save R3-R31 so that fork/vfork can correctly copy the
         * parent's register state to the child.
         *
         * pt_regs layout (after adding R25-R31):
         *   r3:  offset 0
         *   r4:  offset 4
         *   ...
         *   r19: offset 64
         *   r20: offset 68
         *   r21: offset 72
         *   ...
         *   r31: offset 112
         *
         * We use REG_T8 as scratch to compute addresses.
         * REG_T9 holds the pt_regs base address.
         */

        /* Compute pt_regs base = subleq_kernel_sp + 1024 into REG_T9 */
        .word   REG_T0, REG_T0, .+4
        .word   subleq_kernel_sp, REG_T0, .+4        /* ZZ = -kernel_sp */
        .word   REG_T9, REG_T9, .+4                      /* T9 = 0 */
        .word   REG_T0, REG_T9, .+4                  /* T9 = kernel_sp */
        .word   .Lconst_neg1024, REG_T9, .+4           /* T9 = kernel_sp + 1024 = pt_regs base */

        /* Save R3 at [T9 + 0] */
        .word   REG_T0, REG_T0, .+4
        .word   REG_R3, REG_T0, .+4                  /* ZZ = -R3 */
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4  /* [T9] = 0 */
        .word   REG_T0, REG_T9 | INDIRECT, .+4       /* [T9] = R3 */

        /* Save R4 at [T9 + 4] */
        .word   .Lconst_neg4, REG_T9, .+4              /* T9 += 4 */
        .word   REG_T0, REG_T0, .+4
        .word   REG_R4, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R5 at [T9 + 8] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R5, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R6 at [T9 + 12] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R6, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R7 at [T9 + 16] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R7, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R8 at [T9 + 20] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R8, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R9 at [T9 + 24] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R9, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R10 at [T9 + 28] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R10, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R11 at [T9 + 32] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R11, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R12 at [T9 + 36] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R12, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R13 at [T9 + 40] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R13, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R14 at [T9 + 44] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R14, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R15 at [T9 + 48] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R15, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R16 at [T9 + 52] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R16, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R17 at [T9 + 56] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R17, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R18 at [T9 + 60] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R18, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R19 at [T9 + 64] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R19, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R20 at [T9 + 68] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R20, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R21 at [T9 + 72] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R21, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R22 at [T9 + 76] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R22, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R23 at [T9 + 80] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R23, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R24 at [T9 + 84] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R24, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R25 at [T9 + 88] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R25, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R26 at [T9 + 92] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R26, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R27 at [T9 + 96] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R27, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R28 at [T9 + 100] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R28, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R29 at [T9 + 104] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R29, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R30 at [T9 + 108] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R30, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /* Save R31 at [T9 + 112] */
        .word   .Lconst_neg4, REG_T9, .+4
        .word   REG_T0, REG_T0, .+4
        .word   REG_R31, REG_T0, .+4
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4

        /*
         * STEP 4a-continued: Save FP, SP, RA, PC to pt_regs
         *
         * CRITICAL: These must be saved HERE in assembly, not later in C code!
         * If we wait for C code to copy from globals, an interrupt between here
         * and the C code can cause a context switch, allowing another task to
         * overwrite the globals with its own values. When we resume, C would
         * copy the wrong values to pt_regs, causing a crash on syscall return.
         *
         * Offsets (continuing from R31 at 112):
         *   FP at offset 116
         *   SP at offset 120 (must be saved_sp + 4 to match post-call state)
         *   RA at offset 124
         *   PC at offset 128 (same as RA - the return address IS the PC)
         */

        /* Save FP at [T9 + 116] from subleq_syscall_saved_fp */
        .word   .Lconst_neg4, REG_T9, .+4              /* T9 = pt_regs + 116 */
        .word   REG_T0, REG_T0, .+4
        .word   subleq_syscall_saved_fp, REG_T0, .+4  /* ZZ = -saved_fp */
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4      /* [T9] = saved_fp */

        /* Save SP at [T9 + 120] = saved_sp + 4 (post-call SP) */
        .word   .Lconst_neg4, REG_T9, .+4              /* T9 = pt_regs + 120 */
        .word   REG_T0, REG_T0, .+4
        .word   subleq_syscall_saved_sp, REG_T0, .+4  /* ZZ = -saved_sp */
        .word   .Lconst_4, REG_T0, .+4              /* ZZ = -(saved_sp + 4) */
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4      /* [T9] = saved_sp + 4 */

        /* Save RA at [T9 + 124] from subleq_syscall_saved_ra */
        .word   .Lconst_neg4, REG_T9, .+4              /* T9 = pt_regs + 124 */
        .word   REG_T0, REG_T0, .+4
        .word   subleq_syscall_saved_ra, REG_T0, .+4  /* ZZ = -saved_ra */
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4      /* [T9] = saved_ra */

        /* Save PC at [T9 + 128] - same as RA (return address is the PC to return to) */
        .word   .Lconst_neg4, REG_T9, .+4              /* T9 = pt_regs + 128 */
        .word   REG_T0, REG_T0, .+4
        .word   subleq_syscall_saved_ra, REG_T0, .+4  /* ZZ = -saved_ra */
        .word   REG_T9 | INDIRECT, REG_T9 | INDIRECT, .+4
        .word   REG_T0, REG_T9 | INDIRECT, .+4      /* [T9] = saved_ra (as PC) */

        /*
         * STEP 4a-final: RE-ENABLE INTERRUPTS
         *
         * All critical state is now safely saved to pt_regs. We can re-enable
         * interrupts. Even if an interrupt causes a context switch now, our
         * pt_regs (on our kernel stack) remains intact, and when we return,
         * __switch_to will restore subleq_kernel_sp to point to our stack.
         *
         * Restore m[0] from .Lsyscall_saved_handler.
         * Using REG_T0 for consistency with STEP 0 (though interrupts are
         * currently disabled, so REG_T0 would also be safe here).
         */
        .word   REG_T0, REG_T0, .+4                         /* T0 = 0 */
        .word   .Lsyscall_saved_handler, REG_T0, .+4        /* T0 = -handler */
        .word   INT_HANDLER, INT_HANDLER, .+4               /* m[0] = 0 */
        .word   REG_T0, INT_HANDLER, .+4                    /* m[0] = handler */

        /*
         * STEP 4b: Push a6, a5, a4 from userspace stack onto kernel stack
         *
         * The userspace stack (saved in subleq_syscall_saved_sp) has:
         *   [saved_sp]     = return address
         *   [saved_sp+4]   = arg 5 (a4 in C function signature)
         *   [saved_sp+8]   = arg 6 (a5)
         *   [saved_sp+12]  = arg 7 (a6)
         *
         * We need to push these in reverse order (a6, a5, a4) so that
         * when __subleq_syscall_c is called, the stack has:
         *   [SP]    = return address
         *   [SP+4]  = a4 (arg 5)
         *   [SP+8]  = a5 (arg 6)
         *   [SP+12] = a6 (arg 7)
         *
         * Pattern for loading [saved_sp + offset]:
         *   1. Load saved_sp into scratch (.Lsyscall_ustack_addr)
         *   2. Add offset
         *   3. Use indirect addressing to read [scratch]
         *   4. Push value onto kernel stack
         */
        
        /* ---- Push a6 (from [saved_sp + 12]) ---- */
        /* Compute saved_sp + 12 into REG_T8 for indirect access */
        .word   REG_T8, REG_T8, .+4                                /* T8 = 0 */
        .word   REG_T0, REG_T0, .+4
        .word   subleq_syscall_saved_sp, REG_T0, .+4           /* ZZ = -saved_sp */
        .word   REG_T0, REG_T8, .+4                            /* T8 = saved_sp */
        .word   .Lconst_neg12, REG_T8, .+4                       /* T8 = saved_sp + 12 */
        
        /* Load [T8] into REG_T0 using indirect addressing */
        .word   REG_T0, REG_T0, .+4
        .word   REG_T8 | INDIRECT, REG_T0, .+4                 /* ZZ = -[T8] = -a6 */
        
        /* Push -ZZ onto kernel stack */
        .word   .Lconst_4, REG_SP, .+4                           /* SP -= 4 */
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4          /* [SP] = 0 */
        .word   REG_T0, REG_SP | INDIRECT, .+4                 /* [SP] = a6 */
        
        /* ---- Push a5 (from [saved_sp + 8]) ---- */
        .word   REG_T8, REG_T8, .+4                                /* T8 = 0 */
        .word   REG_T0, REG_T0, .+4
        .word   subleq_syscall_saved_sp, REG_T0, .+4           /* ZZ = -saved_sp */
        .word   REG_T0, REG_T8, .+4                            /* T8 = saved_sp */
        .word   .Lconst_neg8, REG_T8, .+4                        /* T8 = saved_sp + 8 */
        
        .word   REG_T0, REG_T0, .+4
        .word   REG_T8 | INDIRECT, REG_T0, .+4                 /* ZZ = -a5 */
        
        .word   .Lconst_4, REG_SP, .+4                           /* SP -= 4 */
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4          /* [SP] = 0 */
        .word   REG_T0, REG_SP | INDIRECT, .+4                 /* [SP] = a5 */
        
        /* ---- Push a4 (from [saved_sp + 4]) ---- */
        .word   REG_T8, REG_T8, .+4                                /* T8 = 0 */
        .word   REG_T0, REG_T0, .+4
        .word   subleq_syscall_saved_sp, REG_T0, .+4           /* ZZ = -saved_sp */
        .word   REG_T0, REG_T8, .+4                            /* T8 = saved_sp */
        .word   .Lconst_neg4, REG_T8, .+4                /* T8 = saved_sp + 4 */
        
        .word   REG_T0, REG_T0, .+4
        .word   REG_T8 | INDIRECT, REG_T0, .+4                 /* ZZ = -a4 */
        
        .word   .Lconst_4, REG_SP, .+4                           /* SP -= 4 */
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4          /* [SP] = 0 */
        .word   REG_T0, REG_SP | INDIRECT, .+4                 /* [SP] = a4 */

        /*
         * STEP 5: Set up call frame and call __subleq_syscall_c
         *
         * Using Subleq+ indirect addressing to push return address onto stack.
         * This avoids SMC which was buggy in the previous implementation.
         *
         * Stack-based call sequence:
         *   1. SP -= 4 (make room for return address)
         *   2. Clear [SP] using indirect: subleq(SP|I, SP|I, next)
         *   3. Load -return_addr into REG_T0
         *   4. Store return_addr to [SP]: subleq(REG_T0, SP|I, next)
         *   5. Jump to function
         */
        
        /* Step 1: SP -= 4 */
        .word   .Lconst_4, REG_SP, .+4  /* SP = SP - 4 */
        
        /* Step 2: Clear [SP] using indirect addressing */
        /* subleq(SP|I, SP|I, next) does: m[m[SP]] -= m[m[SP]] => m[SP] = 0 */
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4
        
        /* Step 3: Get -return_addr into REG_T0 */
        .word   REG_T0, REG_T0, .+4
        .word   .Lsyscall_c_ret_addr, REG_T0, .+4  /* ZZ = -return_point */
        
        /* Step 4: Store return_addr to [SP] using indirect addressing */
        /* subleq(REG_T0, SP|I, next) does: m[m[SP]] -= REG_T0 => m[SP] = 0 - (-addr) = addr */
        .word   REG_T0, REG_SP | INDIRECT, .+4

        /* Step 5: Jump to C handler */
        .word   REG_T0, REG_T0, __subleq_syscall_c


        /* Return point from C handler */
.Lsyscall_c_return:

        /*
         * Syscall return path.
         *
         * R20 contains the syscall return value (set by C calling convention).
         * With R20 now saved in switch_stack, it's preserved across context
         * switches, so parent's return value survives even when child runs.
         *
         * Read userspace SP/FP/PC from pt_regs (which is per-task).
         */

        .word   REG_T0, REG_T0, .Lsyscall_start_restore

.Lsyscall_r20_check:
        .word   0                                              /* scratch for R20 test */

.Lsyscall_start_restore:

        /*
         * STEP 1: Compute pt_regs base address from current SP (re-entrant!)
         *
         * CRITICAL: We use T-registers for ALL scratch state because they are
         * automatically saved/restored by the interrupt handler. If an interrupt
         * causes a context switch during this sequence, our T-register values
         * will be preserved when we resume.
         *
         * Stack layout at this point (AFTER C function returned):
         *   - C epilogue popped return address: SP += 4
         *   - SP now points to a4 (first stack arg)
         *   - Stack: [a4][a5][a6] = 12 bytes above kernel_sp
         *   - So: kernel_sp = SP + 12
         *   - pt_regs = kernel_sp + 1024 = SP + 12 + 1024 = SP + 1036
         *
         * REG_T9 = pt_regs base address (preserved across interrupts)
         */
        .word   REG_T0, REG_T0, .+4           /* T0 = 0 */
        .word   REG_SP, REG_T0, .+4           /* T0 = -SP */
        .word   REG_T9, REG_T9, .+4           /* T9 = 0 */
        .word   REG_T0, REG_T9, .+4           /* T9 = SP */
        .word   .Lconst_neg1036, REG_T9, .+4  /* T9 = SP + 1036 = pt_regs */

        /*
         * STEP 2: Load SP from pt_regs->sp (offset 120)
         * Compute &pt_regs->sp into REG_T8, then use REG_T8|INDIRECT to load
         */
        .word   REG_T0, REG_T0, .+4           /* T0 = 0 */
        .word   REG_T9, REG_T0, .+4           /* T0 = -pt_regs */
        .word   REG_T8, REG_T8, .+4           /* T8 = 0 */
        .word   REG_T0, REG_T8, .+4           /* T8 = pt_regs */
        .word   .Lconst_neg120, REG_T8, .+4   /* T8 = pt_regs + 120 = &sp */
        
        /* Load [T8] (the sp value) via indirect addressing */
        .word   REG_T0, REG_T0, .+4
        .word   REG_T8 | INDIRECT, REG_T0, .+4    /* T0 = -[T8] = -sp */
        .word   REG_SP, REG_SP, .+4               /* SP = 0 */
        .word   REG_T0, REG_SP, .+4               /* SP = sp value */

        /*
         * STEP 3: Load FP from pt_regs->fp (offset 116)
         */
        .word   REG_T0, REG_T0, .+4           /* T0 = 0 */
        .word   REG_T9, REG_T0, .+4           /* T0 = -pt_regs */
        .word   REG_T8, REG_T8, .+4           /* T8 = 0 */
        .word   REG_T0, REG_T8, .+4           /* T8 = pt_regs */
        .word   .Lconst_neg116, REG_T8, .+4   /* T8 = pt_regs + 116 = &fp */
        
        .word   REG_T0, REG_T0, .+4
        .word   REG_T8 | INDIRECT, REG_T0, .+4    /* T0 = -fp */
        .word   REG_FP, REG_FP, .+4               /* FP = 0 */
        .word   REG_T0, REG_FP, .+4               /* FP = fp value */

        /*
         * STEP 3b: Load R24 from pt_regs->r24 (offset 84)
         *
         * CRITICAL: vfork.S stores the caller's return address in R24 before
         * calling __subleq_syscall. The kernel saves this to pt_regs at entry.
         * Each task has its own pt_regs, so parent and child preserve their
         * own R24 values. This fixes nested vfork corruption.
         *
         * NOTE: R24 is an argument register (caller-saved), so the caller
         * doesn't expect it to be preserved. This avoids clobbering callee-saved
         * registers like R3/R4 which caused issues.
         */
        .word   REG_T0, REG_T0, .+4           /* T0 = 0 */
        .word   REG_T9, REG_T0, .+4           /* T0 = -pt_regs */
        .word   REG_T8, REG_T8, .+4           /* T8 = 0 */
        .word   REG_T0, REG_T8, .+4           /* T8 = pt_regs */
        .word   .Lconst_neg84, REG_T8, .+4    /* T8 = pt_regs + 84 = &r24 */
        
        .word   REG_T0, REG_T0, .+4
        .word   REG_T8 | INDIRECT, REG_T0, .+4    /* T0 = -r24 */
        .word   REG_R24, REG_R24, .+4             /* R24 = 0 */
        .word   REG_T0, REG_R24, .+4              /* R24 = r24 value */

        /*
         * STEP 4: Load PC from pt_regs->pc (offset 128) into REG_T15 and jump
         *
         * CRITICAL: We store the final jump PC in REG_T15 (a T-register) instead
         * of SW_Z2 (a global). This ensures the jump target is preserved even if
         * an interrupt + context switch occurs right before the final jump.
         *
         * REG_T15 | INDIRECT = 220 | 2 = 222
         */
        .word   REG_T0, REG_T0, .+4           /* T0 = 0 */
        .word   REG_T9, REG_T0, .+4           /* T0 = -pt_regs */
        .word   REG_T8, REG_T8, .+4           /* T8 = 0 */
        .word   REG_T0, REG_T8, .+4           /* T8 = pt_regs */
        .word   .Lconst_neg128, REG_T8, .+4   /* T8 = pt_regs + 128 = &pc */
        
        /* Load [T8] (the pc value) into REG_T15 (preserved T-register) */
        .word   REG_T0, REG_T0, .+4
        .word   REG_T8 | INDIRECT, REG_T0, .+4    /* T0 = -pc */
        .word   REG_T15, REG_T15, .+4             /* T15 = 0 */
        .word   REG_T0, REG_T15, .+4              /* T15 = pc */
        
        /* Jump to m[REG_T15] = pc value */
        /* REG_T15 | INDIRECT = 220 | 2 = 222 */
        .word   REG_T0, REG_T0, 222



/* Local data for __subleq_syscall */
.Lsyscall_c_ret_addr:
        .word   .Lsyscall_c_return

.Lsyscall_tmp_addr:
        .word   0

/* New constants for pt_regs-based syscall return (vfork fix) */
.Lsyscall_ptregs_addr:
        .word   0

/* Constants for forwarding syscall args 5-7 from userspace stack */
.Lsyscall_ustack_addr:
        .word   0               /* scratch for userspace stack address calculation */

/* Saved interrupt handler for syscall critical section */
.Lsyscall_saved_handler:
        .word   0               /* m[0] saved here while interrupts disabled */

/*
 * ===========================================================================
 * SHARED CONSTANTS SECTION
 * ===========================================================================
 *
 * All read-only numeric and character constants are consolidated here.
 * These are used across subleq_irq_entry, __switch_to, ret_from_fork,
 * jump_to_userspace, and __subleq_syscall.
 *
 * NOTE: Do NOT consolidate '0' constants - those are scratch storage.
 */

/* Numeric constants for pointer arithmetic */
.Lconst_4:
        .word   4               /* +4 increment */
.Lconst_neg4:
        .word   -4              /* -4 / +4 via subtraction */
.Lconst_neg8:
        .word   -8              /* For skipping slots */
.Lconst_neg12:
        .word   -12
.Lconst_neg40:
        .word   -40             /* For pt_regs running pointer (80 -> 120) */
.Lconst_neg44:
        .word   -44             /* For pt_regs running pointer (80 -> 124) */
.Lconst_100:
        .word   100             /* switch_stack size */
.Lconst_neg100:
        .word   -100            /* switch_stack deallocation */

/* pt_regs offsets (negative for subtraction-based addition) */
.Lconst_neg68:
        .word   -68             /* pt_regs->r20 */
.Lconst_neg72:
        .word   -72             /* pt_regs->r21 */
.Lconst_neg76:
        .word   -76             /* pt_regs->r22 */
.Lconst_neg80:
        .word   -80             /* pt_regs->r23 */
.Lconst_neg84:
        .word   -84             /* pt_regs->r24 */
.Lconst_neg116:
        .word   -116            /* pt_regs->fp */
.Lconst_neg120:
        .word   -120            /* pt_regs->sp */
.Lconst_neg124:
        .word   -124            /* pt_regs->ra */
.Lconst_neg128:
        .word   -128            /* pt_regs->pc */
.Lconst_neg136:
        .word   -136            /* pt_regs->syscall_nr */

/* pt_regs size for allocation/deallocation */
.Lconst_pt_size:
        .word   160             /* PT_SIZE = sizeof(struct pt_regs) */
.Lconst_neg_pt_size:
        .word   -160            /* Negative for deallocation */

/* Miscellaneous constants */
.Lconst_1:
        .word   1               /* Literal 1 */
.Lconst_neg1:
        .word   -1              /* Literal -1 for syscall_nr */

/* task_struct offsets - computed from asm-offsets.h */
.Lconst_neg_task_thread_sp:
        .word   -(TASK_THREAD_SP)       /* -offsetof(task_struct, thread.sp) */
.Lconst_neg_task_thread_fp:
        .word   -(TASK_THREAD_FP)       /* -offsetof(task_struct, thread.fp) */
.Lconst_neg_task_stack:
        .word   -(TASK_STACK)           /* -offsetof(task_struct, stack) */
.Lconst_neg_kernel_sp_offset:
        .word   -(KERNEL_SP_OFFSET)     /* -(THREAD_SIZE - sizeof(pt_regs) - 1024) */

/* Syscall-specific offsets */
.Lconst_neg2:
        .word   -2
.Lconst_neg38:
        .word   -38
.Lconst_neg1024:
        .word   -1024
.Lconst_neg1036:
        .word   -1036           /* SP + 1036 = pt_regs (C popped ret addr, so SP = kernel_sp - 12) */

/* Character constants for debug output */
.Lconst_char_I:
        .word   73              /* 'I' */

.size __subleq_syscall, .-__subleq_syscall


/*
 * ===========================================================================
 * SIGNAL RETURN TRAMPOLINE
 * ===========================================================================
 *
 * ret_from_user_rt_signal - Return trampoline for signal handlers
 *
 * When a signal is delivered, the kernel sets up a signal frame on the user
 * stack and sets the return address (pretcode) to point here. When the
 * signal handler returns, execution comes here.
 *
 * This function invokes sys_rt_sigreturn (syscall 139) to restore the
 * original register state and return to the interrupted code.
 *
 * NOTE: This is called from userspace with SP pointing to the signal frame.
 * We must NOT modify SP before calling the syscall.
 */
.globl ret_from_user_rt_signal
.type ret_from_user_rt_signal, @function
ret_from_user_rt_signal:
        /*
         * Load syscall number into R21 (first argument = syscall number)
         * __NR_rt_sigreturn = 139
         */
        .word   REG_R21, REG_R21, .+4           /* R21 = 0 */
        .word   .Lconst_neg139, REG_R21, .+4    /* R21 = 139 */

        /*
         * Jump to __subleq_syscall which will:
         * 1. Switch to kernel stack
         * 2. Call __subleq_syscall_c with syscall 139
         * 3. sys_rt_sigreturn restores context from signal frame
         * 4. Return to original interrupted code
         */
        .word   REG_T0, REG_T0, __subleq_syscall

.Lconst_neg139:
        .word   -139    /* Negative value for syscall number via subtraction */

.size ret_from_user_rt_signal, .-ret_from_user_rt_signal

/*
 * Global variables for syscall entry
 *
 * NOTE: These globals are ONLY used to temporarily save context at syscall
 * ENTRY time, before we copy them to pt_regs. The syscall RETURN path reads
 * from pt_regs (via subleq_kernel_sp) NOT from these globals.
 *
 * This is critical for vfork: the child's syscall would overwrite these,
 * but the parent's pt_regs remains intact on the parent's kernel stack.
 */
.data

/* Saved userspace context at syscall entry - copied to pt_regs by C code */
.globl subleq_syscall_saved_sp
subleq_syscall_saved_sp:
        .word   0

.globl subleq_syscall_saved_fp
subleq_syscall_saved_fp:
        .word   0

.globl subleq_syscall_saved_ra
subleq_syscall_saved_ra:
        .word   0

/* Kernel stack pointer for current task */
.globl subleq_kernel_sp
subleq_kernel_sp:
        .word   0

