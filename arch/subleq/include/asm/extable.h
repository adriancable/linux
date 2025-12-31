/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Exception table for Subleq
 */

#ifndef _ASM_SUBLEQ_EXTABLE_H
#define _ASM_SUBLEQ_EXTABLE_H

/* No exception table - NOMMU doesn't have page faults */
#define ARCH_HAS_RELATIVE_EXTABLE 0

struct exception_table_entry {
	unsigned long insn;
	unsigned long fixup;
};

static inline void swap_ex_entry_fixup(struct exception_table_entry *a,
				       struct exception_table_entry *b,
				       struct exception_table_entry tmp,
				       int delta)
{
	a->insn = b->insn;
	a->fixup = b->fixup;
	b->insn = tmp.insn;
	b->fixup = tmp.fixup;
}

#endif /* _ASM_SUBLEQ_EXTABLE_H */
