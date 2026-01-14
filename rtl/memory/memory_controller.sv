//=============================================================================
// GPGPU-1 Memory Controller
//=============================================================================
// File:        memory_controller.sv
// Description: Memory controller with:
//              - Request scheduling (FR-FCFS: First-Ready First-Come First-Served)
//              - Bank interleaving
//              - Read/Write reordering
//              - Refresh scheduling (for DRAM)
//              - Request coalescing
// Version:     1.0
// Date:        December 21, 2025
//=============================================================================

`default_nettype none

`include "gpgpu_defines.svh"

module memory_controller
    import gpgpu_pkg::*;
#(
    parameter int P_NUM_CHANNELS     = 2,         // Memory channels
    parameter int P_NUM_BANKS        = 8,         // Banks per channel
    parameter int P_NUM_ROWS         = 16384,     // Rows per bank
    parameter int P_ROW_BUFFER_SIZE  = 8192,      // Row buffer size in bytes
    parameter int P_DATA_WIDTH       = 512,       // Data bus width
    parameter int P_QUEUE_DEPTH      = 16,        // Request queue depth
    
    // Timing parameters (in cycles)
    parameter int T_RCD            = 14,        // RAS to CAS delay
    parameter int T_RP             = 14,        // Row precharge time
    parameter int T_RAS            = 35,        // Row active time
    parameter int T_CL             = 14,        // CAS latency
    parameter int T_WR             = 16,        // Write recovery time
    parameter int T_RFC            = 350,       // Refresh cycle time
    parameter int REFRESH_INTERVAL = 7800       // Refresh interval (cycles)
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    //=========================================================================
    // Request Interface (from L2 Cache)
    //=========================================================================
    
    // Read Address Channel
    input  logic                    req_arvalid,
    output logic                    req_arready,
    input  logic [ADDR_WIDTH-1:0]   req_araddr,
    input  logic [7:0]              req_arlen,
    input  logic [2:0]              req_arsize,
    input  logic [1:0]              req_arburst,
    input  logic [3:0]              req_arid,
    
    // Read Data Channel
    output logic                    req_rvalid,
    input  logic                    req_rready,
    output logic [P_DATA_WIDTH-1:0]   req_rdata,
    output logic [1:0]              req_rresp,
    output logic                    req_rlast,
    output logic [3:0]              req_rid,
    
    // Write Address Channel
    input  logic                    req_awvalid,
    output logic                    req_awready,
    input  logic [ADDR_WIDTH-1:0]   req_awaddr,
    input  logic [7:0]              req_awlen,
    input  logic [2:0]              req_awsize,
    input  logic [1:0]              req_awburst,
    input  logic [3:0]              req_awid,
    
    // Write Data Channel
    input  logic                    req_wvalid,
    output logic                    req_wready,
    input  logic [P_DATA_WIDTH-1:0]   req_wdata,
    input  logic [63:0]             req_wstrb,
    input  logic                    req_wlast,
    
    // Write Response Channel
    output logic                    req_bvalid,
    input  logic                    req_bready,
    output logic [1:0]              req_bresp,
    output logic [3:0]              req_bid,
    
    //=========================================================================
    // External Memory Interface (simplified DDR-like)
    //=========================================================================
    
    output logic [P_NUM_CHANNELS-1:0]                  ddr_cs_n,    // Chip select
    output logic [P_NUM_CHANNELS-1:0]                  ddr_ras_n,   // Row address strobe
    output logic [P_NUM_CHANNELS-1:0]                  ddr_cas_n,   // Column address strobe
    output logic [P_NUM_CHANNELS-1:0]                  ddr_we_n,    // Write enable
    output logic [P_NUM_CHANNELS-1:0][$clog2(P_NUM_BANKS)-1:0] ddr_ba,     // Bank address
    output logic [P_NUM_CHANNELS-1:0][$clog2(P_NUM_ROWS)-1:0]  ddr_addr,   // Row/Column address
    output logic [P_NUM_CHANNELS-1:0][P_DATA_WIDTH-1:0]  ddr_wdata,   // Write data
    input  logic [P_NUM_CHANNELS-1:0][P_DATA_WIDTH-1:0]  ddr_rdata,   // Read data
    input  logic [P_NUM_CHANNELS-1:0]                  ddr_rdata_valid,
    
    //=========================================================================
    // Status/Performance
    //=========================================================================
    
    output logic [31:0]             perf_read_count,
    output logic [31:0]             perf_write_count,
    output logic [31:0]             perf_row_hits,
    output logic [31:0]             perf_row_misses
);

    //=========================================================================
    // Address Mapping
    //=========================================================================
    
    localparam int CHANNEL_BITS = $clog2(P_NUM_CHANNELS);
    localparam int BANK_BITS    = $clog2(P_NUM_BANKS);
    localparam int ROW_BITS     = $clog2(P_NUM_ROWS);
    localparam int COL_BITS     = $clog2(P_ROW_BUFFER_SIZE / (P_DATA_WIDTH/8));
    localparam int OFFSET_BITS  = $clog2(P_DATA_WIDTH/8);
    
    // Address breakdown: | Tag | Row | Bank | Channel | Column | Offset |
    function automatic logic [CHANNEL_BITS-1:0] get_channel(input logic [ADDR_WIDTH-1:0] addr);
        return addr[OFFSET_BITS + COL_BITS +: CHANNEL_BITS];
    endfunction
    
    function automatic logic [BANK_BITS-1:0] get_bank(input logic [ADDR_WIDTH-1:0] addr);
        return addr[OFFSET_BITS + COL_BITS + CHANNEL_BITS +: BANK_BITS];
    endfunction
    
    function automatic logic [ROW_BITS-1:0] get_row(input logic [ADDR_WIDTH-1:0] addr);
        return addr[OFFSET_BITS + COL_BITS + CHANNEL_BITS + BANK_BITS +: ROW_BITS];
    endfunction
    
    function automatic logic [COL_BITS-1:0] get_col(input logic [ADDR_WIDTH-1:0] addr);
        return addr[OFFSET_BITS +: COL_BITS];
    endfunction
    
    //=========================================================================
    // Request Queue Entry
    //=========================================================================
    
    typedef struct packed {
        logic                     valid;
        logic                     is_write;
        logic [ADDR_WIDTH-1:0]    addr;
        logic [3:0]               req_id;
        logic [7:0]               len;
        logic [P_DATA_WIDTH-1:0]    wdata;
        logic [63:0]              wstrb;
        logic [CHANNEL_BITS-1:0]  channel;
        logic [BANK_BITS-1:0]     bank;
        logic [ROW_BITS-1:0]      row;
        logic [COL_BITS-1:0]      col;
        logic                     row_hit;      // Pre-computed row hit status
        logic [15:0]              age;          // For aging/priority
    } req_entry_t;
    
    req_entry_t req_queue [P_QUEUE_DEPTH];
    
    logic [$clog2(P_QUEUE_DEPTH)-1:0] queue_head;
    logic [$clog2(P_QUEUE_DEPTH)-1:0] queue_tail;
    logic [$clog2(P_QUEUE_DEPTH):0]   queue_count;
    logic                           queue_full;
    logic                           queue_empty;
    
    assign queue_full  = (queue_count == P_QUEUE_DEPTH);
    assign queue_empty = (queue_count == 0);
    
    //=========================================================================
    // Bank State Tracking
    //=========================================================================
    
    typedef enum logic [2:0] {
        BANK_IDLE,
        BANK_ACTIVATING,
        BANK_ACTIVE,
        BANK_READING,
        BANK_WRITING,
        BANK_PRECHARGING,
        BANK_REFRESHING
    } bank_state_t;
    
    // Per-bank state
    bank_state_t                  bank_state   [P_NUM_CHANNELS][P_NUM_BANKS];
    logic [ROW_BITS-1:0]          open_row     [P_NUM_CHANNELS][P_NUM_BANKS];
    logic [15:0]                  bank_timer   [P_NUM_CHANNELS][P_NUM_BANKS];  // Timing countdown
    
    // Refresh control
    logic [15:0]                  refresh_counter;
    logic [P_NUM_CHANNELS-1:0]      refresh_pending;
    logic [$clog2(P_NUM_BANKS)-1:0] refresh_bank;
    
    //=========================================================================
    // Request Acceptance
    //=========================================================================
    
    assign req_arready = !queue_full;
    assign req_awready = !queue_full && !req_arvalid;  // Read priority
    assign req_wready  = req_awvalid && req_awready;    // Accept write data with address
    
    // Queue incoming requests
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            queue_head  <= '0;
            queue_tail  <= '0;
            queue_count <= '0;
            for (int i = 0; i < P_QUEUE_DEPTH; i++) begin
                req_queue[i].valid <= 1'b0;
            end
        end else begin
            // Enqueue new requests
            if (req_arvalid && req_arready) begin
                req_queue[queue_tail].valid    <= 1'b1;
                req_queue[queue_tail].is_write <= 1'b0;
                req_queue[queue_tail].addr     <= req_araddr;
                req_queue[queue_tail].req_id   <= req_arid;
                req_queue[queue_tail].len      <= req_arlen;
                req_queue[queue_tail].wdata    <= '0;
                req_queue[queue_tail].wstrb    <= '0;
                req_queue[queue_tail].channel  <= get_channel(req_araddr);
                req_queue[queue_tail].bank     <= get_bank(req_araddr);
                req_queue[queue_tail].row      <= get_row(req_araddr);
                req_queue[queue_tail].col      <= get_col(req_araddr);
                req_queue[queue_tail].age      <= '0;
                queue_tail  <= queue_tail + 1;
                queue_count <= queue_count + 1;
            end else if (req_awvalid && req_awready && req_wvalid) begin
                req_queue[queue_tail].valid    <= 1'b1;
                req_queue[queue_tail].is_write <= 1'b1;
                req_queue[queue_tail].addr     <= req_awaddr;
                req_queue[queue_tail].req_id   <= req_awid;
                req_queue[queue_tail].len      <= req_awlen;
                req_queue[queue_tail].wdata    <= req_wdata;
                req_queue[queue_tail].wstrb    <= req_wstrb;
                req_queue[queue_tail].channel  <= get_channel(req_awaddr);
                req_queue[queue_tail].bank     <= get_bank(req_awaddr);
                req_queue[queue_tail].row      <= get_row(req_awaddr);
                req_queue[queue_tail].col      <= get_col(req_awaddr);
                req_queue[queue_tail].age      <= '0;
                queue_tail  <= queue_tail + 1;
                queue_count <= queue_count + 1;
            end
            
            // Age all entries
            for (int i = 0; i < P_QUEUE_DEPTH; i++) begin
                if (req_queue[i].valid && req_queue[i].age < 16'hFFFF) begin
                    req_queue[i].age <= req_queue[i].age + 1;
                end
            end
        end
    end
    
    //=========================================================================
    // Request Scheduler (FR-FCFS)
    //=========================================================================
    // First-Ready First-Come First-Served:
    // 1. Prioritize requests to open rows (row hits)
    // 2. Among row hits, use FCFS ordering
    // 3. If no row hits, select oldest request
    
    logic [$clog2(P_QUEUE_DEPTH)-1:0] selected_req;
    logic                           req_selected;
    logic                           selected_is_row_hit;
    
    always_comb begin
        selected_req       = '0;
        req_selected       = 1'b0;
        selected_is_row_hit = 1'b0;
        
        // Check each entry in queue for schedulability
        // First pass: find oldest row hit
        for (int i = 0; i < P_QUEUE_DEPTH; i++) begin
            if (req_queue[i].valid) begin
                automatic logic [CHANNEL_BITS-1:0] ch  = req_queue[i].channel;
                automatic logic [BANK_BITS-1:0]    bnk = req_queue[i].bank;
                automatic logic [ROW_BITS-1:0]     rw  = req_queue[i].row;
                
                // Check if bank is ready and row is open
                if (bank_state[ch][bnk] == BANK_ACTIVE && 
                    open_row[ch][bnk] == rw &&
                    bank_timer[ch][bnk] == 0) begin
                    // Row hit!
                    if (!req_selected || !selected_is_row_hit || 
                        req_queue[i].age > req_queue[selected_req].age) begin
                        selected_req = i[$clog2(P_QUEUE_DEPTH)-1:0];
                        req_selected = 1'b1;
                        selected_is_row_hit = 1'b1;
                    end
                end
            end
        end
        
        // Second pass: if no row hit, find oldest that can be scheduled
        if (!selected_is_row_hit) begin
            for (int i = 0; i < P_QUEUE_DEPTH; i++) begin
                if (req_queue[i].valid) begin
                    automatic logic [CHANNEL_BITS-1:0] ch  = req_queue[i].channel;
                    automatic logic [BANK_BITS-1:0]    bnk = req_queue[i].bank;
                    
                    // Check if bank can accept a new command
                    if ((bank_state[ch][bnk] == BANK_IDLE || 
                         bank_state[ch][bnk] == BANK_ACTIVE) &&
                        bank_timer[ch][bnk] == 0 &&
                        !refresh_pending[ch]) begin
                        if (!req_selected || req_queue[i].age > req_queue[selected_req].age) begin
                            selected_req = i[$clog2(P_QUEUE_DEPTH)-1:0];
                            req_selected = 1'b1;
                        end
                    end
                end
            end
        end
    end
    
    //=========================================================================
    // Bank State Machine
    //=========================================================================
    
    // Command to issue
    typedef enum logic [2:0] {
        CMD_NOP,
        CMD_ACTIVATE,
        CMD_READ,
        CMD_WRITE,
        CMD_PRECHARGE,
        CMD_REFRESH
    } mem_cmd_t;
    
    mem_cmd_t                     pending_cmd  [P_NUM_CHANNELS];
    logic [BANK_BITS-1:0]         pending_bank [P_NUM_CHANNELS];
    logic [ROW_BITS-1:0]          pending_row  [P_NUM_CHANNELS];
    logic [COL_BITS-1:0]          pending_col  [P_NUM_CHANNELS];
    logic [P_DATA_WIDTH-1:0]        pending_wdata[P_NUM_CHANNELS];
    logic [3:0]                   pending_id   [P_NUM_CHANNELS];
    
    // Read response tracking
    typedef struct packed {
        logic                     valid;
        logic [3:0]               req_id;
        logic [7:0]               beats_remaining;
    } pending_read_t;
    
    pending_read_t pending_reads [P_NUM_CHANNELS];
    
    bank_state_t next_bank_state [P_NUM_CHANNELS][P_NUM_BANKS];

    // FSM State Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int ch = 0; ch < P_NUM_CHANNELS; ch++) begin
                for (int bnk = 0; bnk < P_NUM_BANKS; bnk++) begin
                    bank_state[ch][bnk] <= BANK_IDLE;
                end
            end
        end else begin
            for (int ch = 0; ch < P_NUM_CHANNELS; ch++) begin
                for (int bnk = 0; bnk < P_NUM_BANKS; bnk++) begin
                    bank_state[ch][bnk] <= next_bank_state[ch][bnk];
                end
            end
        end
    end

    // Next State Logic
    always_comb begin
        logic [CHANNEL_BITS-1:0] ch_idx;
        logic [BANK_BITS-1:0]    bnk_idx;
        logic [ROW_BITS-1:0]     row_idx;

        for (int ch = 0; ch < P_NUM_CHANNELS; ch++) begin
            for (int bnk = 0; bnk < P_NUM_BANKS; bnk++) begin
                next_bank_state[ch][bnk] = bank_state[ch][bnk];
            end
        end

        if (req_selected && !refresh_pending[req_queue[selected_req].channel]) begin
            ch_idx  = req_queue[selected_req].channel;
            bnk_idx = req_queue[selected_req].bank;
            row_idx = req_queue[selected_req].row;
            
            case (bank_state[ch_idx][bnk_idx])
                BANK_IDLE: begin
                    next_bank_state[ch_idx][bnk_idx] = BANK_ACTIVATING;
                end
                BANK_ACTIVE: begin
                    if (open_row[ch_idx][bnk_idx] == row_idx) begin
                        if (req_queue[selected_req].is_write) begin
                            next_bank_state[ch_idx][bnk_idx] = BANK_WRITING;
                        end else begin
                            next_bank_state[ch_idx][bnk_idx] = BANK_READING;
                        end
                    end else begin
                        next_bank_state[ch_idx][bnk_idx] = BANK_PRECHARGING;
                    end
                end
                default: ;
            endcase
        end else begin
            ch_idx  = '0;
            bnk_idx = '0;
            row_idx = '0;
        end

        for (int ch = 0; ch < P_NUM_CHANNELS; ch++) begin
            for (int bnk = 0; bnk < P_NUM_BANKS; bnk++) begin
                case (bank_state[ch][bnk])
                    BANK_ACTIVATING, BANK_READING, BANK_WRITING: begin
                        if (bank_timer[ch][bnk] == 0) next_bank_state[ch][bnk] = BANK_ACTIVE;
                    end
                    BANK_PRECHARGING: begin
                        if (bank_timer[ch][bnk] == 0) next_bank_state[ch][bnk] = BANK_IDLE;
                    end
                    BANK_REFRESHING: begin
                        if (bank_timer[ch][bnk] == 0) next_bank_state[ch][bnk] = BANK_IDLE;
                    end
                    default: ;
                endcase
            end

            if (refresh_pending[ch]) begin
                automatic logic all_idle = 1'b1;
                for (int bnk = 0; bnk < P_NUM_BANKS; bnk++) begin
                    if (bank_state[ch][bnk] != BANK_IDLE) all_idle = 1'b0;
                end
                if (all_idle) begin
                    for (int bnk = 0; bnk < P_NUM_BANKS; bnk++) begin
                        next_bank_state[ch][bnk] = BANK_REFRESHING;
                    end
                end
            end
        end
    end

    // Sequential Logic and Outputs
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int ch = 0; ch < P_NUM_CHANNELS; ch++) begin
                for (int bnk = 0; bnk < P_NUM_BANKS; bnk++) begin
                    open_row[ch][bnk]   <= '0;
                    bank_timer[ch][bnk] <= '0;
                end
                pending_cmd[ch]   <= CMD_NOP;
                pending_reads[ch] <= '0;
                refresh_pending[ch] <= 1'b0;
            end
            refresh_counter <= '0;
            refresh_bank    <= '0;
            perf_read_count  <= '0;
            perf_write_count <= '0;
            perf_row_hits    <= '0;
            perf_row_misses  <= '0;
        end else begin
            // Decrement timers
            for (int ch = 0; ch < P_NUM_CHANNELS; ch++) begin
                for (int bnk = 0; bnk < P_NUM_BANKS; bnk++) begin
                    if (bank_timer[ch][bnk] > 0) bank_timer[ch][bnk] <= bank_timer[ch][bnk] - 1;
                end
                pending_cmd[ch] <= CMD_NOP;
            end
            
            // Refresh
            if (refresh_counter >= REFRESH_INTERVAL) begin
                refresh_counter <= '0;
                for (int ch = 0; ch < P_NUM_CHANNELS; ch++) refresh_pending[ch] <= 1'b1;
            end else refresh_counter <= refresh_counter + 1;

            if (req_selected && !refresh_pending[req_queue[selected_req].channel]) begin
                automatic logic [CHANNEL_BITS-1:0] ch  = req_queue[selected_req].channel;
                automatic logic [BANK_BITS-1:0]    bnk = req_queue[selected_req].bank;
                automatic logic [ROW_BITS-1:0]     row = req_queue[selected_req].row;
                automatic logic [COL_BITS-1:0]     col = req_queue[selected_req].col;
                
                case (bank_state[ch][bnk])
                    BANK_IDLE: begin
                        pending_cmd[ch] <= CMD_ACTIVATE; pending_bank[ch] <= bnk; pending_row[ch] <= row;
                        bank_timer[ch][bnk] <= T_RCD; open_row[ch][bnk] <= row; perf_row_misses <= perf_row_misses + 1;
                    end
                    BANK_ACTIVE: begin
                        if (open_row[ch][bnk] == row) begin
                            if (req_queue[selected_req].is_write) begin
                                pending_cmd[ch] <= CMD_WRITE; pending_wdata[ch] <= req_queue[selected_req].wdata;
                                bank_timer[ch][bnk] <= T_WR; perf_write_count <= perf_write_count + 1;
                            end else begin
                                pending_cmd[ch] <= CMD_READ; pending_reads[ch].valid <= 1'b1;
                                pending_reads[ch].req_id <= req_queue[selected_req].req_id;
                                pending_reads[ch].beats_remaining <= req_queue[selected_req].len;
                                bank_timer[ch][bnk] <= T_CL; perf_read_count <= perf_read_count + 1;
                            end
                            pending_bank[ch] <= bnk; pending_col[ch] <= col; pending_id[ch] <= req_queue[selected_req].req_id;
                            perf_row_hits <= perf_row_hits + 1; req_queue[selected_req].valid <= 1'b0; queue_count <= queue_count - 1;
                        end else begin
                            pending_cmd[ch] <= CMD_PRECHARGE; pending_bank[ch] <= bnk;
                            bank_timer[ch][bnk] <= T_RP; perf_row_misses <= perf_row_misses + 1;
                        end
                    end
                    default: ;
                endcase
            end

            for (int ch = 0; ch < P_NUM_CHANNELS; ch++) begin
                if (refresh_pending[ch]) begin
                    automatic logic all_idle = 1'b1;
                    for (int bnk = 0; bnk < P_NUM_BANKS; bnk++) if (bank_state[ch][bnk] != BANK_IDLE) all_idle = 1'b0;
                    if (all_idle) begin
                        pending_cmd[ch] <= CMD_REFRESH;
                        for (int bnk = 0; bnk < P_NUM_BANKS; bnk++) bank_timer[ch][bnk] <= T_RFC;
                        refresh_pending[ch] <= 1'b0;
                    end
                end
            end
        end
    end
    
    //=========================================================================
    // DDR Command Generation
    //=========================================================================
    
    always_comb begin
        for (int ch = 0; ch < P_NUM_CHANNELS; ch++) begin
            ddr_cs_n[ch]  = 1'b1;  // Deselect by default
            ddr_ras_n[ch] = 1'b1;
            ddr_cas_n[ch] = 1'b1;
            ddr_we_n[ch]  = 1'b1;
            ddr_ba[ch]    = pending_bank[ch];
            ddr_addr[ch]  = '0;
            ddr_wdata[ch] = pending_wdata[ch];
            
            case (pending_cmd[ch])
                CMD_ACTIVATE: begin
                    ddr_cs_n[ch]  = 1'b0;
                    ddr_ras_n[ch] = 1'b0;
                    ddr_cas_n[ch] = 1'b1;
                    ddr_we_n[ch]  = 1'b1;
                    ddr_addr[ch]  = pending_row[ch];
                end
                
                CMD_READ: begin
                    ddr_cs_n[ch]  = 1'b0;
                    ddr_ras_n[ch] = 1'b1;
                    ddr_cas_n[ch] = 1'b0;
                    ddr_we_n[ch]  = 1'b1;
                    ddr_addr[ch]  = {{(ROW_BITS-COL_BITS){1'b0}}, pending_col[ch]};
                end
                
                CMD_WRITE: begin
                    ddr_cs_n[ch]  = 1'b0;
                    ddr_ras_n[ch] = 1'b1;
                    ddr_cas_n[ch] = 1'b0;
                    ddr_we_n[ch]  = 1'b0;
                    ddr_addr[ch]  = {{(ROW_BITS-COL_BITS){1'b0}}, pending_col[ch]};
                end
                
                CMD_PRECHARGE: begin
                    ddr_cs_n[ch]  = 1'b0;
                    ddr_ras_n[ch] = 1'b0;
                    ddr_cas_n[ch] = 1'b1;
                    ddr_we_n[ch]  = 1'b0;
                end
                
                CMD_REFRESH: begin
                    ddr_cs_n[ch]  = 1'b0;
                    ddr_ras_n[ch] = 1'b0;
                    ddr_cas_n[ch] = 1'b0;
                    ddr_we_n[ch]  = 1'b1;
                end
                
                default: ; // NOP
            endcase
        end
    end
    
    //=========================================================================
    // Read Response Handling
    //=========================================================================
    
    // For simplicity, aggregate responses from all channels
    // In practice, would need proper tracking per outstanding request
    
    logic                    resp_valid_r;
    logic [P_DATA_WIDTH-1:0]   resp_data_r;
    logic [3:0]              resp_id_r;
    logic                    resp_last_r;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_valid_r <= 1'b0;
            resp_data_r  <= '0;
            resp_id_r    <= '0;
            resp_last_r  <= 1'b0;
        end else begin
            resp_valid_r <= 1'b0;
            
            // Check for read data from any channel
            for (int ch = 0; ch < P_NUM_CHANNELS; ch++) begin
                if (ddr_rdata_valid[ch] && pending_reads[ch].valid) begin
                    resp_valid_r <= 1'b1;
                    resp_data_r  <= ddr_rdata[ch];
                    resp_id_r    <= pending_reads[ch].req_id;
                    
                    if (pending_reads[ch].beats_remaining == 0) begin
                        resp_last_r <= 1'b1;
                        pending_reads[ch].valid <= 1'b0;
                    end else begin
                        resp_last_r <= 1'b0;
                        pending_reads[ch].beats_remaining <= pending_reads[ch].beats_remaining - 1;
                    end
                end
            end
        end
    end
    
    assign req_rvalid = resp_valid_r;
    assign req_rdata  = resp_data_r;
    assign req_rid    = resp_id_r;
    assign req_rlast  = resp_last_r;
    assign req_rresp  = 2'b00;  // OKAY
    
    //=========================================================================
    // Write Response
    //=========================================================================
    
    // Track pending write responses
    logic                    write_resp_pending;
    logic [3:0]              write_resp_id;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_resp_pending <= 1'b0;
            write_resp_id      <= '0;
        end else begin
            // Generate write response after write command issued
            for (int ch = 0; ch < P_NUM_CHANNELS; ch++) begin
                if (pending_cmd[ch] == CMD_WRITE) begin
                    write_resp_pending <= 1'b1;
                    write_resp_id      <= pending_id[ch];
                end
            end
            
            // Clear on handshake
            if (req_bvalid && req_bready) begin
                write_resp_pending <= 1'b0;
            end
        end
    end
    
    assign req_bvalid = write_resp_pending;
    assign req_bid    = write_resp_id;
    assign req_bresp  = 2'b00;  // OKAY

endmodule
