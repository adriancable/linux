// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq interrupt handling
 *
 * The VM fires a timer interrupt every 10000 instruction cycles:
 * - Saves current PC to m[1] (byte address 4)
 * - Jumps to handler address in m[0]
 *
 * The low-level assembly entry point is in entry.S (subleq_irq_entry).
 * It calls subleq_do_IRQ() and returns to the interrupted code.
 *
 * IMPORTANT: The interrupt handler uses a dedicated stack to avoid
 * corruption when interrupts fire while SP is being modified.
 */

#include <linux/init.h>
#include <linux/irq.h>
#include <linux/interrupt.h>
#include <linux/hardirq.h>
#include <linux/preempt.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>

#include <asm/irq.h>
#include <asm/irq_regs.h>
#include <asm/ptrace.h>
#include <asm/thread_info.h>

/*
 * Memory-mapped interrupt registers
 */
#define INT_HANDLER_ADDR ((volatile unsigned long *)0)
#define INT_SAVED_PC_ADDR ((volatile unsigned long *)4)
#define INT_SAVED_HANDLER ((volatile unsigned long *)8)

/*
 * Dedicated interrupt stack (8KB)
 *
 * This stack is used by the interrupt handler to avoid corruption when
 * an interrupt fires while the main code's SP is in an invalid state
 * (e.g., being cleared in preparation for reloading).
 *
 * The subleq_irq_stack_top pointer is exported to assembly (entry.S)
 * and is loaded into SP at the very start of the interrupt handler.
 *
 * IMPORTANT: This must be initialized VERY early, before start_kernel(),
 * because interrupts can fire at any time after that.
 */
#define IRQ_STACK_SIZE 8192
static unsigned long irq_stack[IRQ_STACK_SIZE / sizeof(unsigned long)] __aligned(4);

/* Pointer to top of interrupt stack - accessed from entry.S */
unsigned long subleq_irq_stack_top;

/*
 * INT_SP - The IRQ Stack Pointer register (byte address 460)
 *
 * This is a memory-mapped "register" that tracks the current position
 * in the IRQ stack. Each interrupt push decrements it, each pop increments it.
 * This allows multiple interrupt frames to coexist on the IRQ stack,
 * enabling preemptive multitasking.
 */
#define INT_SP_ADDR ((volatile unsigned long *)460)

/*
 * Early IRQ stack initialization - must be called before start_kernel()
 * This is called from subleq_start() in setup.c
 */
void __init early_irq_stack_init(void)
{
	/* Stack grows downward, so stack_top points to just past the end */
	subleq_irq_stack_top = (unsigned long)&irq_stack[IRQ_STACK_SIZE / sizeof(unsigned long)];

	/*
	 * Initialize INT_SP to the top of the IRQ stack.
	 * As interrupts fire, INT_SP will decrement with each pushed frame.
	 */
	*INT_SP_ADDR = subleq_irq_stack_top;
}

/* Assembly entry point from entry.S */
extern void subleq_irq_entry(void);

/* Timer interrupt handler (in time.c) - just calls legacy_timer_tick */
extern void subleq_timer_interrupt(void);

/* do_notify_resume is defined in signal.c */
extern asmlinkage void do_notify_resume(struct pt_regs *regs);

/* Forward declaration */
static void subleq_work_pending(struct pt_regs *regs);

/*
 * C-level interrupt handler - called from assembly entry.S
 *
 * This function wraps the actual interrupt handlers with irq_enter()/irq_exit().
 * Following the m68k do_IRQ() pattern.
 *
 * @regs: pt_regs structure containing the saved state of the interrupted code.
 *        This is built by entry.S from the saved registers.
 *        Signal delivery may modify this to redirect to a signal handler.
 */
void subleq_do_IRQ(struct pt_regs *regs)
{
	struct pt_regs *old_regs;

	/* Set up irq_regs for get_irq_regs() */
	old_regs = set_irq_regs(regs);

	/* Enter IRQ context - increments preempt_count hardirq bits */
	irq_enter();

	/* Handle the timer interrupt (the only interrupt we have) */
	subleq_timer_interrupt();

	/* Exit IRQ context - may trigger softirqs */
	irq_exit();

	/* Restore previous irq_regs */
	set_irq_regs(old_regs);

	/*
	 * Check for pending work before returning to the interrupted code.
	 * Skip during early boot when the scheduler isn't ready.
	 *
	 * Following the m68k pattern from coldfire/entry.S:
	 * 1. Check preempt_count for preemption safety
	 * 2. Check TIF_NEED_RESCHED for rescheduling
	 * 3. Check TIF_SIGPENDING for signal delivery
	 */
	if (system_state >= SYSTEM_RUNNING)
		subleq_work_pending(regs);
}

/*
 * Initialize the interrupt system
 */
void __init init_IRQ(void)
{
	/*
	 * NOTE: The interrupt stack was already initialized in
	 * early_irq_stack_init() called from subleq_start().
	 */

	/*
	 * Install our assembly interrupt handler.
	 * Set m[2] (saved handler) to the handler address.
	 * m[0] stays 0 (disabled) until local_irq_enable() is called.
	 */
	*INT_SAVED_HANDLER = (unsigned long)subleq_irq_entry;

	pr_info("Subleq IRQ: handler installed at 0x%lx, stack at 0x%lx\n",
		(unsigned long)subleq_irq_entry, subleq_irq_stack_top);
}

/*
 * subleq_work_pending - Check for and handle pending work after interrupt
 *
 * Called from the interrupt return path, after irq_exit() has returned.
 * Following the m68k pattern from coldfire/entry.S and kernel/signal.c.
 *
 * @regs: pt_regs of the interrupted context. Signal delivery will modify
 *        this to redirect execution to the signal handler.
 */
static void subleq_work_pending(struct pt_regs *regs)
{
	struct thread_info *ti;
	unsigned long flags;

	/*
	 * Disable IRQs for the checks.
	 * preempt_schedule_irq() requires IRQs disabled.
	 */
	local_irq_save(flags);

	/*
	 * Check preempt_count - must be 0 to safely reschedule or deliver signals.
	 * If it's non-zero, we're in an atomic context.
	 */
	if (preempt_count() != 0) {
		local_irq_restore(flags);
		return;
	}

	ti = current_thread_info();

	/*
	 * Check for rescheduling first.
	 * preempt_schedule_irq() handles the actual context switch.
	 */
	if (ti->flags & _TIF_NEED_RESCHED) {
		preempt_schedule_irq();
	}

	/*
	 * Check for pending signals.
	 * do_notify_resume() calls do_signal() which will modify regs
	 * to redirect execution to the signal handler.
	 *
	 * This is what makes Ctrl+C work for busy-looping processes!
	 */
	if (ti->flags & (_TIF_SIGPENDING | _TIF_NOTIFY_RESUME | _TIF_NOTIFY_SIGNAL)) {
		local_irq_restore(flags);

		/*
		 * Mark that we're NOT in a syscall for signal delivery.
		 * This prevents do_signal from attempting syscall restart.
		 */
		regs->syscall_nr = -1;

		/*
		 * Deliver signals. This may modify regs to redirect
		 * execution to a signal handler.
		 */
		do_notify_resume(regs);
		return;
	}

	local_irq_restore(flags);
}

