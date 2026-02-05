/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Subleq optimized 1bpp to 32bpp row blitter - OPTIMIZED VERSION
 *
 * void subleq_blit_row8(u32 *dst, u8 byte, u32 fg, u32 bg)
 *
 * OPTIMIZATION STRATEGY:
 * 1. Bias byte by +1: byte becomes 1-256 (never 0)
 * 2. Test T1 - power:
 *    - If result <= 0: bit was CLEAR (bg) - BRANCH TAKEN
 *    - If result > 0: bit was SET (fg) - FALL THROUGH
 * 3. Use args directly (no temp copy for fg/bg) - saves 8 instructions
 * 4. Pre-subtract dst ptr increment from constants - amortize cost
 * 5. Share common write code where possible
 *
 * With biasing:
 *   byte=0x00 -> biased=1 -> 1-128=-127 <= 0 (bit 7 clear, correct)
 *   byte=0x80 -> biased=129 -> 129-128=1 > 0 (bit 7 set, correct)
 *   byte=0xFF -> biased=256 -> 256-128=128 > 0 (bit 7 set, correct)
 */

.text
.globl subleq_blit_row8
.type subleq_blit_row8, @function

/* Register definitions */
.set REG_Z, 12
.set REG_SP, 16
.set REG_R21, 100       /* dst (use directly) */
.set REG_R22, 104       /* byte */
.set REG_R23, 108       /* fg (use directly) */
.set REG_R24, 112       /* bg (use directly) */
.set REG_T0, 160        /* working dst pointer */
.set REG_T1, 164        /* biased byte value */
.set REG_T4, 176        /* scratch for return */
.set INDIRECT, 2

subleq_blit_row8:
        /* Setup: T0 = dst, T1 = byte + 1 (biased) */
        /* T0 = R21 (dst pointer) */
        .word   REG_T0, REG_T0, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R21, REG_Z, .+4
        .word   REG_Z, REG_T0, .+4

        /* T1 = R22 + 1 (biased byte) */
        .word   REG_T1, REG_T1, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R22, REG_Z, .+4
        .word   REG_Z, REG_T1, .+4
        .word   .Lconst_n1, REG_T1, .+4      /* T1 -= -1, i.e. T1 += 1 */

/*
 * PIXEL MACRO (optimized):
 *   .word   [power], REG_T1, bg_label    // T1 -= power; if <= 0, bit clear
 *   // Fall through: bit set, write fg
 *   [write fg]
 *   .word   Z, Z, next_pixel
 * bg_label:
 *   [write bg]
 * next_pixel:
 *   .word   [neg4], REG_T0, .+4          // dst += 4
 *
 * Each write is 4 instructions:
 *   .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4   // [dst] = 0
 *   .word   REG_Z, REG_Z, .+4                            // Z = 0
 *   .word   REG_R23, REG_Z, .+4                          // Z = -fg
 *   .word   REG_Z, REG_T0 | INDIRECT, .+4                // [dst] = fg
 */

/*=== PIXEL 0 (bit 7) ===*/
        .word   .Lconst_0x80, REG_T1, .Lpixel0_bg
        /* fg path (4 instructions) */
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R23, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel0_done
.Lpixel0_bg:
        /* bg path - restore T1 first */
        .word   .Lconst_n0x80, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R24, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
.Lpixel0_done:
        .word   .Lconst_n4, REG_T0, .+4

/*=== PIXEL 1 (bit 6) ===*/
        .word   .Lconst_0x40, REG_T1, .Lpixel1_bg
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R23, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel1_done
.Lpixel1_bg:
        .word   .Lconst_n0x40, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R24, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
.Lpixel1_done:
        .word   .Lconst_n4, REG_T0, .+4

/*=== PIXEL 2 (bit 5) ===*/
        .word   .Lconst_0x20, REG_T1, .Lpixel2_bg
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R23, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel2_done
.Lpixel2_bg:
        .word   .Lconst_n0x20, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R24, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
.Lpixel2_done:
        .word   .Lconst_n4, REG_T0, .+4

/*=== PIXEL 3 (bit 4) ===*/
        .word   .Lconst_0x10, REG_T1, .Lpixel3_bg
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R23, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel3_done
.Lpixel3_bg:
        .word   .Lconst_n0x10, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R24, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
.Lpixel3_done:
        .word   .Lconst_n4, REG_T0, .+4

/*=== PIXEL 4 (bit 3) ===*/
        .word   .Lconst_0x08, REG_T1, .Lpixel4_bg
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R23, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel4_done
.Lpixel4_bg:
        .word   .Lconst_n0x08, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R24, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
.Lpixel4_done:
        .word   .Lconst_n4, REG_T0, .+4

/*=== PIXEL 5 (bit 2) ===*/
        .word   .Lconst_0x04, REG_T1, .Lpixel5_bg
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R23, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel5_done
.Lpixel5_bg:
        .word   .Lconst_n0x04, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R24, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
.Lpixel5_done:
        .word   .Lconst_n4, REG_T0, .+4

/*=== PIXEL 6 (bit 1) ===*/
        .word   .Lconst_0x02, REG_T1, .Lpixel6_bg
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R23, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpixel6_done
.Lpixel6_bg:
        .word   .Lconst_n0x02, REG_T1, .+4
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R24, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
.Lpixel6_done:
        .word   .Lconst_n4, REG_T0, .+4

/*=== PIXEL 7 (bit 0) ===*/
        .word   .Lconst_0x01, REG_T1, .Lpixel7_bg
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R23, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Ldone
.Lpixel7_bg:
        /* No restore needed for last pixel */
        .word   REG_T0 | INDIRECT, REG_T0 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R24, REG_Z, .+4
        .word   REG_Z, REG_T0 | INDIRECT, .+4

/*=== RETURN ===*/
.Ldone:
        .word   REG_T4, REG_T4, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_SP | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_T4, .+4
        .word   .Lconst_n4, REG_SP, .+4
        .word   REG_Z, REG_Z, REG_T4 | INDIRECT

.size subleq_blit_row8, .-subleq_blit_row8

/*===========================================================================
 * CONSTANTS
 *===========================================================================*/
.Lconst_n4:
        .word   -4
.Lconst_n1:
        .word   -1

/* Power constants (positive for subtract-test) */
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

/* Negative power constants (for restore) */
.Lconst_n0x80:
        .word   -0x80
.Lconst_n0x40:
        .word   -0x40
.Lconst_n0x20:
        .word   -0x20
.Lconst_n0x10:
        .word   -0x10
.Lconst_n0x08:
        .word   -0x08
.Lconst_n0x04:
        .word   -0x04
.Lconst_n0x02:
        .word   -0x02
