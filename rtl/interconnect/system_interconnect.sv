// System Interconnect for UnifiedRISCV
// High-performance crossbar switch connecting CPU, GPU array, and memory subsystem

module system_interconnect #(
    parameter NUM_MASTERS = 9,  // 1 CPU + 8 GPU units
    parameter NUM_SLAVES = 4,   // Memory controller, GPU control, system regs, debug
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH = 4
) (
    input  logic clk,
    input  logic rst_n,
    
    // Master interfaces (CPU + 8 GPU units)
    input  logic [NUM_MASTERS-1:0] master_req,
    input  logic [NUM_MASTERS-1:0] master_we,
    input  logic [NUM_MASTERS-1:0][ADDR_WIDTH-1:0] master_addr,
    input  logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0] master_wdata,
    input  logic [NUM_MASTERS-1:0][ID_WIDTH-1:0] master_id,
    output logic [NUM_MASTERS-1:0] master_ack,
    output logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0] master_rdata,
    
    // Slave interfaces
    output logic [NUM_SLAVES-1:0] slave_req,
    output logic [NUM_SLAVES-1:0] slave_we,
    output logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0] slave_addr,
    output logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0] slave_wdata,
    output logic [NUM_SLAVES-1:0][ID_WIDTH-1:0] slave_id,
    input  logic [NUM_SLAVES-1:0] slave_ack,
    input  logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0] slave_rdata
);

    // Address decoding
    localparam MAIN_MEMORY_BASE = 32'h00000000;
    localparam MAIN_MEMORY_SIZE = 32'h10000000; // 256MB
    localparam GPU_CTRL_BASE    = 32'h10000000;
    localparam GPU_CTRL_SIZE    = 32'h00010000; // 64KB
    localparam SYS_CTRL_BASE    = 32'h20000000;
    localparam SYS_CTRL_SIZE    = 32'h00010000; // 64KB
    localparam DEBUG_BASE       = 32'h30000000;
    localparam DEBUG_SIZE       = 32'h00010000; // 64KB
    
    // Slave indices
    localparam SLAVE_MEMORY = 0;
    localparam SLAVE_GPU_CTRL = 1;
    localparam SLAVE_SYS_CTRL = 2;
    localparam SLAVE_DEBUG = 3;
    
    // Master priority (GPU units have higher priority than CPU)
    localparam CPU_MASTER = 0;
    // GPU masters are 1-8
    
    // Crossbar state
    logic [NUM_MASTERS-1:0][1:0] master_target_slave;
    logic [NUM_MASTERS-1:0] master_valid_target;
    logic [NUM_SLAVES-1:0][3:0] slave_granted_master;
    logic [NUM_SLAVES-1:0] slave_has_master;
    
    // Arbitration state
    logic [NUM_SLAVES-1:0][NUM_MASTERS-1:0] request_matrix;
    logic [NUM_SLAVES-1:0][NUM_MASTERS-1:0] grant_matrix;
    
    // Address decoder
    always_comb begin
        for (int m = 0; m < NUM_MASTERS; m++) begin
            master_valid_target[m] = 1'b0;
            master_target_slave[m] = 2'b00;
            
            if (master_req[m]) begin
                if (master_addr[m] >= MAIN_MEMORY_BASE && 
                    master_addr[m] < MAIN_MEMORY_BASE + MAIN_MEMORY_SIZE) begin
                    master_target_slave[m] = SLAVE_MEMORY;
                    master_valid_target[m] = 1'b1;
                end else if (master_addr[m] >= GPU_CTRL_BASE && 
                           master_addr[m] < GPU_CTRL_BASE + GPU_CTRL_SIZE) begin
                    master_target_slave[m] = SLAVE_GPU_CTRL;
                    master_valid_target[m] = 1'b1;
                end else if (master_addr[m] >= SYS_CTRL_BASE && 
                           master_addr[m] < SYS_CTRL_BASE + SYS_CTRL_SIZE) begin
                    master_target_slave[m] = SLAVE_SYS_CTRL;
                    master_valid_target[m] = 1'b1;
                end else if (master_addr[m] >= DEBUG_BASE && 
                           master_addr[m] < DEBUG_BASE + DEBUG_SIZE) begin
                    master_target_slave[m] = SLAVE_DEBUG;
                    master_valid_target[m] = 1'b1;
                end
            end
        end
    end
    
    // Build request matrix
    always_comb begin
        for (int s = 0; s < NUM_SLAVES; s++) begin
            for (int m = 0; m < NUM_MASTERS; m++) begin
                request_matrix[s][m] = master_valid_target[m] && 
                                     (master_target_slave[m] == s);
            end
        end
    end
    
    // Priority arbiters for each slave
    genvar s;
    generate
        for (s = 0; s < NUM_SLAVES; s++) begin : slave_arbiters
            priority_arbiter #(
                .NUM_REQUESTERS(NUM_MASTERS),
                .GPU_PRIORITY(1'b1)  // GPU units have priority over CPU
            ) arbiter (
                .clk(clk),
                .rst_n(rst_n),
                .requests(request_matrix[s]),
                .grants(grant_matrix[s]),
                .granted_id(slave_granted_master[s]),
                .any_grant(slave_has_master[s])
            );
        end
    endgenerate
    
    // Connect granted masters to slaves
    always_comb begin
        // Initialize slave outputs
        for (int s = 0; s < NUM_SLAVES; s++) begin
            slave_req[s] = 1'b0;
            slave_we[s] = 1'b0;
            slave_addr[s] = 32'h0;
            slave_wdata[s] = 32'h0;
            slave_id[s] = 4'h0;
            
            if (slave_has_master[s]) begin
                int master_idx = slave_granted_master[s];
                slave_req[s] = master_req[master_idx];
                slave_we[s] = master_we[master_idx];
                slave_addr[s] = master_addr[master_idx];
                slave_wdata[s] = master_wdata[master_idx];
                slave_id[s] = master_id[master_idx];
            end
        end
        
        // Route responses back to masters
        for (int m = 0; m < NUM_MASTERS; m++) begin
            master_ack[m] = 1'b0;
            master_rdata[m] = 32'h0;
            
            if (master_valid_target[m]) begin
                int slave_idx = master_target_slave[m];
                if (grant_matrix[slave_idx][m]) begin
                    master_ack[m] = slave_ack[slave_idx];
                    master_rdata[m] = slave_rdata[slave_idx];
                end
            end
        end
    end

endmodule
