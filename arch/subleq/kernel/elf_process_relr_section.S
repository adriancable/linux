/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Subleq RELR (Packed Relative Relocations) processor
 *
 * Hand-optimized for Subleq OISC. Uses subtraction-based bit extraction
 * to avoid expensive shift operations.
 *
 * int elf_process_relr_section(u32 *relr_data, size_t relr_size,
 *                              unsigned long load_addr,
 *                              unsigned long base_vaddr,
 *                              unsigned long load_offset)
 *
 * Arguments:
 *   R21 = relr_data, R22 = relr_size, R23 = load_addr, R24 = base_vaddr
 *   [SP+4] = load_offset (5th arg on stack)
 *
 * Returns: 0 in R20
 */

.text
.globl elf_process_relr_section
.type elf_process_relr_section, @function

.set REG_Z, 12
.set REG_SP, 16
.set ZERO, 144
.set REG_R20, 96
.set REG_R21, 100
.set REG_R22, 104
.set REG_R23, 108
.set REG_R24, 112
.set REG_T0, 160      /* addr_adj */
.set REG_T1, 164      /* load_offset */
.set REG_T2, 168      /* bytes_remaining (counts down by 4) */
.set REG_T3, 172      /* ptr to current entry */
.set REG_T4, 176      /* base for bitmaps */
.set REG_T5, 180      /* entry value / working copy */
.set REG_T6, 184      /* original entry (preserved) */
.set REG_T7, 188      /* scratch / base_ptr */
.set REG_T8, 192      /* bit table pointer */
.set REG_T9, 196      /* patch address */
.set INDIRECT, 2

elf_process_relr_section:
        /* T0 = addr_adj = load_addr - base_vaddr */
        .word   REG_T0, REG_T0, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R23, REG_Z, .+4
        .word   REG_Z, REG_T0, .+4               /* T0 = load_addr */
        .word   REG_R24, REG_T0, .+4             /* T0 = load_addr - base_vaddr */

        /* T1 = load_offset from [SP+4] */
        .word   REG_T7, REG_T7, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_SP, REG_Z, .+4
        .word   REG_Z, REG_T7, .+4               /* T7 = SP */
        .word   .Lconst_neg4, REG_T7, .+4        /* T7 = SP + 4 */
        .word   REG_T1, REG_T1, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T7 | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_T1, .+4               /* T1 = [SP+4] = load_offset */

        /* T2 = relr_size (will count down by 4) */
        .word   REG_T2, REG_T2, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R22, REG_Z, .+4
        .word   REG_Z, REG_T2, .+4

        /* T3 = ptr = relr_data */
        .word   REG_T3, REG_T3, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_R21, REG_Z, .+4
        .word   REG_Z, REG_T3, .+4

        /* T4 = base = 0 */
        .word   REG_T4, REG_T4, .+4

/*=== MAIN LOOP ===*/
.Lloop:
        .word   ZERO, REG_T2, .Ldone             /* if bytes_remaining <= 0, exit */

        /* Load entry -> T5, save copy to T6 */
        .word   REG_T5, REG_T5, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T3 | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_T5, .+4               /* T5 = entry */
        .word   REG_T6, REG_T6, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T5, REG_Z, .+4
        .word   REG_Z, REG_T6, .+4               /* T6 = entry (saved) */

        /*
         * Extract LSB: strip all bits 31..1 from T5 using subtraction.
         * After this, T5 = entry & 1.
         */
        /* Bit 31 (sign bit): check if T5 < 0 (not just <= 0) */
        .word   ZERO, REG_T5, .Llsb_b31_check
        .word   REG_Z, REG_Z, .Llsb_b30          /* T5 > 0, skip bit 31 */
.Llsb_b31_check:
        /* T5 <= 0. Use ROBUST NEGATIVE CHECK: T5 < 0 iff (T5 <= 0) AND (T5 + 1 <= 0) */
        /* This handles INT_MIN correctly: INT_MIN + 1 = -2147483647 <= 0, so negative */
        /* Copy T5 to T7, add 1, check if still <= 0 */
        .word   REG_T7, REG_T7, .+4              /* T7 = 0 */
        .word   REG_Z, REG_Z, .+4
        .word   REG_T5, REG_Z, .+4               /* Z = -T5 */
        .word   REG_Z, REG_T7, .+4               /* T7 = T5 */
        .word   .Lconst_neg1, REG_T7, .+4        /* T7 = T5 + 1 */
        .word   ZERO, REG_T7, .Llsb_b31_set      /* if T7 <= 0, T5 < 0, bit 31 is set */
        .word   REG_Z, REG_Z, .Llsb_b30          /* T7 > 0 and T5 <= 0, so T5 == 0, skip */
.Llsb_b31_set:
        /* T5 < 0 (bit 31 is set). Subtract 0x80000000 */
        .word   .Lconst_0x80000000, REG_T5, .+4
.Llsb_b30:
        /* Check T5 >= 0x40000000: T7 = 0x40000000 - T5, if T7 <= 0 then true */
        .word   REG_T7, REG_T7, .+4              /* T7 = 0 */
        .word   .Lconst_cmp30, REG_T7, .+4       /* T7 = 0 - (-0x40000000) = 0x40000000 */
        .word   REG_T5, REG_T7, .+4              /* T7 = 0x40000000 - T5 */
        .word   ZERO, REG_T7, .Llsb_s30
        .word   REG_Z, REG_Z, .Llsb_b29
.Llsb_s30:
        .word   .Lconst_0x40000000, REG_T5, .+4
.Llsb_b29:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp29, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s29
        .word   REG_Z, REG_Z, .Llsb_b28
.Llsb_s29:
        .word   .Lconst_0x20000000, REG_T5, .+4
.Llsb_b28:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp28, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s28
        .word   REG_Z, REG_Z, .Llsb_b27
.Llsb_s28:
        .word   .Lconst_0x10000000, REG_T5, .+4
.Llsb_b27:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp27, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s27
        .word   REG_Z, REG_Z, .Llsb_b26
.Llsb_s27:
        .word   .Lconst_0x08000000, REG_T5, .+4
.Llsb_b26:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp26, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s26
        .word   REG_Z, REG_Z, .Llsb_b25
.Llsb_s26:
        .word   .Lconst_0x04000000, REG_T5, .+4
.Llsb_b25:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp25, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s25
        .word   REG_Z, REG_Z, .Llsb_b24
.Llsb_s25:
        .word   .Lconst_0x02000000, REG_T5, .+4
.Llsb_b24:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp24, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s24
        .word   REG_Z, REG_Z, .Llsb_b23
.Llsb_s24:
        .word   .Lconst_0x01000000, REG_T5, .+4
.Llsb_b23:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp23, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s23
        .word   REG_Z, REG_Z, .Llsb_b22
.Llsb_s23:
        .word   .Lconst_0x00800000, REG_T5, .+4
.Llsb_b22:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp22, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s22
        .word   REG_Z, REG_Z, .Llsb_b21
.Llsb_s22:
        .word   .Lconst_0x00400000, REG_T5, .+4
.Llsb_b21:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp21, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s21
        .word   REG_Z, REG_Z, .Llsb_b20
.Llsb_s21:
        .word   .Lconst_0x00200000, REG_T5, .+4
.Llsb_b20:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp20, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s20
        .word   REG_Z, REG_Z, .Llsb_b19
.Llsb_s20:
        .word   .Lconst_0x00100000, REG_T5, .+4
.Llsb_b19:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp19, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s19
        .word   REG_Z, REG_Z, .Llsb_b18
.Llsb_s19:
        .word   .Lconst_0x00080000, REG_T5, .+4
.Llsb_b18:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp18, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s18
        .word   REG_Z, REG_Z, .Llsb_b17
.Llsb_s18:
        .word   .Lconst_0x00040000, REG_T5, .+4
.Llsb_b17:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp17, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s17
        .word   REG_Z, REG_Z, .Llsb_b16
.Llsb_s17:
        .word   .Lconst_0x00020000, REG_T5, .+4
.Llsb_b16:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp16, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s16
        .word   REG_Z, REG_Z, .Llsb_b15
.Llsb_s16:
        .word   .Lconst_0x00010000, REG_T5, .+4
.Llsb_b15:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp15, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s15
        .word   REG_Z, REG_Z, .Llsb_b14
.Llsb_s15:
        .word   .Lconst_0x00008000, REG_T5, .+4
.Llsb_b14:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp14, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s14
        .word   REG_Z, REG_Z, .Llsb_b13
.Llsb_s14:
        .word   .Lconst_0x00004000, REG_T5, .+4
.Llsb_b13:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp13, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s13
        .word   REG_Z, REG_Z, .Llsb_b12
.Llsb_s13:
        .word   .Lconst_0x00002000, REG_T5, .+4
.Llsb_b12:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp12, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s12
        .word   REG_Z, REG_Z, .Llsb_b11
.Llsb_s12:
        .word   .Lconst_0x00001000, REG_T5, .+4
.Llsb_b11:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp11, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s11
        .word   REG_Z, REG_Z, .Llsb_b10
.Llsb_s11:
        .word   .Lconst_0x00000800, REG_T5, .+4
.Llsb_b10:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp10, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s10
        .word   REG_Z, REG_Z, .Llsb_b9
.Llsb_s10:
        .word   .Lconst_0x00000400, REG_T5, .+4
.Llsb_b9:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp9, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s9
        .word   REG_Z, REG_Z, .Llsb_b8
.Llsb_s9:
        .word   .Lconst_0x00000200, REG_T5, .+4
.Llsb_b8:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp8, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s8
        .word   REG_Z, REG_Z, .Llsb_b7
.Llsb_s8:
        .word   .Lconst_0x00000100, REG_T5, .+4
.Llsb_b7:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp7, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s7
        .word   REG_Z, REG_Z, .Llsb_b6
.Llsb_s7:
        .word   .Lconst_0x00000080, REG_T5, .+4
.Llsb_b6:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp6, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s6
        .word   REG_Z, REG_Z, .Llsb_b5
.Llsb_s6:
        .word   .Lconst_0x00000040, REG_T5, .+4
.Llsb_b5:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp5, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s5
        .word   REG_Z, REG_Z, .Llsb_b4
.Llsb_s5:
        .word   .Lconst_0x00000020, REG_T5, .+4
.Llsb_b4:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp4, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s4
        .word   REG_Z, REG_Z, .Llsb_b3
.Llsb_s4:
        .word   .Lconst_0x00000010, REG_T5, .+4
.Llsb_b3:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp3, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s3
        .word   REG_Z, REG_Z, .Llsb_b2
.Llsb_s3:
        .word   .Lconst_0x00000008, REG_T5, .+4
.Llsb_b2:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp2, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s2
        .word   REG_Z, REG_Z, .Llsb_b1
.Llsb_s2:
        .word   .Lconst_0x00000004, REG_T5, .+4
.Llsb_b1:
        .word   REG_T7, REG_T7, .+4
        .word   .Lconst_cmp1, REG_T7, .+4
        .word   REG_T5, REG_T7, .+4
        .word   ZERO, REG_T7, .Llsb_s1
        .word   REG_Z, REG_Z, .Llsb_done
.Llsb_s1:
        .word   .Lconst_0x00000002, REG_T5, .+4
.Llsb_done:
        /* T5 now contains (entry & 1). If T5 <= 0, it's an address entry */
        .word   ZERO, REG_T5, .Laddr_entry
        /* Fall through: T5 > 0, so (entry & 1) == 1, this is a bitmap entry */
        .word   REG_Z, REG_Z, .Lbitmap_entry

/*=== ADDRESS ENTRY: (entry & 1) == 0 ===*/
.Laddr_entry:
        /* T6 = original entry. Compute patch_addr = addr_adj + entry */
        /* T9 = T0 + T6 = addr_adj + entry */
        .word   REG_T9, REG_T9, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T0, REG_Z, .+4
        .word   REG_Z, REG_T9, .+4               /* T9 = addr_adj */
        .word   REG_Z, REG_Z, .+4
        .word   REG_T6, REG_Z, .+4
        .word   REG_Z, REG_T9, .+4               /* T9 = addr_adj + entry = patch_addr */

        /* *patch_addr += load_offset: [T9] -= -load_offset */
        /* T1 already contains load_offset, negate it to -load_offset */
        .word   REG_Z, REG_Z, .+4
        .word   REG_T1, REG_Z, .+4               /* Z = -load_offset */
        .word   REG_Z, REG_T9 | INDIRECT, .+4    /* [patch_addr] += load_offset */

        /* base = entry + 4 */
        .word   REG_T4, REG_T4, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T6, REG_Z, .+4
        .word   REG_Z, REG_T4, .+4               /* T4 = entry */
        .word   .Lconst_neg4, REG_T4, .+4        /* T4 = entry + 4 = base */
        .word   REG_Z, REG_Z, .Lloop_next

/*=== BITMAP ENTRY: (entry & 1) == 1 ===*/
.Lbitmap_entry:
        /* Use T6 (original entry) as working word. base_ptr = addr_adj + base (T0 + T4) */
        /* T7 = base_ptr = T0 + T4 */
        .word   REG_T7, REG_T7, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T0, REG_Z, .+4
        .word   REG_Z, REG_T7, .+4               /* T7 = addr_adj */
        .word   REG_Z, REG_Z, .+4
        .word   REG_T4, REG_Z, .+4
        .word   REG_Z, REG_T7, .+4               /* T7 = addr_adj + base = base_ptr */

        /* T5 = T6 = word (will be modified during bit extraction) */
        /* T6 already has entry, copy to T5 for modification */
        .word   REG_T5, REG_T5, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T6, REG_Z, .+4
        .word   REG_Z, REG_T5, .+4               /* T5 = word = entry */

        /*
         * TABLE-DRIVEN BITMAP LOOP
         * T8 = table pointer (iterates through 31 entries)
         * Each table entry has: [bit_value, patch_offset]
         * Loop until T8 reaches end of table
         */
        .word   REG_T8, REG_T8, .+4
        .word   REG_Z, REG_Z, .+4
        .word   .Lbit_table_addr, REG_Z, .+4
        .word   REG_Z, REG_T8, .+4               /* T8 = &bit_table */

.Lbmp_loop:
        /* Load bit_value = *T8 into T9 */
        .word   REG_T9, REG_T9, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T8 | INDIRECT, REG_Z, .+4
        .word   REG_Z, REG_T9, .+4               /* T9 = bit_value */

        /* Check if bit_value == 0 (end marker) using ROBUST ZERO CHECK */
        /* T9 == 0 iff (T9 <= 0) AND (T9 + 1 > 0) */
        /* This handles INT_MIN correctly: INT_MIN + 1 = -2147483647 <= 0, not zero */
        .word   ZERO, REG_T9, .Lbmp_end_check
        .word   REG_Z, REG_Z, .Lbmp_check_bit    /* T9 > 0, not zero, continue */
.Lbmp_end_check:
        /* T9 <= 0. Could be 0 or negative (including 0x80000000) */
        /* Copy T9 to T6 for test, then add 1 */
        .word   REG_T6, REG_T6, .+4              /* T6 = 0 */
        .word   REG_Z, REG_Z, .+4
        .word   REG_T9, REG_Z, .+4               /* Z = -T9 */
        .word   REG_Z, REG_T6, .+4               /* T6 = T9 */
        .word   .Lconst_neg1, REG_T6, .+4        /* T6 = T9 + 1 */
        .word   ZERO, REG_T6, .Lbmp_check_bit    /* if T6 <= 0, T9 < 0, continue processing */
        .word   REG_Z, REG_Z, .Lbmp_done         /* T6 > 0 and T9 <= 0, so T9 == 0, end */

.Lbmp_check_bit:
        /* For bit 31 (0x80000000), check sign. For others, check >= comparison */
        /* Check if T9 is negative (bit 31 value = 0x80000000) */
        .word   ZERO, REG_T9, .Lbmp_sign_check
        .word   REG_Z, REG_Z, .Lbmp_ge_check
.Lbmp_sign_check:
        /* T9 < 0 means this is the 0x80000000 entry. Check if T5 < 0 (not just <= 0) */
        .word   ZERO, REG_T5, .Lbmp_sign_disambig
        .word   REG_Z, REG_Z, .Lbmp_next         /* T5 > 0, bit 31 not set */
.Lbmp_sign_disambig:
        /* T5 <= 0. Use ROBUST NEGATIVE CHECK: T5 < 0 iff (T5 <= 0) AND (T5 + 1 <= 0) */
        /* This handles INT_MIN correctly: INT_MIN + 1 = -2147483647 <= 0, so negative */
        .word   REG_T6, REG_T6, .+4              /* T6 = 0 */
        .word   REG_Z, REG_Z, .+4
        .word   REG_T5, REG_Z, .+4               /* Z = -T5 */
        .word   REG_Z, REG_T6, .+4               /* T6 = T5 */
        .word   .Lconst_neg1, REG_T6, .+4        /* T6 = T5 + 1 */
        .word   ZERO, REG_T6, .Lbmp_bit_set      /* if T6 <= 0, T5 < 0, bit 31 is set */
        .word   REG_Z, REG_Z, .Lbmp_next         /* T6 > 0 and T5 <= 0, so T5 == 0, skip */

.Lbmp_ge_check:
        /* Check if T5 >= T9 (bit_value): compute bit_value - T5, if <= 0 then T5 >= bit_value */
        .word   REG_T6, REG_T6, .+4              /* T6 = 0 */
        .word   REG_Z, REG_Z, .+4
        .word   REG_T9, REG_Z, .+4               /* Z = -bit_value */
        .word   REG_Z, REG_T6, .+4               /* T6 = 0 - (-bit_value) = bit_value */
        .word   REG_T5, REG_T6, .+4              /* T6 = bit_value - T5 */
        .word   ZERO, REG_T6, .Lbmp_bit_set      /* if T6 <= 0, T5 >= bit_value */
        .word   REG_Z, REG_Z, .Lbmp_next         /* else skip */

.Lbmp_bit_set:
        /* Bit is set! Subtract bit_value from T5 */
        .word   REG_T9, REG_T5, .+4              /* T5 -= bit_value */

        /* Load patch_offset = *(T8 + 4) */
        /* First, copy T8 to T6 */
        .word   REG_T6, REG_T6, .+4              /* T6 = 0 */
        .word   REG_Z, REG_Z, .+4
        .word   REG_T8, REG_Z, .+4               /* Z = -T8 */
        .word   REG_Z, REG_T6, .+4               /* T6 = T8 */
        .word   .Lconst_neg4, REG_T6, .+4        /* T6 = T8 + 4 (address of patch_offset) */
        /* Now dereference T6 to get patch_offset */
        .word   REG_Z, REG_Z, .+4
        .word   REG_T6 | INDIRECT, REG_Z, .+4    /* Z = -[T6] = -patch_offset */
        .word   REG_T6, REG_T6, .+4              /* T6 = 0 (clear before loading) */
        .word   REG_Z, REG_T6, .+4               /* T6 = 0 - Z = patch_offset */

        /* Compute patch_addr = base_ptr + patch_offset = T7 + T6 */
        /* Reuse T9 for patch_addr */
        .word   REG_T9, REG_T9, .+4
        .word   REG_Z, REG_Z, .+4
        .word   REG_T7, REG_Z, .+4
        .word   REG_Z, REG_T9, .+4               /* T9 = base_ptr */
        .word   REG_Z, REG_Z, .+4
        .word   REG_T6, REG_Z, .+4
        .word   REG_Z, REG_T9, .+4               /* T9 = base_ptr + offset = patch_addr */

        /* Apply relocation: [patch_addr] += load_offset */
        .word   REG_Z, REG_Z, .+4
        .word   REG_T1, REG_Z, .+4               /* Z = -load_offset */
        .word   REG_Z, REG_T9 | INDIRECT, .+4   /* [patch_addr] += load_offset */

.Lbmp_next:
        /* Advance table pointer by 8 (two words per entry) */
        .word   .Lconst_neg8, REG_T8, .+4        /* T8 += 8 */
        .word   REG_Z, REG_Z, .Lbmp_loop

.Lbmp_done:
        /* Advance base by 124 */
        .word   .Lconst_neg124, REG_T4, .+4      /* T4 = base + 124 */
        /* Fall through to loop_next */

/*=== LOOP CONTINUATION ===*/
.Lloop_next:
        /* Advance ptr by 4, decrement bytes_remaining by 4 */
        .word   .Lconst_neg4, REG_T3, .+4        /* ptr += 4 */
        .word   .Lconst_4, REG_T2, .+4           /* bytes_remaining -= 4 */
        .word   REG_Z, REG_Z, .Lloop

/*=== EPILOGUE ===*/
.Ldone:
        /* Return 0 in R20 */
        .word   REG_R20, REG_R20, .+4            /* R20 = 0 */
        
        /* Pop return address from stack and jump */
        /* Step 1: Load [SP] into T7 */
        .word   REG_T7, REG_T7, .+4              /* T7 = 0 */
        .word   REG_Z, REG_Z, .+4
        .word   REG_SP | INDIRECT, REG_Z, .+4   /* Z = -[SP] = -return_addr */
        .word   REG_Z, REG_T7, .+4               /* T7 = return_addr */
        
        /* Step 2: Increment SP by 4 (pop) */
        .word   .Lconst_neg4, REG_SP, .+4        /* SP += 4 */
        
        /* Step 3: Jump to return address via indirect */
        .word   REG_Z, REG_Z, .+4
        .word   REG_Z, REG_Z, REG_T7 | INDIRECT  /* jump to [T7] = return_addr */

.size elf_process_relr_section, .-elf_process_relr_section

/*===========================================================================
 * CONSTANTS
 *===========================================================================*/

/* Basic arithmetic constants */
.Lconst_4:
        .word   4

.Lconst_neg4:
        .word   -4
.Lconst_neg8:
        .word   -8
.Lconst_neg1:
        .word   -1
.Lconst_neg120:
        .word   -120
.Lconst_neg124:
        .word   -124

/* Power-of-2 constants for bit extraction (subtraction operands) */
.Lconst_0x80000000:
        .word   0x80000000
.Lconst_0x40000000:
        .word   0x40000000
.Lconst_0x20000000:
        .word   0x20000000
.Lconst_0x10000000:
        .word   0x10000000
.Lconst_0x08000000:
        .word   0x08000000
.Lconst_0x04000000:
        .word   0x04000000
.Lconst_0x02000000:
        .word   0x02000000
.Lconst_0x01000000:
        .word   0x01000000
.Lconst_0x00800000:
        .word   0x00800000
.Lconst_0x00400000:
        .word   0x00400000
.Lconst_0x00200000:
        .word   0x00200000
.Lconst_0x00100000:
        .word   0x00100000
.Lconst_0x00080000:
        .word   0x00080000
.Lconst_0x00040000:
        .word   0x00040000
.Lconst_0x00020000:
        .word   0x00020000
.Lconst_0x00010000:
        .word   0x00010000
.Lconst_0x00008000:
        .word   0x00008000
.Lconst_0x00004000:
        .word   0x00004000
.Lconst_0x00002000:
        .word   0x00002000
.Lconst_0x00001000:
        .word   0x00001000
.Lconst_0x00000800:
        .word   0x00000800
.Lconst_0x00000400:
        .word   0x00000400
.Lconst_0x00000200:
        .word   0x00000200
.Lconst_0x00000100:
        .word   0x00000100
.Lconst_0x00000080:
        .word   0x00000080
.Lconst_0x00000040:
        .word   0x00000040
.Lconst_0x00000020:
        .word   0x00000020
.Lconst_0x00000010:
        .word   0x00000010
.Lconst_0x00000008:
        .word   0x00000008
.Lconst_0x00000004:
        .word   0x00000004
.Lconst_0x00000002:
        .word   0x00000002

/* Comparison constants for LSB extraction (negated for "load constant" pattern) */
/* Pattern: .Lconst_cmpN stores -value, loading via subleq gives +value in target */
.Lconst_cmp30:
        .word   -0x40000000
.Lconst_cmp29:
        .word   -0x20000000
.Lconst_cmp28:
        .word   -0x10000000
.Lconst_cmp27:
        .word   -0x08000000
.Lconst_cmp26:
        .word   -0x04000000
.Lconst_cmp25:
        .word   -0x02000000
.Lconst_cmp24:
        .word   -0x01000000
.Lconst_cmp23:
        .word   -0x00800000
.Lconst_cmp22:
        .word   -0x00400000
.Lconst_cmp21:
        .word   -0x00200000
.Lconst_cmp20:
        .word   -0x00100000
.Lconst_cmp19:
        .word   -0x00080000
.Lconst_cmp18:
        .word   -0x00040000
.Lconst_cmp17:
        .word   -0x00020000
.Lconst_cmp16:
        .word   -0x00010000
.Lconst_cmp15:
        .word   -0x00008000
.Lconst_cmp14:
        .word   -0x00004000
.Lconst_cmp13:
        .word   -0x00002000
.Lconst_cmp12:
        .word   -0x00001000
.Lconst_cmp11:
        .word   -0x00000800
.Lconst_cmp10:
        .word   -0x00000400
.Lconst_cmp9:
        .word   -0x00000200
.Lconst_cmp8:
        .word   -0x00000100
.Lconst_cmp7:
        .word   -0x00000080
.Lconst_cmp6:
        .word   -0x00000040
.Lconst_cmp5:
        .word   -0x00000020
.Lconst_cmp4:
        .word   -0x00000010
.Lconst_cmp3:
        .word   -0x00000008
.Lconst_cmp2:
        .word   -0x00000004
.Lconst_cmp1:
        .word   -0x00000002

/* Pointer to bit table (address stored directly, load pattern negates it) */
.Lbit_table_addr:
        .word   .Lbit_table

/*===========================================================================
 * BIT TABLE: [bit_value, patch_offset] pairs for bitmap processing
 * Bit 31 -> offset 120 (base_ptr[30]), bit 30 -> offset 116, ..., bit 1 -> offset 0
 * Terminated by [0, 0]
 *===========================================================================*/
.Lbit_table:
        .word   0x80000000, 120         /* bit 31 -> base_ptr[30] */
        .word   0x40000000, 116         /* bit 30 -> base_ptr[29] */
        .word   0x20000000, 112         /* bit 29 -> base_ptr[28] */
        .word   0x10000000, 108         /* bit 28 -> base_ptr[27] */
        .word   0x08000000, 104         /* bit 27 -> base_ptr[26] */
        .word   0x04000000, 100         /* bit 26 -> base_ptr[25] */
        .word   0x02000000, 96          /* bit 25 -> base_ptr[24] */
        .word   0x01000000, 92          /* bit 24 -> base_ptr[23] */
        .word   0x00800000, 88          /* bit 23 -> base_ptr[22] */
        .word   0x00400000, 84          /* bit 22 -> base_ptr[21] */
        .word   0x00200000, 80          /* bit 21 -> base_ptr[20] */
        .word   0x00100000, 76          /* bit 20 -> base_ptr[19] */
        .word   0x00080000, 72          /* bit 19 -> base_ptr[18] */
        .word   0x00040000, 68          /* bit 18 -> base_ptr[17] */
        .word   0x00020000, 64          /* bit 17 -> base_ptr[16] */
        .word   0x00010000, 60          /* bit 16 -> base_ptr[15] */
        .word   0x00008000, 56          /* bit 15 -> base_ptr[14] */
        .word   0x00004000, 52          /* bit 14 -> base_ptr[13] */
        .word   0x00002000, 48          /* bit 13 -> base_ptr[12] */
        .word   0x00001000, 44          /* bit 12 -> base_ptr[11] */
        .word   0x00000800, 40          /* bit 11 -> base_ptr[10] */
        .word   0x00000400, 36          /* bit 10 -> base_ptr[9] */
        .word   0x00000200, 32          /* bit 9 -> base_ptr[8] */
        .word   0x00000100, 28          /* bit 8 -> base_ptr[7] */
        .word   0x00000080, 24          /* bit 7 -> base_ptr[6] */
        .word   0x00000040, 20          /* bit 6 -> base_ptr[5] */
        .word   0x00000020, 16          /* bit 5 -> base_ptr[4] */
        .word   0x00000010, 12          /* bit 4 -> base_ptr[3] */
        .word   0x00000008, 8           /* bit 3 -> base_ptr[2] */
        .word   0x00000004, 4           /* bit 2 -> base_ptr[1] */
        .word   0x00000002, 0           /* bit 1 -> base_ptr[0] */
        .word   0, 0                    /* end marker */

