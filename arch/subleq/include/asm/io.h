/* SPDX-License-Identifier: GPL-2.0 */
/*
 * I/O operations for Subleq
 *
 * Subleq has a flat memory model - all memory is directly accessible.
 * No special I/O space or mapping needed.
 */

#ifndef _ASM_SUBLEQ_IO_H
#define _ASM_SUBLEQ_IO_H

#include <linux/types.h>

/* Subleq uses memory-mapped I/O - no port I/O */
#define IO_SPACE_LIMIT 0

/* All memory access is direct */
#define __raw_readb(a) (*(volatile u8 __force *)(a))
#define __raw_readw(a) (*(volatile u16 __force *)(a))
#define __raw_readl(a) (*(volatile u32 __force *)(a))

#define __raw_writeb(v, a) (*(volatile u8 __force *)(a) = (v))
#define __raw_writew(v, a) (*(volatile u16 __force *)(a) = (v))
#define __raw_writel(v, a) (*(volatile u32 __force *)(a) = (v))

#define readb(a) __raw_readb(a)
#define readw(a) __raw_readw(a)
#define readl(a) __raw_readl(a)

#define writeb(v, a) __raw_writeb(v, a)
#define writew(v, a) __raw_writew(v, a)
#define writel(v, a) __raw_writel(v, a)

#define readb_relaxed(a) readb(a)
#define readw_relaxed(a) readw(a)
#define readl_relaxed(a) readl(a)

#define writeb_relaxed(v, a) writeb(v, a)
#define writew_relaxed(v, a) writew(v, a)
#define writel_relaxed(v, a) writel(v, a)

/* Memory barriers - no reordering on uniprocessor Subleq */
#define mmiowb() barrier()

/* I/O remapping - identity for NOMMU */
#define ioremap(addr, size) ((void __iomem *)(addr))
#define ioremap_wc(addr, size) ((void __iomem *)(addr))
#define ioremap_cache(addr, size) ((void __iomem *)(addr))
#define iounmap(addr) \
	do {          \
	} while (0)

/* Physical to virtual and back - identity mapping */
#define phys_to_virt(x) ((void *)(x))
#define virt_to_phys(x) ((phys_addr_t)(x))

#include <asm-generic/io.h>

#endif /* _ASM_SUBLEQ_IO_H */
