# UnifiedRISCV Makefile for M1 Mac with Verilator
# Optimized for Apple Silicon development

# Project configuration
PROJECT_NAME = unified_riscv_system
TOP_MODULE = unified_riscv_system
RTL_DIR = rtl
TB_DIR = verification/testbenches
SCRIPTS_DIR = scripts
BUILD_DIR = build
WAVES_DIR = waves

# Verilator configuration
VERILATOR = verilator
VERILATOR_FLAGS = -Wall -Wno-fatal --cc --exe --build
VERILATOR_FLAGS += --trace --trace-structs --trace-max-array 1024
VERILATOR_FLAGS += -O3 --x-assign fast --x-initial fast --noassert
VERILATOR_FLAGS += -CFLAGS "-O3 -march=native -mtune=native"
VERILATOR_FLAGS += -LDFLAGS "-O3"

# Source files
RTL_SOURCES = $(RTL_DIR)/$(TOP_MODULE).sv \
              $(RTL_DIR)/cpu/riscv_cpu.sv \
              $(RTL_DIR)/gpu/gpu_compute_array.sv \
              $(RTL_DIR)/gpu/gpu_compute_unit.sv \
              $(RTL_DIR)/memory/unified_memory_controller.sv \
              $(RTL_DIR)/memory/cache_hierarchy.sv

TB_SOURCES = $(TB_DIR)/tb_$(TOP_MODULE).cpp

# Synthesis tools (for FPGA implementation)
VIVADO = vivado
QUARTUS = quartus_sh

# Python environment
PYTHON = python3
VENV_DIR = venv
REQUIREMENTS = verification/requirements.txt

# Default target
.PHONY: all
all: setup verilate

# Setup development environment
.PHONY: setup
setup: $(VENV_DIR)/bin/activate
	@echo "Setting up development environment for M1 Mac..."
	@if ! command -v verilator >/dev/null 2>&1; then \
		echo "Installing Verilator via Homebrew..."; \
		brew install verilator; \
	fi
	@if ! command -v gtkwave >/dev/null 2>&1; then \
		echo "Installing GTKWave for waveform viewing..."; \
		brew install gtkwave; \
	fi
	@mkdir -p $(BUILD_DIR) $(WAVES_DIR)

# Python virtual environment
$(VENV_DIR)/bin/activate: $(REQUIREMENTS)
	$(PYTHON) -m venv $(VENV_DIR)
	$(VENV_DIR)/bin/pip install --upgrade pip
	$(VENV_DIR)/bin/pip install -r $(REQUIREMENTS)
	touch $(VENV_DIR)/bin/activate

# Verilator compilation
.PHONY: verilate
verilate: $(BUILD_DIR)/V$(TOP_MODULE)

$(BUILD_DIR)/V$(TOP_MODULE): $(RTL_SOURCES) $(TB_SOURCES)
	@echo "Compiling with Verilator..."
	@mkdir -p $(BUILD_DIR)
	cd $(BUILD_DIR) && $(VERILATOR) $(VERILATOR_FLAGS) \
		-I../$(RTL_DIR) -I../$(RTL_DIR)/cpu -I../$(RTL_DIR)/gpu -I../$(RTL_DIR)/memory \
		--top-module $(TOP_MODULE) \
		$(addprefix ../,$(RTL_SOURCES)) $(addprefix ../,$(TB_SOURCES))

# Run simulation
.PHONY: sim
sim: $(BUILD_DIR)/V$(TOP_MODULE)
	@echo "Running simulation..."
	cd $(BUILD_DIR) && ./V$(TOP_MODULE) +trace

# View waveforms
.PHONY: waves
waves:
	@if [ -f $(WAVES_DIR)/dump.vcd ]; then \
		gtkwave $(WAVES_DIR)/dump.vcd $(SCRIPTS_DIR)/gtkwave_signals.gtkw & \
	else \
		echo "No waveform file found. Run 'make sim' first."; \
	fi

# Python tests with cocotb
.PHONY: test-python
test-python: $(VENV_DIR)/bin/activate
	@echo "Running Python/cocotb tests..."
	cd verification/tests && ../../$(VENV_DIR)/bin/python -m pytest -v

# Performance benchmarks
.PHONY: benchmark
benchmark: $(VENV_DIR)/bin/activate
	@echo "Running performance benchmarks..."
	cd software/benchmarks && ../../$(VENV_DIR)/bin/python benchmark_suite.py

# Compile example software
.PHONY: software
software:
	@echo "Compiling example ML kernels..."
	cd software/kernels && $(MAKE) all

# Lint RTL code
.PHONY: lint
lint:
	@echo "Linting SystemVerilog code..."
	verilator --lint-only -Wall $(RTL_SOURCES)

# Generate synthesis reports
.PHONY: synth-report
synth-report:
	@echo "Generating synthesis resource estimates..."
	@echo "Estimated LUT usage for 8 GPU units:"
	@echo "- CPU Core: ~2,000 LUTs"
	@echo "- GPU Array (8 units): ~24,000 LUTs" 
	@echo "- Memory Controller: ~4,000 LUTs"
	@echo "- Cache Hierarchy: ~8,000 LUTs"
	@echo "Total: ~38,000 LUTs (fits in mid-range FPGA)"

# Performance analysis
.PHONY: performance
performance:
	@echo "Performance Analysis:"
	@echo "Base Configuration (8 units @ 100MHz):"
	@echo "- Matrix ops/sec: 100M"
	@echo "- INT8 TOPS: 0.128"
	@echo "Scaling to 11.5 TOPS (M1 Neural Engine equivalent):"
	@echo "- Need 90x improvement"
	@echo "- Options: 3x frequency (300MHz) + 30x more units (240 units)"
	@echo "- Or: Mixed precision (FP16/INT4) + 16x units @ 200MHz"

# FPGA implementation targets
.PHONY: fpga-xilinx
fpga-xilinx:
	@echo "Synthesizing for Xilinx FPGA..."
	$(VIVADO) -mode batch -source $(SCRIPTS_DIR)/xilinx_synth.tcl

.PHONY: fpga-intel
fpga-intel:
	@echo "Synthesizing for Intel FPGA..."
	$(QUARTUS) --flow compile $(PROJECT_NAME) -c $(TOP_MODULE)

# Clean build artifacts
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(WAVES_DIR)/*.vcd
	cd software/kernels && $(MAKE) clean

# Deep clean including Python environment
.PHONY: distclean
distclean: clean
	rm -rf $(VENV_DIR)
	rm -rf __pycache__ verification/__pycache__ verification/tests/__pycache__

# Help target
.PHONY: help
help:
	@echo "UnifiedRISCV Makefile - M1 Mac Optimized"
	@echo ""
	@echo "Main targets:"
	@echo "  all          - Setup environment and compile"
	@echo "  setup        - Install dependencies (Homebrew required)"
	@echo "  verilate     - Compile RTL with Verilator"
	@echo "  sim          - Run simulation with waveform generation"
	@echo "  waves        - View waveforms in GTKWave"
	@echo "  test-python  - Run Python/cocotb tests"
	@echo "  benchmark    - Run performance benchmarks"
	@echo "  software     - Compile example ML kernels"
	@echo "  lint         - Lint SystemVerilog code"
	@echo ""
	@echo "Analysis targets:"
	@echo "  synth-report - Show estimated FPGA resource usage"
	@echo "  performance  - Show performance scaling analysis"
	@echo ""
	@echo "FPGA targets:"
	@echo "  fpga-xilinx  - Synthesize for Xilinx FPGAs"
	@echo "  fpga-intel   - Synthesize for Intel FPGAs"
	@echo ""
	@echo "Utility targets:"
	@echo "  clean        - Remove build artifacts"
	@echo "  distclean    - Remove all generated files"
	@echo "  help         - Show this help message"

# Make variables visible for debugging
.PHONY: debug-vars
debug-vars:
	@echo "RTL_SOURCES: $(RTL_SOURCES)"
	@echo "TB_SOURCES: $(TB_SOURCES)"
	@echo "VERILATOR_FLAGS: $(VERILATOR_FLAGS)"