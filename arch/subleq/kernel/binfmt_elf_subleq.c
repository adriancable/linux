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

/* Hardcoded table of kernel runtime symbols */
static const struct {
	const char *name;
	void *addr;
} kernel_runtime_symbols[] = { { "__ashldi3", &__ashldi3 },
			       { "__ashrdi3", &__ashrdi3 },
			       { "__divdi3", &__divdi3 },
			       { "__lshrdi3", &__lshrdi3 },
			       { "__moddi3", &__moddi3 },
			       { "__subleq_and", &__subleq_and },
			       { "__subleq_lb", &__subleq_lb },
			       { "__subleq_lh", &__subleq_lh },
			       { "__subleq_mul", &__subleq_mul },
			       { "__subleq_or", &__subleq_or },
			       { "__subleq_sb", &__subleq_sb },
			       { "__subleq_sdivrem", &__subleq_sdivrem },
			       { "__subleq_sdivrem64", &__subleq_sdivrem64 },
			       { "__subleq_sh", &__subleq_sh },
			       { "__subleq_shl", &__subleq_shl },
			       { "__subleq_sra", &__subleq_sra },
			       { "__subleq_srl", &__subleq_srl },
			       { "__subleq_udivrem", &__subleq_udivrem },
			       { "__subleq_udivrem64", &__subleq_udivrem64 },
			       { "__subleq_xor", &__subleq_xor },
			       { "__udivdi3", &__udivdi3 },
			       { "__umoddi3", &__umoddi3 },
			       { "memcpy", &memcpy },
			       { "memmove", &memmove },
			       { "memset", &memset },
			       { NULL, NULL } };

/* Dynamic symbol table (populated from loaded libraries) */
#define MAX_LIBSRT_SYMBOLS 256
static struct libsrt_symbol libsrt_symbols[MAX_LIBSRT_SYMBOLS];
static int libsrt_symbol_count = 0;
static unsigned long libsrt_load_addr = 0;

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
 * Look up a symbol - first check kernel runtime symbols, then loaded libraries
 * Returns the address or 0 if not found
 */
static unsigned long lookup_libsrt_symbol(const char *name)
{
	int i;

	/* First, check kernel runtime symbols */
	for (i = 0; kernel_runtime_symbols[i].name != NULL; i++) {
		if (strcmp(kernel_runtime_symbols[i].name, name) == 0)
			return (unsigned long)kernel_runtime_symbols[i].addr;
	}

	/* Then check dynamically loaded library symbols */
	for (i = 0; i < libsrt_symbol_count; i++) {
		if (strcmp(libsrt_symbols[i].name, name) == 0)
			return libsrt_symbols[i].addr;
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
 */
static int get_elf_needed_libs(struct file *file, struct elfhdr *hdr,
			       struct needed_lib *libs, int max_libs)
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

	kfree(phdrs);

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
 * Returns the load address or negative error
 */
static long load_elf_segments(struct file *file, struct elfhdr *hdr,
			      struct elf_load_info *info)
{
	struct elf_phdr *phdrs, *phdr;
	unsigned long total_size = 0;
	unsigned long min_addr = ULONG_MAX;
	unsigned long max_addr = 0;
	unsigned long load_addr;
	loff_t pos;
	int i, nloads = 0;
	ssize_t ret;

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

	/* Calculate total memory needed and find min/max addresses */
	for (i = 0, phdr = phdrs; i < hdr->e_phnum; i++, phdr++) {
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
		kfree(phdrs);
		return load_addr;
	}

	subleq_elf_debug("Allocated at 0x%lx", load_addr);

	/* Load each PT_LOAD segment */
	for (i = 0, phdr = phdrs; i < hdr->e_phnum; i++, phdr++) {
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
				vm_munmap(load_addr, total_size);
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

	kfree(phdrs);
	return 0;
}

/*
 * Process relocations for the loaded ELF
 *
 * Reads section headers to find relocation sections (.rel.*),
 * then applies R_386_32 relocations by adding the load offset
 * to each absolute address reference.
 */
static int process_elf_relocations(struct file *file, struct elfhdr *hdr,
				   unsigned long load_addr,
				   unsigned long base_vaddr)
{
	struct elf_shdr *shdrs = NULL;
	struct elf_shdr *shdr;
	unsigned long load_offset = load_addr - base_vaddr;
	loff_t pos;
	ssize_t ret;
	int i;
	int relocs_applied = 0;

	/* No relocations needed if loaded at the linked address */
	if (load_offset == 0)
		return 0;

	/* Read section headers */
	if (hdr->e_shentsize != sizeof(struct elf_shdr))
		return 0; /* No section headers or wrong format */
	if (hdr->e_shnum == 0)
		return 0; /* No sections */
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

	/* Find and process relocation sections */
	for (i = 0, shdr = shdrs; i < hdr->e_shnum; i++, shdr++) {
		struct elf32_rel *rels = NULL;
		struct elf32_rel *rel;
		int nrels, j;

		/* Only process SHT_REL sections (not SHT_RELA - we use REL for i386) */
		if (shdr->sh_type != SHT_REL)
			continue;

		/* Calculate number of relocation entries */
		if (shdr->sh_entsize != sizeof(struct elf32_rel)) {
			pr_warn("SUBLEQ_ELF: Unexpected rel entry size %u\n",
				(unsigned)shdr->sh_entsize);
			continue;
		}

		nrels = shdr->sh_size / sizeof(struct elf32_rel);
		if (nrels == 0)
			continue;

		/* Allocate buffer for relocations */
		rels = kmalloc(shdr->sh_size, GFP_KERNEL);
		if (!rels) {
			kfree(shdrs);
			return -ENOMEM;
		}

		/* Read relocation entries */
		pos = shdr->sh_offset;
		ret = kernel_read(file, rels, shdr->sh_size, &pos);
		if (ret != shdr->sh_size) {
			kfree(rels);
			kfree(shdrs);
			return ret < 0 ? ret : -ENOEXEC;
		}

		/* Apply each relocation */
		for (j = 0, rel = rels; j < nrels; j++, rel++) {
			unsigned int type = ELF32_R_TYPE(rel->r_info);
			unsigned long reloc_addr;
			u32 *patch_addr;
			u32 value;

			/*
			 * Only process R_386_32 relocations.
			 * Skip R_386_RELATIVE to avoid double-relocating offsets that
			 * appear in both .rel.dyn (R_386_RELATIVE from -shared) and
			 * .rel.text (R_386_32 from --emit-relocs).
			 * R_386_32 is preferred because it includes symbol references
			 * for undefined external symbols.
			 */
			if (type != R_386_32)
				continue;

			/* Calculate where to apply the relocation */
			reloc_addr = load_addr + (rel->r_offset - base_vaddr);
			patch_addr = (u32 *)reloc_addr;

			/* Read current value, add load offset, write back */
			value = *patch_addr;
			value += load_offset;
			*patch_addr = value;

			relocs_applied++;
		}

		kfree(rels);
	}

	kfree(shdrs);

	subleq_elf_debug("Applied %d relocations with offset 0x%lx",
			 relocs_applied, load_offset);

	return 0;
}

/*
 * Resolve external symbol references in an executable against libsrt
 *
 * This reads the executable's symbol table and relocation entries,
 * finds undefined symbols that reference libsrt functions, and patches
 * them to point to the correct addresses in libsrt.
 */
static int resolve_external_symbols(struct file *file, struct elfhdr *hdr,
				    unsigned long load_addr,
				    unsigned long base_vaddr)
{
	struct elf_shdr *shdrs = NULL;
	struct elf_shdr *shdr;
	struct elf_shdr *symtab_shdr = NULL;
	struct elf_shdr *strtab_shdr = NULL;
	struct elf32_sym *syms = NULL;
	char *strtab = NULL;
	loff_t pos;
	ssize_t ret;
	int i, nsyms;
	int symbols_resolved = 0;

	if (libsrt_symbol_count == 0)
		return 0; /* No libsrt symbols to resolve */

	/* Read section headers */
	if (hdr->e_shentsize != sizeof(struct elf_shdr) || hdr->e_shnum == 0)
		return 0;

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

	/* Find .symtab and .strtab sections */
	for (i = 0, shdr = shdrs; i < hdr->e_shnum; i++, shdr++) {
		if (shdr->sh_type == SHT_SYMTAB)
			symtab_shdr = shdr;
		else if (shdr->sh_type == SHT_STRTAB && i != hdr->e_shstrndx)
			strtab_shdr = shdr;
	}

	if (!symtab_shdr || !strtab_shdr) {
		kfree(shdrs);
		return 0;
	}

	/* Read string table */
	strtab = kmalloc(strtab_shdr->sh_size, GFP_KERNEL);
	if (!strtab) {
		kfree(shdrs);
		return -ENOMEM;
	}

	pos = strtab_shdr->sh_offset;
	ret = kernel_read(file, strtab, strtab_shdr->sh_size, &pos);
	if (ret != strtab_shdr->sh_size) {
		kfree(strtab);
		kfree(shdrs);
		return ret < 0 ? ret : -ENOEXEC;
	}

	/* Read symbol table */
	nsyms = symtab_shdr->sh_size / sizeof(struct elf32_sym);
	syms = kmalloc(symtab_shdr->sh_size, GFP_KERNEL);
	if (!syms) {
		kfree(strtab);
		kfree(shdrs);
		return -ENOMEM;
	}

	pos = symtab_shdr->sh_offset;
	ret = kernel_read(file, syms, symtab_shdr->sh_size, &pos);
	if (ret != symtab_shdr->sh_size) {
		kfree(syms);
		kfree(strtab);
		kfree(shdrs);
		return ret < 0 ? ret : -ENOEXEC;
	}

	/* Now find relocation sections and resolve undefined symbols */
	for (i = 0, shdr = shdrs; i < hdr->e_shnum; i++, shdr++) {
		struct elf32_rel *rels = NULL;
		struct elf32_rel *rel;
		int nrels, j;

		if (shdr->sh_type != SHT_REL)
			continue;

		if (shdr->sh_entsize != sizeof(struct elf32_rel))
			continue;

		nrels = shdr->sh_size / sizeof(struct elf32_rel);
		if (nrels == 0)
			continue;

		rels = kmalloc(shdr->sh_size, GFP_KERNEL);
		if (!rels)
			continue;

		pos = shdr->sh_offset;
		ret = kernel_read(file, rels, shdr->sh_size, &pos);
		if (ret != shdr->sh_size) {
			kfree(rels);
			continue;
		}

		/* Process each relocation */
		for (j = 0, rel = rels; j < nrels; j++, rel++) {
			unsigned int sym_idx = ELF32_R_SYM(rel->r_info);
			unsigned int type = ELF32_R_TYPE(rel->r_info);
			struct elf32_sym *sym;
			const char *name;
			unsigned long sym_addr;
			unsigned long reloc_addr;
			u32 *patch_addr;

			if (type != R_386_32)
				continue;
			if (sym_idx >= nsyms)
				continue;

			sym = &syms[sym_idx];

			/* Only resolve undefined symbols */
			if (sym->st_shndx != SHN_UNDEF)
				continue;
			if (sym->st_name >= strtab_shdr->sh_size)
				continue;

			name = strtab + sym->st_name;

			/* Look up in libsrt */
			sym_addr = lookup_libsrt_symbol(name);
			if (sym_addr == 0)
				continue; /* Symbol not found in libsrt */

			/* Patch the relocation to point to libsrt */
			reloc_addr = load_addr + (rel->r_offset - base_vaddr);
			patch_addr = (u32 *)reloc_addr;
			*patch_addr = sym_addr;

			subleq_elf_debug("Resolved %s -> 0x%lx", name,
					 sym_addr);
			symbols_resolved++;
		}

		kfree(rels);
	}

	subleq_elf_debug("Resolved %d external symbols", symbols_resolved);

	kfree(syms);
	kfree(strtab);
	kfree(shdrs);
	return 0;
}

/*
 * Build symbol table from the library's ELF file
 * Adds all global function symbols to the shared symbol table
 * (appends to existing symbols - does NOT reset)
 */
static int build_lib_symbol_table(struct file *file, struct elfhdr *hdr,
				  unsigned long load_addr)
{
	struct elf_shdr *shdrs = NULL;
	struct elf_shdr *shdr;
	struct elf_shdr *symtab_shdr = NULL;
	struct elf_shdr *strtab_shdr = NULL;
	struct elf32_sym *syms = NULL;
	char *strtab = NULL;
	loff_t pos;
	ssize_t ret;
	int i, nsyms;
	int symbols_added = 0;

	libsrt_load_addr = load_addr;

	/* Read section headers */
	if (hdr->e_shentsize != sizeof(struct elf_shdr) || hdr->e_shnum == 0)
		return 0;

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

	/* Find .symtab and .strtab sections */
	for (i = 0, shdr = shdrs; i < hdr->e_shnum; i++, shdr++) {
		if (shdr->sh_type == SHT_SYMTAB)
			symtab_shdr = shdr;
		else if (shdr->sh_type == SHT_STRTAB && i != hdr->e_shstrndx)
			strtab_shdr = shdr;
	}

	if (!symtab_shdr || !strtab_shdr) {
		subleq_elf_debug("libsrt: No symbol table found");
		kfree(shdrs);
		return 0;
	}

	/* Read string table */
	strtab = kmalloc(strtab_shdr->sh_size, GFP_KERNEL);
	if (!strtab) {
		kfree(shdrs);
		return -ENOMEM;
	}

	pos = strtab_shdr->sh_offset;
	ret = kernel_read(file, strtab, strtab_shdr->sh_size, &pos);
	if (ret != strtab_shdr->sh_size) {
		kfree(strtab);
		kfree(shdrs);
		return ret < 0 ? ret : -ENOEXEC;
	}

	/* Read symbol table */
	nsyms = symtab_shdr->sh_size / sizeof(struct elf32_sym);
	syms = kmalloc(symtab_shdr->sh_size, GFP_KERNEL);
	if (!syms) {
		kfree(strtab);
		kfree(shdrs);
		return -ENOMEM;
	}

	pos = symtab_shdr->sh_offset;
	ret = kernel_read(file, syms, symtab_shdr->sh_size, &pos);
	if (ret != symtab_shdr->sh_size) {
		kfree(syms);
		kfree(strtab);
		kfree(shdrs);
		return ret < 0 ? ret : -ENOEXEC;
	}

	/* Extract all global function symbols */
	for (i = 0; i < nsyms && libsrt_symbol_count < MAX_LIBSRT_SYMBOLS;
	     i++) {
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

	subleq_elf_debug("Added %d symbols (total: %d)", symbols_added,
			 libsrt_symbol_count);

	kfree(syms);
	kfree(strtab);
	kfree(shdrs);
	return 0;
}

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

	ret = load_elf_segments(lib_file, &lib_hdr, lib_info);
	if (ret < 0) {
		fput(lib_file);
		pr_err("SUBLEQ_ELF: Failed to load %s: %d\n", lib_path,
		       (int)ret);
		return ret;
	}

	/* Record this library as loaded BEFORE processing dependencies
	 * to handle circular dependencies */
	record_loaded_lib(lib_name, lib_info->load_addr);

	/* Apply relocations to the library itself */
	ret = process_elf_relocations(lib_file, &lib_hdr, lib_info->load_addr,
				      lib_info->base_vaddr);
	if (ret < 0) {
		fput(lib_file);
		pr_err("SUBLEQ_ELF: Failed to process relocations for %s: %d\n",
		       lib_path, (int)ret);
		return ret;
	}

	/* Build symbol table for later lookups */
	pos = 0;
	ret = kernel_read(lib_file, &lib_hdr, sizeof(lib_hdr), &pos);
	if (ret == sizeof(lib_hdr)) {
		build_lib_symbol_table(lib_file, &lib_hdr, lib_info->load_addr);
	}

	/* Check for DT_NEEDED dependencies in this library and load them */
	pos = 0;
	ret = kernel_read(lib_file, &lib_hdr, sizeof(lib_hdr), &pos);
	if (ret == sizeof(lib_hdr)) {
		ndeps = get_elf_needed_libs(lib_file, &lib_hdr, lib_deps,
					    MAX_NEEDED_LIBS);
		for (i = 0; i < ndeps; i++) {
			struct elf_load_info dep_info = { 0 };
			snprintf(dep_path, sizeof(dep_path), "/lib/%s",
				 lib_deps[i].name);
			/* Recursive call - will skip if already loaded */
			load_libsrt(dep_path, &dep_info);
		}
	}

	fput(lib_file);

	subleq_elf_debug("Shared library loaded at 0x%lx", lib_info->load_addr);
	return 1; /* Library loaded successfully */
}

/*
 * Create the argument and environment tables on the stack
 */
static int create_elf_tables(struct linux_binprm *bprm, struct mm_struct *mm,
			     struct elf_load_info *exec_info)
{
	unsigned long sp = mm->start_stack;
	unsigned long argc = bprm->argc;
	int ret;

	/* Transfer arguments to stack */
	ret = transfer_args_to_stack(bprm, &sp);
	if (ret < 0)
		return ret;

	sp &= ~15UL; /* 16-byte alignment */

	/* Space for envp[] pointers + NULL */
	sp -= (bprm->envc + 1) * sizeof(unsigned long);

	/* Space for argv[] pointers + NULL */
	sp -= (bprm->argc + 1) * sizeof(unsigned long);

	/* Space for argc */
	sp -= sizeof(unsigned long);

	/* Store argc */
	if (put_user(argc, (unsigned long __user *)sp))
		return -EFAULT;

	mm->start_stack = sp;
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
	int ret;
	int has_libsrt = 0;
	int nlibs, i;

	subleq_elf_debug("Checking ELF binary: %s", bprm->filename);

	/* Check if this is a Subleq ELF */
	if (!is_subleq_elf(hdr, bprm->file))
		return -ENOEXEC;

	subleq_elf_debug("Valid Subleq ELF, entry=0x%lx",
			 (unsigned long)hdr->e_entry);

	/* Extract DT_NEEDED library names before point of no return */
	nlibs = get_elf_needed_libs(bprm->file, hdr, needed_libs,
				    MAX_NEEDED_LIBS);
	subleq_elf_debug("Found %d DT_NEEDED libraries", nlibs);

	/* Flush old executable */
	ret = begin_new_exec(bprm);
	if (ret)
		return ret;

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

	/* Phase 2: Now that all libraries are loaded and symbols collected,
	 * resolve external symbols in each library. This iterates over ALL
	 * loaded libraries (including recursively loaded dependencies). */
	for (i = 0; i < loaded_lib_count; i++) {
		struct file *lib_file;
		struct elfhdr lib_hdr;
		loff_t pos = 0;

		snprintf(lib_path, sizeof(lib_path), "/lib/%s",
			 loaded_libs[i].name);

		lib_file = filp_open(lib_path, O_RDONLY, 0);
		if (IS_ERR(lib_file))
			continue;

		ret = kernel_read(lib_file, &lib_hdr, sizeof(lib_hdr), &pos);
		if (ret == sizeof(lib_hdr)) {
			/* Shared libs are linked at 0, so base_vaddr = 0 */
			resolve_external_symbols(lib_file, &lib_hdr,
						 loaded_libs[i].load_addr, 0);
		}
		fput(lib_file);
	}

	/* Load the main executable */
	ret = load_elf_segments(bprm->file, hdr, &exec_info);
	if (ret < 0)
		return ret;

	subleq_elf_debug("Executable loaded at 0x%lx, entry=0x%lx",
			 exec_info.load_addr, exec_info.entry_addr);

	/* Apply relocations - adjust for difference between link and load address */
	ret = process_elf_relocations(bprm->file, hdr, exec_info.load_addr,
				      exec_info.base_vaddr);
	if (ret < 0) {
		pr_err("SUBLEQ_ELF: Failed to process relocations: %d\n", ret);
		return ret;
	}

	/* Resolve external symbols against libsrt */
	if (has_libsrt) {
		ret = resolve_external_symbols(bprm->file, hdr,
					       exec_info.load_addr,
					       exec_info.base_vaddr);
		if (ret < 0) {
			pr_err("SUBLEQ_ELF: Failed to resolve symbols: %d\n",
			       ret);
			return ret;
		}
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

	current->mm->start_brk = exec_info.load_addr + exec_info.total_size;
	current->mm->brk = current->mm->start_brk;
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
