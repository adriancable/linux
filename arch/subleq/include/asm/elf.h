/* SPDX-License-Identifier: GPL-2.0 */
/*
 * ELF definitions for Subleq
 */

#ifndef _ASM_SUBLEQ_ELF_H
#define _ASM_SUBLEQ_ELF_H

#include <asm/ptrace.h>

/*
 * ELF register state for core dumps
 */
typedef unsigned long elf_greg_t;

#define ELF_NGREG (sizeof(struct pt_regs) / sizeof(elf_greg_t))
typedef elf_greg_t elf_gregset_t[ELF_NGREG];

/* No FPU */
typedef unsigned long elf_fpregset_t;

/*
 * ELF class - 32-bit
 */
#define ELF_CLASS ELFCLASS32

/*
 * ELF data encoding - little endian
 */
#define ELF_DATA ELFDATA2LSB

/*
 * ELF machine type - use EM_NONE for now (custom arch)
 */
#define ELF_ARCH EM_NONE

/*
 * Memory map for this architecture
 */
#define ELF_PLAT_INIT(_r, load_addr) \
	do {                         \
	} while (0)

#define ELF_EXEC_PAGESIZE PAGE_SIZE

#define ELF_ET_DYN_BASE (TASK_SIZE / 3 * 2)

/* We don't really support core dumps yet */
#define ELF_CORE_COPY_REGS(dest, regs) \
	(void)memcpy(&(dest), (regs), sizeof(struct pt_regs))

#endif /* _ASM_SUBLEQ_ELF_H */
