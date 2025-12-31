/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Delay functions for Subleq
 */

#ifndef _ASM_SUBLEQ_DELAY_H
#define _ASM_SUBLEQ_DELAY_H

#include <linux/param.h>

extern void __delay(unsigned long loops);
extern void __udelay(unsigned long usecs);
extern void __ndelay(unsigned long nsecs);

#define udelay(n) __udelay(n)
#define ndelay(n) __ndelay(n)

#endif /* _ASM_SUBLEQ_DELAY_H */
