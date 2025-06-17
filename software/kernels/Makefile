# Makefile for UnifiedRISCV ML Kernels
# Cross-compilation for RISC-V target

# RISC-V toolchain
RISCV_PREFIX = riscv32-unknown-elf-
CC = $(RISCV_PREFIX)gcc
AS = $(RISCV_PREFIX)as
LD = $(RISCV_PREFIX)ld
OBJCOPY = $(RISCV_PREFIX)objcopy
OBJDUMP = $(RISCV_PREFIX)objdump

# Compiler flags
CFLAGS = -march=rv32i -mabi=ilp32 -O2 -Wall -Wextra
CFLAGS += -fno-builtin -nostdlib -nostartfiles
CFLAGS += -I./include
ASFLAGS = -march=rv32i -mabi=ilp32

# Linker flags
LDFLAGS = -T linker.ld -nostdlib -static

# Sources
SOURCES = matrix_multiply.c conv2d.c vector_add.c
ASM_SOURCES = startup.s gpu_interface.s
OBJECTS = $(SOURCES:.c=.o) $(ASM_SOURCES:.s=.o)

# Targets
TARGET = ml_kernels
BINARY = $(TARGET).bin
DISASM = $(TARGET).dis

.PHONY: all clean install

all: $(BINARY) $(DISASM)

$(TARGET): $(OBJECTS)
	$(LD) $(LDFLAGS) -o $@ $^

$(BINARY): $(TARGET)
	$(OBJCOPY) -O binary $< $@

$(DISASM): $(TARGET)
	$(OBJDUMP) -D $< > $@

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.s
	$(AS) $(ASFLAGS) -o $@ $<

clean:
	rm -f $(OBJECTS) $(TARGET) $(BINARY) $(DISASM)

install: $(BINARY)
	cp $(BINARY) ../../verification/testbenches/

# Help target
help:
	@echo "Available targets:"
	@echo "  all      - Build all kernels"
	@echo "  clean    - Remove build artifacts"
	@echo "  install  - Copy binary to testbench directory"
	@echo "  help     - Show this help"