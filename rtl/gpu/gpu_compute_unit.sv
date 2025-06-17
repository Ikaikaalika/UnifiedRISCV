// GPU Compute Unit - Single unit performing 4x4 matrix multiply-accumulate
// Optimized for INT8/FP16 operations with high throughput

module gpu_compute_unit (
    input  logic clk,
    input  logic rst_n,
    
    // Control interface
    input  logic start,
    output logic busy,
    output logic done,
    
    // Matrix addresses in memory
    input  logic [31:0] matrix_a_addr,
    input  logic [31:0] matrix_b_addr,
    input  logic [31:0] matrix_c_addr,
    
    // Memory interface
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    input  logic [31:0] mem_rdata,
    output logic mem_req,
    output logic mem_we,
    input  logic mem_ack
);

    // State machine for matrix operations
    typedef enum logic [3:0] {
        IDLE,
        LOAD_A,
        LOAD_B,
        COMPUTE,
        STORE_C,
        DONE_STATE
    } state_t;
    
    state_t current_state, next_state;
    
    // Matrix storage (4x4 matrices, 8-bit elements)
    logic [7:0] matrix_a [3:0][3:0];
    logic [7:0] matrix_b [3:0][3:0];
    logic [15:0] matrix_c [3:0][3:0]; // 16-bit for accumulation
    
    // Control counters
    logic [3:0] load_counter;
    logic [3:0] compute_counter;
    logic [3:0] store_counter;
    logic [1:0] row_idx, col_idx, k_idx;
    
    // MAC units for parallel computation
    logic [15:0] mac_result [3:0][3:0];
    logic [15:0] accumulator [3:0][3:0];
    
    assign busy = (current_state != IDLE);
    assign done = (current_state == DONE_STATE);
    
    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            load_counter <= 4'h0;
            compute_counter <= 4'h0;
            store_counter <= 4'h0;
            row_idx <= 2'h0;
            col_idx <= 2'h0;
            k_idx <= 2'h0;
        end else begin
            current_state <= next_state;
            
            case (current_state)
                IDLE: begin
                    if (start) begin
                        load_counter <= 4'h0;
                        compute_counter <= 4'h0;
                        store_counter <= 4'h0;
                        row_idx <= 2'h0;
                        col_idx <= 2'h0;
                        k_idx <= 2'h0;
                        // Initialize result matrix to zero
                        for (int i = 0; i < 4; i++) begin
                            for (int j = 0; j < 4; j++) begin
                                matrix_c[i][j] <= 16'h0;
                            end
                        end
                    end
                end
                
                LOAD_A: begin
                    if (mem_ack) begin
                        // Pack 4 8-bit values from 32-bit word
                        matrix_a[load_counter[3:2]][load_counter[1:0]] <= mem_rdata[7:0];
                        matrix_a[load_counter[3:2]][load_counter[1:0]+1] <= mem_rdata[15:8];
                        matrix_a[load_counter[3:2]][load_counter[1:0]+2] <= mem_rdata[23:16];
                        matrix_a[load_counter[3:2]][load_counter[1:0]+3] <= mem_rdata[31:24];
                        load_counter <= load_counter + 1;
                    end
                end
                
                LOAD_B: begin
                    if (mem_ack) begin
                        matrix_b[load_counter[3:2]][load_counter[1:0]] <= mem_rdata[7:0];
                        matrix_b[load_counter[3:2]][load_counter[1:0]+1] <= mem_rdata[15:8];
                        matrix_b[load_counter[3:2]][load_counter[1:0]+2] <= mem_rdata[23:16];
                        matrix_b[load_counter[3:2]][load_counter[1:0]+3] <= mem_rdata[31:24];
                        load_counter <= load_counter + 1;
                    end
                end
                
                COMPUTE: begin
                    // Perform matrix multiplication using systolic array approach
                    if (compute_counter < 4) begin
                        // Compute one row of results per cycle
                        for (int j = 0; j < 4; j++) begin
                            for (int k = 0; k < 4; k++) begin
                                matrix_c[compute_counter][j] <= matrix_c[compute_counter][j] + 
                                    (matrix_a[compute_counter][k] * matrix_b[k][j]);
                            end
                        end
                        compute_counter <= compute_counter + 1;
                    end
                end
                
                STORE_C: begin
                    if (mem_ack) begin
                        store_counter <= store_counter + 1;
                    end
                end
            endcase
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (start) next_state = LOAD_A;
            end
            LOAD_A: begin
                if (load_counter >= 4) next_state = LOAD_B;
            end
            LOAD_B: begin
                if (load_counter >= 8) next_state = COMPUTE;
            end
            COMPUTE: begin
                if (compute_counter >= 4) next_state = STORE_C;
            end
            STORE_C: begin
                if (store_counter >= 4) next_state = DONE_STATE;
            end
            DONE_STATE: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Memory interface control
    always_comb begin
        mem_req = 1'b0;
        mem_we = 1'b0;
        mem_addr = 32'h0;
        mem_wdata = 32'h0;
        
        case (current_state)
            LOAD_A: begin
                mem_req = 1'b1;
                mem_we = 1'b0;
                mem_addr = matrix_a_addr + (load_counter << 2); // 4 bytes per word
            end
            LOAD_B: begin
                mem_req = 1'b1;
                mem_we = 1'b0;
                mem_addr = matrix_b_addr + ((load_counter - 4) << 2);
            end
            STORE_C: begin
                mem_req = 1'b1;
                mem_we = 1'b1;
                mem_addr = matrix_c_addr + (store_counter << 2);
                // Pack 2 16-bit results into 32-bit word
                mem_wdata = {matrix_c[store_counter[1:0]][1], matrix_c[store_counter[1:0]][0]};
            end
        endcase
    end

endmodule
