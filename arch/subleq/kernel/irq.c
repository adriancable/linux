// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq interrupt handling
 *
 * The VM fires a timer interrupt every 10000 instruction cycles:
 * - Saves current PC to m[1] (byte address 4)
 * - Jumps to handler address in m[0]
 *
 * The low-level assembly entry point is in entry.S (subleq_irq_entry).
 * It uses the current task's kernel stack (not a dedicated IRQ stack).
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

/* subleq_irq_entry declared in asm/ptrace.h as char[] for address range checking */

/* do_notify_resume is defined in signal.c */
extern asmlinkage void do_notify_resume(struct pt_regs *regs);

/*
 * C-level interrupt handler - called from assembly entry.S
 *
 * This function wraps the actual interrupt handlers with irq_enter()/irq_exit().
 * Following the m68k do_IRQ() pattern.
 *
 * IMPORTANT: This function does NOT handle signal delivery or rescheduling.
 * That is done by a separate call to subleq_do_work() from assembly, following
 * the ColdFire coldfire/entry.S pattern where the work loop is in assembly.
 *
 * @regs: pt_regs structure containing the saved state of the interrupted code.
 */
void subleq_do_IRQ(struct pt_regs *regs)
{
	struct pt_regs *old_regs;

	/* Set up irq_regs for get_irq_regs() */
	old_regs = set_irq_regs(regs);

	/* Enter IRQ context - increments preempt_count hardirq bits */
	irq_enter();

	/* Handle the timer interrupt (the only interrupt we have) */
	legacy_timer_tick(1);

	/* Exit IRQ context - may trigger softirqs */
	irq_exit();

	/* Restore previous irq_regs */
	set_irq_regs(old_regs);

	/* 
	 * NOTE: Work checking (signals, reschedule) is now done by assembly
	 * calling subleq_do_work() in a loop, following ColdFire pattern.
	 */
}

/*
 * Initialize the interrupt system
 */
void __init init_IRQ(void)
{
	/*
	 * Install our assembly interrupt handler.
	 * Set m[2] (saved handler) to the handler address.
	 * m[0] stays 0 (disabled) until local_irq_enable() is called.
	 */
	*INT_SAVED_HANDLER = (unsigned long)subleq_irq_entry;

	pr_info("Subleq IRQ: handler installed at 0x%lx\n",
		(unsigned long)subleq_irq_entry);
}

/*
 * subleq_do_work - Handle pending work before returning to user
 *
 * Called from the interrupt return path in entry.S, AFTER subleq_do_IRQ returns.
 * This follows the ColdFire coldfire/entry.S pattern where assembly calls this
 * in a loop until no work remains.
 *
 * @regs: pt_regs of the interrupted context. Signal delivery may modify
 *        this to redirect execution to the signal handler.
 *
 * Returns: 0 if no work done (safe to return to user)
 *          non-zero if work was done (assembly should loop back and check again)
 */
int subleq_do_work(struct pt_regs *regs)
{
	struct thread_info *ti;
	unsigned long work_flags;

	/* Skip during early boot when the scheduler isn't ready */
	if (system_state < SYSTEM_RUNNING)
		return 0;

	/*
	 * Check preempt_count - must be 0 to safely reschedule or deliver signals.
	 * If it's non-zero, we're in an atomic context.
	 */
	if (preempt_count() != 0)
		return 0;

	/*
	 * CRITICAL: Only deliver signals when returning to USERSPACE.
	 * If we're returning to kernel code (e.g., interrupted syscall),
	 * skip signal delivery. Signals will be delivered when that
	 * kernel code eventually returns to userspace via the syscall path.
	 *
	 * This follows the ColdFire pattern in coldfire/entry.S:
	 *   btst #5,%sp@(PT_OFF_SR)  ; check if returning to kernel
	 *   jeq  Luser_return        ; if user mode, check for work
	 */
	if (!user_mode(regs))
		return 0;

	/*
	 * Check for transient invalid SP.
	 *
	 * In Subleq, SP updates are non-atomic: SP is cleared to 0 before
	 * being set to the new value. If an interrupt fires between these
	 * operations, SP will be 0 or garbage.
	 *
	 * If SP is invalid (0 or in low memory), skip signal delivery.
	 * The signal will be delivered on the next interrupt when SP is valid.
	 * This is safe because signals are edge-triggered - they'll still
	 * be pending on the next check.
	 *
	 * We consider SP invalid if it's below 4KB (0x1000), as valid user
	 * stacks are in higher memory.
	 */
	if (PT_REG_GET(regs, sp) < 0x1000)
		return 0;

	ti = current_thread_info();
	work_flags = ti->flags & _TIF_WORK_MASK;

	/* No work to do */
	if (!work_flags)
		return 0;

	/*
	 * Handle rescheduling first.
	 * preempt_schedule_irq() requires IRQs disabled, handles that internally.
	 */
	if (work_flags & _TIF_NEED_RESCHED) {
		preempt_schedule_irq();
		/* Return 1 to recheck flags - reschedule may have cleared flag */
		return 1;
	}

	/*
	 * Handle signals.
	 * do_notify_resume() calls do_signal() which will modify regs
	 * to redirect execution to the signal handler.
	 *
	 * This is what makes Ctrl+C work for busy-looping processes!
	 */
	if (work_flags & (_TIF_SIGPENDING | _TIF_NOTIFY_RESUME | _TIF_NOTIFY_SIGNAL)) {
		/*
		 * IRQ entry assembly already sets syscall_nr = -1, so
		 * do_signal() won't attempt syscall restart. Just deliver
		 * the signal. This may modify regs to redirect execution
		 * to a signal handler.
		 */
		do_notify_resume(regs);

		/* Return 1 to recheck flags - new signals may have been queued */
		return 1;
	}

	return 0;
}

