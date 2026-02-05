// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq Keyboard Input Driver
 *
 * Simple input driver that polls __subleq_getchar() and injects
 * characters directly into the TTY layer for both VT and serial consoles.
 *
 * We bypass the full input subsystem to avoid ASCII→keycode→ASCII
 * conversion issues. Instead, we inject ASCII directly into the
 * foreground VT console and the serial tty.
 */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/timer.h>
#include <linux/jiffies.h>
#include <linux/tty.h>
#include <linux/tty_flip.h>
#include <linux/vt_kern.h>

/* Polling interval for keyboard input (in jiffies) */
#define SUBLEQ_KBD_POLL_INTERVAL (HZ / 100) /* 10ms */

/* External I/O intrinsic from compiler */
extern int __subleq_getchar(void);

/* External function to inject to ttyS0 */
extern void subleq_tty_inject_char(unsigned char c);

static struct timer_list subleq_kbd_timer;

/*
 * Inject a character into the foreground VT console
 */
static void subleq_kbd_inject_to_vt(unsigned char c)
{
	struct tty_struct *tty;
	int fg_console_num;

	/* Get the foreground console number */
	fg_console_num = fg_console;
	
	/* Get the tty for this console */
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

	/* Poll for available characters */
	while ((c = __subleq_getchar()) != 0) {
		unsigned char ch = (unsigned char)c;
		
		/* Inject to foreground VT console */
		subleq_kbd_inject_to_vt(ch);
		
		/* Also inject to ttyS0 for serial console compatibility */
		subleq_tty_inject_char(ch);
	}

	/* Re-arm timer */
	mod_timer(&subleq_kbd_timer, jiffies + SUBLEQ_KBD_POLL_INTERVAL);
}

/*
 * Driver initialization
 */
static int __init subleq_kbd_init(void)
{
	pr_info("subleq_kbd: initializing keyboard driver\n");

	/* Initialize and start polling timer */
	timer_setup(&subleq_kbd_timer, subleq_kbd_poll, 0);
	mod_timer(&subleq_kbd_timer, jiffies + SUBLEQ_KBD_POLL_INTERVAL);

	pr_info("subleq_kbd: keyboard driver registered\n");
	return 0;
}

device_initcall(subleq_kbd_init);
