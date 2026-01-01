//=============================================================================
// GPGPU-1 Instruction Fetch Unit
//=============================================================================
// File:        fetch_unit.sv
// Description: Fetches instructions for warps from instruction memory/cache.
//              Manages per-warp PCs and interfaces with warp scheduler.
//              Includes instruction cache and fetch buffer.
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`include "gpgpu_defines.svh"

//=============================================================================
// Instruction Cache (Simple Direct-Mapped)
//=============================================================================

module icache
    import gpgpu_pkg::*;
#(
    parameter int CACHE_SIZE    = 4096,         // 4KB cache
    parameter int LINE_SIZE     = 32,           // 32 bytes per line (8 instructions)
    parameter int ADDR_WIDTH    = 64,
    parameter int INST_WIDTH    = 32
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Fetch request interface
    input  logic                    req_valid,
    input  logic [ADDR_WIDTH-1:0]   req_addr,
    output logic                    req_ready,
    
    // Fetch response interface
    output logic                    resp_valid,
    output logic [INST_WIDTH-1:0]   resp_instr,
    output logic                    resp_hit,
    
    // Memory interface (for cache misses)
    output logic                    mem_req_valid,
    output logic [ADDR_WIDTH-1:0]   mem_req_addr,
    input  logic                    mem_req_ready,
    input  logic                    mem_resp_valid,
    input  logic [LINE_SIZE*8-1:0]  mem_resp_data,
    
    // Cache control
    input  logic                    flush,
    output logic                    busy
);

    // Cache parameters
    localparam int NUM_LINES     = CACHE_SIZE / LINE_SIZE;      // 128 lines
    localparam int INDEX_BITS    = $clog2(NUM_LINES);           // 7 bits
    localparam int OFFSET_BITS   = $clog2(LINE_SIZE);           // 5 bits
    localparam int TAG_BITS      = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
    localparam int INSTS_PER_LINE = LINE_SIZE / (INST_WIDTH/8); // 8 instructions
    
    // Cache storage
    logic [TAG_BITS-1:0]       tag_array   [0:NUM_LINES-1];
    logic [NUM_LINES-1:0]      valid_array;  // Use packed array for Verilator compatibility
    logic [LINE_SIZE*8-1:0]    data_array  [0:NUM_LINES-1];
    
    // Address decomposition
    logic [TAG_BITS-1:0]       req_tag;
    logic [INDEX_BITS-1:0]     req_index;
    logic [OFFSET_BITS-1:0]    req_offset;
    logic [2:0]                req_word_sel;  // Which 32-bit word within line
    
    assign req_tag     = req_addr[ADDR_WIDTH-1 : INDEX_BITS+OFFSET_BITS];
    assign req_index   = req_addr[INDEX_BITS+OFFSET_BITS-1 : OFFSET_BITS];
    assign req_offset  = req_addr[OFFSET_BITS-1 : 0];
    assign req_word_sel = req_addr[4:2];  // Bits [4:2] select 32-bit word
    
    // Cache lookup
    logic tag_match;
    logic line_valid;
    logic cache_hit;
    
    assign line_valid = valid_array[req_index];
    assign tag_match  = (tag_array[req_index] == req_tag);
    assign cache_hit  = line_valid && tag_match;
    
    // State machine
    typedef enum logic [2:0] {
        S_IDLE,
        S_LOOKUP,
        S_MISS_REQ,
        S_MISS_WAIT,
        S_REFILL,
        S_FLUSH
    } state_t;
    
    state_t state, next_state;
    
    // Registered request
    logic [ADDR_WIDTH-1:0] req_addr_r;
    logic [TAG_BITS-1:0]   req_tag_r;
    logic [INDEX_BITS-1:0] req_index_r;
    logic [2:0]            req_word_sel_r;
    
    // Captured memory response data
    logic [LINE_SIZE*8-1:0] mem_resp_data_r;
    
    // Flush counter
    logic [INDEX_BITS-1:0] flush_counter;
    
    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            req_addr_r <= '0;
            req_tag_r <= '0;
            req_index_r <= '0;
            req_word_sel_r <= '0;
            flush_counter <= '0;
            mem_resp_data_r <= '0;
            
            // Initialize valid bits (packed array)
            valid_array <= '0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (flush) begin
                        state <= S_FLUSH;
                        flush_counter <= '0;
                    end else if (req_valid) begin
                        req_addr_r <= req_addr;
                        req_tag_r <= req_tag;
                        req_index_r <= req_index;
                        req_word_sel_r <= req_word_sel;
                        state <= S_LOOKUP;
                    end
                end
                
                S_LOOKUP: begin
                    if (cache_hit) begin
                        state <= S_IDLE;
                    end else begin
                        state <= S_MISS_REQ;
                    end
                end
                
                S_MISS_REQ: begin
                    if (mem_req_ready) begin
                        state <= S_MISS_WAIT;
                    end
                end
                
                S_MISS_WAIT: begin
                    if (mem_resp_valid) begin
                        // Capture response data when it's valid
                        mem_resp_data_r <= mem_resp_data;
                        state <= S_REFILL;
                    end
                end
                
                S_REFILL: begin
                    // Write to cache using captured data
                    tag_array[req_index_r] <= req_tag_r;
                    valid_array[req_index_r] <= 1'b1;
                    data_array[req_index_r] <= mem_resp_data_r;
                    state <= S_IDLE;
                end
                
                S_FLUSH: begin
                    valid_array[flush_counter] <= 1'b0;
                    if (flush_counter == NUM_LINES - 1) begin
                        state <= S_IDLE;
                    end else begin
                        flush_counter <= flush_counter + 1;
                    end
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end
    
    // Extract instruction from cache line
    logic [INST_WIDTH-1:0] cached_instr;
    always_comb begin
        cached_instr = data_array[req_index_r][req_word_sel_r*32 +: 32];
    end
    
    // Output logic
    assign req_ready = (state == S_IDLE) && !flush;
    assign resp_valid = (state == S_LOOKUP && cache_hit) || (state == S_REFILL);
    assign resp_instr = (state == S_REFILL) ? mem_resp_data_r[req_word_sel_r*32 +: 32] : cached_instr;
    assign resp_hit = (state == S_LOOKUP) && cache_hit;
    
    assign mem_req_valid = (state == S_MISS_REQ);
    assign mem_req_addr = {req_addr_r[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};  // Line-aligned
    
    assign busy = (state != S_IDLE);

endmodule

//=============================================================================
// Fetch Buffer (Per-Warp Instruction Queue)
//=============================================================================

module fetch_buffer
    import gpgpu_pkg::*;
#(
    parameter int BUFFER_DEPTH = 4,
    parameter int INST_WIDTH   = 32,
    parameter int ADDR_WIDTH   = 64
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Write interface (from cache)
    input  logic                    wr_valid,
    input  logic [INST_WIDTH-1:0]   wr_instr,
    input  logic [ADDR_WIDTH-1:0]   wr_pc,
    output logic                    wr_ready,
    
    // Read interface (to decoder)
    output logic                    rd_valid,
    output logic [INST_WIDTH-1:0]   rd_instr,
    output logic [ADDR_WIDTH-1:0]   rd_pc,
    input  logic                    rd_ready,
    
    // Status
    output logic                    empty,
    output logic                    full,
    
    // Flush (on branch mispredict)
    input  logic                    flush
);

    localparam int PTR_WIDTH = $clog2(BUFFER_DEPTH);
    
    // Buffer storage
    logic [INST_WIDTH-1:0]   instr_buf [0:BUFFER_DEPTH-1];
    logic [ADDR_WIDTH-1:0]   pc_buf    [0:BUFFER_DEPTH-1];
    
    // Pointers
    logic [PTR_WIDTH:0] wr_ptr, rd_ptr;
    logic [PTR_WIDTH:0] count;
    
    assign count = wr_ptr - rd_ptr;
    assign empty = (count == 0);
    assign full  = (count == BUFFER_DEPTH);
    assign wr_ready = !full;
    assign rd_valid = !empty;
    
    // Read data
    assign rd_instr = instr_buf[rd_ptr[PTR_WIDTH-1:0]];
    assign rd_pc    = pc_buf[rd_ptr[PTR_WIDTH-1:0]];
    
    // Write and read logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else if (flush) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin
            // Write
            if (wr_valid && wr_ready) begin
                instr_buf[wr_ptr[PTR_WIDTH-1:0]] <= wr_instr;
                pc_buf[wr_ptr[PTR_WIDTH-1:0]] <= wr_pc;
                wr_ptr <= wr_ptr + 1;
            end
            
            // Read
            if (rd_valid && rd_ready) begin
                rd_ptr <= rd_ptr + 1;
            end
        end
    end

endmodule

//=============================================================================
// Instruction Fetch Unit (Top Level)
//=============================================================================

module fetch_unit
    import gpgpu_pkg::*;
#(
    parameter int NUM_WARPS      = WARPS_PER_CORE,
    parameter int ICACHE_SIZE    = 4096,
    parameter int FETCH_BUF_DEPTH = 2
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Warp scheduler interface
    input  logic                    sched_valid,
    input  logic [WARP_ID_WIDTH-1:0] sched_warp_id,
    input  logic [ADDR_WIDTH-1:0]   sched_pc,
    input  logic [WARP_SIZE-1:0]    sched_active_mask,
    output logic                    sched_ready,
    
    // Decode interface
    output logic                    decode_valid,
    output logic [INST_WIDTH-1:0]   decode_instr,
    output logic [ADDR_WIDTH-1:0]   decode_pc,
    output logic [WARP_ID_WIDTH-1:0] decode_warp_id,
    output logic [WARP_SIZE-1:0]    decode_active_mask,
    input  logic                    decode_ready,
    
    // Instruction memory interface
    output logic                    imem_req_valid,
    output logic [ADDR_WIDTH-1:0]   imem_req_addr,
    input  logic                    imem_req_ready,
    input  logic                    imem_resp_valid,
    input  logic [255:0]            imem_resp_data,  // 32-byte cache line
    
    // Control
    input  logic [NUM_WARPS-1:0]    warp_flush,      // Per-warp flush (branch)
    input  logic                    cache_flush,     // Full cache flush
    
    // PC update interface (from execute stage - for branches)
    input  logic                    pc_update_valid,
    input  logic [WARP_ID_WIDTH-1:0] pc_update_warp_id,
    input  logic [ADDR_WIDTH-1:0]   pc_update_value,
    
    // PC update interface (to scheduler - for PC+4 after fetch)
    output logic                    pc_advance_valid,
    output logic [WARP_ID_WIDTH-1:0] pc_advance_warp_id,
    output logic [ADDR_WIDTH-1:0]   pc_advance_value,
    
    // Status
    output logic                    busy,
    output logic [NUM_WARPS-1:0]    warp_fetch_ready
);

    //=========================================================================
    // Per-Warp State
    //=========================================================================
    
    // Per-warp PCs
    logic [NUM_WARPS-1:0][ADDR_WIDTH-1:0] warp_pc;
    logic [NUM_WARPS-1:0][WARP_SIZE-1:0]  warp_mask;
    logic [NUM_WARPS-1:0]                  warp_active;
    
    // Per-warp fetch buffers (simplified - using shared buffer)
    // In a full implementation, each warp would have its own buffer
    
    //=========================================================================
    // Fetch State Machine
    //=========================================================================
    
    typedef enum logic [2:0] {
        F_IDLE,
        F_CACHE_REQ,
        F_CACHE_WAIT,
        F_BUFFER,
        F_STALL
    } fetch_state_t;
    
    fetch_state_t state, next_state;
    
    // Current fetch context
    logic [WARP_ID_WIDTH-1:0] fetch_warp_id;
    logic [ADDR_WIDTH-1:0]    fetch_pc;
    logic [WARP_SIZE-1:0]     fetch_mask;
    
    // Captured instruction from cache response
    logic [INST_WIDTH-1:0]   captured_instr;
    logic                    captured_valid;
    
    // Instruction cache interface
    logic                    icache_req_valid;
    logic [ADDR_WIDTH-1:0]   icache_req_addr;
    logic                    icache_req_ready;
    logic                    icache_resp_valid;
    logic [INST_WIDTH-1:0]   icache_resp_instr;
    logic                    icache_resp_hit;
    logic                    icache_busy;
    
    //=========================================================================
    // Instruction Cache Instance
    //=========================================================================
    
    icache #(
        .CACHE_SIZE(ICACHE_SIZE),
        .LINE_SIZE(32),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INST_WIDTH(INST_WIDTH)
    ) u_icache (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(icache_req_valid),
        .req_addr(icache_req_addr),
        .req_ready(icache_req_ready),
        .resp_valid(icache_resp_valid),
        .resp_instr(icache_resp_instr),
        .resp_hit(icache_resp_hit),
        .mem_req_valid(imem_req_valid),
        .mem_req_addr(imem_req_addr),
        .mem_req_ready(imem_req_ready),
        .mem_resp_valid(imem_resp_valid),
        .mem_resp_data(imem_resp_data),
        .flush(cache_flush),
        .busy(icache_busy)
    );
    
    //=========================================================================
    // Fetch Buffer (shared, simplified)
    //=========================================================================
    
    logic                    fbuf_wr_valid;
    logic [INST_WIDTH-1:0]   fbuf_wr_instr;
    logic [ADDR_WIDTH-1:0]   fbuf_wr_pc;
    logic                    fbuf_wr_ready;
    logic                    fbuf_rd_valid;
    logic [INST_WIDTH-1:0]   fbuf_rd_instr;
    logic [ADDR_WIDTH-1:0]   fbuf_rd_pc;
    logic                    fbuf_rd_ready;
    logic                    fbuf_empty;
    logic                    fbuf_full;
    logic                    fbuf_flush;
    
    // Warp context for buffered instructions
    logic [WARP_ID_WIDTH-1:0] fbuf_warp_id [0:FETCH_BUF_DEPTH-1];
    logic [WARP_SIZE-1:0]     fbuf_mask    [0:FETCH_BUF_DEPTH-1];
    logic [WARP_ID_WIDTH-1:0] fbuf_rd_warp_id;
    logic [WARP_SIZE-1:0]     fbuf_rd_mask;
    
    // Simplified fetch buffer
    logic [1:0] fbuf_wr_ptr, fbuf_rd_ptr;
    logic [2:0] fbuf_count;
    
    assign fbuf_empty = (fbuf_count == 0);
    assign fbuf_full  = (fbuf_count >= FETCH_BUF_DEPTH);
    assign fbuf_wr_ready = !fbuf_full;
    assign fbuf_rd_valid = !fbuf_empty;
    
    // Buffer storage
    logic [INST_WIDTH-1:0]   fbuf_instr [0:FETCH_BUF_DEPTH-1];
    logic [ADDR_WIDTH-1:0]   fbuf_pc_buf [0:FETCH_BUF_DEPTH-1];
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fbuf_wr_ptr <= '0;
            fbuf_rd_ptr <= '0;
            fbuf_count <= '0;
        end else if (fbuf_flush || (|warp_flush)) begin
            fbuf_wr_ptr <= '0;
            fbuf_rd_ptr <= '0;
            fbuf_count <= '0;
        end else begin
            // Write
            if (fbuf_wr_valid && fbuf_wr_ready) begin
                fbuf_instr[fbuf_wr_ptr[0]] <= fbuf_wr_instr;
                fbuf_pc_buf[fbuf_wr_ptr[0]] <= fbuf_wr_pc;
                fbuf_warp_id[fbuf_wr_ptr[0]] <= fetch_warp_id;
                fbuf_mask[fbuf_wr_ptr[0]] <= fetch_mask;
                fbuf_wr_ptr <= fbuf_wr_ptr + 1;
                fbuf_count <= fbuf_count + 1;
            end
            
            // Read
            if (fbuf_rd_valid && fbuf_rd_ready) begin
                fbuf_rd_ptr <= fbuf_rd_ptr + 1;
                fbuf_count <= fbuf_count - 1;
            end
            
            // Simultaneous read/write
            if (fbuf_wr_valid && fbuf_wr_ready && fbuf_rd_valid && fbuf_rd_ready) begin
                fbuf_count <= fbuf_count;  // No net change
            end
        end
    end
    
    assign fbuf_rd_instr = fbuf_instr[fbuf_rd_ptr[0]];
    assign fbuf_rd_pc = fbuf_pc_buf[fbuf_rd_ptr[0]];
    assign fbuf_rd_warp_id = fbuf_warp_id[fbuf_rd_ptr[0]];
    assign fbuf_rd_mask = fbuf_mask[fbuf_rd_ptr[0]];
    
    //=========================================================================
    // Warp PC Management
    //=========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int w = 0; w < NUM_WARPS; w++) begin
                warp_pc[w] <= '0;
                warp_mask[w] <= '0;
                warp_active[w] <= 1'b0;
            end
        end else begin
            // PC update from execute stage (branch taken)
            if (pc_update_valid) begin
                warp_pc[pc_update_warp_id] <= pc_update_value;
            end
            
            // Update from scheduler (warp activation)
            if (sched_valid && sched_ready) begin
                warp_pc[sched_warp_id] <= sched_pc;
                warp_mask[sched_warp_id] <= sched_active_mask;
                warp_active[sched_warp_id] <= 1'b1;
            end
            
            // Increment PC after successful fetch
            if (icache_resp_valid && !warp_flush[fetch_warp_id]) begin
                warp_pc[fetch_warp_id] <= warp_pc[fetch_warp_id] + 4;
            end
        end
    end
    
    //=========================================================================
    // Fetch State Machine
    //=========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= F_IDLE;
            fetch_warp_id <= '0;
            fetch_pc <= '0;
            fetch_mask <= '0;
            captured_instr <= '0;
            captured_valid <= 1'b0;
        end else begin
            case (state)
                F_IDLE: begin
                    captured_valid <= 1'b0;
                    if (sched_valid && !fbuf_full && !icache_busy) begin
                        fetch_warp_id <= sched_warp_id;
                        fetch_pc <= sched_pc;
                        fetch_mask <= sched_active_mask;
                        state <= F_CACHE_REQ;
                    end
                end
                
                F_CACHE_REQ: begin
                    if (warp_flush[fetch_warp_id]) begin
                        state <= F_IDLE;
                    end else if (icache_req_ready) begin
                        state <= F_CACHE_WAIT;
                    end
                end
                
                F_CACHE_WAIT: begin
                    if (warp_flush[fetch_warp_id]) begin
                        state <= F_IDLE;
                    end else if (icache_resp_valid) begin
                        // Capture the instruction when it's valid
                        captured_instr <= icache_resp_instr;
                        captured_valid <= 1'b1;
                        state <= F_BUFFER;
                    end
                end
                
                F_BUFFER: begin
                    if (fbuf_wr_ready) begin
                        captured_valid <= 1'b0;
                        state <= F_IDLE;
                    end else begin
                        state <= F_STALL;
                    end
                end
                
                F_STALL: begin
                    if (fbuf_wr_ready) begin
                        captured_valid <= 1'b0;
                        state <= F_IDLE;
                    end
                end
                
                default: state <= F_IDLE;
            endcase
        end
    end
    
    //=========================================================================
    // Output Logic
    //=========================================================================
    
    // Cache request
    assign icache_req_valid = (state == F_CACHE_REQ);
    assign icache_req_addr = fetch_pc;
    
    // Buffer write - use captured instruction
    assign fbuf_wr_valid = (state == F_BUFFER || state == F_STALL) && captured_valid;
    assign fbuf_wr_instr = captured_instr;
    assign fbuf_wr_pc = fetch_pc;
    assign fbuf_flush = cache_flush;
    
    // Scheduler interface
    assign sched_ready = (state == F_IDLE) && !fbuf_full && !icache_busy;
    
    // Decode interface
    assign decode_valid = fbuf_rd_valid;
    assign decode_instr = fbuf_rd_instr;
    assign decode_pc = fbuf_rd_pc;
    assign decode_warp_id = fbuf_rd_warp_id;
    assign decode_active_mask = fbuf_rd_mask;
    assign fbuf_rd_ready = decode_ready;
    
    // Status
    assign busy = (state != F_IDLE) || icache_busy;
    
    // Per-warp fetch ready
    always_comb begin
        for (int w = 0; w < NUM_WARPS; w++) begin
            warp_fetch_ready[w] = warp_active[w] && !warp_flush[w];
        end
    end
    
    // PC advance output - notify scheduler when instruction enters decode
    // This advances the scheduler's PC to PC+4 for the next fetch
    assign pc_advance_valid   = fbuf_rd_valid && fbuf_rd_ready && !warp_flush[fbuf_rd_warp_id];
    assign pc_advance_warp_id = fbuf_rd_warp_id;
    assign pc_advance_value   = fbuf_rd_pc + 4;

endmodule
