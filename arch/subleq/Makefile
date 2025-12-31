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

# Wrap signed integer overflow (important for Subleq runtime)
KBUILD_CFLAGS += -fwrapv

# Subleq-specific: disable features that generate problematic code
KBUILD_CFLAGS += -fno-optimize-sibling-calls

# Stack size for the kernel (near top of 1GB address space)
# 0x3F000000 = 1008MB, leaving ~16MB for stack
SUBLEQ_STACK_SIZE := 0x3F000000

# Text start address (after boot area)
SUBLEQ_TEXT_START := 0x1000

export SUBLEQ_STACK_SIZE SUBLEQ_TEXT_START

# Head object comes first
head-y := arch/subleq/kernel/head.o

# Core directories
core-y += arch/subleq/

# Linker flags
LDFLAGS_vmlinux := -T $(srctree)/arch/subleq/kernel/vmlinux.lds

PHONY += archheaders
archheaders:

PHONY += archscripts
archscripts:

archclean:
	$(Q)$(MAKE) $(clean)=arch/subleq

# Ensure all targets are declared
.PHONY: $(PHONY)
