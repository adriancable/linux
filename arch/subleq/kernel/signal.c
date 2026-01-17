// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq signal handling
 *
 * Based on m68k/kernel/signal.c signal handling patterns for NOMMU.
 */

#include <linux/kernel.h>
#include <linux/signal.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/syscalls.h>
#include <linux/errno.h>
#include <linux/resume_user_mode.h>
#include <linux/uaccess.h>
#include <linux/unistd.h>

#include <asm/ptrace.h>
#include <asm/sigcontext.h>
#include <asm/ucontext.h>

/* Forward declarations */
void do_signal(struct pt_regs *regs);
asmlinkage long sys_rt_sigreturn(void);



/*
 * Signal return trampoline - defined in entry.S
 * This is a kernel function that the userspace signal handler returns to.
 * It invokes sys_rt_sigreturn to restore the original context.
 */
extern void ret_from_user_rt_signal(void);

/*
 * Signal frame structure - placed on user stack when delivering a signal.
 *
 * When a signal is delivered:
 * 1. This frame is pushed onto the user stack
 * 2. SP is set to point to this frame
 * 3. PC is set to the signal handler
 * 4. R21 (arg1) is set to the signal number
 *
 * When the handler returns (via pretcode), sys_rt_sigreturn restores
 * the original context from this frame.
 */
struct rt_sigframe {
	void *pretcode;              /* Return trampoline address */
	int sig;                     /* Signal number */
	struct siginfo __user *pinfo; /* Pointer to info below */
	void __user *puc;            /* Pointer to uc below */
	struct siginfo info;         /* Signal info */
	struct ucontext uc;          /* User context with saved regs/mask */
};

/*
 * save_sigcontext - Save register state to sigcontext
 */
static int save_sigcontext(struct sigcontext __user *sc, struct pt_regs *regs)
{
	int err = 0;

	/*
	 * regs->pc contains the return address for both syscall and interrupt
	 * context. For syscalls, syscall_entry.c sets it to subleq_syscall_saved_ra.
	 * For interrupts, the interrupt handler sets it to the interrupted PC.
	 */


	/* Save all general purpose registers */
	err |= __put_user(regs->r3, &sc->sc_regs[0]);
	err |= __put_user(regs->r4, &sc->sc_regs[1]);
	err |= __put_user(regs->r5, &sc->sc_regs[2]);
	err |= __put_user(regs->r6, &sc->sc_regs[3]);
	err |= __put_user(regs->r7, &sc->sc_regs[4]);
	err |= __put_user(regs->r8, &sc->sc_regs[5]);
	err |= __put_user(regs->r9, &sc->sc_regs[6]);
	err |= __put_user(regs->r10, &sc->sc_regs[7]);
	err |= __put_user(regs->r11, &sc->sc_regs[8]);
	err |= __put_user(regs->r12, &sc->sc_regs[9]);
	err |= __put_user(regs->r13, &sc->sc_regs[10]);
	err |= __put_user(regs->r14, &sc->sc_regs[11]);
	err |= __put_user(regs->r15, &sc->sc_regs[12]);
	err |= __put_user(regs->r16, &sc->sc_regs[13]);
	err |= __put_user(regs->r17, &sc->sc_regs[14]);
	err |= __put_user(regs->r18, &sc->sc_regs[15]);
	err |= __put_user(regs->r19, &sc->sc_regs[16]);
	err |= __put_user(regs->r20, &sc->sc_regs[17]);
	err |= __put_user(regs->r21, &sc->sc_regs[18]);
	err |= __put_user(regs->r22, &sc->sc_regs[19]);
	err |= __put_user(regs->r23, &sc->sc_regs[20]);
	err |= __put_user(regs->r24, &sc->sc_regs[21]);
	err |= __put_user(regs->r25, &sc->sc_regs[22]);
	err |= __put_user(regs->r26, &sc->sc_regs[23]);
	err |= __put_user(regs->r27, &sc->sc_regs[24]);
	err |= __put_user(regs->r28, &sc->sc_regs[25]);
	err |= __put_user(regs->r29, &sc->sc_regs[26]);
	err |= __put_user(regs->r30, &sc->sc_regs[27]);
	err |= __put_user(regs->r31, &sc->sc_regs[28]);
	err |= __put_user(regs->fp, &sc->sc_regs[29]);
	err |= __put_user(regs->sp, &sc->sc_regs[30]);
	err |= __put_user(regs->ra, &sc->sc_regs[31]);
	err |= __put_user(regs->pc, &sc->sc_pc);

	return err;
}

/*
 * restore_sigcontext - Restore register state from sigcontext
 */
static int restore_sigcontext(struct pt_regs *regs, struct sigcontext __user *sc)
{
	int err = 0;

	/* Restore all general purpose registers */
	err |= __get_user(regs->r3, &sc->sc_regs[0]);
	err |= __get_user(regs->r4, &sc->sc_regs[1]);
	err |= __get_user(regs->r5, &sc->sc_regs[2]);
	err |= __get_user(regs->r6, &sc->sc_regs[3]);
	err |= __get_user(regs->r7, &sc->sc_regs[4]);
	err |= __get_user(regs->r8, &sc->sc_regs[5]);
	err |= __get_user(regs->r9, &sc->sc_regs[6]);
	err |= __get_user(regs->r10, &sc->sc_regs[7]);
	err |= __get_user(regs->r11, &sc->sc_regs[8]);
	err |= __get_user(regs->r12, &sc->sc_regs[9]);
	err |= __get_user(regs->r13, &sc->sc_regs[10]);
	err |= __get_user(regs->r14, &sc->sc_regs[11]);
	err |= __get_user(regs->r15, &sc->sc_regs[12]);
	err |= __get_user(regs->r16, &sc->sc_regs[13]);
	err |= __get_user(regs->r17, &sc->sc_regs[14]);
	err |= __get_user(regs->r18, &sc->sc_regs[15]);
	err |= __get_user(regs->r19, &sc->sc_regs[16]);
	err |= __get_user(regs->r20, &sc->sc_regs[17]);
	err |= __get_user(regs->r21, &sc->sc_regs[18]);
	err |= __get_user(regs->r22, &sc->sc_regs[19]);
	err |= __get_user(regs->r23, &sc->sc_regs[20]);
	err |= __get_user(regs->r24, &sc->sc_regs[21]);
	err |= __get_user(regs->r25, &sc->sc_regs[22]);
	err |= __get_user(regs->r26, &sc->sc_regs[23]);
	err |= __get_user(regs->r27, &sc->sc_regs[24]);
	err |= __get_user(regs->r28, &sc->sc_regs[25]);
	err |= __get_user(regs->r29, &sc->sc_regs[26]);
	err |= __get_user(regs->r30, &sc->sc_regs[27]);
	err |= __get_user(regs->r31, &sc->sc_regs[28]);
	err |= __get_user(regs->fp, &sc->sc_regs[29]);
	err |= __get_user(regs->sp, &sc->sc_regs[30]);
	err |= __get_user(regs->ra, &sc->sc_regs[31]);
	err |= __get_user(regs->pc, &sc->sc_pc);

	return err;
}

/*
 * get_sigframe - Calculate where to place the signal frame on user stack
 */
static inline void __user *get_sigframe(struct ksignal *ksig,
					struct pt_regs *regs,
					size_t frame_size)
{
	unsigned long sp;

	/* Use alternate signal stack if available and appropriate */
	sp = sigsp(regs->sp, ksig);

	/* Align to 4-byte boundary (Subleq word alignment) */
	sp = (sp - frame_size) & ~3UL;

	return (void __user *)sp;
}

/*
 * setup_rt_frame - Set up the signal frame on user stack
 *
 * This function:
 * 1. Allocates space on user stack for rt_sigframe
 * 2. Saves current registers to the frame
 * 3. Saves signal mask
 * 4. Sets pretcode to return trampoline
 * 5. Modifies regs so that when we return to userspace:
 *    - PC points to signal handler
 *    - SP points to signal frame
 *    - R21 (arg1) contains signal number
 */
static int setup_rt_frame(struct ksignal *ksig, sigset_t *set,
			  struct pt_regs *regs)
{
	struct rt_sigframe __user *frame;
	int err = 0;

	frame = get_sigframe(ksig, regs, sizeof(*frame));



	if (!access_ok(frame, sizeof(*frame)))
		return -EFAULT;

	/* Set up the frame header */
	err |= __put_user((void *)ret_from_user_rt_signal, &frame->pretcode);
	err |= __put_user(ksig->sig, &frame->sig);
	err |= __put_user(&frame->info, &frame->pinfo);
	err |= __put_user(&frame->uc, &frame->puc);

	/* Copy siginfo */
	err |= copy_siginfo_to_user(&frame->info, &ksig->info);

	/* Set up ucontext */
	err |= __put_user(0, &frame->uc.uc_flags);
	err |= __put_user(NULL, &frame->uc.uc_link);
	err |= __save_altstack(&frame->uc.uc_stack, regs->sp);
	err |= save_sigcontext(&frame->uc.uc_mcontext, regs);
	err |= __copy_to_user(&frame->uc.uc_sigmask, set, sizeof(*set));

	if (err)
		return -EFAULT;

	/*
	 * Set up registers for signal handler.
	 * When we return to userspace, we'll be executing the handler.
	 *
	 * CRITICAL: Subleq's RET instruction pops the return address from [SP].
	 * Normal function calls push RA before jumping to the callee.
	 * We must simulate this by pushing the trampoline address onto the stack.
	 *
	 * Stack layout after setup:
	 *   [higher addresses]
	 *   <signal frame data>  <- frame points here
	 *   [return address]     <- SP points here (trampoline address)
	 *   [lower addresses]
	 *
	 * When handler returns:
	 * 1. Handler's epilogue restores SP to point to return address
	 * 2. RET pops return address and jumps to trampoline
	 * 3. Trampoline invokes sigreturn with SP pointing above the RA slot
	 */
	{
		unsigned long __user *ra_slot;

		/* Allocate space for return address below the frame */
		ra_slot = (unsigned long __user *)((unsigned long)frame - 4);

		/* Push the trampoline address */
		err = __put_user((unsigned long)ret_from_user_rt_signal, ra_slot);
		if (err)
			return -EFAULT;

		/* SP points to the pushed return address */
		regs->sp = (unsigned long)ra_slot;
	}

	regs->pc = (unsigned long)ksig->ka.sa.sa_handler;
	regs->r21 = ksig->sig;  /* First argument: signal number */

	/*
	 * For SA_SIGINFO handlers, set up additional arguments:
	 * R22 = pointer to siginfo
	 * R23 = pointer to ucontext
	 */
	if (ksig->ka.sa.sa_flags & SA_SIGINFO) {
		regs->r22 = (unsigned long)&frame->info;
		regs->r23 = (unsigned long)&frame->uc;
	}

	/*
	 * Also set RA register for compatibility with code that reads RA directly.
	 * The primary return mechanism is the pushed value on the stack.
	 */
	regs->ra = (unsigned long)ret_from_user_rt_signal;

	return 0;
}

/*
 * handle_restart - Handle syscall restart based on error code and signal state
 *
 * @regs: Current pt_regs
 * @ka:   Signal action (NULL if no signal to deliver)
 * @has_handler: True if a signal handler is about to be invoked
 *
 * This follows the m68k pattern for handling restart codes.
 */
static inline void
handle_restart(struct pt_regs *regs, struct k_sigaction *ka, int has_handler)
{
	switch (regs->r20) {
	case -ERESTARTNOHAND:
		/*
		 * ERESTARTNOHAND: Restart only if there's no handler.
		 * If we have a handler, convert to EINTR.
		 */
		if (!has_handler)
			goto do_restart;
		regs->r20 = -EINTR;
		break;

	case -ERESTART_RESTARTBLOCK:
		/*
		 * ERESTART_RESTARTBLOCK: Use the restart_block mechanism.
		 * For now, convert to EINTR. Proper implementation would
		 * change syscall to __NR_restart_syscall.
		 */
		if (!has_handler)
			goto do_restart;
		regs->r20 = -EINTR;
		break;

	case -ERESTARTSYS:
		/*
		 * ERESTARTSYS: Restart unless there's a handler without SA_RESTART.
		 */
		if (has_handler && !(ka->sa.sa_flags & SA_RESTART)) {
			regs->r20 = -EINTR;
			break;
		}
		fallthrough;

	case -ERESTARTNOINTR:
		/*
		 * ERESTARTNOINTR: Always restart, regardless of signals.
		 * This is used by vfork's wait_for_vfork_done().
		 *
		 * To restart the syscall:
		 * 1. Restore original syscall number to R21 (from orig_r21)
		 * 2. Keep the restart code so syscall_entry.c knows to restart
		 */
	do_restart:
		regs->r21 = regs->orig_r21;
		regs->r20 = -ERESTARTNOINTR;  /* Keep the restart code */
		break;
	}
}

/*
 * handle_signal - Invoke a signal handler
 */
static void handle_signal(struct ksignal *ksig, struct pt_regs *regs)
{
	sigset_t *oldset = sigmask_to_save();
	int err;

	/* Handle syscall restart if we came from a syscall */
	if (in_syscall(regs))
		handle_restart(regs, &ksig->ka, 1);

	/* Set up the signal frame */
	err = setup_rt_frame(ksig, oldset, regs);

	/* Report signal setup status */
	signal_setup_done(err, ksig, 0);
}

/*
 * do_signal - Handle signal delivery and syscall restart
 *
 * This is called from the syscall return path. It:
 * 1. Checks for pending signals using get_signal()
 * 2. If a signal is pending, handles restart and delivers the signal
 * 3. If no signal, handles restart for interrupted syscalls
 *
 * Following the m68k pattern for proper NOMMU signal handling.
 */
void do_signal(struct pt_regs *regs)
{
	struct ksignal ksig;

	/*
	 * Check if there's a signal to deliver.
	 * get_signal() returns true if a signal needs to be delivered.
	 * It also handles signal stopping, coredumps, and sets up ksig.
	 */
	if (get_signal(&ksig)) {
		/* Deliver the signal */
		handle_signal(&ksig, regs);
		return;
	}

	/*
	 * No signal to deliver.
	 *
	 * If we came from a syscall and got a restart code, handle it.
	 * With no signal handler, ERESTARTSYS and ERESTARTNOHAND should
	 * both result in syscall restart.
	 */
	if (in_syscall(regs))
		handle_restart(regs, NULL, 0);

	/*
	 * If there's no signal to deliver, restore the saved sigmask.
	 * This is used by sigsuspend() and related calls.
	 */
	restore_saved_sigmask();
}

/*
 * sys_rt_sigreturn - Restore context after signal handler returns
 *
 * This is called when the signal handler returns via the trampoline.
 * It restores the original register state and signal mask from the
 * signal frame on the user stack.
 */
asmlinkage long sys_rt_sigreturn(void)
{
	struct pt_regs *regs = current_pt_regs();
	struct rt_sigframe __user *frame;
	sigset_t set;

	/*
	 * The signal frame is at SP - 4.
	 *
	 * When the handler's RET pops the return address, SP points to the frame.
	 * Then the trampoline JUMPs (not CALLs) to __subleq_syscall.
	 * But syscall_entry.c adds 4 to saved_sp to account for a normal CALL's
	 * pushed RA. Since we jumped, not called, we need to subtract that 4.
	 */
	frame = (struct rt_sigframe __user *)(regs->sp - 4);

	if (!access_ok(frame, sizeof(*frame)))
		goto badframe;

	/* Restore signal mask */
	if (__copy_from_user(&set, &frame->uc.uc_sigmask, sizeof(set)))
		goto badframe;

	set_current_blocked(&set);

	/* Restore registers */
	if (restore_sigcontext(regs, &frame->uc.uc_mcontext))
		goto badframe;

	/* Restore alternate signal stack */
	if (restore_altstack(&frame->uc.uc_stack))
		goto badframe;

	/*
	 * CRITICAL: Mark that we're NOT in a syscall.
	 * This prevents do_signal from attempting syscall restart,
	 * which would corrupt the restored PC.
	 */
	regs->syscall_nr = -1;

	/*
	 * Return the restored R20 value.
	 * The caller will use this as the function return value.
	 */
	return regs->r20;

badframe:
	force_sig(SIGSEGV);
	return 0;
}
