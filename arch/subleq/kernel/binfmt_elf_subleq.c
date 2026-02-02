// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq ELF binary format handler for NOMMU systems
 *
 * This is a simplified ELF loader for Subleq that:
 * 1. Loads ET_DYN (PIE / Position Independent Executable) ELF binaries ONLY
 * 2. Supports shared libraries loaded from /lib/
 * 3. Performs relocations at load time (.rel.dyn with R_386_RELATIVE/R_386_32)
 *
 * ET_EXEC binaries are rejected (return -ENOEXEC) as the Subleq toolchain
 * now produces only PIE executables. This simplifies the loader by
 * eliminating the --emit-relocs / .rel.text code path.
 *
 * Based on binfmt_elf_fdpic.c's NOMMU code path.
 */

#include <linux/module.h>
#include <linux/fs.h>
#include <linux/stat.h>
#include <linux/sched.h>
#include <linux/sched/task_stack.h>
#include <linux/mm.h>
#include <linux/mman.h>
#include <linux/errno.h>
#include <linux/signal.h>
#include <linux/binfmts.h>
#include <linux/string.h>
#include <linux/file.h>
#include <linux/slab.h>
#include <linux/personality.h>
#include <linux/init.h>
#include <linux/elf.h>
#include <linux/uaccess.h>
#include <linux/sort.h>
#include <linux/mutex.h>

#include <asm/param.h>
#include <asm/ptrace.h>
#include <asm/processor.h>
#include <asm/current.h>

/* ELF relocation types for i386 */
#ifndef R_386_32
#define R_386_32 1 /* Absolute 32-bit address */
#endif
/* R_386_COPY (5) and R_386_JUMP_SLOT (7) are not used.
 * The toolchain uses -z notext for direct R_386_32 relocations.
 */
#ifndef R_386_RELATIVE
#define R_386_RELATIVE 8 /* Adjust by load base (for shared libs) */
#endif

/*
 * RELR - Packed Relative Relocations (ELF gABI extension)
 * High-efficiency encoding for R_*_RELATIVE relocations.
 * Can achieve 90-98% space savings over REL format.
 */
#ifndef SHT_RELR
#define SHT_RELR 19 /* Packed relative relocations */
#endif
#ifndef DT_RELR
#define DT_RELR 36    /* Address of RELR relocations */
#define DT_RELRSZ 35  /* Size of RELR relocations in bytes */
#define DT_RELRENT 37 /* Size of one RELR entry */
#endif

#define SUBLEQ_ELF_DEBUG 0

#if SUBLEQ_ELF_DEBUG
#define subleq_elf_debug(fmt, ...) \
	pr_info("SUBLEQ_ELF: " fmt "\n", ##__VA_ARGS__)
#else
#define subleq_elf_debug(fmt, ...) \
	do {                       \
	} while (0)
#endif

/*
 * Check if a symbol needs external resolution.
 * Returns 1 for undefined symbols that need to be resolved by the kernel
 * runtime or other loaded libraries.
 * Returns 0 for defined symbols or file symbols.
 */
static inline int symbol_needs_resolution(const struct elf32_sym *sym)
{
	/* STT_FILE = 4, stored in low nibble of st_info */
	if ((sym->st_info & 0xf) == 4)
		return 0;
	/* SHN_UNDEF = 0: undefined symbols needing kernel/library resolution */
	return sym->st_shndx == SHN_UNDEF && sym->st_name != 0;
}

/* Maximum length of library path */
#define MAX_LIB_PATH 256

/* Maximum number of DT_NEEDED libraries */
#define MAX_NEEDED_LIBS 8

/* Information about a loaded ELF segment */
struct elf_load_info {
	unsigned long load_addr; /* Where the ELF was loaded */
	unsigned long
		base_vaddr; /* Original link address (first PT_LOAD vaddr) */
	unsigned long entry_addr; /* Entry point address */
	unsigned long stack_size; /* Requested stack size */
	unsigned long total_size; /* Total memory size needed */
};

/*
 * Kernel runtime symbols - these are built into the kernel and can be
 * resolved directly without loading a shared library.
 */
extern void __ashldi3(void);
extern void __ashrdi3(void);
extern void __divdi3(void);
extern void __lshrdi3(void);
extern void __moddi3(void);
extern void __subleq_and(void);
extern void __subleq_lb(void);
extern void __subleq_lh(void);
extern void __subleq_mul(void);
extern void __subleq_or(void);
extern void __subleq_sb(void);
extern void __subleq_sdivrem(void);
extern void __subleq_sdivrem64(void);
extern void __subleq_sh(void);
extern void __subleq_shl(void);
extern void __subleq_sra(void);
extern void __subleq_srl(void);
extern void __subleq_udivrem(void);
extern void __subleq_udivrem64(void);
extern void __subleq_xor(void);
extern void __udivdi3(void);
extern void __umoddi3(void);
extern void __subleq_memcpy(void);
extern void __subleq_memset(void);
extern void __subleq_memmove(void);
/* __subleq_syscall declared in asm/ptrace.h as char[] for address range checking */

/* Soft float functions (from subleq_runtime_softfloat.c) */
/* Double-precision arithmetic */
extern void __adddf3(void);
extern void __subdf3(void);
extern void __muldf3(void);
extern void __divdf3(void);
/* Single-precision arithmetic */
extern void __addsf3(void);
extern void __subsf3(void);
extern void __mulsf3(void);
extern void __divsf3(void);
/* Double-precision comparisons */
extern void __eqdf2(void);
extern void __nedf2(void);
extern void __ledf2(void);
extern void __gedf2(void);
extern void __ltdf2(void);
extern void __gtdf2(void);
extern void __unorddf2(void);
/* Single-precision comparisons */
extern void __eqsf2(void);
extern void __nesf2(void);
extern void __lesf2(void);
extern void __gesf2(void);
extern void __ltsf2(void);
extern void __gtsf2(void);
extern void __unordsf2(void);
/* Double to int conversions */
extern void __fixdfsi(void);
extern void __fixdfdi(void);
extern void __fixunsdfsi(void);
extern void __fixunsdfdi(void);
/* Single to int conversions */
extern void __fixsfsi(void);
extern void __fixsfdi(void);
extern void __fixunssfsi(void);
extern void __fixunssfdi(void);
/* Int to double conversions */
extern void __floatsidf(void);
extern void __floatdidf(void);
extern void __floatunsidf(void);
extern void __floatundidf(void);
/* Int to single conversions */
extern void __floatsisf(void);
extern void __floatdisf(void);
extern void __floatunsisf(void);
extern void __floatundisf(void);
/* Precision conversions */
extern void __extendsfdf2(void);
extern void __truncdfsf2(void);
/* Complex arithmetic */
extern void __mulsc3(void);
extern void __divsc3(void);
extern void __muldc3(void);
extern void __divdc3(void);



/*
 * Kernel runtime symbols - SORTED ALPHABETICALLY for binary search.
 * IMPORTANT: When adding new symbols, maintain alphabetical order!
 */
static const struct {
	const char *name;
	void *addr;
} kernel_runtime_symbols[] = {
	{ "__adddf3", &__adddf3 },
	{ "__addsf3", &__addsf3 },
	{ "__ashldi3", &__ashldi3 },
	{ "__ashrdi3", &__ashrdi3 },
	{ "__divdc3", &__divdc3 },
	{ "__divdf3", &__divdf3 },
	{ "__divdi3", &__divdi3 },
	{ "__divsc3", &__divsc3 },
	{ "__divsf3", &__divsf3 },
	{ "__eqdf2", &__eqdf2 },
	{ "__eqsf2", &__eqsf2 },
	{ "__extendsfdf2", &__extendsfdf2 },
	{ "__fixdfdi", &__fixdfdi },
	{ "__fixdfsi", &__fixdfsi },
	{ "__fixsfdi", &__fixsfdi },
	{ "__fixsfsi", &__fixsfsi },
	{ "__fixunsdfdi", &__fixunsdfdi },
	{ "__fixunsdfsi", &__fixunsdfsi },
	{ "__fixunssfdi", &__fixunssfdi },
	{ "__fixunssfsi", &__fixunssfsi },
	{ "__floatdidf", &__floatdidf },
	{ "__floatdisf", &__floatdisf },
	{ "__floatsidf", &__floatsidf },
	{ "__floatsisf", &__floatsisf },
	{ "__floatundidf", &__floatundidf },
	{ "__floatundisf", &__floatundisf },
	{ "__floatunsidf", &__floatunsidf },
	{ "__floatunsisf", &__floatunsisf },
	{ "__gedf2", &__gedf2 },
	{ "__gesf2", &__gesf2 },
	{ "__gtdf2", &__gtdf2 },
	{ "__gtsf2", &__gtsf2 },
	{ "__ledf2", &__ledf2 },
	{ "__lesf2", &__lesf2 },
	{ "__lshrdi3", &__lshrdi3 },
	{ "__ltdf2", &__ltdf2 },
	{ "__ltsf2", &__ltsf2 },
	{ "__moddi3", &__moddi3 },
	{ "__muldc3", &__muldc3 },
	{ "__muldf3", &__muldf3 },
	{ "__mulsc3", &__mulsc3 },
	{ "__mulsf3", &__mulsf3 },
	{ "__nedf2", &__nedf2 },
	{ "__nesf2", &__nesf2 },
	{ "__subdf3", &__subdf3 },
	{ "__subleq_and", &__subleq_and },
	{ "__subleq_lb", &__subleq_lb },
	{ "__subleq_lh", &__subleq_lh },
	{ "__subleq_memcpy", &__subleq_memcpy },
	{ "__subleq_memmove", &__subleq_memmove },
	{ "__subleq_memset", &__subleq_memset },
	{ "__subleq_mul", &__subleq_mul },
	{ "__subleq_or", &__subleq_or },
	{ "__subleq_sb", &__subleq_sb },
	{ "__subleq_sdivrem", &__subleq_sdivrem },
	{ "__subleq_sdivrem64", &__subleq_sdivrem64 },
	{ "__subleq_sh", &__subleq_sh },
	{ "__subleq_shl", &__subleq_shl },
	{ "__subleq_sra", &__subleq_sra },
	{ "__subleq_srl", &__subleq_srl },
	{ "__subleq_syscall", &__subleq_syscall },
	{ "__subleq_udivrem", &__subleq_udivrem },
	{ "__subleq_udivrem64", &__subleq_udivrem64 },
	{ "__subleq_xor", &__subleq_xor },
	{ "__subsf3", &__subsf3 },
	{ "__truncdfsf2", &__truncdfsf2 },
	{ "__udivdi3", &__udivdi3 },
	{ "__umoddi3", &__umoddi3 },
	{ "__unorddf2", &__unorddf2 },
	{ "__unordsf2", &__unordsf2 },
};

#define KERNEL_RUNTIME_SYMBOL_COUNT \
	(sizeof(kernel_runtime_symbols) / sizeof(kernel_runtime_symbols[0]))

/*
 * Hash table for library symbols - O(1) lookup, no sorting needed.
 * Uses FNV-1a hash with open addressing (linear probing).
 * Table size is power of 2 for fast modulo via bitmask.
 */
#define LIBSRT_HASH_SIZE 8192  /* Must be power of 2, > 2x max symbols */
#define LIBSRT_HASH_MASK (LIBSRT_HASH_SIZE - 1)
#define MAX_LOADED_LIBS 16

struct libsrt_hash_entry {
	char name[64];
	unsigned long addr;
	int occupied;  /* 0 = empty, 1 = used */
};

/*
 * State for the current ELF load operation.
 * Eliminates global state to allow re-entrant concurrent loading.
 */
struct libsrt_state {
	struct libsrt_hash_entry *hash;
	int symbol_count;
	unsigned long libsrt_load_addr;
	/* Track which libraries have been loaded */
	struct {
		char name[64];
		unsigned long load_addr;
		unsigned long base_vaddr;
		struct file *file;       /* For deferred relocation processing */
		struct elfhdr hdr;       /* For deferred relocation processing */
		struct elf_shdr *shdrs;  /* Cached section headers */
		int relocs_applied;
	} loaded_libs[MAX_LOADED_LIBS];
	int loaded_lib_count;
};

/*
 * FNV-1a hash function - fast and good distribution for strings.
 */
static inline unsigned int fnv1a_hash(const char *str)
{
	unsigned int hash = 2166136261u;  /* FNV offset basis */
	while (*str) {
		hash ^= (unsigned char)*str++;
		hash *= 16777619u;  /* FNV prime */
	}
	return hash;
}

/*
 * Returns 1 on success, 0 if table full or duplicate.
 */
static int libsrt_hash_insert(struct libsrt_state *state, const char *name, unsigned long addr)
{
	unsigned int hash = fnv1a_hash(name);
	unsigned int idx = hash & LIBSRT_HASH_MASK;
	int probes = 0;

	while (probes < LIBSRT_HASH_SIZE) {
		if (!state->hash[idx].occupied) {
			/* Empty slot - insert here */
			strscpy(state->hash[idx].name, name,
				sizeof(state->hash[idx].name));
			state->hash[idx].addr = addr;
			state->hash[idx].occupied = 1;
			state->symbol_count++;
			return 1;
		}
		if (strcmp(state->hash[idx].name, name) == 0) {
			/* Duplicate - already exists */
			return 0;
		}
		/* Linear probing */
		idx = (idx + 1) & LIBSRT_HASH_MASK;
		probes++;
	}
	/* Table full - shouldn't happen with proper sizing */
	return 0;
}

/*
 * Lookup symbol in hash table.
 * Returns address or 0 if not found.
 */
static unsigned long libsrt_hash_lookup(struct libsrt_state *state, const char *name)
{
	unsigned int hash = fnv1a_hash(name);
	unsigned int idx = hash & LIBSRT_HASH_MASK;
	int probes = 0;

	while (probes < LIBSRT_HASH_SIZE && state->hash[idx].occupied) {
		if (strcmp(state->hash[idx].name, name) == 0)
			return state->hash[idx].addr;
		idx = (idx + 1) & LIBSRT_HASH_MASK;
		probes++;
	}
	return 0;  /* Not found */
}

/* Track which libraries have been loaded to avoid duplicates.
 * Also stores file/header info for deferred relocation processing (two-pass). */
#define MAX_LOADED_LIBS 16
/* Check if a library has already been loaded. Returns load_addr or 0 if not. */
static unsigned long find_loaded_lib(struct libsrt_state *state, const char *name)
{
	int i;
	for (i = 0; i < state->loaded_lib_count; i++) {
		if (strcmp(state->loaded_libs[i].name, name) == 0)
			return state->loaded_libs[i].load_addr;
	}
	return 0;
}

/* Record that a library has been loaded (for deferred relocation) */
static void record_loaded_lib(struct libsrt_state *state, const char *name, unsigned long load_addr,
			      unsigned long base_vaddr, struct file *file,
			      struct elfhdr *hdr)
{
	if (state->loaded_lib_count < MAX_LOADED_LIBS) {
		strscpy(state->loaded_libs[state->loaded_lib_count].name, name,
			sizeof(state->loaded_libs[0].name));
		state->loaded_libs[state->loaded_lib_count].load_addr = load_addr;
		state->loaded_libs[state->loaded_lib_count].base_vaddr = base_vaddr;
		state->loaded_libs[state->loaded_lib_count].file = file;
		state->loaded_libs[state->loaded_lib_count].hdr = *hdr;
		state->loaded_libs[state->loaded_lib_count].shdrs = NULL;  /* Will be populated by process_relocations_and_symbols */
		state->loaded_libs[state->loaded_lib_count].relocs_applied = 0;
		state->loaded_lib_count++;
	}
}

/*
 * Look up a symbol in kernel runtime symbols using binary search.
 * The kernel_runtime_symbols table MUST be sorted alphabetically.
 * Returns the address or 0 if not found.
 */
static unsigned long lookup_kernel_symbol(const char *name)
{
	int low = 0;
	int high = KERNEL_RUNTIME_SYMBOL_COUNT - 1;

	while (low <= high) {
		int mid = low + (high - low) / 2;
		int cmp = strcmp(kernel_runtime_symbols[mid].name, name);

		if (cmp == 0)
			return (unsigned long)kernel_runtime_symbols[mid].addr;
		else if (cmp < 0)
			low = mid + 1;
		else
			high = mid - 1;
	}
	return 0;
}

/*
 * Look up a symbol - check kernel runtime symbols first (binary search),
 * then loaded libraries (hash table lookup - O(1) average).
 * Returns the address or 0 if not found.
 */
static unsigned long lookup_libsrt_symbol(struct libsrt_state *state, const char *name)
{
	unsigned long addr;

	/* Binary search in sorted kernel runtime symbols - O(log n) */
	addr = lookup_kernel_symbol(name);
	if (addr)
		return addr;

	/* Hash table lookup in library symbols - O(1) average */
	return libsrt_hash_lookup(state, name);
}


static int load_elf_subleq_binary(struct linux_binprm *bprm);

/*
 * Process RELR (Packed Relative Relocations) section.
 *
 * RELR is a highly efficient encoding for R_*_RELATIVE relocations.
 * Each entry is either:
 *   - An address (LSB = 0): Apply one relocation at this offset
 *   - A bitmap (LSB = 1): Apply up to 31 relocations at subsequent offsets
 *
 * The bitmap works as follows:
 *   - Remove the LSB marker (shift right by 1)
 *   - Each set bit represents a relocation at (base + bit_position * 4)
 *   - After processing, base advances by 31 * 4 = 124 bytes
 *
 * IMPORTANT: RELR entries contain virtual addresses (r_offset), which must
 * be converted to actual memory addresses by: load_addr + (vaddr - base_vaddr)
 *
 * Returns number of relocations applied.
 */
static int process_relr_section(u32 *relr_data, size_t relr_size,
				unsigned long load_addr,
				unsigned long base_vaddr,
				unsigned long load_offset)
{
	size_t nentries = relr_size / sizeof(u32);
	size_t i;
	u32 base = 0;
	int relocs_applied = 0;

	for (i = 0; i < nentries; i++) {
		u32 entry = relr_data[i];

		if ((entry & 1) == 0) {
			/* Address entry: relocate this single location */
			u32 *patch_addr = (u32 *)(load_addr + (entry - base_vaddr));
			u32 old_val = *patch_addr;
			*patch_addr += load_offset;

			relocs_applied++;
			/* Set base for subsequent bitmaps */
			base = entry + 4;
		} else {
			/* Bitmap entry: decode up to 31 relocations */
			u32 bitmap = entry >> 1;
			int j;

			for (j = 0; bitmap != 0; j++, bitmap >>= 1) {
				if (bitmap & 1) {
					u32 offset = base + j * 4;
					u32 *patch_addr = (u32 *)(load_addr + (offset - base_vaddr));
					u32 old_val = *patch_addr;
					*patch_addr += load_offset;

					relocs_applied++;
				}
			}
			/* Advance base by bitmap span (31 words = 124 bytes) */
			base += 31 * 4;
		}
	}

	return relocs_applied;
}

static struct linux_binfmt elf_subleq_format = {
	.module = THIS_MODULE,
	.load_binary = load_elf_subleq_binary,
};

/*
 * Check if this is a Subleq ELF binary
 */
static int is_subleq_elf(struct elfhdr *hdr, struct file *file)
{
	if (memcmp(hdr->e_ident, ELFMAG, SELFMAG) != 0)
		return 0;
	if (hdr->e_ident[EI_CLASS] != ELFCLASS32)
		return 0;
	/*
	 * ONLY accept ET_DYN (PIE/shared library) binaries.
	 * ET_EXEC binaries are no longer supported - the toolchain now
	 * produces only PIE executables. Rejecting ET_EXEC causes shells
	 * to display "cannot execute binary file" error.
	 */
	if (hdr->e_type != ET_DYN)
		return 0;
	/* Subleq ELF binaries use EM_SUBLEQ */
	if (hdr->e_machine != EM_SUBLEQ)
		return 0;
	return 1;
}

/*
 * Structure to hold library name extracted from DT_NEEDED
 * and the load address after loading
 */
struct needed_lib {
	char name[64];
	unsigned long load_addr; /* Filled in after loading */
};

/*
 * Extract DT_NEEDED library names from PT_DYNAMIC segment
 * Returns the number of libraries found (stored in libs array)
 *
 * If phdrs_out and phnum_out are non-NULL, the program headers are returned
 * to the caller instead of being freed. Caller must kfree(*phdrs_out).
 */
static int get_elf_needed_libs(struct file *file, struct elfhdr *hdr,
			       struct needed_lib *libs, int max_libs,
			       struct elf_phdr **phdrs_out, int *phnum_out)
{
	struct elf_phdr *phdrs = NULL, *phdr;
	Elf32_Dyn *dyns = NULL, *dyn;
	char *strtab = NULL;
	unsigned long strtab_addr = 0;
	unsigned long strtab_size = 0;
	unsigned long strtab_file_offset = 0;
	unsigned long dyn_offset = 0;
	unsigned long dyn_size = 0;
	unsigned long load_vaddr = 0;
	unsigned long load_offset = 0;
	loff_t pos;
	ssize_t ret;
	int i, nlibs = 0;
	int ndyns;

	/* Read program headers */
	if (hdr->e_phentsize != sizeof(struct elf_phdr))
		return 0;
	if (hdr->e_phnum > 65536 / sizeof(struct elf_phdr))
		return 0;

	phdrs = kmalloc_array(hdr->e_phnum, sizeof(struct elf_phdr),
			      GFP_KERNEL);
	if (!phdrs)
		return 0;

	pos = hdr->e_phoff;
	ret = kernel_read(file, phdrs, hdr->e_phnum * sizeof(struct elf_phdr),
			  &pos);
	if (ret != hdr->e_phnum * sizeof(struct elf_phdr)) {
		kfree(phdrs);
		return 0;
	}

	/* Find PT_DYNAMIC and PT_LOAD segments */
	int found_load = 0;
	for (i = 0, phdr = phdrs; i < hdr->e_phnum; i++, phdr++) {
		if (phdr->p_type == PT_DYNAMIC) {
			dyn_offset = phdr->p_offset;
			dyn_size = phdr->p_filesz;
		}
		if (phdr->p_type == PT_LOAD && !found_load) {
			/* First PT_LOAD segment - use for vaddr to file offset conversion */
			load_vaddr = phdr->p_vaddr;
			load_offset = phdr->p_offset;
			found_load = 1;
		}
	}

	/* Return phdrs to caller if requested, otherwise free */
	if (phdrs_out && phnum_out) {
		*phdrs_out = phdrs;
		*phnum_out = hdr->e_phnum;
	} else {
		kfree(phdrs);
	}

	if (dyn_size == 0) {
		subleq_elf_debug("No PT_DYNAMIC segment found");
		return 0; /* No dynamic section */
	}

	/* Read dynamic section */
	if (dyn_size > 4096) /* Sanity check */
		dyn_size = 4096;

	dyns = kmalloc(dyn_size, GFP_KERNEL);
	if (!dyns)
		return 0;

	pos = dyn_offset;
	ret = kernel_read(file, dyns, dyn_size, &pos);
	if (ret != dyn_size) {
		kfree(dyns);
		return 0;
	}

	ndyns = dyn_size / sizeof(Elf32_Dyn);

	/* First pass: find DT_STRTAB and DT_STRSZ */
	for (i = 0, dyn = dyns; i < ndyns; i++, dyn++) {
		if (dyn->d_tag == DT_NULL)
			break;
		if (dyn->d_tag == DT_STRTAB)
			strtab_addr = dyn->d_un.d_ptr;
		if (dyn->d_tag == DT_STRSZ)
			strtab_size = dyn->d_un.d_val;
	}

	if (strtab_size == 0 || strtab_size > 4096) {
		kfree(dyns);
		subleq_elf_debug("No DT_STRTAB or invalid size");
		return 0;
	}

	/* Convert virtual address to file offset using PT_LOAD segment info
	 * file_offset = vaddr - p_vaddr + p_offset
	 */
	strtab_file_offset = strtab_addr - load_vaddr + load_offset;
	subleq_elf_debug("DT_STRTAB vaddr=0x%lx -> file offset=0x%lx",
			 strtab_addr, strtab_file_offset);

	/* Read string table */
	strtab = kmalloc(strtab_size, GFP_KERNEL);
	if (!strtab) {
		kfree(dyns);
		return 0;
	}

	pos = strtab_file_offset;
	ret = kernel_read(file, strtab, strtab_size, &pos);
	if (ret != strtab_size) {
		kfree(strtab);
		kfree(dyns);
		return 0;
	}

	/* Second pass: extract DT_NEEDED library names */
	for (i = 0, dyn = dyns; i < ndyns && nlibs < max_libs; i++, dyn++) {
		if (dyn->d_tag == DT_NULL)
			break;
		if (dyn->d_tag == DT_NEEDED) {
			unsigned long name_offset = dyn->d_un.d_val;
			if (name_offset < strtab_size) {
				strscpy(libs[nlibs].name, strtab + name_offset,
					sizeof(libs[0].name));
				subleq_elf_debug("DT_NEEDED: %s",
						 libs[nlibs].name);
				nlibs++;
			}
		}
	}

	kfree(strtab);
	kfree(dyns);
	return nlibs;
}

/*
 * Load an ELF binary into memory
 * If phdrs_in is non-NULL, use the pre-read program headers instead of
 * reading them again. The caller retains ownership (no free here).
 * Returns 0 on success or negative error.
 */
static long load_elf_segments(struct file *file, struct elfhdr *hdr,
			      struct elf_load_info *info,
			      struct elf_phdr *phdrs_in, int phnum_in)
{
	struct elf_phdr *phdrs = NULL, *phdr;
	unsigned long total_size = 0;
	unsigned long min_addr = ULONG_MAX;
	unsigned long max_addr = 0;
	unsigned long load_addr;
	loff_t pos;
	int i, nloads = 0, phnum;
	ssize_t ret;
	int own_phdrs = 0; /* Track if we allocated phdrs and need to free */

	/* Use pre-read program headers if provided, otherwise read them */
	if (phdrs_in && phnum_in > 0) {
		phdrs = phdrs_in;
		phnum = phnum_in;
	} else {
		/* Read program headers */
		if (hdr->e_phentsize != sizeof(struct elf_phdr))
			return -ENOEXEC;
		if (hdr->e_phnum > 65536 / sizeof(struct elf_phdr))
			return -ENOEXEC;

		phdrs = kmalloc_array(hdr->e_phnum, sizeof(struct elf_phdr),
				      GFP_KERNEL);
		if (!phdrs)
			return -ENOMEM;

		pos = hdr->e_phoff;
		ret = kernel_read(file, phdrs, hdr->e_phnum * sizeof(struct elf_phdr),
				  &pos);
		if (ret != hdr->e_phnum * sizeof(struct elf_phdr)) {
			kfree(phdrs);
			return ret < 0 ? ret : -EIO;
		}
		phnum = hdr->e_phnum;
		own_phdrs = 1;
	}

	/* Calculate total memory needed and find min/max addresses */
	for (i = 0, phdr = phdrs; i < phnum; i++, phdr++) {
		if (phdr->p_type == PT_LOAD) {
			unsigned long end = phdr->p_vaddr + phdr->p_memsz;
			if (phdr->p_vaddr < min_addr)
				min_addr = phdr->p_vaddr;
			if (end > max_addr)
				max_addr = end;
			nloads++;
		}
		if (phdr->p_type == PT_GNU_STACK) {
			info->stack_size = phdr->p_memsz;
		}
	}

	if (nloads == 0) {
		if (own_phdrs)
			kfree(phdrs);
		return -ENOEXEC;
	}

	total_size = max_addr - min_addr;
	total_size = PAGE_ALIGN(total_size);

	subleq_elf_debug("Loading ELF: %d segments, size=%lu", nloads,
			 total_size);

	/* Allocate memory for the entire ELF image */
	load_addr = vm_mmap(NULL, 0, total_size,
			    PROT_READ | PROT_WRITE | PROT_EXEC,
			    MAP_PRIVATE | MAP_ANONYMOUS, 0);
	if (IS_ERR_VALUE(load_addr)) {
		if (own_phdrs)
			kfree(phdrs);
		return load_addr;
	}

	subleq_elf_debug("Allocated at 0x%lx", load_addr);

	/* Load each PT_LOAD segment */
	for (i = 0, phdr = phdrs; i < phnum; i++, phdr++) {
		subleq_elf_debug("Segment loop i=%d, p_type=%d", i, phdr->p_type);
		if (phdr->p_type != PT_LOAD)
			continue;

		unsigned long seg_addr = load_addr + (phdr->p_vaddr - min_addr);

		subleq_elf_debug(
			"  Segment %d: vaddr=0x%lx filesz=%lu memsz=%lu -> 0x%lx",
			i, (unsigned long)phdr->p_vaddr,
			(unsigned long)phdr->p_filesz,
			(unsigned long)phdr->p_memsz, seg_addr);

		/* Read file contents */
		if (phdr->p_filesz > 0) {
			pos = phdr->p_offset;
			ret = kernel_read(file, (void *)seg_addr,
					  phdr->p_filesz, &pos);
			if (ret != phdr->p_filesz) {
				subleq_elf_debug("Segment %d read failed: wanted %lu, got %ld\n",
				       i, (unsigned long)phdr->p_filesz, (long)ret);
				vm_munmap(load_addr, total_size);
				if (own_phdrs)
					kfree(phdrs);
				return ret < 0 ? ret : -EIO;
			}
		}

		/* Zero the BSS portion */
		if (phdr->p_memsz > phdr->p_filesz) {
			memset((void *)(seg_addr + phdr->p_filesz), 0,
			       phdr->p_memsz - phdr->p_filesz);
		}
	}

	/* Calculate entry point */
	info->load_addr = load_addr;
	info->base_vaddr = min_addr; /* Original link address */
	info->entry_addr = load_addr + (hdr->e_entry - min_addr);
	info->total_size = total_size;

	if (own_phdrs)
		kfree(phdrs);
	return 0;
}

/*
 * Process relocations, resolve external symbols, and optionally build symbol table.
 *
 * This function combines multiple operations in a SINGLE PASS to minimize I/O:
 * 1. Applying load offset to absolute addresses (for defined symbols)
 * 2. Resolving undefined external symbols against kernel runtime / libsrt
 * 3. Optionally building the symbol table for later lookups (for libraries)
 *
 * By doing all operations with a single read of section headers, symbol table,
 * and string table, we avoid redundant disk I/O which is very expensive in Subleq.
 *
 * For each R_386_32 relocation:
 * - If symbol is defined: add load_offset to the current value
 * - If symbol is undefined: look up in kernel/libsrt and patch to that address
 *
 * If build_symtab is true, also extracts global function symbols from the
 * symbol table and adds them to the libsrt hash table for use by dependent binaries.
 *
 * If skip_relocs is true, only builds symtab without applying relocations.
 * This is used for two-pass loading where all libraries are loaded first,
 * then relocations are processed after all symbols are available.
 *
 * is_main_exec: 1 = main executable (even if ET_DYN/PIE), 0 = library
 */
static int process_relocations_and_symbols(struct libsrt_state *state, struct file *file, struct elfhdr *hdr,
					   unsigned long load_addr,
					   unsigned long base_vaddr,
					   int build_symtab, int skip_relocs,
					   int is_main_exec,
					   struct elf_shdr *cached_shdrs,
					   struct elf_shdr **shdrs_out)
{
	struct elf_shdr *shdrs = NULL;
	struct elf_shdr *shdr;
	struct elf_shdr *symtab_shdr = NULL;
	struct elf_shdr *strtab_shdr = NULL;
	struct elf32_sym *syms = NULL;
	char *strtab = NULL;
	unsigned long *sym_cache = NULL;
	unsigned long load_offset = load_addr - base_vaddr;
	loff_t pos;
	ssize_t ret;
	int i, nsyms = 0;
	int relocs_applied = 0;  /* Total entries processed */
	int symbols_resolved = 0;
	int have_symtab = 0;
	int own_shdrs = 0;  /* Track if we allocated shdrs and need to free */

	/*
	 * All binaries are now ET_DYN (PIE or shared library).
	 * They use .dynsym and .rel.dyn for relocation processing.
	 * ET_EXEC support has been removed (no more .symtab/.rel.text path).
	 */

	/* Use cached section headers if provided, otherwise read them */
	if (hdr->e_shentsize != sizeof(struct elf_shdr))
		return 0;
	if (hdr->e_shnum == 0)
		return 0;
	if (hdr->e_shnum > 65536 / sizeof(struct elf_shdr))
		return -ENOEXEC;

	if (cached_shdrs) {
		/* Reuse cached section headers (no allocation, no read) */
		shdrs = cached_shdrs;
	} else {
		/* Allocate and read section headers */
		shdrs = kmalloc_array(hdr->e_shnum, sizeof(struct elf_shdr),
				      GFP_KERNEL);
		if (!shdrs)
			return -ENOMEM;

		pos = hdr->e_shoff;
		ret = kernel_read(file, shdrs, hdr->e_shnum * sizeof(struct elf_shdr),
				  &pos);
		if (ret != hdr->e_shnum * sizeof(struct elf_shdr)) {
			kfree(shdrs);
			return ret < 0 ? ret : -EIO;
		}
		own_shdrs = 1;
	}

	/*
	 * Find the appropriate symbol table for relocation processing:
	 *
	 * EXECUTABLES (ET_EXEC or PIE): Use .symtab (SHT_SYMTAB)
	 *   - .rel.text (from --emit-relocs) uses static symbol indices
	 *
	 * SHARED LIBRARIES (ET_DYN, not PIE): Use .dynsym (SHT_DYNSYM)
	 *   - .rel.dyn uses dynamic symbol indices
	 *   - Without --emit-relocs, .symtab indices don't match .rel.dyn
	 */
	for (i = 0, shdr = shdrs; i < hdr->e_shnum; i++, shdr++) {
		if (shdr->sh_type == SHT_DYNSYM) {
			symtab_shdr = shdr;
			break;
		}
	}

	/* Load symbol table and string table if available */
	if (symtab_shdr && symtab_shdr->sh_link < hdr->e_shnum) {
		strtab_shdr = &shdrs[symtab_shdr->sh_link];

		if (strtab_shdr->sh_type == SHT_STRTAB) {
			/* Read string table */
			strtab = kmalloc(strtab_shdr->sh_size, GFP_KERNEL);
			if (strtab) {
				pos = strtab_shdr->sh_offset;
				ret = kernel_read(file, strtab,
						  strtab_shdr->sh_size, &pos);
				if (ret != strtab_shdr->sh_size) {
					kfree(strtab);
					strtab = NULL;
				}
			}

			/* Read symbol table */
			if (strtab) {
				nsyms = symtab_shdr->sh_size /
					sizeof(struct elf32_sym);
				syms = kmalloc(symtab_shdr->sh_size, GFP_KERNEL);
				if (syms) {
					pos = symtab_shdr->sh_offset;
					ret = kernel_read(file, syms,
							  symtab_shdr->sh_size,
							  &pos);
					if (ret != symtab_shdr->sh_size) {
						kfree(syms);
						syms = NULL;
					} else {
						have_symtab = 1;
						/* Allocate symbol resolution cache only if processing relocs */
						if (!skip_relocs) {
							sym_cache = kzalloc(
								nsyms *
									sizeof(unsigned long),
								GFP_KERNEL);
						}
					}
				}
			}
		}
	}

	/*
	 * OPTIMIZATION: Pre-scan symbol table and populate cache.
	 * Cache values:
	 *   0 = not checked yet (normal defined symbol - just add load_offset)
	 *   1 = checked, not found (resolution failed)
	 *   2 = needs resolution (SHN_UNDEF or SHN_ABS with value 0)
	 *   >2 = resolved address
	 *
	 * This eliminates symbol_needs_resolution() calls in the hot loop.
	 * Only do this if we're processing relocations - skip for symtab-only pass.
	 */
	int undef_count = 0;
	if (!skip_relocs && have_symtab && strtab_shdr && sym_cache) {
		for (i = 1; i < nsyms; i++) {
			if (symbol_needs_resolution(&syms[i]) &&
			    syms[i].st_name < strtab_shdr->sh_size &&
			    syms[i].st_name != 0) {
				sym_cache[i] = 2;  /* Mark as needing resolution */
				undef_count++;
			}
			/* Symbols with cache[i] == 0 just need load_offset */
		}
		subleq_elf_debug("Pre-scanned %d symbols, %d need resolution",
				 nsyms, undef_count);
	}

	/* Skip relocation processing if requested (two-pass loading) */
	if (skip_relocs)
		goto build_symtab_only;

	/*
	 * OPTIMIZATION: Find max relocation section size and allocate once.
	 * This avoids repeated kmalloc/kfree in the processing loop.
	 */
	size_t max_rel_size = 0;
	struct elf32_rel *rels_buf = NULL;
	for (i = 0, shdr = shdrs; i < hdr->e_shnum; i++, shdr++) {
		if (shdr->sh_type == SHT_REL && shdr->sh_size > max_rel_size)
			max_rel_size = shdr->sh_size;
	}
	if (max_rel_size > 0) {
		rels_buf = kmalloc(max_rel_size, GFP_KERNEL);
		if (!rels_buf) {
			kfree(sym_cache);
			kfree(syms);
			kfree(strtab);
			if (own_shdrs)
				kfree(shdrs);
			return -ENOMEM;
		}
	}

	/* Process all relocation sections */
	for (i = 0, shdr = shdrs; i < hdr->e_shnum; i++, shdr++) {
		struct elf32_rel *rel;
		int nrels, j;

		if (shdr->sh_type != SHT_REL)
			continue;

		/*
		 * All binaries are now ET_DYN (PIE or shared library).
		 * Process .rel.dyn sections which contain R_386_RELATIVE + R_386_32.
		 * .rel.dyn sections have SHF_ALLOC.
		 */

		if (shdr->sh_entsize != sizeof(struct elf32_rel)) {
			subleq_elf_debug("Unexpected rel entry size %u\n",
				(unsigned)shdr->sh_entsize);
			continue;
		}

		nrels = shdr->sh_size / sizeof(struct elf32_rel);
		if (nrels == 0)
			continue;

		/* Read relocation entries into pre-allocated buffer */
		pos = shdr->sh_offset;
		ret = kernel_read(file, rels_buf, shdr->sh_size, &pos);
		if (ret != shdr->sh_size) {
			kfree(rels_buf);
			kfree(sym_cache);
			kfree(syms);
			kfree(strtab);
			if (own_shdrs)
				kfree(shdrs);
			return ret < 0 ? ret : -EIO;
		}

		subleq_elf_debug("Processing reloc section sh_flags=0x%x nrels=%d e_type=%d",
			shdr->sh_flags, nrels, hdr->e_type);

		/*
		 * Process each relocation.
		 * All binaries are now ET_DYN - handle R_386_RELATIVE and R_386_32.
		 *
		 * Optimized structure: check sym_cache FIRST since that's
		 * the main decision point. Most relocations have cache=0
		 * (defined symbols) and just need load_offset added.
		 */
#if SUBLEQ_ELF_DEBUG
		int rel_relative_count = 0, rel_32_count = 0, rel_unknown_count = 0;
#endif
		for (j = 0, rel = rels_buf; j < nrels; j++, rel++) {
			u32 *patch_addr;
			unsigned int rel_type = rel->r_info & 0xFF;

			patch_addr = (u32 *)(load_addr +
					     (rel->r_offset - base_vaddr));

			switch (rel_type) {
			case R_386_RELATIVE:
				/* Most common: add load_offset (no-op if 0) */
				*patch_addr += load_offset;
#if SUBLEQ_ELF_DEBUG
				rel_relative_count++;
#endif
				break;

			case R_386_32: {
				/*
				 * R_386_32: S + A (symbol value + addend)
				 *
				 * Cache values:
				 *   0 = defined symbol, just add load_offset
				 *   1 = undefined, lookup failed (weak: use 0)
				 *   2 = needs first lookup
				 *   >2 = resolved address
				 */
				unsigned int sym_idx = rel->r_info >> 8;
				unsigned long cache_val = sym_cache[sym_idx];

				if (cache_val == 1) {
					/*
					 * Already looked up, not found.
					 * For weak symbols, set to 0.
					 * For strong symbols, leave as-is.
					 */
					unsigned char bind = syms[sym_idx].st_info >> 4;
					if (bind == 2) { /* STB_WEAK */
						*patch_addr = 0;
					}
				} else if (cache_val >= 2) {
					/* Symbol needs external resolution */
					unsigned long sym_addr;

					if (cache_val > 2) {
						sym_addr = cache_val;
					} else {
						sym_addr = lookup_libsrt_symbol(state,
							strtab + syms[sym_idx].st_name);
						sym_cache[sym_idx] = sym_addr ? sym_addr : 1;
					}

					if (sym_addr) {
						*patch_addr = sym_addr + *patch_addr;
						symbols_resolved++;
					} else {
						/*
						 * First lookup failed. For weak undefined,
						 * set to 0. STB_WEAK = 2.
						 */
						unsigned char bind = syms[sym_idx].st_info >> 4;
						if (bind == 2) { /* STB_WEAK */
							*patch_addr = 0;
						}
					}
				} else {
					/*
					 * Defined symbol (cache_val == 0): add load_offset.
					 */
					*patch_addr += load_offset;
				}
#if SUBLEQ_ELF_DEBUG
				rel_32_count++;
#endif
				break;
			}

			default:
				/* Unknown relocation type - skip */
#if SUBLEQ_ELF_DEBUG
				rel_unknown_count++;
#endif
				break;
			}
		}
#if SUBLEQ_ELF_DEBUG
		subleq_elf_debug("  Reloc breakdown: %d RELATIVE, %d R_386_32, %d unknown",
			rel_relative_count, rel_32_count, rel_unknown_count);
#endif

		relocs_applied += nrels;  /* Count total after processing */
	}

	/* Free the reusable relocation buffer */
	kfree(rels_buf);

	/*
	 * Process RELR (Packed Relative Relocations) sections.
	 * These are a memory-efficient encoding for R_*_RELATIVE operations.
	 * RELR can reduce relocation section size by 90-98%.
	 */
	for (i = 0, shdr = shdrs; i < hdr->e_shnum; i++, shdr++) {
		u32 *relr_buf;
		int relr_applied;

		/* Accept both standard SHT_RELR and Android's legacy tag */
		if (shdr->sh_type != SHT_RELR)
			continue;

		if (shdr->sh_size == 0)
			continue;

		subleq_elf_debug("Processing RELR section: size=%lu entries",
			shdr->sh_size / sizeof(u32));

		/* Allocate buffer for RELR data */
		relr_buf = kmalloc(shdr->sh_size, GFP_KERNEL);
		if (!relr_buf)
			continue;  /* Skip this section on alloc failure */

		pos = shdr->sh_offset;
		ret = kernel_read(file, relr_buf, shdr->sh_size, &pos);
		if (ret != shdr->sh_size) {
			kfree(relr_buf);
			continue;
		}

		/* Decode and apply RELR relocations */
		relr_applied = process_relr_section(relr_buf, shdr->sh_size,
						    load_addr, base_vaddr,
						    load_offset);
		relocs_applied += relr_applied;

		subleq_elf_debug("  RELR: applied %d relocations", relr_applied);
		kfree(relr_buf);
	}

	subleq_elf_debug("Applied %d relocations with offset 0x%lx",
			 relocs_applied, load_offset);
	subleq_elf_debug("Resolved %d external symbols", symbols_resolved);

build_symtab_only:
	/*
	 * If requested, build symbol table from the already-loaded symtab/strtab.
	 * This eliminates redundant file I/O by reusing data we already have.
	 */
	if (build_symtab && have_symtab && strtab_shdr) {
		int symbols_added = 0;

		state->libsrt_load_addr = load_addr;
		/* Extract all global function symbols */
		for (i = 0; i < nsyms && state->symbol_count < LIBSRT_HASH_SIZE; i++) {
			struct elf32_sym *sym = &syms[i];
			const char *name;

			/* Skip undefined symbols */
			if (sym->st_shndx == SHN_UNDEF)
				continue;
		/* Skip non-function/non-object symbols (we need both for R_386_COPY) */
			if (ELF32_ST_TYPE(sym->st_info) != STT_FUNC &&
			    ELF32_ST_TYPE(sym->st_info) != STT_OBJECT &&
			    ELF32_ST_TYPE(sym->st_info) != STT_NOTYPE)
				continue;
			/* Only include global symbols (not local) */
			if (ELF32_ST_BIND(sym->st_info) == STB_LOCAL)
				continue;
			if (sym->st_name >= strtab_shdr->sh_size)
				continue;
			if (sym->st_name == 0) /* Skip empty names */
				continue;

			name = strtab + sym->st_name;

			/* Insert symbol into hash table */
			if (libsrt_hash_insert(state, name, load_addr + sym->st_value))
				symbols_added++;
		}

		subleq_elf_debug("Added %d lib symbols (total: %d, hash table)",
				 symbols_added, state->symbol_count);
	}

	kfree(sym_cache);
	kfree(syms);
	kfree(strtab);
	/* Return shdrs to caller for caching, or free if we own them */
	if (shdrs_out && own_shdrs) {
		*shdrs_out = shdrs;  /* Transfer ownership to caller */
	} else if (own_shdrs) {
		kfree(shdrs);
	}
	/* If !own_shdrs, caller owns the cached_shdrs - don't free */
	return 0;
}

/*
 * NOTE: resolve_external_symbols() and build_lib_symbol_table() have been
 * removed. Their functionality is now integrated into process_relocations_and_symbols()
 * which handles relocation patching, symbol resolution, and symbol table building
 * all in a single pass. This eliminates redundant file I/O (section headers,
 * symbol table, string table were being read twice per library).
 */

/*
 * Load the shared runtime library if present
 * lib_path is the path to load (from PT_INTERP), or NULL to skip
 * This function handles recursive loading of DT_NEEDED dependencies.
 */
static int load_libsrt(struct libsrt_state *state, const char *lib_path, struct elf_load_info *lib_info)
{
	struct file *lib_file;
	struct elfhdr lib_hdr;
	loff_t pos = 0;
	ssize_t ret;
	const char *lib_name;
	struct needed_lib lib_deps[MAX_NEEDED_LIBS];
	int ndeps, i;
	char dep_path[MAX_LIB_PATH];

	if (!lib_path || lib_path[0] == '\0') {
		/* No library path specified - binary might not need it */
		return 0;
	}

	/* Extract just the library name from the path */
	lib_name = strrchr(lib_path, '/');
	lib_name = lib_name ? lib_name + 1 : lib_path;

	/* Check if already loaded */
	if (find_loaded_lib(state, lib_name)) {
		subleq_elf_debug("Library %s already loaded, skipping",
				 lib_name);
		lib_info->load_addr = find_loaded_lib(state, lib_name);
		return 1; /* Already loaded */
	}

	lib_file = filp_open(lib_path, O_RDONLY, 0);
	if (IS_ERR(lib_file)) {
		/* Library not found - this is OK, binary might not need it */
		subleq_elf_debug("Shared library not found: %s", lib_path);
		return 0;
	}

	/* Read ELF header */
	ret = kernel_read(lib_file, &lib_hdr, sizeof(lib_hdr), &pos);
	if (ret != sizeof(lib_hdr)) {
		fput(lib_file);
		return ret < 0 ? ret : -EIO;
	}

	if (!is_subleq_elf(&lib_hdr, lib_file)) {
		fput(lib_file);
		subleq_elf_debug("%s is not a valid Subleq ELF\n", lib_path);
		return -ENOEXEC;
	}

	subleq_elf_debug("Loading shared library from %s", lib_path);

	ret = load_elf_segments(lib_file, &lib_hdr, lib_info, NULL, 0);
	if (ret < 0) {
		fput(lib_file);
		subleq_elf_debug("Failed to load %s: %d\n", lib_path,
		       (int)ret);
		return ret;
	}

	/* Record this library as loaded BEFORE processing dependencies.
	 * Store file handle and header for deferred relocation processing.
	 * File will be closed after all libraries are loaded and relocated.
	 */
	/* Record this library as loaded BEFORE processing dependencies.
	 * Store file handle and header for deferred relocation processing.
	 * File will be closed after all libraries are loaded and relocated.
	 */
	record_loaded_lib(state, lib_name, lib_info->load_addr, lib_info->base_vaddr,
			  lib_file, &lib_hdr);

	/* Build symbol table only (skip relocations for now).
	 * Relocations will be processed after ALL libraries are loaded,
	 * so that symbols from later-loaded libs are available.
	 * With build_symtab=1, skip_relocs=1, this only exports symbols.
	 */
	ret = process_relocations_and_symbols(state, lib_file, &lib_hdr,
					      lib_info->load_addr,
					      lib_info->base_vaddr, 1, 1,
					      0,  /* is_main_exec=0: this is a library */
					      NULL,  /* No cached shdrs yet */
					      &state->loaded_libs[state->loaded_lib_count - 1].shdrs);
	if (ret < 0) {
		subleq_elf_debug("Failed to build symtab for %s: %d\n",
		       lib_path, (int)ret);
		return ret;
	}

	/* Check for DT_NEEDED dependencies in this library and load them.
	 * Reuse lib_hdr from earlier read (no need to re-read from disk).
	 */
	ndeps = get_elf_needed_libs(lib_file, &lib_hdr, lib_deps,
				    MAX_NEEDED_LIBS, NULL, NULL);
	for (i = 0; i < ndeps; i++) {
		struct elf_load_info dep_info = { 0 };
		snprintf(dep_path, sizeof(dep_path), "/lib/%s",
			 lib_deps[i].name);
		/* Recursive call - will skip if already loaded */
		load_libsrt(state, dep_path, &dep_info);
	}

	/* NOTE: Do NOT close file here - deferred until after relocs processed */

	subleq_elf_debug("Shared library loaded at 0x%lx (relocs pending)",
			 lib_info->load_addr);
	return 1; /* Library loaded successfully */
}

/*
 * Create the argument and environment tables on the stack
 *
 * Stack layout after this function (growing down):
 *   [high addr]
 *   strings: "arg0\0arg1\0...env0\0env1\0..."
 *   padding for alignment
 *   auxv[1] = {AT_NULL, 0}
 *   auxv[0] = {AT_PAGESZ, PAGE_SIZE}
 *   envp[envc] = NULL
 *   envp[envc-1]
 *   ...
 *   envp[0]
 *   argv[argc] = NULL
 *   argv[argc-1]
 *   ...
 *   argv[0]
 *   argc
 *   [low addr / SP]
 */
static int create_elf_tables(struct linux_binprm *bprm, struct mm_struct *mm,
			     struct elf_load_info *exec_info)
{
	unsigned long sp = mm->start_stack;
	unsigned long argc = bprm->argc;
	unsigned long envc = bprm->envc;
	unsigned long __user *argv;
	unsigned long __user *envp;
	unsigned long __user *auxv;
	unsigned long strings_start;
	char __user *p;
	size_t len;
	int ret, i;

	/* Transfer argument and environment strings to stack */
	ret = transfer_args_to_stack(bprm, &sp);
	if (ret < 0)
		return ret;

	/*
	 * After transfer_args_to_stack, sp points to the start of the
	 * transferred strings. This is where argv[0] string begins.
	 * Save this before we align sp for the pointer arrays.
	 */
	strings_start = sp;
	mm->arg_start = sp;

	sp &= ~15UL; /* 16-byte alignment */

	/*
	 * Space for minimal auxv: {AT_PAGESZ, page_size}, {AT_NULL, 0}
	 * Each auxv entry is 2 words (a_type and a_val), so 4 words total.
	 */
	sp -= 4 * sizeof(unsigned long);
	auxv = (unsigned long __user *)sp;

	/* Space for envp[] pointers + NULL */
	sp -= (envc + 1) * sizeof(unsigned long);
	envp = (unsigned long __user *)sp;

	/* Space for argv[] pointers + NULL */
	sp -= (argc + 1) * sizeof(unsigned long);
	argv = (unsigned long __user *)sp;

	/* Space for argc */
	sp -= sizeof(unsigned long);

	/* Store argc */
	if (put_user(argc, (unsigned long __user *)sp))
		return -EFAULT;

	/*
	 * Fill in argv[] pointers.
	 * Strings start at strings_start and are packed consecutively.
	 * This matches the regular ELF loader pattern in fs/binfmt_elf.c.
	 */
	p = (char __user *)strings_start;
	for (i = 0; i < argc; i++) {
		if (put_user((unsigned long)p, argv++))
			return -EFAULT;
		len = strnlen_user(p, MAX_ARG_STRLEN);
		if (!len || len > MAX_ARG_STRLEN)
			return -EINVAL;
		p += len;
	}
	/* NULL terminate argv[] */
	if (put_user(0, argv))
		return -EFAULT;
	mm->arg_end = (unsigned long)p;

	/* Fill in envp[] pointers */
	mm->env_start = (unsigned long)p;
	for (i = 0; i < envc; i++) {
		if (put_user((unsigned long)p, envp++))
			return -EFAULT;
		len = strnlen_user(p, MAX_ARG_STRLEN);
		if (!len || len > MAX_ARG_STRLEN)
			return -EINVAL;
		p += len;
	}
	/* NULL terminate envp[] */
	if (put_user(0, envp))
		return -EFAULT;
	mm->env_end = (unsigned long)p;

	/*
	 * Fill in minimal auxv - uClibc's _dl_aux_init expects to find
	 * auxv entries immediately after the envp NULL terminator.
	 * We provide AT_PAGESZ (useful for memory allocation) and AT_NULL.
	 */
	if (put_user((unsigned long)AT_PAGESZ, auxv++) ||
	    put_user((unsigned long)PAGE_SIZE, auxv++) ||
	    put_user((unsigned long)AT_NULL, auxv++) ||
	    put_user(0UL, auxv))
		return -EFAULT;

	mm->start_stack = sp;

	/*
	 * Debug: print the stack layout for verification
	 */
#if SUBLEQ_ELF_DEBUG
	pr_info("SUBLEQ_ELF: create_elf_tables debug:\n");
	pr_info("  mm->start_stack (SP) = 0x%lx\n", mm->start_stack);
	pr_info("  argc = %lu, envc = %lu\n", argc, envc);
	pr_info("  strings_start = 0x%lx\n", strings_start);
	pr_info("  mm->arg_start = 0x%lx, mm->arg_end = 0x%lx\n",
		mm->arg_start, mm->arg_end);
	pr_info("  mm->env_start = 0x%lx, mm->env_end = 0x%lx\n",
		mm->env_start, mm->env_end);

	/* Print stack layout: [SP] = argc, then argv[], then envp[], then auxv[] */
	{
		unsigned long __user *ptr = (unsigned long __user *)sp;
		unsigned long val;
		int j;
		char strbuf[64];

		/* argc at SP */
		if (!get_user(val, ptr))
			pr_info("  [SP+0x00] argc = %lu\n", val);

		/* argv pointers start at SP+4 */
		ptr++;
		pr_info("  argv[] array at 0x%lx:\n", (unsigned long)ptr);
		for (j = 0; j <= argc && j < 4; j++) {
			if (!get_user(val, ptr + j)) {
				if (val != 0) {
					/* Try to read the string */
					long copied = strncpy_from_user(strbuf,
						(const char __user *)val,
						sizeof(strbuf) - 1);
					if (copied > 0) {
						strbuf[copied] = '\0';
						pr_info("    argv[%d] = 0x%lx -> \"%s\"\n",
							j, val, strbuf);
					} else {
						pr_info("    argv[%d] = 0x%lx -> (read failed: %ld)\n",
							j, val, copied);
					}
				} else {
					pr_info("    argv[%d] = 0x0 (NULL)\n", j);
				}
			}
		}

		/* envp pointers start after argv */
		ptr += argc + 1;
		pr_info("  envp[] array at 0x%lx:\n", (unsigned long)ptr);
		for (j = 0; j <= envc && j < 4; j++) {
			if (!get_user(val, ptr + j)) {
				if (val != 0) {
					/* Try to read the string */
					long copied = strncpy_from_user(strbuf,
						(const char __user *)val,
						sizeof(strbuf) - 1);
					if (copied > 0) {
						strbuf[copied] = '\0';
						pr_info("    envp[%d] = 0x%lx -> \"%s\"\n",
							j, val, strbuf);
					} else {
						pr_info("    envp[%d] = 0x%lx -> (read failed: %ld)\n",
							j, val, copied);
					}
				} else {
					pr_info("    envp[%d] = 0x0 (NULL)\n", j);
				}
			}
		}

		/* auxv starts after envp */
		ptr += envc + 1;
		pr_info("  auxv[] array at 0x%lx:\n", (unsigned long)ptr);
		for (j = 0; j < 4; j++) {
			if (!get_user(val, ptr + j))
				pr_info("    auxv[%d] = 0x%lx\n", j, val);
		}
	}

	/* Flush printk buffer so we see the debug output before any crash */
	printk_trigger_flush();
#endif

	return 0;
}

/*
 * Main entry point for loading a Subleq ELF binary
 */
static int load_elf_subleq_binary(struct linux_binprm *bprm)
{
	struct elfhdr *hdr = (struct elfhdr *)bprm->buf;
	struct pt_regs *regs = task_pt_regs(current);
	struct elf_load_info exec_info = { 0 };
	struct elf_load_info lib_info = { 0 };
	struct needed_lib needed_libs[MAX_NEEDED_LIBS];
	char lib_path[MAX_LIB_PATH];
	unsigned long stack_size;
	unsigned long stack_base;
	unsigned long heap_size;
	unsigned long heap_base;
	int ret;
	int has_libsrt = 0;
	int nlibs, i;
	struct elf_phdr *phdrs = NULL;  /* Reuse phdrs from get_elf_needed_libs */
	int phnum = 0;
	struct libsrt_state *state;

	subleq_elf_debug("Checking ELF binary: %s", bprm->filename);

	/* Check if this is a Subleq ELF */
	if (!is_subleq_elf(hdr, bprm->file))
		return -ENOEXEC;

	/* Allocate re-entrant state on the heap (stack is too small for big array) */
	state = kmalloc(sizeof(struct libsrt_state), GFP_KERNEL);
	if (!state)
		return -ENOMEM;
	memset(state, 0, sizeof(struct libsrt_state));

	subleq_elf_debug("Valid Subleq ELF, entry=0x%lx",
			 (unsigned long)hdr->e_entry);

	/*
	 * Reject executables with entry point 0 (e.g., shared libraries).
	 * Must check BEFORE begin_new_exec() so we can return -ENOEXEC and
	 * allow the shell to display "cannot execute binary file".
	 */
	if (hdr->e_entry == 0) {
		subleq_elf_debug("Rejecting: entry point is 0 (shared library?)");
		return -ENOEXEC;
	}

	/* Extract DT_NEEDED library names before point of no return.
	 * Also returns program headers to avoid reading them again later. */
	nlibs = get_elf_needed_libs(bprm->file, hdr, needed_libs,
				    MAX_NEEDED_LIBS, &phdrs, &phnum);
	subleq_elf_debug("Found %d DT_NEEDED libraries", nlibs);

	subleq_elf_debug("Before begin_new_exec: PID=%d comm=%s",
			 task_tgid_vnr(current), current->comm);

	/* Flush old executable */
	ret = begin_new_exec(bprm);
	if (ret) {
		kfree(phdrs);
		kfree(state); /* Free state on early error too */
		return ret;
	}

	subleq_elf_debug("After begin_new_exec: PID=%d comm=%s",
			 task_tgid_vnr(current), current->comm);

	/* Point of no return */
	set_personality(PER_LINUX_32BIT);
	setup_new_exec(bprm);
	set_binfmt(&elf_subleq_format);

	/* Reset symbol table and loaded library list for new process */
	/* Allocate hash table dynamically to avoid permanent BSS usage */
	/* Re-entrant: store in state struct */
	{
		unsigned long table_size = LIBSRT_HASH_SIZE * sizeof(struct libsrt_hash_entry);
		unsigned long table_addr;
		
		table_size = PAGE_ALIGN(table_size);
		table_addr = vm_mmap(NULL, 0, table_size, PROT_READ | PROT_WRITE,
				     MAP_PRIVATE | MAP_ANONYMOUS, 0);
		if (IS_ERR_VALUE(table_addr)) {
			ret = table_addr;
			goto out_free_state;
		}
			
		state->hash = (struct libsrt_hash_entry *)table_addr;
	}
	
	state->symbol_count = 0;
	state->loaded_lib_count = 0;

	/* Phase 1: Load each DT_NEEDED library from /lib/ and collect symbols */
	for (i = 0; i < nlibs; i++) {
		/* Build full path: /lib/<libname> */
		snprintf(lib_path, sizeof(lib_path), "/lib/%s",
			 needed_libs[i].name);

		ret = load_libsrt(state, lib_path, &lib_info);
		if (ret < 0)
			goto out;
		if (ret > 0) {
			has_libsrt = 1;
			/* Store load address for second pass */
			needed_libs[i].load_addr = lib_info.load_addr;
		}
	}

	/* Hash table is already indexed - no sorting needed (O(1) lookup) */
	if (state->symbol_count > 0) {
		subleq_elf_debug("Library symbols ready (%d in hash table)",
				 state->symbol_count);
	}

	/* Phase 2: Now that ALL libraries are loaded and their symbols exported,
	 * process deferred relocations for each library.
	 */
	for (i = 0; i < state->loaded_lib_count; i++) {
		if (!state->loaded_libs[i].relocs_applied && state->loaded_libs[i].file) {
			subleq_elf_debug("Processing deferred relocs for %s",
					 state->loaded_libs[i].name);
			ret = process_relocations_and_symbols(
				state,
				state->loaded_libs[i].file,
				&state->loaded_libs[i].hdr,
				state->loaded_libs[i].load_addr,
				state->loaded_libs[i].base_vaddr, 0, 0,
				0,  /* is_main_exec=0: this is a library */
				state->loaded_libs[i].shdrs,  /* Use cached shdrs */
				NULL);  /* No need to cache again */
			if (ret < 0) {
				subleq_elf_debug("Failed deferred relocs for %s: %d\n",
				       state->loaded_libs[i].name, (int)ret);
				/* Close all open files and free cached data before returning */
				for (i = 0; i < state->loaded_lib_count; i++) {
					if (state->loaded_libs[i].file) {
						fput(state->loaded_libs[i].file);
						state->loaded_libs[i].file = NULL;
					}
					if (state->loaded_libs[i].shdrs) {
						kfree(state->loaded_libs[i].shdrs);
						state->loaded_libs[i].shdrs = NULL;
					}
				}
				goto out; /* Deferred relocs cleanup handles itself */
			}
			state->loaded_libs[i].relocs_applied = 1;
		}
	}


	/* Close all library files and free cached data now that relocations are done */
	for (i = 0; i < state->loaded_lib_count; i++) {
		if (state->loaded_libs[i].file) {
			fput(state->loaded_libs[i].file);
			state->loaded_libs[i].file = NULL;
		}
		if (state->loaded_libs[i].shdrs) {
			kfree(state->loaded_libs[i].shdrs);
			state->loaded_libs[i].shdrs = NULL;
		}
	}

	/* Load the main executable using pre-read program headers */
	ret = load_elf_segments(bprm->file, hdr, &exec_info, phdrs, phnum);
	/* Free phdrs now - no longer needed */
	kfree(phdrs);
	phdrs = NULL;
	if (ret < 0)
		return ret;

	subleq_elf_debug("Executable loaded at 0x%lx, entry=0x%lx",
			 exec_info.load_addr, exec_info.entry_addr);

	/* Apply relocations and resolve external symbols.
	 * build_symtab=0, skip_relocs=0 since executable needs full processing.
	 * is_main_exec=1 to treat PIE (ET_DYN) as executable, not library.
	 */
	ret = process_relocations_and_symbols(state, bprm->file, hdr,
					      exec_info.load_addr,
					      exec_info.base_vaddr, 0, 0,
					      1,  /* is_main_exec=1: main executable */
					      NULL, NULL);
	if (ret < 0) {
		subleq_elf_debug("Failed to process relocations/symbols: %d\n",
		       ret);
		goto out;
	}

	/* Allocate heap region for brk/sbrk.
	 * On NOMMU systems, brk() (in mm/nommu.c) just moves a pointer within
	 * pre-allocated memory - it doesn't allocate. We must allocate the
	 * heap region explicitly via vm_mmap.
	 */
	heap_size = 1 * 1024 * 1024; /* 1MB initial heap for small allocations.
				      * Large allocations (>128KB) use mmap() which
				      * allocates dynamically, so we don't need a huge
				      * pre-allocated heap region here. */
	heap_size = PAGE_ALIGN(heap_size);

	heap_base = vm_mmap(NULL, 0, heap_size, PROT_READ | PROT_WRITE,
			    MAP_PRIVATE | MAP_ANONYMOUS, 0);
	if (IS_ERR_VALUE(heap_base)) {
		subleq_elf_debug("Failed to allocate heap, using minimal");
		/* Fallback: use a minimal heap at end of loaded binary */
		heap_base = exec_info.load_addr + exec_info.total_size;
		heap_size = PAGE_SIZE; /* Minimal, will likely fail */
	}

	/* Set up stack */
	stack_size = exec_info.stack_size;
	if (stack_size == 0)
		stack_size = 128 * 1024; /* 128KB default */

	stack_size = PAGE_ALIGN(stack_size);

	stack_base = vm_mmap(NULL, 0, stack_size, PROT_READ | PROT_WRITE,
			     MAP_PRIVATE | MAP_ANONYMOUS | MAP_GROWSDOWN, 0);
	if (IS_ERR_VALUE(stack_base)) {
		ret = stack_base;
		goto out;
	}

	current->mm->start_brk = heap_base;
	current->mm->brk = heap_base;
	current->mm->context.end_brk = heap_base + heap_size;
	current->mm->start_stack = stack_base + stack_size;

	/* Set up memory ranges */
	current->mm->start_code = exec_info.load_addr;
	current->mm->end_code = exec_info.load_addr + exec_info.total_size;
	current->mm->start_data = exec_info.load_addr;
	current->mm->end_data = exec_info.load_addr + exec_info.total_size;

	/* Create argument tables */
	ret = create_elf_tables(bprm, current->mm, &exec_info);
	if (ret < 0)
		goto out;

	finalize_exec(bprm);

	/* Start the thread */
	subleq_elf_debug("Starting thread: entry=0x%lx sp=0x%lx",
			 exec_info.entry_addr, current->mm->start_stack);
	start_thread(regs, exec_info.entry_addr, current->mm->start_stack);

	ret = 0;

out:
	if (state) {
		if (state->hash) {
			unsigned long table_size = LIBSRT_HASH_SIZE * sizeof(struct libsrt_hash_entry);
			table_size = PAGE_ALIGN(table_size);
			vm_munmap((unsigned long)state->hash, table_size);
			state->hash = NULL;
		}
		kfree(state);
		state = NULL;
	}
	return ret;

out_free_state:
	kfree(state);
	return ret;
}

static int __init init_elf_subleq_binfmt(void)
{
	register_binfmt(&elf_subleq_format);
	pr_info("Subleq ELF binary format registered\n");
	return 0;
}

static void __exit exit_elf_subleq_binfmt(void)
{
	unregister_binfmt(&elf_subleq_format);
}

core_initcall(init_elf_subleq_binfmt);
module_exit(exit_elf_subleq_binfmt);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Subleq ELF binary format");
