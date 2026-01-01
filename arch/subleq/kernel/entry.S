/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Subleq interrupt entry/exit code
 *
 * This is the low-level interrupt handler entry point.
 * It's jumped to directly by the VM when a timer interrupt fires.
 *
 * Memory layout (byte addresses):
 *   0   = INT_HANDLER (handler address, 0 = disabled)
 *   4   = INT_SAVED_PC (PC at interrupt)
 *   8   = INT_SAVED_HANDLER (saved handler when disabled)
 *   12  = Z (scratch zero)
 *   16  = SP (stack pointer)
 *   20  = RA (return address)
 *   24  = ZERO (constant 0)
 *   224 = INT_Z (interrupt scratch for return jump)
 *   228 = INT_T0 (interrupt temporary 0)
 *   232 = INT_T1 (interrupt temporary 1)
 *   ...
 */

.text
.globl subleq_irq_entry
.type subleq_irq_entry, @function

/*
 * Interrupt entry point
 *
 * The VM saved PC to m[1] and jumped here.
 * We need to:
 * 1. Save RA (since we'll make a call)
 * 2. Call subleq_do_IRQ
 * 3. Restore RA
 * 4. Jump to saved PC at m[1]
 *
 * For step 1 & 3, we use INT_T0 (byte 228) to save RA (byte 20)
 * For step 4, we use INT_Z (byte 224) to perform indirect jump
 */
subleq_irq_entry:
        /* Step 1: Save RA to INT_T0 */
        /* INT_T0 = 0 */
        .word   228, 228, .Lirq_save_ra1
.Lirq_save_ra1:
        /* INT_T0 -= RA => INT_T0 = -RA */
        .word   20, 228, .Lirq_call

.Lirq_call:
        /*
         * Step 2: Call subleq_do_IRQ
         * This is tricky - we need to set RA and jump
         * RA = return address (after the jump)
         * Then jump to subleq_do_IRQ
         *
         * Z = 0
         * Z -= address of return point => Z = -return_addr
         * RA = 0
         * RA -= Z => RA = return_addr
         * Jump to subleq_do_IRQ
         */
        /* Z = 0 */
        .word   12, 12, .Lirq_call2
.Lirq_call2:
        /* Z -= .Lirq_returned => Z = -(return addr) */
        .word   .Lirq_return_addr, 12, .Lirq_call3
.Lirq_call3:
        /* RA = 0 */
        .word   20, 20, .Lirq_call4
.Lirq_call4:
        /* RA -= Z => RA = return addr */
        .word   12, 20, .Lirq_do_jump
.Lirq_do_jump:
        /* Jump to subleq_do_IRQ (always taken since 0 <= 0) */
        .word   12, 12, subleq_do_IRQ

.Lirq_returned:
        /* Step 3: Restore RA from INT_T0 */
        /* RA = 0 already or needs to be cleared? */
        .word   20, 20, .Lirq_restore_ra1
.Lirq_restore_ra1:
        /* RA -= INT_T0 => RA = -(-old_RA) = old_RA */
        .word   228, 20, .Lirq_return

.Lirq_return:
        /*
         * Step 4: Return from interrupt - jump to saved PC at m[1]
         *
         * We need to read m[1] (byte addr 4) and jump to it.
         * Using self-modifying code with INT_Z:
         *
         * INT_Z = 0
         * INT_Z -= m[1] => INT_Z = -saved_pc
         * Modify jump target to be saved_pc
         * Jump
         */
        /* INT_Z = 0 */
        .word   224, 224, .Lirq_ret1
.Lirq_ret1:
        /* INT_Z -= m[1] => INT_Z = -saved_pc */
        .word   4, 224, .Lirq_ret2
.Lirq_ret2:
        /* Now we need to jump to saved_pc */
        /* Clear Z first */
        .word   12, 12, .Lirq_ret3
.Lirq_ret3:
        /* Load saved_pc into the jump target using self-modifying code */
        /* Z -= INT_Z => Z = saved_pc */
        .word   224, 12, .Lirq_ret4
.Lirq_ret4:
        /* Patch the jump target: store Z into .Lirq_jmp_target+8 */
        /* First, .Lirq_jmp_patch = 0 */
        .word   .Lirq_jmp_patch, .Lirq_jmp_patch, .Lirq_ret5
.Lirq_ret5:
        /* .Lirq_jmp_patch -= Z => stores -saved_pc */
        .word   12, .Lirq_jmp_patch, .Lirq_ret6
.Lirq_ret6:
        /* Now negate: first clear Z */
        .word   12, 12, .Lirq_ret7
.Lirq_ret7:
        /* Z -= .Lirq_jmp_patch => Z = saved_pc */
        .word   .Lirq_jmp_patch, 12, .Lirq_ret8
.Lirq_ret8:
        /* Clear target location */
        .word   .Lirq_jmp_target, .Lirq_jmp_target, .Lirq_ret9
.Lirq_ret9:
        /* Store: .Lirq_jmp_target -= Z => stores -saved_pc there (we need positive) */
        /* Actually we need to negate Z first */
        /* Let's try a different approach - just negate and use directly */
        .word   12, .Lirq_jmp_target, .Lirq_ret10
.Lirq_ret10:
        /* Negate the target location */
        .word   12, 12, .Lirq_ret11
.Lirq_ret11:
        .word   .Lirq_jmp_target, 12, .Lirq_ret12
.Lirq_ret12:
        .word   .Lirq_jmp_target, .Lirq_jmp_target, .Lirq_ret13
.Lirq_ret13:
        .word   12, .Lirq_jmp_target, .Lirq_do_return

.Lirq_do_return:
        /* Final jump - always taken since Z = Z means result is 0 <= 0 */
        .word   12, 12, 0   /* Jump target patched here */
.Lirq_jmp_target = .Lirq_do_return + 8

        /* Scratch space for address calculation */
.Lirq_jmp_patch:
        .word   0

        /* Constant: address of .Lirq_returned for call setup */
.Lirq_return_addr:
        .word   .Lirq_returned

.size subleq_irq_entry, .-subleq_irq_entry
