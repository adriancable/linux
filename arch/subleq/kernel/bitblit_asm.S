/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Subleq optimized font copy for 8px × 16px fonts
 *
 * void bitblit_copy_font8x16(u8 *dst, const u16 *s, const u8 *font,
 *                            u32 cnt, u32 d_pitch, u32 s_pitch);
 *
 * From docs/architecture.md:
 *   T0-T15 (bytes 160-220): Compiler temporaries
 *
 * __subleq_lb uses: T0, T1, T3, T5, T6, T7
 * __subleq_sb uses: T0, T1, T2, T3, T4, T5, T6
 * Safe to use: T8, T9, T10, T11, T12, T13, T14, T15
 *
 * Screen buffer (s) contains u16 values: (attr << 8) | char
 * We only need the low byte (char). Use __subleq_lb to read it
 * correctly regardless of alignment.
 *
 * Stack frame after allocation (8 bytes):
 *   [SP+0] = saved RA
 *   [SP+4] = cur_dst during inner loop
 *   [SP+8] = caller's RA (before copy)
 *   [SP+12] = d_pitch
 *   [SP+16] = s_pitch
 */

.text
.globl bitblit_copy_font8x16
.type bitblit_copy_font8x16, @function

.set REG_Z, 12
.set REG_SP, 16
.set REG_R20, 96
.set REG_R21, 100
.set REG_R22, 104
.set REG_R23, 108
.set REG_R24, 112
.set REG_T8, 192
.set REG_T9, 196
.set REG_T10, 200
.set REG_T11, 204
.set REG_T12, 208
.set REG_T13, 212
.set REG_T14, 216
.set REG_T15, 220
.set INDIRECT, 2

bitblit_copy_font8x16:
        /* Allocate 8 bytes: SP -= 8 */
        .word   .Lconst_8, REG_SP, .+4

        /* Save RA from [SP+8] to [SP+0] */
        .word   REG_T8, REG_T8, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_SP, REG_Z, .+4
        .word   .Lconst_8, REG_Z, .+4
        .word   REG_Z, REG_T8, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T8 | INDIRECT, REG_Z, .+4
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4
        .word   REG_Z, REG_SP | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        /* T8 = dst (R21) */
        .word   REG_T8, REG_T8, .+4
        .word   REG_R21, REG_Z, .+4
        .word   REG_Z, REG_T8, .+4
        .word   REG_Z, REG_Z, .+4

        /* T9 = s (R22) */
        .word   REG_T9, REG_T9, .+4
        .word   REG_R22, REG_Z, .+4
        .word   REG_Z, REG_T9, .+4
        .word   REG_Z, REG_Z, .+4

        /* T10 = font (R23) */
        .word   REG_T10, REG_T10, .+4
        .word   REG_R23, REG_Z, .+4
        .word   REG_Z, REG_T10, .+4
        .word   REG_Z, REG_Z, .+4

        /* T11 = cnt (R24) */
        .word   REG_T11, REG_T11, .+4
        .word   REG_R24, REG_Z, .+4
        .word   REG_Z, REG_T11, .+4
        .word   REG_Z, REG_Z, .+4

        /* T12 = d_pitch from [SP+12] (5th arg: RA at +8, then +4 for d_pitch) */
        .word   REG_T12, REG_T12, .+4
        .word   REG_T15, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_SP, REG_Z, .+4
        .word   .Lconst_12, REG_Z, .+4
        .word   REG_Z, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T15 | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_T12, .+4
        .word   REG_Z, REG_Z, .+4

        /* T13 = s_pitch from [SP+16] (6th arg: RA at +8, d_pitch at +12, s_pitch at +16) */
        .word   REG_T13, REG_T13, .+4
        .word   REG_T15, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_SP, REG_Z, .+4
        .word   .Lconst_16, REG_Z, .+4
        .word   REG_Z, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T15 | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_T13, .+4
        .word   REG_Z, REG_Z, .+4

        /*
         * CHECK d_pitch == 1 for fast path
         * If T12 == 1, branch to memmove fast loop
         * subleq(1, T12, target) does T12 = T12 - 1, branch if <= 0
         * So if T12 == 1, result = 0, branch taken
         */
        .word   .Lconst_1, REG_T12, .Lfast_path

        /* Restore T12: T12 was decremented, add 1 back */
        .word   .Lconst_n1, REG_T12, .+4

/*=== STRIDED PATH (d_pitch > 1) ===*/
/*=== MAIN CHARACTER LOOP ===*/
.Lchar_loop:
        /* if T11 (cnt) <= 0, done */
        /* subleq(Z, T11, target) does T11 = T11 - 0 = T11, branch if T11 <= 0 */
        .word   REG_Z, REG_T11, .Ldone

        /*
         * Read character code using __subleq_lb from address T9.
         * This handles alignment correctly - reads just the low byte
         * of the u16, which is the character code.
         */
        .word   REG_R21, REG_R21, .+4
        .word   REG_T9, REG_Z, .+4
        .word   REG_Z, REG_R21, .+4
        .word   REG_Z, REG_Z, .+4

        /* Push and call __subleq_lb to get char code */
        .word   .Lconst_4, REG_SP, .+4
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   .Lchar_lb_ret_const, REG_Z, .+4
        .word   REG_Z, REG_SP | INDIRECT, .+4
        .word   REG_Z, REG_Z, __subleq_lb

.Lchar_lb_ret:
        /* R20 = character code (0-255). Compute font offset = R20 * 64 */
        /* (expanded font: 4 bytes per row, 16 rows = 64 bytes per char) */
        .word   REG_T14, REG_T14, .+4
        .word   REG_R20, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4

        /* T14 = ch * 64 via 6 doublings */
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4

        /* T14 += T10 (font base) => T14 = font + ch*64 */
        .word   REG_T10, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4

        /* Save cur_dst = T8 to [SP+4] */
        .word   REG_T15, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_SP, REG_Z, .+4
        .word   .Lconst_4, REG_Z, .+4
        .word   REG_Z, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T15 | INDIRECT, REG_T15 | INDIRECT, .+4
        .word   REG_T8, REG_Z, .+4
        .word   REG_Z, REG_T15 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        /* T15 = 16 (row counter) */
        .word   REG_T15, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4
        .word   .Lconst_16, REG_Z, .+4
        .word   REG_Z, REG_T15, .+4
        .word   REG_Z, REG_Z, .+4

/*=== BYTE COPY LOOP (16 rows) ===*/
.Lbyte_loop:
        /* if T15 (row counter) <= 0, done */
        /* subleq(Z, T15, target) does T15 = T15 - 0 = T15, branch if T15 <= 0 */
        .word   REG_Z, REG_T15, .Lbyte_done

        /*
         * OPTIMIZED: Direct word read from expanded font (no lb call!)
         * Font byte is at [T14] as a u32 (only low byte matters)
         * R20 = [T14]
         */
        .word   REG_R20, REG_R20, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14 | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_R20, .+4
        .word   REG_Z, REG_Z, .+4

        /* Load cur_dst from [SP+4] to R21 for sb */
        .word   REG_R22, REG_R22, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_SP, REG_Z, .+4
        .word   .Lconst_4, REG_Z, .+4
        .word   REG_Z, REG_R22, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R21, REG_R21, .+4
        .word   REG_R22 | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_R21, .+4
        .word   REG_Z, REG_Z, .+4

        /* R22 = R20 (byte from word read) */
        .word   REG_R22, REG_R22, .+4
        .word   REG_R20, REG_Z, .+4
        .word   REG_Z, REG_R22, .+4
        .word   REG_Z, REG_Z, .+4

        /* Push and call __subleq_sb */
        .word   .Lconst_4, REG_SP, .+4
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   .Lsb_ret_const, REG_Z, .+4
        .word   REG_Z, REG_SP | INDIRECT, .+4
        .word   REG_Z, REG_Z, __subleq_sb

.Lsb_ret:
        /* T14 += 4 (next font word - expanded font has 4 bytes per row) */
        .word   .Lconst_n4, REG_T14, .+4

        /* [SP+4] += T12 (cur_dst += d_pitch) */
        .word   REG_R21, REG_R21, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_SP, REG_Z, .+4
        .word   .Lconst_4, REG_Z, .+4
        .word   REG_Z, REG_R21, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T12, REG_Z, .+4
        .word   REG_Z, REG_R21 | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4

        /* T15 -= 1 */
        .word   .Lconst_1, REG_T15, .+4

        .word   REG_Z, REG_Z, .Lbyte_loop

.Lbyte_done:
        /* T8 += T13 (dst_base += s_pitch for next column) */
        .word   REG_Z, REG_Z, .+4
        .word   REG_T13, REG_Z, .+4
        .word   REG_Z, REG_T8, .+4
        .word   REG_Z, REG_Z, .+4

        /* T9 += 2 (next u16 in screen buffer) */
        .word   .Lconst_n2, REG_T9, .+4

        /* T11 -= 1 */
        .word   .Lconst_1, REG_T11, .+4

        .word   REG_Z, REG_Z, .Lchar_loop

/*===========================================================================
 * FAST PATH: d_pitch == 1 (contiguous copy)
 * Use memmove(dst, font_ptr, 16) per character - much faster than 16 lb/sb!
 *
 * State at entry (d_pitch was consumed by check, but we don't need it):
 *   T8 = dst, T9 = s, T10 = font, T11 = cnt, T13 = s_pitch
 *===========================================================================*/
.Lfast_path:
        /* Restore T12 = 1 (it was decremented to 0 by the check) */
        .word   .Lconst_n1, REG_T12, .+4

.Lfast_loop:
        /* if T11 (cnt) <= 0, done */
        .word   REG_Z, REG_T11, .Ldone

        /*
         * Read character code using __subleq_lb from address T9.
         */
        .word   REG_R21, REG_R21, .+4
        .word   REG_T9, REG_Z, .+4
        .word   REG_Z, REG_R21, .+4
        .word   REG_Z, REG_Z, .+4

        /* Push and call __subleq_lb to get char code */
        .word   .Lconst_4, REG_SP, .+4
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   .Lfast_lb_ret_const, REG_Z, .+4
        .word   REG_Z, REG_SP | INDIRECT, .+4
        .word   REG_Z, REG_Z, __subleq_lb

.Lfast_lb_ret:
        /* R20 = character code (0-255). Compute font offset = R20 * 16 */
        .word   REG_T14, REG_T14, .+4
        .word   REG_R20, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4

        /* T14 = ch * 16 via 4 doublings */
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4

        /* T14 += T10 (font base) => T14 = font + ch*16 */
        .word   REG_T10, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4

        /*
         * Call memmove(dst=T8, src=T14, len=16)
         * memmove args: R21=dst, R22=src, R23=len
         */
        .word   REG_R21, REG_R21, .+4
        .word   REG_T8, REG_Z, .+4
        .word   REG_Z, REG_R21, .+4
        .word   REG_Z, REG_Z, .+4

        .word   REG_R22, REG_R22, .+4
        .word   REG_T14, REG_Z, .+4
        .word   REG_Z, REG_R22, .+4
        .word   REG_Z, REG_Z, .+4

        .word   REG_R23, REG_R23, .+4
        .word   REG_Z, REG_Z, .+4
        .word   .Lconst_16, REG_Z, .+4
        .word   REG_Z, REG_R23, .+4
        .word   REG_Z, REG_Z, .+4

        /* Push and call memmove */
        .word   .Lconst_4, REG_SP, .+4
        .word   REG_SP | INDIRECT, REG_SP | INDIRECT, .+4
        .word   REG_Z, REG_Z, .+4
        .word   .Lfast_memmove_ret_const, REG_Z, .+4
        .word   REG_Z, REG_SP | INDIRECT, .+4
        .word   REG_Z, REG_Z, memmove

.Lfast_memmove_ret:
        /* T8 += 16 (dst advances by 16 since d_pitch == 1) */
        .word   .Lconst_n16, REG_T8, .+4

        /* T9 += 2 (next u16 in screen buffer) */
        .word   .Lconst_n2, REG_T9, .+4

        /* T11 -= 1 */
        .word   .Lconst_1, REG_T11, .+4

        .word   REG_Z, REG_Z, .Lfast_loop

.Ldone:
        /* Load RA from [SP+0] */
        .word   REG_T14, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_SP | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_T14, .+4
        .word   REG_Z, REG_Z, .+4

        /* Deallocate stack: SP += 8 */
        .word   .Lconst_n8, REG_SP, .+4

        /* Return */
        .word   REG_Z, REG_Z, REG_T14 | INDIRECT

/* Constants */
.Lconst_n1:     .word   -1
.Lconst_n2:     .word   -2
.Lconst_n4:     .word   -4
.Lconst_n8:     .word   -8
.Lconst_n16:    .word   -16
.Lconst_1:      .word   1
.Lconst_4:      .word   4
.Lconst_8:      .word   8
.Lconst_12:     .word   12
.Lconst_16:     .word   16

/* Return address constants */
.Lchar_lb_ret_const:      .word   .Lchar_lb_ret
.Lsb_ret_const:           .word   .Lsb_ret
.Lfast_lb_ret_const:      .word   .Lfast_lb_ret
.Lfast_memmove_ret_const: .word   .Lfast_memmove_ret

.size bitblit_copy_font8x16, . - bitblit_copy_font8x16
