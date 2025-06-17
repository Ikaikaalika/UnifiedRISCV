/*
 * Matrix Multiplication Kernel for UnifiedRISCV
 * Optimized for GPU compute units with custom instructions
 */

#include "gpu_interface.h"
#include "matrix_ops.h"

// GPU matrix multiply using custom instructions
void gpu_matrix_multiply_4x4(int8_t *a, int8_t *b, int16_t *c, int gpu_unit) {
    // Use custom GPU instruction to perform 4x4 matrix multiply
    // This maps to the GPU_MATMUL custom instruction in the CPU
    
    asm volatile (
        "mv t0, %0\n"          // Load matrix A address
        "mv t1, %1\n"          // Load matrix B address  
        "mv t2, %2\n"          // Load matrix C address
        "mv t3, %3\n"          // GPU unit number
        
        // Custom instruction: GPU matrix multiply setup
        // Format: .insn r 0x0b, 0x0, 0x0, rd, rs1, rs2
        ".insn r 0x0b, 0x0, 0x0, t2, t0, t1\n"
        
        // Wait for GPU unit to complete
        "1:\n"
        ".insn r 0x2b, 0x1, 0x0, t4, t3, x0\n"  // Check GPU status
        "bnez t4, 1b\n"        // Loop while busy
        
        : // No output operands
        : "r"(a), "r"(b), "r"(c), "r"(gpu_unit)
        : "t0", "t1", "t2", "t3", "t4", "memory"
    );
}

// CPU-based matrix multiply for comparison
void cpu_matrix_multiply_4x4(int8_t *a, int8_t *b, int16_t *c) {
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            int16_t sum = 0;
            for (int k = 0; k < 4; k++) {
                sum += a[i*4 + k] * b[k*4 + j];
            }
            c[i*4 + j] = sum;
        }
    }
}

// Large matrix multiply using tiled approach with GPU units
void gpu_matrix_multiply_tiled(int8_t *a, int8_t *b, int16_t *c, 
                               int rows, int cols, int inner_dim) {
    // Tile size is 4x4 to match GPU compute unit capability
    const int TILE_SIZE = 4;
    int num_gpu_units = 8;
    int current_unit = 0;
    
    for (int i = 0; i < rows; i += TILE_SIZE) {
        for (int j = 0; j < cols; j += TILE_SIZE) {
            // Zero the output tile
            for (int ii = 0; ii < TILE_SIZE && (i + ii) < rows; ii++) {
                for (int jj = 0; jj < TILE_SIZE && (j + jj) < cols; jj++) {
                    c[(i + ii) * cols + (j + jj)] = 0;
                }
            }
            
            // Accumulate partial products
            for (int k = 0; k < inner_dim; k += TILE_SIZE) {
                // Extract 4x4 tiles
                int8_t tile_a[16], tile_b[16];
                int16_t tile_c[16] = {0};
                
                // Copy A tile
                for (int ii = 0; ii < TILE_SIZE; ii++) {
                    for (int kk = 0; kk < TILE_SIZE; kk++) {
                        int row = i + ii;
                        int col = k + kk;
                        if (row < rows && col < inner_dim) {
                            tile_a[ii * TILE_SIZE + kk] = a[row * inner_dim + col];
                        } else {
                            tile_a[ii * TILE_SIZE + kk] = 0;
                        }
                    }
                }
                
                // Copy B tile
                for (int kk = 0; kk < TILE_SIZE; kk++) {
                    for (int jj = 0; jj < TILE_SIZE; jj++) {
                        int row = k + kk;
                        int col = j + jj;
                        if (row < inner_dim && col < cols) {
                            tile_b[kk * TILE_SIZE + jj] = b[row * cols + col];
                        } else {
                            tile_b[kk * TILE_SIZE + jj] = 0;
                        }
                    }
                }
                
                // Perform tile multiplication using GPU
                gpu_matrix_multiply_4x4(tile_a, tile_b, tile_c, current_unit);
                
                // Accumulate results back to main matrix
                for (int ii = 0; ii < TILE_SIZE; ii++) {
                    for (int jj = 0; jj < TILE_SIZE; jj++) {
                        int row = i + ii;
                        int col = j + jj;
                        if (row < rows && col < cols) {
                            c[row * cols + col] += tile_c[ii * TILE_SIZE + jj];
                        }
                    }
                }
                
                // Round-robin GPU unit assignment
                current_unit = (current_unit + 1) % num_gpu_units;
            }
        }
    }
}

// Benchmark function
void benchmark_matrix_multiply() {
    // Test data
    static int8_t test_a[16] = {
        1, 2, 3, 4,
        5, 6, 7, 8,
        9, 10, 11, 12,
        13, 14, 15, 16
    };
    
    static int8_t test_b[16] = {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    }; // Identity matrix
    
    static int16_t result_gpu[16];
    static int16_t result_cpu[16];
    
    // Get cycle counter (custom instruction)
    uint32_t start_cycles, end_cycles;
    
    // GPU version
    asm volatile ("rdcycle %0" : "=r"(start_cycles));
    gpu_matrix_multiply_4x4(test_a, test_b, result_gpu, 0);
    asm volatile ("rdcycle %0" : "=r"(end_cycles));
    uint32_t gpu_cycles = end_cycles - start_cycles;
    
    // CPU version
    asm volatile ("rdcycle %0" : "=r"(start_cycles));
    cpu_matrix_multiply_4x4(test_a, test_b, result_cpu);
    asm volatile ("rdcycle %0" : "=r"(end_cycles));
    uint32_t cpu_cycles = end_cycles - start_cycles;
    
    // Verify results match
    int correct = 1;
    for (int i = 0; i < 16; i++) {
        if (result_gpu[i] != result_cpu[i]) {
            correct = 0;
            break;
        }
    }
    
    // Output results (would need UART or similar for real hardware)
    if (correct) {
        // Results match
        debug_print("Matrix multiply test: PASSED\n");
    } else {
        debug_print("Matrix multiply test: FAILED\n");
    }
    
    debug_printf("GPU cycles: %d\n", gpu_cycles);
    debug_printf("CPU cycles: %d\n", cpu_cycles);
    debug_printf("Speedup: %dx\n", cpu_cycles / gpu_cycles);
}

// Performance test with larger matrices
void performance_test_large_matrix() {
    const int SIZE = 32; // 32x32 matrix
    static int8_t large_a[SIZE * SIZE];
    static int8_t large_b[SIZE * SIZE];
    static int16_t large_c[SIZE * SIZE];
    
    // Initialize with test pattern
    for (int i = 0; i < SIZE * SIZE; i++) {
        large_a[i] = (i % 256) - 128; // -128 to 127 range
        large_b[i] = ((i * 7) % 256) - 128;
    }
    
    uint32_t start_cycles, end_cycles;
    
    asm volatile ("rdcycle %0" : "=r"(start_cycles));
    gpu_matrix_multiply_tiled(large_a, large_b, large_c, SIZE, SIZE, SIZE);
    asm volatile ("rdcycle %0" : "=r"(end_cycles));
    
    uint32_t total_cycles = end_cycles - start_cycles;
    
    // Calculate performance metrics
    uint32_t total_ops = (uint32_t)SIZE * SIZE * SIZE; // MAC operations
    uint32_t ops_per_cycle = total_ops / total_cycles;
    
    debug_printf("Large matrix (%dx%d) performance:\n", SIZE, SIZE);
    debug_printf("Total cycles: %d\n", total_cycles);
    debug_printf("Total MAC ops: %d\n", total_ops);
    debug_printf("MAC ops/cycle: %d\n", ops_per_cycle);
    
    // Theoretical TOPS calculation at 100MHz
    // ops_per_cycle * 100M cycles/sec / 1e12 = TOPS
    debug_printf("Theoretical TOPS @ 100MHz: %d.%03d\n", 
                 (ops_per_cycle * 100) / 1000, 
                 (ops_per_cycle * 100) % 1000);
}