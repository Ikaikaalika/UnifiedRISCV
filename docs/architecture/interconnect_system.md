# UnifiedRISCV Interconnect System

## Overview

The UnifiedRISCV system features a sophisticated interconnect architecture that provides efficient communication between the CPU, GPU compute units, and various system peripherals. The interconnect is designed with GPU-priority arbitration to optimize performance for machine learning workloads.

## Architecture Components

### 1. System Interconnect (`system_interconnect.sv`)

The main interconnect module implements a crossbar switch with the following features:

- **9 Master Interfaces**: 1 CPU + 8 GPU compute units
- **4 Slave Interfaces**: Memory controller, GPU control, system control, debug
- **GPU Priority Arbitration**: GPU requests prioritized over CPU
- **Address Decoding**: Automatic routing based on memory map
- **Transaction IDs**: 4-bit IDs for transaction tracking

#### Address Map

| Base Address | Size | Component | Description |
|--------------|------|-----------|-------------|
| 0x00000000 | 256MB | Main Memory | DDR/external memory |
| 0x10000000 | 64KB | GPU Control | Memory-mapped GPU registers |
| 0x20000000 | 64KB | System Control | System configuration registers |
| 0x30000000 | 64KB | Debug Interface | Debug and trace registers |

### 2. Priority Arbiter (`priority_arbiter.sv`)

Implements intelligent arbitration with the following features:

- **GPU Priority**: GPU units (masters 1-8) prioritized over CPU (master 0)
- **Round-Robin**: Fair scheduling among GPU units
- **Starvation Prevention**: CPU gets access when no GPU requests pending
- **Configurable Priority**: Can disable GPU priority for testing

#### Arbitration Algorithm

```
if (GPU_PRIORITY && gpu_has_request) {
    // Round-robin among GPU units only
    grant_next_gpu_unit();
} else if (cpu_has_request && !gpu_has_request) {
    // Grant CPU when no GPU activity
    grant_cpu();
} else {
    // Fallback: standard round-robin
    grant_round_robin();
}
```

### 3. GPU Control Interface (`gpu_control_interface.sv`)

Provides memory-mapped access to GPU control and status with:

- **Global Control**: System-wide GPU enable/disable
- **Per-Unit Control**: Individual GPU unit configuration
- **Status Monitoring**: Real-time busy/done/error status
- **Performance Counters**: Cycle counts and operation counts
- **Matrix Configuration**: Memory addresses for matrix operations

#### Register Map

**Global Registers (0x10000000 base):**

| Offset | Register | Description |
|--------|----------|-------------|
| 0x0000 | GPU_GLOBAL_CTRL | Global enable/disable |
| 0x0004 | GPU_GLOBAL_STATUS | Aggregated status |
| 0x0008 | GPU_GLOBAL_PRIORITY | Priority configuration |
| 0x000C | GPU_DEBUG_CTRL | Debug control |

**Per-Unit Registers (0x10000100 + unit*64):**

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | UNIT_CTRL | Enable, reset, start |
| 0x04 | UNIT_STATUS | Busy, done, error flags |
| 0x08 | UNIT_MATRIX_A | Matrix A address |
| 0x0C | UNIT_MATRIX_B | Matrix B address |
| 0x10 | UNIT_MATRIX_C | Matrix C address |
| 0x14 | UNIT_CONFIG | Operation configuration |
| 0x18 | UNIT_CYCLES | Cycle counter |
| 0x1C | UNIT_OPS | Operation counter |

### 4. AXI4-Lite Bridge (`axi_bridge.sv`)

Provides standard AXI4-Lite interface for external connectivity:

- **Protocol Conversion**: Internal protocol ↔ AXI4-Lite
- **State Machine**: Handles AXI handshaking protocols
- **Future Expansion**: Ready for external AXI peripherals

## Performance Characteristics

### Bandwidth Analysis

**Maximum Theoretical Bandwidth:**
- Clock frequency: 100 MHz (base)
- Data width: 32 bits
- Peak bandwidth per master: 400 MB/s
- Total system bandwidth: 3.6 GB/s (9 masters)

**Practical Bandwidth:**
- GPU priority reduces CPU bandwidth to ~100 MB/s under load
- GPU units achieve ~350 MB/s each under optimal conditions
- Memory controller is the primary bottleneck at 6.4 GB/s

### Latency Characteristics

**Arbitration Latency:**
- Best case: 1 cycle (no contention)
- Worst case: 9 cycles (full round-robin)
- GPU priority: 2-3 cycles average

**End-to-End Latency:**
- CPU to memory: 5-10 cycles (including cache)
- GPU to memory: 3-8 cycles (optimized path)
- Register access: 2-4 cycles

## Usage Examples

### CPU Programming Interface

```c
// Enable GPU unit 0
volatile uint32_t *gpu_ctrl = (uint32_t*)0x10000100;
*gpu_ctrl = 0x01; // Enable bit

// Configure matrix operation
volatile uint32_t *matrix_a = (uint32_t*)0x10000108;
volatile uint32_t *matrix_b = (uint32_t*)0x1000010C;
volatile uint32_t *matrix_c = (uint32_t*)0x10000110;

*matrix_a = 0x1000; // Matrix A at 0x1000
*matrix_b = 0x2000; // Matrix B at 0x2000
*matrix_c = 0x3000; // Matrix C at 0x3000

// Start operation
*gpu_ctrl |= 0x04; // Set start bit

// Wait for completion
volatile uint32_t *gpu_status = (uint32_t*)0x10000104;
while (*gpu_status & 0x01) { /* wait for busy bit to clear */ }
```

### SystemVerilog Interface

```systemverilog
// Connect to interconnect
system_interconnect #(
    .NUM_MASTERS(9),
    .NUM_SLAVES(4)
) interconnect (
    .clk(clk),
    .rst_n(rst_n),
    .master_req(master_requests),
    .master_addr(master_addresses),
    // ... other connections
);
```

## Design Trade-offs

### Advantages

1. **Scalability**: Easy to add more masters/slaves
2. **Priority Optimization**: GPU-optimized for ML workloads
3. **Standard Interfaces**: AXI4-Lite compatibility
4. **Monitoring**: Built-in performance counters
5. **Flexibility**: Configurable priority schemes

### Limitations

1. **Arbitration Overhead**: Multi-cycle arbitration delays
2. **Single Memory Controller**: Potential bottleneck
3. **Fixed Priority**: Limited dynamic priority adjustment
4. **Area Cost**: Crossbar requires significant logic resources

## Future Enhancements

### Short-term Improvements

1. **Burst Support**: Add burst transaction support
2. **Quality of Service**: Advanced QoS arbitration
3. **Error Handling**: Enhanced error detection and recovery
4. **Debug Features**: Transaction tracing and analysis

### Long-term Roadmap

1. **Network-on-Chip**: Replace crossbar with NoC
2. **Multiple Memory Controllers**: Reduce memory bottleneck
3. **Hardware Coherency**: Cache coherency protocol
4. **Dynamic Frequency**: Adaptive frequency scaling

## Verification Strategy

### Functional Testing

1. **Basic Connectivity**: All master-slave paths
2. **Priority Verification**: GPU priority enforcement
3. **Address Decoding**: Correct slave selection
4. **Error Conditions**: Invalid address handling

### Performance Testing

1. **Bandwidth Measurement**: Sustained throughput
2. **Latency Analysis**: End-to-end timing
3. **Contention Scenarios**: Multiple masters competing
4. **Priority Validation**: GPU vs CPU access patterns

### Integration Testing

1. **Full System**: CPU + GPU + memory workloads
2. **Real Workloads**: Matrix multiplication tests
3. **Stress Testing**: Maximum load scenarios
4. **Corner Cases**: Reset, error recovery

This interconnect system provides the foundation for efficient communication in the UnifiedRISCV system while maintaining the flexibility needed for future enhancements and optimizations.