// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq syscall C handler - called from assembly trampoline
 *
 * The trampoline in entry.S handles:
 *   - Saving return address to a global (avoids userspace stack corruption)
 *   - Switching to kernel stack
 *   - Calling this function
 *   - Returning via the saved return address
 *
 * This function just dispatches to the appropriate syscall.
 */

#include <linux/syscalls.h>
#include <linux/errno.h>
#include <linux/sched/task_stack.h>
#include <asm/unistd.h>
#include <asm/ptrace.h>

/* Import the syscall table */
extern void *sys_call_table[];

/* Syscall function type */
typedef long (*syscall_fn_t)(long, long, long, long, long, long);

/*
 * Globals for saving userspace context - set by assembly trampoline.
 * These are defined in entry.S.
 */
extern unsigned long subleq_syscall_saved_sp;
extern unsigned long subleq_syscall_saved_fp;
extern unsigned long subleq_syscall_saved_ra;

/*
 * __subleq_syscall_c - C syscall handler
 *
 * Called from the assembly trampoline after stack has been switched
 * to the kernel stack. Returns to the trampoline which handles the
 * userspace return.
 */
extern void __subleq_putchar(int c);

long __subleq_syscall_c(long nr, long a1, long a2, long a3, long a4, long a5, long a6)
{
	syscall_fn_t fn;
	struct pt_regs *regs;

	/* DEBUG: Print syscall number to trace child execution */
	__subleq_putchar('{');
	/* Print syscall number as decimal (max 3 digits for common syscalls) */
	if (nr >= 100) __subleq_putchar('0' + (nr / 100) % 10);
	if (nr >= 10) __subleq_putchar('0' + (nr / 10) % 10);
	__subleq_putchar('0' + nr % 10);
	__subleq_putchar('}');

	/*
	 * Fill in pt_regs using the saved globals.
	 * This is needed for fork/vfork to copy the correct return context.
	 *
	 * The child process (via ret_from_fork) should return to the exact
	 * same state as the parent would after __subleq_syscall returns:
	 *   - PC = saved_ra (instruction after syscall call)
	 *   - FP = saved_fp (caller's frame pointer)
	 *   - SP = saved_sp + 4 (caller's SP after popping RA)
	 */
	regs = task_pt_regs(current);
	regs->pc = subleq_syscall_saved_ra;
	regs->fp = subleq_syscall_saved_fp;
	regs->sp = subleq_syscall_saved_sp + 4;  /* +4 to match SP after RA pop */

	/* Dispatch the syscall */
	if (nr < 0 || nr >= __NR_syscalls) {
		pr_warn("SUBLEQ_SYSCALL: nr=%ld out of range (max=%d)\n",
			nr, __NR_syscalls);
		return -ENOSYS;
	}

	fn = (syscall_fn_t)sys_call_table[nr];
	if (!fn || fn == (syscall_fn_t)sys_ni_syscall) {
		pr_warn("SUBLEQ_SYSCALL: syscall %ld not implemented\n", nr);
		return -ENOSYS;
	}

	return fn(a1, a2, a3, a4, a5, a6);
}


/*
 * subleq_init_kernel_sp - Initialize kernel stack pointer for a task
 *
 * Called during context switch to set up subleq_kernel_sp for the new task.
 * The assembly trampoline uses this to switch to the kernel stack.
 */
extern unsigned long subleq_kernel_sp;

void subleq_init_kernel_sp(struct task_struct *tsk)
{
	subleq_kernel_sp = (unsigned long)task_stack_page(tsk) + THREAD_SIZE 
			   - sizeof(struct pt_regs) - 256;
	/* Debug trace commented out
	pr_info("INIT_KERNEL_SP: tsk=%px subleq_kernel_sp=0x%lx stack=%px THREAD_SIZE=0x%lx\n",
		tsk, subleq_kernel_sp, task_stack_page(tsk), (unsigned long)THREAD_SIZE);
	*/
}
