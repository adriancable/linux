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
 *   [SP+32] = s_pitch   - Bytes per screen char (usually 2)
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
 *   T15 = scratch / loop counter
 */

        .text
        .globl  subleq_direct_putcs
        .type   subleq_direct_putcs, @function
        .balign 4
subleq_direct_putcs:

/* Register offsets */
.set REG_Z, 12
.set REG_SP, 16
.set REG_R20, 96
.set REG_R21, 100
.set REG_R22, 104
.set REG_R23, 108
.set REG_R24, 112
.set REG_T4, 176
.set REG_T8, 192
.set REG_T9, 196
.set REG_T10, 200
.set REG_T11, 204
.set REG_T12, 208
.set REG_T13, 212
.set REG_T14, 216
.set REG_T15, 220
.set INDIRECT, 2

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

        /* T8 = fb = R21 */
        .word   REG_T8, REG_T8, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R21, REG_Z, .+4
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
         * [SP+16] = s_pitch (arg 8, hardcoded to 2)
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

        /* Skip s_pitch [SP+16] - we hardcode 2 */
        .word   .Lconst_n4, REG_T15, .+4  /* T15 = SP + 16 */

        /* T13 = fg = [SP+20] */
        .word   .Lconst_n4, REG_T15, .+4  /* T15 = SP + 20 */
        .word   REG_T13, REG_T13, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T15 | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_T13, .+4
        .word   REG_Z, REG_Z, .+4

        /* T14 = bg = [SP+24] */
        .word   .Lconst_n4, REG_T15, .+4  /* T15 = SP + 24 */
        .word   REG_T14, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T15 | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4

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
        .word   REG_Z, REG_Z, .+4
        .word   .Lmul_ret_const, REG_Z, .+4
        .word   REG_Z, REG_SP | INDIRECT, .+4
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

/*===========================================================================
 * MAIN CHARACTER LOOP
 *===========================================================================*/
.Lchar_loop:
        /* if T11 (cnt) <= 0, done */
        .word   REG_Z, REG_T11, .Ldone

        /* Read character code using __subleq_lb from T9 */
        .word   REG_R21, REG_R21, .+4
        .word   REG_T9, REG_Z, .+4
        .word   REG_Z, REG_R21, .+4
        .word   REG_Z, REG_Z, .+4

        .word   .Lconst_4, REG_SP, .+4
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   .Llb_ret_const, REG_Z, .+4
        .word   REG_Z, REG_SP | INDIRECT, .+4
        .word   REG_Z, REG_Z, __subleq_lb

.Llb_ret:
        /* __subleq_lb already popped return address, no extra pop needed */

        /* R20 = char code. Compute font_ptr = font + char * 64 */
        .word   REG_T15, REG_T15, .+4
        .word   REG_R20, REG_Z, .+4
        .word   REG_Z, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4

        /* T15 = ch * 64 via 6 doublings */
        .word   REG_T15, REG_Z, .+4
        .word   REG_Z, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T15, REG_Z, .+4
        .word   REG_Z, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T15, REG_Z, .+4
        .word   REG_Z, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T15, REG_Z, .+4
        .word   REG_Z, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T15, REG_Z, .+4
        .word   REG_Z, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T15, REG_Z, .+4
        .word   REG_Z, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4

        /* T15 += T10 => T15 = font + ch*64 (font_ptr) */
        .word   REG_T10, REG_Z, .+4
        .word   REG_Z, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4

        /* Save pixel row pointer = T8 to R22 */
        .word   REG_R22, REG_R22, .+4
        .word   REG_T8, REG_Z, .+4
        .word   REG_Z, REG_R22, .+4
        .word   REG_Z, REG_Z, .+4

        /* R23 = 16 (row counter) */
        .word   REG_R23, REG_R23, .+4
        .word   REG_Z, REG_Z, .+4
        .word   .Lconst_16, REG_Z, .+4
        .word   REG_Z, REG_R23, .+4
        .word   REG_Z, REG_Z, .+4

/*=== ROW LOOP (16 rows) ===*/
.Lrow_loop:
        .word   REG_Z, REG_R23, .Lrow_done

        /* Read font byte (as word) from [T15] */
        .word   REG_R20, REG_R20, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T15 | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_R20, .+4
        .word   REG_Z, REG_Z, .+4

        /* CRITICAL: Bias font byte by +1 for correct bit testing */
        /* Without this, byte=0x80 - 0x80 = 0 branches to bg incorrectly */
        .word   .Lconst_n1, REG_R20, .+4

        /* R21 = pixel pointer for this row */
        .word   REG_R21, REG_R21, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R22, REG_Z, .+4
        .word   REG_Z, REG_R21, .+4


        /* Process 8 pixels - use pattern from subleq_blit_row.S */
        /* For each pixel: subtract positive mask from R20, branch to bg if <= 0 */
        /* fg path: clear Z, write fg, jump over bg. bg path: restore R20, clear Z, write bg */

        /* Pixel 7 (bit 7): test R20 & 0x80 */
        .word   .Lconst_128, REG_R20, .Lpix7_bg
        /* fg path */
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T13, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpix7_done
.Lpix7_bg:
        .word   .Lconst_n128, REG_R20, .+4     /* restore R20 */
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
.Lpix7_done:
        .word   .Lconst_n4, REG_R21, .+4

        /* Pixel 6 (bit 6): test R20 & 0x40 */
        .word   .Lconst_64, REG_R20, .Lpix6_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T13, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpix6_done
.Lpix6_bg:
        .word   .Lconst_n64, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
.Lpix6_done:
        .word   .Lconst_n4, REG_R21, .+4

        /* Pixel 5 (bit 5): test R20 & 0x20 */
        .word   .Lconst_32, REG_R20, .Lpix5_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T13, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpix5_done
.Lpix5_bg:
        .word   .Lconst_n32, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
.Lpix5_done:
        .word   .Lconst_n4, REG_R21, .+4

        /* Pixel 4 (bit 4): test R20 & 0x10 */
        .word   .Lconst_16, REG_R20, .Lpix4_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T13, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpix4_done
.Lpix4_bg:
        .word   .Lconst_n16, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
.Lpix4_done:
        .word   .Lconst_n4, REG_R21, .+4

        /* Pixel 3 (bit 3): test R20 & 0x08 */
        .word   .Lconst_8, REG_R20, .Lpix3_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T13, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpix3_done
.Lpix3_bg:
        .word   .Lconst_n8, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
.Lpix3_done:
        .word   .Lconst_n4, REG_R21, .+4

        /* Pixel 2 (bit 2): test R20 & 0x04 */
        .word   .Lconst_4, REG_R20, .Lpix2_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T13, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpix2_done
.Lpix2_bg:
        .word   .Lconst_n4, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
.Lpix2_done:
        .word   .Lconst_n4, REG_R21, .+4

        /* Pixel 1 (bit 1): test R20 & 0x02 */
        .word   .Lconst_2, REG_R20, .Lpix1_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T13, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpix1_done
.Lpix1_bg:
        .word   .Lconst_n2, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
.Lpix1_done:
        .word   .Lconst_n4, REG_R21, .+4

        /* Pixel 0 (bit 0): test R20 & 0x01 */
        .word   .Lconst_1, REG_R20, .Lpix0_bg
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T13, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .Lpix0_done
.Lpix0_bg:
        .word   .Lconst_n1, REG_R20, .+4
        .word   REG_R21 | INDIRECT, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
.Lpix0_done:
        .word   REG_Z, REG_Z, .+4



        /* Advance font_ptr by 4 bytes */
        .word   .Lconst_n4, REG_T15, .+4

        /* Advance row pointer by fb_pitch */
        .word   REG_T12, REG_Z, .+4
        .word   REG_Z, REG_R22, .+4
        .word   REG_Z, REG_Z, .+4

        /* R23 -= 1 */
        .word   .Lconst_1, REG_R23, .+4

        .word   REG_Z, REG_Z, .Lrow_loop

.Lrow_done:
        /* Advance T8 by 32 (8 pixels * 4 bytes) for next character column */
        .word   .Lconst_n32, REG_T8, .+4

        /* Advance T9 by 2 (next u16 in screen buffer) */
        .word   .Lconst_n2, REG_T9, .+4

        /* T11 -= 1 */
        .word   .Lconst_1, REG_T11, .+4

        .word   REG_Z, REG_Z, .Lchar_loop

.Ldone:
        /* Return: Load RA from [SP] and jump to it */
        .word   REG_T4, REG_T4, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_SP | INDIRECT, REG_Z, .+4   /* Z = -[SP] = -return_addr */
        .word   REG_Z, REG_T4, .+4              /* T4 = return_addr */
        .word   REG_Z, REG_Z, REG_T4 | INDIRECT /* Jump to [T4] */

/* Constants */
.Lconst_n128:   .word   -128
.Lconst_n64:    .word   -64
.Lconst_n32:    .word   -32
.Lconst_n24:    .word   -24
.Lconst_n16:    .word   -16
.Lconst_n8:     .word   -8
.Lconst_n4:     .word   -4
.Lconst_n2:     .word   -2
.Lconst_n1:     .word   -1
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

/* Return address constants */
.Lmul_ret_const: .word  .Lmul_ret
.Llb_ret_const:  .word  .Llb_ret

.size subleq_direct_putcs, . - subleq_direct_putcs
