/* SPDX-License-Identifier: GPL-2.0 */
/*
 * subleq_direct_putcs - Direct framebuffer text rendering
 *
 * Renders characters directly to 32bpp XRGB8888 framebuffer,
 * bypassing the intermediate 1bpp pixmap buffer.
 *
 * void subleq_direct_putcs(u32 *fb, u32 fb_pitch, u32 x, u32 y,
 *                          const u32 *font, const u16 *s, u32 cnt,
 *                          u32 s_pitch, u32 fg, u32 bg);
 *
 * Arguments (on stack, Subleq variadic convention):
 *   [SP+4]  = fb        - Framebuffer base pointer
 *   [SP+8]  = fb_pitch  - Bytes per framebuffer row (e.g. 3200)
 *   [SP+12] = x         - Starting X pixel coordinate
 *   [SP+16] = y         - Starting Y pixel coordinate
 *   [SP+20] = font      - Expanded font array (word per row)
 *   [SP+24] = s         - Screen buffer (u16 per char)
 *   [SP+28] = cnt       - Number of characters
 *   [SP+32] = s_off    - Byte offset of s within word (0=aligned, 2=misaligned)
 *   [SP+36] = fg        - Foreground color (32-bit XRGB)
 *   [SP+40] = bg        - Background color (32-bit XRGB)
 *
 * Register allocation:
 *   T8  = current pixel pointer (fb + y*pitch + x*4)
 *   T9  = s (screen buffer pointer)
 *   T10 = font base
 *   T11 = remaining character count
 *   T12 = fb_pitch
 *   T13 = fg color
 *   T14 = bg color
 *   T7  = alignment offset (0 or 2), cleared after first iteration
 */

        .text
        .globl  subleq_direct_putcs
        .type   subleq_direct_putcs, @function
        .balign 4
subleq_direct_putcs:

#include <asm/subleq-regs.h>

/*===========================================================================
 * PROLOGUE: Load arguments
 * Calling convention: args 1-4 in R21-R24, args 5+ on stack (right-to-left)
 * At entry:
 *   R21 = fb, R22 = fb_pitch, R23 = x, R24 = y
 *   [SP+0] = RA
 *   [SP+4] = bg (arg 10, pushed first)
 *   [SP+8] = fg (arg 9)
 *   [SP+12] = s_pitch (arg 8)
 *   [SP+16] = cnt (arg 7)
 *   [SP+20] = s (arg 6)
 *   [SP+24] = font (arg 5)
 *===========================================================================*/

        /* T8 = fb = R21 (Z-scratch: Z is clean at entry) */
        .word   REG_R21, REG_Z, .+4
        .word   REG_T8, REG_T8, .+4
        .word   REG_Z, REG_T8, .+4

        /* T12 = fb_pitch = R22 */
        .word   REG_T12, REG_T12, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R22, REG_Z, .+4
        .word   REG_Z, REG_T12, .+4

        /* Save x (R23) and y (R24) for later - use R20, R21 as scratch */
        /* R20 = x = R23 */
        .word   REG_R20, REG_R20, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R23, REG_Z, .+4
        .word   REG_Z, REG_R20, .+4

        /* R21 = y = R24 (clobbers R21, but we saved fb to T8) */
        .word   REG_R21, REG_R21, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R24, REG_Z, .+4

        .word   REG_Z, REG_R21, .+4
        .word   REG_Z, REG_Z, .+4

        /* Stack layout at entry (RA pushed by caller):
         * [SP+0]  = RA
         * [SP+4]  = font (arg 5, pushed last)
         * [SP+8]  = s (arg 6)
         * [SP+12] = cnt (arg 7)
         * [SP+16] = s_off (arg 8, 0=aligned, 2=misaligned)
         * [SP+20] = fg (arg 9)
         * [SP+24] = bg (arg 10, pushed first)
         */

        /* T15 = SP + 4 (pointer to font arg) */
        .word   REG_T15, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_SP, REG_Z, .+4        /* Z = -SP */
        .word   .Lconst_4, REG_Z, .+4     /* Z = -SP - 4 */
        .word   REG_Z, REG_T15, .+4       /* T15 = SP + 4 */
        .word   REG_Z, REG_Z, .+4

        /* T10 = font = [SP+4] */
        .word   REG_T10, REG_T10, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T15 | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_T10, .+4
        .word   REG_Z, REG_Z, .+4

        /* T9 = s = [SP+8] */
        .word   .Lconst_n4, REG_T15, .+4  /* T15 = SP + 8 */
        .word   REG_T9, REG_T9, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T15 | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_T9, .+4
        .word   REG_Z, REG_Z, .+4

        /* T11 = cnt = [SP+12] */
        .word   .Lconst_n4, REG_T15, .+4  /* T15 = SP + 12 */
        .word   REG_T11, REG_T11, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T15 | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_T11, .+4
        .word   REG_Z, REG_Z, .+4

        /* T7 = s_pitch/alignment offset = [SP+16] (0=aligned, 2=misaligned) */
        .word   .Lconst_n4, REG_T15, .+4  /* T15 = SP + 16 */
        .word   REG_T7, REG_T7, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T15 | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_T7, .+4
        .word   REG_Z, REG_Z, .+4

        /* T13 = -fg (negated for 2-op pixel writes) */
        .word   .Lconst_n4, REG_T15, .+4  /* T15 = SP + 20 */
        .word   REG_T13, REG_T13, .+4
        .word   REG_T15 | INDIRECT, REG_T13, .+4  /* T13 = 0 - fg = -fg */

        /* T14 = -bg (negated for 2-op pixel writes) */
        .word   .Lconst_n4, REG_T15, .+4  /* T15 = SP + 24 */
        .word   REG_T14, REG_T14, .+4
        .word   REG_T15 | INDIRECT, REG_T14, .+4  /* T14 = 0 - bg = -bg */

/*===========================================================================
 * COMPUTE INITIAL PIXEL POINTER: T8 = fb + y*fb_pitch + x*4
 * At this point: R20 = x, R21 = y, T8 = fb, T12 = fb_pitch
 *===========================================================================*/

        /* Save x to T15 before mul clobbers R20 */
        .word   REG_T15, REG_T15, .+4
        .word   REG_R20, REG_Z, .+4
        .word   REG_Z, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4

        /* Call __subleq_mul: R21 = y, R22 = fb_pitch, result in R20 */
        .word   REG_R22, REG_R22, .+4
        .word   REG_T12, REG_Z, .+4
        .word   REG_Z, REG_R22, .+4
        .word   REG_Z, REG_Z, .+4

        /* Push return address and call mul */
        .word   .Lconst_4, REG_SP, .+4
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4
        .word   .Lmul_ret_neg, REG_SP | INDIRECT, .+4
        .word   REG_Z, REG_Z, __subleq_mul

.Lmul_ret:
        /* __subleq_mul already popped return address, no extra pop needed */

        /* R20 now = y * fb_pitch. Add to T8 (fb base) */
        .word   REG_R20, REG_Z, .+4
        .word   REG_Z, REG_T8, .+4
        .word   REG_Z, REG_Z, .+4

        /* Restore x from T15, then compute x * 4 */
        .word   REG_R20, REG_R20, .+4
        .word   REG_T15, REG_Z, .+4
        .word   REG_Z, REG_R20, .+4
        .word   REG_Z, REG_Z, .+4

        /* R20 = x * 4 via 2 doublings */
        .word   REG_R20, REG_Z, .+4
        .word   REG_Z, REG_R20, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R20, REG_Z, .+4
        .word   REG_Z, REG_R20, .+4
        .word   REG_Z, REG_Z, .+4

        /* T8 += R20 (x*4) => T8 = fb + y*pitch + x*4 */
        .word   REG_R20, REG_Z, .+4
        .word   REG_Z, REG_T8, .+4
        .word   REG_Z, REG_Z, .+4

        /* R22 = -(pitch - 28): row-advance constant for render_char.
         * Computed once; R22 is free after prologue and not touched by lattice.
         * After 8 pixels, R21 advances by 28 bytes (7 x 4), so the
         * row stride correction is pitch - 28. */
        .word   REG_R22, REG_R22, .+4          /* R22 = 0 */
        .word   REG_T12, REG_R22, .+4          /* R22 = -pitch */
        .word   .Lconst_n28, REG_R22, .+4      /* R22 = -(pitch-28) */

        /* R23 = -T10 (pre-negated font base for faster font ptr setup).
         * Allows computing T15 = charN*64 + T10 in 4 insn instead of 6.
         * R23 is free after prologue and not touched by lattice. */
        .word   REG_R23, REG_R23, .+4          /* R23 = 0 */
        .word   REG_T10, REG_R23, .+4          /* R23 = -T10 */
        .word   REG_Z, REG_Z, .+4              /* Z = 0 */

.Lpair_loop:
        /* if T11 (cnt) <= 0, done */
        .word   REG_Z, REG_T11, .Ldone

        /* === Read u32 word from screen buffer [T9] === */
        /* Z is clean here: prologue ends with Z,Z or loop-back is Z,Z,.Lpair_loop */
        .word   REG_T3, REG_T3, .+4
        .word   REG_T9 | INDIRECT, REG_Z, .+4       /* Z = -[T9] */
        .word   REG_Z, REG_T3, .+4                  /* T3 = [T9] */

        /* === Clear char accumulators === */
        .word   REG_T0, REG_T0, .+4      /* T0 = 0 */
        .word   REG_T2, REG_T2, .+4      /* T2 = 0 */

        /* === Jump to extraction lattice (Z,Z also clears Z; lattice doesn't need it) === */
        .word   REG_Z, REG_Z, .Lext_sign

        /* === Return from lattice: T0=char0*64, T2=char1*64 === */
.Lext_ret:

        /* Check alignment: T7=0 (aligned) → render char0, T7>0 → skip to char1 */
        .word   .Lconst_0, REG_T7, .Lrender_char0
        /* T7 > 0: misaligned start, skip char0, clear T7 for future iterations */
        .word   REG_T7, REG_T7, .+4
        .word   REG_Z, REG_Z, .Lskip_to_char1

.Lrender_char0:
        /* ===== RENDER CHAR 0 ===== */
        /* T15 = T0 + T10, using R23 = -T10 (pre-negated, 4 insn) */
        .word   REG_T15, REG_T15, .+4          /* T15 = 0 */
        .word   REG_T0, REG_Z, .+4             /* Z = -T0 */
        .word   REG_Z, REG_T15, .+4            /* T15 = T0 */
        .word   REG_R23, REG_T15, .+4          /* T15 -= (-T10) = T0 + T10 */

        /* Set render return to .Lrender0_ret (4 insn using neg constant) */
        .word   REG_T5, REG_T5, .+4            /* T5 = 0 */
        .word   .Lrender0_ret_neg, REG_T5, .+4 /* T5 -= (-ret) = ret_addr */
        .word   REG_Z, REG_Z, .Lrender_char    /* clear Z + jump */

.Lrender0_ret:
        /* Advance T8 by 32 (8 pixels * 4 bytes) for next column */
        .word   .Lconst_n32, REG_T8, .+4

        /* T11 -= 1 (one char rendered) */
        .word   .Lconst_1, REG_T11, .+4

        /* if T11 <= 0, skip char1 (handles odd count) */
        .word   REG_Z, REG_T11, .Lpair_advance

.Lskip_to_char1:
        /* ===== RENDER CHAR 1 ===== */
        /* T15 = T2 + T10, using R23 = -T10 (pre-negated, 4 insn) */
        .word   REG_T15, REG_T15, .+4          /* T15 = 0 */
        .word   REG_T2, REG_Z, .+4             /* Z = -T2 */
        .word   REG_Z, REG_T15, .+4            /* T15 = T2 */
        .word   REG_R23, REG_T15, .+4          /* T15 -= (-T10) = T2 + T10 */

        /* Set render return to .Lrender1_ret (4 insn using neg constant) */
        .word   REG_T5, REG_T5, .+4            /* T5 = 0 */
        .word   .Lrender1_ret_neg, REG_T5, .+4 /* T5 -= (-ret) = ret_addr */
        .word   REG_Z, REG_Z, .Lrender_char    /* clear Z + jump */

.Lrender1_ret:
        /* Advance T8 by 32 for char1's column */
        .word   .Lconst_n32, REG_T8, .+4

        /* T11 -= 1 */
        .word   .Lconst_1, REG_T11, .+4

.Lpair_advance:
        /* Advance T9 by 4 (skip one u32 = two u16 characters) */
        .word   .Lconst_n4, REG_T9, .+4

        .word   REG_Z, REG_Z, .Lpair_loop

/*===========================================================================
 * RENDER CHARACTER SUB-PROCEDURE
 *
 * Renders one 8x16 character glyph to the framebuffer.
 * Expects:  T15 = font_ptr, T8 = column pixel pointer,
 *           T13 = -fg, T14 = -bg, T12 = fb_pitch, Z = 0
 * Returns via: indirect jump through T5
 * Clobbers: R20, R21, R23, T4
 *
 * OPTIMIZATIONS (R1+R2+R3+R4+R6):
 *   R1+R2+R3: Rolling R21 pointer, pitch-32 advance, no Z clear.
 *   R4: Full 16-row unroll — no loop counter, no branch overhead.
 *        Saves 3 insn * 16 rows = 48 insn/char.
 *   R6: T15 and R21 advances are adjacent, improving locality.
 *===========================================================================*/
.Lrender_char:
        /* R21 = T8 (Z-scratch: Z=0 on entry) */
        .word   REG_T8, REG_Z, .+4            /* Z = -T8 */
        .word   REG_R21, REG_R21, .+4          /* R21 = 0 */
        .word   REG_Z, REG_R21, .+4            /* R21 = T8 */

        /* R22 = -(pitch-28) is pre-computed in the prologue */

        /* Z = 0 for first font load */
        .word   REG_Z, REG_Z, .+4

/*=== ROW 0 ===*/
.Lrow_0:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr0_pix7:
        .word   .Lconst_128, REG_R20, .Lr0_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr0_pix6:
        .word   .Lconst_64, REG_R20, .Lr0_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr0_pix5:
        .word   .Lconst_32, REG_R20, .Lr0_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr0_pix4:
        .word   .Lconst_16, REG_R20, .Lr0_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr0_pix3:
        .word   .Lconst_8, REG_R20, .Lr0_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr0_pix2:
        .word   .Lconst_4, REG_R20, .Lr0_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr0_pix1:
        .word   .Lconst_2, REG_R20, .Lr0_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr0_pix0:
        .word   .Lconst_1, REG_R20, .Lr0_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Advance font_ptr and row pointer (R6) */
        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        /* Z = 0 from T4 advance? No: subleq doesn't clear Z. */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */

/*=== ROW 1 ===*/
.Lrow_1:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr1_pix7:
        .word   .Lconst_128, REG_R20, .Lr1_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr1_pix6:
        .word   .Lconst_64, REG_R20, .Lr1_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr1_pix5:
        .word   .Lconst_32, REG_R20, .Lr1_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr1_pix4:
        .word   .Lconst_16, REG_R20, .Lr1_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr1_pix3:
        .word   .Lconst_8, REG_R20, .Lr1_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr1_pix2:
        .word   .Lconst_4, REG_R20, .Lr1_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr1_pix1:
        .word   .Lconst_2, REG_R20, .Lr1_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr1_pix0:
        .word   .Lconst_1, REG_R20, .Lr1_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Advance font_ptr and row pointer (R6) */
        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        /* Z = 0 from T4 advance? No: subleq doesn't clear Z. */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */

/*=== ROW 2 ===*/
.Lrow_2:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr2_pix7:
        .word   .Lconst_128, REG_R20, .Lr2_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr2_pix6:
        .word   .Lconst_64, REG_R20, .Lr2_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr2_pix5:
        .word   .Lconst_32, REG_R20, .Lr2_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr2_pix4:
        .word   .Lconst_16, REG_R20, .Lr2_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr2_pix3:
        .word   .Lconst_8, REG_R20, .Lr2_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr2_pix2:
        .word   .Lconst_4, REG_R20, .Lr2_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr2_pix1:
        .word   .Lconst_2, REG_R20, .Lr2_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr2_pix0:
        .word   .Lconst_1, REG_R20, .Lr2_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Advance font_ptr and row pointer (R6) */
        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        /* Z = 0 from T4 advance? No: subleq doesn't clear Z. */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */

/*=== ROW 3 ===*/
.Lrow_3:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr3_pix7:
        .word   .Lconst_128, REG_R20, .Lr3_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr3_pix6:
        .word   .Lconst_64, REG_R20, .Lr3_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr3_pix5:
        .word   .Lconst_32, REG_R20, .Lr3_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr3_pix4:
        .word   .Lconst_16, REG_R20, .Lr3_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr3_pix3:
        .word   .Lconst_8, REG_R20, .Lr3_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr3_pix2:
        .word   .Lconst_4, REG_R20, .Lr3_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr3_pix1:
        .word   .Lconst_2, REG_R20, .Lr3_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr3_pix0:
        .word   .Lconst_1, REG_R20, .Lr3_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Advance font_ptr and row pointer (R6) */
        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        /* Z = 0 from T4 advance? No: subleq doesn't clear Z. */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */

/*=== ROW 4 ===*/
.Lrow_4:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr4_pix7:
        .word   .Lconst_128, REG_R20, .Lr4_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr4_pix6:
        .word   .Lconst_64, REG_R20, .Lr4_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr4_pix5:
        .word   .Lconst_32, REG_R20, .Lr4_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr4_pix4:
        .word   .Lconst_16, REG_R20, .Lr4_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr4_pix3:
        .word   .Lconst_8, REG_R20, .Lr4_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr4_pix2:
        .word   .Lconst_4, REG_R20, .Lr4_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr4_pix1:
        .word   .Lconst_2, REG_R20, .Lr4_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr4_pix0:
        .word   .Lconst_1, REG_R20, .Lr4_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Advance font_ptr and row pointer (R6) */
        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        /* Z = 0 from T4 advance? No: subleq doesn't clear Z. */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */

/*=== ROW 5 ===*/
.Lrow_5:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr5_pix7:
        .word   .Lconst_128, REG_R20, .Lr5_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr5_pix6:
        .word   .Lconst_64, REG_R20, .Lr5_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr5_pix5:
        .word   .Lconst_32, REG_R20, .Lr5_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr5_pix4:
        .word   .Lconst_16, REG_R20, .Lr5_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr5_pix3:
        .word   .Lconst_8, REG_R20, .Lr5_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr5_pix2:
        .word   .Lconst_4, REG_R20, .Lr5_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr5_pix1:
        .word   .Lconst_2, REG_R20, .Lr5_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr5_pix0:
        .word   .Lconst_1, REG_R20, .Lr5_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Advance font_ptr and row pointer (R6) */
        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        /* Z = 0 from T4 advance? No: subleq doesn't clear Z. */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */

/*=== ROW 6 ===*/
.Lrow_6:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr6_pix7:
        .word   .Lconst_128, REG_R20, .Lr6_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr6_pix6:
        .word   .Lconst_64, REG_R20, .Lr6_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr6_pix5:
        .word   .Lconst_32, REG_R20, .Lr6_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr6_pix4:
        .word   .Lconst_16, REG_R20, .Lr6_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr6_pix3:
        .word   .Lconst_8, REG_R20, .Lr6_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr6_pix2:
        .word   .Lconst_4, REG_R20, .Lr6_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr6_pix1:
        .word   .Lconst_2, REG_R20, .Lr6_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr6_pix0:
        .word   .Lconst_1, REG_R20, .Lr6_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Advance font_ptr and row pointer (R6) */
        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        /* Z = 0 from T4 advance? No: subleq doesn't clear Z. */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */

/*=== ROW 7 ===*/
.Lrow_7:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr7_pix7:
        .word   .Lconst_128, REG_R20, .Lr7_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr7_pix6:
        .word   .Lconst_64, REG_R20, .Lr7_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr7_pix5:
        .word   .Lconst_32, REG_R20, .Lr7_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr7_pix4:
        .word   .Lconst_16, REG_R20, .Lr7_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr7_pix3:
        .word   .Lconst_8, REG_R20, .Lr7_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr7_pix2:
        .word   .Lconst_4, REG_R20, .Lr7_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr7_pix1:
        .word   .Lconst_2, REG_R20, .Lr7_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr7_pix0:
        .word   .Lconst_1, REG_R20, .Lr7_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Advance font_ptr and row pointer (R6) */
        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        /* Z = 0 from T4 advance? No: subleq doesn't clear Z. */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */

/*=== ROW 8 ===*/
.Lrow_8:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr8_pix7:
        .word   .Lconst_128, REG_R20, .Lr8_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr8_pix6:
        .word   .Lconst_64, REG_R20, .Lr8_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr8_pix5:
        .word   .Lconst_32, REG_R20, .Lr8_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr8_pix4:
        .word   .Lconst_16, REG_R20, .Lr8_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr8_pix3:
        .word   .Lconst_8, REG_R20, .Lr8_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr8_pix2:
        .word   .Lconst_4, REG_R20, .Lr8_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr8_pix1:
        .word   .Lconst_2, REG_R20, .Lr8_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr8_pix0:
        .word   .Lconst_1, REG_R20, .Lr8_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Advance font_ptr and row pointer (R6) */
        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        /* Z = 0 from T4 advance? No: subleq doesn't clear Z. */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */

/*=== ROW 9 ===*/
.Lrow_9:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr9_pix7:
        .word   .Lconst_128, REG_R20, .Lr9_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr9_pix6:
        .word   .Lconst_64, REG_R20, .Lr9_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr9_pix5:
        .word   .Lconst_32, REG_R20, .Lr9_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr9_pix4:
        .word   .Lconst_16, REG_R20, .Lr9_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr9_pix3:
        .word   .Lconst_8, REG_R20, .Lr9_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr9_pix2:
        .word   .Lconst_4, REG_R20, .Lr9_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr9_pix1:
        .word   .Lconst_2, REG_R20, .Lr9_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr9_pix0:
        .word   .Lconst_1, REG_R20, .Lr9_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Advance font_ptr and row pointer (R6) */
        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        /* Z = 0 from T4 advance? No: subleq doesn't clear Z. */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */

/*=== ROW 10 ===*/
.Lrow_10:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr10_pix7:
        .word   .Lconst_128, REG_R20, .Lr10_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr10_pix6:
        .word   .Lconst_64, REG_R20, .Lr10_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr10_pix5:
        .word   .Lconst_32, REG_R20, .Lr10_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr10_pix4:
        .word   .Lconst_16, REG_R20, .Lr10_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr10_pix3:
        .word   .Lconst_8, REG_R20, .Lr10_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr10_pix2:
        .word   .Lconst_4, REG_R20, .Lr10_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr10_pix1:
        .word   .Lconst_2, REG_R20, .Lr10_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr10_pix0:
        .word   .Lconst_1, REG_R20, .Lr10_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Advance font_ptr and row pointer (R6) */
        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        /* Z = 0 from T4 advance? No: subleq doesn't clear Z. */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */

/*=== ROW 11 ===*/
.Lrow_11:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr11_pix7:
        .word   .Lconst_128, REG_R20, .Lr11_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr11_pix6:
        .word   .Lconst_64, REG_R20, .Lr11_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr11_pix5:
        .word   .Lconst_32, REG_R20, .Lr11_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr11_pix4:
        .word   .Lconst_16, REG_R20, .Lr11_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr11_pix3:
        .word   .Lconst_8, REG_R20, .Lr11_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr11_pix2:
        .word   .Lconst_4, REG_R20, .Lr11_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr11_pix1:
        .word   .Lconst_2, REG_R20, .Lr11_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr11_pix0:
        .word   .Lconst_1, REG_R20, .Lr11_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Advance font_ptr and row pointer (R6) */
        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        /* Z = 0 from T4 advance? No: subleq doesn't clear Z. */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */

/*=== ROW 12 ===*/
.Lrow_12:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr12_pix7:
        .word   .Lconst_128, REG_R20, .Lr12_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr12_pix6:
        .word   .Lconst_64, REG_R20, .Lr12_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr12_pix5:
        .word   .Lconst_32, REG_R20, .Lr12_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr12_pix4:
        .word   .Lconst_16, REG_R20, .Lr12_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr12_pix3:
        .word   .Lconst_8, REG_R20, .Lr12_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr12_pix2:
        .word   .Lconst_4, REG_R20, .Lr12_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr12_pix1:
        .word   .Lconst_2, REG_R20, .Lr12_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr12_pix0:
        .word   .Lconst_1, REG_R20, .Lr12_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Advance font_ptr and row pointer (R6) */
        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        /* Z = 0 from T4 advance? No: subleq doesn't clear Z. */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */

/*=== ROW 13 ===*/
.Lrow_13:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr13_pix7:
        .word   .Lconst_128, REG_R20, .Lr13_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr13_pix6:
        .word   .Lconst_64, REG_R20, .Lr13_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr13_pix5:
        .word   .Lconst_32, REG_R20, .Lr13_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr13_pix4:
        .word   .Lconst_16, REG_R20, .Lr13_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr13_pix3:
        .word   .Lconst_8, REG_R20, .Lr13_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr13_pix2:
        .word   .Lconst_4, REG_R20, .Lr13_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr13_pix1:
        .word   .Lconst_2, REG_R20, .Lr13_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr13_pix0:
        .word   .Lconst_1, REG_R20, .Lr13_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Advance font_ptr and row pointer (R6) */
        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        /* Z = 0 from T4 advance? No: subleq doesn't clear Z. */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */

/*=== ROW 14 ===*/
.Lrow_14:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr14_pix7:
        .word   .Lconst_128, REG_R20, .Lr14_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr14_pix6:
        .word   .Lconst_64, REG_R20, .Lr14_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr14_pix5:
        .word   .Lconst_32, REG_R20, .Lr14_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr14_pix4:
        .word   .Lconst_16, REG_R20, .Lr14_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr14_pix3:
        .word   .Lconst_8, REG_R20, .Lr14_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr14_pix2:
        .word   .Lconst_4, REG_R20, .Lr14_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr14_pix1:
        .word   .Lconst_2, REG_R20, .Lr14_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr14_pix0:
        .word   .Lconst_1, REG_R20, .Lr14_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Advance font_ptr and row pointer (R6) */
        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        /* Z = 0 from T4 advance? No: subleq doesn't clear Z. */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */

/*=== ROW 15 ===*/
.Lrow_15:
        /* Read font byte (Z clean here) */
        .word   REG_T15 | INDIRECT, REG_Z, .+4  /* Z = -font[T15] */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        .word   REG_Z, REG_R20, .+4              /* R20 = font byte */
        .word   .Lconst_n1, REG_R20, .+4         /* bias +1 */

.Lr15_pix7:
        .word   .Lconst_128, REG_R20, .Lr15_pix7_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr15_pix6:
        .word   .Lconst_64, REG_R20, .Lr15_pix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr15_pix5:
        .word   .Lconst_32, REG_R20, .Lr15_pix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr15_pix4:
        .word   .Lconst_16, REG_R20, .Lr15_pix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr15_pix3:
        .word   .Lconst_8, REG_R20, .Lr15_pix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr15_pix2:
        .word   .Lconst_4, REG_R20, .Lr15_pix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr15_pix1:
        .word   .Lconst_2, REG_R20, .Lr15_pix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
.Lr15_pix0:
        .word   .Lconst_1, REG_R20, .Lr15_pix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T13, REG_R21 | INDIRECT, .+4
        /* Last row done - advance font_ptr and return */

        /* Advance font_ptr past last row (for final char) */
        .word   .Lconst_n4, REG_T15, .+4
        /* fall through to return */

.Lrow_done_fg:
        /* Return to caller via T5 */
        .word   REG_Z, REG_Z, REG_T5 | INDIRECT

/*===========================================================================
 * BG COLD TRAMPOLINES (out-of-line to keep FG path tight)
 * Each: restore R20, clear pixel, write bg, advance R21, jump back
 *===========================================================================*/
.Lr0_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr0_pix6

.Lr0_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr0_pix5

.Lr0_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr0_pix4

.Lr0_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr0_pix3

.Lr0_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr0_pix2

.Lr0_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr0_pix1

.Lr0_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr0_pix0

.Lr0_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        .word   REG_Z, REG_Z, .Lrow_1         /* clear Z + jump */

.Lr1_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr1_pix6

.Lr1_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr1_pix5

.Lr1_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr1_pix4

.Lr1_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr1_pix3

.Lr1_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr1_pix2

.Lr1_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr1_pix1

.Lr1_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr1_pix0

.Lr1_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        .word   REG_Z, REG_Z, .Lrow_2         /* clear Z + jump */

.Lr2_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr2_pix6

.Lr2_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr2_pix5

.Lr2_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr2_pix4

.Lr2_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr2_pix3

.Lr2_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr2_pix2

.Lr2_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr2_pix1

.Lr2_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr2_pix0

.Lr2_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        .word   REG_Z, REG_Z, .Lrow_3         /* clear Z + jump */

.Lr3_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr3_pix6

.Lr3_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr3_pix5

.Lr3_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr3_pix4

.Lr3_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr3_pix3

.Lr3_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr3_pix2

.Lr3_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr3_pix1

.Lr3_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr3_pix0

.Lr3_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        .word   REG_Z, REG_Z, .Lrow_4         /* clear Z + jump */

.Lr4_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr4_pix6

.Lr4_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr4_pix5

.Lr4_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr4_pix4

.Lr4_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr4_pix3

.Lr4_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr4_pix2

.Lr4_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr4_pix1

.Lr4_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr4_pix0

.Lr4_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        .word   REG_Z, REG_Z, .Lrow_5         /* clear Z + jump */

.Lr5_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr5_pix6

.Lr5_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr5_pix5

.Lr5_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr5_pix4

.Lr5_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr5_pix3

.Lr5_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr5_pix2

.Lr5_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr5_pix1

.Lr5_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr5_pix0

.Lr5_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        .word   REG_Z, REG_Z, .Lrow_6         /* clear Z + jump */

.Lr6_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr6_pix6

.Lr6_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr6_pix5

.Lr6_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr6_pix4

.Lr6_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr6_pix3

.Lr6_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr6_pix2

.Lr6_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr6_pix1

.Lr6_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr6_pix0

.Lr6_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        .word   REG_Z, REG_Z, .Lrow_7         /* clear Z + jump */

.Lr7_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr7_pix6

.Lr7_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr7_pix5

.Lr7_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr7_pix4

.Lr7_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr7_pix3

.Lr7_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr7_pix2

.Lr7_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr7_pix1

.Lr7_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr7_pix0

.Lr7_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        .word   REG_Z, REG_Z, .Lrow_8         /* clear Z + jump */

.Lr8_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr8_pix6

.Lr8_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr8_pix5

.Lr8_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr8_pix4

.Lr8_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr8_pix3

.Lr8_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr8_pix2

.Lr8_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr8_pix1

.Lr8_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr8_pix0

.Lr8_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        .word   REG_Z, REG_Z, .Lrow_9         /* clear Z + jump */

.Lr9_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr9_pix6

.Lr9_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr9_pix5

.Lr9_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr9_pix4

.Lr9_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr9_pix3

.Lr9_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr9_pix2

.Lr9_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr9_pix1

.Lr9_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr9_pix0

.Lr9_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        .word   REG_Z, REG_Z, .Lrow_10        /* clear Z + jump */

.Lr10_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr10_pix6

.Lr10_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr10_pix5

.Lr10_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr10_pix4

.Lr10_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr10_pix3

.Lr10_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr10_pix2

.Lr10_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr10_pix1

.Lr10_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr10_pix0

.Lr10_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        .word   REG_Z, REG_Z, .Lrow_11        /* clear Z + jump */

.Lr11_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr11_pix6

.Lr11_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr11_pix5

.Lr11_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr11_pix4

.Lr11_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr11_pix3

.Lr11_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr11_pix2

.Lr11_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr11_pix1

.Lr11_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr11_pix0

.Lr11_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        .word   REG_Z, REG_Z, .Lrow_12        /* clear Z + jump */

.Lr12_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr12_pix6

.Lr12_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr12_pix5

.Lr12_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr12_pix4

.Lr12_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr12_pix3

.Lr12_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr12_pix2

.Lr12_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr12_pix1

.Lr12_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr12_pix0

.Lr12_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        .word   REG_Z, REG_Z, .Lrow_13        /* clear Z + jump */

.Lr13_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr13_pix6

.Lr13_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr13_pix5

.Lr13_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr13_pix4

.Lr13_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr13_pix3

.Lr13_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr13_pix2

.Lr13_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr13_pix1

.Lr13_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr13_pix0

.Lr13_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        .word   REG_Z, REG_Z, .Lrow_14        /* clear Z + jump */

.Lr14_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr14_pix6

.Lr14_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr14_pix5

.Lr14_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr14_pix4

.Lr14_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr14_pix3

.Lr14_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr14_pix2

.Lr14_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr14_pix1

.Lr14_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr14_pix0

.Lr14_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4      /* T15 += 4 */
        .word   REG_R22, REG_R21, .+4          /* R21 += pitch-32 */
        .word   REG_Z, REG_Z, .Lrow_15        /* clear Z + jump */

.Lr15_pix7_bg:
        .word   .Lconst_n128, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr15_pix6

.Lr15_pix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr15_pix5

.Lr15_pix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr15_pix4

.Lr15_pix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr15_pix3

.Lr15_pix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr15_pix2

.Lr15_pix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr15_pix1

.Lr15_pix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   .Lconst_n4, REG_R21, .+4
        .word   REG_Z, REG_Z, .Lr15_pix0

.Lr15_pix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_T14, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_n4, REG_T15, .+4
        /* fall through into .Lrow_done */
.Lrow_done:
        /* Return to caller via T5 */
        .word   REG_Z, REG_Z, REG_T5 | INDIRECT


.Ldone:
        /* Return: Load RA from [SP], pop the stack, and jump to return address */
        .word   REG_T4, REG_T4, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_SP | INDIRECT, REG_Z, .+4   /* Z = -[SP] = -return_addr */
        .word   REG_Z, REG_T4, .+4              /* T4 = return_addr */
        .word   REG_Z, REG_Z, .+4               /* Z = 0 */
        /* Pop RA: SP += 4 (callee must undo the push done by emitPushRALabel) */
        .word   .Lconst_n4, REG_SP, .+4
        .word   REG_Z, REG_Z, REG_T4 | INDIRECT /* Jump to [T4] = return_addr */

/*===========================================================================
 * INLINE EXTRACTION LATTICE
 *
 * Biased non-restoring lattice that extracts 4 bytes from a u32 word in T3.
 * Outputs: T0=char0 (bits 0-7), T1=attr0 (bits 8-15),
 *          T2=char1 (bits 16-23), T4=attr1 (bits 24-31)
 *
 * Follows the same pattern as emit_lb_o1.py:
 *   1. Sign bit (bit 31) check
 *   2. Bias T3 += 1
 *   3. For bits 30..0: P/N state lattice with accumulation
 *
 * Each accumulating bit k adds 2^(k%8) to the target register:
 *   bits 0-7 -> T0 (char0), bits 8-15 -> T1 (attr0),
 *   bits 16-23 -> T2 (char1), bits 24-30 -> T4 (attr1)
 *
 * Cost: ~70 executed instructions (2-3 per bit on average)
 *===========================================================================*/

/* === Sign bit (bit 31) handling === */
.Lext_sign:
        .word   .Lconst_0, REG_T3, .Lext_le0  /* if T3 <= 0, cold path */
        /* T3 > 0: bit 31 clear, fall through to bias (HOT PATH) */

.Lext_bias:
        .word   .Lconst_n1, REG_T3, .+4       /* T3 += 1 (bias) */

/* === Bit 30 (attr1 bit 6, accumulates 64 to T4) === */
.Lext_b30_P:
        .word   .Lxc1073741824, REG_T3, .Lext_b30_PN
        .word   REG_Z, REG_Z, .Lext_b29_P
.Lext_b30_PN:
        .word   REG_Z, REG_Z, .Lext_b29_N

.Lext_b30_N:
        .word   .Lxn1073741824, REG_T3, .Lext_b30_NN
        .word   REG_Z, REG_Z, .Lext_b29_P
.Lext_b30_NN:
        .word   REG_Z, REG_Z, .Lext_b29_N

/* === Bit 29 (attr1 bit 5, accumulates 32 to T4) === */
.Lext_b29_P:
        .word   .Lxc536870912, REG_T3, .Lext_b29_PN
        .word   REG_Z, REG_Z, .Lext_b28_P
.Lext_b29_PN:
        .word   REG_Z, REG_Z, .Lext_b28_N

.Lext_b29_N:
        .word   .Lxn536870912, REG_T3, .Lext_b29_NN
        .word   REG_Z, REG_Z, .Lext_b28_P
.Lext_b29_NN:
        .word   REG_Z, REG_Z, .Lext_b28_N

/* === Bit 28 (attr1 bit 4, accumulates 16 to T4) === */
.Lext_b28_P:
        .word   .Lxc268435456, REG_T3, .Lext_b28_PN
        .word   REG_Z, REG_Z, .Lext_b27_P
.Lext_b28_PN:
        .word   REG_Z, REG_Z, .Lext_b27_N

.Lext_b28_N:
        .word   .Lxn268435456, REG_T3, .Lext_b28_NN
        .word   REG_Z, REG_Z, .Lext_b27_P
.Lext_b28_NN:
        .word   REG_Z, REG_Z, .Lext_b27_N

/* === Bit 27 (attr1 bit 3, accumulates 8 to T4) === */
.Lext_b27_P:
        .word   .Lxc134217728, REG_T3, .Lext_b27_PN
        .word   REG_Z, REG_Z, .Lext_b26_P
.Lext_b27_PN:
        .word   REG_Z, REG_Z, .Lext_b26_N

.Lext_b27_N:
        .word   .Lxn134217728, REG_T3, .Lext_b27_NN
        .word   REG_Z, REG_Z, .Lext_b26_P
.Lext_b27_NN:
        .word   REG_Z, REG_Z, .Lext_b26_N

/* === Bit 26 (attr1 bit 2, accumulates 4 to T4) === */
.Lext_b26_P:
        .word   .Lxc67108864, REG_T3, .Lext_b26_PN
        .word   REG_Z, REG_Z, .Lext_b25_P
.Lext_b26_PN:
        .word   REG_Z, REG_Z, .Lext_b25_N

.Lext_b26_N:
        .word   .Lxn67108864, REG_T3, .Lext_b26_NN
        .word   REG_Z, REG_Z, .Lext_b25_P
.Lext_b26_NN:
        .word   REG_Z, REG_Z, .Lext_b25_N

/* === Bit 25 (attr1 bit 1, accumulates 2 to T4) === */
.Lext_b25_P:
        .word   .Lxc33554432, REG_T3, .Lext_b25_PN
        .word   REG_Z, REG_Z, .Lext_b24_P
.Lext_b25_PN:
        .word   REG_Z, REG_Z, .Lext_b24_N

.Lext_b25_N:
        .word   .Lxn33554432, REG_T3, .Lext_b25_NN
        .word   REG_Z, REG_Z, .Lext_b24_P
.Lext_b25_NN:
        .word   REG_Z, REG_Z, .Lext_b24_N

/* === Bit 24 (attr1 bit 0, accumulates 1 to T4) === */
.Lext_b24_P:
        .word   .Lxc16777216, REG_T3, .Lext_b24_PN
        .word   REG_Z, REG_Z, .Lext_b23_P
.Lext_b24_PN:
        .word   REG_Z, REG_Z, .Lext_b23_N

.Lext_b24_N:
        .word   .Lxn16777216, REG_T3, .Lext_b24_NN
        .word   REG_Z, REG_Z, .Lext_b23_P
.Lext_b24_NN:
        .word   REG_Z, REG_Z, .Lext_b23_N

/* === Bit 23 (char1 bit 7, accumulates 128*64=8192 to T2) === */
.Lext_b23_P:
        .word   .Lxc8388608, REG_T3, .Lext_b23_PN
        .word   .Lconst_n8192, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b22_P
.Lext_b23_PN:
        .word   REG_Z, REG_Z, .Lext_b22_N

.Lext_b23_N:
        .word   .Lxn8388608, REG_T3, .Lext_b23_NN
        .word   .Lconst_n8192, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b22_P
.Lext_b23_NN:
        .word   REG_Z, REG_Z, .Lext_b22_N

/* === Bit 22 (char1 bit 6, accumulates 64*64=4096 to T2) === */
.Lext_b22_P:
        .word   .Lxc4194304, REG_T3, .Lext_b22_PN
        .word   .Lconst_n4096, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b21_P
.Lext_b22_PN:
        .word   REG_Z, REG_Z, .Lext_b21_N

.Lext_b22_N:
        .word   .Lxn4194304, REG_T3, .Lext_b22_NN
        .word   .Lconst_n4096, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b21_P
.Lext_b22_NN:
        .word   REG_Z, REG_Z, .Lext_b21_N

/* === Bit 21 (char1 bit 5, accumulates 32*64=2048 to T2) === */
.Lext_b21_P:
        .word   .Lxc2097152, REG_T3, .Lext_b21_PN
        .word   .Lconst_n2048, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b20_P
.Lext_b21_PN:
        .word   REG_Z, REG_Z, .Lext_b20_N

.Lext_b21_N:
        .word   .Lxn2097152, REG_T3, .Lext_b21_NN
        .word   .Lconst_n2048, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b20_P
.Lext_b21_NN:
        .word   REG_Z, REG_Z, .Lext_b20_N

/* === Bit 20 (char1 bit 4, accumulates 16*64=1024 to T2) === */
.Lext_b20_P:
        .word   .Lxc1048576, REG_T3, .Lext_b20_PN
        .word   .Lconst_n1024, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b19_P
.Lext_b20_PN:
        .word   REG_Z, REG_Z, .Lext_b19_N

.Lext_b20_N:
        .word   .Lxn1048576, REG_T3, .Lext_b20_NN
        .word   .Lconst_n1024, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b19_P
.Lext_b20_NN:
        .word   REG_Z, REG_Z, .Lext_b19_N

/* === Bit 19 (char1 bit 3, accumulates 8*64=512 to T2) === */
.Lext_b19_P:
        .word   .Lxc524288, REG_T3, .Lext_b19_PN
        .word   .Lconst_n512, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b18_P
.Lext_b19_PN:
        .word   REG_Z, REG_Z, .Lext_b18_N

.Lext_b19_N:
        .word   .Lxn524288, REG_T3, .Lext_b19_NN
        .word   .Lconst_n512, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b18_P
.Lext_b19_NN:
        .word   REG_Z, REG_Z, .Lext_b18_N

/* === Bit 18 (char1 bit 2, accumulates 4*64=256 to T2) === */
.Lext_b18_P:
        .word   .Lxc262144, REG_T3, .Lext_b18_PN
        .word   .Lconst_n256, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b17_P
.Lext_b18_PN:
        .word   REG_Z, REG_Z, .Lext_b17_N

.Lext_b18_N:
        .word   .Lxn262144, REG_T3, .Lext_b18_NN
        .word   .Lconst_n256, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b17_P
.Lext_b18_NN:
        .word   REG_Z, REG_Z, .Lext_b17_N

/* === Bit 17 (char1 bit 1, accumulates 2*64=128 to T2) === */
.Lext_b17_P:
        .word   .Lxc131072, REG_T3, .Lext_b17_PN
        .word   .Lconst_n128, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b16_P
.Lext_b17_PN:
        .word   REG_Z, REG_Z, .Lext_b16_N

.Lext_b17_N:
        .word   .Lxn131072, REG_T3, .Lext_b17_NN
        .word   .Lconst_n128, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b16_P
.Lext_b17_NN:
        .word   REG_Z, REG_Z, .Lext_b16_N

/* === Bit 16 (char1 bit 0, accumulates 1*64=64 to T2) === */
.Lext_b16_P:
        .word   .Lxc65536, REG_T3, .Lext_b16_PN
        .word   .Lconst_n64, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b15_P
.Lext_b16_PN:
        .word   REG_Z, REG_Z, .Lext_b15_N

.Lext_b16_N:
        .word   .Lxn65536, REG_T3, .Lext_b16_NN
        .word   .Lconst_n64, REG_T2, .+4
        .word   REG_Z, REG_Z, .Lext_b15_P
.Lext_b16_NN:
        .word   REG_Z, REG_Z, .Lext_b15_N

/* === Bit 15 (attr0 bit 7, accumulates 128 to T1) === */
.Lext_b15_P:
        .word   .Lxc32768, REG_T3, .Lext_b15_PN
        .word   REG_Z, REG_Z, .Lext_b14_P
.Lext_b15_PN:
        .word   REG_Z, REG_Z, .Lext_b14_N

.Lext_b15_N:
        .word   .Lxn32768, REG_T3, .Lext_b15_NN
        .word   REG_Z, REG_Z, .Lext_b14_P
.Lext_b15_NN:
        .word   REG_Z, REG_Z, .Lext_b14_N

/* === Bit 14 (attr0 bit 6, accumulates 64 to T1) === */
.Lext_b14_P:
        .word   .Lxc16384, REG_T3, .Lext_b14_PN
        .word   REG_Z, REG_Z, .Lext_b13_P
.Lext_b14_PN:
        .word   REG_Z, REG_Z, .Lext_b13_N

.Lext_b14_N:
        .word   .Lxn16384, REG_T3, .Lext_b14_NN
        .word   REG_Z, REG_Z, .Lext_b13_P
.Lext_b14_NN:
        .word   REG_Z, REG_Z, .Lext_b13_N

/* === Bit 13 (attr0 bit 5, accumulates 32 to T1) === */
.Lext_b13_P:
        .word   .Lxc8192, REG_T3, .Lext_b13_PN
        .word   REG_Z, REG_Z, .Lext_b12_P
.Lext_b13_PN:
        .word   REG_Z, REG_Z, .Lext_b12_N

.Lext_b13_N:
        .word   .Lxn8192, REG_T3, .Lext_b13_NN
        .word   REG_Z, REG_Z, .Lext_b12_P
.Lext_b13_NN:
        .word   REG_Z, REG_Z, .Lext_b12_N

/* === Bit 12 (attr0 bit 4, accumulates 16 to T1) === */
.Lext_b12_P:
        .word   .Lxc4096, REG_T3, .Lext_b12_PN
        .word   REG_Z, REG_Z, .Lext_b11_P
.Lext_b12_PN:
        .word   REG_Z, REG_Z, .Lext_b11_N

.Lext_b12_N:
        .word   .Lxn4096, REG_T3, .Lext_b12_NN
        .word   REG_Z, REG_Z, .Lext_b11_P
.Lext_b12_NN:
        .word   REG_Z, REG_Z, .Lext_b11_N

/* === Bit 11 (attr0 bit 3, accumulates 8 to T1) === */
.Lext_b11_P:
        .word   .Lxc2048, REG_T3, .Lext_b11_PN
        .word   REG_Z, REG_Z, .Lext_b10_P
.Lext_b11_PN:
        .word   REG_Z, REG_Z, .Lext_b10_N

.Lext_b11_N:
        .word   .Lxn2048, REG_T3, .Lext_b11_NN
        .word   REG_Z, REG_Z, .Lext_b10_P
.Lext_b11_NN:
        .word   REG_Z, REG_Z, .Lext_b10_N

/* === Bit 10 (attr0 bit 2, accumulates 4 to T1) === */
.Lext_b10_P:
        .word   .Lxc1024, REG_T3, .Lext_b10_PN
        .word   REG_Z, REG_Z, .Lext_b9_P
.Lext_b10_PN:
        .word   REG_Z, REG_Z, .Lext_b9_N

.Lext_b10_N:
        .word   .Lxn1024, REG_T3, .Lext_b10_NN
        .word   REG_Z, REG_Z, .Lext_b9_P
.Lext_b10_NN:
        .word   REG_Z, REG_Z, .Lext_b9_N

/* === Bit 9 (attr0 bit 1, accumulates 2 to T1) === */
.Lext_b9_P:
        .word   .Lxc512, REG_T3, .Lext_b9_PN
        .word   REG_Z, REG_Z, .Lext_b8_P
.Lext_b9_PN:
        .word   REG_Z, REG_Z, .Lext_b8_N

.Lext_b9_N:
        .word   .Lxn512, REG_T3, .Lext_b9_NN
        .word   REG_Z, REG_Z, .Lext_b8_P
.Lext_b9_NN:
        .word   REG_Z, REG_Z, .Lext_b8_N

/* === Bit 8 (attr0 bit 0, accumulates 1 to T1) === */
.Lext_b8_P:
        .word   .Lxc256, REG_T3, .Lext_b8_PN
        .word   REG_Z, REG_Z, .Lext_b7_P
.Lext_b8_PN:
        .word   REG_Z, REG_Z, .Lext_b7_N

.Lext_b8_N:
        .word   .Lxn256, REG_T3, .Lext_b8_NN
        .word   REG_Z, REG_Z, .Lext_b7_P
.Lext_b8_NN:
        .word   REG_Z, REG_Z, .Lext_b7_N

/* === Bit 7 (char0 bit 7, accumulates 128*64=8192 to T0) === */
.Lext_b7_P:
        .word   .Lconst_128, REG_T3, .Lext_b7_PN
        .word   .Lconst_n8192, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_b6_P
.Lext_b7_PN:
        .word   REG_Z, REG_Z, .Lext_b6_N

.Lext_b7_N:
        .word   .Lconst_n128, REG_T3, .Lext_b7_NN
        .word   .Lconst_n8192, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_b6_P
.Lext_b7_NN:
        .word   REG_Z, REG_Z, .Lext_b6_N

/* === Bit 6 (char0 bit 6, accumulates 64*64=4096 to T0) === */
.Lext_b6_P:
        .word   .Lconst_64, REG_T3, .Lext_b6_PN
        .word   .Lconst_n4096, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_b5_P
.Lext_b6_PN:
        .word   REG_Z, REG_Z, .Lext_b5_N

.Lext_b6_N:
        .word   .Lconst_n64, REG_T3, .Lext_b6_NN
        .word   .Lconst_n4096, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_b5_P
.Lext_b6_NN:
        .word   REG_Z, REG_Z, .Lext_b5_N

/* === Bit 5 (char0 bit 5, accumulates 32*64=2048 to T0) === */
.Lext_b5_P:
        .word   .Lconst_32, REG_T3, .Lext_b5_PN
        .word   .Lconst_n2048, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_b4_P
.Lext_b5_PN:
        .word   REG_Z, REG_Z, .Lext_b4_N

.Lext_b5_N:
        .word   .Lconst_n32, REG_T3, .Lext_b5_NN
        .word   .Lconst_n2048, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_b4_P
.Lext_b5_NN:
        .word   REG_Z, REG_Z, .Lext_b4_N

/* === Bit 4 (char0 bit 4, accumulates 16*64=1024 to T0) === */
.Lext_b4_P:
        .word   .Lconst_16, REG_T3, .Lext_b4_PN
        .word   .Lconst_n1024, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_b3_P
.Lext_b4_PN:
        .word   REG_Z, REG_Z, .Lext_b3_N

.Lext_b4_N:
        .word   .Lconst_n16, REG_T3, .Lext_b4_NN
        .word   .Lconst_n1024, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_b3_P
.Lext_b4_NN:
        .word   REG_Z, REG_Z, .Lext_b3_N

/* === Bit 3 (char0 bit 3, accumulates 8*64=512 to T0) === */
.Lext_b3_P:
        .word   .Lconst_8, REG_T3, .Lext_b3_PN
        .word   .Lconst_n512, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_b2_P
.Lext_b3_PN:
        .word   REG_Z, REG_Z, .Lext_b2_N

.Lext_b3_N:
        .word   .Lconst_n8, REG_T3, .Lext_b3_NN
        .word   .Lconst_n512, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_b2_P
.Lext_b3_NN:
        .word   REG_Z, REG_Z, .Lext_b2_N

/* === Bit 2 (char0 bit 2, accumulates 4*64=256 to T0) === */
.Lext_b2_P:
        .word   .Lconst_4, REG_T3, .Lext_b2_PN
        .word   .Lconst_n256, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_b1_P
.Lext_b2_PN:
        .word   REG_Z, REG_Z, .Lext_b1_N

.Lext_b2_N:
        .word   .Lconst_n4, REG_T3, .Lext_b2_NN
        .word   .Lconst_n256, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_b1_P
.Lext_b2_NN:
        .word   REG_Z, REG_Z, .Lext_b1_N

/* === Bit 1 (char0 bit 1, accumulates 2*64=128 to T0) === */
.Lext_b1_P:
        .word   .Lconst_2, REG_T3, .Lext_b1_PN
        .word   .Lconst_n128, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_b0_P
.Lext_b1_PN:
        .word   REG_Z, REG_Z, .Lext_b0_N

.Lext_b1_N:
        .word   .Lconst_n2, REG_T3, .Lext_b1_NN
        .word   .Lconst_n128, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_b0_P
.Lext_b1_NN:
        .word   REG_Z, REG_Z, .Lext_b0_N

/* === Bit 0 (char0 bit 0, accumulates 1*64=64 to T0) === */
.Lext_b0_P:
        .word   .Lconst_1, REG_T3, .Lext_b0_PN
        .word   .Lconst_n64, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_ret
.Lext_b0_PN:
        .word   REG_Z, REG_Z, .Lext_ret

.Lext_b0_N:
        .word   .Lconst_n1, REG_T3, .Lext_b0_NN
        .word   .Lconst_n64, REG_T0, .+4
        .word   REG_Z, REG_Z, .Lext_ret
.Lext_b0_NN:
        .word   REG_Z, REG_Z, .Lext_ret

/* === Cold path: T3 <= 0 (sign bit handling) === */
.Lext_le0:
        /* Distinguish T3 = 0 from T3 < 0 */
        .word   REG_T6, REG_T6, .+4           /* T6 = 0 */
        .word   REG_Z, REG_Z, .+4             /* Z = 0 */
        .word   REG_T3, REG_Z, .+4            /* Z = -T3 */
        .word   REG_Z, REG_T6, .+4            /* T6 = T3 */
        .word   .Lconst_n1, REG_T6, .+4       /* T6 = T3 + 1 */
        .word   .Lconst_0, REG_T6, .Lext_neg  /* if T6 <= 0 → T3 < 0 */
        /* T3 = 0: bit 31 not set, go to bias */
        .word   REG_Z, REG_Z, .Lext_bias

.Lext_neg:
        /* T3 < 0 (bit 31 set): clear bit 31 (attr1 bit 7 not accumulated) */
        .word   .Lext_min, REG_T3, .+4        /* T3 -= INT_MIN = clear bit 31 */
        .word   REG_Z, REG_Z, .Lext_bias      /* goto bias */

/*===========================================================================
 * CONSTANTS
 *===========================================================================*/

/* Existing small constants */
.Lconst_n8192:  .word   -8192
.Lconst_n4096:  .word   -4096
.Lconst_n2048:  .word   -2048
.Lconst_n1024:  .word   -1024
.Lconst_n512:   .word   -512
.Lconst_n256:   .word   -256
.Lconst_n128:   .word   -128
.Lconst_n64:    .word   -64
.Lconst_n32:    .word   -32
.Lconst_n28:    .word   -28
.Lconst_n24:    .word   -24
.Lconst_n16:    .word   -16
.Lconst_n8:     .word   -8
.Lconst_n4:     .word   -4
.Lconst_n2:     .word   -2
.Lconst_n1:     .word   -1
.Lconst_0:      .word   0
.Lconst_1:      .word   1
.Lconst_2:      .word   2
.Lconst_4:      .word   4
.Lconst_8:      .word   8
.Lconst_12:     .word   12
.Lconst_16:     .word   16
.Lconst_24:     .word   24
.Lconst_32:     .word   32
.Lconst_64:     .word   64
.Lconst_128:    .word   128

/* Lattice test constants: positive powers of 2 (for P-state subtraction) */
.Lxc256:          .word   256
.Lxc512:          .word   512
.Lxc1024:         .word   1024
.Lxc2048:         .word   2048
.Lxc4096:         .word   4096
.Lxc8192:         .word   8192
.Lxc16384:        .word   16384
.Lxc32768:        .word   32768
.Lxc65536:        .word   65536
.Lxc131072:       .word   131072
.Lxc262144:       .word   262144
.Lxc524288:       .word   524288
.Lxc1048576:      .word   1048576
.Lxc2097152:      .word   2097152
.Lxc4194304:      .word   4194304
.Lxc8388608:      .word   8388608
.Lxc16777216:     .word   16777216
.Lxc33554432:     .word   33554432
.Lxc67108864:     .word   67108864
.Lxc134217728:    .word   134217728
.Lxc268435456:    .word   268435456
.Lxc536870912:    .word   536870912
.Lxc1073741824:   .word   1073741824

/* Lattice test constants: negative powers (for N-state addition) */
.Lxn256:          .word   -256
.Lxn512:          .word   -512
.Lxn1024:         .word   -1024
.Lxn2048:         .word   -2048
.Lxn4096:         .word   -4096
.Lxn8192:         .word   -8192
.Lxn16384:        .word   -16384
.Lxn32768:        .word   -32768
.Lxn65536:        .word   -65536
.Lxn131072:       .word   -131072
.Lxn262144:       .word   -262144
.Lxn524288:       .word   -524288
.Lxn1048576:      .word   -1048576
.Lxn2097152:      .word   -2097152
.Lxn4194304:      .word   -4194304
.Lxn8388608:      .word   -8388608
.Lxn16777216:     .word   -16777216
.Lxn33554432:     .word   -33554432
.Lxn67108864:     .word   -67108864
.Lxn134217728:    .word   -134217728
.Lxn268435456:    .word   -268435456
.Lxn536870912:    .word   -536870912
.Lxn1073741824:   .word   -1073741824

/* INT_MIN for sign bit clearing */
.Lext_min:        .word   -2147483648

/* Return address constants */
.Lmul_ret_const:    .word   .Lmul_ret
.Lmul_ret_neg:      .word   -.Lmul_ret
.Lrender0_ret_c:    .word   .Lrender0_ret
.Lrender1_ret_c:    .word   .Lrender1_ret
/* Negated return address constants for 4-insn T5 load */
.Lrender0_ret_neg:  .word   -.Lrender0_ret
.Lrender1_ret_neg:  .word   -.Lrender1_ret

.size subleq_direct_putcs, . - subleq_direct_putcs
