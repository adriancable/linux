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

_start:
	/*
	 * The boot sequence has already:
	 * 1. Set up the stack pointer at word 4 (byte 16)
	 * 2. Jumped to our entry point
	 *
	 * We need to:
	 * 1. Clear BSS (done in subleq_start)
	 * 2. Call start_kernel() (done in subleq_start)
	 * 3. Hang if we return (shouldn't happen)
	 *
	 * We jump to subleq_start() which is a simple C function that:
	 * 1. Calls clear_bss()
	 * 2. Calls start_kernel()
	 *
	 * Since start_kernel() never returns, we don't need a proper
	 * call/return setup - just a simple jump.
	 */
	.extern subleq_start
.Ljump_start:
	.word 24, 24, subleq_start

	/*
	 * If subleq_start somehow returns, halt the machine.
	 */
1:
	.word -4, 24, -4	/* HALT with exit code 0 */

	.size _start, . - _start

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
