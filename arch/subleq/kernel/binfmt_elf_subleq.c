// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq ELF binary format handler for NOMMU systems
 *
 * This is a simplified ELF loader for Subleq that:
 * 1. Loads PIE (Position Independent Executable) ELF binaries
 * 2. Supports a shared runtime library at /lib/libsrt
 * 3. Performs relocations at load time
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

#include <asm/param.h>
#include <asm/ptrace.h>
#include <asm/processor.h>
#include <asm/current.h>

/* ELF relocation types for i386 */
#ifndef R_386_32
#define R_386_32 1 /* Absolute 32-bit address */
#endif
#ifndef R_386_RELATIVE
#define R_386_RELATIVE 8 /* Adjust by load base (for shared libs) */
#endif

#define SUBLEQ_ELF_DEBUG 1

#if SUBLEQ_ELF_DEBUG
#define subleq_elf_debug(fmt, ...) \
	pr_info("SUBLEQ_ELF: " fmt "\n", ##__VA_ARGS__)
#else
#define subleq_elf_debug(fmt, ...) \
	do {                       \
	} while (0)
#endif

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

/* Symbol table entry for runtime symbols */
struct libsrt_symbol {
	char name[64];
	unsigned long addr;
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
extern long __subleq_syscall(long, long, long, long, long, long, long);

/* Stub _init and _fini for static binaries without crti.o/crtn.o */
static void __used __subleq_init(void) { }
static void __used __subleq_fini(void) { }

/*
 * Kernel runtime symbols - SORTED ALPHABETICALLY for binary search.
 * IMPORTANT: When adding new symbols, maintain alphabetical order!
 */
static const struct {
	const char *name;
	void *addr;
} kernel_runtime_symbols[] = {
	{ "__ashldi3", &__ashldi3 },
	{ "__ashrdi3", &__ashrdi3 },
	{ "__divdi3", &__divdi3 },
	{ "__lshrdi3", &__lshrdi3 },
	{ "__moddi3", &__moddi3 },
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
	{ "__udivdi3", &__udivdi3 },
	{ "__umoddi3", &__umoddi3 },
	{ "_fini", &__subleq_fini },
	{ "_init", &__subleq_init },
};

#define KERNEL_RUNTIME_SYMBOL_COUNT \
	(sizeof(kernel_runtime_symbols) / sizeof(kernel_runtime_symbols[0]))

/* Dynamic symbol table (populated from loaded libraries) */
#define MAX_LIBSRT_SYMBOLS 256
static struct libsrt_symbol libsrt_symbols[MAX_LIBSRT_SYMBOLS];
static int libsrt_symbol_count = 0;
static unsigned long libsrt_load_addr = 0;
static int libsrt_symbols_sorted = 0;  /* Flag: symbols need re-sorting after add */

/*
 * Comparison function for sorting libsrt_symbols alphabetically.
 * Used by sort() to enable binary search lookups.
 */
static int libsrt_symbol_cmp(const void *a, const void *b)
{
	const struct libsrt_symbol *sa = a;
	const struct libsrt_symbol *sb = b;
	return strcmp(sa->name, sb->name);
}

/* Track which libraries have been loaded to avoid duplicates */
#define MAX_LOADED_LIBS 16
static struct {
	char name[64];
	unsigned long load_addr;
} loaded_libs[MAX_LOADED_LIBS];
static int loaded_lib_count = 0;

/* Check if a library has already been loaded. Returns load_addr or 0 if not. */
static unsigned long find_loaded_lib(const char *name)
{
	int i;
	for (i = 0; i < loaded_lib_count; i++) {
		if (strcmp(loaded_libs[i].name, name) == 0)
			return loaded_libs[i].load_addr;
	}
	return 0;
}

/* Record that a library has been loaded */
static void record_loaded_lib(const char *name, unsigned long load_addr)
{
	if (loaded_lib_count < MAX_LOADED_LIBS) {
		strscpy(loaded_libs[loaded_lib_count].name, name,
			sizeof(loaded_libs[0].name));
		loaded_libs[loaded_lib_count].load_addr = load_addr;
		loaded_lib_count++;
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
 * then loaded libraries (also binary search after sorting).
 * Returns the address or 0 if not found.
 */
static unsigned long lookup_libsrt_symbol(const char *name)
{
	unsigned long addr;
	int low, high;

	/* Binary search in sorted kernel runtime symbols - O(log n) */
	addr = lookup_kernel_symbol(name);
	if (addr)
		return addr;

	/* Binary search in sorted library symbols - O(log n) */
	if (libsrt_symbol_count == 0)
		return 0;

	low = 0;
	high = libsrt_symbol_count - 1;

	while (low <= high) {
		int mid = low + (high - low) / 2;
		int cmp = strcmp(libsrt_symbols[mid].name, name);

		if (cmp == 0)
			return libsrt_symbols[mid].addr;
		else if (cmp < 0)
			low = mid + 1;
		else
			high = mid - 1;
	}
	return 0;
}

static int load_elf_subleq_binary(struct linux_binprm *bprm);

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
	/* Accept both ET_EXEC and ET_DYN (PIE) */
	if (hdr->e_type != ET_EXEC && hdr->e_type != ET_DYN)
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
			return ret < 0 ? ret : -ENOEXEC;
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
		pr_info("SUBLEQ_ELF: Segment loop i=%d, p_type=%d\n", i, phdr->p_type);
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
				pr_err("SUBLEQ_ELF: Segment %d read failed: wanted %lu, got %ld\n",
				       i, (unsigned long)phdr->p_filesz, (long)ret);
				vm_munmap(load_addr, total_size);
				if (own_phdrs)
					kfree(phdrs);
				return ret < 0 ? ret : -ENOEXEC;
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
 * symbol table and adds them to libsrt_symbols for use by dependent binaries.
 */
static int process_relocations_and_symbols(struct file *file, struct elfhdr *hdr,
					   unsigned long load_addr,
					   unsigned long base_vaddr,
					   int build_symtab)
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
	int relocs_applied = 0;
	int symbols_resolved = 0;
	int have_symtab = 0;

	/* Read section headers */
	if (hdr->e_shentsize != sizeof(struct elf_shdr))
		return 0;
	if (hdr->e_shnum == 0)
		return 0;
	if (hdr->e_shnum > 65536 / sizeof(struct elf_shdr))
		return -ENOEXEC;

	shdrs = kmalloc_array(hdr->e_shnum, sizeof(struct elf_shdr),
			      GFP_KERNEL);
	if (!shdrs)
		return -ENOMEM;

	pos = hdr->e_shoff;
	ret = kernel_read(file, shdrs, hdr->e_shnum * sizeof(struct elf_shdr),
			  &pos);
	if (ret != hdr->e_shnum * sizeof(struct elf_shdr)) {
		kfree(shdrs);
		return ret < 0 ? ret : -ENOEXEC;
	}

	/* Find .symtab section (needed for external symbol resolution) */
	for (i = 0, shdr = shdrs; i < hdr->e_shnum; i++, shdr++) {
		if (shdr->sh_type == SHT_SYMTAB) {
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
						/* Allocate symbol resolution cache */
						sym_cache = kzalloc(
							nsyms *
								sizeof(unsigned long),
							GFP_KERNEL);
					}
				}
			}
		}
	}

	/*
	 * OPTIMIZATION: Pre-scan symbol table to count undefined symbols.
	 * If there are no undefined external symbols, we can use a fast path
	 * that skips all symbol checking and just applies load_offset.
	 */
	int have_any_undef = 0;
	if (have_symtab && strtab_shdr) {
		for (i = 1; i < nsyms; i++) {
			if (syms[i].st_shndx == SHN_UNDEF &&
			    syms[i].st_name < strtab_shdr->sh_size &&
			    syms[i].st_name != 0) {
				have_any_undef = 1;
				break;  /* Found at least one, no need to continue */
			}
		}
		if (!have_any_undef) {
			subleq_elf_debug("No undefined symbols - using fast reloc path");
		}
	}

	/* Process all relocation sections */
	for (i = 0, shdr = shdrs; i < hdr->e_shnum; i++, shdr++) {
		struct elf32_rel *rels = NULL;
		struct elf32_rel *rel;
		int nrels, j;

		if (shdr->sh_type != SHT_REL)
			continue;

		if (shdr->sh_entsize != sizeof(struct elf32_rel)) {
			pr_warn("SUBLEQ_ELF: Unexpected rel entry size %u\n",
				(unsigned)shdr->sh_entsize);
			continue;
		}

		nrels = shdr->sh_size / sizeof(struct elf32_rel);
		if (nrels == 0)
			continue;

		/* Allocate and read relocation entries */
		rels = kmalloc(shdr->sh_size, GFP_KERNEL);
		if (!rels) {
			kfree(sym_cache);
			kfree(syms);
			kfree(strtab);
			kfree(shdrs);
			return -ENOMEM;
		}

		pos = shdr->sh_offset;
		ret = kernel_read(file, rels, shdr->sh_size, &pos);
		if (ret != shdr->sh_size) {
			kfree(rels);
			kfree(sym_cache);
			kfree(syms);
			kfree(strtab);
			kfree(shdrs);
			return ret < 0 ? ret : -ENOEXEC;
		}

		/*
		 * Process each relocation.
		 * Two paths:
		 * 1. FAST PATH: No undefined symbols - just add load_offset to all
		 *    R_386_32 relocations, no symbol lookup needed.
		 * 2. SLOW PATH: Has undefined symbols - need to check each relocation.
		 */
		if (!have_any_undef && load_offset != 0) {
			/*
			 * FAST PATH: No undefined symbols in this binary.
			 * All relocations just need load_offset added.
			 * We still need to verify type=R_386_32, but can skip
			 * all symbol table lookups.
			 */
			for (j = 0, rel = rels; j < nrels; j++, rel++) {
				u32 *patch_addr;

				/*
				 * Quick type check: R_386_32 has type=1, so
				 * r_info ends with 0x01. We check (r_info & 0xFF) == 1
				 * but to avoid AND, check if r_info % 256 == 1.
				 * Actually, just check the low byte directly:
				 * if ((r_info - 1) >> 8 << 8) + 1 != r_info, skip.
				 * Simpler: assume all are R_386_32 (validated by linker).
				 */
				patch_addr = (u32 *)(load_addr + (rel->r_offset - base_vaddr));
				*patch_addr += load_offset;
				relocs_applied++;
			}
		} else if (!have_any_undef && load_offset == 0) {
			/*
			 * ULTRA FAST PATH: No undefined symbols AND no load offset.
			 * Nothing to do at all!
			 */
			relocs_applied += nrels;
		} else {
			/*
			 * SLOW PATH: Has undefined symbols - need full processing.
			 */
			for (j = 0, rel = rels; j < nrels; j++, rel++) {
				unsigned long reloc_addr;
				u32 *patch_addr;

				/*
				 * Extract sym_idx. Since the Subleq LLVM backend only
				 * emits R_386_32 relocations (type=1), we know:
				 * r_info = (sym_idx << 8) | 1
				 * So sym_idx = r_info >> 8
				 *
				 * No type check needed - guaranteed by backend.
				 */
				unsigned int sym_idx = rel->r_info >> 8;

				reloc_addr = load_addr + (rel->r_offset - base_vaddr);
				patch_addr = (u32 *)reloc_addr;

				/*
				 * Check if this is an undefined symbol that needs
				 * external resolution.
				 */
				if (have_symtab && sym_idx > 0 && sym_idx < nsyms) {
					struct elf32_sym *sym = &syms[sym_idx];

					if (sym->st_shndx == SHN_UNDEF &&
					    sym->st_name < strtab_shdr->sh_size) {
						unsigned long sym_addr;
						int first_resolution = 0;

						/* Check cache first */
						if (sym_cache) {
							if (sym_cache[sym_idx] == 1) {
								/* Not found - apply load offset */
								goto apply_offset;
							}
							if (sym_cache[sym_idx] != 0) {
								sym_addr = sym_cache[sym_idx];
								goto apply_sym;
							}
						}

						/* Cache miss - look up */
						sym_addr = lookup_libsrt_symbol(
							strtab + sym->st_name);

						if (sym_cache) {
							sym_cache[sym_idx] =
								sym_addr ? sym_addr : 1;
						}

						if (sym_addr == 0)
							goto apply_offset;

						first_resolution = 1;

apply_sym:
						*patch_addr = sym_addr;

						if (first_resolution) {
							subleq_elf_debug(
								"Resolved %s -> 0x%lx",
								strtab + sym->st_name,
								sym_addr);
						}
						symbols_resolved++;
						continue;
					}
				}

apply_offset:
				/* Defined symbol or no symtab: add load offset */
				if (load_offset != 0) {
					*patch_addr += load_offset;
					relocs_applied++;
				}
			}
		}

		kfree(rels);
	}

	subleq_elf_debug("Applied %d relocations with offset 0x%lx",
			 relocs_applied, load_offset);
	subleq_elf_debug("Resolved %d external symbols", symbols_resolved);

	/*
	 * If requested, build symbol table from the already-loaded symtab/strtab.
	 * This eliminates redundant file I/O by reusing data we already have.
	 */
	if (build_symtab && have_symtab && strtab_shdr) {
		int symbols_added = 0;

		libsrt_load_addr = load_addr;

		/* Extract all global function symbols */
		for (i = 0; i < nsyms && libsrt_symbol_count < MAX_LIBSRT_SYMBOLS; i++) {
			struct elf32_sym *sym = &syms[i];
			const char *name;

			/* Skip undefined symbols */
			if (sym->st_shndx == SHN_UNDEF)
				continue;
			/* Skip non-function symbols */
			if (ELF32_ST_TYPE(sym->st_info) != STT_FUNC &&
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

			/* Store symbol with adjusted address */
			strscpy(libsrt_symbols[libsrt_symbol_count].name, name,
				sizeof(libsrt_symbols[0].name));
			libsrt_symbols[libsrt_symbol_count].addr =
				load_addr + sym->st_value;
			libsrt_symbol_count++;
			symbols_added++;
		}

		/* Sort symbols alphabetically to enable binary search lookups */
		if (symbols_added > 0 && libsrt_symbol_count > 1) {
			sort(libsrt_symbols, libsrt_symbol_count,
			     sizeof(struct libsrt_symbol), libsrt_symbol_cmp, NULL);
			libsrt_symbols_sorted = 1;
		}

		subleq_elf_debug("Added %d lib symbols (total: %d, sorted)",
				 symbols_added, libsrt_symbol_count);
	}

	kfree(sym_cache);
	kfree(syms);
	kfree(strtab);
	kfree(shdrs);
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
static int load_libsrt(const char *lib_path, struct elf_load_info *lib_info)
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
	if (find_loaded_lib(lib_name)) {
		subleq_elf_debug("Library %s already loaded, skipping",
				 lib_name);
		lib_info->load_addr = find_loaded_lib(lib_name);
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
		return ret < 0 ? ret : -ENOEXEC;
	}

	if (!is_subleq_elf(&lib_hdr, lib_file)) {
		fput(lib_file);
		pr_err("SUBLEQ_ELF: %s is not a valid Subleq ELF\n", lib_path);
		return -ENOEXEC;
	}

	subleq_elf_debug("Loading shared library from %s", lib_path);

	ret = load_elf_segments(lib_file, &lib_hdr, lib_info, NULL, 0);
	if (ret < 0) {
		fput(lib_file);
		pr_err("SUBLEQ_ELF: Failed to load %s: %d\n", lib_path,
		       (int)ret);
		return ret;
	}

	/* Record this library as loaded BEFORE processing dependencies
	 * to handle circular dependencies */
	record_loaded_lib(lib_name, lib_info->load_addr);

	/* Apply relocations, resolve external symbols, and build symbol table.
	 * With build_symtab=1, this also exports the library's symbols for
	 * dependent binaries, avoiding a redundant read of section/symbol tables.
	 */
	ret = process_relocations_and_symbols(lib_file, &lib_hdr,
					      lib_info->load_addr,
					      lib_info->base_vaddr, 1);
	if (ret < 0) {
		fput(lib_file);
		pr_err("SUBLEQ_ELF: Failed to process relocations for %s: %d\n",
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
		load_libsrt(dep_path, &dep_info);
	}

	fput(lib_file);

	subleq_elf_debug("Shared library loaded at 0x%lx", lib_info->load_addr);
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

	subleq_elf_debug("Checking ELF binary: %s", bprm->filename);

	/* Check if this is a Subleq ELF */
	if (!is_subleq_elf(hdr, bprm->file))
		return -ENOEXEC;

	subleq_elf_debug("Valid Subleq ELF, entry=0x%lx",
			 (unsigned long)hdr->e_entry);

	/* Extract DT_NEEDED library names before point of no return.
	 * Also returns program headers to avoid reading them again later. */
	nlibs = get_elf_needed_libs(bprm->file, hdr, needed_libs,
				    MAX_NEEDED_LIBS, &phdrs, &phnum);
	subleq_elf_debug("Found %d DT_NEEDED libraries", nlibs);

	subleq_elf_debug("Before begin_new_exec: PID=%d comm=%s",
			 task_tgid_vnr(current), current->comm);

	/* Flush old executable */
	ret = begin_new_exec(bprm);
	if (ret)
		return ret;

	subleq_elf_debug("After begin_new_exec: PID=%d comm=%s",
			 task_tgid_vnr(current), current->comm);

	/* Point of no return */
	set_personality(PER_LINUX_32BIT);
	setup_new_exec(bprm);
	set_binfmt(&elf_subleq_format);

	/* Reset symbol table and loaded library list for new process */
	libsrt_symbol_count = 0;
	loaded_lib_count = 0;

	/* Phase 1: Load each DT_NEEDED library from /lib/ and collect symbols */
	for (i = 0; i < nlibs; i++) {
		/* Build full path: /lib/<libname> */
		snprintf(lib_path, sizeof(lib_path), "/lib/%s",
			 needed_libs[i].name);

		ret = load_libsrt(lib_path, &lib_info);
		if (ret < 0)
			return ret;
		if (ret > 0) {
			has_libsrt = 1;
			/* Store load address for second pass */
			needed_libs[i].load_addr = lib_info.load_addr;
		}
	}

	/* Note: Phase 2 symbol resolution has been removed.
	 * External symbols are now resolved during the initial
	 * process_relocations_and_symbols() call in load_libsrt().
	 */

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
	 * build_symtab=0 since the main executable doesn't export symbols.
	 */
	ret = process_relocations_and_symbols(bprm->file, hdr,
					      exec_info.load_addr,
					      exec_info.base_vaddr, 0);
	if (ret < 0) {
		pr_err("SUBLEQ_ELF: Failed to process relocations/symbols: %d\n",
		       ret);
		return ret;
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
	if (IS_ERR_VALUE(stack_base))
		return stack_base;

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
		return ret;

	finalize_exec(bprm);

	/* Start the thread */
	subleq_elf_debug("Starting thread: entry=0x%lx sp=0x%lx",
			 exec_info.entry_addr, current->mm->start_stack);
	start_thread(regs, exec_info.entry_addr, current->mm->start_stack);

	return 0;
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
