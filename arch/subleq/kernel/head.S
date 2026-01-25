/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Subleq kernel entry point
 *
 * This file contains the boot code in raw Subleq assembly.
 * Written using .word directives since Subleq has no named instructions.
 *
 * Memory layout when we enter:
 *   - SP is initialized by boot sequence (at ~1GB)
 *   - PC starts at _start (0x1000 by default)
 *   - Interrupts are disabled (m[0] = 0)
 */

	.section .init.text, "ax"
	.global _start
	.type _start, @function

/* Register addresses */
.set REG_Z, 12
.set REG_SP, 16

/* Thread size = PAGE_SIZE (must match asm/page.h PAGE_SHIFT=14 -> 16KB) */
.set THREAD_SIZE, 16384

_start:
	/*
	 * The boot sequence has already:
	 * 1. Set up a temporary stack pointer at word 4 (byte 16)
	 * 2. Jumped to our entry point
	 *
	 * We need to:
	 * 1. Switch to the init_task's kernel stack (CRITICAL!)
	 * 2. Jump to subleq_start which then:
	 *    a. Clears BSS
	 *    b. Calls start_kernel()
	 *
	 * The boot stack from make_boot_image.py must NOT be used after this
	 * point - it may overlap with kernel memory.
	 */

	/*
	 * Switch SP to init_thread_union + THREAD_SIZE
	 * This is the proper kernel stack for the init task.
	 *
	 * Algorithm:
	 *   Z = 0
	 *   Z = -(.Linit_stack_top)  ; load negated value
	 *   SP = 0
	 *   SP = SP - Z = init_stack_top
	 */
	.word   REG_Z, REG_Z, .Lsetup_sp1	/* Z = 0 */
.Lsetup_sp1:
	.word   .Linit_stack_top, REG_Z, .Lsetup_sp2	/* Z = -(init_stack_top) */
.Lsetup_sp2:
	.word   REG_SP, REG_SP, .Lsetup_sp3	/* SP = 0 */
.Lsetup_sp3:
	.word   REG_Z, REG_SP, .Ljump_start	/* SP = 0 - (-init_stack_top) = init_stack_top */

	/*
	 * Now jump to subleq_start with the proper kernel stack
	 */
	.extern subleq_start
.Ljump_start:
	.word 144, 144, subleq_start

	/*
	 * If subleq_start somehow returns, halt the machine.
	 */
1:
	.word -4, 144, -4	/* HALT with exit code 0 */

	.size _start, . - _start

/*
 * Constant: address of top of init_task's kernel stack
 * This is init_thread_union + THREAD_SIZE
 */
.Linit_stack_top:
	.word init_thread_union + THREAD_SIZE



/*
 * Note: empty_zero_page is allocated dynamically in arch/subleq/mm/init.c
 * via memblock_alloc() during paging_init().
 */

/*
 * init_stack/init_thread_union symbol definitions.
 *
 * These symbols are defined here in assembly rather than relying on
 * linker script symbols because LLD has issues with `. = symbol` syntax
 * in linker scripts, sometimes placing symbols in orphan sections.
 *
 * By defining strong symbols in the .data..init_thread_info section,
 * we ensure they get the correct address in the .data section.
 */
	.section ".data..init_thread_info", "aw"
	.align 4

	.global init_stack
	.global init_thread_union
	.global __start_init_stack
	.type init_stack, @object
	.type init_thread_union, @object

__start_init_stack:
init_stack:
init_thread_union:
	/* 
	 * The init_thread_info structure (16 bytes) from init_task.c 
	 * follows here - it's also placed in .data..init_thread_info.
	 * The linker will concatenate our empty definition with init_task.c's data.
	 */
