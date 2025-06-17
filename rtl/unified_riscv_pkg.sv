// UnifiedRISCV Package - Common definitions and types

package unified_riscv_pkg;

    // System parameters
    parameter int XLEN = 32;
    parameter int NUM_GPU_UNITS = 8;
    parameter int CACHE_LINE_WIDTH = 512;
    parameter int NUM_MEMORY_BANKS = 16;
    parameter int ADDR_WIDTH = 32;
    parameter int DATA_WIDTH = 32;
    parameter int ID_WIDTH = 4;

    // Derived parameters
    parameter int NUM_MASTERS = NUM_GPU_UNITS + 1;  // CPU + GPU units
    parameter int NUM_SLAVES = 4;                   // Memory, GPU ctrl, sys ctrl, debug

    // Address map constants
    parameter logic [31:0] MAIN_MEMORY_BASE = 32'h00000000;
    parameter logic [31:0] MAIN_MEMORY_SIZE = 32'h10000000; // 256MB
    parameter logic [31:0] GPU_CTRL_BASE    = 32'h10000000;
    parameter logic [31:0] GPU_CTRL_SIZE    = 32'h00010000; // 64KB
    parameter logic [31:0] SYS_CTRL_BASE    = 32'h20000000;
    parameter logic [31:0] SYS_CTRL_SIZE    = 32'h00010000; // 64KB
    parameter logic [31:0] DEBUG_BASE       = 32'h30000000;
    parameter logic [31:0] DEBUG_SIZE       = 32'h00010000; // 64KB

endpackage