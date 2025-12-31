/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Interrupt enable/disable for Subleq
 *
 * Subleq interrupts are controlled by memory location 0 (INT_HANDLER):
 * - m[0] = 0 means interrupts disabled
 * - m[0] = handler_address means interrupts enabled
 * - m[2] holds the saved handler address when disabled
 */

#ifndef _ASM_SUBLEQ_IRQFLAGS_H
#define _ASM_SUBLEQ_IRQFLAGS_H

#include <linux/types.h>

/* Memory-mapped interrupt control registers */
#define SUBLEQ_INT_HANDLER ((volatile unsigned long *)0)
#define SUBLEQ_INT_SAVED_PC ((volatile unsigned long *)4)
#define SUBLEQ_INT_SAVED_HANDLER ((volatile unsigned long *)8)

#ifndef __ASSEMBLY__

/* Get current interrupt state (0 = disabled, nonzero = enabled) */
static inline unsigned long arch_local_save_flags(void)
{
	return *SUBLEQ_INT_HANDLER;
}

/* Disable interrupts */
static inline void arch_local_irq_disable(void)
{
	unsigned long handler = *SUBLEQ_INT_HANDLER;
	if (handler) {
		*SUBLEQ_INT_SAVED_HANDLER = handler;
		*SUBLEQ_INT_HANDLER = 0;
	}
}

/* Enable interrupts */
static inline void arch_local_irq_enable(void)
{
	if (*SUBLEQ_INT_HANDLER == 0) {
		*SUBLEQ_INT_HANDLER = *SUBLEQ_INT_SAVED_HANDLER;
	}
}

/* Save flags and disable interrupts */
static inline unsigned long arch_local_irq_save(void)
{
	unsigned long flags = *SUBLEQ_INT_HANDLER;
	arch_local_irq_disable();
	return flags;
}

/* Restore saved interrupt flags */
static inline void arch_local_irq_restore(unsigned long flags)
{
	if (flags) {
		/* Re-enable with the saved handler */
		*SUBLEQ_INT_HANDLER = flags;
	} else {
		/* Leave disabled */
		*SUBLEQ_INT_HANDLER = 0;
	}
}

/* Check if interrupts are disabled */
static inline bool arch_irqs_disabled_flags(unsigned long flags)
{
	return flags == 0;
}

static inline bool arch_irqs_disabled(void)
{
	return arch_irqs_disabled_flags(arch_local_save_flags());
}

#endif /* !__ASSEMBLY__ */

#endif /* _ASM_SUBLEQ_IRQFLAGS_H */
