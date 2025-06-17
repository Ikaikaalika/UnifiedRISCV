// M1-Inspired Cache Hierarchy with 512-bit cache lines
// L1: 32KB 4-way, L2: 256KB 8-way, L3: 2MB 16-way

module cache_hierarchy #(
    parameter L1_SIZE = 32 * 1024,    // 32KB
    parameter L2_SIZE = 256 * 1024,   // 256KB  
    parameter L3_SIZE = 2 * 1024 * 1024, // 2MB
    parameter CACHE_LINE_WIDTH = 512,
    parameter ADDR_WIDTH = 32
) (
    input  logic clk,
    input  logic rst_n,
    
    // CPU/GPU interface
    input  logic [ADDR_WIDTH-1:0] req_addr,
    input  logic [31:0] req_wdata,
    output logic [31:0] req_rdata,
    input  logic req_valid,
    input  logic req_we,
    output logic req_ready,
    input  logic req_is_gpu, // GPU requests have different caching behavior
    
    // External memory interface
    output logic [ADDR_WIDTH-1:0] mem_addr,
    output logic [CACHE_LINE_WIDTH-1:0] mem_wdata,
    input  logic [CACHE_LINE_WIDTH-1:0] mem_rdata,
    output logic mem_req,
    output logic mem_we,
    input  logic mem_ack
);

    // Cache level parameters
    localparam L1_WAYS = 4;
    localparam L2_WAYS = 8;
    localparam L3_WAYS = 16;
    
    localparam LINE_SIZE = CACHE_LINE_WIDTH / 8; // 64 bytes
    localparam OFFSET_BITS = $clog2(LINE_SIZE);
    
    // L1 Cache parameters
    localparam L1_SETS = L1_SIZE / (L1_WAYS * LINE_SIZE);
    localparam L1_SET_BITS = $clog2(L1_SETS);
    localparam L1_TAG_BITS = ADDR_WIDTH - L1_SET_BITS - OFFSET_BITS;
    
    // L2 Cache parameters
    localparam L2_SETS = L2_SIZE / (L2_WAYS * LINE_SIZE);
    localparam L2_SET_BITS = $clog2(L2_SETS);
    localparam L2_TAG_BITS = ADDR_WIDTH - L2_SET_BITS - OFFSET_BITS;
    
    // L3 Cache parameters
    localparam L3_SETS = L3_SIZE / (L3_WAYS * LINE_SIZE);
    localparam L3_SET_BITS = $clog2(L3_SETS);
    localparam L3_TAG_BITS = ADDR_WIDTH - L3_SET_BITS - OFFSET_BITS;
    
    // Address breakdown
    logic [L1_SET_BITS-1:0] l1_set;
    logic [L1_TAG_BITS-1:0] l1_tag;
    logic [OFFSET_BITS-1:0] offset;
    
    assign l1_set = req_addr[L1_SET_BITS+OFFSET_BITS-1:OFFSET_BITS];
    assign l1_tag = req_addr[ADDR_WIDTH-1:L1_SET_BITS+OFFSET_BITS];
    assign offset = req_addr[OFFSET_BITS-1:0];
    
    // L1 Cache arrays
    logic [L1_TAG_BITS-1:0] l1_tags [L1_SETS-1:0][L1_WAYS-1:0];
    logic [CACHE_LINE_WIDTH-1:0] l1_data [L1_SETS-1:0][L1_WAYS-1:0];
    logic l1_valid [L1_SETS-1:0][L1_WAYS-1:0];
    logic l1_dirty [L1_SETS-1:0][L1_WAYS-1:0];
    logic [1:0] l1_lru [L1_SETS-1:0]; // 2-bit LRU for 4-way
    
    // L1 Cache control
    logic l1_hit, l1_miss;
    logic [1:0] l1_hit_way, l1_victim_way;
    
    // Cache state machine
    typedef enum logic [3:0] {
        IDLE,
        L1_LOOKUP,
        L1_HIT_SERVE,
        L1_MISS_L2,
        L2_LOOKUP,
        L2_HIT_FILL,
        L2_MISS_L3,
        L3_LOOKUP,
        L3_HIT_FILL,
        L3_MISS_MEM,
        WRITEBACK,
        FILL_L1
    } cache_state_t;
    
    cache_state_t current_state, next_state;
    
    // Request registers
    logic [ADDR_WIDTH-1:0] current_addr;
    logic [31:0] current_wdata;
    logic current_we;
    logic current_is_gpu;
    
    // L1 Cache hit detection
    always_comb begin
        l1_hit = 1'b0;
        l1_hit_way = 2'b00;
        for (int i = 0; i < L1_WAYS; i++) begin
            if (l1_valid[l1_set][i] && l1_tags[l1_set][i] == l1_tag) begin
                l1_hit = 1'b1;
                l1_hit_way = i[1:0];
                break;
            end
        end
        l1_miss = ~l1_hit;
    end
    
    // L1 Victim selection (LRU)
    assign l1_victim_way = l1_lru[l1_set];
    
    // Main state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            req_ready <= 1'b1;
            mem_req <= 1'b0;
            
            // Initialize L1 cache
            for (int i = 0; i < L1_SETS; i++) begin
                for (int j = 0; j < L1_WAYS; j++) begin
                    l1_valid[i][j] <= 1'b0;
                    l1_dirty[i][j] <= 1'b0;
                    l1_tags[i][j] <= '0;
                    l1_data[i][j] <= '0;
                end
                l1_lru[i] <= 2'b00;
            end
        end else begin
            current_state <= next_state;
            
            case (current_state)
                IDLE: begin
                    req_ready <= 1'b1;
                    if (req_valid) begin
                        current_addr <= req_addr;
                        current_wdata <= req_wdata;
                        current_we <= req_we;
                        current_is_gpu <= req_is_gpu;
                        req_ready <= 1'b0;
                    end
                end
                
                L1_LOOKUP: begin
                    // L1 lookup is combinational, move to next state
                end
                
                L1_HIT_SERVE: begin
                    if (current_we) begin
                        // Write hit
                        l1_data[l1_set][l1_hit_way] <= update_cache_line(
                            l1_data[l1_set][l1_hit_way], 
                            current_wdata, 
                            offset
                        );
                        l1_dirty[l1_set][l1_hit_way] <= 1'b1;
                    end else begin
                        // Read hit
                        req_rdata <= extract_word(l1_data[l1_set][l1_hit_way], offset);
                    end
                    
                    // Update LRU
                    l1_lru[l1_set] <= update_l1_lru(l1_lru[l1_set], l1_hit_way);
                end
                
                L1_MISS_L2: begin
                    // Check if victim line needs writeback
                    if (l1_dirty[l1_set][l1_victim_way] && l1_valid[l1_set][l1_victim_way]) begin
                        next_state <= WRITEBACK;
                    end else begin
                        // Proceed to L2 lookup (simplified - direct to memory for now)
                        next_state <= L3_MISS_MEM;
                    end
                end
                
                WRITEBACK: begin
                    if (!mem_req) begin
                        mem_addr <= {l1_tags[l1_set][l1_victim_way], l1_set, {OFFSET_BITS{1'b0}}};
                        mem_wdata <= l1_data[l1_set][l1_victim_way];
                        mem_we <= 1'b1;
                        mem_req <= 1'b1;
                    end else if (mem_ack) begin
                        mem_req <= 1'b0;
                        l1_dirty[l1_set][l1_victim_way] <= 1'b0;
                        next_state <= L3_MISS_MEM;
                    end
                end
                
                L3_MISS_MEM: begin
                    if (!mem_req) begin
                        mem_addr <= {current_addr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
                        mem_we <= 1'b0;
                        mem_req <= 1'b1;
                    end else if (mem_ack) begin
                        mem_req <= 1'b0;
                        next_state <= FILL_L1;
                    end
                end
                
                FILL_L1: begin
                    // Fill L1 cache line
                    l1_data[l1_set][l1_victim_way] <= mem_rdata;
                    l1_tags[l1_set][l1_victim_way] <= l1_tag;
                    l1_valid[l1_set][l1_victim_way] <= 1'b1;
                    l1_dirty[l1_set][l1_victim_way] <= 1'b0;
                    
                    // Serve the original request
                    if (current_we) begin
                        l1_data[l1_set][l1_victim_way] <= update_cache_line(
                            mem_rdata, current_wdata, offset
                        );
                        l1_dirty[l1_set][l1_victim_way] <= 1'b1;
                    end else begin
                        req_rdata <= extract_word(mem_rdata, offset);
                    end
                    
                    // Update LRU
                    l1_lru[l1_set] <= update_l1_lru(l1_lru[l1_set], l1_victim_way);
                end
            endcase
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (req_valid) next_state = L1_LOOKUP;
            end
            L1_LOOKUP: begin
                if (l1_hit) next_state = L1_HIT_SERVE;
                else next_state = L1_MISS_L2;
            end
            L1_HIT_SERVE: next_state = IDLE;
            L1_MISS_L2: begin
                if (l1_dirty[l1_set][l1_victim_way] && l1_valid[l1_set][l1_victim_way]) 
                    next_state = WRITEBACK;
                else 
                    next_state = L3_MISS_MEM;
            end
            WRITEBACK: begin
                if (mem_ack) next_state = L3_MISS_MEM;
            end
            L3_MISS_MEM: begin
                if (mem_ack) next_state = FILL_L1;
            end
            FILL_L1: next_state = IDLE;
        endcase
    end
    
    // Helper functions
    function logic [CACHE_LINE_WIDTH-1:0] update_cache_line;
        input logic [CACHE_LINE_WIDTH-1:0] cache_line;
        input logic [31:0] new_data;
        input logic [OFFSET_BITS-1:0] byte_offset;
        
        logic [CACHE_LINE_WIDTH-1:0] result;
        int word_offset;
        
        word_offset = byte_offset >> 2;
        result = cache_line;
        result[word_offset*32 +: 32] = new_data;
        return result;
    endfunction
    
    function logic [31:0] extract_word;
        input logic [CACHE_LINE_WIDTH-1:0] cache_line;
        input logic [OFFSET_BITS-1:0] byte_offset;
        
        int word_offset;
        word_offset = byte_offset >> 2;
        return cache_line[word_offset*32 +: 32];
    endfunction
    
    function logic [1:0] update_l1_lru;
        input logic [1:0] current_lru;
        input logic [1:0] accessed_way;
        
        case (accessed_way)
            2'b00: return 2'b01;
            2'b01: return 2'b10; 
            2'b10: return 2'b11;
            2'b11: return 2'b00;
        endcase
        return current_lru;
    endfunction

endmodule