// SPDX-License-Identifier: GPL-2.0
/*
 * Subleq trap/exception handling
 */

#include <linux/kernel.h>
#include <linux/init.h>

/*
 * Trap handling stubs
 *
 * Subleq doesn't really have hardware traps/exceptions.
 * Everything is software-implemented.
 */

void __init trap_init(void)
{
	/* No hardware traps to set up */
}
