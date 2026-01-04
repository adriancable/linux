/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Timer/timex for Subleq
 */

#ifndef _ASM_SUBLEQ_TIMEX_H
#define _ASM_SUBLEQ_TIMEX_H

/* Timer tick frequency - arbitrary since Subleq doesn't have a real timer */
#define CLOCK_TICK_RATE 1000000

typedef unsigned long cycles_t;

/*
 * Subleq has no hardware cycle counter. We use jiffies as a fallback
 * entropy source. This isn't cryptographically strong, but it:
 * 1. Prevents the "Missing cycle counter" RNG warning
 * 2. Provides some timestamp variation for timer calculations
 * 3. Avoids timer wheel inconsistencies from zero timestamps
 *
 * For better entropy, the VM could expose its instruction counter
 * at a memory-mapped address.
 */
static inline cycles_t get_cycles(void)
{
	extern unsigned long volatile jiffies;
	return jiffies;
}

#define random_get_entropy() get_cycles()

#endif /* _ASM_SUBLEQ_TIMEX_H */
