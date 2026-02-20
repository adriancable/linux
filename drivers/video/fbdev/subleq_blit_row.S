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
.set REG_R21, 100       /* dst pointer (modified in place) */
.set REG_R22, 104       /* byte (biased in place) */
.set REG_R23, 108       /* fg (use directly) */
.set REG_R24, 112       /* bg (use directly) */
.set REG_T4, 176        /* scratch for fg */
.set REG_T5, 180        /* scratch for bg */
.set INDIRECT, 2

subleq_blit_row8:
        /*
         * OPTIMIZED: Use R21 directly as dst pointer, bias R22 in place.
         * Saves 8 instructions vs copying to T0/T1.
         *
         * R21 = dst (use directly, caller-saved so we can modify)
         * R22 = byte + 1 (biased in place)
         */
        .word   .Lconst_n1, REG_R22, .+4      /* R22 += 1 (bias) */

/*
 * OPTIMIZATION: pre-negate fg/bg into T4/T5.
 */
        .word   REG_T4, REG_T4, .+4
        .word   REG_R23, REG_T4, .+4          /* T4 = -fg */
        .word   REG_T5, REG_T5, .+4
        .word   REG_R24, REG_T5, .+4          /* T5 = -bg */

/*
 * PIXEL MACRO (optimized):
 * Foreground path is completely straight-line. Background falls to out-of-line trampolines.
 */

/*=== PIXEL 0 (bit 7) ===*/
.Lpix0: .word   .Lconst_0x80, REG_R22, .Lpix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T4, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4

/*=== PIXEL 1 (bit 6) ===*/
.Lpix1: .word   .Lconst_0x40, REG_R22, .Lpix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T4, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4

/*=== PIXEL 2 (bit 5) ===*/
.Lpix2: .word   .Lconst_0x20, REG_R22, .Lpix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T4, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4

/*=== PIXEL 3 (bit 4) ===*/
.Lpix3: .word   .Lconst_0x10, REG_R22, .Lpix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T4, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4

/*=== PIXEL 4 (bit 3) ===*/
.Lpix4: .word   .Lconst_0x08, REG_R22, .Lpix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T4, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4

/*=== PIXEL 5 (bit 2) ===*/
.Lpix5: .word   .Lconst_0x04, REG_R22, .Lpix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T4, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4

/*=== PIXEL 6 (bit 1) ===*/
.Lpix6: .word   .Lconst_0x02, REG_R22, .Lpix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T4, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4

/*=== PIXEL 7 (bit 0) ===*/
.Lpix7: .word   .Lconst_0x01, REG_R22, .Lpix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T4, REG_R21 | INDIRECT, .+4

.Lpix_all_done:
        .word   REG_T4, REG_T4, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_SP | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_T4, .+4
        .word   .Lconst_n4, REG_SP, .+4
        .word   REG_Z, REG_Z, REG_T4 | INDIRECT

/*===========================================================================
 * BG COLD TRAMPOLINES
 *===========================================================================*/
.Lpix0_bg:
        .word   .Lconst_n0x80, REG_R22, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T5, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lpix1

.Lpix1_bg:
        .word   .Lconst_n0x40, REG_R22, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T5, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lpix2

.Lpix2_bg:
        .word   .Lconst_n0x20, REG_R22, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T5, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lpix3

.Lpix3_bg:
        .word   .Lconst_n0x10, REG_R22, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T5, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lpix4

.Lpix4_bg:
        .word   .Lconst_n0x08, REG_R22, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T5, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lpix5

.Lpix5_bg:
        .word   .Lconst_n0x04, REG_R22, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T5, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lpix6

.Lpix6_bg:
        .word   .Lconst_n0x02, REG_R22, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T5, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lpix7

.Lpix7_bg:
        /* No restore needed for last pixel */
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T5, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpix_all_done

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
