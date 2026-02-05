// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq Virtual Machine Framebuffer Driver
 *
 * Simple fbdev driver that maps a fixed memory region as the display buffer.
 * The framebuffer is located at the top of the 1GB address space.
 *
 * Resolution: 800x600, RGB888 (24-bit truecolor)
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/errno.h>
#include <linux/string.h>
#include <linux/mm.h>
#include <linux/slab.h>
#include <linux/delay.h>
#include <linux/fb.h>
#include <linux/init.h>
#include <linux/platform_device.h>

/* Framebuffer configuration - must match VM settings */
#define SUBLEQFB_WIDTH       800
#define SUBLEQFB_HEIGHT      600
#define SUBLEQFB_BPP         32      /* XRGB8888 - 32-bit aligned for fast word access */
#define SUBLEQFB_FB_SIZE     (SUBLEQFB_WIDTH * SUBLEQFB_HEIGHT * 4)
#define SUBLEQFB_FB_ADDR     (0x40000000UL - SUBLEQFB_FB_SIZE)

static struct fb_var_screeninfo subleqfb_var = {
	.xres           = SUBLEQFB_WIDTH,
	.yres           = SUBLEQFB_HEIGHT,
	.xres_virtual   = SUBLEQFB_WIDTH,
	.yres_virtual   = SUBLEQFB_HEIGHT,
	.bits_per_pixel = SUBLEQFB_BPP,
	/* XRGB8888: X in bits 24-31 (unused), R in 16-23, G in 8-15, B in 0-7 */
	.red            = { .offset = 16, .length = 8 },
	.green          = { .offset = 8,  .length = 8 },
	.blue           = { .offset = 0,  .length = 8 },
	.transp         = { .offset = 24, .length = 0 },  /* No alpha, just padding */
	.activate       = FB_ACTIVATE_NOW,
	.vmode          = FB_VMODE_NONINTERLACED,
};

static struct fb_fix_screeninfo subleqfb_fix = {
	.id             = "SubleqFB",
	.type           = FB_TYPE_PACKED_PIXELS,
	.visual         = FB_VISUAL_TRUECOLOR,
	.xpanstep       = 0,
	.ypanstep       = 0,
	.ywrapstep      = 0,
	.line_length    = SUBLEQFB_WIDTH * 4,
	.accel          = FB_ACCEL_NONE,
	.smem_start     = SUBLEQFB_FB_ADDR,
	.smem_len       = SUBLEQFB_FB_SIZE,
};

/* Pseudo palette for 24/32bpp modes */
static u32 pseudo_palette[16];

/*
 * Set a single color register (for truecolor modes, this populates the
 * pseudo palette used by higher-level fbcon code).
 */
static int subleqfb_setcolreg(u_int regno, u_int red, u_int green, u_int blue,
			      u_int transp, struct fb_info *info)
{
	if (regno >= 16)
		return 1;

	/* Convert 16-bit color values to 8-bit */
	red   >>= 8;
	green >>= 8;
	blue  >>= 8;

	/* XRGB8888: store in pseudo palette */
	pseudo_palette[regno] = (red << info->var.red.offset) |
				(green << info->var.green.offset) |
				(blue << info->var.blue.offset);
	return 0;
}

/*
 * Custom framebuffer operations using optimized memory functions
 * memmove() maps to __subleq_memmove which is highly optimized
 */

/* Fill rectangle with solid color */
static void subleqfb_fillrect(struct fb_info *info, const struct fb_fillrect *rect)
{
	u32 *dst;
	u32 color;
	u32 x, y, width, height;
	u32 line_bytes = info->fix.line_length;

	/* Get color from pseudo palette or use raw color */
	if (info->fix.visual == FB_VISUAL_TRUECOLOR && rect->color < 16)
		color = ((u32 *)info->pseudo_palette)[rect->color];
	else
		color = rect->color;

	/* Clamp to screen bounds */
	x = rect->dx;
	y = rect->dy;
	width = rect->width;
	height = rect->height;

	if (x >= info->var.xres || y >= info->var.yres)
		return;
	if (x + width > info->var.xres)
		width = info->var.xres - x;
	if (y + height > info->var.yres)
		height = info->var.yres - y;

	/* 
	 * Fill first row, then use memmove to replicate to other rows.
	 * This is faster than per-pixel loops.
	 */
	dst = (u32 *)((u8 *)info->screen_buffer + y * line_bytes) + x;
	
	/* Fill first row */
	{
		u32 *p = dst;
		u32 w;
		for (w = 0; w < width; w++)
			*p++ = color;
	}
	
	/* Copy first row to remaining rows using memmove */
	if (height > 1) {
		u32 row_size = width * 4;
		u32 h;
		u8 *row_dst = (u8 *)dst + line_bytes;
		for (h = 1; h < height; h++) {
			memmove(row_dst, dst, row_size);
			row_dst += line_bytes;
		}
	}
}

/* Copy rectangle using memmove for each scanline */
static void subleqfb_copyarea(struct fb_info *info, const struct fb_copyarea *area)
{
	u8 *base = info->screen_buffer;
	u32 line_bytes = info->fix.line_length;
	u32 sx, sy, dx, dy, width, height;
	u32 row_bytes;

	sx = area->sx;
	sy = area->sy;
	dx = area->dx;
	dy = area->dy;
	width = area->width;
	height = area->height;
	row_bytes = width * 4;  /* 4 bytes per pixel */

	/* memmove handles overlapping regions correctly */
	if (dy <= sy) {
		/* Copy top-to-bottom */
		u32 h;
		for (h = 0; h < height; h++) {
			u8 *src_row = base + (sy + h) * line_bytes + sx * 4;
			u8 *dst_row = base + (dy + h) * line_bytes + dx * 4;
			memmove(dst_row, src_row, row_bytes);
		}
	} else {
		/* Copy bottom-to-top for overlapping regions */
		u32 h;
		for (h = height; h > 0; h--) {
			u8 *src_row = base + (sy + h - 1) * line_bytes + sx * 4;
			u8 *dst_row = base + (dy + h - 1) * line_bytes + dx * 4;
			memmove(dst_row, src_row, row_bytes);
		}
	}
}

/* Draw image (for fonts/cursors) - optimized for 8-pixel batches */
static void subleqfb_imageblit(struct fb_info *info, const struct fb_image *image)
{
	u32 *dst;
	const u8 *src;
	u32 fg, bg;
	u32 x, y, width, height;
	u32 line_words = info->fix.line_length / 4;

	/* Only support 1bpp images (monochrome fonts) */
	if (image->depth != 1)
		return;

	/* Get foreground and background colors */
	if (info->fix.visual == FB_VISUAL_TRUECOLOR) {
		fg = image->fg_color < 16 ? ((u32 *)info->pseudo_palette)[image->fg_color] : image->fg_color;
		bg = image->bg_color < 16 ? ((u32 *)info->pseudo_palette)[image->bg_color] : image->bg_color;
	} else {
		fg = image->fg_color;
		bg = image->bg_color;
	}

	x = image->dx;
	y = image->dy;
	width = image->width;
	height = image->height;

	src = image->data;
	dst = (u32 *)info->screen_buffer + y * line_words + x;

	/* Draw each scanline */
	for (; height > 0; height--) {
		u32 *p = dst;
		u32 w = 0;

		/* Process full bytes (8 pixels at a time) with unrolled loop */
		while (w + 8 <= width) {
			u8 byte = *src++;
			/* Unrolled: write 8 pixels from one byte */

			if (byte >= 0x80) { byte -= 0x80; *p++ = fg; } else *p++ = bg;
			if (byte >= 0x40) { byte -= 0x40; *p++ = fg; } else *p++ = bg;
			if (byte >= 0x20) { byte -= 0x20; *p++ = fg; } else *p++ = bg;
			if (byte >= 0x10) { byte -= 0x10; *p++ = fg; } else *p++ = bg;
			if (byte >= 0x08) { byte -= 0x08; *p++ = fg; } else *p++ = bg;
			if (byte >= 0x04) { byte -= 0x04; *p++ = fg; } else *p++ = bg;
			if (byte >= 0x02) { byte -= 0x02; *p++ = fg; } else *p++ = bg;
			if (byte >= 0x01) { *p++ = fg; } else *p++ = bg;

			w += 8;
		}

		/* Handle remaining pixels (width not multiple of 8) */
		if (w < width) {
			u8 byte = *src++;
			u8 mask = 0x80;
			while (w < width) {
				*p++ = (byte & mask) ? fg : bg;
				mask >>= 1;
				w++;
			}
		}

		dst += line_words;
	}
}

static const struct fb_ops subleqfb_ops = {
	.owner          = THIS_MODULE,
	__FB_DEFAULT_SYSMEM_OPS_RDWR,
	.fb_setcolreg   = subleqfb_setcolreg,
	/* Custom word-only drawing operations */
	.fb_fillrect    = subleqfb_fillrect,
	.fb_copyarea    = subleqfb_copyarea,
	.fb_imageblit   = subleqfb_imageblit,
};

static int subleqfb_probe(struct platform_device *pdev)
{
	struct fb_info *info;
	int ret;

	pr_info("subleqfb: probing device\n");

	info = framebuffer_alloc(0, &pdev->dev);
	if (!info)
		return -ENOMEM;

	info->var = subleqfb_var;
	info->fix = subleqfb_fix;
	info->fbops = &subleqfb_ops;
	info->flags = FBINFO_VIRTFB | FBINFO_READS_FAST;
	info->pseudo_palette = pseudo_palette;

	/*
	 * On NOMMU Subleq, physical == virtual, so we can directly
	 * point screen_buffer to the framebuffer address.
	 */
	info->screen_buffer = (void __iomem *)SUBLEQFB_FB_ADDR;
	info->screen_size = SUBLEQFB_FB_SIZE;



	ret = fb_alloc_cmap(&info->cmap, 256, 0);
	if (ret < 0) {
		framebuffer_release(info);
		return ret;
	}

	ret = register_framebuffer(info);
	if (ret < 0) {
		fb_dealloc_cmap(&info->cmap);
		framebuffer_release(info);
		return ret;
	}

	platform_set_drvdata(pdev, info);

	fb_info(info, "Subleq framebuffer at 0x%08lx, %dx%d %dbpp\n",
		SUBLEQFB_FB_ADDR, SUBLEQFB_WIDTH, SUBLEQFB_HEIGHT, SUBLEQFB_BPP);

	return 0;
}

static void subleqfb_remove(struct platform_device *pdev)
{
	struct fb_info *info = platform_get_drvdata(pdev);

	if (info) {
		unregister_framebuffer(info);
		fb_dealloc_cmap(&info->cmap);
		framebuffer_release(info);
	}
}

static struct platform_driver subleqfb_driver = {
	.probe  = subleqfb_probe,
	.remove = subleqfb_remove,
	.driver = {
		.name = "subleqfb",
	},
};

static struct platform_device *subleqfb_device;

static int __init subleqfb_init(void)
{
	int ret;

	pr_info("subleqfb: initializing\n");

	ret = platform_driver_register(&subleqfb_driver);
	if (ret)
		return ret;

	subleqfb_device = platform_device_alloc("subleqfb", 0);
	if (!subleqfb_device) {
		platform_driver_unregister(&subleqfb_driver);
		return -ENOMEM;
	}

	ret = platform_device_add(subleqfb_device);
	if (ret) {
		platform_device_put(subleqfb_device);
		platform_driver_unregister(&subleqfb_driver);
		return ret;
	}

	return 0;
}

static void __exit subleqfb_exit(void)
{
	platform_device_unregister(subleqfb_device);
	platform_driver_unregister(&subleqfb_driver);
}

/* Use device_initcall for earlier initialization, before fbcon */
device_initcall(subleqfb_init);
module_exit(subleqfb_exit);

MODULE_DESCRIPTION("Subleq Virtual Machine Framebuffer Driver");
MODULE_LICENSE("GPL");

