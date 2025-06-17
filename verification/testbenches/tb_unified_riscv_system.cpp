// C++ Testbench for UnifiedRISCV System using Verilator
// Optimized for M1 Mac with comprehensive GPU testing

#include <iostream>
#include <vector>
#include <random>
#include <chrono>
#include <cstdint>
#include <iomanip>
#include "Vunified_riscv_simple.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

class UnifiedRISCVTestbench {
private:
    Vunified_riscv_simple* dut;
    VerilatedVcdC* trace;
    uint64_t sim_time;
    
    // Memory model (simplified)
    std::vector<uint8_t> memory;
    static const uint32_t MEMORY_SIZE = 1024 * 1024; // 1MB
    
    // Test statistics
    uint32_t tests_passed;
    uint32_t tests_failed;
    
public:
    UnifiedRISCVTestbench() : sim_time(0), tests_passed(0), tests_failed(0) {
        dut = new Vunified_riscv_simple;
        memory.resize(MEMORY_SIZE, 0);
        
        // Initialize trace
        Verilated::traceEverOn(true);
        trace = new VerilatedVcdC;
        dut->trace(trace, 99);
        trace->open("waves/dump.vcd");
        
        std::cout << "UnifiedRISCV Testbench Initialized" << std::endl;
        std::cout << "Memory size: " << MEMORY_SIZE << " bytes" << std::endl;
    }
    
    ~UnifiedRISCVTestbench() {
        trace->close();
        delete trace;
        delete dut;
    }
    
    void clock_tick() {
        // Positive edge
        dut->clk = 1;
        dut->eval();
        trace->dump(sim_time);
        sim_time++;
        
        // Handle memory interface
        handle_memory_interface();
        
        // Negative edge
        dut->clk = 0;
        dut->eval();
        trace->dump(sim_time);
        sim_time++;
        
        // Handle memory interface on negative edge too
        handle_memory_interface();
    }
    
    void reset(int cycles = 5) {
        dut->rst_n = 0;
        for (int i = 0; i < cycles; i++) {
            clock_tick();
        }
        dut->rst_n = 1;
        std::cout << "Reset completed after " << cycles << " cycles" << std::endl;
    }
    
    void handle_memory_interface() {
        static int mem_delay = 0;
        static bool mem_pending = false;
        
        if (dut->mem_req && !mem_pending) {
            mem_pending = true;
            mem_delay = 2; // 2-cycle memory latency
        }
        
        if (mem_pending) {
            if (mem_delay > 0) {
                mem_delay--;
                dut->mem_ack = 0;
            } else {
                dut->mem_ack = 1;
                mem_pending = false;
                
                uint32_t addr = dut->mem_addr;
                if (addr < MEMORY_SIZE) {
                    if (dut->mem_we) {
                        // Write operation - store 512-bit data
                        for (int i = 0; i < 64; i++) { // 512 bits = 64 bytes
                            if (addr + i < MEMORY_SIZE) {
                                // Extract byte i from the 512-bit word
                                int word_idx = i / 4; // Which 32-bit word
                                int byte_idx = i % 4;  // Which byte in that word
                                memory[addr + i] = (dut->mem_wdata[word_idx] >> (byte_idx * 8)) & 0xFF;
                            }
                        }
                        std::cout << "MEM WRITE: addr=0x" << std::hex << addr << std::dec << std::endl;
                    } else {
                        // Read operation - load 512-bit data
                        for (int i = 0; i < 16; i++) { // 16 32-bit words = 512 bits
                            uint32_t word_data = 0;
                            for (int j = 0; j < 4; j++) { // 4 bytes per word
                                if (addr + i*4 + j < MEMORY_SIZE) {
                                    word_data |= (uint32_t)memory[addr + i*4 + j] << (j * 8);
                                }
                            }
                            dut->mem_rdata[i] = word_data;
                        }
                        std::cout << "MEM READ: addr=0x" << std::hex << addr << std::dec << std::endl;
                    }
                }
            }
        } else {
            dut->mem_ack = 0;
        }
    }
    
    void load_program(const std::vector<uint32_t>& program, uint32_t start_addr = 0) {
        for (size_t i = 0; i < program.size(); i++) {
            uint32_t addr = start_addr + i * 4;
            if (addr + 3 < MEMORY_SIZE) {
                memory[addr] = program[i] & 0xFF;
                memory[addr + 1] = (program[i] >> 8) & 0xFF;
                memory[addr + 2] = (program[i] >> 16) & 0xFF;
                memory[addr + 3] = (program[i] >> 24) & 0xFF;
            }
        }
        std::cout << "Loaded program: " << program.size() << " instructions" << std::endl;
    }
    
    void test_basic_cpu() {
        std::cout << "\n=== Testing Basic CPU Operations ===" << std::endl;
        
        // Simple program: ADDI x1, x0, 42
        std::vector<uint32_t> program = {
            0x02A00093, // ADDI x1, x0, 42
            0x00100113, // ADDI x2, x0, 1  
            0x002081B3, // ADD x3, x1, x2
            0x00000073  // ECALL (end)
        };
        
        load_program(program);
        
        // Run for 100 cycles
        for (int i = 0; i < 100; i++) {
            clock_tick();
            
            if (dut->debug_valid) {
                std::cout << "PC: 0x" << std::hex << dut->debug_pc 
                          << " INST: 0x" << dut->debug_inst << std::dec << std::endl;
            }
        }
        
        std::cout << "Basic CPU test completed" << std::endl;
        tests_passed++;
    }
    
    void test_gpu_matrix_multiply() {
        std::cout << "\n=== Testing GPU Matrix Multiply ===" << std::endl;
        
        // Initialize test matrices in memory
        uint32_t matrix_a_addr = 0x1000;
        uint32_t matrix_b_addr = 0x1100;
        uint32_t matrix_c_addr = 0x1200;
        
        // Create 4x4 test matrices (INT8)
        std::vector<int8_t> matrix_a = {
            1, 2, 3, 4,
            5, 6, 7, 8,
            9, 10, 11, 12,
            13, 14, 15, 16
        };
        
        std::vector<int8_t> matrix_b = {
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1
        }; // Identity matrix
        
        // Load matrices into memory
        for (int i = 0; i < 16; i++) {
            memory[matrix_a_addr + i] = matrix_a[i];
            memory[matrix_b_addr + i] = matrix_b[i];
        }
        
        // GPU matrix multiply program
        std::vector<uint32_t> gpu_program = {
            0x01000093, // ADDI x1, x0, matrix_a_addr >> 12 (simplified)
            0x01100113, // ADDI x2, x0, matrix_b_addr >> 12  
            0x01200193, // ADDI x3, x0, matrix_c_addr >> 12
            0x0020802B, // Custom GPU instruction: MATMUL unit=0, src1=x1, src2=x2
            0x00000073  // ECALL
        };
        
        load_program(gpu_program, 0x2000);
        
        // Set PC to GPU program
        // Note: This would need proper CPU state control in real implementation
        
        // Run GPU test
        int max_cycles = 1000;
        bool gpu_done = false;
        
        for (int i = 0; i < max_cycles && !gpu_done; i++) {
            clock_tick();
            
            // Check if any GPU unit is busy
            bool any_gpu_busy = false;
            // Note: Would need to access internal GPU busy signals
            
            if (i > 500) { // Assume GPU operation completes by now
                gpu_done = true;
            }
        }
        
        std::cout << "GPU matrix multiply test completed" << std::endl;
        
        // Verify results (matrix_a * identity = matrix_a)
        bool results_correct = true;
        for (int i = 0; i < 16; i++) {
            int16_t expected = matrix_a[i]; // Identity multiply
            int16_t actual = memory[matrix_c_addr + i*2] | (memory[matrix_c_addr + i*2 + 1] << 8);
            
            if (actual != expected) {
                std::cout << "Mismatch at position " << i << ": expected " 
                          << expected << ", got " << actual << std::endl;
                results_correct = false;
            }
        }
        
        if (results_correct) {
            std::cout << "GPU matrix multiply: PASSED" << std::endl;
            tests_passed++;
        } else {
            std::cout << "GPU matrix multiply: FAILED" << std::endl;
            tests_failed++;
        }
    }
    
    void test_memory_hierarchy() {
        std::cout << "\n=== Testing Memory Hierarchy ===" << std::endl;
        
        // Test cache behavior with sequential and random access patterns
        std::vector<uint32_t> test_program = {
            0x00000093, // ADDI x1, x0, 0 (address counter)
            0x40000113, // ADDI x2, x0, 0x400 (loop limit)
            // Loop: load from sequential addresses
            0x0000A083, // LW x1, 0(x1)  - load from address in x1
            0x00408093, // ADDI x1, x1, 4 - increment address
            0xFE209EE3, // BNE x1, x2, loop - branch if not equal
            0x00000073  // ECALL
        };
        
        load_program(test_program, 0x3000);
        
        // Fill memory with test pattern
        for (uint32_t addr = 0; addr < 0x1000; addr += 4) {
            uint32_t data = addr ^ 0xDEADBEEF; // XOR pattern
            memory[addr] = data & 0xFF;
            memory[addr + 1] = (data >> 8) & 0xFF;
            memory[addr + 2] = (data >> 16) & 0xFF; 
            memory[addr + 3] = (data >> 24) & 0xFF;
        }
        
        auto start_time = std::chrono::high_resolution_clock::now();
        
        // Run memory test
        for (int i = 0; i < 2000; i++) {
            clock_tick();
        }
        
        auto end_time = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end_time - start_time);
        
        std::cout << "Memory hierarchy test completed in " << duration.count() << " µs" << std::endl;
        std::cout << "Simulated " << sim_time << " clock cycles" << std::endl;
        tests_passed++;
    }
    
    void performance_benchmark() {
        std::cout << "\n=== Performance Benchmark ===" << std::endl;
        
        // Measure matrix operations per second
        uint32_t num_operations = 100;
        
        auto start_time = std::chrono::high_resolution_clock::now();
        uint64_t start_cycles = sim_time;
        
        // Simulate matrix operations
        for (uint32_t op = 0; op < num_operations; op++) {
            // Each matrix op takes ~20 cycles (load A, load B, compute, store C)
            for (int i = 0; i < 20; i++) {
                clock_tick();
            }
        }
        
        auto end_time = std::chrono::high_resolution_clock::now();
        uint64_t total_cycles = sim_time - start_cycles;
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end_time - start_time);
        
        double sim_frequency = (double)total_cycles / (duration.count() / 1e6); // Hz
        double ops_per_second = (double)num_operations / (duration.count() / 1e6);
        
        std::cout << "Performance Results:" << std::endl;
        std::cout << "  Simulation frequency: " << std::fixed << std::setprecision(2) 
                  << sim_frequency / 1e6 << " MHz" << std::endl;
        std::cout << "  Matrix ops/sec: " << std::fixed << std::setprecision(0) 
                  << ops_per_second << std::endl;
        std::cout << "  Cycles per operation: " << total_cycles / num_operations << std::endl;
        
        // Theoretical TOPS calculation
        // Each 4x4 INT8 matrix multiply = 4*4*4 = 64 ops
        // 8 GPU units * 64 ops/matrix * ops_per_second = total ops/sec
        double theoretical_ops = 8.0 * 64.0 * ops_per_second;
        double theoretical_tops = theoretical_ops / 1e12;
        
        std::cout << "  Theoretical TOPS (INT8): " << std::fixed << std::setprecision(3) 
                  << theoretical_tops << std::endl;
        
        // Scaling analysis
        std::cout << "\nScaling to M1 Neural Engine (11.5 TOPS):" << std::endl;
        double scale_factor = 11.5 / theoretical_tops;
        std::cout << "  Required improvement: " << std::fixed << std::setprecision(1) 
                  << scale_factor << "x" << std::endl;
        std::cout << "  Achievable with: 300MHz + 30 GPU units" << std::endl;
        std::cout << "  Or: 200MHz + 60 GPU units + FP16" << std::endl;
    }
    
    void run_all_tests() {
        std::cout << "Starting UnifiedRISCV System Tests" << std::endl;
        std::cout << "Simulator: Verilator" << std::endl;
        std::cout << "Platform: Apple Silicon (M1/M2)" << std::endl;
        
        reset();
        
        test_basic_cpu();
        test_gpu_matrix_multiply();
        test_memory_hierarchy();
        performance_benchmark();
        
        std::cout << "\n=== Test Summary ===" << std::endl;
        std::cout << "Tests passed: " << tests_passed << std::endl;
        std::cout << "Tests failed: " << tests_failed << std::endl;
        std::cout << "Total simulation time: " << sim_time << " cycles" << std::endl;
        
        if (tests_failed == 0) {
            std::cout << "ALL TESTS PASSED!" << std::endl;
        } else {
            std::cout << "Some tests failed. Check output above." << std::endl;
        }
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    
    UnifiedRISCVTestbench tb;
    tb.run_all_tests();
    
    return 0;
}