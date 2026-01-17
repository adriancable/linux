/* SPDX-License-Identifier: GPL-2.0 */
/*
 * IRQ definitions for Subleq
 */

#ifndef _ASM_SUBLEQ_IRQ_H
#define _ASM_SUBLEQ_IRQ_H

/* Subleq has one interrupt source - the timer */
#define NR_IRQS 2
#define TIMER_IRQ 0

/* Timer interrupt handler (called from entry.S via subleq_do_IRQ) */
extern void subleq_timer_interrupt(void);

/* C-level interrupt handler (called from assembly) */
struct pt_regs;
extern void subleq_do_IRQ(struct pt_regs *regs);

/* Early IRQ stack initialization (called from setup.c before start_kernel) */
extern void early_irq_stack_init(void);

#include <asm-generic/irq.h>

#endif /* _ASM_SUBLEQ_IRQ_H */
