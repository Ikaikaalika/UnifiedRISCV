# UnifiedRISCV - RISC-V CPU/GPU System for Deep Learning

A complete RISC-V CPU/GPU system with unified memory architecture, optimized for deep learning workloads on Apple Silicon (M1/M2) development platforms.

## 🚀 Overview

UnifiedRISCV is a synthesizable RTL implementation featuring:

- **RV32I RISC-V CPU core** with custom GPU instructions
- **8 GPU compute units** performing 4x4 matrix multiply-accumulate operations
- **Unified memory controller** with GPU priority for ML workloads
- **M1-inspired memory hierarchy** with 512-bit cache lines and 16 banks
- **Complete verification environment** with C++ and Python testbenches
- **Comprehensive benchmarking suite** comparing to M1 Neural Engine performance

## 📊 Performance Targets

| Configuration | Base (8 units @ 100MHz) | Target (M1 equivalent) |
|---------------|-------------------------|------------------------|
| **Performance** | 0.128 TOPS | 11.5+ TOPS |
| **Scaling Path** | 3x frequency + 30x units | 300MHz + 240 units |
| **Alternative** | Mixed precision + 60 units | FP16/INT4 + 200MHz |

## 🏗️ Architecture

### System Components

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   RISC-V CPU    │    │   GPU Compute    │    │     Unified     │
│     Core        │◄──►│     Array        │◄──►│     Memory      │
│  (RV32I + GPU)  │    │   (8 x 4x4 MAC)  │    │   Controller    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                        │
         └────────────────────────┼────────────────────────┘
                                  │
                      ┌─────────────────┐
                      │  Cache Hierarchy │
                      │ L1: 32KB 4-way   │
                      │ L2: 256KB 8-way  │
                      │ L3: 2MB 16-way   │
                      └─────────────────┘
```

### GPU Compute Units

Each GPU unit features:
- 4x4 matrix multiply-accumulate operations
- INT8 precision with INT16 accumulation
- 20-cycle operation latency
- Systolic array computation pattern

## 🛠️ Getting Started

### Prerequisites (M1/M2 Mac)

The system is optimized for Apple Silicon development:

```bash
# Run the automated setup script
./scripts/setup/setup_m1_dev.sh
```

This installs:
- Verilator (HDL simulator)
- RISC-V toolchain
- Python environment with M1-optimized ML libraries
- GTKWave (waveform viewer)
- Development tools

### Manual Setup

```bash
# Install Homebrew dependencies
brew install verilator gtkwave

# Install RISC-V toolchain
brew tap riscv-software-src/riscv
brew install riscv-tools

# Setup Python environment
python3 -m venv venv
source venv/bin/activate
pip install -r verification/requirements.txt
```

### Building and Simulation

```bash
# Build the system
make setup
make verilate

# Run simulation with waveforms
make sim

# View waveforms
make waves

# Run Python tests
make test-python

# Run benchmarks
make benchmark
```

## 📁 Project Structure

```
UnifiedRISCV/
├── rtl/                          # SystemVerilog RTL
│   ├── unified_riscv_system.sv   # Top-level integration
│   ├── cpu/                      # RISC-V CPU core
│   ├── gpu/                      # GPU compute units
│   ├── memory/                   # Memory controller & cache
│   └── interconnect/             # System interconnect
├── verification/                 # Verification environment
│   ├── testbenches/              # C++ testbenches
│   ├── tests/                    # Python/cocotb tests
│   └── requirements.txt          # Python dependencies
├── software/                     # Software components
│   ├── kernels/                  # ML kernel implementations
│   ├── benchmarks/               # Performance benchmarks
│   └── examples/                 # Example applications
├── docs/                         # Documentation
│   ├── architecture/             # Architecture specifications
│   ├── implementation/           # Implementation guides
│   └── guides/                   # User guides
├── scripts/                      # Build and utility scripts
│   ├── build/                    # Build automation
│   └── setup/                    # Environment setup
└── Makefile                      # Main build system
```

## 🧪 Verification

### C++ Testbench (Verilator)

```bash
# Compile and run basic tests
make sim

# The testbench includes:
# - Basic CPU instruction execution
# - GPU matrix multiplication
# - Memory hierarchy testing
# - Performance benchmarking
```

### Python Tests (cocotb)

```bash
# Run GPU operation tests
make test-python

# Tests include:
# - Matrix multiplication correctness
# - Parallel GPU unit operation
# - Performance measurements
```

### Example Test Output

```
=== GPU Matrix Multiply Test ===
Matrix A (4x4): Identity test
GPU operation completed in 23 cycles
Result verification: PASSED
Performance: 2.78 MAC ops/cycle
Theoretical TOPS @ 100MHz: 0.128
```

## 📈 Performance Analysis

### Benchmarking Suite

```bash
# Run comprehensive benchmarks
cd software/benchmarks
python benchmark_suite.py
```

The benchmark suite provides:
- Matrix multiplication performance comparison
- Convolution operation analysis
- Neural network layer benchmarks
- Scaling analysis to reach M1 performance
- Resource utilization estimates

### Scaling to M1 Neural Engine Performance

Current performance: **0.128 TOPS** (base configuration)
Target performance: **11.5 TOPS** (M1 Neural Engine equivalent)

**Scaling options:**

1. **Frequency scaling**: 300 MHz + 30 GPU units
2. **Balanced approach**: 200 MHz + 60 units + mixed precision
3. **Optimized design**: Custom 16-bit units + 240 units @ 200 MHz

## 🔧 FPGA Implementation

### Resource Estimates

| Component | LUTs | BRAMs | DSPs |
|-----------|------|-------|------|
| CPU Core | 2,000 | 4 | 0 |
| GPU Array (8 units) | 24,000 | 32 | 64 |
| Memory Controller | 4,000 | 8 | 0 |
| Cache Hierarchy | 8,000 | 64 | 0 |
| **Total** | **38,000** | **108** | **64** |

Fits comfortably in mid-range FPGAs (Zynq UltraScale+, Cyclone V).

### Synthesis

```bash
# Generate synthesis reports
make synth-report

# For Xilinx FPGAs
make fpga-xilinx

# For Intel FPGAs  
make fpga-intel
```

## 📚 Documentation

### Architecture Documentation

- [System Architecture Overview](docs/architecture/system_overview.md)
- [CPU Core Specification](docs/architecture/cpu_core.md)
- [GPU Compute Units](docs/architecture/gpu_units.md)
- [Memory Hierarchy](docs/architecture/memory_system.md)

### Implementation Guides

- [FPGA Implementation Guide](docs/implementation/fpga_guide.md)
- [Performance Optimization](docs/implementation/optimization.md)
- [Custom Instruction Set](docs/implementation/custom_instructions.md)

### Development Guides

- [Building and Testing](docs/guides/building.md)
- [Adding New Features](docs/guides/development.md)
- [Troubleshooting](docs/guides/troubleshooting.md)

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md).

### Development Workflow

1. Fork the repository
2. Create a feature branch
3. Run tests: `make test-python && make sim`
4. Submit a pull request

### Code Style

- SystemVerilog: Follow standard RTL coding conventions
- C/C++: Use provided `.clang-format` configuration
- Python: Use `black` formatter and `flake8` linter

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- RISC-V International for the open ISA specification
- Verilator project for the excellent open-source simulator
- Apple for the M1 Neural Engine inspiration
- The open-source HDL and verification community

## 📞 Support

- 📖 [Documentation](docs/)
- 🐛 [Issue Tracker](https://github.com/your-username/UnifiedRISCV/issues)
- 💬 [Discussions](https://github.com/your-username/UnifiedRISCV/discussions)

---

**UnifiedRISCV** - Bridging RISC-V and AI acceleration for the future of open hardware ML systems.