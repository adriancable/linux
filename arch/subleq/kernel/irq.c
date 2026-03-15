// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq interrupt handling
 *
 * The VM fires a timer interrupt periodically (by instruction count):
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
 * C-level interrupt handler, called from entry.S.
 * Wraps tick processing with irq_enter()/irq_exit().
 * Signal delivery and rescheduling happen separately via subleq_do_work().
 */
void subleq_do_IRQ(struct pt_regs *regs)
{
	struct pt_regs *old_regs;

	/* Set up irq_regs for get_irq_regs() */
	old_regs = set_irq_regs(regs);

	/* Enter IRQ context - increments preempt_count hardirq bits */
	irq_enter();

	/*
	 * Advance jiffies based on wall-clock time.
	 * Timer interrupts fire by instruction count, not real time,
	 * so we calculate elapsed ticks from the clock registers.
	 * Uses a 32-bit incremental loop to avoid expensive 64-bit math.
	 */
	{
		unsigned int ticks = 0;
		u32 lo = readl((void __iomem *)SUBLEQ_CLOCK_S_LO);
		u32 hi = readl((void __iomem *)SUBLEQ_CLOCK_S_HI);
		u32 ns = readl((void __iomem *)SUBLEQ_CLOCK_NS);
		static u32 last_s_lo;
		static u32 last_s_hi;
		static u32 last_ns;
		const u32 tick_ns = NSEC_PER_SEC / HZ;

		if (last_s_lo == 0 && last_s_hi == 0 && last_ns == 0) {
			last_s_lo = lo;
			last_s_hi = hi;
			last_ns = ns;
		}

		/*
		 * Advance last_s:last_ns by tick_ns for each full tick.
		 * Normalizes across second boundaries. Typically 0-1 iterations.
		 */
		for (;;) {
			u32 next_ns = last_ns + tick_ns;
			u32 next_s_lo = last_s_lo;
			u32 next_s_hi = last_s_hi;

			if (next_ns >= NSEC_PER_SEC) {
				next_ns -= NSEC_PER_SEC;
				next_s_lo++;
				if (next_s_lo == 0)
					next_s_hi++;
			}
			/*
			 * Full 64-bit tuple comparison:
			 * (hi,lo,ns) >= (next_s_hi,next_s_lo,next_ns)
			 */
			if (hi > next_s_hi ||
			    (hi == next_s_hi && (lo > next_s_lo ||
			    (lo == next_s_lo && ns >= next_ns)))) {
				ticks++;
				last_s_lo = next_s_lo;
				last_s_hi = next_s_hi;
				last_ns = next_ns;
			} else {
				break;
			}
		}

		if (ticks > 0)
			legacy_timer_tick(ticks);
	}

	/* Exit IRQ context - may trigger softirqs */
	irq_exit();

	/* Restore previous irq_regs */
	set_irq_regs(old_regs);

	/* Work checking (signals, resched) is done by subleq_do_work() */
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
 * Handle pending work (signals, rescheduling) before returning to user.
 * Called from the interrupt return path in entry.S in a loop until
 * no work remains. Returns non-zero if work was done.
 */
int subleq_do_work(struct pt_regs *regs)
{
	struct thread_info *ti;
	unsigned long work_flags;

	/* Skip during early boot when the scheduler isn't ready */
	if (system_state < SYSTEM_RUNNING)
		return 0;

	/*
	 * Kernel-mode preemption: if preemption is safe, let the
	 * scheduler run. preempt_schedule_irq() handles IRQ state.
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

	/* User-mode return path: check for pending work */

	/* Check preempt_count - must be 0 to safely reschedule or deliver signals */
	if (preempt_count() != 0)
		return 0;

	/*
	 * Guard against transient SP=0. Subleq SP updates are non-atomic
	 * (clear then set), so an interrupt between them sees SP=0.
	 * Skip work; it'll be handled on the next interrupt.
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

