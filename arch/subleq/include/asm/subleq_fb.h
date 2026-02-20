/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Subleq framebuffer constants - shared between setup.c and subleqfb.c
 *
 * These must be kept in sync: setup.c reserves the memory region, and
 * subleqfb.c maps it as the display framebuffer.
 */

#ifndef _ASM_SUBLEQ_SUBLEQ_FB_H
#define _ASM_SUBLEQ_SUBLEQ_FB_H

#define SUBLEQ_FB_WIDTH       800
#define SUBLEQ_FB_HEIGHT      512
#define SUBLEQ_FB_BPP         32      /* XRGB8888: 32-bit per pixel */
#define SUBLEQ_FB_SIZE        (SUBLEQ_FB_WIDTH * SUBLEQ_FB_HEIGHT * (SUBLEQ_FB_BPP / 8))
#define SUBLEQ_FB_ADDR        (0x60000000UL - SUBLEQ_FB_SIZE)

#endif /* _ASM_SUBLEQ_SUBLEQ_FB_H */
