/*
 * GPU Interface Header for UnifiedRISCV
 * Defines custom instructions and GPU control functions
 */

#ifndef GPU_INTERFACE_H
#define GPU_INTERFACE_H

#include <stdint.h>

// GPU Configuration
#define NUM_GPU_UNITS 8
#define GPU_MATRIX_SIZE 4  // 4x4 matrices

// Custom instruction opcodes
#define GPU_MATMUL_OPCODE   0x0b  // custom-0
#define GPU_STATUS_OPCODE   0x2b  // custom-1

// GPU unit status flags
#define GPU_UNIT_IDLE       0x0
#define GPU_UNIT_BUSY       0x1
#define GPU_UNIT_DONE       0x2
#define GPU_UNIT_ERROR      0x3

// Function declarations
void gpu_matrix_multiply_4x4(int8_t *a, int8_t *b, int16_t *c, int gpu_unit);
void cpu_matrix_multiply_4x4(int8_t *a, int8_t *b, int16_t *c);
void gpu_matrix_multiply_tiled(int8_t *a, int8_t *b, int16_t *c, 
                               int rows, int cols, int inner_dim);

// GPU control functions
static inline uint32_t gpu_get_status(int unit) {
    uint32_t status;
    asm volatile (
        ".insn r %1, 0x1, 0x0, %0, %2, x0"
        : "=r"(status)
        : "i"(GPU_STATUS_OPCODE), "r"(unit)
    );
    return status;
}

static inline void gpu_wait_idle(int unit) {
    while (gpu_get_status(unit) != GPU_UNIT_IDLE) {
        // Busy wait
        asm volatile ("nop");
    }
}

static inline void gpu_wait_all_idle(void) {
    for (int i = 0; i < NUM_GPU_UNITS; i++) {
        gpu_wait_idle(i);
    }
}

// Debug and utility functions
void debug_print(const char *str);
void debug_printf(const char *format, ...);
uint32_t get_cycle_count(void);
void delay_cycles(uint32_t cycles);

// Memory management helpers
void* gpu_malloc(size_t size);
void gpu_free(void* ptr);
void gpu_memcpy(void* dest, const void* src, size_t n);

// Performance monitoring
typedef struct {
    uint32_t start_cycles;
    uint32_t end_cycles;
    uint32_t gpu_operations;
    uint32_t cache_misses;
} perf_counter_t;

void perf_start(perf_counter_t* counter);
void perf_end(perf_counter_t* counter);
void perf_report(const perf_counter_t* counter, const char* test_name);

#endif // GPU_INTERFACE_H