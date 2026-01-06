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
 */
subleq_irq_entry:
        /* DEBUG disabled - was printing 'A' */
        /* .word   -4, .Lchar_A, .Ldisable0 */

        /* PHASE 0: DISABLE INTERRUPTS */
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

        /* PHASE 1: SAVE ALL REGISTERS */
.Lsave_z:
        SAVE_REG REG_Z, SAVE_Z, .Lsave_sp
.Lsave_sp:
        SAVE_REG REG_SP, SAVE_SP, .Lsave_ra
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

/*
 * Trivial test function - just returns via RA using indirect jump
 * To call: set RA = return address, then jump here
 */
.globl test_return
.type test_return, @function
test_return:
        /* Print 'X' to show we got here */
        .word   -4, .Lchar_X, .Ltest_do_return
.Ltest_do_return:
        /* Return via RA using Subleq+ indirect jump */
        /* Clear INT_ZZ for unconditional jump */
        .word   INT_ZZ, INT_ZZ, .Ltest_ret1
.Ltest_ret1:
        /* Indirect jump: subleq(Z, Z, RA|I) always jumps to m[RA] */
        .word   INT_ZZ
        .word   INT_ZZ
        .word   REG_RA | INDIRECT
.size test_return, .-test_return

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
         * NOTE: The caller has ALREADY pushed the return address to the stack
         * before jumping here. This is the Subleq C calling convention:
         *   Caller does: SP -= 4; [SP] = return_addr; jump function
         *
         * So on entry, SP points to the return address on the stack.
         * We do NOT push RA here - RA is a scratch register with garbage.
         *
         * We simply save SP (which points to the stacked return address),
         * and later when we restore SP, we pop that return address.
         */

        /*
         * Step 2: Save SP to prev->thread.sp
         * prev is in R21, offset is TASK_THREAD_SP (1180)
         *
         * Calculate address into SW_ZZ2, then use indirect store
         */
.Lsw_save_sp:
        /* SW_ZZ = R21 (prev) */
        .word   SW_ZZ, SW_ZZ, .Lsw_save_sp1
.Lsw_save_sp1:
        .word   REG_R21, SW_ZZ, .Lsw_save_sp2
.Lsw_save_sp2:
        .word   SW_ZZ2, SW_ZZ2, .Lsw_save_sp3
.Lsw_save_sp3:
        .word   SW_ZZ, SW_ZZ2, .Lsw_save_sp4         /* SW_ZZ2 = R21 */
.Lsw_save_sp4:
        .word   .Loffset_neg, SW_ZZ2, .Lsw_save_sp5  /* SW_ZZ2 = R21 + 1180 = &prev->thread.sp */

.Lsw_save_sp5:
        /* Clear [SW_ZZ2] using indirect addressing */
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .Lsw_save_sp6

.Lsw_save_sp6:
        /* Store SP: first get -SP into SW_ZZ */
        .word   SW_ZZ, SW_ZZ, .Lsw_save_sp7
.Lsw_save_sp7:
        .word   REG_SP, SW_ZZ, .Lsw_save_sp8
.Lsw_save_sp8:
        /* [SW_ZZ2] -= SW_ZZ => prev->thread.sp = SP */
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_save_fp

        /*
         * Step 2b: Save FP to prev->thread.fp
         */
.Lsw_save_fp:
        /* Calculate &prev->thread.fp into SW_ZZ2 */
        .word   SW_ZZ, SW_ZZ, .Lsw_save_fp1
.Lsw_save_fp1:
        .word   REG_R21, SW_ZZ, .Lsw_save_fp2
.Lsw_save_fp2:
        .word   SW_ZZ2, SW_ZZ2, .Lsw_save_fp3
.Lsw_save_fp3:
        .word   SW_ZZ, SW_ZZ2, .Lsw_save_fp4         /* SW_ZZ2 = R21 */
.Lsw_save_fp4:
        .word   .Loffset_fp_neg, SW_ZZ2, .Lsw_save_fp5  /* SW_ZZ2 = R21 + 1184 = &prev->thread.fp */

.Lsw_save_fp5:
        /* Clear [SW_ZZ2] */
        .word   SW_ZZ2 | INDIRECT, SW_ZZ2 | INDIRECT, .Lsw_save_fp6

.Lsw_save_fp6:
        /* Store FP: get -FP into SW_ZZ */
        .word   SW_ZZ, SW_ZZ, .Lsw_save_fp7
.Lsw_save_fp7:
        .word   REG_FP, SW_ZZ, .Lsw_save_fp8
.Lsw_save_fp8:
        /* [SW_ZZ2] -= SW_ZZ => prev->thread.fp = FP */
        .word   SW_ZZ, SW_ZZ2 | INDIRECT, .Lsw_update_current

        /*
         * Step 3: Update subleq_current_task = next
         */
.Lsw_update_current:
        .word   SW_ZZ, SW_ZZ, .Lsw_update1
.Lsw_update1:
        .word   REG_R22, SW_ZZ, .Lsw_update2         /* SW_ZZ = -next */
.Lsw_update2:
        .word   subleq_current_task, subleq_current_task, .Lsw_update3
.Lsw_update3:
        .word   SW_ZZ, subleq_current_task, .Lsw_load_sp  /* current = next */

        /*
         * Step 4: Load SP from next->thread.sp
         */
.Lsw_load_sp:
        /* Calculate &next->thread.sp into SW_ZZ2 */
        .word   SW_ZZ, SW_ZZ, .Lsw_load_sp1
.Lsw_load_sp1:
        .word   REG_R22, SW_ZZ, .Lsw_load_sp2
.Lsw_load_sp2:
        .word   SW_ZZ2, SW_ZZ2, .Lsw_load_sp3
.Lsw_load_sp3:
        .word   SW_ZZ, SW_ZZ2, .Lsw_load_sp4         /* SW_ZZ2 = R22 */
.Lsw_load_sp4:
        .word   .Loffset_neg, SW_ZZ2, .Lsw_load_sp5  /* SW_ZZ2 = R22 + 1180 = &next->thread.sp */

.Lsw_load_sp5:
        /* Load [SW_ZZ2] into SW_ZZ using indirect addressing */
        /* subleq(SW_ZZ2|I, SW_ZZ, next) does: SW_ZZ -= m[SW_ZZ2] => SW_ZZ = -next->thread.sp */
        .word   SW_ZZ, SW_ZZ, .Lsw_load_sp6
.Lsw_load_sp6:
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .Lsw_load_sp7

.Lsw_load_sp7:
        /* SP = -SW_ZZ = next->thread.sp */
        .word   REG_SP, REG_SP, .Lsw_load_sp8
.Lsw_load_sp8:
        .word   SW_ZZ, REG_SP, .Lsw_load_fp

        /*
         * Step 4b: Load FP from next->thread.fp
         */
.Lsw_load_fp:
        /* Calculate &next->thread.fp into SW_ZZ2 */
        .word   SW_ZZ, SW_ZZ, .Lsw_load_fp1
.Lsw_load_fp1:
        .word   REG_R22, SW_ZZ, .Lsw_load_fp2
.Lsw_load_fp2:
        .word   SW_ZZ2, SW_ZZ2, .Lsw_load_fp3
.Lsw_load_fp3:
        .word   SW_ZZ, SW_ZZ2, .Lsw_load_fp4         /* SW_ZZ2 = R22 */
.Lsw_load_fp4:
        .word   .Loffset_fp_neg, SW_ZZ2, .Lsw_load_fp5  /* SW_ZZ2 = R22 + 1184 = &next->thread.fp */

.Lsw_load_fp5:
        /* Load [SW_ZZ2] into SW_ZZ */
        .word   SW_ZZ, SW_ZZ, .Lsw_load_fp6
.Lsw_load_fp6:
        .word   SW_ZZ2 | INDIRECT, SW_ZZ, .Lsw_load_fp7

.Lsw_load_fp7:
        /* FP = -SW_ZZ = next->thread.fp */
        .word   REG_FP, REG_FP, .Lsw_load_fp8
.Lsw_load_fp8:
        .word   SW_ZZ, REG_FP, .Lsw_set_retval

        /*
         * Step 5: Set return value R20 = prev (R21)
         */
.Lsw_set_retval:
        .word   SW_ZZ, SW_ZZ, .Lsw_set_retval1
.Lsw_set_retval1:
        .word   REG_R21, SW_ZZ, .Lsw_set_retval2     /* SW_ZZ = -prev */
.Lsw_set_retval2:
        .word   REG_R20, REG_R20, .Lsw_set_retval3
.Lsw_set_retval3:
        .word   SW_ZZ, REG_R20, .Lsw_pop_ra          /* R20 = prev */

        /*
         * Step 6: Pop return address from stack and return
         *
         * The return address was pushed by the CALLER of __switch_to before
         * jumping here. We saved SP (which points to that return address),
         * and now we restore SP and pop that same return address.
         */
.Lsw_pop_ra:
        /* Load [SP] into SW_ZZ using indirect addressing */
        .word   SW_ZZ, SW_ZZ, .Lsw_pop1
.Lsw_pop1:
        /* subleq(SP|I, SW_ZZ, next) does: SW_ZZ -= m[SP] => SW_ZZ = -return_addr */
        .word   REG_SP | INDIRECT, SW_ZZ, .Lsw_pop2

.Lsw_pop2:
        /* RA = -SW_ZZ = return_addr */
        .word   REG_RA, REG_RA, .Lsw_pop3
.Lsw_pop3:
        .word   SW_ZZ, REG_RA, .Lsw_pop4

.Lsw_pop4:
        /* SP += 4 (pop the return address) */
        .word   .Lconst_neg4, REG_SP, .Lsw_return

        /*
         * Step 7: Return via RA using indirect jump
         */
.Lsw_return:
        /* Clear SW_ZZ for the unconditional jump */
        .word   SW_ZZ, SW_ZZ, .Lsw_do_ret1
.Lsw_do_ret1:
        /* Indirect jump: subleq(Z, Z, RA|I) jumps to m[RA] */
        .word   SW_ZZ
        .word   SW_ZZ
        .word   REG_RA | INDIRECT

/* Data for __switch_to */
.Loffset_neg:
        .word   -1180           /* Negative of TASK_THREAD_SP offset */
.Loffset_fp_neg:
        .word   -1184           /* Negative of TASK_THREAD_FP offset */
.Lconst_neg4:
        .word   -4
/* Note: .Lconst_4 is defined earlier in the file (in irq handler section) */

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
         * Call ret_to_user_prep(prev) which will:
         * 1. Call schedule_tail(prev)
         * 2. Return with R20 = pc, R21 = sp (userspace entry point and stack)
         * Then we set SP and jump to PC.
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
         * R20 = pc (userspace entry point)
         * R21 = sp (userspace stack pointer)
         *
         * Now we need to:
         * 1. Set hardware SP (memory location 16) to R21
         * 2. Jump to R20
         */

        /* Step 1: SP = R21 */
        /* Clear SP */
        .word   REG_SP, REG_SP, .Lrff_set_sp1
.Lrff_set_sp1:
        /* Get -R21 into SW_ZZ */
        .word   SW_ZZ, SW_ZZ, .Lrff_set_sp2
.Lrff_set_sp2:
        .word   REG_R21, SW_ZZ, .Lrff_set_sp3  /* SW_ZZ = -R21 */
.Lrff_set_sp3:
        /* SP -= SW_ZZ => SP = R21 */
        .word   SW_ZZ, REG_SP, .Lrff_jump_user

        /* Step 2: Jump to R20 using indirect addressing */
.Lrff_jump_user:
        .word   SW_ZZ, SW_ZZ, .Lrff_jump_user2
.Lrff_jump_user2:
        /* Indirect jump: subleq(Z, Z, R20|I) jumps to m[R20] */
        .word   SW_ZZ
        .word   SW_ZZ
        .word   REG_R20 | INDIRECT

.Lrff_loop:
        /* Infinite loop - should never reach here for kernel threads */
        .word   SW_ZZ, SW_ZZ, .Lrff_loop

.Lrff_loop_addr:
        .word   .Lrff_loop
.Lrff_user_ret_addr:
        .word   .Lrff_user_return
.Lrff_const4:
        .word   4

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
