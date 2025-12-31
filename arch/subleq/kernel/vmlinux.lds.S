/* SPDX-License-Identifier: GPL-2.0 */
/*
 * vmlinux.lds.S - Linker script for Subleq architecture
 *
 * This linker script defines how the kernel binary is laid out in memory.
 * Subleq is a NOMMU architecture with a simple memory model.
 *
 * Modeled after arch/microblaze/kernel/vmlinux.lds.S
 */

/* Exception table alignment - needed by RO_DATA macro */
#define RO_EXCEPTION_TABLE_ALIGN	16

#include <asm/page.h>
#include <asm/cache.h>
#include <asm/thread_info.h>
#include <asm-generic/vmlinux.lds.h>

/*
 * Use i386 output format since Subleq uses 32-bit words and this is
 * what the LLVM backend generates.
 */
OUTPUT_FORMAT("elf32-i386", "elf32-i386", "elf32-i386")
OUTPUT_ARCH(i386)
ENTRY(_start)

jiffies = jiffies_64;

SECTIONS
{
	/* Start at 4KB to leave room for boot area */
	. = 0x1000;

	_text = .;
	_stext = .;

	/* Text section */
	.text : AT(ADDR(.text) - LOAD_OFFSET) {
		HEAD_TEXT
		TEXT_TEXT
		SCHED_TEXT
		LOCK_TEXT
		KPROBES_TEXT
		IRQENTRY_TEXT
		SOFTIRQENTRY_TEXT
		*(.fixup)
		. = ALIGN(16);
		_etext = .;
	}

	/* Read-only data */
	. = ALIGN(16);
	RO_DATA(PAGE_SIZE)

	/* Read-write data - uses standard RW_DATA macro like microblaze */
	_sdata = .;
	RW_DATA(L1_CACHE_BYTES, PAGE_SIZE, THREAD_SIZE)
	_edata = .;

	/* Per-CPU data (minimal, we're single-CPU) */
	PERCPU_SECTION(L1_CACHE_BYTES)

	/* Init section - can be freed after boot */
	. = ALIGN(PAGE_SIZE);
	__init_begin = .;

	INIT_TEXT_SECTION(PAGE_SIZE)

	.init.data : AT(ADDR(.init.data) - LOAD_OFFSET) {
		INIT_DATA
	}

	.init.setup : AT(ADDR(.init.setup) - LOAD_OFFSET) {
		INIT_SETUP(16)
	}

	.initcall.init : AT(ADDR(.initcall.init) - LOAD_OFFSET) {
		INIT_CALLS
	}

	.con_initcall.init : AT(ADDR(.con_initcall.init) - LOAD_OFFSET) {
		CON_INITCALL
	}

	__init_end = .;

	/* BSS section - uninitialized data, zeroed at runtime */
	. = ALIGN(PAGE_SIZE);
	BSS_SECTION(0, 0, 0)

	_end = .;

	/* Debug sections */
	STABS_DEBUG
	DWARF_DEBUG
	ELF_DETAILS

	/* Sections to discard */
	DISCARDS
}
