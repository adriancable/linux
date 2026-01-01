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
 * 
 * For NOMMU kernels, we need to:
 * 1. Set up high_memory pointer
 * 2. Allocate empty_zero_page
 * 3. Initialize memory zones via free_area_init()
 *
 * empty_zero_page is declared in pgtable.h but allocated here.
 */

/* Allocate the zero page from memblock */
void *empty_zero_page;

/*
 * paging_init - Set up memory zones for NOMMU kernel
 *
 * This must be called from setup_arch() to initialize the zone
 * allocator before mm_core_init() runs. Without this, the kernel
 * will report "Total pages: 0" and SLUB allocation will fail.
 */
void __init paging_init(void)
{
	unsigned long end_mem = subleq_memory_end & PAGE_MASK;
	unsigned long max_zone_pfn[MAX_NR_ZONES] = {
		0,
	};

	/* Set high_memory to end of physical memory */
	high_memory = (void *)end_mem;

	/* Allocate the zero page */
	empty_zero_page = memblock_alloc(PAGE_SIZE, PAGE_SIZE);
	if (!empty_zero_page)
		panic("Failed to allocate empty_zero_page\n");
	memset(empty_zero_page, 0, PAGE_SIZE);

	/* Set up min/max PFNs */
	min_low_pfn = PFN_UP(subleq_memory_start);
	max_low_pfn = PFN_DOWN(end_mem);
	max_mapnr = max_low_pfn;

	/*
	 * For NOMMU, all memory is in ZONE_NORMAL.
	 * This tells the zone allocator about our available memory.
	 */
	max_zone_pfn[ZONE_NORMAL] = max_low_pfn;

	/* Initialize memory zones - this is critical! */
	free_area_init(max_zone_pfn);
}

/*
 * mem_init - Final memory initialization
 *
 * Called after zone setup is complete.
 */
void __init mem_init(void)
{
	/* Memory stats are now printed by generic code */
}

/*
 * Free memory from initrd etc.
 */
void free_initmem(void)
{
	/* Nothing to free */
}
