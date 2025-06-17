// Priority Arbiter for UnifiedRISCV Interconnect
// Implements GPU-priority round-robin arbitration

module priority_arbiter #(
    parameter NUM_REQUESTERS = 9,
    parameter GPU_PRIORITY = 1
) (
    input  logic clk,
    input  logic rst_n,
    
    input  logic [NUM_REQUESTERS-1:0] requests,
    output logic [NUM_REQUESTERS-1:0] grants,
    output logic [$clog2(NUM_REQUESTERS)-1:0] granted_id,
    output logic any_grant
);

    // Assuming requester 0 is CPU, 1-8 are GPU units
    localparam CPU_ID = 0;
    localparam NUM_GPU_UNITS = NUM_REQUESTERS - 1;
    
    // Round-robin state
    logic [$clog2(NUM_REQUESTERS)-1:0] rr_pointer;
    logic [$clog2(NUM_REQUESTERS)-1:0] next_rr_pointer;
    
    // Priority logic
    logic [NUM_REQUESTERS-1:0] masked_requests;
    logic [NUM_REQUESTERS-1:0] unmasked_requests;
    logic use_unmasked;
    
    // GPU priority grouping
    logic gpu_has_request;
    logic cpu_has_request;
    
    assign cpu_has_request = requests[CPU_ID];
    assign gpu_has_request = |requests[NUM_REQUESTERS-1:1]; // GPU units 1-8
    
    // Generate round-robin mask
    logic [NUM_REQUESTERS-1:0] rr_mask;
    always_comb begin
        rr_mask = '0;
        for (int i = 0; i < NUM_REQUESTERS; i++) begin
            if (i >= rr_pointer) begin
                rr_mask[i] = 1'b1;
            end
        end
    end
    
    // Apply mask to requests
    assign masked_requests = requests & rr_mask;
    assign unmasked_requests = requests;
    assign use_unmasked = (masked_requests == '0) && (requests != '0);
    
    // Grant generation with GPU priority
    always_comb begin
        grants = '0;
        granted_id = '0;
        any_grant = 1'b0;
        
        if (GPU_PRIORITY && gpu_has_request) begin
            // GPU units have priority - round-robin among GPU units only
            logic [NUM_REQUESTERS-1:0] gpu_requests;
            logic [NUM_REQUESTERS-1:0] gpu_masked;
            logic [NUM_REQUESTERS-1:0] gpu_final;
            
            // Extract GPU requests (exclude CPU)
            gpu_requests = requests & ~(1 << CPU_ID);
            gpu_masked = gpu_requests & rr_mask;
            gpu_final = (gpu_masked != '0) ? gpu_masked : gpu_requests;
            
            // Find first GPU requester
            for (int i = 1; i < NUM_REQUESTERS; i++) begin // Start from 1 (first GPU)
                if (gpu_final[i] && !any_grant) begin
                    grants[i] = 1'b1;
                    granted_id = i;
                    any_grant = 1'b1;
                end
            end
        end else if (cpu_has_request && !gpu_has_request) begin
            // Only CPU requesting
            grants[CPU_ID] = 1'b1;
            granted_id = CPU_ID;
            any_grant = 1'b1;
        end else begin
            // Fallback: standard round-robin
            logic [NUM_REQUESTERS-1:0] final_requests;
            final_requests = use_unmasked ? unmasked_requests : masked_requests;
            
            for (int i = 0; i < NUM_REQUESTERS; i++) begin
                if (final_requests[i] && !any_grant) begin
                    grants[i] = 1'b1;
                    granted_id = i;
                    any_grant = 1'b1;
                end
            end
        end
    end
    
    // Update round-robin pointer
    always_comb begin
        if (any_grant) begin
            next_rr_pointer = (granted_id + 1) % NUM_REQUESTERS;
        end else begin
            next_rr_pointer = rr_pointer;
        end
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_pointer <= '0;
        end else begin
            rr_pointer <= next_rr_pointer;
        end
    end

endmodule
