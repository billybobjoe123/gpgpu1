// filepath: l2_cache.sv
//=============================================================================
// GPGPU-1 L2 Cache
//=============================================================================
// Simplified direct-mapped L2 cache for Verilator compatibility

`include "gpgpu_defines.svh"

module l2_cache
    import gpgpu_pkg::*;
#(
    parameter int CACHE_SIZE_KB   = 64,
    parameter int LINE_SIZE_BYTES = 64,
    parameter int NUM_WAYS        = 4,
    parameter int NUM_MSHR        = 8
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Read Address Channel
    input  logic                    req_arvalid,
    output logic                    req_arready,
    input  logic [ADDR_WIDTH-1:0]   req_araddr,
    input  logic [7:0]              req_arlen,
    input  logic [2:0]              req_arsize,
    input  logic [3:0]              req_arid,
    
    // Read Data Channel
    output logic                    req_rvalid,
    input  logic                    req_rready,
    output logic [511:0]            req_rdata,
    output logic [1:0]              req_rresp,
    output logic                    req_rlast,
    output logic [3:0]              req_rid,
    
    // Write Address Channel
    input  logic                    req_awvalid,
    output logic                    req_awready,
    input  logic [ADDR_WIDTH-1:0]   req_awaddr,
    input  logic [7:0]              req_awlen,
    input  logic [2:0]              req_awsize,
    input  logic [3:0]              req_awid,
    
    // Write Data Channel
    input  logic                    req_wvalid,
    output logic                    req_wready,
    input  logic [511:0]            req_wdata,
    input  logic [63:0]             req_wstrb,
    input  logic                    req_wlast,
    
    // Write Response Channel
    output logic                    req_bvalid,
    input  logic                    req_bready,
    output logic [1:0]              req_bresp,
    output logic [3:0]              req_bid,
    
    // Memory Read Address
    output logic                    mem_arvalid,
    input  logic                    mem_arready,
    output logic [ADDR_WIDTH-1:0]   mem_araddr,
    output logic [7:0]              mem_arlen,
    output logic [2:0]              mem_arsize,
    output logic [1:0]              mem_arburst,
    output logic [3:0]              mem_arid,
    
    // Memory Read Data
    input  logic                    mem_rvalid,
    output logic                    mem_rready,
    input  logic [511:0]            mem_rdata,
    input  logic [1:0]              mem_rresp,
    input  logic                    mem_rlast,
    input  logic [3:0]              mem_rid,
    
    // Memory Write Address
    output logic                    mem_awvalid,
    input  logic                    mem_awready,
    output logic [ADDR_WIDTH-1:0]   mem_awaddr,
    output logic [7:0]              mem_awlen,
    output logic [2:0]              mem_awsize,
    output logic [1:0]              mem_awburst,
    output logic [3:0]              mem_awid,
    
    // Memory Write Data
    output logic                    mem_wvalid,
    input  logic                    mem_wready,
    output logic [511:0]            mem_wdata,
    output logic [63:0]             mem_wstrb,
    output logic                    mem_wlast,
    
    // Memory Write Response
    input  logic                    mem_bvalid,
    output logic                    mem_bready,
    input  logic [1:0]              mem_bresp,
    input  logic [3:0]              mem_bid,
    
    output logic [31:0]             perf_hits,
    output logic [31:0]             perf_misses,
    output logic [31:0]             perf_writebacks
);

    localparam int CACHE_SIZE_BYTES = CACHE_SIZE_KB * 1024;
    localparam int NUM_LINES = CACHE_SIZE_BYTES / LINE_SIZE_BYTES;
    localparam int INDEX_BITS = $clog2(NUM_LINES);
    localparam int OFFSET_BITS = $clog2(LINE_SIZE_BYTES);
    localparam int TAG_BITS = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
    localparam int LINE_BITS = LINE_SIZE_BYTES * 8;
    
    // Storage
    logic [NUM_LINES-1:0] valid_array;
    logic [NUM_LINES-1:0] dirty_array;
    logic [NUM_LINES-1:0][TAG_BITS-1:0] tag_array;
    logic [LINE_BITS-1:0] data_array [NUM_LINES];
    
    typedef enum logic [3:0] {
        S_IDLE, S_TAG_CHECK, S_HIT_READ, S_HIT_WRITE,
        S_WRITEBACK_ADDR, S_WRITEBACK_DATA, S_WRITEBACK_RESP,
        S_FILL_ADDR, S_FILL_DATA, S_RESP_READ, S_RESP_WRITE
    } state_t;
    
    state_t state;
    logic req_is_write;
    logic [ADDR_WIDTH-1:0] req_addr;
    logic [3:0] req_id;
    logic [LINE_BITS-1:0] req_wdata_r;
    logic [63:0] req_wstrb_r;
    logic [LINE_BITS-1:0] fill_data;
    
    logic [TAG_BITS-1:0] addr_tag;
    logic [INDEX_BITS-1:0] addr_index;
    
    assign addr_tag = req_addr[ADDR_WIDTH-1 -: TAG_BITS];
    assign addr_index = req_addr[OFFSET_BITS +: INDEX_BITS];
    
    logic line_valid, line_dirty, cache_hit;
    logic [TAG_BITS-1:0] line_tag;
    logic [LINE_BITS-1:0] line_data;
    
    assign line_valid = valid_array[addr_index];
    assign line_dirty = dirty_array[addr_index];
    assign line_tag = tag_array[addr_index];
    assign line_data = data_array[addr_index];
    assign cache_hit = line_valid && (line_tag == addr_tag);
    
    logic [ADDR_WIDTH-1:0] writeback_addr, fill_addr;
    assign writeback_addr = {line_tag, addr_index, {OFFSET_BITS{1'b0}}};
    assign fill_addr = {addr_tag, addr_index, {OFFSET_BITS{1'b0}}};
    
    assign req_arready = (state == S_IDLE);
    assign req_awready = (state == S_IDLE) && !req_arvalid;
    assign req_wready = (state == S_IDLE) && req_awvalid && req_awready;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            req_is_write <= 1'b0;
            req_addr <= '0;
            req_id <= '0;
            req_wdata_r <= '0;
            req_wstrb_r <= '0;
            fill_data <= '0;
            valid_array <= '0;
            dirty_array <= '0;
            tag_array <= '0;
            perf_hits <= '0;
            perf_misses <= '0;
            perf_writebacks <= '0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (req_arvalid && req_arready) begin
                        req_is_write <= 1'b0;
                        req_addr <= req_araddr;
                        req_id <= req_arid;
                        state <= S_TAG_CHECK;
                    end else if (req_awvalid && req_awready && req_wvalid) begin
                        req_is_write <= 1'b1;
                        req_addr <= req_awaddr;
                        req_id <= req_awid;
                        req_wdata_r <= req_wdata;
                        req_wstrb_r <= req_wstrb;
                        state <= S_TAG_CHECK;
                    end
                end
                
                S_TAG_CHECK: begin
                    if (cache_hit) begin
                        perf_hits <= perf_hits + 1;
                        state <= req_is_write ? S_HIT_WRITE : S_HIT_READ;
                    end else begin
                        perf_misses <= perf_misses + 1;
                        if (line_valid && line_dirty) begin
                            perf_writebacks <= perf_writebacks + 1;
                            state <= S_WRITEBACK_ADDR;
                        end else begin
                            state <= S_FILL_ADDR;
                        end
                    end
                end
                
                S_HIT_READ: if (req_rready) state <= S_IDLE;
                
                S_HIT_WRITE: begin
                    for (int b = 0; b < 64; b++) begin
                        if (req_wstrb_r[b])
                            data_array[addr_index][b*8 +: 8] <= req_wdata_r[b*8 +: 8];
                    end
                    dirty_array[addr_index] <= 1'b1;
                    state <= S_RESP_WRITE;
                end
                
                S_RESP_WRITE: if (req_bready) state <= S_IDLE;
                
                S_WRITEBACK_ADDR: if (mem_awready) state <= S_WRITEBACK_DATA;
                S_WRITEBACK_DATA: if (mem_wready) state <= S_WRITEBACK_RESP;
                S_WRITEBACK_RESP: if (mem_bvalid) state <= S_FILL_ADDR;
                S_FILL_ADDR: if (mem_arready) state <= S_FILL_DATA;
                
                S_FILL_DATA: begin
                    if (mem_rvalid && mem_rlast) begin
                        fill_data <= mem_rdata;
                        tag_array[addr_index] <= addr_tag;
                        valid_array[addr_index] <= 1'b1;
                        if (req_is_write) begin
                            for (int b = 0; b < 64; b++) begin
                                if (req_wstrb_r[b])
                                    data_array[addr_index][b*8 +: 8] <= req_wdata_r[b*8 +: 8];
                                else
                                    data_array[addr_index][b*8 +: 8] <= mem_rdata[b*8 +: 8];
                            end
                            dirty_array[addr_index] <= 1'b1;
                            state <= S_RESP_WRITE;
                        end else begin
                            data_array[addr_index] <= mem_rdata;
                            dirty_array[addr_index] <= 1'b0;
                            state <= S_RESP_READ;
                        end
                    end
                end
                
                S_RESP_READ: if (req_rready) state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end
    
    // Memory interface
    assign mem_awvalid = (state == S_WRITEBACK_ADDR);
    assign mem_awaddr = writeback_addr;
    assign mem_awlen = 8'd0;
    assign mem_awsize = 3'b110;
    assign mem_awburst = 2'b01;
    assign mem_awid = req_id;
    
    assign mem_wvalid = (state == S_WRITEBACK_DATA);
    assign mem_wdata = line_data;
    assign mem_wstrb = 64'hFFFFFFFFFFFFFFFF;
    assign mem_wlast = 1'b1;
    
    assign mem_bready = (state == S_WRITEBACK_RESP);
    
    assign mem_arvalid = (state == S_FILL_ADDR);
    assign mem_araddr = fill_addr;
    assign mem_arlen = 8'd0;
    assign mem_arsize = 3'b110;
    assign mem_arburst = 2'b01;
    assign mem_arid = req_id;
    
    assign mem_rready = (state == S_FILL_DATA);
    
    // Response interface
    assign req_rvalid = (state == S_HIT_READ) || (state == S_RESP_READ);
    assign req_rdata = (state == S_RESP_READ) ? fill_data : line_data;
    assign req_rresp = 2'b00;
    assign req_rlast = 1'b1;
    assign req_rid = req_id;
    
    assign req_bvalid = (state == S_RESP_WRITE);
    assign req_bresp = 2'b00;
    assign req_bid = req_id;

endmodule
