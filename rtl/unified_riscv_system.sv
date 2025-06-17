// UnifiedRISCV - Top-level system integrating RISC-V CPU with GPU compute units
// Optimized for deep learning workloads with unified memory architecture

module unified_riscv_system #(
    parameter XLEN = 32,
    parameter NUM_GPU_UNITS = 8,
    parameter CACHE_LINE_WIDTH = 512,
    parameter NUM_MEMORY_BANKS = 16,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  logic clk,
    input  logic rst_n,
    
    // External memory interface
    output logic [ADDR_WIDTH-1:0] mem_addr,
    output logic [CACHE_LINE_WIDTH-1:0] mem_wdata,
    input  logic [CACHE_LINE_WIDTH-1:0] mem_rdata,
    output logic mem_req,
    output logic mem_we,
    input  logic mem_ack,
    
    // Debug interface
    output logic [31:0] debug_pc,
    output logic [31:0] debug_inst,
    output logic debug_valid
);

    // Internal buses
    logic [ADDR_WIDTH-1:0] cpu_addr, gpu_addr;
    logic [DATA_WIDTH-1:0] cpu_wdata, gpu_wdata;
    logic [DATA_WIDTH-1:0] cpu_rdata, gpu_rdata;
    logic cpu_req, gpu_req;
    logic cpu_we, gpu_we;
    logic cpu_ack, gpu_ack;
    
    // GPU compute interface
    logic [NUM_GPU_UNITS-1:0] gpu_unit_busy;
    logic [NUM_GPU_UNITS-1:0] gpu_unit_start;
    logic [31:0] gpu_matrix_a [NUM_GPU_UNITS-1:0];
    logic [31:0] gpu_matrix_b [NUM_GPU_UNITS-1:0];
    logic [31:0] gpu_matrix_c [NUM_GPU_UNITS-1:0];
    
    // RISC-V CPU Core
    riscv_cpu #(
        .XLEN(XLEN)
    ) cpu_core (
        .clk(clk),
        .rst_n(rst_n),
        .mem_addr(cpu_addr),
        .mem_wdata(cpu_wdata),
        .mem_rdata(cpu_rdata),
        .mem_req(cpu_req),
        .mem_we(cpu_we),
        .mem_ack(cpu_ack),
        .gpu_unit_busy(gpu_unit_busy),
        .gpu_unit_start(gpu_unit_start),
        .gpu_matrix_a(gpu_matrix_a),
        .gpu_matrix_b(gpu_matrix_b),
        .gpu_matrix_c(gpu_matrix_c),
        .debug_pc(debug_pc),
        .debug_inst(debug_inst),
        .debug_valid(debug_valid)
    );
    
    // GPU Compute Array
    gpu_compute_array #(
        .NUM_UNITS(NUM_GPU_UNITS)
    ) gpu_array (
        .clk(clk),
        .rst_n(rst_n),
        .mem_addr(gpu_addr),
        .mem_wdata(gpu_wdata),
        .mem_rdata(gpu_rdata),
        .mem_req(gpu_req),
        .mem_we(gpu_we),
        .mem_ack(gpu_ack),
        .unit_busy(gpu_unit_busy),
        .unit_start(gpu_unit_start),
        .matrix_a(gpu_matrix_a),
        .matrix_b(gpu_matrix_b),
        .matrix_c(gpu_matrix_c)
    );
    
    // Unified Memory Controller with GPU Priority
    unified_memory_controller #(
        .CACHE_LINE_WIDTH(CACHE_LINE_WIDTH),
        .NUM_BANKS(NUM_MEMORY_BANKS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) memory_controller (
        .clk(clk),
        .rst_n(rst_n),
        
        // CPU interface
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),
        .cpu_req(cpu_req),
        .cpu_we(cpu_we),
        .cpu_ack(cpu_ack),
        
        // GPU interface
        .gpu_addr(gpu_addr),
        .gpu_wdata(gpu_wdata),
        .gpu_rdata(gpu_rdata),
        .gpu_req(gpu_req),
        .gpu_we(gpu_we),
        .gpu_ack(gpu_ack),
        
        // External memory
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_ack(mem_ack)
    );

endmodule