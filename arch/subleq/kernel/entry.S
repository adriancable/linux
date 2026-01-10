/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Subleq interrupt entry/exit code - INSTRUMENTED VERSION
 *
 * Debug trace characters:
 *   'A' = Entry, before disable
 *   'B' = After disable
 *   'C' = After save complete
 *   'D' = Before calling C handler
 *   'E' = After C handler returns
 *   'F' = After restore complete
 *   'G' = After capture return address
 *   'H' = After re-enable
 *   'I' = Before final jump
 */

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

.set INT_ZZ, 224

/* Save slots */
.set SAVE_Z, 228
.set SAVE_SP, 232
.set SAVE_RA, 236
.set SAVE_R3, 240
.set SAVE_R4, 244
.set SAVE_R5, 248
.set SAVE_R6, 252
.set SAVE_R7, 256
.set SAVE_R8, 260
.set SAVE_R9, 264
.set SAVE_R10, 268
.set SAVE_R11, 272
.set SAVE_R12, 276
.set SAVE_R13, 280
.set SAVE_R14, 284
.set SAVE_R15, 288
.set SAVE_R16, 292
.set SAVE_R17, 296
.set SAVE_R18, 300
.set SAVE_R19, 304
.set SAVE_R20, 308
.set SAVE_R21, 312
.set SAVE_R22, 316
.set SAVE_R23, 320
.set SAVE_R24, 324
.set SAVE_R25, 328
.set SAVE_R26, 332
.set SAVE_R27, 336
.set SAVE_R28, 340
.set SAVE_R29, 344
.set SAVE_R30, 348
.set SAVE_R31, 352
.set SAVE_T0, 356
.set SAVE_T1, 360
.set SAVE_T2, 364
.set SAVE_T3, 368
.set SAVE_T4, 372
.set SAVE_T5, 376
.set SAVE_T6, 380
.set SAVE_T7, 384
.set SAVE_T8, 388
.set SAVE_T9, 392
.set SAVE_T10, 396
.set SAVE_T11, 400
.set SAVE_T12, 404
.set SAVE_T13, 408
.set SAVE_T14, 412
.set SAVE_T15, 416
.set SAVE_SCRATCH, 420
.set SAVE_JMPTGT, 424

.set SAVE_FP, 436        /* Save slot for frame pointer */

/* Context switch scratch registers - separate from INT_ZZ to avoid conflicts
 * when context switch runs with interrupts enabled */
.set SW_ZZ, 440   /* Scratch for __switch_to / ret_from_fork */
.set SW_ZZ2, 444  /* Second scratch if needed */

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
.set SUBLEQ_USP, 448    /* Saved userspace stack pointer */
.set SUBLEQ_UFP, 452    /* Saved userspace frame pointer */
.set SYSCALL_ZZ, 456    /* Scratch for syscall trampoline */

/* Save/restore macros */
.macro SAVE_REG reg_addr, save_addr, next_label
        .word   \save_addr, \save_addr, .+4
        .word   \reg_addr, \save_addr, \next_label
.endm

.macro RESTORE_REG save_addr, reg_addr, next_label
        .word   \reg_addr, \reg_addr, .+4
        .word   \save_addr, \reg_addr, \next_label
.endm

/*
 * Interrupt entry point
 *
 * CRITICAL: We must save SP and switch to the dedicated interrupt stack
 * IMMEDIATELY, before doing anything else. This is because an interrupt
 * can fire at any time, including when SP is in an invalid state (e.g.,
 * being cleared in preparation for reloading a new value).
 *
 * The dedicated interrupt stack pointer is at subleq_irq_stack_top.
 */
subleq_irq_entry:
        /* DEBUG disabled - was printing 'A' */
        /* .word   -4, .Lchar_A, .Lsave_sp_first */

        /*
         * PHASE 0a: SAVE SP IMMEDIATELY - before anything else!
         *
         * The caller's SP might be garbage (e.g., mid-reload), so we must
         * save it to SAVE_SP using only INT_ZZ as scratch before touching
         * any stack operations.
         *
         * IMPORTANT: SAVE_REG/RESTORE_REG store values as NEGATIVE.
         * We must follow the same convention: SAVE_SP = -SP
         *
         * Pattern: SAVE_SP = -SP (matching SAVE_REG convention)
         *   1. SAVE_SP = SAVE_SP - SAVE_SP = 0
         *   2. SAVE_SP = SAVE_SP - SP = -SP
         */
.Lsave_sp_first:
        .word   SAVE_SP, SAVE_SP, .Lsave_sp_first1    /* SAVE_SP = 0 */
.Lsave_sp_first1:
        .word   REG_SP, SAVE_SP, .Lload_irq_stack     /* SAVE_SP = -SP */

        /*
         * PHASE 0b: SWITCH TO DEDICATED INTERRUPT STACK
         *
         * Load the IRQ stack top pointer into SP.
         * Pattern: SP = subleq_irq_stack_top
         *   1. SP = SP - SP = 0
         *   2. INT_ZZ = INT_ZZ - INT_ZZ = 0
         *   3. INT_ZZ = INT_ZZ - [subleq_irq_stack_top] = -stack_top
         *   4. SP = SP - INT_ZZ = -(-stack_top) = stack_top
         */
.Lload_irq_stack:
        .word   REG_SP, REG_SP, .Lload_irq_stack1     /* SP = 0 */
.Lload_irq_stack1:
        .word   INT_ZZ, INT_ZZ, .Lload_irq_stack2     /* INT_ZZ = 0 */
.Lload_irq_stack2:
        .word   subleq_irq_stack_top, INT_ZZ, .Lload_irq_stack3  /* INT_ZZ = -stack_top */
.Lload_irq_stack3:
        .word   INT_ZZ, REG_SP, .Ldisable0            /* SP = stack_top */

        /* PHASE 0c: DISABLE INTERRUPTS */
.Ldisable0:
        .word   INT_ZZ, INT_ZZ, .Ldisable1
.Ldisable1:
        .word   INT_HANDLER, INT_ZZ, .Ldisable2
.Ldisable2:
        .word   INT_SAVED_HANDLER, INT_SAVED_HANDLER, .Ldisable3
.Ldisable3:
        .word   INT_ZZ, INT_SAVED_HANDLER, .Ldisable4
.Ldisable4:
        .word   INT_HANDLER, INT_HANDLER, .Ldisable_done

.Ldisable_done:
        /* DEBUG: Print 'B' (66) - after disable */
        /* .word   -4, .Lchar_B, .Lsave_z */

        /*
         * PHASE 1: SAVE ALL OTHER REGISTERS
         *
         * Note: SP was already saved in PHASE 0a above.
         * We skip saving SP here and proceed directly to save Z, RA, etc.
         */
.Lsave_z:
        SAVE_REG REG_Z, SAVE_Z, .Lsave_ra
.Lsave_ra:
        SAVE_REG REG_RA, SAVE_RA, .Lsave_r3
.Lsave_r3:
        SAVE_REG REG_R3, SAVE_R3, .Lsave_r4
.Lsave_r4:
        SAVE_REG REG_R4, SAVE_R4, .Lsave_r5
.Lsave_r5:
        SAVE_REG REG_R5, SAVE_R5, .Lsave_r6
.Lsave_r6:
        SAVE_REG REG_R6, SAVE_R6, .Lsave_r7
.Lsave_r7:
        SAVE_REG REG_R7, SAVE_R7, .Lsave_r8
.Lsave_r8:
        SAVE_REG REG_R8, SAVE_R8, .Lsave_r9
.Lsave_r9:
        SAVE_REG REG_R9, SAVE_R9, .Lsave_r10
.Lsave_r10:
        SAVE_REG REG_R10, SAVE_R10, .Lsave_r11
.Lsave_r11:
        SAVE_REG REG_R11, SAVE_R11, .Lsave_r12
.Lsave_r12:
        SAVE_REG REG_R12, SAVE_R12, .Lsave_r13
.Lsave_r13:
        SAVE_REG REG_R13, SAVE_R13, .Lsave_r14
.Lsave_r14:
        SAVE_REG REG_R14, SAVE_R14, .Lsave_r15
.Lsave_r15:
        SAVE_REG REG_R15, SAVE_R15, .Lsave_r16
.Lsave_r16:
        SAVE_REG REG_R16, SAVE_R16, .Lsave_r17
.Lsave_r17:
        SAVE_REG REG_R17, SAVE_R17, .Lsave_r18
.Lsave_r18:
        SAVE_REG REG_R18, SAVE_R18, .Lsave_r19
.Lsave_r19:
        SAVE_REG REG_R19, SAVE_R19, .Lsave_r20
.Lsave_r20:
        SAVE_REG REG_R20, SAVE_R20, .Lsave_r21
.Lsave_r21:
        SAVE_REG REG_R21, SAVE_R21, .Lsave_r22
.Lsave_r22:
        SAVE_REG REG_R22, SAVE_R22, .Lsave_r23
.Lsave_r23:
        SAVE_REG REG_R23, SAVE_R23, .Lsave_r24
.Lsave_r24:
        SAVE_REG REG_R24, SAVE_R24, .Lsave_r25
.Lsave_r25:
        SAVE_REG REG_R25, SAVE_R25, .Lsave_r26
.Lsave_r26:
        SAVE_REG REG_R26, SAVE_R26, .Lsave_r27
.Lsave_r27:
        SAVE_REG REG_R27, SAVE_R27, .Lsave_r28
.Lsave_r28:
        SAVE_REG REG_R28, SAVE_R28, .Lsave_r29
.Lsave_r29:
        SAVE_REG REG_R29, SAVE_R29, .Lsave_r30
.Lsave_r30:
        SAVE_REG REG_R30, SAVE_R30, .Lsave_r31
.Lsave_r31:
        SAVE_REG REG_R31, SAVE_R31, .Lsave_t0
.Lsave_t0:
        SAVE_REG REG_T0, SAVE_T0, .Lsave_t1
.Lsave_t1:
        SAVE_REG REG_T1, SAVE_T1, .Lsave_t2
.Lsave_t2:
        SAVE_REG REG_T2, SAVE_T2, .Lsave_t3
.Lsave_t3:
        SAVE_REG REG_T3, SAVE_T3, .Lsave_t4
.Lsave_t4:
        SAVE_REG REG_T4, SAVE_T4, .Lsave_t5
.Lsave_t5:
        SAVE_REG REG_T5, SAVE_T5, .Lsave_t6
.Lsave_t6:
        SAVE_REG REG_T6, SAVE_T6, .Lsave_t7
.Lsave_t7:
        SAVE_REG REG_T7, SAVE_T7, .Lsave_t8
.Lsave_t8:
        SAVE_REG REG_T8, SAVE_T8, .Lsave_t9
.Lsave_t9:
        SAVE_REG REG_T9, SAVE_T9, .Lsave_t10
.Lsave_t10:
        SAVE_REG REG_T10, SAVE_T10, .Lsave_t11
.Lsave_t11:
        SAVE_REG REG_T11, SAVE_T11, .Lsave_t12
.Lsave_t12:
        SAVE_REG REG_T12, SAVE_T12, .Lsave_t13
.Lsave_t13:
        SAVE_REG REG_T13, SAVE_T13, .Lsave_t14
.Lsave_t14:
        SAVE_REG REG_T14, SAVE_T14, .Lsave_t15
.Lsave_t15:
        SAVE_REG REG_T15, SAVE_T15, .Lsave_fp
.Lsave_fp:
        SAVE_REG REG_FP, SAVE_FP, .Lsave_done

.Lsave_done:
        /* DEBUG: Print 'C' (67) - after save */
        /* .word   -4, .Lchar_C, .Lirq_call */

        /* PHASE 2: CALL C HANDLER */
.Lirq_call:
        /* DEBUG: Print 'D' (68) - before C call */
        /* .word   -4, .Lchar_D, .Lirq_do_call */

        /*
         * STACK-BASED CALL to subleq_do_IRQ using Subleq+ indirect addressing
         *
         * The C compiler expects the return address to be ON THE STACK,
         * not in RA. We must:
         * 1. SP -= 4 (make room)
         * 2. Clear [SP] using indirect addressing
         * 3. Store return address at [SP] using indirect addressing
         * 4. Jump to function
         *
         * Subleq+ indirect addressing avoids self-modifying code entirely.
         */

.Lirq_do_call:
        /* Step 1: SP -= 4 (decrement stack pointer) */
        .word   .Lconst_4, REG_SP, .Lcall_push1

.Lcall_push1:
        /* Step 2: Clear [SP] using indirect addressing */
        /* subleq(SP|I, SP|I, next) does: m[m[SP]] -= m[m[SP]] => [SP] = 0 */
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .Lcall_push2

.Lcall_push2:
        /* Step 3: Store .Lirq_returned at [SP] */
        /* Get -return_addr into INT_ZZ */
        .word   INT_ZZ, INT_ZZ, .Lcall_push3
.Lcall_push3:
        .word   .Lirq_return_addr, INT_ZZ, .Lcall_push4

.Lcall_push4:
        /* [SP] -= INT_ZZ => [SP] = return_addr */
        /* subleq(INT_ZZ, SP|I, next) does: m[m[SP]] -= INT_ZZ => [SP] = -(-addr) = addr */
        .word   INT_ZZ, REG_SP | INDIRECT, .Lcall_jump

        /* Step 4: Jump to subleq_do_IRQ */
.Lcall_jump:
        .word   INT_ZZ, INT_ZZ, subleq_do_IRQ

        /* PHASE 3: RESTORE ALL REGISTERS */
.Lirq_returned:
        /* DEBUG: Print 'E' (69) - after C call */
        /* .word   -4, .Lchar_E, .Lrestore_fp */

.Lrestore_fp:
        RESTORE_REG SAVE_FP, REG_FP, .Lrestore_t15
.Lrestore_t15:
        RESTORE_REG SAVE_T15, REG_T15, .Lrestore_t14
.Lrestore_t14:
        RESTORE_REG SAVE_T14, REG_T14, .Lrestore_t13
.Lrestore_t13:
        RESTORE_REG SAVE_T13, REG_T13, .Lrestore_t12
.Lrestore_t12:
        RESTORE_REG SAVE_T12, REG_T12, .Lrestore_t11
.Lrestore_t11:
        RESTORE_REG SAVE_T11, REG_T11, .Lrestore_t10
.Lrestore_t10:
        RESTORE_REG SAVE_T10, REG_T10, .Lrestore_t9
.Lrestore_t9:
        RESTORE_REG SAVE_T9, REG_T9, .Lrestore_t8
.Lrestore_t8:
        RESTORE_REG SAVE_T8, REG_T8, .Lrestore_t7
.Lrestore_t7:
        RESTORE_REG SAVE_T7, REG_T7, .Lrestore_t6
.Lrestore_t6:
        RESTORE_REG SAVE_T6, REG_T6, .Lrestore_t5
.Lrestore_t5:
        RESTORE_REG SAVE_T5, REG_T5, .Lrestore_t4
.Lrestore_t4:
        RESTORE_REG SAVE_T4, REG_T4, .Lrestore_t3
.Lrestore_t3:
        RESTORE_REG SAVE_T3, REG_T3, .Lrestore_t2
.Lrestore_t2:
        RESTORE_REG SAVE_T2, REG_T2, .Lrestore_t1
.Lrestore_t1:
        RESTORE_REG SAVE_T1, REG_T1, .Lrestore_t0
.Lrestore_t0:
        RESTORE_REG SAVE_T0, REG_T0, .Lrestore_r31
.Lrestore_r31:
        RESTORE_REG SAVE_R31, REG_R31, .Lrestore_r30
.Lrestore_r30:
        RESTORE_REG SAVE_R30, REG_R30, .Lrestore_r29
.Lrestore_r29:
        RESTORE_REG SAVE_R29, REG_R29, .Lrestore_r28
.Lrestore_r28:
        RESTORE_REG SAVE_R28, REG_R28, .Lrestore_r27
.Lrestore_r27:
        RESTORE_REG SAVE_R27, REG_R27, .Lrestore_r26
.Lrestore_r26:
        RESTORE_REG SAVE_R26, REG_R26, .Lrestore_r25
.Lrestore_r25:
        RESTORE_REG SAVE_R25, REG_R25, .Lrestore_r24
.Lrestore_r24:
        RESTORE_REG SAVE_R24, REG_R24, .Lrestore_r23
.Lrestore_r23:
        RESTORE_REG SAVE_R23, REG_R23, .Lrestore_r22
.Lrestore_r22:
        RESTORE_REG SAVE_R22, REG_R22, .Lrestore_r21
.Lrestore_r21:
        RESTORE_REG SAVE_R21, REG_R21, .Lrestore_r20
.Lrestore_r20:
        RESTORE_REG SAVE_R20, REG_R20, .Lrestore_r19
.Lrestore_r19:
        RESTORE_REG SAVE_R19, REG_R19, .Lrestore_r18
.Lrestore_r18:
        RESTORE_REG SAVE_R18, REG_R18, .Lrestore_r17
.Lrestore_r17:
        RESTORE_REG SAVE_R17, REG_R17, .Lrestore_r16
.Lrestore_r16:
        RESTORE_REG SAVE_R16, REG_R16, .Lrestore_r15
.Lrestore_r15:
        RESTORE_REG SAVE_R15, REG_R15, .Lrestore_r14
.Lrestore_r14:
        RESTORE_REG SAVE_R14, REG_R14, .Lrestore_r13
.Lrestore_r13:
        RESTORE_REG SAVE_R13, REG_R13, .Lrestore_r12
.Lrestore_r12:
        RESTORE_REG SAVE_R12, REG_R12, .Lrestore_r11
.Lrestore_r11:
        RESTORE_REG SAVE_R11, REG_R11, .Lrestore_r10
.Lrestore_r10:
        RESTORE_REG SAVE_R10, REG_R10, .Lrestore_r9
.Lrestore_r9:
        RESTORE_REG SAVE_R9, REG_R9, .Lrestore_r8
.Lrestore_r8:
        RESTORE_REG SAVE_R8, REG_R8, .Lrestore_r7
.Lrestore_r7:
        RESTORE_REG SAVE_R7, REG_R7, .Lrestore_r6
.Lrestore_r6:
        RESTORE_REG SAVE_R6, REG_R6, .Lrestore_r5
.Lrestore_r5:
        RESTORE_REG SAVE_R5, REG_R5, .Lrestore_r4
.Lrestore_r4:
        RESTORE_REG SAVE_R4, REG_R4, .Lrestore_r3
.Lrestore_r3:
        RESTORE_REG SAVE_R3, REG_R3, .Lrestore_ra
.Lrestore_ra:
        RESTORE_REG SAVE_RA, REG_RA, .Lrestore_sp
.Lrestore_sp:
        RESTORE_REG SAVE_SP, REG_SP, .Lrestore_z
.Lrestore_z:
        RESTORE_REG SAVE_Z, REG_Z, .Lrestore_done

.Lrestore_done:
        /* DEBUG: Print 'F' (70) - after restore */
        /* .word   -4, .Lchar_F, .Lirq_return */

        /* PHASE 4: CAPTURE RETURN ADDRESS */
.Lirq_return:
        .word   INT_ZZ, INT_ZZ, .Lirq_ret1
.Lirq_ret1:
        .word   INT_SAVED_PC, INT_ZZ, .Lirq_ret2
.Lirq_ret2:
        .word   SAVE_JMPTGT, SAVE_JMPTGT, .Lirq_ret3
.Lirq_ret3:
        .word   INT_ZZ, SAVE_JMPTGT, .Lcapture_done

.Lcapture_done:
        /* DEBUG: Print 'G' (71) - after capture */
        /* .word   -4, .Lchar_G, .Ldo_jump */

        /*
         * PHASE 5: RE-ENABLE INTERRUPTS AND RETURN
         *
         * At this point, subleq_do_IRQ() has returned, which means:
         * - All C-level interrupt processing is complete
         * - irq_exit() has finished (including any softirq processing)
         * - The preempt_count is back to its pre-interrupt value
         *
         * The key to preventing re-entrancy is in irqflags.h:
         * - arch_local_irq_enable() checks in_interrupt() (hardirq | softirq)
         * - During irq_exit(), even though hardirq count is decremented,
         *   the softirq bits are set during handle_softirqs()
         * - So local_irq_enable() calls inside softirq processing are no-ops
         *
         * We MUST re-enable interrupts here because:
         * - The interrupted code was running with interrupts enabled
         *   (otherwise the interrupt wouldn't have fired)
         * - If we don't re-enable, the system will hang with interrupts off
         *
         * Using Subleq+ indirect addressing for the return jump.
         * SAVE_JMPTGT contains the return address (from INT_SAVED_PC).
         * We use indirect jump: subleq(Z, Z, SAVE_JMPTGT|I) to jump to m[SAVE_JMPTGT].
         */
.Ldo_jump:
        /* Re-enable interrupts: restore handler address to m[0] */
.Lenable_irq:
        .word   INT_ZZ, INT_ZZ, .Lenable1
.Lenable1:
        .word   INT_SAVED_HANDLER, INT_ZZ, .Lenable2
.Lenable2:
        .word   INT_HANDLER, INT_HANDLER, .Lenable3
.Lenable3:
        /* Re-enable interrupts: m[0] = handler address from m[2] */
        .word   INT_ZZ, INT_HANDLER, .Ldo_return

.Ldo_return:
        /* Clear INT_ZZ for unconditional jump */
        .word   INT_ZZ, INT_ZZ, .Ldo_return2
.Ldo_return2:
        /* Indirect jump: subleq(Z, Z, SAVE_JMPTGT|I) always jumps to m[SAVE_JMPTGT] */
        .word   INT_ZZ
        .word   INT_ZZ
        .word   SAVE_JMPTGT | INDIRECT

        /* If we get here, something is very wrong! */
.Ljump_failed:
        .word   -4, .Lchar_I, .Ljump_failed2
.Ljump_failed2:
        .word   -4, .Lchar_J, .Lhang
.Lhang:
        .word   INT_ZZ, INT_ZZ, .Lhang

.Lirq_return_addr:
        .word   .Lirq_returned

/* Character constants for debug output */
.Lchar_A:
        .word   65
.Lchar_B:
        .word   66
.Lchar_C:
        .word   67
.Lchar_D:
        .word   68
.Lchar_E:
        .word   69
.Lchar_F:
        .word   70
.Lchar_G:
        .word   71
.Lchar_H:
        .word   42
.Lchar_I:
        .word   73
.Lchar_X:
        .word   88
.Lchar_J:
        .word   74

/* Constant for stack operations */
.Lconst_4:
        .word   4

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

/* Offset of thread.sp in task_struct (TASK_THREAD + THREAD_SP = 1180 + 0) */
.set TASK_THREAD_SP, 1180
/* Offset of thread.fp in task_struct (TASK_THREAD + THREAD_FP = 1180 + 4) */
.set TASK_THREAD_FP, 1184

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
        .word   .Lsw_const_100, REG_SP, .Lsw_save_regs_start

        /*
         * STEP 2: Save callee-saved registers to switch_stack
         *
         * We save R3-R19 (17 regs) at offsets 0-64
         * then R20 (1 reg, for vfork) at offset 68
         * and R25-R31 (7 regs) at offsets 72-96
         *
         * For each register, we compute SP + offset into SW_ZZ2,
         * then store the register value there using indirect addressing.
         */
.Lsw_save_regs_start:
        /* Save R3 at [SP + 0] */
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4              /* SW_ZZ2 = SP + 0 */
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4  /* clear [SP+0] */
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R3, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r4

        /* Save R4 at [SP + 4] */
.Lsw_save_r4:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg4, SW_ZZ2, .+4          /* SW_ZZ2 = SP + 4 */
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R4, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r5

        /* Save R5 at [SP + 8] */
.Lsw_save_r5:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg8, SW_ZZ2, .+4          /* SW_ZZ2 = SP + 8 */
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R5, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r6

        /* Save R6 at [SP + 12] */
.Lsw_save_r6:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg12, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R6, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r7

        /* Save R7 at [SP + 16] */
.Lsw_save_r7:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg16, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R7, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r8

        /* Save R8 at [SP + 20] */
.Lsw_save_r8:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg20, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R8, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r9

        /* Save R9 at [SP + 24] */
.Lsw_save_r9:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg24, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R9, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r10

        /* Save R10 at [SP + 28] */
.Lsw_save_r10:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg28, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R10, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r11

        /* Save R11 at [SP + 32] */
.Lsw_save_r11:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg32, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R11, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r12

        /* Save R12 at [SP + 36] */
.Lsw_save_r12:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg36, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R12, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r13

        /* Save R13 at [SP + 40] */
.Lsw_save_r13:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg40, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R13, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r14

        /* Save R14 at [SP + 44] */
.Lsw_save_r14:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg44, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R14, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r15

        /* Save R15 at [SP + 48] */
.Lsw_save_r15:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg48, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R15, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r16

        /* Save R16 at [SP + 52] */
.Lsw_save_r16:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg52, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R16, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r17

        /* Save R17 at [SP + 56] */
.Lsw_save_r17:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg56, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R17, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r18

        /* Save R18 at [SP + 60] */
.Lsw_save_r18:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg60, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R18, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r19

        /* Save R19 at [SP + 64] */
.Lsw_save_r19:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg64, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R19, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r20

        /* Save R20 at [SP + 68] - needed for vfork CLONE_VM fix */
.Lsw_save_r20:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg68, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R20, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r25

        /* Save R25 at [SP + 72] */
.Lsw_save_r25:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg72, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R25, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r26

        /* Save R26 at [SP + 76] */
.Lsw_save_r26:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg76, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R26, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r27

        /* Save R27 at [SP + 80] */
.Lsw_save_r27:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg80, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R27, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r28

        /* Save R28 at [SP + 84] */
.Lsw_save_r28:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg84, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R28, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r29

        /* Save R29 at [SP + 88] */
.Lsw_save_r29:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg88, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R29, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r30

        /* Save R30 at [SP + 92] */
.Lsw_save_r30:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg92, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R30, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_r31

        /* Save R31 at [SP + 96] */
.Lsw_save_r31:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg96, SW_ZZ2, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R31, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_sp

        /*
         * STEP 3: Save SP to prev->thread.sp
         */
.Lsw_save_sp:
        /* Calculate &prev->thread.sp into SW_ZZ2 */
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R21, SW_ZZ, .+4
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ2, .+4              /* SW_ZZ2 = prev */
        .word   .Loffset_neg, SW_ZZ2, .+4       /* SW_ZZ2 = &prev->thread.sp */
        /* Clear and store SP */
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_fp

        /*
         * STEP 3b: Save FP to prev->thread.fp
         */
.Lsw_save_fp:
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R21, SW_ZZ, .+4
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Loffset_fp_neg, SW_ZZ2, .+4    /* SW_ZZ2 = &prev->thread.fp */
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_FP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_update_current

        /*
         * STEP 4: Update subleq_current_task = next
         */
.Lsw_update_current:
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R22, SW_ZZ, .+4
        .word   subleq_current_task, subleq_current_task, .+4
        .word   SW_ZZ, subleq_current_task, .Lsw_load_sp

        /*
         * STEP 5: Load SP from next->thread.sp
         */
.Lsw_load_sp:
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R22, SW_ZZ, .+4
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Loffset_neg, SW_ZZ2, .+4       /* SW_ZZ2 = &next->thread.sp */
        /* Load [SW_ZZ2] into SP */
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_SP, REG_SP, .+4
        .word   SW_ZZ, REG_SP, .Lsw_load_fp

        /*
         * STEP 5b: Load FP from next->thread.fp
         */
.Lsw_load_fp:
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R22, SW_ZZ, .+4
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Loffset_fp_neg, SW_ZZ2, .+4    /* SW_ZZ2 = &next->thread.fp */
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_FP, REG_FP, .+4
        .word   SW_ZZ, REG_FP, .Lsw_restore_regs_start

        /*
         * STEP 6: Restore callee-saved registers from switch_stack
         *
         * Similar to save, but loading from [SP + offset] into registers.
         */
.Lsw_restore_regs_start:
        /* Restore R3 from [SP + 0] */
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4              /* SW_ZZ2 = SP */
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4   /* SW_ZZ = -[SP+0] */
        .word   REG_R3, REG_R3, .+4
        .word   SW_ZZ, REG_R3, .Lsw_restore_r4  /* R3 = [SP+0] */

        /* Restore R4 from [SP + 4] */
.Lsw_restore_r4:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg4, SW_ZZ2, .+4          /* SW_ZZ2 = SP + 4 */
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R4, REG_R4, .+4
        .word   SW_ZZ, REG_R4, .Lsw_restore_r5

        /* Restore R5 from [SP + 8] */
.Lsw_restore_r5:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg8, SW_ZZ2, .+4          /* SW_ZZ2 = SP + 8 */
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R5, REG_R5, .+4
        .word   SW_ZZ, REG_R5, .Lsw_restore_r6

        /* Restore R6 from [SP + 12] */
.Lsw_restore_r6:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg12, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R6, REG_R6, .+4
        .word   SW_ZZ, REG_R6, .Lsw_restore_r7

        /* Restore R7 from [SP + 16] */
.Lsw_restore_r7:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg16, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R7, REG_R7, .+4
        .word   SW_ZZ, REG_R7, .Lsw_restore_r8

        /* Restore R8 from [SP + 20] */
.Lsw_restore_r8:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg20, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R8, REG_R8, .+4
        .word   SW_ZZ, REG_R8, .Lsw_restore_r9

        /* Restore R9 from [SP + 24] */
.Lsw_restore_r9:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg24, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R9, REG_R9, .+4
        .word   SW_ZZ, REG_R9, .Lsw_restore_r10

        /* Restore R10 from [SP + 28] */
.Lsw_restore_r10:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg28, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R10, REG_R10, .+4
        .word   SW_ZZ, REG_R10, .Lsw_restore_r11

        /* Restore R11 from [SP + 32] */
.Lsw_restore_r11:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg32, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R11, REG_R11, .+4
        .word   SW_ZZ, REG_R11, .Lsw_restore_r12

        /* Restore R12 from [SP + 36] */
.Lsw_restore_r12:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg36, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R12, REG_R12, .+4
        .word   SW_ZZ, REG_R12, .Lsw_restore_r13

        /* Restore R13 from [SP + 40] */
.Lsw_restore_r13:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg40, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R13, REG_R13, .+4
        .word   SW_ZZ, REG_R13, .Lsw_restore_r14

        /* Restore R14 from [SP + 44] */
.Lsw_restore_r14:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg44, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R14, REG_R14, .+4
        .word   SW_ZZ, REG_R14, .Lsw_restore_r15

        /* Restore R15 from [SP + 48] */
.Lsw_restore_r15:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg48, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R15, REG_R15, .+4
        .word   SW_ZZ, REG_R15, .Lsw_restore_r16

        /* Restore R16 from [SP + 52] */
.Lsw_restore_r16:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg52, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R16, REG_R16, .+4
        .word   SW_ZZ, REG_R16, .Lsw_restore_r17

        /* Restore R17 from [SP + 56] */
.Lsw_restore_r17:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg56, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R17, REG_R17, .+4
        .word   SW_ZZ, REG_R17, .Lsw_restore_r18

        /* Restore R18 from [SP + 60] */
.Lsw_restore_r18:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg60, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R18, REG_R18, .+4
        .word   SW_ZZ, REG_R18, .Lsw_restore_r19

        /* Restore R19 from [SP + 64] */
.Lsw_restore_r19:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg64, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R19, REG_R19, .+4
        .word   SW_ZZ, REG_R19, .Lsw_restore_r20

        /* Restore R20 from [SP + 68] - needed for vfork CLONE_VM fix */
.Lsw_restore_r20:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg68, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R20, REG_R20, .+4
        .word   SW_ZZ, REG_R20, .Lsw_restore_r25

        /* Restore R25 from [SP + 72] */
.Lsw_restore_r25:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg72, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R25, REG_R25, .+4
        .word   SW_ZZ, REG_R25, .Lsw_restore_r26

        /* Restore R26 from [SP + 76] */
.Lsw_restore_r26:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg76, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R26, REG_R26, .+4
        .word   SW_ZZ, REG_R26, .Lsw_restore_r27

        /* Restore R27 from [SP + 80] */
.Lsw_restore_r27:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg80, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R27, REG_R27, .+4
        .word   SW_ZZ, REG_R27, .Lsw_restore_r28

        /* Restore R28 from [SP + 84] */
.Lsw_restore_r28:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg84, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R28, REG_R28, .+4
        .word   SW_ZZ, REG_R28, .Lsw_restore_r29

        /* Restore R29 from [SP + 88] */
.Lsw_restore_r29:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg88, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R29, REG_R29, .+4
        .word   SW_ZZ, REG_R29, .Lsw_restore_r30

        /* Restore R30 from [SP + 92] */
.Lsw_restore_r30:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg92, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R30, REG_R30, .+4
        .word   SW_ZZ, REG_R30, .Lsw_restore_r31

        /* Restore R31 from [SP + 96] */
.Lsw_restore_r31:
        .word   SW_ZZ2, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP, SW_ZZ, .+4
        .word   SW_ZZ, SW_ZZ2, .+4
        .word   .Lsw_neg96, SW_ZZ2, .+4
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .+4
        .word   REG_R31, REG_R31, .+4
        .word   SW_ZZ, REG_R31, .Lsw_restore_done

.Lsw_restore_done:

        /*
         * STEP 7: Deallocate switch_stack: SP += 100
         */
        .word   .Lsw_neg100, REG_SP, .Lsw_set_retval

        /*
         * STEP 8: Set return value R20 = prev (R21)
         */
.Lsw_set_retval:
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_R21, SW_ZZ, .+4
        .word   REG_R20, REG_R20, .+4
        .word   SW_ZZ, REG_R20, .Lsw_pop_ra

        /*
         * STEP 9: Pop return address and return
         *
         * Now SP points to the return address (at old SP+96 = retpc slot).
         */
.Lsw_pop_ra:
        .word   SW_ZZ, SW_ZZ, .+4
        .word   REG_SP | INDIRECT, SW_ZZ, .+4   /* SW_ZZ = -[SP] */
        .word   REG_RA, REG_RA, .+4
        .word   SW_ZZ, REG_RA, .+4              /* RA = [SP] */
        .word   .Lconst_neg4, REG_SP, .Lsw_return  /* SP += 4 */

        /*
         * STEP 10: Jump to return address
         *
         * DEBUG: Print 'J[XXXXXX]' - DISABLED for clean output
         */
.Lsw_return:
        /* Jump directly without debug output */
        .word   SW_ZZ, SW_ZZ, .+4
        .word   SW_ZZ
        .word   SW_ZZ
        .word   REG_RA | INDIRECT

/* Disabled debug code for J[OK] printing:
.Lsw_print_hex:
        .word   -4, .Lsw_char_lbracket, .Lsw_hex_start
        ... (hex printing code) ...
        ... (OK/BAD/RF comparison code) ...
*/

.Lsw_char_J:
        .word   74      /* 'J' */
.Lsw_char_lbracket:
        .word   91      /* '[' */
.Lsw_char_rbracket:
        .word   93      /* ']' */
.Lsw_char_B:
        .word   66      /* 'B' */
.Lsw_char_A:
        .word   65      /* 'A' */
.Lsw_char_D:
        .word   68      /* 'D' */
.Lsw_char_O:
        .word   79      /* 'O' */
.Lsw_char_K:
        .word   75      /* 'K' */
.Lsw_char_R:
        .word   82      /* 'R' */
.Lsw_char_F:
        .word   70      /* 'F' */
.Lsw_ra_copy:
        .word   0       /* Temp storage for RA */
.Lsw_syscall_ret_addr:
        .word   .Lsyscall_c_return   /* Address of syscall return point (BAD if parent returns here) */
.Lsw_ret_from_fork_addr:
        .word   ret_from_fork        /* Address of ret_from_fork (RF if parent returns here) */

/* Constants for __switch_to */
.Loffset_neg:
        .word   -1180           /* Negative of TASK_THREAD_SP offset */
.Loffset_fp_neg:
        .word   -1184           /* Negative of TASK_THREAD_FP offset */
.Lconst_neg4:
        .word   -4
.Lsw_const_100:
        .word   100             /* switch_stack size (25 registers) */
.Lsw_neg4:
        .word   -4
.Lsw_neg8:
        .word   -8
.Lsw_neg12:
        .word   -12
.Lsw_neg16:
        .word   -16
.Lsw_neg20:
        .word   -20
.Lsw_neg24:
        .word   -24
.Lsw_neg28:
        .word   -28
.Lsw_neg32:
        .word   -32
.Lsw_neg36:
        .word   -36
.Lsw_neg40:
        .word   -40
.Lsw_neg44:
        .word   -44
.Lsw_neg48:
        .word   -48
.Lsw_neg52:
        .word   -52
.Lsw_neg56:
        .word   -56
.Lsw_neg60:
        .word   -60
.Lsw_neg64:
        .word   -64
.Lsw_neg68:
        .word   -68
.Lsw_neg72:
        .word   -72
.Lsw_neg76:
        .word   -76
.Lsw_neg80:
        .word   -80
.Lsw_neg84:
        .word   -84
.Lsw_neg88:
        .word   -88
.Lsw_neg92:
        .word   -92
.Lsw_neg96:
        .word   -96
.Lsw_neg100:
        .word   -100

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
        .word   SW_ZZ, SW_ZZ, .Lrff_copy2
.Lrff_copy2:
        .word   REG_R20, SW_ZZ, .Lrff_copy3     /* SW_ZZ = -R20 */
.Lrff_copy3:
        .word   SW_ZZ, REG_R21, .Lrff_check_r3  /* R21 = R20 = prev */

        /*
         * Read pt_regs.r3 from [SP] (offset 0) to check kernel/user thread.
         * SW_ZZ2 will hold r3 value for comparison.
         */
.Lrff_check_r3:
        .word   SW_ZZ, SW_ZZ, .Lrff_check_r3_1
.Lrff_check_r3_1:
        /* Load [SP] into SW_ZZ using indirect addressing */
        /* subleq(SP|I, SW_ZZ, next) does: SW_ZZ -= m[SP] => SW_ZZ = -r3 */
        .word   REG_SP | INDIRECT, SW_ZZ, .Lrff_check_r3_2
.Lrff_check_r3_2:
        /* Now SW_ZZ = -r3. If r3 == 0, SW_ZZ == 0. */
        /* subleq(A, B, C) branches to C if B <= 0 after subtraction */
        /* We want to branch if r3 == 0, i.e., if SW_ZZ == 0 */
        /* Test: if SW_ZZ == 0, then 0 - 0 <= 0, so we branch */
        /* But we need to test SW_ZZ itself, not subtract something from it */
        
        /* Check if SW_ZZ == 0 (which means r3 == 0 => user thread) */
        /* We use: subleq(SW_ZZ, ZERO, user_thread_path) - if SW_ZZ <= 0, branch */
        /* But since SW_ZZ = -r3, if r3 > 0 then SW_ZZ < 0, so always branches! */
        /* We need a different approach. */
        
        /* Alternative: Check if SW_ZZ != 0 (kernel thread) */
        /* Actually let's be more direct: check if [SP] (r3) is 0 */
        /* Negate back: SW_ZZ2 = -SW_ZZ = r3 */
        .word   SW_ZZ2, SW_ZZ2, .Lrff_check_r3_3
.Lrff_check_r3_3:
        .word   SW_ZZ, SW_ZZ2, .Lrff_check_r3_4    /* SW_ZZ2 = -SW_ZZ = r3 */
.Lrff_check_r3_4:
        /* Now SW_ZZ2 = r3. Test if r3 == 0 (user thread) or r3 != 0 (kernel thread) */
        /* subleq(SW_ZZ2, ZERO, target) - branches to target if 0 - SW_ZZ2 <= 0 */
        /* i.e., branches if -SW_ZZ2 <= 0, i.e., branches if SW_ZZ2 >= 0 */
        /* This will branch for r3 >= 0, which is always true for valid pointers... */
        
        /* Let's use a simpler approach: test if r3 == 0 using subtraction */
        /* If SW_ZZ2 == 0, then subleq(SW_ZZ2, SW_ZZ2, fallthrough) will NOT branch */
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
        /* SW_ZZ2 = r3 */
        
        /* Step 1: if r3 < 0, it's a kernel thread (valid function pointer) */
        .word   SW_ZZ2, SW_ZZ, .Lrff_check_nonneg   /* Z -= r3; branches if Z <= 0 after, i.e., -r3 <= 0, i.e., r3 >= 0 */
        /* If we get here, r3 < 0. But pointers are positive... this is kernel thread */
        .word   SW_ZZ, SW_ZZ, .Lrff_kernel_thread

.Lrff_check_nonneg:
        /* r3 >= 0. Now check if r3 == 0 or r3 > 0 */
        /* Clear SW_ZZ first */
        .word   SW_ZZ, SW_ZZ, .Lrff_check_nonneg2
.Lrff_check_nonneg2:
        /* subleq(Z, r3_copy, target) - branches if r3 - 0 <= 0 => r3 <= 0 */
        /* Since we know r3 >= 0, this branches iff r3 == 0 */
        /* Use SW_ZZ2 which still holds r3 */
        .word   SW_ZZ, SW_ZZ2, .Lrff_user_thread   /* branches if r3 <= 0 (since r3 >= 0, this means r3 == 0) */
        /* Fall through: r3 > 0, it's a kernel thread */

.Lrff_kernel_thread:
        /*
         * KERNEL THREAD PATH
         * Call kernel_thread_helper(prev) - R21 already contains prev
         */
        /* Push return address onto stack using indirect addressing */
        .word   .Lrff_const4, REG_SP, .Lrff_kpush1  /* SP -= 4 */

.Lrff_kpush1:
        /* Clear [SP] using indirect addressing */
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .Lrff_kpush2

.Lrff_kpush2:
        /* Store loop address to [SP] (kernel threads should never return) */
        .word   SW_ZZ, SW_ZZ, .Lrff_kpush3
.Lrff_kpush3:
        .word   .Lrff_loop_addr, SW_ZZ, .Lrff_kpush4  /* SW_ZZ = -loop_addr */
.Lrff_kpush4:
        /* [SP] -= SW_ZZ => [SP] = loop_addr */
        .word   SW_ZZ, REG_SP | INDIRECT, .Lrff_kjump

.Lrff_kjump:
        /* Jump to kernel_thread_helper */
        .word   SW_ZZ, SW_ZZ, kernel_thread_helper

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
        .word   .Lrff_const4, REG_SP, .Lrff_upush1  /* SP -= 4 */

.Lrff_upush1:
        /* Clear [SP] using indirect addressing */
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .Lrff_upush2

.Lrff_upush2:
        /* Store .Lrff_user_return to [SP] */
        .word   SW_ZZ, SW_ZZ, .Lrff_upush3
.Lrff_upush3:
        .word   .Lrff_user_ret_addr, SW_ZZ, .Lrff_upush4  /* SW_ZZ = -return_addr */
.Lrff_upush4:
        /* [SP] -= SW_ZZ => [SP] = return_addr */
        .word   SW_ZZ, REG_SP | INDIRECT, .Lrff_ujump

.Lrff_ujump:
        /* Jump to ret_to_user_prep */
        .word   SW_ZZ, SW_ZZ, ret_to_user_prep

.Lrff_user_return:
        /*
         * ret_to_user_prep has returned.
         * R20 = pointer to pt_regs
         *
         * DEBUG: Print 'U' - DISABLED
         * .word   -4, .Lrff_char_U, .Lrff_debug1
         */
.Lrff_debug1:
        /*
         * pt_regs layout (offsets from base):
         *   r20: offset 68 (return value, 0 for fork child)
         *   sp:  offset 88 (user stack pointer)
         *   pc:  offset 96 (user PC to return to)
         *
         * We need to:
         * 1. Load pt_regs->pc into SW_ZZ2 (we'll jump to this)
         * 2. Load pt_regs->sp into hardware SP
         * 3. Load pt_regs->fp into hardware FP
         * 4. Load pt_regs->r20 into hardware R20
         * 5. Jump to the saved PC
         */

        /*
         * Step 1: Calculate &pt_regs->pc (R20 + 100) and load into SW_ZZ2
         * SW_ZZ2 will hold the PC value
         */
        .word   SW_ZZ, SW_ZZ, .Lrff_load_pc1
.Lrff_load_pc1:
        .word   REG_R20, SW_ZZ, .Lrff_load_pc2        /* SW_ZZ = -R20 */
.Lrff_load_pc2:
        .word   SW_ZZ2, SW_ZZ2, .Lrff_load_pc3
.Lrff_load_pc3:
        .word   SW_ZZ, SW_ZZ2, .Lrff_load_pc4         /* SW_ZZ2 = R20 (pt_regs base) */
.Lrff_load_pc4:
        .word   .Lrff_neg100, SW_ZZ2, .Lrff_load_pc5  /* SW_ZZ2 = R20 + 100 = &pt_regs->pc */
.Lrff_load_pc5:
        /* Load [SW_ZZ2] into SW_ZZ using indirect addressing */
        .word   SW_ZZ, SW_ZZ, .Lrff_load_pc6
.Lrff_load_pc6:
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .Lrff_load_pc7  /* SW_ZZ = -pc */
.Lrff_load_pc7:
        .word   SW_ZZ2, SW_ZZ2, .Lrff_load_pc8
.Lrff_load_pc8:
        .word   SW_ZZ, SW_ZZ2, .Lrff_load_sp          /* SW_ZZ2 = pc (user entry point) */

        /*
         * Step 2: Load pt_regs->sp (R20 + 92) into hardware SP
         */
.Lrff_load_sp:
        .word   SW_ZZ, SW_ZZ, .Lrff_load_sp1
.Lrff_load_sp1:
        .word   REG_R20, SW_ZZ, .Lrff_load_sp2        /* SW_ZZ = -R20 */
.Lrff_load_sp2:
        /* Calculate R20 + 92 into a temp location - reuse RA as scratch */
        .word   REG_RA, REG_RA, .Lrff_load_sp3
.Lrff_load_sp3:
        .word   SW_ZZ, REG_RA, .Lrff_load_sp4         /* RA = R20 */
.Lrff_load_sp4:
        .word   .Lrff_neg92, REG_RA, .Lrff_load_sp5   /* RA = R20 + 92 = &pt_regs->sp */
.Lrff_load_sp5:
        /* Load [RA] into SW_ZZ */
        .word   SW_ZZ, SW_ZZ, .Lrff_load_sp6
.Lrff_load_sp6:
        .word   REG_RA | INDIRECT, SW_ZZ, .Lrff_load_sp7  /* SW_ZZ = -sp */
.Lrff_load_sp7:
        /* Set hardware SP = -SW_ZZ = sp */
        .word   REG_SP, REG_SP, .Lrff_load_sp8
.Lrff_load_sp8:
        .word   SW_ZZ, REG_SP, .Lrff_load_fp          /* SP = user sp */

        /*
         * Step 3: Load pt_regs->fp (R20 + 88) into hardware FP
         * This is CRITICAL - the child needs the parent's frame pointer!
         */
.Lrff_load_fp:
        .word   SW_ZZ, SW_ZZ, .Lrff_load_fp1
.Lrff_load_fp1:
        .word   REG_R20, SW_ZZ, .Lrff_load_fp2        /* SW_ZZ = -R20 */
.Lrff_load_fp2:
        .word   REG_RA, REG_RA, .Lrff_load_fp3
.Lrff_load_fp3:
        .word   SW_ZZ, REG_RA, .Lrff_load_fp4         /* RA = R20 */
.Lrff_load_fp4:
        .word   .Lrff_neg88, REG_RA, .Lrff_load_fp5   /* RA = R20 + 88 = &pt_regs->fp */
.Lrff_load_fp5:
        /* Load [RA] into SW_ZZ */
        .word   SW_ZZ, SW_ZZ, .Lrff_load_fp6
.Lrff_load_fp6:
        .word   REG_RA | INDIRECT, SW_ZZ, .Lrff_load_fp7  /* SW_ZZ = -fp */
.Lrff_load_fp7:
        /* Set hardware FP = -SW_ZZ = fp */
        .word   REG_FP, REG_FP, .Lrff_load_fp8
.Lrff_load_fp8:
        .word   SW_ZZ, REG_FP, .Lrff_load_r20         /* FP = user fp */

        /*
         * Step 4: Load pt_regs->r20 (R20 + 68) into hardware R20
         * This is the fork return value (0 for child)
         */
.Lrff_load_r20:
        /* First save the current R20 (pt_regs pointer) to SW_ZZ temporarily */
        .word   SW_ZZ, SW_ZZ, .Lrff_load_r20_1
.Lrff_load_r20_1:
        .word   REG_R20, SW_ZZ, .Lrff_load_r20_2      /* SW_ZZ = -R20 (save pt_regs ptr) */
.Lrff_load_r20_2:
        /* Calculate &pt_regs->r20 using RA as scratch */
        .word   REG_RA, REG_RA, .Lrff_load_r20_3
.Lrff_load_r20_3:
        .word   SW_ZZ, REG_RA, .Lrff_load_r20_4       /* RA = R20 (pt_regs base) */
.Lrff_load_r20_4:
        .word   .Lrff_neg68, REG_RA, .Lrff_load_r20_5 /* RA = R20 + 68 = &pt_regs->r20 */
.Lrff_load_r20_5:
        /* Load [RA] into SW_ZZ */
        .word   SW_ZZ, SW_ZZ, .Lrff_load_r20_6
.Lrff_load_r20_6:
        .word   REG_RA | INDIRECT, SW_ZZ, .Lrff_load_r20_7  /* SW_ZZ = -r20_value */
.Lrff_load_r20_7:
        /* Set hardware R20 = -SW_ZZ = r20_value (0 for child) */
        .word   REG_R20, REG_R20, .Lrff_load_r20_8
.Lrff_load_r20_8:
        .word   SW_ZZ, REG_R20, .Lrff_jump_user       /* R20 = fork return value */

        /*
         * Step 5: Jump to user PC (saved in SW_ZZ2)
         * DEBUG: Print 'R' and R20 - DISABLED, jump directly
         */
.Lrff_jump_user:
        /* Jump directly without debug output */
        .word   SW_ZZ, SW_ZZ, .Lrff_jump_user2

/* Disabled debug code:
.Lrff_print_r20:
        .word   REG_RA, REG_RA, .Lrff_print_r20_1
.Lrff_print_r20_1:
        .word   SW_ZZ, SW_ZZ, .Lrff_print_r20_2
.Lrff_print_r20_2:
        .word   .Lrff_char_zero, SW_ZZ, .Lrff_print_r20_3
.Lrff_print_r20_3:
        .word   SW_ZZ, REG_RA, .Lrff_print_r20_4
.Lrff_print_r20_4:
        .word   SW_ZZ, SW_ZZ, .Lrff_print_r20_5
.Lrff_print_r20_5:
        .word   REG_R20, SW_ZZ, .Lrff_print_r20_6
.Lrff_print_r20_6:
        .word   SW_ZZ, REG_RA, .Lrff_print_r20_7
.Lrff_print_r20_7:
        .word   -4, REG_RA, .Lrff_do_jump
*/

.Lrff_do_jump:
        /* Just jump to userspace - no extra debug (was crashing) */
        .word   SW_ZZ, SW_ZZ, .Lrff_jump_user2

.Lrff_jump_user2:
        /* Indirect jump: subleq(Z, Z, SW_ZZ2|I) jumps to m[SW_ZZ2] */
        .word   SW_ZZ
        .word   SW_ZZ
        .word   SW_ZZ2 | INDIRECT

.Lrff_loop:
        /* Infinite loop - should never reach here for kernel threads */
        .word   SW_ZZ, SW_ZZ, .Lrff_loop

.Lrff_loop_addr:
        .word   .Lrff_loop
.Lrff_user_ret_addr:
        .word   .Lrff_user_return
.Lrff_const4:
        .word   4
.Lrff_neg68:
        .word   -68     /* Offset to pt_regs->r20 */
.Lrff_neg88:
        .word   -88     /* Offset to pt_regs->fp (NEW!) */
.Lrff_neg92:
        .word   -92     /* Offset to pt_regs->sp (was 88) */
.Lrff_neg100:
        .word   -100    /* Offset to pt_regs->pc (was 96) */
.Lrff_char_U:
        .word   85      /* 'U' */
.Lrff_char_R:
        .word   82      /* 'R' */
.Lrff_char_zero:
        .word   48      /* '0' */

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
        .word   .Ljtu_neg4, REG_SP, .Ljtu_set_ra

        /*
         * Set RA to a halt loop as a safety backstop.
         * If the user binary returns (which it shouldn't), it will
         * jump to this loop instead of crashing on RA=0.
         */
.Ljtu_set_ra:
        .word   REG_RA, REG_RA, .Ljtu_set_ra1
.Ljtu_set_ra1:
        .word   SW_ZZ, SW_ZZ, .Ljtu_set_ra2
.Ljtu_set_ra2:
        .word   .Ljtu_halt_addr, SW_ZZ, .Ljtu_set_ra3  /* SW_ZZ = -halt_loop_addr */
.Ljtu_set_ra3:
        .word   SW_ZZ, REG_RA, .Ljtu_set_sp  /* RA = halt_loop_addr */

        /*
         * Set SP = R22 (the user stack pointer)
         */
.Ljtu_set_sp:
        /* Clear SP */
        .word   REG_SP, REG_SP, .Ljtu_set_sp1
.Ljtu_set_sp1:
        /* Get -R22 into SW_ZZ */
        .word   SW_ZZ, SW_ZZ, .Ljtu_set_sp2
.Ljtu_set_sp2:
        .word   REG_R22, SW_ZZ, .Ljtu_set_sp3  /* SW_ZZ = -R22 */
.Ljtu_set_sp3:
        /* SP -= SW_ZZ => SP = R22 */
        .word   SW_ZZ, REG_SP, .Ljtu_jump

        /*
         * Jump to R21 (the user entry point) using indirect addressing.
         * This is a RAW JUMP - no return address is pushed!
         */
.Ljtu_jump:
        .word   SW_ZZ, SW_ZZ, .Ljtu_jump2
.Ljtu_jump2:
        /* Indirect jump: subleq(Z, Z, R21|I) jumps to m[R21] */
        .word   SW_ZZ
        .word   SW_ZZ
        .word   REG_R21 | INDIRECT

        /*
         * Halt loop - if user binary returns, it will end up here
         */
.Ljtu_halt_loop:
        .word   SW_ZZ, SW_ZZ, .Ljtu_halt_loop

.Ljtu_halt_addr:
        .word   .Ljtu_halt_loop
.Ljtu_neg4:
        .word   -4

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
         * STEP 1: Save SP to global subleq_syscall_saved_sp
         */
        .word   subleq_syscall_saved_sp, subleq_syscall_saved_sp, .+4  /* clear */
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4  /* ZZ = 0 */
        .word   REG_SP, SYSCALL_ZZ, .+4       /* ZZ = -SP */
        .word   SYSCALL_ZZ, subleq_syscall_saved_sp, .+4  /* saved_sp = SP */
        
        /*
         * STEP 2: Save FP to global subleq_syscall_saved_fp
         */
        .word   subleq_syscall_saved_fp, subleq_syscall_saved_fp, .+4  /* clear */
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4  /* ZZ = 0 */
        .word   REG_FP, SYSCALL_ZZ, .+4       /* ZZ = -FP */
        .word   SYSCALL_ZZ, subleq_syscall_saved_fp, .+4  /* saved_fp = FP */

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
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4
        .word   subleq_kernel_sp, SYSCALL_ZZ, .+4  /* ZZ = -kernel_sp */
        .word   SYSCALL_ZZ, REG_SP, .+4   /* SP = kernel_sp */

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
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4
        .word   subleq_syscall_saved_sp, SYSCALL_ZZ, .+4           /* ZZ = -saved_sp */
        .word   SYSCALL_ZZ, REG_T8, .+4                            /* T8 = saved_sp */
        .word   .Lsyscall_neg12, REG_T8, .+4                       /* T8 = saved_sp + 12 */
        
        /* Load [T8] into SYSCALL_ZZ using indirect addressing */
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4
        .word   REG_T8 | INDIRECT, SYSCALL_ZZ, .+4                 /* ZZ = -[T8] = -a6 */
        
        /* Push -ZZ onto kernel stack */
        .word   .Lsyscall_4, REG_SP, .+4                           /* SP -= 4 */
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4          /* [SP] = 0 */
        .word   SYSCALL_ZZ, REG_SP | INDIRECT, .+4                 /* [SP] = a6 */
        
        /* ---- Push a5 (from [saved_sp + 8]) ---- */
        .word   REG_T8, REG_T8, .+4                                /* T8 = 0 */
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4
        .word   subleq_syscall_saved_sp, SYSCALL_ZZ, .+4           /* ZZ = -saved_sp */
        .word   SYSCALL_ZZ, REG_T8, .+4                            /* T8 = saved_sp */
        .word   .Lsyscall_neg8, REG_T8, .+4                        /* T8 = saved_sp + 8 */
        
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4
        .word   REG_T8 | INDIRECT, SYSCALL_ZZ, .+4                 /* ZZ = -a5 */
        
        .word   .Lsyscall_4, REG_SP, .+4                           /* SP -= 4 */
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4          /* [SP] = 0 */
        .word   SYSCALL_ZZ, REG_SP | INDIRECT, .+4                 /* [SP] = a5 */
        
        /* ---- Push a4 (from [saved_sp + 4]) ---- */
        .word   REG_T8, REG_T8, .+4                                /* T8 = 0 */
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4
        .word   subleq_syscall_saved_sp, SYSCALL_ZZ, .+4           /* ZZ = -saved_sp */
        .word   SYSCALL_ZZ, REG_T8, .+4                            /* T8 = saved_sp */
        .word   .Lsyscall_neg4_for_usp, REG_T8, .+4                /* T8 = saved_sp + 4 */
        
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4
        .word   REG_T8 | INDIRECT, SYSCALL_ZZ, .+4                 /* ZZ = -a4 */
        
        .word   .Lsyscall_4, REG_SP, .+4                           /* SP -= 4 */
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4          /* [SP] = 0 */
        .word   SYSCALL_ZZ, REG_SP | INDIRECT, .+4                 /* [SP] = a4 */

        /*
         * STEP 5: Set up call frame and call __subleq_syscall_c
         *
         * Using Subleq+ indirect addressing to push return address onto stack.
         * This avoids SMC which was buggy in the previous implementation.
         *
         * Stack-based call sequence:
         *   1. SP -= 4 (make room for return address)
         *   2. Clear [SP] using indirect: subleq(SP|I, SP|I, next)
         *   3. Load -return_addr into SYSCALL_ZZ
         *   4. Store return_addr to [SP]: subleq(SYSCALL_ZZ, SP|I, next)
         *   5. Jump to function
         */
        
        /* Step 1: SP -= 4 */
        .word   .Lsyscall_4, REG_SP, .+4  /* SP = SP - 4 */
        
        /* Step 2: Clear [SP] using indirect addressing */
        /* subleq(SP|I, SP|I, next) does: m[m[SP]] -= m[m[SP]] => m[SP] = 0 */
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4
        
        /* Step 3: Get -return_addr into SYSCALL_ZZ */
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4
        .word   .Lsyscall_c_ret_addr, SYSCALL_ZZ, .+4  /* ZZ = -return_point */
        
        /* Step 4: Store return_addr to [SP] using indirect addressing */
        /* subleq(SYSCALL_ZZ, SP|I, next) does: m[m[SP]] -= SYSCALL_ZZ => m[SP] = 0 - (-addr) = addr */
        .word   SYSCALL_ZZ, REG_SP | INDIRECT, .+4

        /* Step 5: Jump to C handler */
        .word   SYSCALL_ZZ, SYSCALL_ZZ, __subleq_syscall_c


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

        /* DEBUG: Print 'X' to mark syscall return path entry - disabled
        .word   -4, .Lsyscall_char_X, .+4
        */
        
        /* DEBUG: Check R20 - disabled
        .word   .Lsyscall_r20_check, .Lsyscall_r20_check, .+4
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4
        .word   REG_R20, SYSCALL_ZZ, .+4
        .word   SYSCALL_ZZ, .Lsyscall_r20_check, .+4
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4
        .word   SYSCALL_ZZ, .Lsyscall_r20_check, .Lsyscall_child_ret
        .word   -4, .Lsyscall_char_P, .+4
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .Lsyscall_start_restore
.Lsyscall_child_ret:
        .word   -4, .Lsyscall_char_C, .+4
        */
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .Lsyscall_start_restore

.Lsyscall_r20_check:
        .word   0                                              /* scratch for R20 test */

.Lsyscall_start_restore:

        /*
         * STEP 1: Compute pt_regs base address
         * pt_regs_addr = subleq_kernel_sp + 256
         * Store in .Lsyscall_ptregs_addr for reuse
         */
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4           /* ZZ = 0 */
        .word   subleq_kernel_sp, SYSCALL_ZZ, .+4     /* ZZ = -kernel_sp */
        .word   .Lsyscall_ptregs_addr, .Lsyscall_ptregs_addr, .+4  /* clear */
        .word   SYSCALL_ZZ, .Lsyscall_ptregs_addr, .+4  /* = kernel_sp */
        .word   .Lsyscall_neg256, .Lsyscall_ptregs_addr, .+4  /* += 256 */

        /*
         * STEP 2: Load SP from pt_regs->sp (offset 92)
         * Compute &pt_regs->sp into REG_T8, then use REG_T8|INDIRECT to load
         */
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4           /* ZZ = 0 */
        .word   .Lsyscall_ptregs_addr, SYSCALL_ZZ, .+4  /* ZZ = -pt_regs */
        .word   REG_T8, REG_T8, .+4                   /* T8 = 0 */
        .word   SYSCALL_ZZ, REG_T8, .+4               /* T8 = pt_regs */
        .word   .Lsyscall_neg92, REG_T8, .+4          /* T8 = pt_regs + 92 = &sp */
        
        /* Load [T8] (the sp value) via indirect addressing */
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4
        .word   REG_T8 | INDIRECT, SYSCALL_ZZ, .+4    /* ZZ = -[T8] = -sp */
        .word   REG_SP, REG_SP, .+4                   /* SP = 0 */
        .word   SYSCALL_ZZ, REG_SP, .+4               /* SP = sp value */

        /*
         * STEP 3: Load FP from pt_regs->fp (offset 88)
         */
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4
        .word   .Lsyscall_ptregs_addr, SYSCALL_ZZ, .+4
        .word   REG_T8, REG_T8, .+4
        .word   SYSCALL_ZZ, REG_T8, .+4               /* T8 = pt_regs */
        .word   .Lsyscall_neg88, REG_T8, .+4          /* T8 = pt_regs + 88 = &fp */
        
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4
        .word   REG_T8 | INDIRECT, SYSCALL_ZZ, .+4    /* ZZ = -fp */
        .word   REG_FP, REG_FP, .+4                   /* FP = 0 */
        .word   SYSCALL_ZZ, REG_FP, .+4               /* FP = fp value */

        /*
         * STEP 4: Load PC from pt_regs->pc (offset 100) and jump to it
         *
         * Store PC in SW_ZZ2 (address 444), then jump via 446 (SW_ZZ2|INDIRECT).
         * Same pattern as ret_from_fork.
         */
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4
        .word   .Lsyscall_ptregs_addr, SYSCALL_ZZ, .+4
        .word   REG_T8, REG_T8, .+4
        .word   SYSCALL_ZZ, REG_T8, .+4               /* T8 = pt_regs */
        .word   .Lsyscall_neg100, REG_T8, .+4         /* T8 = pt_regs + 100 = &pc */
        
        /* Load [T8] (the pc value) into SW_ZZ2 (address 444) */
        .word   SYSCALL_ZZ, SYSCALL_ZZ, .+4
        .word   REG_T8 | INDIRECT, SYSCALL_ZZ, .+4    /* ZZ = -pc */
        .word   SW_ZZ2, SW_ZZ2, .+4                   /* clear SW_ZZ2 */
        .word   SYSCALL_ZZ, SW_ZZ2, .+4               /* SW_ZZ2 = pc */
        
        /* DEBUG: Print '>' then hex dump of PC - DISABLED
        .word   -4, .Lsyscall_char_gt, .+4
        ... debug_print_hex call ...
        */
        
        /* Jump to m[SW_ZZ2] = pc value */
        /* SW_ZZ2 | INDIRECT = 444 | 2 = 446 */
        .word   SYSCALL_ZZ, SYSCALL_ZZ, 446

.Lsyscall_char_gt:
        .word   62      /* '>' */

/* Local data for __subleq_syscall */
.Lsyscall_c_ret_addr:
        .word   .Lsyscall_c_return

.Lsyscall_tmp_addr:
        .word   0

.Lsyscall_neg4:
        .word   -4

.Lsyscall_neg2:
        .word   -2

.Lsyscall_4:
        .word   4

.Lsyscall_debug_char:
        .word   0

.Lsyscall_neg38:
        .word   -38

/* New constants for pt_regs-based syscall return (vfork fix) */
.Lsyscall_ptregs_addr:
        .word   0

.Lsyscall_neg256:
        .word   -256

.Lsyscall_neg88:
        .word   -88

.Lsyscall_neg92:
        .word   -92

.Lsyscall_neg100:
        .word   -100

/* Constants for forwarding syscall args 5-7 from userspace stack */
.Lsyscall_ustack_addr:
        .word   0               /* scratch for userspace stack address calculation */

.Lsyscall_neg4_for_usp:
        .word   -4              /* for saved_sp + 4 (arg 5) */

.Lsyscall_neg8:
        .word   -8              /* for saved_sp + 8 (arg 6) */

.Lsyscall_neg12:
        .word   -12             /* for saved_sp + 12 (arg 7) */

/* Debug character for syscall return tracing */
.Lsyscall_char_X:
        .word   88  /* 'X' */
.Lsyscall_char_P:
        .word   80  /* 'P' for parent (R20 > 0) */
.Lsyscall_char_C:
        .word   67  /* 'C' for child-like return (R20 <= 0) */

/* Debug constants - disabled but kept for reference
.Lsyscall_debug_ret_addr:
        .word   .Lsyscall_debug_ret
*/

.size __subleq_syscall, .-__subleq_syscall


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

