/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Interrupt enable/disable for Subleq
 *
 * Subleq interrupts are controlled by memory location 0 (INT_HANDLER):
 * - m[0] = 0 means interrupts disabled
 * - m[0] = handler_address means interrupts enabled
 * - m[2] holds the saved handler address when disabled
 *
 * IMPORTANT: arch_local_irq_enable() must NOT re-enable hardware interrupts
 * when called from inside an interrupt handler. The kernel's generic code
 * (e.g., spin_unlock_irq, local_irq_enable) may be called during interrupt
 * processing, and we must not allow nested interrupts which would corrupt
 * the saved state in the interrupt entry code.
 *
 * This follows the same pattern as m68k (see arch/m68k/include/asm/irqflags.h)
 * which guards arch_local_irq_enable() with !hardirq_count().
 *
 * NOTE: We cannot include <linux/preempt.h> here because it creates a circular
 * dependency: irqflags.h <- cmpxchg.h <- atomic.h <- bitops.h <- ... <- preempt.h
 * So we access the preempt_count directly from thread_info at the stack base.
 */

#ifndef _ASM_SUBLEQ_IRQFLAGS_H
#define _ASM_SUBLEQ_IRQFLAGS_H

#include <linux/types.h>

/* Memory-mapped interrupt control registers */
#define SUBLEQ_INT_HANDLER ((volatile unsigned long *)0)
#define SUBLEQ_INT_SAVED_PC ((volatile unsigned long *)4)
#define SUBLEQ_INT_SAVED_HANDLER ((volatile unsigned long *)8)

#ifndef __ASSEMBLY__

extern void __subleq_putchar(int c);

/*
 * Get hardirq count directly from thread_info without including preempt.h
 * This avoids a circular include dependency.
 *
 * The thread_info is at the bottom of the kernel stack. We read SP from
 * memory location 16 and mask off the stack offset. The preempt_count
 * is at offset 4 (after the flags field) in struct thread_info.
 *
 * hardirq_count() = preempt_count & HARDIRQ_MASK
 * where HARDIRQ_MASK = 0x000f0000 (bits 16-19)
 */
#define SUBLEQ_THREAD_SIZE 4096 /* PAGE_SIZE - must match asm/page.h */
#define SUBLEQ_HARDIRQ_MASK 0x000f0000

static inline int __subleq_in_hardirq(void)
{
	unsigned long sp = *(volatile unsigned long *)16;
	/* thread_info is at stack base; preempt_count is at offset 4 */
	int *preempt_ptr = (int *)((sp & ~(SUBLEQ_THREAD_SIZE - 1)) + 4);
	return (*preempt_ptr) & SUBLEQ_HARDIRQ_MASK;
}

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

/*
 * Enable interrupts - but ONLY if we're not inside a hardirq handler.
 *
 * During interrupt handling, code paths like timer tick processing may
 * call local_irq_enable() or spin_unlock_irq(). If we actually enabled
 * hardware interrupts here, the VM could fire another timer interrupt,
 * causing nested entry into the interrupt handler. This would corrupt
 * the saved register state (stored in fixed memory locations) and cause
 * a recursive loop.
 *
 * By checking if we're in hardirq context, we ensure that:
 * - In normal context, local_irq_enable() actually enables interrupts
 * - Inside an interrupt handler, it's a no-op (hardware stays disabled
 *   until the handler completes and returns via entry.S)
 */
static inline void arch_local_irq_enable(void)
{
	if (*SUBLEQ_INT_HANDLER == 0 && !__subleq_in_hardirq()) {
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
		/*
		 * Re-enable interrupts only if not in hardirq context.
		 * Same reasoning as arch_local_irq_enable().
		 */
		if (!__subleq_in_hardirq()) {
			*SUBLEQ_INT_HANDLER = flags;
		}
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
