/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Subleq register and architecture constants for assembly code
 *
 * Shared definitions used by all .S files. Include with:
 *   #include <asm/subleq-regs.h>
 */

#ifndef _ASM_SUBLEQ_REGS_H
#define _ASM_SUBLEQ_REGS_H

/* Interrupt control addresses */
.set INT_HANDLER, 0
.set INT_SAVED_PC, 4
.set INT_SAVED_HANDLER, 8

/* Core registers */
.set REG_Z, 12
.set REG_SP, 16
.set REG_RA, 20

/* General purpose registers R3-R31 */
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

/* Read-only zero constant */
.set ZERO, 144

/* Frame pointer */
.set REG_FP, 148

/* Temporary registers T0-T15 */
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

/* Indirect addressing flag (OR'd with register address) */
.set INDIRECT, 1

/* Thread size = PAGE_SIZE (must match asm/page.h PAGE_SHIFT=14 -> 16KB) */
.set THREAD_SIZE, 16384

#endif /* _ASM_SUBLEQ_REGS_H */
