/*
 * Matrix Operations Header for UnifiedRISCV
 * Defines common matrix operation interfaces
 */

#ifndef MATRIX_OPS_H
#define MATRIX_OPS_H

#include <stdint.h>

// Matrix operation function prototypes
void gpu_matrix_multiply_4x4(int8_t *a, int8_t *b, int16_t *c, int gpu_unit);
void cpu_matrix_multiply_4x4(int8_t *a, int8_t *b, int16_t *c);
void gpu_matrix_multiply_tiled(int8_t *a, int8_t *b, int16_t *c, 
                               int rows, int cols, int inner_dim);

// Convolution operations
void conv2d_direct(int8_t *input, int8_t *kernel, int16_t *output,
                   int input_h, int input_w, int kernel_h, int kernel_w,
                   int stride_h, int stride_w, int pad_h, int pad_w);

void conv2d_gpu_gemm(int8_t *input, int8_t *kernel, int16_t *output,
                     int input_h, int input_w, int channels,
                     int num_filters, int kernel_h, int kernel_w,
                     int stride_h, int stride_w, int pad_h, int pad_w);

void conv2d_3x3_optimized(int8_t *input, int8_t *kernel, int16_t *output,
                          int input_h, int input_w, int channels, int num_filters);

void depthwise_conv2d(int8_t *input, int8_t *depthwise_kernel, int16_t *output,
                     int input_h, int input_w, int channels,
                     int kernel_h, int kernel_w,
                     int stride_h, int stride_w, int pad_h, int pad_w);

// Vector operations
void vector_add_int8(int8_t *a, int8_t *b, int8_t *c, int length);
void vector_add_int16(int16_t *a, int16_t *b, int16_t *c, int length);
void vector_scale_int8(int8_t *input, int8_t scale, int8_t *output, int length);
void vector_relu_int8(int8_t *input, int8_t *output, int length);

// Utility functions
void im2col(int8_t *input, int8_t *output,
           int input_h, int input_w, int channels,
           int kernel_h, int kernel_w,
           int stride_h, int stride_w, int pad_h, int pad_w);

// Benchmarking functions
void benchmark_matrix_multiply(void);
void benchmark_conv2d(void);
void performance_test_large_matrix(void);

#endif // MATRIX_OPS_H