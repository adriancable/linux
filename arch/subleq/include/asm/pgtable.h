/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Page table definitions for Subleq
 *
 * NOMMU - no page tables.
 */

#ifndef _ASM_SUBLEQ_PGTABLE_H
#define _ASM_SUBLEQ_PGTABLE_H

#include <asm-generic/pgtable-nopud.h>
#include <asm-generic/pgtable-nopmd.h>

/* No page tables */
#define pgd_none(pgd) (1)
#define pgd_bad(pgd) (0)
#define pgd_present(pgd) (0)
#define pgd_clear(pgdp) \
	do {            \
	} while (0)

#define pte_none(pte) (1)
#define pte_present(pte) (0)
#define pte_clear(mm, addr, ptep) \
	do {                      \
	} while (0)

#define kern_addr_valid(addr) (1)
#define pte_pfn(pte) (0)

/* Protection values - unused but needed for compilation */
#define PAGE_NONE __pgprot(0)
#define PAGE_SHARED __pgprot(0)
#define PAGE_COPY __pgprot(0)
#define PAGE_READONLY __pgprot(0)
#define PAGE_KERNEL __pgprot(0)

#define __P000 PAGE_NONE
#define __P001 PAGE_READONLY
#define __P010 PAGE_COPY
#define __P011 PAGE_COPY
#define __P100 PAGE_READONLY
#define __P101 PAGE_READONLY
#define __P110 PAGE_COPY
#define __P111 PAGE_COPY

#define __S000 PAGE_NONE
#define __S001 PAGE_READONLY
#define __S010 PAGE_SHARED
#define __S011 PAGE_SHARED
#define __S100 PAGE_READONLY
#define __S101 PAGE_READONLY
#define __S110 PAGE_SHARED
#define __S111 PAGE_SHARED

/* Stubs for NOMMU */
#define swapper_pg_dir ((pgd_t *)0)

/*
 * ZERO_PAGE - a global shared page that is always zero
 */
extern void *empty_zero_page;
#define ZERO_PAGE(vaddr) (virt_to_page(empty_zero_page))

#endif /* _ASM_SUBLEQ_PGTABLE_H */
