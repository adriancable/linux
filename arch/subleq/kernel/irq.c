// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq interrupt handling
 *
 * The VM fires a timer interrupt every 500000 instruction cycles:
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
#include <asm/current.h>

/*
 * Memory-mapped interrupt registers
 */
#define INT_HANDLER_ADDR ((volatile unsigned long *)0)
#define INT_SAVED_PC_ADDR ((volatile unsigned long *)4)
#define INT_SAVED_HANDLER ((volatile unsigned long *)8)

/* Subleq Clock Registers */
#define SUBLEQ_CLOCK_S_LO	256
#define SUBLEQ_CLOCK_S_HI	260
#define SUBLEQ_CLOCK_NS		264

/* subleq_irq_entry declared in asm/ptrace.h as char[] for address range checking */

/* do_notify_resume is defined in signal.c */
extern asmlinkage void do_notify_resume(struct pt_regs *regs);

static inline u64 subleq_get_time_ns(void)
{
	u32 lo = readl((void __iomem *)SUBLEQ_CLOCK_S_LO);
	u32 hi = readl((void __iomem *)SUBLEQ_CLOCK_S_HI);
	u32 ns = readl((void __iomem *)SUBLEQ_CLOCK_NS);
	return ((u64)hi << 32 | lo) * NSEC_PER_SEC + ns;
}

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
	/*
	 * Advance jiffies based on real wall-clock time.
	 *
	 * Timer interrupts fire by instruction count, not real time.
	 * Read the VM's nanosecond-resolution clock and compute how
	 * many ticks (at HZ rate) should have elapsed since the last
	 * update, then advance jiffies by that amount.
	 *
	 * If less than one tick has elapsed, skip — do not force a
	 * minimum, as that would cause last_ns to drift ahead of
	 * now_ns and eventually wrap the unsigned subtraction.
	 */
	{
		unsigned int ticks;
		u64 now_ns = subleq_get_time_ns();
		static u64 last_ns;

		if (last_ns == 0)
			last_ns = now_ns;

		ticks = (unsigned int)((now_ns - last_ns) /
				       (NSEC_PER_SEC / HZ));
		if (ticks > 0) {
			last_ns += (u64)ticks * (NSEC_PER_SEC / HZ);
			legacy_timer_tick(ticks);
		}
	}

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
	 * KERNEL-MODE PREEMPTION (CONFIG_PREEMPTION)
	 *
	 * If we interrupted kernel code and preemption is safe, allow
	 * the scheduler to preempt. This follows the ColdFire/nios2
	 * pattern where preempt_schedule_irq() is called ONLY for
	 * kernel-mode returns, with IRQs disabled.
	 *
	 * preempt_schedule_irq() requires: preempt_count() == 0 &&
	 * irqs_disabled(). It enables IRQs internally for schedule().
	 */
	if (!user_mode(regs)) {
#ifdef CONFIG_PREEMPTION
		if (preempt_count() == 0 && need_resched()) {
			preempt_schedule_irq();
			return 1;
		}
#endif
		return 0;
	}

	/*
	 * USER-MODE RETURN PATH
	 *
	 * We're returning to userspace. Check for pending work.
	 * Following the standard pattern (ColdFire, nios2, generic entry):
	 * enable IRQs, call schedule()/do_notify_resume(), disable IRQs.
	 */

	/* Check preempt_count - must be 0 to safely reschedule or deliver signals */
	if (preempt_count() != 0)
		return 0;

	/*
	 * Check for transient invalid SP.
	 *
	 * In Subleq, SP updates are non-atomic: SP is cleared to 0 before
	 * being set to the new value. If an interrupt fires between these
	 * operations, SP will be 0 or garbage.
	 *
	 * If SP is invalid (0 or in low memory), skip work.
	 * The signal/resched will be handled on the next interrupt.
	 */
	if (PT_REG_GET(regs, sp) < 0x1000)
		return 0;

	ti = current_thread_info();
	work_flags = ti->flags & _TIF_WORK_MASK;

	/* No work to do */
	if (!work_flags)
		return 0;

	/*
	 * Handle rescheduling.
	 * For user-mode returns: enable IRQs, call schedule(), disable IRQs.
	 * This is the standard pattern used by ColdFire, nios2, and the
	 * generic kernel entry code (kernel/entry/common.c).
	 */
	if (work_flags & _TIF_NEED_RESCHED) {
		local_irq_enable();
		schedule();
		local_irq_disable();
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
		local_irq_enable();
		do_notify_resume(regs);
		local_irq_disable();
		return 1;
	}

	return 0;
}

