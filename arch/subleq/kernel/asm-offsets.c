// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq asm-offsets - Generate constants for assembly code
 */

#include <linux/kbuild.h>
#include <linux/sched.h>
#include <asm/ptrace.h>
#include <asm/processor.h>
#include <asm/thread_info.h>

int main(void)
{
	COMMENT("Subleq pt_regs offsets");
	OFFSET(PT_SP, pt_regs, sp);
	OFFSET(PT_RA, pt_regs, ra);
	OFFSET(PT_PC, pt_regs, pc);
	OFFSET(PT_R3, pt_regs, r3);
	DEFINE(PT_SIZE, sizeof(struct pt_regs));
	BLANK();

	COMMENT("Subleq thread_info offsets");
	OFFSET(TI_FLAGS, thread_info, flags);
	DEFINE(THREAD_SIZE_ASM, THREAD_SIZE);
	BLANK();

	COMMENT("Subleq task_struct offsets");
	OFFSET(TASK_THREAD, task_struct, thread);
	OFFSET(THREAD_SP, thread_struct, sp);
	OFFSET(THREAD_FP, thread_struct, fp);
	/* Combined offsets for direct access from task_struct pointer */
	DEFINE(TASK_THREAD_SP, offsetof(struct task_struct, thread.sp));
	DEFINE(TASK_THREAD_FP, offsetof(struct task_struct, thread.fp));
	BLANK();

	return 0;
}
