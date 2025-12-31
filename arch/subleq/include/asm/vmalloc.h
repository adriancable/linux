/* SPDX-License-Identifier: GPL-2.0 */
/*
 * vmalloc support for Subleq
 *
 * NOMMU - vmalloc is just regular allocation
 */

#ifndef _ASM_SUBLEQ_VMALLOC_H
#define _ASM_SUBLEQ_VMALLOC_H

#include <asm/pgtable.h>

/*
 * NOMMU: No virtual memory, so vmalloc space is just the
 * physical address space.
 */
#define VMALLOC_START 0UL
#define VMALLOC_END 0xffffffffUL

/* Align vmalloc area on module boundary */
#define VMALLOC_MODULE_START VMALLOC_START
#define VMALLOC_MODULE_END VMALLOC_END

#endif /* _ASM_SUBLEQ_VMALLOC_H */
