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
        .word   -4, .Lchar_A, .Ldisable0

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
        .word   -4, .Lchar_B, .Lsave_z

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
        SAVE_REG REG_T15, SAVE_T15, .Lsave_done

.Lsave_done:
        /* DEBUG: Print 'C' (67) - after save */
        .word   -4, .Lchar_C, .Lirq_call

        /* PHASE 2: CALL C HANDLER */
.Lirq_call:
        /* DEBUG: Print 'D' (68) - before C call */
        .word   -4, .Lchar_D, .Lirq_do_call

        /*
         * STACK-BASED CALL to subleq_do_IRQ
         *
         * The C compiler expects the return address to be ON THE STACK,
         * not in RA. We must:
         * 1. SP -= 4 (make room)
         * 2. Store return address at [SP]
         * 3. Jump to function
         *
         * This is complex in Subleq because we need self-modifying code
         * to store to [SP] (indirect write).
         */

.Lirq_do_call:
        /* Step 1: SP -= 4 (decrement stack pointer) */
        /* SP -= 4 can be done as: SP -= const_4 */
        .word   .Lconst_4, REG_SP, .Lcall_step2

.Lcall_step2:
        /* Step 2: Store .Lirq_returned at [SP] using self-modifying code */
        /*
         * We need to write to memory at address SP.
         * Use INT_ZZ as scratch.
         *
         * 2a: Get -SP into INT_ZZ
         * 2b: Patch the 'a' field of a clear instruction with SP
         * 2c: Patch the 'b' field of a clear instruction with SP
         * 2d: Execute the patched clear to zero [SP]
         * 2e: Store return address to [SP] via another patched instruction
         */

        /* 2a: INT_ZZ = -SP */
        .word   INT_ZZ, INT_ZZ, .Lcall_step2a
.Lcall_step2a:
        .word   REG_SP, INT_ZZ, .Lcall_step2b

        /* 2b: Patch .Lcall_clear_a with SP (clear a-field) */
.Lcall_step2b:
        .word   .Lcall_clear_a, .Lcall_clear_a, .Lcall_step2c
.Lcall_step2c:
        .word   INT_ZZ, .Lcall_clear_a, .Lcall_step2d

        /* 2d: Patch .Lcall_clear_b with SP (clear b-field) */
.Lcall_step2d:
        .word   .Lcall_clear_b, .Lcall_clear_b, .Lcall_step2e
.Lcall_step2e:
        .word   INT_ZZ, .Lcall_clear_b, .Lcall_do_clear

        /* Execute patched clear: mem[SP] = 0 */
.Lcall_do_clear:
        .word   0, 0, .Lcall_step3       /* a,b patched to SP */
.Lcall_clear_a = .Lcall_do_clear + 0
.Lcall_clear_b = .Lcall_do_clear + 4

.Lcall_step3:
        /* Step 3: Store return address at [SP] */
        /* mem[SP] -= (-return_addr) => mem[SP] = return_addr */

        /* 3a: INT_ZZ = -return_addr */
        .word   INT_ZZ, INT_ZZ, .Lcall_step3a
.Lcall_step3a:
        .word   .Lirq_return_addr, INT_ZZ, .Lcall_step3b

        /* 3b: Patch store instruction b-field with SP */
.Lcall_step3b:
        .word   INT_ZZ, INT_ZZ, .Lcall_step3c   /* Clear INT_ZZ first */
.Lcall_step3c:
        .word   REG_SP, INT_ZZ, .Lcall_step3d    /* INT_ZZ = -SP */
.Lcall_step3d:
        .word   .Lcall_store_b, .Lcall_store_b, .Lcall_step3e  /* Clear patch target */
.Lcall_step3e:
        .word   INT_ZZ, .Lcall_store_b, .Lcall_step3f  /* Patch with SP */

        /* 3f: Get -return_addr into INT_ZZ again */
.Lcall_step3f:
        .word   INT_ZZ, INT_ZZ, .Lcall_step3g
.Lcall_step3g:
        .word   .Lirq_return_addr, INT_ZZ, .Lcall_do_store

        /* Execute patched store: mem[SP] -= INT_ZZ => mem[SP] = return_addr */
.Lcall_do_store:
        .word   INT_ZZ, 0, .Lcall_jump    /* b patched to SP */
.Lcall_store_b = .Lcall_do_store + 4

        /* Step 4: Jump to subleq_do_IRQ */
.Lcall_jump:
        .word   INT_ZZ, INT_ZZ, subleq_do_IRQ

        /* PHASE 3: RESTORE ALL REGISTERS */
.Lirq_returned:
        /* DEBUG: Print 'E' (69) - after C call */
        .word   -4, .Lchar_E, .Lrestore_t15

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
        .word   -4, .Lchar_F, .Lirq_return

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
        .word   -4, .Lchar_G, .Ldo_jump

        /* PHASE 5+6: SET UP JUMP, THEN RE-ENABLE, THEN JUMP */
        /*
         * We must set up the jump target BEFORE re-enabling interrupts,
         * because once interrupts are enabled, a new interrupt could
         * clobber SAVE_JMPTGT.
         */
.Ldo_jump:
        /* DEBUG: Print 'H' (72) - setting up jump */
        .word   -4, .Lchar_H, .Ljump_setup

.Ljump_setup:
        /* First, patch the jump target while interrupts are still disabled */
        .word   INT_ZZ, INT_ZZ, .Ljump1
.Ljump1:
        .word   SAVE_JMPTGT, INT_ZZ, .Ljump2
.Ljump2:
        .word   .Lirq_jmp_target, .Lirq_jmp_target, .Ljump3
.Ljump3:
        .word   INT_ZZ, .Lirq_jmp_target, .Lenable_irq

        /* Now re-enable interrupts (jump target is already patched) */
.Lenable_irq:
        .word   INT_ZZ, INT_ZZ, .Lenable1
.Lenable1:
        .word   INT_SAVED_HANDLER, INT_ZZ, .Lenable2
.Lenable2:
        .word   INT_HANDLER, INT_HANDLER, .Lenable3
.Lenable3:
        /* Re-enable interrupts: m[0] = handler */
        .word   INT_ZZ, INT_HANDLER, .Ldo_return
        /* Fall through to .Ldo_return (result > 0 so no branch) */

.Ldo_return:
        /* Unconditional jump to patched target */
        /* subleq(INT_ZZ, INT_ZZ, target) always jumps because 0 <= 0 */
        .word   INT_ZZ, INT_ZZ, 0
.Lirq_jmp_target = .Ldo_return + 8

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
        .word   72
.Lchar_I:
        .word   73
.Lchar_X:
        .word   88
.Lchar_J:
        .word   74

/* Constant for stack operations */
.Lconst_4:
        .word   4

/*
 * Trivial test function - just returns via RA
 * To call: set RA = return address, then jump here
 */
.globl test_return
.type test_return, @function
test_return:
        /* Print 'X' to show we got here */
        .word   -4, .Lchar_X, .Ltest_do_return
.Ltest_do_return:
        /* Return via RA: jump to address in RA */
        /* Need to do indirect jump: read RA, jump to it */
        /* INT_ZZ = 0 */
        .word   INT_ZZ, INT_ZZ, .Ltest_ret1
.Ltest_ret1:
        /* INT_ZZ -= RA => INT_ZZ = -RA */
        .word   REG_RA, INT_ZZ, .Ltest_ret2
.Ltest_ret2:
        /* Clear jump target */
        .word   .Ltest_jmp_target, .Ltest_jmp_target, .Ltest_ret3
.Ltest_ret3:
        /* jmp_target -= INT_ZZ => jmp_target = RA */
        .word   INT_ZZ, .Ltest_jmp_target, .Ltest_do_jmp
.Ltest_do_jmp:
        /* Jump */
        .word   INT_ZZ, INT_ZZ, 0
.Ltest_jmp_target = .Ltest_do_jmp + 8
.size test_return, .-test_return

.size subleq_irq_entry, .-subleq_irq_entry

/*
 * ===========================================================================
 * Context Switch Implementation
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
 * This function:
 *   1. Saves callee-saved registers (R3-R19, R25-R31, RA) to prev's stack
 *   2. Saves SP to prev->thread.sp
 *   3. Loads SP from next->thread.sp
 *   4. Restores callee-saved registers from next's stack
 *   5. Returns (to the return address saved by next's previous switch)
 *
 * For NEW threads (first switch), the stack is set up by copy_thread so that:
 *   - The "return address" points to ret_from_fork
 *   - ret_from_fork will call the thread's function
 */

/* Offset of thread.sp in task_struct (TASK_THREAD + THREAD_SP = 1180 + 0) */
.set TASK_THREAD_SP, 1180

.globl __switch_to
.type __switch_to, @function
__switch_to:
        /* Debug: print 'S' for switch */
        .word   -4, .Lchar_S, .Lswitch_start

.Lswitch_start:
        /*
         * Step 1: Save return address to stack
         * We need to push RA so when we switch back, we return to caller
         * SP -= 4; mem[SP] = RA
         */
        .word   .Lconst_4, REG_SP, .Lsw_push_ra1

.Lsw_push_ra1:
        /* Store RA at [SP] using self-modifying code */
        /* Get -SP into INT_ZZ */
        .word   INT_ZZ, INT_ZZ, .Lsw_push_ra2
.Lsw_push_ra2:
        .word   REG_SP, INT_ZZ, .Lsw_push_ra3
.Lsw_push_ra3:
        /* Patch the clear instruction's A field with SP */
        .word   .Lsw_clr_a, .Lsw_clr_a, .Lsw_push_ra4
.Lsw_push_ra4:
        .word   INT_ZZ, .Lsw_clr_a, .Lsw_push_ra5
.Lsw_push_ra5:
        /* Patch the clear instruction's B field with SP */
        .word   .Lsw_clr_b, .Lsw_clr_b, .Lsw_push_ra6
.Lsw_push_ra6:
        .word   INT_ZZ, .Lsw_clr_b, .Lsw_do_clr
.Lsw_do_clr:
        /* Clear [SP] */
        .word   0, 0, .Lsw_push_ra7
.Lsw_clr_a = .Lsw_do_clr + 0
.Lsw_clr_b = .Lsw_do_clr + 4

.Lsw_push_ra7:
        /* Now store RA to [SP]: [SP] -= (-RA) */
        .word   INT_ZZ, INT_ZZ, .Lsw_push_ra8
.Lsw_push_ra8:
        .word   REG_RA, INT_ZZ, .Lsw_push_ra9
.Lsw_push_ra9:
        /* INT_ZZ now has -RA, get -SP again */
        /* Reuse: need to patch store instruction */
        .word   .Lsw_store_b, .Lsw_store_b, .Lsw_push_ra10
.Lsw_push_ra10:
        /* Get -SP */
        .word   REG_Z, REG_Z, .Lsw_push_ra11
.Lsw_push_ra11:
        .word   REG_SP, REG_Z, .Lsw_push_ra12
.Lsw_push_ra12:
        .word   REG_Z, .Lsw_store_b, .Lsw_do_store
.Lsw_do_store:
        /* [SP] -= INT_ZZ => [SP] = RA */
        .word   INT_ZZ, 0, .Lsw_save_sp
.Lsw_store_b = .Lsw_do_store + 4

        /*
         * Step 2: Save SP to prev->thread.sp
         * prev is in R21, offset is TASK_THREAD_SP
         */
.Lsw_save_sp:
        /* Calculate prev->thread.sp address = R21 + 1180 */
        /* We need to read [R21+1180] but Subleq only does indirect via patching */
        /* For simplicity, use R3 as scratch (it's callee-saved but we'll save it) */
        
        /* Actually, let's just use INT_ZZ and patch approach */
        /* First: compute address = R21 + 1180 into a scratch location */
        
        .word   INT_ZZ, INT_ZZ, .Lsw_save_sp1
.Lsw_save_sp1:
        .word   REG_R21, INT_ZZ, .Lsw_save_sp2   /* INT_ZZ = -R21 */
.Lsw_save_sp2:
        .word   .Lsw_addr_scratch, .Lsw_addr_scratch, .Lsw_save_sp3
.Lsw_save_sp3:
        .word   INT_ZZ, .Lsw_addr_scratch, .Lsw_save_sp4  /* addr_scratch = R21 */
.Lsw_save_sp4:
        .word   .Loffset_neg, .Lsw_addr_scratch, .Lsw_save_sp5 /* addr_scratch = R21 + 1180 */
        
.Lsw_save_sp5:
        /* Now addr_scratch has the address of prev->thread.sp */
        /* We need to store SP there */
        /* Patch a store instruction to write to [addr_scratch] */
        .word   INT_ZZ, INT_ZZ, .Lsw_save_sp6
.Lsw_save_sp6:
        .word   .Lsw_addr_scratch, INT_ZZ, .Lsw_save_sp7
.Lsw_save_sp7:
        /* Clear the target location first */
        .word   .Lsw_sp_clr_a2, .Lsw_sp_clr_a2, .Lsw_save_sp8
.Lsw_save_sp8:
        .word   INT_ZZ, .Lsw_sp_clr_a2, .Lsw_save_sp9
.Lsw_save_sp9:
        .word   .Lsw_sp_clr_b2, .Lsw_sp_clr_b2, .Lsw_save_sp10
.Lsw_save_sp10:
        .word   INT_ZZ, .Lsw_sp_clr_b2, .Lsw_do_sp_clr

.Lsw_do_sp_clr:
        .word   0, 0, .Lsw_save_sp11
.Lsw_sp_clr_a2 = .Lsw_do_sp_clr + 0
.Lsw_sp_clr_b2 = .Lsw_do_sp_clr + 4

.Lsw_save_sp11:
        /* Now store SP to that location */
        .word   INT_ZZ, INT_ZZ, .Lsw_save_sp12
.Lsw_save_sp12:
        .word   REG_SP, INT_ZZ, .Lsw_save_sp13  /* INT_ZZ = -SP */
.Lsw_save_sp13:
        /* Patch store B field */
        .word   .Lsw_sp_store_b2, .Lsw_sp_store_b2, .Lsw_save_sp14
.Lsw_save_sp14:
        .word   .Lsw_addr_scratch, INT_ZZ, .Lsw_save_sp15
.Lsw_save_sp15:
        .word   INT_ZZ, INT_ZZ, .Lsw_save_sp16
.Lsw_save_sp16:
        .word   REG_SP, INT_ZZ, .Lsw_save_sp17  /* INT_ZZ = -SP again */
.Lsw_save_sp17:
        .word   INT_ZZ, .Lsw_sp_store_b2, .Lsw_do_sp_store

.Lsw_do_sp_store:
        .word   INT_ZZ, 0, .Lsw_update_current
.Lsw_sp_store_b2 = .Lsw_do_sp_store + 4

        /*
         * Step 3: Update subleq_current_task = next
         */
.Lsw_update_current:
        .word   INT_ZZ, INT_ZZ, .Lsw_update1
.Lsw_update1:
        .word   REG_R22, INT_ZZ, .Lsw_update2  /* INT_ZZ = -next */
.Lsw_update2:
        .word   subleq_current_task, subleq_current_task, .Lsw_update3
.Lsw_update3:
        .word   INT_ZZ, subleq_current_task, .Lsw_load_sp  /* current = next */

        /*
         * Step 4: Load SP from next->thread.sp
         */
.Lsw_load_sp:
        /* Calculate next->thread.sp address = R22 + 1180 */
        .word   INT_ZZ, INT_ZZ, .Lsw_load_sp1
.Lsw_load_sp1:
        .word   REG_R22, INT_ZZ, .Lsw_load_sp2
.Lsw_load_sp2:
        .word   .Lsw_addr_scratch, .Lsw_addr_scratch, .Lsw_load_sp3
.Lsw_load_sp3:
        .word   INT_ZZ, .Lsw_addr_scratch, .Lsw_load_sp4  /* addr_scratch = R22 */
.Lsw_load_sp4:
        .word   .Loffset_neg, .Lsw_addr_scratch, .Lsw_load_sp5 /* addr_scratch = R22 + 1180 */

.Lsw_load_sp5:
        /* Load from [addr_scratch] into SP */
        /* Patch a load instruction */
        .word   INT_ZZ, INT_ZZ, .Lsw_load_sp6
.Lsw_load_sp6:
        .word   .Lsw_addr_scratch, INT_ZZ, .Lsw_load_sp7  /* INT_ZZ = -addr */
.Lsw_load_sp7:
        .word   .Lsw_ld_a, .Lsw_ld_a, .Lsw_load_sp8
.Lsw_load_sp8:
        .word   INT_ZZ, .Lsw_ld_a, .Lsw_do_ld

.Lsw_do_ld:
        /* Read [addr_scratch] into INT_ZZ */
        .word   INT_ZZ, INT_ZZ, .Lsw_do_ld1
.Lsw_do_ld1:
        .word   0, INT_ZZ, .Lsw_load_sp9  /* INT_ZZ = -[addr] */
.Lsw_ld_a = .Lsw_do_ld1 + 0

.Lsw_load_sp9:
        /* SP = -INT_ZZ */
        .word   REG_SP, REG_SP, .Lsw_load_sp10
.Lsw_load_sp10:
        .word   INT_ZZ, REG_SP, .Lsw_set_retval  /* SP = new SP */

        /*
         * Step 5: Set return value R20 = prev (R21)
         */
.Lsw_set_retval:
        .word   INT_ZZ, INT_ZZ, .Lsw_set_retval1
.Lsw_set_retval1:
        .word   REG_R21, INT_ZZ, .Lsw_set_retval2  /* INT_ZZ = -prev */
.Lsw_set_retval2:
        .word   REG_R20, REG_R20, .Lsw_set_retval3
.Lsw_set_retval3:
        .word   INT_ZZ, REG_R20, .Lsw_pop_ra  /* R20 = prev */

        /*
         * Step 6: Pop return address and return
         */
.Lsw_pop_ra:
        /* Load RA from [SP] */
        .word   INT_ZZ, INT_ZZ, .Lsw_pop_ra1
.Lsw_pop_ra1:
        .word   REG_SP, INT_ZZ, .Lsw_pop_ra2  /* INT_ZZ = -SP */
.Lsw_pop_ra2:
        .word   .Lsw_pop_a, .Lsw_pop_a, .Lsw_pop_ra3
.Lsw_pop_ra3:
        .word   INT_ZZ, .Lsw_pop_a, .Lsw_do_pop

.Lsw_do_pop:
        .word   INT_ZZ, INT_ZZ, .Lsw_do_pop1
.Lsw_do_pop1:
        .word   0, INT_ZZ, .Lsw_pop_ra4  /* INT_ZZ = -[SP] = -RA */
.Lsw_pop_a = .Lsw_do_pop1 + 0

.Lsw_pop_ra4:
        /* RA = -INT_ZZ */
        .word   REG_RA, REG_RA, .Lsw_pop_ra5
.Lsw_pop_ra5:
        .word   INT_ZZ, REG_RA, .Lsw_pop_ra6  /* RA = return address */

.Lsw_pop_ra6:
        /* SP += 4 */
        .word   .Lconst_neg4, REG_SP, .Lsw_return

        /*
         * Step 7: Return via RA
         */
.Lsw_return:
        /* Debug: print 'T' for "switched To" */
        .word   -4, .Lchar_T, .Lsw_do_ret

.Lsw_do_ret:
        /* Jump to RA using patching */
        .word   INT_ZZ, INT_ZZ, .Lsw_do_ret1
.Lsw_do_ret1:
        .word   REG_RA, INT_ZZ, .Lsw_do_ret2
.Lsw_do_ret2:
        .word   .Lsw_ret_target, .Lsw_ret_target, .Lsw_do_ret3
.Lsw_do_ret3:
        .word   INT_ZZ, .Lsw_ret_target, .Lsw_do_ret4
.Lsw_do_ret4:
        .word   INT_ZZ, INT_ZZ, 0
.Lsw_ret_target = .Lsw_do_ret4 + 8

/* Data for __switch_to */
.Lsw_addr_scratch:
        .word   0
.Loffset_neg:
        .word   -1180           /* Negative of TASK_THREAD_SP offset */
.Lconst_neg4:
        .word   -4
.Lchar_S:
        .word   83              /* 'S' */
.Lchar_T:
        .word   84              /* 'T' */

.size __switch_to, .-__switch_to

/*
 * ret_from_fork - Entry point for new kernel threads
 *
 * When a new thread is scheduled for the first time, __switch_to returns
 * here. The thread's pt_regs are on the stack:
 *   - pc = thread function
 *   - r21 = argument
 *
 * We call the thread function with its argument.
 */
.globl ret_from_fork
.type ret_from_fork, @function
ret_from_fork:
        /* Debug: print 'N' for New thread */
        .word   -4, .Lchar_N, .Lrff_start

.Lrff_start:
        /*
         * For kernel threads, the pt_regs were set up by copy_thread:
         *   - childregs->pc = thread function
         *   - childregs->r21 = argument
         *
         * But actually, the simpler approach: copy_thread should set up
         * the stack so that:
         *   - SP points to childregs
         *   - The "return address" we popped was ret_from_fork
         *
         * Now we need to call the thread function.
         * The function pointer should be in a known location.
         * Let's use the approach where copy_thread stores:
         *   - thread function in R3 (as saved value)
         *   - argument in R21
         */
        
        /* For now, call kernel_thread_helper which is a C function */
        /* that reads the pt_regs and calls the actual function */
        
        /* Simple approach: just call a C helper */
        .word   .Lconst_4, REG_SP, .Lrff_call  /* SP -= 4 */

.Lrff_call:
        /* Push return address (infinite loop) onto stack */
        .word   INT_ZZ, INT_ZZ, .Lrff_call1
.Lrff_call1:
        .word   REG_SP, INT_ZZ, .Lrff_call2
.Lrff_call2:
        /* Clear [SP] */
        .word   .Lrff_clr_a, .Lrff_clr_a, .Lrff_call3
.Lrff_call3:
        .word   INT_ZZ, .Lrff_clr_a, .Lrff_call4
.Lrff_call4:
        .word   .Lrff_clr_b, .Lrff_clr_b, .Lrff_call5
.Lrff_call5:
        .word   INT_ZZ, .Lrff_clr_b, .Lrff_do_clr

.Lrff_do_clr:
        .word   0, 0, .Lrff_call6
.Lrff_clr_a = .Lrff_do_clr + 0
.Lrff_clr_b = .Lrff_do_clr + 4

.Lrff_call6:
        /* Store loop address to [SP] */
        .word   INT_ZZ, INT_ZZ, .Lrff_call7
.Lrff_call7:
        .word   .Lrff_loop_addr, INT_ZZ, .Lrff_call8
.Lrff_call8:
        .word   .Lrff_store_b, .Lrff_store_b, .Lrff_call9
.Lrff_call9:
        .word   REG_Z, REG_Z, .Lrff_call10
.Lrff_call10:
        .word   REG_SP, REG_Z, .Lrff_call11
.Lrff_call11:
        .word   REG_Z, .Lrff_store_b, .Lrff_do_store2

.Lrff_do_store2:
        .word   INT_ZZ, 0, .Lrff_jump
.Lrff_store_b = .Lrff_do_store2 + 4

.Lrff_jump:
        /* Jump to kernel_thread_helper */
        .word   INT_ZZ, INT_ZZ, kernel_thread_helper

.Lrff_loop:
        /* Infinite loop - should never reach here */
        .word   -4, .Lchar_exclaim, .Lrff_loop2
.Lrff_loop2:
        .word   INT_ZZ, INT_ZZ, .Lrff_loop

.Lrff_loop_addr:
        .word   .Lrff_loop

.Lchar_N:
        .word   78              /* 'N' */
.Lchar_exclaim:
        .word   33              /* '!' */

.size ret_from_fork, .-ret_from_fork
