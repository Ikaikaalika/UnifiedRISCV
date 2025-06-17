/*
 * 2D Convolution Kernel for UnifiedRISCV
 * Optimized for deep learning inference using GPU compute units
 */

#include "gpu_interface.h"
#include "matrix_ops.h"

// Direct 2D convolution implementation
void conv2d_direct(int8_t *input, int8_t *kernel, int16_t *output,
                   int input_h, int input_w, int kernel_h, int kernel_w,
                   int stride_h, int stride_w, int pad_h, int pad_w) {
    
    int output_h = (input_h + 2 * pad_h - kernel_h) / stride_h + 1;
    int output_w = (input_w + 2 * pad_w - kernel_w) / stride_w + 1;
    
    for (int oh = 0; oh < output_h; oh++) {
        for (int ow = 0; ow < output_w; ow++) {
            int16_t sum = 0;
            
            for (int kh = 0; kh < kernel_h; kh++) {
                for (int kw = 0; kw < kernel_w; kw++) {
                    int ih = oh * stride_h - pad_h + kh;
                    int iw = ow * stride_w - pad_w + kw;
                    
                    // Check bounds
                    if (ih >= 0 && ih < input_h && iw >= 0 && iw < input_w) {
                        sum += input[ih * input_w + iw] * kernel[kh * kernel_w + kw];
                    }
                }
            }
            
            output[oh * output_w + ow] = sum;
        }
    }
}

// Im2col transformation for GEMM-based convolution
void im2col(int8_t *input, int8_t *output,
           int input_h, int input_w, int channels,
           int kernel_h, int kernel_w,
           int stride_h, int stride_w, int pad_h, int pad_w) {
    
    int output_h = (input_h + 2 * pad_h - kernel_h) / stride_h + 1;
    int output_w = (input_w + 2 * pad_w - kernel_w) / stride_w + 1;
    
    int col_idx = 0;
    
    for (int c = 0; c < channels; c++) {
        for (int kh = 0; kh < kernel_h; kh++) {
            for (int kw = 0; kw < kernel_w; kw++) {
                for (int oh = 0; oh < output_h; oh++) {
                    for (int ow = 0; ow < output_w; ow++) {
                        int ih = oh * stride_h - pad_h + kh;
                        int iw = ow * stride_w - pad_w + kw;
                        
                        if (ih >= 0 && ih < input_h && iw >= 0 && iw < input_w) {
                            output[col_idx] = input[c * input_h * input_w + ih * input_w + iw];
                        } else {
                            output[col_idx] = 0; // Padding
                        }
                        col_idx++;
                    }
                }
            }
        }
    }
}

// GPU-accelerated convolution using GEMM approach
void conv2d_gpu_gemm(int8_t *input, int8_t *kernel, int16_t *output,
                     int input_h, int input_w, int channels,
                     int num_filters, int kernel_h, int kernel_w,
                     int stride_h, int stride_w, int pad_h, int pad_w) {
    
    int output_h = (input_h + 2 * pad_h - kernel_h) / stride_h + 1;
    int output_w = (input_w + 2 * pad_w - kernel_w) / stride_w + 1;
    int output_size = output_h * output_w;
    
    // Allocate im2col buffer
    int col_size = channels * kernel_h * kernel_w * output_size;
    static int8_t im2col_buffer[32768]; // Statically allocated buffer
    
    if (col_size > sizeof(im2col_buffer)) {
        debug_print("Error: im2col buffer too small\n");
        return;
    }
    
    // Transform input to column format
    im2col(input, im2col_buffer, input_h, input_w, channels,
           kernel_h, kernel_w, stride_h, stride_w, pad_h, pad_w);
    
    // Perform GEMM: kernel * im2col_buffer = output
    // kernel: [num_filters, channels * kernel_h * kernel_w]
    // im2col_buffer: [channels * kernel_h * kernel_w, output_size]
    // output: [num_filters, output_size]
    
    int kernel_size = channels * kernel_h * kernel_w;
    
    // Use tiled matrix multiplication with GPU
    gpu_matrix_multiply_tiled(kernel, im2col_buffer, output,
                             num_filters, output_size, kernel_size);
}

// Optimized 3x3 convolution with stride 1
void conv2d_3x3_optimized(int8_t *input, int8_t *kernel, int16_t *output,
                          int input_h, int input_w, int channels, int num_filters) {
    
    int output_h = input_h - 2; // No padding, 3x3 kernel
    int output_w = input_w - 2;
    
    // Process 4 output pixels at once using GPU 4x4 matrix units
    for (int f = 0; f < num_filters; f++) {
       for (int c = 0; c < channels; c++) {
           for (int oh = 0; oh < output_h; oh += 2) {
               for (int ow = 0; ow < output_w; ow += 2) {
                   
                   // Extract 4x4 input patch for 2x2 output
                   int8_t input_patch[16];
                   int16_t output_patch[4] = {0};
                   
                   // Fill input patch (4x4)
                   for (int i = 0; i < 4; i++) {
                       for (int j = 0; j < 4; j++) {
                           int ih = oh + i;
                           int iw = ow + j;
                           if (ih < input_h && iw < input_w) {
                               input_patch[i * 4 + j] = 
                                   input[c * input_h * input_w + ih * input_w + iw];
                           } else {
                               input_patch[i * 4 + j] = 0;
                           }
                       }
                   }
                   
                   // Create 4x4 kernel matrix (replicated 3x3 kernel)
                   int8_t kernel_matrix[16];
                   for (int i = 0; i < 16; i++) {
                       kernel_matrix[i] = 0;
                   }
                   
                   // Copy 3x3 kernel to top-left of 4x4 matrix
                   for (int i = 0; i < 3; i++) {
                       for (int j = 0; j < 3; j++) {  
                           kernel_matrix[i * 4 + j] = 
                               kernel[f * channels * 9 + c * 9 + i * 3 + j];
                       }
                   }
                   
                   // Use GPU for 4x4 matrix multiply
                   gpu_matrix_multiply_4x4(input_patch, kernel_matrix, output_patch, 
                                         f % 8); // Use GPU unit based on filter
                   
                   // Accumulate results to output (only use top-left 2x2)
                   for (int i = 0; i < 2 && (oh + i) < output_h; i++) {
                       for (int j = 0; j < 2 && (ow + j) < output_w; j++) {
                           int out_idx = f * output_h * output_w + 
                                       (oh + i) * output_w + (ow + j);
                           output[out_idx] += output_patch[i * 4 + j];
                       }
                   }
               }
           }
       }
    }
}

// Depthwise separable convolution (MobileNet style)
void depthwise_conv2d(int8_t *input, int8_t *depthwise_kernel, int16_t *output,
                     int input_h, int input_w, int channels,
                     int kernel_h, int kernel_w,
                     int stride_h, int stride_w, int pad_h, int pad_w) {
    
    int output_h = (input_h + 2 * pad_h - kernel_h) / stride_h + 1;
    int output_w = (input_w + 2 * pad_w - kernel_w) / stride_w + 1;
    
    // Each channel is convolved independently
    for (int c = 0; c < channels; c++) {
        for (int oh = 0; oh < output_h; oh++) {
            for (int ow = 0; ow < output_w; ow++) {
                int16_t sum = 0;
                
                for (int kh = 0; kh < kernel_h; kh++) {
                    for (int kw = 0; kw < kernel_w; kw++) {
                        int ih = oh * stride_h - pad_h + kh;
                        int iw = ow * stride_w - pad_w + kw;
                        
                        if (ih >= 0 && ih < input_h && iw >= 0 && iw < input_w) {
                            sum += input[c * input_h * input_w + ih * input_w + iw] *
                                  depthwise_kernel[c * kernel_h * kernel_w + kh * kernel_w + kw];
                        }
                    }
                }
                
                output[c * output_h * output_w + oh * output_w + ow] = sum;
            }
        }
    }
}

// Benchmark different convolution implementations
void benchmark_conv2d() {
    // Test parameters
    const int INPUT_H = 16, INPUT_W = 16, CHANNELS = 8, NUM_FILTERS = 16;
    const int KERNEL_H = 3, KERNEL_W = 3;
    
    // Allocate test data
    static int8_t input[INPUT_H * INPUT_W * CHANNELS];
    static int8_t kernel[NUM_FILTERS * CHANNELS * KERNEL_H * KERNEL_W];
    static int16_t output_direct[NUM_FILTERS * (INPUT_H-2) * (INPUT_W-2)];
    static int16_t output_gemm[NUM_FILTERS * (INPUT_H-2) * (INPUT_W-2)];
    
    // Initialize test data
    for (int i = 0; i < INPUT_H * INPUT_W * CHANNELS; i++) {
        input[i] = (i % 256) - 128;
    }
    
    for (int i = 0; i < NUM_FILTERS * CHANNELS * KERNEL_H * KERNEL_W; i++) {
        kernel[i] = ((i * 7) % 256) - 128;
    }
    
    uint32_t start_cycles, end_cycles;
    
    // Test direct convolution
    asm volatile ("rdcycle %0" : "=r"(start_cycles));
    conv2d_direct(input, kernel, output_direct,
                  INPUT_H, INPUT_W, KERNEL_H, KERNEL_W,
                  1, 1, 0, 0); // stride=1, no padding
    asm volatile ("rdcycle %0" : "=r"(end_cycles));
    uint32_t direct_cycles = end_cycles - start_cycles;
    
    // Test GPU GEMM convolution
    asm volatile ("rdcycle %0" : "=r"(start_cycles));
    conv2d_gpu_gemm(input, kernel, output_gemm,
                    INPUT_H, INPUT_W, CHANNELS, NUM_FILTERS,
                    KERNEL_H, KERNEL_W, 1, 1, 0, 0);
    asm volatile ("rdcycle %0" : "=r"(end_cycles));
    uint32_t gemm_cycles = end_cycles - start_cycles;
    
    // Verify results match (within tolerance for different algorithms)
    int correct = 1;
    int max_diff = 0;
    int output_size = NUM_FILTERS * (INPUT_H-2) * (INPUT_W-2);
    
    for (int i = 0; i < output_size; i++) {
        int diff = output_direct[i] - output_gemm[i];
        if (diff < 0) diff = -diff;
        if (diff > max_diff) max_diff = diff;
        if (diff > 10) { // Allow small differences due to algorithm variations
            correct = 0;
        }
    }
    
    debug_printf("Conv2D Benchmark Results:\n");
    debug_printf("Input size: %dx%dx%d\n", INPUT_H, INPUT_W, CHANNELS);
    debug_printf("Kernel size: %dx%d, Filters: %d\n", KERNEL_H, KERNEL_W, NUM_FILTERS);
    debug_printf("Direct cycles: %d\n", direct_cycles);
    debug_printf("GPU GEMM cycles: %d\n", gemm_cycles);
    debug_printf("Speedup: %dx\n", direct_cycles / gemm_cycles);
    debug_printf("Max difference: %d\n", max_diff);
    debug_printf("Results match: %s\n", correct ? "YES" : "NO");
    
    // Calculate throughput
    uint32_t total_ops = (uint32_t)NUM_FILTERS * (INPUT_H-2) * (INPUT_W-2) * 
                        CHANNELS * KERNEL_H * KERNEL_W;
    debug_printf("Total MAC operations: %d\n", total_ops);
    debug_printf("GPU MAC ops/cycle: %d\n", total_ops / gemm_cycles);
}