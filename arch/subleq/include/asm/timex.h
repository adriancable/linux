/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Timer/timex for Subleq
 */

#ifndef _ASM_SUBLEQ_TIMEX_H
#define _ASM_SUBLEQ_TIMEX_H

/* Timer tick frequency - arbitrary since Subleq doesn't have a real timer */
#define CLOCK_TICK_RATE 1000000

typedef unsigned long cycles_t;

static inline cycles_t get_cycles(void)
{
	/* No hardware cycle counter - return 0 */
	return 0;
}

#define random_get_entropy() get_cycles()

#endif /* _ASM_SUBLEQ_TIMEX_H */
