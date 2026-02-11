# SPDX-License-Identifier: GPL-2.0
# Makefile for the Subleq architecture

KBUILD_DEFCONFIG = defconfig

# Note: We rely on LLVM= being passed on the command line
# The kernel build system will set up the toolchain paths

# Freestanding environment - no libc
KBUILD_CFLAGS += -ffreestanding
KBUILD_CFLAGS += -fno-builtin
KBUILD_CFLAGS += -fno-stack-protector

# No PIC/PIE - we run at fixed addresses
KBUILD_CFLAGS += -fno-pic -fno-pie

# Suppress false positive array-bounds warnings from signal.h macros
# (switch-based code with compile-time constant _NSIG_WORDS=2)
KBUILD_CFLAGS += -Wno-array-bounds

# Text start address (after boot area)
SUBLEQ_TEXT_START := 0x1000

export SUBLEQ_TEXT_START

# Head object comes first
head-y := arch/subleq/kernel/head.o

# Core directories
core-y += arch/subleq/

# Note: The kernel build system uses KBUILD_LDS from $(srctree)/Makefile
# which points to arch/$(SRCARCH)/kernel/vmlinux.lds - no need to set it here

PHONY += archheaders
archheaders:

PHONY += archscripts
archscripts:

archclean:
	$(Q)$(MAKE) $(clean)=arch/subleq

# Ensure all targets are declared
.PHONY: $(PHONY)
