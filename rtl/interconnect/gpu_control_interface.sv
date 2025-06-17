// GPU Control Interface for UnifiedRISCV
// Memory-mapped registers for GPU control and status

module gpu_control_interface #(
    parameter NUM_GPU_UNITS = 8,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  logic clk,
    input  logic rst_n,
    
    // Interconnect interface
    input  logic req,
    input  logic we,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic ack,
    output logic [DATA_WIDTH-1:0] rdata,
    
    // GPU control signals
    output logic [NUM_GPU_UNITS-1:0] gpu_enable,
    output logic [NUM_GPU_UNITS-1:0] gpu_reset,
    output logic [NUM_GPU_UNITS-1:0] gpu_start,
    input  logic [NUM_GPU_UNITS-1:0] gpu_busy,
    input  logic [NUM_GPU_UNITS-1:0] gpu_done,
    input  logic [NUM_GPU_UNITS-1:0] gpu_error,
    
    // Matrix operation configuration
    output logic [31:0] gpu_matrix_a_addr [NUM_GPU_UNITS-1:0],
    output logic [31:0] gpu_matrix_b_addr [NUM_GPU_UNITS-1:0],
    output logic [31:0] gpu_matrix_c_addr [NUM_GPU_UNITS-1:0],
    output logic [15:0] gpu_operation_config [NUM_GPU_UNITS-1:0],
    
    // Performance counters
    input  logic [31:0] gpu_cycle_count [NUM_GPU_UNITS-1:0],
    input  logic [31:0] gpu_operation_count [NUM_GPU_UNITS-1:0],
    
    // Global GPU configuration
    output logic [7:0] gpu_global_priority,
    output logic gpu_global_enable,
    output logic gpu_debug_enable
);

    // Register map
    localparam GPU_GLOBAL_CTRL      = 16'h0000;
    localparam GPU_GLOBAL_STATUS    = 16'h0004;
    localparam GPU_GLOBAL_PRIORITY  = 16'h0008;
    localparam GPU_DEBUG_CTRL       = 16'h000C;
    
    // Per-unit registers (64 bytes per unit, starting at 0x0100)
    localparam GPU_UNIT_BASE        = 16'h0100;
    localparam GPU_UNIT_SIZE        = 16'h0040; // 64 bytes per unit
    
    // Per-unit register offsets
    localparam UNIT_CTRL_OFFSET     = 16'h00;
    localparam UNIT_STATUS_OFFSET   = 16'h04;
    localparam UNIT_MATRIX_A_OFFSET = 16'h08;
    localparam UNIT_MATRIX_B_OFFSET = 16'h0C;
    localparam UNIT_MATRIX_C_OFFSET = 16'h10;
    localparam UNIT_CONFIG_OFFSET   = 16'h14;
    localparam UNIT_CYCLES_OFFSET   = 16'h18;
    localparam UNIT_OPS_OFFSET      = 16'h1C;
    
    // Address decoding
    logic [15:0] reg_addr;
    logic [3:0] unit_id;
    logic [15:0] unit_offset;
    logic is_global_reg;
    logic is_unit_reg;
    logic valid_unit;
    
    assign reg_addr = addr[15:0];
    assign is_global_reg = (reg_addr < GPU_UNIT_BASE);
    assign is_unit_reg = (reg_addr >= GPU_UNIT_BASE);
    assign unit_id = (reg_addr - GPU_UNIT_BASE) / GPU_UNIT_SIZE;
    assign unit_offset = (reg_addr - GPU_UNIT_BASE) % GPU_UNIT_SIZE;
    assign valid_unit = (unit_id < NUM_GPU_UNITS);
    
    // Global registers
    logic [31:0] global_ctrl_reg;
    logic [31:0] global_status_reg;
    logic [31:0] global_priority_reg;
    logic [31:0] debug_ctrl_reg;
    
    // Per-unit control registers
    logic [31:0] unit_ctrl_reg [NUM_GPU_UNITS-1:0];
    logic [31:0] unit_config_reg [NUM_GPU_UNITS-1:0];
    
    // Global control assignments
    assign gpu_global_enable = global_ctrl_reg[0];
    assign gpu_global_priority = global_priority_reg[7:0];
    assign gpu_debug_enable = debug_ctrl_reg[0];
    
    // Per-unit control assignments
    genvar i;
    generate
        for (i = 0; i < NUM_GPU_UNITS; i++) begin : unit_assignments
            assign gpu_enable[i] = unit_ctrl_reg[i][0];
            assign gpu_reset[i] = unit_ctrl_reg[i][1];
            assign gpu_start[i] = unit_ctrl_reg[i][2];
            assign gpu_operation_config[i] = unit_config_reg[i][15:0];
        end
    endgenerate
    
    // Global status register composition
    always_comb begin
        global_status_reg = '0;
        global_status_reg[7:0] = gpu_busy;
        global_status_reg[15:8] = gpu_done;
        global_status_reg[23:16] = gpu_error;
        global_status_reg[31] = |gpu_busy; // Any GPU busy
    end
    
    // Register access logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all registers
            global_ctrl_reg <= '0;
            global_priority_reg <= 32'h80; // Default priority
            debug_ctrl_reg <= '0;
            
            for (int i = 0; i < NUM_GPU_UNITS; i++) begin
                unit_ctrl_reg[i] <= '0;
                unit_config_reg[i] <= '0;
                gpu_matrix_a_addr[i] <= '0;
                gpu_matrix_b_addr[i] <= '0;
                gpu_matrix_c_addr[i] <= '0;
            end
            
            ack <= 1'b0;
            rdata <= '0;
        end else begin
            ack <= 1'b0;
            rdata <= '0;
            
            // Clear one-shot control bits
            for (int i = 0; i < NUM_GPU_UNITS; i++) begin
                unit_ctrl_reg[i][2] <= 1'b0; // Clear start bit
            end
            
            if (req) begin
                ack <= 1'b1;
                
                if (we) begin
                    // Write operations
                    if (is_global_reg) begin
                        case (reg_addr)
                            GPU_GLOBAL_CTRL: global_ctrl_reg <= wdata;
                            GPU_GLOBAL_PRIORITY: global_priority_reg <= wdata;
                            GPU_DEBUG_CTRL: debug_ctrl_reg <= wdata;
                        endcase
                    end else if (is_unit_reg && valid_unit) begin
                        case (unit_offset)
                            UNIT_CTRL_OFFSET: unit_ctrl_reg[unit_id] <= wdata;
                            UNIT_MATRIX_A_OFFSET: gpu_matrix_a_addr[unit_id] <= wdata;
                            UNIT_MATRIX_B_OFFSET: gpu_matrix_b_addr[unit_id] <= wdata;
                            UNIT_MATRIX_C_OFFSET: gpu_matrix_c_addr[unit_id] <= wdata;
                            UNIT_CONFIG_OFFSET: unit_config_reg[unit_id] <= wdata;
                        endcase
                    end
                end else begin
                    // Read operations
                    if (is_global_reg) begin
                        case (reg_addr)
                            GPU_GLOBAL_CTRL: rdata <= global_ctrl_reg;
                            GPU_GLOBAL_STATUS: rdata <= global_status_reg;
                            GPU_GLOBAL_PRIORITY: rdata <= global_priority_reg;
                            GPU_DEBUG_CTRL: rdata <= debug_ctrl_reg;
                            default: rdata <= 32'hDEADBEEF; // Invalid address
                        endcase
                    end else if (is_unit_reg && valid_unit) begin
                        case (unit_offset)
                            UNIT_CTRL_OFFSET: begin
                                rdata <= unit_ctrl_reg[unit_id];
                            end
                            UNIT_STATUS_OFFSET: begin
                                rdata[0] <= gpu_busy[unit_id];
                                rdata[1] <= gpu_done[unit_id];
                                rdata[2] <= gpu_error[unit_id];
                                rdata[3] <= gpu_enable[unit_id];
                            end
                            UNIT_MATRIX_A_OFFSET: rdata <= gpu_matrix_a_addr[unit_id];
                            UNIT_MATRIX_B_OFFSET: rdata <= gpu_matrix_b_addr[unit_id];
                            UNIT_MATRIX_C_OFFSET: rdata <= gpu_matrix_c_addr[unit_id];
                            UNIT_CONFIG_OFFSET: rdata <= unit_config_reg[unit_id];
                            UNIT_CYCLES_OFFSET: rdata <= gpu_cycle_count[unit_id];
                            UNIT_OPS_OFFSET: rdata <= gpu_operation_count[unit_id];
                            default: rdata <= 32'hDEADBEEF; // Invalid address
                        endcase
                    end else begin
                        rdata <= 32'hDEADBEEF; // Invalid unit or address
                    end
                end
            end
        end
    end

endmodule
