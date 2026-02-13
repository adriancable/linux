// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq Keyboard Input Driver
 *
 * Polls __subleq_getchar() for SDL scancode events and feeds them
 * into the Linux input subsystem. The VT keyboard layer handles
 * keymap translation, shift states, Ctrl combos, F-keys, etc.
 *
 * Protocol from VM: one int per key event
 *   positive = SDL scancode (key down)
 *   negative = -SDL scancode (key up)
 *   0 = no key pending
 *
 * SDL scancodes are USB HID usage page 0x07 codes. The mapping
 * table from HID usage to Linux KEY_* is copied from
 * drivers/hid/hid-input.c (hid_keyboard[256]).
 *
 * For serial console (vm.c without framebuffer), we fall back to
 * injecting raw ASCII bytes into ttyS0.
 */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/timer.h>
#include <linux/jiffies.h>
#include <linux/input.h>
#include <linux/tty.h>
#include <linux/tty_flip.h>
#include <linux/vt_kern.h>

/* Polling interval for keyboard input (in jiffies) */
#define SUBLEQ_KBD_POLL_INTERVAL (HZ / 100) /* 10ms */

/* External I/O intrinsic from compiler */
extern int __subleq_getchar(void);

/* External function to inject to ttyS0 (serial fallback) */
extern void subleq_tty_inject_char(unsigned char c);

static struct timer_list subleq_kbd_timer;
static struct input_dev *subleq_kbd_dev;

/*
 * USB HID usage code -> Linux KEY_* mapping table.
 * Copied from drivers/hid/hid-input.c hid_keyboard[256].
 * SDL scancodes ARE USB HID usage codes (page 0x07).
 */
static const unsigned char hid_to_keycode[256] = {
	  0,  0,  0,  0, 30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38,
	 50, 49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44,  2,  3,
	  4,  5,  6,  7,  8,  9, 10, 11, 28,  1, 14, 15, 57, 12, 13, 26,
	 27, 43, 43, 39, 40, 41, 51, 52, 53, 58, 59, 60, 61, 62, 63, 64,
	 65, 66, 67, 68, 87, 88, 99, 70,119,110,102,104,111,107,109,106,
	105,108,103, 69, 98, 55, 74, 78, 96, 79, 80, 81, 75, 76, 77, 71,
	 72, 73, 82, 83, 86,127,116,117,183,184,185,186,187,188,189,190,
	191,192,193,194,134,138,130,132,128,129,131,137,133,135,136,113,
	115,114,  0,  0,  0,121,  0, 89, 93,124, 92, 94, 95,  0,  0,  0,
	122,123, 90, 91, 85,  0,  0,  0,  0,  0,  0,  0,111,  0,  0,  0,
	  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
	  0,  0,  0,  0,  0,  0,179,180,  0,  0,  0,  0,  0,  0,  0,  0,
	  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
	  0,  0,  0,  0,  0,  0,  0,  0,111,  0,  0,  0,  0,  0,  0,  0,
	 29, 42, 56,125, 97, 54,100,126,164,166,165,163,161,115,114,113,
	150,158,159,128,136,177,178,176,142,152,173,140,  0,  0,  0,  0
};

/*
 * Detect whether framebuffer console is active at runtime.
 * Both VMs use the same kernel binary. The serial VM boots with
 * console=ttyS0, while the framebuffer VM uses console=tty0 (or default).
 */
static bool subleq_fbcon_active(void)
{
	return !strstr(saved_command_line, "console=ttyS");
}

/*
 * Serial console fallback: inject ASCII into VT and ttyS0
 */
static void subleq_kbd_inject_to_vt(unsigned char c)
{
	struct tty_struct *tty;
	int fg_console_num;

	fg_console_num = fg_console;
	tty = vc_cons[fg_console_num].d->port.tty;
	if (tty) {
		tty_insert_flip_char(tty->port, c, TTY_NORMAL);
		tty_flip_buffer_push(tty->port);
	}
}

/*
 * Timer callback to poll for keyboard input
 */
static void subleq_kbd_poll(struct timer_list *t)
{
	int c;

	if (subleq_fbcon_active() && subleq_kbd_dev) {
		/*
		 * Framebuffer mode: read single-int scancode events.
		 * Positive = key down, negative = key up.
		 */
		while ((c = __subleq_getchar()) != 0) {
			int scancode = c > 0 ? c : -c;
			int keycode;

			if (scancode > 255)
				continue;

			keycode = hid_to_keycode[scancode];
			if (keycode == 0)
				continue; /* unmapped key */

			input_report_key(subleq_kbd_dev, keycode,
					 c > 0 ? 1 : 0);
			input_sync(subleq_kbd_dev);
		}
	} else {
		/*
		 * Serial mode: inject raw ASCII into VT + ttyS0
		 * (legacy path for vm.c without framebuffer)
		 */
		while ((c = __subleq_getchar()) != 0) {
			unsigned char ch = (unsigned char)c;
			subleq_kbd_inject_to_vt(ch);
			subleq_tty_inject_char(ch);
		}
	}

	/* Re-arm timer */
	mod_timer(&subleq_kbd_timer, jiffies + SUBLEQ_KBD_POLL_INTERVAL);
}

/*
 * Driver initialization
 */
static int __init subleq_kbd_init(void)
{
	int i, error;

	pr_info("subleq_kbd: initializing keyboard driver\n");

	if (subleq_fbcon_active()) {
		/* Allocate and register input device */
		subleq_kbd_dev = input_allocate_device();
		if (!subleq_kbd_dev) {
			pr_err("subleq_kbd: failed to allocate input device\n");
			return -ENOMEM;
		}

		subleq_kbd_dev->name = "ESI Virtual Keyboard";
		subleq_kbd_dev->phys = "subleq/input0";
		subleq_kbd_dev->id.bustype = BUS_VIRTUAL;
		subleq_kbd_dev->id.vendor = 0x0001;
		subleq_kbd_dev->id.product = 0x0001;
		subleq_kbd_dev->id.version = 0x0001;

		/* We generate key events and support auto-repeat */
		set_bit(EV_KEY, subleq_kbd_dev->evbit);
		set_bit(EV_REP, subleq_kbd_dev->evbit);

		/* Mark all keys that appear in the mapping table */
		for (i = 0; i < 256; i++) {
			if (hid_to_keycode[i])
				set_bit(hid_to_keycode[i],
					subleq_kbd_dev->keybit);
		}

		error = input_register_device(subleq_kbd_dev);
		if (error) {
			pr_err("subleq_kbd: failed to register input device: %d\n",
			       error);
			input_free_device(subleq_kbd_dev);
			subleq_kbd_dev = NULL;
			return error;
		}

		/* Override repeat delay after registration (default 250ms) */
		subleq_kbd_dev->rep[REP_DELAY] = 500;

		pr_info("subleq_kbd: registered input device (scancode mode)\n");
	} else {
		pr_info("subleq_kbd: registered input device (serial mode)\n");
	}

	/* Initialize and start polling timer */
	timer_setup(&subleq_kbd_timer, subleq_kbd_poll, 0);
	mod_timer(&subleq_kbd_timer, jiffies + SUBLEQ_KBD_POLL_INTERVAL);

	pr_info("subleq_kbd: keyboard driver registered\n");
	return 0;
}

device_initcall(subleq_kbd_init);
