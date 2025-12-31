// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq memory initialization
 */

#include <linux/init.h>
#include <linux/mm.h>
#include <linux/memblock.h>

#include <asm/page.h>
#include <asm/sections.h>
#include <asm/setup.h>

/*
 * Memory initialization for NOMMU kernel
 */

unsigned long max_mapnr;
unsigned long max_low_pfn;
unsigned long min_low_pfn;

/* Empty zero page for NOMMU */
void *empty_zero_page;

/*
 * Memory map - we have a simple flat memory model
 */
void __init mem_init(void)
{
	max_mapnr = PFN_DOWN(subleq_memory_end);
	max_low_pfn = max_mapnr;
	min_low_pfn = PFN_UP(subleq_memory_start);

	/*
	 * For NOMMU, the memory is already available.
	 * Just report memory stats.
	 */
	pr_info("Memory: %luK available\n",
		(subleq_memory_end - subleq_memory_start) >> 10);
}

/*
 * Free memory from initrd etc.
 */
void free_initmem(void)
{
	/* Nothing to free */
}
