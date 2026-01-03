/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Subleq hardirq definitions
 */
#ifndef __ASM_SUBLEQ_HARDIRQ_H
#define __ASM_SUBLEQ_HARDIRQ_H

#include <asm-generic/hardirq.h>

/*
 * The Subleq interrupt system keeps hardware interrupts disabled throughout
 * the irq_exit() path, including softirq processing.
 *
 * This flag tells the kernel that when irq_exit() runs, interrupts are already
 * disabled, so there's no need to call local_irq_disable() at the start of
 * __irq_exit_rcu().
 *
 * The complete flow is:
 * 1. entry.S: Timer interrupt fires, handler disables (m[0]=0), saves state
 * 2. C code: subleq_do_IRQ() runs with m[0]=0
 * 3. irq_enter() / handler / irq_exit() all run with m[0]=0
 * 4. irq_exit() calls invoke_softirq() -> handle_softirqs()
 * 5. handle_softirqs() calls local_irq_enable(), but our arch_local_irq_enable()
 *    checks in_interrupt() which returns true (softirq bits set), so it's a no-op
 * 6. subleq_do_IRQ() returns to entry.S
 * 7. entry.S: restores state, re-enables interrupts (m[0]=handler), returns
 *
 * The key protection is in irqflags.h: arch_local_irq_enable() is a no-op
 * when in_interrupt() is true (hardirq OR softirq context).
 */
#define __ARCH_IRQ_EXIT_IRQS_DISABLED 1

#endif /* __ASM_SUBLEQ_HARDIRQ_H */
