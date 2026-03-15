// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq-optimized bitblit for fbcon
 *
 * Overrides the generic bitblit with: memcpy instead of byte-by-byte copy,
 * loop-invariant hoisting, fast path for 8px wide fonts, and direct
 * framebuffer rendering that skips the intermediate pixmap buffer.
 */

#include <linux/module.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/fb.h>
#include <linux/vt_kern.h>
#include <linux/console.h>
#include <asm/types.h>
#include "../../../drivers/video/fbdev/core/fbcon.h"

/*
 * Render characters directly to 32bpp framebuffer, bypassing the pixmap.
 * See the assembly implementation for parameter details.
 */
extern void subleq_direct_putcs(u32 *fb, u32 fb_pitch, u32 x, u32 y,
				const u32 *font, const u16 *s, u32 cnt,
				u32 s_pitch, u32 fg, u32 bg);


/*
 * Expanded font: one word per byte for fast word-aligned access.
 * 256 chars × 16 rows × 4 bytes = 16KB.
 */
static u32 expanded_font[256 * 16] __aligned(4);
static const u8 *current_font_data;
static bool font_expanded;

/*
 * Expand packed font data (1 byte per row) to word-aligned (1 word per row).
 * Called once per font change.
 */
static void expand_font(const u8 *packed, u32 charcount, u32 height)
{
	u32 i;
	u32 total = charcount * height;

	/* Limit to 256 chars × 16 rows = 4096 entries */
	if (total > 256 * 16)
		total = 256 * 16;

	for (i = 0; i < total; i++)
		expanded_font[i] = (u32)packed[i];
}

/*
 * Update attributes (underline/bold/reverse) on font data.
 * This is relatively rare in normal console usage.
 */
static void update_attr(u8 *dst, u8 *src, int attribute, struct vc_data *vc)
{
	int i, offset = (vc->vc_font.height < 10) ? 1 : 2;
	int width = DIV_ROUND_UP(vc->vc_font.width, 8);
	unsigned int cellsize = vc->vc_font.height * width;
	u8 c;

	offset = cellsize - (offset * width);
	for (i = 0; i < cellsize; i++) {
		c = src[i];
		if (attribute & FBCON_ATTRIBUTE_UNDERLINE && i >= offset)
			c = 0xff;
		if (attribute & FBCON_ATTRIBUTE_BOLD)
			c |= c >> 1;
		if (attribute & FBCON_ATTRIBUTE_REVERSE)
			c = ~c;
		dst[i] = c;
	}
}

static void bit_bmove(struct vc_data *vc, struct fb_info *info, int sy,
		      int sx, int dy, int dx, int height, int width)
{
	struct fb_copyarea area;

	area.sx = sx * vc->vc_font.width;
	area.sy = sy * vc->vc_font.height;
	area.dx = dx * vc->vc_font.width;
	area.dy = dy * vc->vc_font.height;
	area.height = height * vc->vc_font.height;
	area.width = width * vc->vc_font.width;

	info->fbops->fb_copyarea(info, &area);
}

static void bit_clear(struct vc_data *vc, struct fb_info *info, int sy,
		      int sx, int height, int width, int fg, int bg)
{
	struct fb_fillrect region;

	region.color = bg;
	region.dx = sx * vc->vc_font.width;
	region.dy = sy * vc->vc_font.height;
	region.width = width * vc->vc_font.width;
	region.height = height * vc->vc_font.height;
	region.rop = ROP_COPY;

	info->fbops->fb_fillrect(info, &region);
}

/* Fast path for 8px font: each scanline is 1 byte, can use memcpy */
static inline void subleq_pad_8pixel(u8 *dst, u32 d_pitch, u8 *src, u32 height)
{
	/* When d_pitch == 1 (single character), entire cell is contiguous */
	if (d_pitch == 1) {
		memcpy(dst, src, height);
	} else {
		/* Multiple characters per row in buffer - copy row by row */
		u32 i;
		for (i = 0; i < height; i++) {
			dst[0] = src[i];
			dst += d_pitch;
		}
	}
}

/*
 * Aligned putcs for 8px wide fonts.
 * Hoists charmask/cellsize/height out of the loop. Separate
 * fast/medium/slow paths for no-attr, wider fonts, and attr cases.
 */
static void bit_putcs_aligned(struct vc_data *vc, struct fb_info *info,
			      const u16 *s, u32 attr, u32 cnt,
			      u32 d_pitch, u32 s_pitch, u32 cellsize,
			      struct fb_image *image, u8 *buf, u8 *dst)
{
	const u16 charmask = vc->vc_hi_font_mask ? 0x1ff : 0xff;
	const unsigned int charcnt = vc->vc_font.charcount;
	const u8 *fontdata = vc->vc_font.data;
	const u32 height = image->height;
	const u32 idx = vc->vc_font.width >> 3;
	u8 *src;
	u16 ch;

	if (likely(idx == 1 && !attr)) {

		/*
		 * FAST PATH: 8-pixel font, no attributes (other heights)
		 * This is the common case for normal console text
		 */
		while (cnt--) {
			ch = scr_readw(s++) & charmask;
			if (unlikely(ch >= charcnt))
				ch = 0;
			src = (u8 *)fontdata + ch * cellsize;
			subleq_pad_8pixel(dst, d_pitch, src, height);
			dst += s_pitch;
		}
	} else if (likely(!attr)) {
		/*
		 * MEDIUM PATH: wider fonts, no attributes
		 * Use memcpy for each character cell
		 */
		const u32 row_bytes = idx;
		while (cnt--) {
			u32 row;
			ch = scr_readw(s++) & charmask;
			if (unlikely(ch >= charcnt))
				ch = 0;
			src = (u8 *)fontdata + ch * cellsize;
			
			/* Copy font data to pixmap buffer */
			for (row = 0; row < height; row++) {
				memcpy(dst + row * d_pitch, src, row_bytes);
				src += row_bytes;
			}
			dst += s_pitch;
		}
	} else {
		/*
		 * SLOW PATH: attributes needed (rare)
		 */
		while (cnt--) {
			ch = scr_readw(s++) & charmask;
			if (unlikely(ch >= charcnt))
				ch = 0;
			src = (u8 *)fontdata + ch * cellsize;
			update_attr(buf, src, attr, vc);
			src = buf;

			if (likely(idx == 1)) {
				subleq_pad_8pixel(dst, d_pitch, src, height);
			} else {
				u32 row;
				for (row = 0; row < height; row++) {
					memcpy(dst + row * d_pitch, src, idx);
					src += idx;
				}
			}
			dst += s_pitch;
		}
	}

	info->fbops->fb_imageblit(info, image);
}

/*
 * Unaligned font path (font width not multiple of 8)
 * Less common, so less aggressively optimized
 */
static void bit_putcs_unaligned(struct vc_data *vc, struct fb_info *info,
				const u16 *s, u32 attr, u32 cnt, u32 d_pitch,
				u32 s_pitch, u32 cellsize,
				struct fb_image *image, u8 *buf, u8 *dst)
{
	u16 charmask = vc->vc_hi_font_mask ? 0x1ff : 0xff;
	unsigned int charcnt = vc->vc_font.charcount;
	u32 shift_low = 0, mod = vc->vc_font.width % 8;
	u32 shift_high = 8;
	u32 idx = vc->vc_font.width >> 3;
	u8 *src;

	while (cnt--) {
		u16 ch = scr_readw(s++) & charmask;

		if (ch >= charcnt)
			ch = 0;
		src = vc->vc_font.data + (unsigned int)ch * cellsize;

		if (attr) {
			update_attr(buf, src, attr, vc);
			src = buf;
		}

		fb_pad_unaligned_buffer(dst, d_pitch, src, idx,
					image->height, shift_high,
					shift_low, mod);
		shift_low += mod;
		dst += (shift_low >= 8) ? s_pitch : s_pitch - 1;
		shift_low &= 7;
		shift_high = 8 - shift_low;
	}

	info->fbops->fb_imageblit(info, image);
}

static void bit_putcs(struct vc_data *vc, struct fb_info *info,
		      const unsigned short *s, int count, int yy, int xx,
		      int fg, int bg)
{
	struct fb_image image;
	u32 width, cellsize, maxcnt, scan_align, buf_align;
	u32 mod, cnt, pitch, size, attribute;
	u8 *dst, *buf = NULL;

	image.fg_color = fg;
	image.bg_color = bg;
	image.dx = xx * vc->vc_font.width;
	image.dy = yy * vc->vc_font.height;
	image.height = vc->vc_font.height;
	image.depth = 1;

	if (image.dy >= info->var.yres)
		return;

	image.height = min(image.height, info->var.yres - image.dy);

	/*
	 * SUBLEQ DIRECT FRAMEBUFFER PATH
	 * For 8x16 fonts with no attributes, render directly to framebuffer
	 * bypassing the intermediate pixmap buffer entirely.
	 */
	if (likely(vc->vc_font.width == 8 && vc->vc_font.height == 16 &&
		   info->var.bits_per_pixel == 32)) {
		const u8 *fontdata = vc->vc_font.data;
		u32 fb_fg, fb_bg;
		int s_off = ((uintptr_t)s) & 2;

		/* Expand font on first use or if font changed */
		if (!font_expanded || current_font_data != fontdata) {
			expand_font(fontdata, vc->vc_font.charcount, 16);
			current_font_data = fontdata;
			font_expanded = true;
		}

		/* Convert palette indices to 32-bit colors */
		fb_fg = fg < 16 ? ((u32 *)info->pseudo_palette)[fg] : fg;
		fb_bg = bg < 16 ? ((u32 *)info->pseudo_palette)[bg] : bg;

		/* Render directly to framebuffer.
		 * Word-align s for pair processing; pass byte offset
		 * (0 or 2) via s_pitch so assembly can skip char0
		 * on the first iteration when misaligned.
		 */
		subleq_direct_putcs((u32 *)info->screen_base,
				    info->fix.line_length,
				    image.dx, image.dy,
				    expanded_font,
				    (const u16 *)((uintptr_t)s & ~3),
				    count,
				    s_off, fb_fg, fb_bg);
		return;
	}

	/* Slow path: compute values only needed for pixmap rendering */
	width = DIV_ROUND_UP(vc->vc_font.width, 8);
	cellsize = width * vc->vc_font.height;
	maxcnt = info->pixmap.size / cellsize;
	scan_align = info->pixmap.scan_align - 1;
	buf_align = info->pixmap.buf_align - 1;
	mod = vc->vc_font.width % 8;
	attribute = get_attribute(info, scr_readw(s));

	if (attribute) {
		buf = kmalloc(cellsize, GFP_ATOMIC);
		if (!buf)
			return;
	}

	while (count) {
		if (count > maxcnt)
			cnt = maxcnt;
		else
			cnt = count;

		image.width = vc->vc_font.width * cnt;

		if (image.dx >= info->var.xres)
			break;

		if (image.dx + image.width > info->var.xres) {
			image.width = info->var.xres - image.dx;
			cnt = image.width / vc->vc_font.width;
			if (cnt == 0)
				break;
			image.width = cnt * vc->vc_font.width;
		}

		pitch = DIV_ROUND_UP(image.width, 8) + scan_align;
		pitch &= ~scan_align;
		size = pitch * image.height + buf_align;
		size &= ~buf_align;
		dst = fb_get_buffer_offset(info, &info->pixmap, size);
		image.data = dst;

		if (!mod)
			bit_putcs_aligned(vc, info, s, attribute, cnt, pitch,
					  width, cellsize, &image, buf, dst);
		else
			bit_putcs_unaligned(vc, info, s, attribute, cnt,
					    pitch, width, cellsize, &image,
					    buf, dst);

		image.dx += cnt * vc->vc_font.width;
		count -= cnt;
		s += cnt;
	}

	if (unlikely(buf))
		kfree(buf);
}

static void bit_clear_margins(struct vc_data *vc, struct fb_info *info,
			      int color, int bottom_only)
{
	unsigned int cw = vc->vc_font.width;
	unsigned int ch = vc->vc_font.height;
	unsigned int rw = info->var.xres - (vc->vc_cols * cw);
	unsigned int bh = info->var.yres - (vc->vc_rows * ch);
	unsigned int rs = info->var.xres - rw;
	unsigned int bs = info->var.yres - bh;
	struct fb_fillrect region;

	region.color = color;
	region.rop = ROP_COPY;

	if ((int)rw > 0 && !bottom_only) {
		region.dx = info->var.xoffset + rs;
		region.dy = 0;
		region.width = rw;
		region.height = info->var.yres_virtual;
		info->fbops->fb_fillrect(info, &region);
	}

	if ((int)bh > 0) {
		region.dx = info->var.xoffset;
		region.dy = info->var.yoffset + bs;
		region.width = rs;
		region.height = bh;
		info->fbops->fb_fillrect(info, &region);
	}
}

static void bit_cursor(struct vc_data *vc, struct fb_info *info, bool enable,
		       int fg, int bg)
{
	struct fb_cursor cursor;
	struct fbcon_par *par = info->fbcon_par;
	unsigned short charmask = vc->vc_hi_font_mask ? 0x1ff : 0xff;
	int w = DIV_ROUND_UP(vc->vc_font.width, 8), c;
	int y = real_y(par->p, vc->state.y);
	int attribute, use_sw = vc->vc_cursor_type & CUR_SW;
	int err = 1;
	char *src;

	cursor.set = 0;

	if (!vc->vc_font.data)
		return;

	c = scr_readw((u16 *)vc->vc_pos);
	attribute = get_attribute(info, c);
	src = vc->vc_font.data + ((c & charmask) * (w * vc->vc_font.height));

	if (par->cursor_state.image.data != src ||
	    par->cursor_reset) {
		par->cursor_state.image.data = src;
		cursor.set |= FB_CUR_SETIMAGE;
	}

	if (attribute) {
		u8 *dst;

		dst = kmalloc_array(w, vc->vc_font.height, GFP_ATOMIC);
		if (!dst)
			return;
		kfree(par->cursor_data);
		par->cursor_data = dst;
		update_attr(dst, src, attribute, vc);
		src = dst;
	}

	if (par->cursor_state.image.fg_color != fg ||
	    par->cursor_state.image.bg_color != bg ||
	    par->cursor_reset) {
		par->cursor_state.image.fg_color = fg;
		par->cursor_state.image.bg_color = bg;
		cursor.set |= FB_CUR_SETCMAP;
	}

	if ((par->cursor_state.image.dx != (vc->vc_font.width * vc->state.x)) ||
	    (par->cursor_state.image.dy != (vc->vc_font.height * y)) ||
	    par->cursor_reset) {
		par->cursor_state.image.dx = vc->vc_font.width * vc->state.x;
		par->cursor_state.image.dy = vc->vc_font.height * y;
		cursor.set |= FB_CUR_SETPOS;
	}

	if (par->cursor_state.image.height != vc->vc_font.height ||
	    par->cursor_state.image.width != vc->vc_font.width ||
	    par->cursor_reset) {
		par->cursor_state.image.height = vc->vc_font.height;
		par->cursor_state.image.width = vc->vc_font.width;
		cursor.set |= FB_CUR_SETSIZE;
	}

	if (par->cursor_state.hot.x || par->cursor_state.hot.y ||
	    par->cursor_reset) {
		par->cursor_state.hot.x = cursor.hot.y = 0;
		cursor.set |= FB_CUR_SETHOT;
	}

	if (cursor.set & FB_CUR_SETSIZE ||
	    vc->vc_cursor_type != par->p->cursor_shape ||
	    par->cursor_state.mask == NULL ||
	    par->cursor_reset) {
		char *mask = kmalloc_array(w, vc->vc_font.height, GFP_ATOMIC);
		int cur_height, size, i = 0;
		u8 msk = 0xff;

		if (!mask)
			return;

		kfree(par->cursor_state.mask);
		par->cursor_state.mask = mask;

		par->p->cursor_shape = vc->vc_cursor_type;
		cursor.set |= FB_CUR_SETSHAPE;

		switch (CUR_SIZE(par->p->cursor_shape)) {
		case CUR_NONE:
			cur_height = 0;
			break;
		case CUR_UNDERLINE:
			cur_height = (vc->vc_font.height < 10) ? 1 : 2;
			break;
		case CUR_LOWER_THIRD:
			cur_height = vc->vc_font.height / 3;
			break;
		case CUR_LOWER_HALF:
			cur_height = vc->vc_font.height >> 1;
			break;
		case CUR_TWO_THIRDS:
			cur_height = (vc->vc_font.height << 1) / 3;
			break;
		case CUR_BLOCK:
		default:
			cur_height = vc->vc_font.height;
			break;
		}

		size = (vc->vc_font.height - cur_height) * w;
		memset(mask, ~msk, size);
		i = size;
		size = cur_height * w;
		memset(mask + i, msk, size);
	}

	par->cursor_state.enable = enable && !use_sw;

	cursor.image.data = src;
	cursor.image.fg_color = par->cursor_state.image.fg_color;
	cursor.image.bg_color = par->cursor_state.image.bg_color;
	cursor.image.dx = par->cursor_state.image.dx;
	cursor.image.dy = par->cursor_state.image.dy;
	cursor.image.height = par->cursor_state.image.height;
	cursor.image.width = par->cursor_state.image.width;
	cursor.hot.x = par->cursor_state.hot.x;
	cursor.hot.y = par->cursor_state.hot.y;
	cursor.mask = par->cursor_state.mask;
	cursor.enable = par->cursor_state.enable;
	cursor.image.depth = 1;
	cursor.rop = ROP_XOR;

	if (info->fbops->fb_cursor)
		err = info->fbops->fb_cursor(info, &cursor);

	if (err)
		soft_cursor(info, &cursor);

	par->cursor_reset = 0;
}

static int bit_update_start(struct fb_info *info)
{
	struct fbcon_par *par = info->fbcon_par;
	int err;

	err = fb_pan_display(info, &par->var);
	par->var.xoffset = info->var.xoffset;
	par->var.yoffset = info->var.yoffset;
	par->var.vmode = info->var.vmode;
	return err;
}

static const struct fbcon_bitops bit_fbcon_bitops = {
	.bmove = bit_bmove,
	.clear = bit_clear,
	.putcs = bit_putcs,
	.clear_margins = bit_clear_margins,
	.cursor = bit_cursor,
	.update_start = bit_update_start,
};

void fbcon_set_bitops_ur(struct fbcon_par *par)
{
	par->bitops = &bit_fbcon_bitops;
}
