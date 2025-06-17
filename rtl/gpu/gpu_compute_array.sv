// GPU Compute Array with 8 compute units for matrix operations
// Each unit performs 4x4 matrix multiply-accumulate operations

module gpu_compute_array #(
    parameter NUM_UNITS = 8
) (
    input  logic clk,
    input  logic rst_n,
    
    // Memory interface
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    input  logic [31:0] mem_rdata,
    output logic mem_req,
    output logic mem_we,
    input  logic mem_ack,
    
    // Control interface from CPU
    output logic [NUM_UNITS-1:0] unit_busy,
    input  logic [NUM_UNITS-1:0] unit_start,
    input  logic [31:0] matrix_a [NUM_UNITS-1:0],
    input  logic [31:0] matrix_b [NUM_UNITS-1:0],
    output logic [31:0] matrix_c [NUM_UNITS-1:0]
);

    // Internal signals for each compute unit
    logic [NUM_UNITS-1:0] unit_mem_req;
    logic [NUM_UNITS-1:0] unit_mem_we;
    logic [31:0] unit_mem_addr [NUM_UNITS-1:0];
    logic [31:0] unit_mem_wdata [NUM_UNITS-1:0];
    logic [31:0] unit_mem_rdata [NUM_UNITS-1:0];
    logic [NUM_UNITS-1:0] unit_mem_ack;
    logic [NUM_UNITS-1:0] unit_done;
    
    // Memory arbiter state
    logic [2:0] current_unit;
    logic arbiter_busy;
    
    // Generate compute units
    genvar i;
    generate
        for (i = 0; i < NUM_UNITS; i++) begin : gpu_units
            gpu_compute_unit unit (
                .clk(clk),
                .rst_n(rst_n),
                .start(unit_start[i]),
                .busy(unit_busy[i]),
                .done(unit_done[i]),
                .matrix_a_addr(matrix_a[i]),
                .matrix_b_addr(matrix_b[i]),
                .matrix_c_addr(matrix_c[i]),
                .mem_addr(unit_mem_addr[i]),
                .mem_wdata(unit_mem_wdata[i]),
                .mem_rdata(unit_mem_rdata[i]),
                .mem_req(unit_mem_req[i]),
                .mem_we(unit_mem_we[i]),
                .mem_ack(unit_mem_ack[i])
            );
        end
    endgenerate
    
    // Simple round-robin memory arbiter with GPU priority
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_unit <= 3'h0;
            arbiter_busy <= 1'b0;
            mem_req <= 1'b0;
            mem_we <= 1'b0;
            mem_addr <= 32'h0;
            mem_wdata <= 32'h0;
        end else begin
            if (!arbiter_busy) begin
                // Find next unit requesting memory access
                for (int j = 0; j < NUM_UNITS; j++) begin
                    int unit_idx = (current_unit + j) % NUM_UNITS;
                    if (unit_mem_req[unit_idx]) begin
                        current_unit <= unit_idx[2:0];
                        arbiter_busy <= 1'b1;
                        mem_addr <= unit_mem_addr[unit_idx];
                        mem_wdata <= unit_mem_wdata[unit_idx];
                        mem_req <= 1'b1;
                        mem_we <= unit_mem_we[unit_idx];
                        break;
                    end
                end
            end else if (mem_ack) begin
                // Complete current transaction
                unit_mem_rdata[current_unit] <= mem_rdata;
                unit_mem_ack[current_unit] <= 1'b1;
                mem_req <= 1'b0;
                arbiter_busy <= 1'b0;
                current_unit <= (current_unit + 1) % NUM_UNITS;
            end else begin
                unit_mem_ack <= {NUM_UNITS{1'b0}};
            end
        end
    end

endmodule
