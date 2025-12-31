/* SPDX-License-Identifier: GPL-2.0 */
/*
 * MMU context for Subleq
 *
 * NOMMU - context switch is trivial.
 */

#ifndef _ASM_SUBLEQ_MMU_CONTEXT_H
#define _ASM_SUBLEQ_MMU_CONTEXT_H

#include <asm/mmu.h>
#include <asm-generic/mm_hooks.h>

static inline int init_new_context(struct task_struct *tsk,
				   struct mm_struct *mm)
{
	return 0;
}

static inline void destroy_context(struct mm_struct *mm)
{
}

static inline void switch_mm(struct mm_struct *prev, struct mm_struct *next,
			     struct task_struct *tsk)
{
	/* NOMMU - nothing to do */
}

#define activate_mm(prev, next) switch_mm((prev), (next), NULL)
#define deactivate_mm(tsk, mm) \
	do {                   \
	} while (0)
#define enter_lazy_tlb(mm, tsk) \
	do {                    \
	} while (0)

#endif /* _ASM_SUBLEQ_MMU_CONTEXT_H */
