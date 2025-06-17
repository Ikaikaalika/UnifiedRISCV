# UnifiedRISCV System Architecture Overview

## Introduction

UnifiedRISCV is a complete RISC-V CPU/GPU system designed for deep learning acceleration. It combines a custom RISC-V processor with GPU compute units in a unified memory architecture optimized for machine learning workloads.

## Design Philosophy

The system is built around three core principles:

1. **Unified Memory Architecture**: CPU and GPU share the same memory space with intelligent prioritization for ML workloads
2. **Scalable Performance**: Modular design allows scaling from 0.128 TOPS to 20+ TOPS through frequency and unit scaling
3. **Open Source Accessibility**: Complete RTL implementation with comprehensive verification and development tools

## System Components

### RISC-V CPU Core (RV32I + Custom Extensions)

The CPU core implements the RV32I base instruction set with custom GPU control extensions:

- **Base ISA**: RV32I (32-bit integer instructions)
- **Pipeline**: 5-stage in-order pipeline
- **Custom Instructions**: GPU matrix multiply, GPU status, GPU control
- **Cache**: Integrated L1 instruction and data caches
- **Performance**: ~1 IPC at target frequency

**Custom Instruction Format:**
```
GPU_MATMUL:  .insn r 0x0b, 0x0, 0x0, rd, rs1, rs2
GPU_STATUS:  .insn r 0x2b, 0x1, 0x0, rd, rs1, x0
```

### GPU Compute Array

The GPU consists of 8 independent compute units, each capable of 4x4 matrix operations:

- **Compute Units**: 8 parallel units
- **Matrix Size**: 4x4 INT8 with INT16 accumulation
- **Operations**: Matrix multiply-accumulate (MAC)
- **Latency**: 20 cycles per operation (including memory access)
- **Throughput**: 64 MAC operations per unit per operation

**Compute Unit Architecture:**
```
Input Matrices (4x4 INT8) → Systolic Array → Output Matrix (4x4 INT16)
                ↓
        Memory Interface ← Round-Robin Arbiter
```

### Unified Memory Controller

The memory controller provides intelligent arbitration between CPU and GPU with ML workload optimization:

- **Priority**: GPU requests prioritized over CPU
- **Cache Line**: 512-bit wide for efficient burst transfers
- **Banking**: 16 memory banks for parallel access
- **Cache Coherency**: Write-through with invalidation
- **Bandwidth**: Up to 6.4 GB/s @ 100 MHz base frequency

**Memory Hierarchy:**
- **L1 Cache**: 32KB, 4-way associative, 32-byte lines
- **L2 Cache**: 256KB, 8-way associative, 64-byte lines  
- **L3 Cache**: 2MB, 16-way associative, 64-byte lines
- **Main Memory**: External DDR interface

## System Integration

### Address Space Layout

```
0x00000000 - 0x0FFFFFFF : Main Memory (256 MB)
0x10000000 - 0x1000FFFF : GPU Control Registers (64 KB)
0x20000000 - 0x2000FFFF : System Control Registers (64 KB)
0x80000000 - 0x8FFFFFFF : Boot ROM (256 MB)
```

### Interconnect Architecture

The system uses a hierarchical interconnect:

1. **CPU-Memory Interface**: Direct connection to unified memory controller
2. **GPU-Memory Interface**: Round-robin arbitrated access through memory controller
3. **Control Interface**: Memory-mapped GPU control registers
4. **Debug Interface**: JTAG-compatible debug access

## Performance Characteristics

### Base Configuration (8 units @ 100 MHz)

- **Peak Performance**: 0.128 TOPS (INT8)
- **Memory Bandwidth**: 6.4 GB/s
- **Power Efficiency**: ~0.064 TOPS/W (estimated)
- **Latency**: 20 cycles per 4x4 matrix operation

### Scaling Analysis

The system can scale to M1 Neural Engine performance levels through:

**Option 1: Frequency Scaling (90x improvement needed)**
- Target: 300 MHz operation frequency
- Additional: 30x more GPU units (240 total)
- Challenge: Power and thermal management

**Option 2: Balanced Scaling**
- Frequency: 200 MHz (2x improvement)
- Units: 60 GPU units (7.5x improvement)  
- Precision: Mixed INT8/INT4 (2x improvement)
- Total: 30x improvement toward 11.5 TOPS target

**Option 3: Architectural Optimization**
- Custom 16-bit units for higher precision
- Improved memory hierarchy
- Advanced prefetching and caching
- Specialized matrix instruction formats

## Design Trade-offs

### Advantages

1. **Modularity**: Easy to scale GPU units and frequency
2. **Flexibility**: Programmable via standard RISC-V tools
3. **Efficiency**: Unified memory reduces data movement
4. **Verification**: Complete test infrastructure included

### Limitations

1. **Memory Bandwidth**: Single memory controller may become bottleneck
2. **Precision**: INT8 limits some ML applications requiring FP16/FP32
3. **Complexity**: Custom instructions require modified toolchain
4. **Area**: 38K LUTs may limit FPGA implementation options

## Target Applications

### Primary Use Cases

1. **Edge AI Inference**: Real-time inference for computer vision, NLP
2. **IoT Processing**: Low-power ML at the edge
3. **Research Platform**: Academic research in ML acceleration
4. **Prototyping**: FPGA-based prototyping of larger systems

### Example Workloads

- **Computer Vision**: CNN inference (ResNet, MobileNet, EfficientNet)
- **Natural Language**: Transformer attention mechanisms
- **Signal Processing**: Real-time filtering and analysis
- **Control Systems**: Model predictive control with ML

## Future Enhancements

### Short-term Improvements

1. **Mixed Precision**: Add FP16 and INT4 support
2. **Advanced Caching**: Implement prediction and prefetching
3. **Compression**: Add sparse matrix and quantization support
4. **Power Management**: Dynamic frequency and voltage scaling

### Long-term Roadmap

1. **Multi-chip Scaling**: Scale beyond single FPGA limitations
2. **Advanced Memory**: HBM integration for bandwidth scaling
3. **Specialized Units**: Custom units for specific ML operations
4. **Software Stack**: Complete ML framework integration

## FPGA Implementation

### Resource Requirements

| Component | LUTs | BRAMs | DSPs | Power (est.) |
|-----------|------|-------|------|-------------|
| CPU Core | 2,000 | 4 | 0 | 0.5W |
| GPU Array | 24,000 | 32 | 64 | 3.0W |
| Memory Ctrl | 4,000 | 8 | 0 | 0.5W |
| Cache Hier. | 8,000 | 64 | 0 | 1.0W |
| **Total** | **38,000** | **108** | **64** | **5.0W** |

### Target FPGAs

- **Xilinx**: Zynq UltraScale+ (ZU9EG, ZU15EG)
- **Intel**: Cyclone V (5CEBA9, 5CGXFC9)
- **Microsemi**: PolarFire (MPF300T)
- **Lattice**: FPGAs with sufficient resources

## Verification Strategy

### Multi-level Verification

1. **Unit Testing**: Individual component verification
2. **Integration Testing**: System-level functionality
3. **Performance Testing**: Benchmark against targets
4. **Compliance Testing**: RISC-V ISA compliance

### Test Environments

1. **Verilator**: Cycle-accurate C++ simulation
2. **Cocotb**: Python-based verification framework
3. **Formal**: Formal verification of critical components
4. **FPGA**: Hardware-in-the-loop testing

This architecture provides a solid foundation for ML acceleration while maintaining the flexibility and openness that makes RISC-V an attractive platform for research and development.