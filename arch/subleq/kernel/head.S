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

	.section .text.head, "ax"
	.global _start
	.type _start, @function

_start:
	/*
	 * The boot sequence has already:
	 * 1. Set up the stack pointer at word 4 (byte 16)
	 * 2. Jumped to our entry point
	 *
	 * We need to:
	 * 1. Clear BSS
	 * 2. Call start_kernel()
	 * 3. Hang if we return (shouldn't happen)
	 *
	/*
	 * Jump to start_kernel - this never returns
	 * Subleq unconditional jump: subleq(Z, Z, target)
	 * Use ZERO constant at word address 6 (byte 24)
	 */
	.extern start_kernel
.Ljump_kernel:
	.word 24, 24, start_kernel

	/*
	 * If start_kernel returns, halt the machine.
	 * Use HALT instruction: subleq(-4, exit_code, -4)
	 *
	 * Exit code address at word 6 = byte 24 (ZERO constant = 0)
	 */
1:
	.word -4, 24, -4	/* HALT with exit code 0 */

	.size _start, . - _start

/*
 * Empty zero page - required by some kernel code.
 * Must be in .data..page_aligned so it gets merged with main .data section.
 */
	.section ".data..page_aligned", "aw"
	.align 4096
	.global empty_zero_page
empty_zero_page:
	.fill 4096, 1, 0

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
