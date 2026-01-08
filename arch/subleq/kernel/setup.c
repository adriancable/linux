// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq architecture setup
 */

#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/mm.h>
#include <linux/memblock.h>
#include <linux/console.h>
#include <linux/screen_info.h>
#include <linux/root_dev.h>
#include <linux/seq_file.h>
#include <linux/sched/task.h>
#include <generated/utsrelease.h>

#include <asm/setup.h>
#include <asm/sections.h>

/* Memory layout */
unsigned long subleq_memory_start = 0;
unsigned long subleq_memory_end = 0x40000000; /* 1GB */

/* Current task pointer for non-SMP - must be initialized to init_task */
struct task_struct *subleq_current_task = &init_task;
EXPORT_SYMBOL(subleq_current_task);

/* Command line */
static char __initdata builtin_cmdline[COMMAND_LINE_SIZE] = CONFIG_CMDLINE;

/* External early console putchar - compiler intrinsic */
extern void __subleq_putchar(int c);

/*
 * Early console - uses Subleq's putchar instruction
 */
static void subleq_early_write(struct console *con, const char *s, unsigned n)
{
	while (n--) {
		if (*s == '\n')
			__subleq_putchar('\r');
		__subleq_putchar(*s);
		s++;
	}
}

static struct console subleq_early_console = {
	.name = "subleq",
	.write = subleq_early_write,
	.flags = CON_PRINTBUFFER | CON_BOOT,
	.index = -1,
};

/*
 * Clear BSS section
 */
static void __init clear_bss(void)
{
	extern char __bss_start[], __bss_stop[];
	char *p;

	for (p = __bss_start; p < __bss_stop; p++)
		*p = 0;
}

/*
 * Entry point from head.S
 *
 * This function is called by head.S instead of start_kernel() directly.
 * It clears BSS first, initializes critical early systems, then calls
 * start_kernel().
 *
 * This ensures BSS is cleared before any C code (including printk)
 * tries to use BSS-resident data structures like the printk ring buffer.
 */
extern asmlinkage void __noreturn start_kernel(void);

/* Early IRQ stack initialization - defined in irq.c */
extern void early_irq_stack_init(void);

/* Kernel stack pointer initialization - defined in syscall_entry.c */
extern void subleq_init_kernel_sp(struct task_struct *tsk);

asmlinkage void __init __noreturn subleq_start(void)
{
	clear_bss();

	/*
	 * Initialize the IRQ stack IMMEDIATELY after BSS is cleared.
	 * This must happen before start_kernel() because interrupts
	 * can fire at any point during kernel initialization.
	 */
	early_irq_stack_init();

	/*
	 * Initialize the kernel stack pointer for the init task.
	 * This is needed so the first syscall from userspace (before
	 * any context switch happens) has a valid kernel stack.
	 */
	subleq_init_kernel_sp(&init_task);

	start_kernel();
}

/*
 * setup_arch - architecture-specific setup
 *
 * Called early in boot by start_kernel()
 */
void __init setup_arch(char **cmdline_p)
{
	/* BSS already cleared in subleq_start() before start_kernel() */

	/* Register early console */
	register_console(&subleq_early_console);

	pr_info("Subleq Linux %s\n", UTS_RELEASE);
	pr_info("Memory: 0x%08lx - 0x%08lx (%lu MB)\n", subleq_memory_start,
		subleq_memory_end,
		(subleq_memory_end - subleq_memory_start) >> 20);

	/* Set up command line */
	strscpy(boot_command_line, builtin_cmdline, COMMAND_LINE_SIZE);
	*cmdline_p = boot_command_line;

	/* Parse early parameters */
	parse_early_param();

	/* Set up memory */
	memblock_add(subleq_memory_start,
		     subleq_memory_end - subleq_memory_start);

	/* Reserve kernel code and data */
	memblock_reserve(__pa(_text), _end - _text);

	/* Reserve low memory (boot area, registers, etc.) */
	memblock_reserve(0, 0x1000);

	/* NOMMU: no sparse memory */

	/* No swap device */
	ROOT_DEV = 0;

	/*
	 * Initialize memory zones - this MUST be called before mm_core_init()
	 * so the zone allocator knows about available memory.
	 */
	paging_init();

	pr_info("setup_arch complete\n");
}

/*
 * CPU info for /proc/cpuinfo
 */
static void *c_start(struct seq_file *m, loff_t *pos)
{
	return *pos < 1 ? (void *)1 : NULL;
}

static void *c_next(struct seq_file *m, void *v, loff_t *pos)
{
	++*pos;
	return NULL;
}

static void c_stop(struct seq_file *m, void *v)
{
}

static int show_cpuinfo(struct seq_file *m, void *v)
{
	seq_printf(m, "processor\t: 0\n");
	seq_printf(m, "model name\t: Subleq OISC Virtual Machine\n");
	seq_printf(m, "BogoMIPS\t: 0.00\n");
	seq_printf(m, "\n");
	return 0;
}

const struct seq_operations cpuinfo_op = {
	.start = c_start,
	.next = c_next,
	.stop = c_stop,
	.show = show_cpuinfo,
};
