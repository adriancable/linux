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
 * Get interrupt context status directly from thread_info without including preempt.h
 * This avoids a circular include dependency.
 *
 * The thread_info is at the bottom of the kernel stack. We read SP from
 * memory location 16 and mask off the stack offset. The preempt_count
 * is at offset 4 (after the flags field) in struct thread_info.
 *
 * We need to check BOTH hardirq AND softirq context:
 *   in_interrupt() = (preempt_count & (HARDIRQ_MASK | SOFTIRQ_MASK))
 *
 * This is critical because irq_exit() decrements the hardirq count BEFORE
 * calling invoke_softirq(). If we only checked hardirq, we would re-enable
 * interrupts during softirq processing, causing re-entrancy.
 *
 * Bit layout (from preempt.h):
 *   Bits 0-7:   preempt count
 *   Bits 8-15:  softirq count (SOFTIRQ_MASK = 0x0000ff00)
 *   Bits 16-19: hardirq count (HARDIRQ_MASK = 0x000f0000)
 *   Bits 20+:   NMI, etc
 */
#define SUBLEQ_THREAD_SIZE 8192 /* 2*PAGE_SIZE - must match asm/thread_info.h */
#define SUBLEQ_HARDIRQ_MASK 0x000f0000
#define SUBLEQ_SOFTIRQ_MASK 0x0000ff00
#define SUBLEQ_IRQMASK (SUBLEQ_HARDIRQ_MASK | SUBLEQ_SOFTIRQ_MASK)

static inline int __subleq_in_interrupt(void)
{
	unsigned long sp = *(volatile unsigned long *)16;
	/* thread_info is at stack base; preempt_count is at offset 4 */
	int *preempt_ptr = (int *)((sp & ~(SUBLEQ_THREAD_SIZE - 1)) + 4);
	return (*preempt_ptr) & SUBLEQ_IRQMASK;
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
 * Enable interrupts - but ONLY if we're not inside ANY interrupt context.
 *
 * During interrupt handling, kernel code may call local_irq_enable() or
 * spin_unlock_irq(). This includes:
 *   - Direct calls during hardirq processing
 *   - Calls from handle_softirqs() (after irq_exit decrements hardirq count)
 *
 * If we actually enabled hardware interrupts while in interrupt context,
 * the VM could fire another timer interrupt, causing nested entry into the
 * interrupt handler. This would corrupt the saved register state and cause
 * a crash or infinite recursion.
 *
 * We check BOTH hardirq AND softirq context because:
 *   - irq_exit() decrements hardirq count BEFORE calling invoke_softirq()
 *   - handle_softirqs() calls local_irq_enable() at line 606
 *   - At that point, in_hardirq() is FALSE but we're still in the ISR path!
 *   - in_serving_softirq() is TRUE, so in_interrupt() catches this case
 *
 * By checking in_interrupt() (hardirq | softirq), we ensure:
 *   - In normal context, local_irq_enable() actually enables interrupts
 *   - Inside any interrupt processing, it's a no-op (hardware stays disabled
 *     until the handler completes and returns via entry.S)
 */
static inline void arch_local_irq_enable(void)
{
	if (*SUBLEQ_INT_HANDLER == 0 && !__subleq_in_interrupt()) {
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
		 * Re-enable interrupts only if not in any interrupt context.
		 * Same reasoning as arch_local_irq_enable().
		 */
		if (!__subleq_in_interrupt()) {
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
