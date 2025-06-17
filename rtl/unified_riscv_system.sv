// UnifiedRISCV - Top-level system integrating RISC-V CPU with GPU compute units
// Optimized for deep learning workloads with unified memory architecture

module unified_riscv_system #(
    parameter XLEN = 32,
    parameter NUM_GPU_UNITS = 8,
    parameter CACHE_LINE_WIDTH = 512,
    parameter NUM_MEMORY_BANKS = 16,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter NUM_MASTERS = NUM_GPU_UNITS + 1,  // CPU + GPU units
    parameter NUM_SLAVES = 4,                   // Memory, GPU ctrl, sys ctrl, debug
    parameter ID_WIDTH = 4
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
    output logic debug_valid,
    
    // AXI4-Lite interface (optional)
    output logic [ADDR_WIDTH-1:0] axi_awaddr,
    output logic [2:0] axi_awprot,
    output logic axi_awvalid,
    input  logic axi_awready,
    output logic [DATA_WIDTH-1:0] axi_wdata,
    output logic [(DATA_WIDTH/8)-1:0] axi_wstrb,
    output logic axi_wvalid,
    input  logic axi_wready,
    input  logic [1:0] axi_bresp,
    input  logic axi_bvalid,
    output logic axi_bready,
    output logic [ADDR_WIDTH-1:0] axi_araddr,
    output logic [2:0] axi_arprot,
    output logic axi_arvalid,
    input  logic axi_arready,
    input  logic [DATA_WIDTH-1:0] axi_rdata,
    input  logic [1:0] axi_rresp,
    input  logic axi_rvalid,
    output logic axi_rready
);

    // Interconnect master interfaces
    logic [NUM_MASTERS-1:0] master_req;
    logic [NUM_MASTERS-1:0] master_we;
    logic [NUM_MASTERS-1:0][ADDR_WIDTH-1:0] master_addr;
    logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0] master_wdata;
    logic [NUM_MASTERS-1:0][ID_WIDTH-1:0] master_id;
    logic [NUM_MASTERS-1:0] master_ack;
    logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0] master_rdata;
    
    // Interconnect slave interfaces
    logic [NUM_SLAVES-1:0] slave_req;
    logic [NUM_SLAVES-1:0] slave_we;
    logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0] slave_addr;
    logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0] slave_wdata;
    logic [NUM_SLAVES-1:0][ID_WIDTH-1:0] slave_id;
    logic [NUM_SLAVES-1:0] slave_ack;
    logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0] slave_rdata;
    
    // GPU control signals
    logic [NUM_GPU_UNITS-1:0] gpu_unit_busy;
    logic [NUM_GPU_UNITS-1:0] gpu_unit_start;
    logic [NUM_GPU_UNITS-1:0] gpu_enable;
    logic [NUM_GPU_UNITS-1:0] gpu_reset;
    logic [NUM_GPU_UNITS-1:0] gpu_done;
    logic [NUM_GPU_UNITS-1:0] gpu_error;
    logic [31:0] gpu_matrix_a_addr [NUM_GPU_UNITS-1:0];
    logic [31:0] gpu_matrix_b_addr [NUM_GPU_UNITS-1:0];
    logic [31:0] gpu_matrix_c_addr [NUM_GPU_UNITS-1:0];
    logic [15:0] gpu_operation_config [NUM_GPU_UNITS-1:0];
    logic [31:0] gpu_cycle_count [NUM_GPU_UNITS-1:0];
    logic [31:0] gpu_operation_count [NUM_GPU_UNITS-1:0];
    logic [7:0] gpu_global_priority;
    logic gpu_global_enable;
    logic gpu_debug_enable;
    
    // Individual GPU unit memory interfaces
    logic [NUM_GPU_UNITS-1:0] gpu_unit_req;
    logic [NUM_GPU_UNITS-1:0] gpu_unit_we;
    logic [NUM_GPU_UNITS-1:0][ADDR_WIDTH-1:0] gpu_unit_addr;
    logic [NUM_GPU_UNITS-1:0][DATA_WIDTH-1:0] gpu_unit_wdata;
    logic [NUM_GPU_UNITS-1:0] gpu_unit_ack;
    logic [NUM_GPU_UNITS-1:0][DATA_WIDTH-1:0] gpu_unit_rdata;
    
    // CPU master interface
    logic cpu_req, cpu_we, cpu_ack;
    logic [ADDR_WIDTH-1:0] cpu_addr;
    logic [DATA_WIDTH-1:0] cpu_wdata, cpu_rdata;
    
    // Master interface assignments
    // CPU is master 0
    assign master_req[0] = cpu_req;
    assign master_we[0] = cpu_we;
    assign master_addr[0] = cpu_addr;
    assign master_wdata[0] = cpu_wdata;
    assign master_id[0] = 4'h0;
    assign cpu_ack = master_ack[0];
    assign cpu_rdata = master_rdata[0];
    
    // GPU units are masters 1-8
    genvar m;
    generate
        for (m = 0; m < NUM_GPU_UNITS; m++) begin : gpu_master_connections
            assign master_req[m+1] = gpu_unit_req[m];
            assign master_we[m+1] = gpu_unit_we[m];
            assign master_addr[m+1] = gpu_unit_addr[m];
            assign master_wdata[m+1] = gpu_unit_wdata[m];
            assign master_id[m+1] = 4'h1 + m;
            assign gpu_unit_ack[m] = master_ack[m+1];
            assign gpu_unit_rdata[m] = master_rdata[m+1];
        end
    endgenerate
    
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
        .gpu_matrix_a(gpu_matrix_a_addr),
        .gpu_matrix_b(gpu_matrix_b_addr),
        .gpu_matrix_c(gpu_matrix_c_addr),
        .debug_pc(debug_pc),
        .debug_inst(debug_inst),
        .debug_valid(debug_valid)
    );
    
    // GPU Compute Units (individual units with their own memory interfaces)
    genvar g;
    generate
        for (g = 0; g < NUM_GPU_UNITS; g++) begin : gpu_units
            gpu_compute_unit gpu_unit (
                .clk(clk),
                .rst_n(rst_n & ~gpu_reset[g]),
                .start(gpu_unit_start[g] & gpu_enable[g]),
                .busy(gpu_unit_busy[g]),
                .done(gpu_done[g]),
                .matrix_a_addr(gpu_matrix_a_addr[g]),
                .matrix_b_addr(gpu_matrix_b_addr[g]),
                .matrix_c_addr(gpu_matrix_c_addr[g]),
                .mem_addr(gpu_unit_addr[g]),
                .mem_wdata(gpu_unit_wdata[g]),
                .mem_rdata(gpu_unit_rdata[g]),
                .mem_req(gpu_unit_req[g]),
                .mem_we(gpu_unit_we[g]),
                .mem_ack(gpu_unit_ack[g])
            );
        end
    endgenerate
    
    // System Interconnect
    system_interconnect #(
        .NUM_MASTERS(NUM_MASTERS),
        .NUM_SLAVES(NUM_SLAVES),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) interconnect (
        .clk(clk),
        .rst_n(rst_n),
        .master_req(master_req),
        .master_we(master_we),
        .master_addr(master_addr),
        .master_wdata(master_wdata),
        .master_id(master_id),
        .master_ack(master_ack),
        .master_rdata(master_rdata),
        .slave_req(slave_req),
        .slave_we(slave_we),
        .slave_addr(slave_addr),
        .slave_wdata(slave_wdata),
        .slave_id(slave_id),
        .slave_ack(slave_ack),
        .slave_rdata(slave_rdata)
    );
    
    // Unified Memory Controller (Slave 0)
    unified_memory_controller #(
        .CACHE_LINE_WIDTH(CACHE_LINE_WIDTH),
        .NUM_BANKS(NUM_MEMORY_BANKS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) memory_controller (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_addr(slave_addr[0]),
        .cpu_wdata(slave_wdata[0]),
        .cpu_rdata(slave_rdata[0]),
        .cpu_req(slave_req[0]),
        .cpu_we(slave_we[0]),
        .cpu_ack(slave_ack[0]),
        .gpu_addr(32'h0),     // Unified through interconnect
        .gpu_wdata(32'h0),
        .gpu_rdata(),
        .gpu_req(1'b0),
        .gpu_we(1'b0),
        .gpu_ack(),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_ack(mem_ack)
    );
    
    // GPU Control Interface (Slave 1)
    gpu_control_interface #(
        .NUM_GPU_UNITS(NUM_GPU_UNITS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) gpu_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .req(slave_req[1]),
        .we(slave_we[1]),
        .addr(slave_addr[1]),
        .wdata(slave_wdata[1]),
        .ack(slave_ack[1]),
        .rdata(slave_rdata[1]),
        .gpu_enable(gpu_enable),
        .gpu_reset(gpu_reset),
        .gpu_start(gpu_unit_start),
        .gpu_busy(gpu_unit_busy),
        .gpu_done(gpu_done),
        .gpu_error(gpu_error),
        .gpu_matrix_a_addr(gpu_matrix_a_addr),
        .gpu_matrix_b_addr(gpu_matrix_b_addr),
        .gpu_matrix_c_addr(gpu_matrix_c_addr),
        .gpu_operation_config(gpu_operation_config),
        .gpu_cycle_count(gpu_cycle_count),
        .gpu_operation_count(gpu_operation_count),
        .gpu_global_priority(gpu_global_priority),
        .gpu_global_enable(gpu_global_enable),
        .gpu_debug_enable(gpu_debug_enable)
    );
    
    // System Control Registers (Slave 2) - Simple placeholder
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slave_ack[2] <= 1'b0;
            slave_rdata[2] <= '0;
        end else begin
            slave_ack[2] <= slave_req[2];
            slave_rdata[2] <= 32'hDEAD2222; // System control placeholder
        end
    end
    
    // Debug Interface (Slave 3) - Simple placeholder
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slave_ack[3] <= 1'b0;
            slave_rdata[3] <= '0;
        end else begin
            slave_ack[3] <= slave_req[3];
            slave_rdata[3] <= 32'hDEAD3333; // Debug interface placeholder
        end
    end
    
    // AXI4-Lite Bridge (optional external interface)
    axi_bridge #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) axi_bridge_inst (
        .clk(clk),
        .rst_n(rst_n),
        .internal_req(1'b0),     // Not connected in this version
        .internal_we(1'b0),
        .internal_addr(32'h0),
        .internal_wdata(32'h0),
        .internal_ack(),
        .internal_rdata(),
        .axi_awaddr(axi_awaddr),
        .axi_awprot(axi_awprot),
        .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready),
        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready),
        .axi_bresp(axi_bresp),
        .axi_bvalid(axi_bvalid),
        .axi_bready(axi_bready),
        .axi_araddr(axi_araddr),
        .axi_arprot(axi_arprot),
        .axi_arvalid(axi_arvalid),
        .axi_arready(axi_arready),
        .axi_rdata(axi_rdata),
        .axi_rresp(axi_rresp),
        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready)
    );

endmodule
