// AXI4-Lite Bridge for UnifiedRISCV
// Converts internal protocol to standard AXI4-Lite for external connectivity

module axi_bridge #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  logic clk,
    input  logic rst_n,
    
    // Internal protocol (from interconnect)
    input  logic internal_req,
    input  logic internal_we,
    input  logic [ADDR_WIDTH-1:0] internal_addr,
    input  logic [DATA_WIDTH-1:0] internal_wdata,
    output logic internal_ack,
    output logic [DATA_WIDTH-1:0] internal_rdata,
    
    // AXI4-Lite Master interface
    // Write Address Channel
    output logic [ADDR_WIDTH-1:0] axi_awaddr,
    output logic [2:0] axi_awprot,
    output logic axi_awvalid,
    input  logic axi_awready,
    
    // Write Data Channel
    output logic [DATA_WIDTH-1:0] axi_wdata,
    output logic [(DATA_WIDTH/8)-1:0] axi_wstrb,
    output logic axi_wvalid,
    input  logic axi_wready,
    
    // Write Response Channel
    input  logic [1:0] axi_bresp,
    input  logic axi_bvalid,
    output logic axi_bready,
    
    // Read Address Channel
    output logic [ADDR_WIDTH-1:0] axi_araddr,
    output logic [2:0] axi_arprot,
    output logic axi_arvalid,
    input  logic axi_arready,
    
    // Read Data Channel
    input  logic [DATA_WIDTH-1:0] axi_rdata,
    input  logic [1:0] axi_rresp,
    input  logic axi_rvalid,
    output logic axi_rready
);

    // State machine for protocol conversion
    typedef enum logic [2:0] {
        IDLE,
        WRITE_ADDR,
        WRITE_DATA,
        WRITE_RESP,
        READ_ADDR,
        READ_DATA
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal registers
    logic [ADDR_WIDTH-1:0] addr_reg;
    logic [DATA_WIDTH-1:0] wdata_reg;
    logic we_reg;
    
    // AXI signal assignments
    assign axi_awaddr = addr_reg;
    assign axi_awprot = 3'b000; // Normal access
    assign axi_wdata = wdata_reg;
    assign axi_wstrb = {(DATA_WIDTH/8){1'b1}}; // All bytes valid
    assign axi_araddr = addr_reg;
    assign axi_arprot = 3'b000; // Normal access
    
    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            addr_reg <= '0;
            wdata_reg <= '0;
            we_reg <= 1'b0;
        end else begin
            current_state <= next_state;
            
            if (current_state == IDLE && internal_req) begin
                addr_reg <= internal_addr;
                wdata_reg <= internal_wdata;
                we_reg <= internal_we;
            end
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (internal_req) begin
                    if (internal_we) begin
                        next_state = WRITE_ADDR;
                    end else begin
                        next_state = READ_ADDR;
                    end
                end
            end
            
            WRITE_ADDR: begin
                if (axi_awready) begin
                    next_state = WRITE_DATA;
                end
            end
            
            WRITE_DATA: begin
                if (axi_wready) begin
                    next_state = WRITE_RESP;
                end
            end
            
            WRITE_RESP: begin
                if (axi_bvalid) begin
                    next_state = IDLE;
                end
            end
            
            READ_ADDR: begin
                if (axi_arready) begin
                    next_state = READ_DATA;
                end
            end
            
            READ_DATA: begin
                if (axi_rvalid) begin
                    next_state = IDLE;
                end
            end
        endcase
    end
    
    // Output logic
    always_comb begin
        // Default values
        axi_awvalid = 1'b0;
        axi_wvalid = 1'b0;
        axi_bready = 1'b0;
        axi_arvalid = 1'b0;
        axi_rready = 1'b0;
        internal_ack = 1'b0;
        internal_rdata = '0;
        
        case (current_state)
            WRITE_ADDR: begin
                axi_awvalid = 1'b1;
            end
            
            WRITE_DATA: begin
                axi_wvalid = 1'b1;
            end
            
            WRITE_RESP: begin
                axi_bready = 1'b1;
                if (axi_bvalid) begin
                    internal_ack = 1'b1;
                end
            end
            
            READ_ADDR: begin
                axi_arvalid = 1'b1;
            end
            
            READ_DATA: begin
                axi_rready = 1'b1;
                if (axi_rvalid) begin
                    internal_ack = 1'b1;
                    internal_rdata = axi_rdata;
                end
            end
        endcase
    end

endmodule
