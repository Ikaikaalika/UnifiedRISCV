// RISC-V RV32I CPU Core with Custom GPU Instructions
// Extended with GPU control and matrix operations

module riscv_cpu #(
    parameter XLEN = 32
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
    
    // GPU interface
    input  logic [7:0] gpu_unit_busy,
    output logic [7:0] gpu_unit_start,
    output logic [31:0] gpu_matrix_a [7:0],
    output logic [31:0] gpu_matrix_b [7:0],
    output logic [31:0] gpu_matrix_c [7:0],
    
    // Debug interface
    output logic [31:0] debug_pc,
    output logic [31:0] debug_inst,
    output logic debug_valid
);

    // CPU state
    logic [31:0] pc, pc_next;
    logic [31:0] registers [31:0];
    logic [31:0] instruction;
    logic [31:0] immediate;
    
    // Pipeline stages
    typedef enum logic [2:0] {
        FETCH,
        DECODE,
        EXECUTE,
        MEMORY,
        WRITEBACK
    } pipeline_stage_t;
    
    pipeline_stage_t current_stage;
    
    // Instruction decode
    logic [6:0] opcode;
    logic [4:0] rd, rs1, rs2;
    logic [2:0] funct3;
    logic [6:0] funct7;
    
    // ALU
    logic [31:0] alu_a, alu_b, alu_result;
    logic [3:0] alu_op;
    
    // Control signals
    logic reg_write_en;
    logic [1:0] reg_write_src;
    logic branch_taken;
    logic mem_read, mem_write;
    logic gpu_instruction;
    
    // Custom GPU opcodes (using custom-0 and custom-1 space)
    localparam GPU_MATMUL   = 7'b0001011;  // custom-0
    localparam GPU_STATUS   = 7'b0101011;  // custom-1
    
    assign opcode = instruction[6:0];
    assign rd = instruction[11:7];
    assign rs1 = instruction[19:15];
    assign rs2 = instruction[24:20];
    assign funct3 = instruction[14:12];
    assign funct7 = instruction[31:25];
    
    assign debug_pc = pc;
    assign debug_inst = instruction;
    assign debug_valid = (current_stage == DECODE);
    
    // Main CPU pipeline
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'h0;
            current_stage <= FETCH;
            for (int i = 0; i < 32; i++) begin
                registers[i] <= 32'h0;
            end
            gpu_unit_start <= 8'h0;
        end else begin
            case (current_stage)
                FETCH: begin
                    mem_addr <= pc;
                    mem_req <= 1'b1;
                    mem_we <= 1'b0;
                    if (mem_ack) begin
                        instruction <= mem_rdata;
                        current_stage <= DECODE;
                        mem_req <= 1'b0;
                    end
                end
                
                DECODE: begin
                    // Decode instruction and prepare operands
                    alu_a <= registers[rs1];
                    case (opcode)
                        7'b0010011: begin // I-type (ADDI, etc.)
                            immediate <= {{20{instruction[31]}}, instruction[31:20]};
                            alu_b <= immediate;
                            alu_op <= (funct3 == 3'b000) ? 4'b0000 : 4'b0001; // ADD/SUB
                        end
                        7'b0110011: begin // R-type (ADD, SUB, etc.)
                            alu_b <= registers[rs2];
                            alu_op <= (funct3 == 3'b000) ? 
                                     ((funct7 == 7'b0000000) ? 4'b0000 : 4'b0001) : // ADD/SUB
                                     4'b0010; // Other ops
                        end
                        GPU_MATMUL: begin // Custom GPU matrix multiply
                            gpu_instruction <= 1'b1;
                        end
                        default: begin
                            alu_op <= 4'b0000;
                        end
                    endcase
                    current_stage <= EXECUTE;
                end
                
                EXECUTE: begin
                    if (gpu_instruction) begin
                        // Handle GPU instructions
                        case (funct3)
                            3'b000: begin // Matrix multiply setup
                                if (!gpu_unit_busy[rs1[2:0]]) begin
                                    gpu_matrix_a[rs1[2:0]] <= registers[rs1];
                                    gpu_matrix_b[rs1[2:0]] <= registers[rs2];
                                    gpu_unit_start[rs1[2:0]] <= 1'b1;
                                end
                            end
                            3'b001: begin // Get result
                                if (!gpu_unit_busy[rs1[2:0]]) begin
                                    registers[rd] <= gpu_matrix_c[rs1[2:0]];
                                end
                            end
                        endcase
                        gpu_instruction <= 1'b0;
                    end else begin
                        // Standard ALU operations
                        case (alu_op)
                            4'b0000: alu_result <= alu_a + alu_b;  // ADD
                            4'b0001: alu_result <= alu_a - alu_b;  // SUB
                            4'b0010: alu_result <= alu_a & alu_b;  // AND
                            4'b0011: alu_result <= alu_a | alu_b;  // OR
                            4'b0100: alu_result <= alu_a ^ alu_b;  // XOR
                            4'b0101: alu_result <= alu_a << alu_b[4:0]; // SLL
                            4'b0110: alu_result <= alu_a >> alu_b[4:0]; // SRL
                            4'b0111: alu_result <= $signed(alu_a) >>> alu_b[4:0]; // SRA
                            default: alu_result <= 32'h0;
                        endcase
                    end
                    current_stage <= MEMORY;
                end
                
                MEMORY: begin
                    // Handle memory operations (load/store)
                    case (opcode)
                        7'b0000011: begin // Load
                            mem_addr <= alu_result;
                            mem_req <= 1'b1;
                            mem_we <= 1'b0;
                            if (mem_ack) begin
                                registers[rd] <= mem_rdata;
                                mem_req <= 1'b0;
                                current_stage <= WRITEBACK;
                            end
                        end
                        7'b0100011: begin // Store
                            mem_addr <= alu_result;
                            mem_wdata <= registers[rs2];
                            mem_req <= 1'b1;
                            mem_we <= 1'b1;
                            if (mem_ack) begin
                                mem_req <= 1'b0;
                                current_stage <= WRITEBACK;
                            end
                        end
                        default: current_stage <= WRITEBACK;
                    endcase
                end
                
                WRITEBACK: begin
                    // Write back results to register file
                    if (rd != 5'h0 && !gpu_instruction) begin // x0 is hardwired to 0
                        case (opcode)
                            7'b0010011, 7'b0110011: registers[rd] <= alu_result;
                            // Load instructions already handled in MEMORY stage
                        endcase
                    end
                    
                    // Advance PC and return to fetch
                    pc <= pc + 4;
                    current_stage <= FETCH;
                    gpu_unit_start <= 8'h0; // Clear GPU start signals
                end
            endcase
        end
    end

endmodule