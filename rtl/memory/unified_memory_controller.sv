// Unified Memory Controller with GPU Priority for ML Workloads
// M1-inspired design with 512-bit cache lines and 16 banks

module unified_memory_controller #(
    parameter CACHE_LINE_WIDTH = 512,
    parameter NUM_BANKS = 16,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  logic clk,
    input  logic rst_n,
    
    // CPU interface
    input  logic [ADDR_WIDTH-1:0] cpu_addr,
    input  logic [DATA_WIDTH-1:0] cpu_wdata,
    output logic [DATA_WIDTH-1:0] cpu_rdata,
    input  logic cpu_req,
    input  logic cpu_we,
    output logic cpu_ack,
    
    // GPU interface (higher priority)
    input  logic [ADDR_WIDTH-1:0] gpu_addr,
    input  logic [DATA_WIDTH-1:0] gpu_wdata,
    output logic [DATA_WIDTH-1:0] gpu_rdata,
    input  logic gpu_req,
    input  logic gpu_we,
    output logic gpu_ack,
    
    // External memory interface (512-bit wide)
    output logic [ADDR_WIDTH-1:0] mem_addr,
    output logic [CACHE_LINE_WIDTH-1:0] mem_wdata,
    input  logic [CACHE_LINE_WIDTH-1:0] mem_rdata,
    output logic mem_req,
    output logic mem_we,
    input  logic mem_ack
);

    // L1 Cache parameters
    localparam CACHE_SIZE = 32 * 1024; // 32KB L1 cache
    localparam CACHE_WAYS = 4;
    localparam CACHE_SETS = CACHE_SIZE / (CACHE_WAYS * CACHE_LINE_WIDTH / 8);
    localparam SET_BITS = $clog2(CACHE_SETS);
    localparam OFFSET_BITS = $clog2(CACHE_LINE_WIDTH / 8);
    localparam TAG_BITS = ADDR_WIDTH - SET_BITS - OFFSET_BITS;
    
    // Cache structures
    logic [TAG_BITS-1:0] cache_tags [CACHE_SETS-1:0][CACHE_WAYS-1:0];
    logic [CACHE_LINE_WIDTH-1:0] cache_data [CACHE_SETS-1:0][CACHE_WAYS-1:0];
    logic cache_valid [CACHE_SETS-1:0][CACHE_WAYS-1:0];
    logic cache_dirty [CACHE_SETS-1:0][CACHE_WAYS-1:0];
    logic [1:0] cache_lru [CACHE_SETS-1:0]; // Simple 2-bit LRU for 4-way
    
    // Memory banking
    logic [3:0] bank_select;
    logic [NUM_BANKS-1:0] bank_busy;
    logic [NUM_BANKS-1:0] bank_req;
    logic [ADDR_WIDTH-1:0] bank_addr [NUM_BANKS-1:0];
    
    // Request arbitration
    typedef enum logic [2:0] {
        IDLE,
        GPU_ACCESS,
        CPU_ACCESS,
        CACHE_FILL,
        CACHE_WRITEBACK
    } arbiter_state_t;
    
    arbiter_state_t current_state, next_state;
    
    // Current request tracking
    logic [ADDR_WIDTH-1:0] current_addr;
    logic [DATA_WIDTH-1:0] current_wdata;
    logic current_we;
    logic is_gpu_req;
    
    // Cache lookup signals
    logic [SET_BITS-1:0] cache_set;
    logic [TAG_BITS-1:0] cache_tag;
    logic [OFFSET_BITS-1:0] cache_offset;
    logic cache_hit;
    logic [1:0] hit_way;
    logic [1:0] victim_way;
    
    // Address decomposition
    assign cache_set = current_addr[SET_BITS+OFFSET_BITS-1:OFFSET_BITS];
    assign cache_tag = current_addr[ADDR_WIDTH-1:SET_BITS+OFFSET_BITS];
    assign cache_offset = current_addr[OFFSET_BITS-1:0];
    assign bank_select = current_addr[7:4]; // Simple bank mapping
    
    // Cache hit detection
    always_comb begin
        cache_hit = 1'b0;
        hit_way = 2'b00;
        for (int i = 0; i < CACHE_WAYS; i++) begin
            if (cache_valid[cache_set][i] && 
                cache_tags[cache_set][i] == cache_tag) begin
                cache_hit = 1'b1;
                hit_way = i[1:0];
                break;
            end
        end
    end
    
    // LRU victim selection
    always_comb begin
        victim_way = cache_lru[cache_set];
    end
    
    // Main state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            cpu_ack <= 1'b0;
            gpu_ack <= 1'b0;
            mem_req <= 1'b0;
            
            // Initialize cache
            for (int i = 0; i < CACHE_SETS; i++) begin
                for (int j = 0; j < CACHE_WAYS; j++) begin
                    cache_valid[i][j] <= 1'b0;
                    cache_dirty[i][j] <= 1'b0;
                    cache_tags[i][j] <= '0;
                    cache_data[i][j] <= '0;
                end
                cache_lru[i] <= 2'b00;
            end
        end else begin
            current_state <= next_state;
            
            case (current_state)
                IDLE: begin
                    cpu_ack <= 1'b0;
                    gpu_ack <= 1'b0;
                    
                    // GPU has priority over CPU
                    if (gpu_req) begin
                        current_addr <= gpu_addr;
                        current_wdata <= gpu_wdata;
                        current_we <= gpu_we;
                        is_gpu_req <= 1'b1;
                    end else if (cpu_req) begin
                        current_addr <= cpu_addr;
                        current_wdata <= cpu_wdata;
                        current_we <= cpu_we;
                        is_gpu_req <= 1'b0;
                    end
                end
                
                GPU_ACCESS, CPU_ACCESS: begin
                    if (cache_hit) begin
                        // Cache hit - serve immediately
                        if (current_we) begin
                            // Write hit
                            cache_data[cache_set][hit_way] <= update_cache_line(
                                cache_data[cache_set][hit_way], 
                                current_wdata, 
                                cache_offset
                            );
                            cache_dirty[cache_set][hit_way] <= 1'b1;
                        end else begin
                            // Read hit
                            if (is_gpu_req) begin
                                gpu_rdata <= extract_word(cache_data[cache_set][hit_way], cache_offset);
                            end else begin
                                cpu_rdata <= extract_word(cache_data[cache_set][hit_way], cache_offset);
                            end
                        end
                        
                        // Update LRU
                        cache_lru[cache_set] <= update_lru(cache_lru[cache_set], hit_way);
                        
                        // Acknowledge request
                        if (is_gpu_req) gpu_ack <= 1'b1;
                        else cpu_ack <= 1'b1;
                        
                    end else begin
                        // Cache miss - need to fetch from memory
                        if (cache_dirty[cache_set][victim_way] && 
                            cache_valid[cache_set][victim_way]) begin
                            // Need to writeback dirty line first
                            next_state <= CACHE_WRITEBACK;
                        end else begin
                            // Can directly fetch new line
                            next_state <= CACHE_FILL;
                        end
                    end
                end
                
                CACHE_WRITEBACK: begin
                    if (!mem_req) begin
                        mem_addr <= {cache_tags[cache_set][victim_way], cache_set, {OFFSET_BITS{1'b0}}};
                        mem_wdata <= cache_data[cache_set][victim_way];
                        mem_we <= 1'b1;
                        mem_req <= 1'b1;
                    end else if (mem_ack) begin
                        mem_req <= 1'b0;
                        cache_dirty[cache_set][victim_way] <= 1'b0;
                        next_state <= CACHE_FILL;
                    end
                end
                
                CACHE_FILL: begin
                    if (!mem_req) begin
                        mem_addr <= {cache_tag, cache_set, {OFFSET_BITS{1'b0}}};
                        mem_we <= 1'b0;
                        mem_req <= 1'b1;
                    end else if (mem_ack) begin
                        // Fill cache line
                        cache_data[cache_set][victim_way] <= mem_rdata;
                        cache_tags[cache_set][victim_way] <= cache_tag;
                        cache_valid[cache_set][victim_way] <= 1'b1;
                        cache_dirty[cache_set][victim_way] <= 1'b0;
                        mem_req <= 1'b0;
                        
                        // Now serve the original request
                        if (current_we) begin
                            cache_data[cache_set][victim_way] <= update_cache_line(
                                mem_rdata, current_wdata, cache_offset
                            );
                            cache_dirty[cache_set][victim_way] <= 1'b1;
                        end else begin
                            if (is_gpu_req) begin
                                gpu_rdata <= extract_word(mem_rdata, cache_offset);
                            end else begin
                                cpu_rdata <= extract_word(mem_rdata, cache_offset);
                            end
                        end
                        
                        // Update LRU and acknowledge
                        cache_lru[cache_set] <= update_lru(cache_lru[cache_set], victim_way);
                        if (is_gpu_req) gpu_ack <= 1'b1;
                        else cpu_ack <= 1'b1;
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
                if (gpu_req) next_state = GPU_ACCESS;
                else if (cpu_req) next_state = CPU_ACCESS;
            end
            GPU_ACCESS, CPU_ACCESS: begin
                if (cache_hit || (current_state == CACHE_FILL && mem_ack)) begin
                    next_state = IDLE;
                end
            end
            CACHE_WRITEBACK: begin
                if (mem_ack) next_state = CACHE_FILL;
            end
            CACHE_FILL: begin
                if (mem_ack) next_state = IDLE;
            end
        endcase
    end
    
    // Helper functions
    function logic [CACHE_LINE_WIDTH-1:0] update_cache_line;
        input logic [CACHE_LINE_WIDTH-1:0] cache_line;
        input logic [DATA_WIDTH-1:0] new_data;
        input logic [OFFSET_BITS-1:0] offset;
        
        logic [CACHE_LINE_WIDTH-1:0] result;
        int word_offset;
        
        word_offset = offset >> 2; // Convert byte offset to word offset
        result = cache_line;
        result[word_offset*32 +: 32] = new_data;
        return result;
    endfunction
    
    function logic [DATA_WIDTH-1:0] extract_word;
        input logic [CACHE_LINE_WIDTH-1:0] cache_line;
        input logic [OFFSET_BITS-1:0] offset;
        
        int word_offset;
        word_offset = offset >> 2;
        return cache_line[word_offset*32 +: 32];
    endfunction
    
    function logic [1:0] update_lru;
        input logic [1:0] current_lru;
        input logic [1:0] accessed_way;
        
        // Simple LRU update for 4-way associative cache
        case (accessed_way)
            2'b00: return 2'b01;
            2'b01: return 2'b10;
            2'b10: return 2'b11;
            2'b11: return 2'b00;
        endcase
        return current_lru;
    endfunction

endmodule