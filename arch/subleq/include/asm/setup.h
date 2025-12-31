/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Setup declarations for Subleq
 */

#ifndef _ASM_SUBLEQ_SETUP_H
#define _ASM_SUBLEQ_SETUP_H

#include <linux/init.h>

#define COMMAND_LINE_SIZE 256

/* Early console setup */
extern void __init subleq_early_console_init(void);

/* Memory setup */
extern unsigned long subleq_memory_start;
extern unsigned long subleq_memory_end;

#endif /* _ASM_SUBLEQ_SETUP_H */
