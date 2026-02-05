/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Subleq optimized 1bpp to 32bpp row blitter
 *
 * Expands one row of 8 1bpp font pixels to 8 32bpp framebuffer pixels.
 * Hand-optimized for Subleq OISC using subtraction-based bit testing.
 *
 * void subleq_blit_row8(u32 *dst, u8 byte, u32 fg, u32 bg)
 *
 * Arguments (Subleq calling convention):
 *   R21 = dst    - pointer to framebuffer destination (8 pixels)
 *   R22 = byte   - 8-bit font data (bits 7-0 = pixels left-to-right)
 *   R23 = fg     - foreground color (32-bit XRGB8888)
 *   R24 = bg     - background color (32-bit XRGB8888)
 *
 * Bit testing logic:
 *   subleq branches on (result <= 0)
 *   T1 -= 0x80: if T1 was >= 0x80, result >= 0
 *     - result > 0: NO branch, bit WAS set (more bits left)
 *     - result == 0: branch, bit WAS set (exactly that value)
 *     - result < 0: branch, bit was NOT set
 *   
 *   So: branch target = bg (bit probably not set OR exactly equal)
 *       fall through = fg when result > 0, need second check
 *
 *   SIMPLIFIED: Since byte is 0-255, we check T1 >= power:
 *     After T1 -= power:
 *       If original T1 >= power: T1 now >= 0 (bit was set)
 *       If original T1 < power: T1 now < 0 (bit was clear)
 *     Branch on <= 0 catches both (T1 == 0) and (T1 < 0)
 *     So branch = bg, fall through = fg ONLY works if we don't restore
 *     
 *   ACTUAL FIX: Don't branch on first test, check sign after
 */

.text
.globl subleq_blit_row8
.type subleq_blit_row8, @function

/* Register definitions */
.set REG_Z, 12
.set REG_SP, 16
.set ZERO, 144
.set REG_R20, 96        /* return value */
.set REG_R21, 100       /* dst */
.set REG_R22, 104       /* byte */
.set REG_R23, 108       /* fg */
.set REG_R24, 112       /* bg */
.set REG_T0, 160        /* working dst pointer */
.set REG_T1, 164        /* working byte value */
.set REG_T2, 168        /* fg color (cached) */
.set REG_T3, 172        /* bg color (cached) */
.set REG_T4, 176        /* scratch */
.set INDIRECT, 2

subleq_blit_row8:
        /* Copy args to temp registers */
        /* T0 = dst */
        .word   REG_T0, REG_T0, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R21, REG_Z, .+4
        .word   REG_Z, REG_T0, .+4

        /* T1 = byte */
        .word   REG_T1, REG_T1, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R22, REG_Z, .+4
        .word   REG_Z, REG_T1, .+4

        /* T2 = fg */
        .word   REG_T2, REG_T2, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R23, REG_Z, .+4
        .word   REG_Z, REG_T2, .+4

        /* T3 = bg */
        .word   REG_T3, REG_T3, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R24, REG_Z, .+4
        .word   REG_Z, REG_T3, .+4

/*
 * BIT TEST LOGIC (CORRECTED):
 *   T1 -= power; branch if <= 0
 *   
 *   If byte >= power: after subtract, T1 >= 0
 *     - T1 > 0: no branch (fall through) -> bit set, keep subtracting
 *     - T1 == 0: branch taken -> bit set (exactly equal)
 *   If byte < power: after subtract, T1 < 0 -> branch taken -> bit clear
 *   
 *   So: branch target handles BOTH (bit clear) AND (bit set, exactly equal)
 *   Fall-through: bit set with remainder
 *   
 *   For bit 7: if T1 >= 128, it must be 128-255
 *     T1 - 128 gives 0-127, will be >= 0
 *     If T1 >= 128: result >= 0 (could be 0, could be positive)
 *     Branch on <= 0: catches T1 == 128 (result = 0)
 *     No branch: T1 was 129-255 (result = 1-127 > 0) -> BIT SET
 *   
 *   CONCLUSION: 
 *     No branch (result > 0) = bit definitely set, keep T1 reduced
 *     Branch (result <= 0) = bit might be set (if result==0) or clear (if result<0)
 *       Need to check: if result == 0, bit was set; if result < 0, bit was clear
 *
 *   SIMPLER APPROACH: Just use sign test after subtract
 *     T1 -= power (always)
 *     if T1 < 0: bg (and restore T1)
 *     else: fg (keep T1 reduced)
 */

/*=== PIXEL 0 (bit 7): T1 -= 0x80, check if T1 < 0 ===*/
.Lpixel0:
        .word   .Lconst_0x80, REG_T1, .+4      /* T1 -= 0x80, always continue */
        /* Now check if T1 < 0 (bit was clear) */
        .word   ZERO, REG_T1, .Lpixel0_bg      /* if T1 <= 0, might be bg */
        /* T1 > 0: bit was definitely set, write fg */
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel0_next
.Lpixel0_bg:
        /* T1 <= 0: check if exactly 0 (bit set) or < 0 (bit clear) */
        /* If T1 == 0: fg. If T1 < 0: bg and restore */
        /* Test: T1 + 1 <= 0 means T1 < 0 (was truly negative) */
        .word   .Lconst_neg1, REG_T1, .Lpixel0_bg_write  /* T1 += 1, if <= 0, T1 was < 0 */
        /* T1 was exactly 0 before +1, now T1 = 1, bit was set, write fg */
        .word   .Lconst_1, REG_T1, .+4         /* restore T1 to 0 */
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel0_next
.Lpixel0_bg_write:
        /* T1 was < 0 (bit clear), restore and write bg */
        .word   .Lconst_n0x80_minus1, REG_T1, .+4   /* T1 += 0x81 (restore from T1-0x80+1) */
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T3, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
.Lpixel0_next:
        .word   .Lconst_neg4, REG_T0, .+4

/*=== PIXEL 1 (bit 6) ===*/
.Lpixel1:
        .word   .Lconst_0x40, REG_T1, .+4
        .word   ZERO, REG_T1, .Lpixel1_bg
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel1_next
.Lpixel1_bg:
        .word   .Lconst_neg1, REG_T1, .Lpixel1_bg_write
        .word   .Lconst_1, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel1_next
.Lpixel1_bg_write:
        .word   .Lconst_n0x40_minus1, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T3, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
.Lpixel1_next:
        .word   .Lconst_neg4, REG_T0, .+4

/*=== PIXEL 2 (bit 5) ===*/
.Lpixel2:
        .word   .Lconst_0x20, REG_T1, .+4
        .word   ZERO, REG_T1, .Lpixel2_bg
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel2_next
.Lpixel2_bg:
        .word   .Lconst_neg1, REG_T1, .Lpixel2_bg_write
        .word   .Lconst_1, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel2_next
.Lpixel2_bg_write:
        .word   .Lconst_n0x20_minus1, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T3, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
.Lpixel2_next:
        .word   .Lconst_neg4, REG_T0, .+4

/*=== PIXEL 3 (bit 4) ===*/
.Lpixel3:
        .word   .Lconst_0x10, REG_T1, .+4
        .word   ZERO, REG_T1, .Lpixel3_bg
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel3_next
.Lpixel3_bg:
        .word   .Lconst_neg1, REG_T1, .Lpixel3_bg_write
        .word   .Lconst_1, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel3_next
.Lpixel3_bg_write:
        .word   .Lconst_n0x10_minus1, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T3, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
.Lpixel3_next:
        .word   .Lconst_neg4, REG_T0, .+4

/*=== PIXEL 4 (bit 3) ===*/
.Lpixel4:
        .word   .Lconst_0x08, REG_T1, .+4
        .word   ZERO, REG_T1, .Lpixel4_bg
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel4_next
.Lpixel4_bg:
        .word   .Lconst_neg1, REG_T1, .Lpixel4_bg_write
        .word   .Lconst_1, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel4_next
.Lpixel4_bg_write:
        .word   .Lconst_n0x08_minus1, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T3, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
.Lpixel4_next:
        .word   .Lconst_neg4, REG_T0, .+4

/*=== PIXEL 5 (bit 2) ===*/
.Lpixel5:
        .word   .Lconst_0x04, REG_T1, .+4
        .word   ZERO, REG_T1, .Lpixel5_bg
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel5_next
.Lpixel5_bg:
        .word   .Lconst_neg1, REG_T1, .Lpixel5_bg_write
        .word   .Lconst_1, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel5_next
.Lpixel5_bg_write:
        .word   .Lconst_n0x04_minus1, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T3, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
.Lpixel5_next:
        .word   .Lconst_neg4, REG_T0, .+4

/*=== PIXEL 6 (bit 1) ===*/
.Lpixel6:
        .word   .Lconst_0x02, REG_T1, .+4
        .word   ZERO, REG_T1, .Lpixel6_bg
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel6_next
.Lpixel6_bg:
        .word   .Lconst_neg1, REG_T1, .Lpixel6_bg_write
        .word   .Lconst_1, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel6_next
.Lpixel6_bg_write:
        .word   .Lconst_n0x02_minus1, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T3, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
.Lpixel6_next:
        .word   .Lconst_neg4, REG_T0, .+4

/*=== PIXEL 7 (bit 0) ===*/
.Lpixel7:
        .word   .Lconst_0x01, REG_T1, .+4
        .word   ZERO, REG_T1, .Lpixel7_bg
        /* T1 > 0: impossible for bit 0 since remainder would be 0 */
        /* But handle anyway: write fg */
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Ldone
.Lpixel7_bg:
        /* T1 <= 0: if T1 == 0, fg; if T1 < 0, bg */
        .word   .Lconst_neg1, REG_T1, .Lpixel7_bg_write
        /* T1 was 0, write fg */
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T2, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Ldone
.Lpixel7_bg_write:
        /* T1 < 0, write bg */
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T3, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4

/*=== RETURN ===*/
.Ldone:
        /* Pop return address and jump */
        .word   REG_T4, REG_T4, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_SP | INDIRECT, REG_Z, .+4     /* Z = -[SP] */
        .word   REG_Z, REG_T4, .+4                /* T4 = return_addr */
        .word   .Lconst_neg4, REG_SP, .+4         /* SP += 4 (pop) */
        .word   REG_Z, REG_Z, REG_T4 | INDIRECT   /* jump to return_addr */

.size subleq_blit_row8, .-subleq_blit_row8

/*===========================================================================
 * CONSTANTS
 *===========================================================================*/

.Lconst_neg4:
        .word   -4
.Lconst_neg1:
        .word   -1
.Lconst_1:
        .word   1

/* Power-of-2 constants for bit testing */
.Lconst_0x80:
        .word   0x80
.Lconst_0x40:
        .word   0x40
.Lconst_0x20:
        .word   0x20
.Lconst_0x10:
        .word   0x10
.Lconst_0x08:
        .word   0x08
.Lconst_0x04:
        .word   0x04
.Lconst_0x02:
        .word   0x02
.Lconst_0x01:
        .word   0x01

/* Restore constants: -(power - 1) to undo (subtract power, add 1) */
.Lconst_n0x80_minus1:
        .word   -(0x80 - 1)     /* -127 = 0x81 */
.Lconst_n0x40_minus1:
        .word   -(0x40 - 1)     /* -63 */
.Lconst_n0x20_minus1:
        .word   -(0x20 - 1)     /* -31 */
.Lconst_n0x10_minus1:
        .word   -(0x10 - 1)     /* -15 */
.Lconst_n0x08_minus1:
        .word   -(0x08 - 1)     /* -7 */
.Lconst_n0x04_minus1:
        .word   -(0x04 - 1)     /* -3 */
.Lconst_n0x02_minus1:
        .word   -(0x02 - 1)     /* -1 */
