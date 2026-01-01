//=============================================================================
// GPGPU-1 GPU Top-Level Module
//=============================================================================
// File:        gpu_top.sv
// Description: Top-level GPU module instantiating multiple cores with:
//              - Dispatch unit for kernel launch and thread block distribution
//              - Memory arbiter for global memory access
//              - Shared instruction memory interface
//              - Performance counters and status
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`include "gpgpu_defines.svh"

module gpu_top
    import gpgpu_pkg::*;
#(
    parameter int NUM_CORES       = 4,
    parameter int WARPS_PER_CORE  = 4,
    parameter int ICACHE_SIZE     = 4096,
    parameter int SHARED_MEM_SIZE = 16384
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    //=========================================================================
    // Command Interface (from Host)
    //=========================================================================
    
    input  logic                    cmd_valid,
    output logic                    cmd_ready,
    input  logic [3:0]              cmd_opcode,      // Command type
    input  logic [ADDR_WIDTH-1:0]   cmd_pc,          // Kernel start PC
    input  logic [31:0]             cmd_grid_dim_x,  // Grid dimensions
    input  logic [31:0]             cmd_grid_dim_y,
    input  logic [31:0]             cmd_grid_dim_z,
    input  logic [15:0]             cmd_block_dim_x, // Block dimensions
    input  logic [15:0]             cmd_block_dim_y,
    input  logic [15:0]             cmd_block_dim_z,
    
    //=========================================================================
    // Global Memory Interface (AXI4)
    //=========================================================================
    
    // Read Address Channel
    output logic                    axi_arvalid,
    input  logic                    axi_arready,
    output logic [ADDR_WIDTH-1:0]   axi_araddr,
    output logic [7:0]              axi_arlen,
    output logic [2:0]              axi_arsize,
    output logic [1:0]              axi_arburst,
    output logic [3:0]              axi_arid,
    
    // Read Data Channel
    input  logic                    axi_rvalid,
    output logic                    axi_rready,
    input  logic [511:0]            axi_rdata,       // 512-bit wide data bus
    input  logic [1:0]              axi_rresp,
    input  logic                    axi_rlast,
    input  logic [3:0]              axi_rid,
    
    // Write Address Channel
    output logic                    axi_awvalid,
    input  logic                    axi_awready,
    output logic [ADDR_WIDTH-1:0]   axi_awaddr,
    output logic [7:0]              axi_awlen,
    output logic [2:0]              axi_awsize,
    output logic [1:0]              axi_awburst,
    output logic [3:0]              axi_awid,
    
    // Write Data Channel
    output logic                    axi_wvalid,
    input  logic                    axi_wready,
    output logic [511:0]            axi_wdata,
    output logic [63:0]             axi_wstrb,
    output logic                    axi_wlast,
    
    // Write Response Channel
    input  logic                    axi_bvalid,
    output logic                    axi_bready,
    input  logic [1:0]              axi_bresp,
    input  logic [3:0]              axi_bid,
    
    //=========================================================================
    // Status Outputs
    //=========================================================================
    
    output logic                    gpu_busy,
    output logic                    gpu_done,
    output logic [NUM_CORES-1:0]    cores_active,
    output logic [31:0]             perf_cycle_count,
    output logic [31:0]             perf_instr_count
);

    //=========================================================================
    // Command Opcodes
    //=========================================================================
    
    localparam CMD_NOP        = 4'h0;
    localparam CMD_LAUNCH     = 4'h1;  // Launch kernel
    localparam CMD_SYNC       = 4'h2;  // Wait for completion
    localparam CMD_RESET      = 4'hF;  // Reset GPU
    
    //=========================================================================
    // Internal Signals
    //=========================================================================
    
    // Dispatch signals per core
    logic [NUM_CORES-1:0]                  core_dispatch_valid;
    logic [NUM_CORES-1:0]                  core_dispatch_ready;
    logic [NUM_CORES-1:0][WARP_ID_WIDTH-1:0] core_dispatch_warp_id;
    logic [NUM_CORES-1:0][ADDR_WIDTH-1:0]  core_dispatch_pc;
    logic [NUM_CORES-1:0][WARP_SIZE-1:0]   core_dispatch_mask;
    
    // Core status
    logic [NUM_CORES-1:0]                  core_busy;
    logic [NUM_CORES-1:0]                  core_all_warps_done;
    logic [NUM_CORES-1:0][WARPS_PER_CORE-1:0] core_warps_active;
    
    // Core memory interfaces
    logic [NUM_CORES-1:0]                  core_gmem_arvalid;
    logic [NUM_CORES-1:0]                  core_gmem_arready;
    logic [NUM_CORES-1:0][ADDR_WIDTH-1:0]  core_gmem_araddr;
    logic [NUM_CORES-1:0][7:0]             core_gmem_arlen;
    logic [NUM_CORES-1:0][2:0]             core_gmem_arsize;
    
    logic [NUM_CORES-1:0]                  core_gmem_rvalid;
    logic [NUM_CORES-1:0]                  core_gmem_rready;
    logic [NUM_CORES-1:0][DATA_WIDTH-1:0]  core_gmem_rdata;
    logic [NUM_CORES-1:0][1:0]             core_gmem_rresp;
    logic [NUM_CORES-1:0]                  core_gmem_rlast;
    
    logic [NUM_CORES-1:0]                  core_gmem_awvalid;
    logic [NUM_CORES-1:0]                  core_gmem_awready;
    logic [NUM_CORES-1:0][ADDR_WIDTH-1:0]  core_gmem_awaddr;
    logic [NUM_CORES-1:0][7:0]             core_gmem_awlen;
    logic [NUM_CORES-1:0][2:0]             core_gmem_awsize;
    
    logic [NUM_CORES-1:0]                  core_gmem_wvalid;
    logic [NUM_CORES-1:0]                  core_gmem_wready;
    logic [NUM_CORES-1:0][DATA_WIDTH-1:0]  core_gmem_wdata;
    logic [NUM_CORES-1:0][7:0]             core_gmem_wstrb;
    logic [NUM_CORES-1:0]                  core_gmem_wlast;
    
    logic [NUM_CORES-1:0]                  core_gmem_bvalid;
    logic [NUM_CORES-1:0]                  core_gmem_bready;
    logic [NUM_CORES-1:0][1:0]             core_gmem_bresp;
    
    // Instruction memory interfaces per core
    logic [NUM_CORES-1:0]                  core_imem_req_valid;
    logic [NUM_CORES-1:0][ADDR_WIDTH-1:0]  core_imem_req_addr;
    logic [NUM_CORES-1:0]                  core_imem_req_ready;
    logic [NUM_CORES-1:0]                  core_imem_resp_valid;
    logic [NUM_CORES-1:0][255:0]           core_imem_resp_data;
    
    //=========================================================================
    // Dispatch Unit
    //=========================================================================
    
    dispatch_unit #(
        .NUM_CORES(NUM_CORES),
        .WARPS_PER_CORE(WARPS_PER_CORE)
    ) u_dispatch (
        .clk              (clk),
        .rst_n            (rst_n),
        
        // Command interface
        .cmd_valid        (cmd_valid),
        .cmd_ready        (cmd_ready),
        .cmd_opcode       (cmd_opcode),
        .cmd_pc           (cmd_pc),
        .cmd_grid_dim_x   (cmd_grid_dim_x),
        .cmd_grid_dim_y   (cmd_grid_dim_y),
        .cmd_grid_dim_z   (cmd_grid_dim_z),
        .cmd_block_dim_x  (cmd_block_dim_x),
        .cmd_block_dim_y  (cmd_block_dim_y),
        .cmd_block_dim_z  (cmd_block_dim_z),
        
        // Core dispatch interfaces
        .core_dispatch_valid   (core_dispatch_valid),
        .core_dispatch_ready   (core_dispatch_ready),
        .core_dispatch_warp_id (core_dispatch_warp_id),
        .core_dispatch_pc      (core_dispatch_pc),
        .core_dispatch_mask    (core_dispatch_mask),
        
        // Core status
        .core_busy            (core_busy),
        .core_all_warps_done  (core_all_warps_done),
        
        // Status
        .dispatch_busy        (gpu_busy),
        .dispatch_done        (gpu_done)
    );
    
    //=========================================================================
    // GPU Core Instances
    //=========================================================================
    
    generate
        for (genvar c = 0; c < NUM_CORES; c++) begin : gen_cores
            gpu_core #(
                .CORE_ID(c),
                .NUM_WARPS(WARPS_PER_CORE),
                .ICACHE_SIZE(ICACHE_SIZE),
                .SHARED_MEM_SIZE(SHARED_MEM_SIZE)
            ) u_core (
                .clk              (clk),
                .rst_n            (rst_n),
                
                // Dispatch interface
                .dispatch_valid   (core_dispatch_valid[c]),
                .dispatch_warp_id (core_dispatch_warp_id[c]),
                .dispatch_pc      (core_dispatch_pc[c]),
                .dispatch_mask    (core_dispatch_mask[c]),
                .dispatch_ready   (core_dispatch_ready[c]),
                
                // Global memory interface
                .gmem_arvalid     (core_gmem_arvalid[c]),
                .gmem_arready     (core_gmem_arready[c]),
                .gmem_araddr      (core_gmem_araddr[c]),
                .gmem_arlen       (core_gmem_arlen[c]),
                .gmem_arsize      (core_gmem_arsize[c]),
                
                .gmem_rvalid      (core_gmem_rvalid[c]),
                .gmem_rready      (core_gmem_rready[c]),
                .gmem_rdata       (core_gmem_rdata[c]),
                .gmem_rresp       (core_gmem_rresp[c]),
                .gmem_rlast       (core_gmem_rlast[c]),
                
                .gmem_awvalid     (core_gmem_awvalid[c]),
                .gmem_awready     (core_gmem_awready[c]),
                .gmem_awaddr      (core_gmem_awaddr[c]),
                .gmem_awlen       (core_gmem_awlen[c]),
                .gmem_awsize      (core_gmem_awsize[c]),
                
                .gmem_wvalid      (core_gmem_wvalid[c]),
                .gmem_wready      (core_gmem_wready[c]),
                .gmem_wdata       (core_gmem_wdata[c]),
                .gmem_wstrb       (core_gmem_wstrb[c]),
                .gmem_wlast       (core_gmem_wlast[c]),
                
                .gmem_bvalid      (core_gmem_bvalid[c]),
                .gmem_bready      (core_gmem_bready[c]),
                .gmem_bresp       (core_gmem_bresp[c]),
                
                // Instruction memory interface
                .imem_req_valid   (core_imem_req_valid[c]),
                .imem_req_addr    (core_imem_req_addr[c]),
                .imem_req_ready   (core_imem_req_ready[c]),
                .imem_resp_valid  (core_imem_resp_valid[c]),
                .imem_resp_data   (core_imem_resp_data[c]),
                
                // Status
                .warps_active     (core_warps_active[c]),
                .core_busy        (core_busy[c]),
                .all_warps_done   (core_all_warps_done[c])
            );
        end
    endgenerate
    
    //=========================================================================
    // Memory Arbiter (Round-Robin)
    //=========================================================================
    
    memory_arbiter #(
        .NUM_CORES(NUM_CORES)
    ) u_mem_arbiter (
        .clk              (clk),
        .rst_n            (rst_n),
        
        // Core data memory interfaces
        .core_arvalid     (core_gmem_arvalid),
        .core_arready     (core_gmem_arready),
        .core_araddr      (core_gmem_araddr),
        .core_arlen       (core_gmem_arlen),
        .core_arsize      (core_gmem_arsize),
        
        .core_rvalid      (core_gmem_rvalid),
        .core_rready      (core_gmem_rready),
        .core_rdata       (core_gmem_rdata),
        .core_rresp       (core_gmem_rresp),
        .core_rlast       (core_gmem_rlast),
        
        .core_awvalid     (core_gmem_awvalid),
        .core_awready     (core_gmem_awready),
        .core_awaddr      (core_gmem_awaddr),
        .core_awlen       (core_gmem_awlen),
        .core_awsize      (core_gmem_awsize),
        
        .core_wvalid      (core_gmem_wvalid),
        .core_wready      (core_gmem_wready),
        .core_wdata       (core_gmem_wdata),
        .core_wstrb       (core_gmem_wstrb),
        .core_wlast       (core_gmem_wlast),
        
        .core_bvalid      (core_gmem_bvalid),
        .core_bready      (core_gmem_bready),
        .core_bresp       (core_gmem_bresp),
        
        // Core instruction memory interfaces
        .core_imem_req_valid  (core_imem_req_valid),
        .core_imem_req_addr   (core_imem_req_addr),
        .core_imem_req_ready  (core_imem_req_ready),
        .core_imem_resp_valid (core_imem_resp_valid),
        .core_imem_resp_data  (core_imem_resp_data),
        
        // External AXI interface
        .axi_arvalid      (axi_arvalid),
        .axi_arready      (axi_arready),
        .axi_araddr       (axi_araddr),
        .axi_arlen        (axi_arlen),
        .axi_arsize       (axi_arsize),
        .axi_arburst      (axi_arburst),
        .axi_arid         (axi_arid),
        
        .axi_rvalid       (axi_rvalid),
        .axi_rready       (axi_rready),
        .axi_rdata        (axi_rdata),
        .axi_rresp        (axi_rresp),
        .axi_rlast        (axi_rlast),
        .axi_rid          (axi_rid),
        
        .axi_awvalid      (axi_awvalid),
        .axi_awready      (axi_awready),
        .axi_awaddr       (axi_awaddr),
        .axi_awlen        (axi_awlen),
        .axi_awsize       (axi_awsize),
        .axi_awburst      (axi_awburst),
        .axi_awid         (axi_awid),
        
        .axi_wvalid       (axi_wvalid),
        .axi_wready       (axi_wready),
        .axi_wdata        (axi_wdata),
        .axi_wstrb        (axi_wstrb),
        .axi_wlast        (axi_wlast),
        
        .axi_bvalid       (axi_bvalid),
        .axi_bready       (axi_bready),
        .axi_bresp        (axi_bresp),
        .axi_bid          (axi_bid)
    );
    
    //=========================================================================
    // Performance Counters
    //=========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            perf_cycle_count <= '0;
            perf_instr_count <= '0;
        end else begin
            // Count cycles when GPU is busy
            if (gpu_busy) begin
                perf_cycle_count <= perf_cycle_count + 1;
            end
            
            // TODO: Add instruction counting from cores
        end
    end
    
    //=========================================================================
    // Status Aggregation
    //=========================================================================
    
    assign cores_active = ~core_all_warps_done;

endmodule


//=============================================================================
// Dispatch Unit
//=============================================================================
// Distributes thread blocks to available cores

module dispatch_unit
    import gpgpu_pkg::*;
#(
    parameter int NUM_CORES      = 4,
    parameter int WARPS_PER_CORE = 4
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Command interface
    input  logic                    cmd_valid,
    output logic                    cmd_ready,
    input  logic [3:0]              cmd_opcode,
    input  logic [ADDR_WIDTH-1:0]   cmd_pc,
    input  logic [31:0]             cmd_grid_dim_x,
    input  logic [31:0]             cmd_grid_dim_y,
    input  logic [31:0]             cmd_grid_dim_z,
    input  logic [15:0]             cmd_block_dim_x,
    input  logic [15:0]             cmd_block_dim_y,
    input  logic [15:0]             cmd_block_dim_z,
    
    // Core dispatch interfaces
    output logic [NUM_CORES-1:0]                     core_dispatch_valid,
    input  logic [NUM_CORES-1:0]                     core_dispatch_ready,
    output logic [NUM_CORES-1:0][WARP_ID_WIDTH-1:0]  core_dispatch_warp_id,
    output logic [NUM_CORES-1:0][ADDR_WIDTH-1:0]     core_dispatch_pc,
    output logic [NUM_CORES-1:0][WARP_SIZE-1:0]      core_dispatch_mask,
    
    // Core status
    input  logic [NUM_CORES-1:0]    core_busy,
    input  logic [NUM_CORES-1:0]    core_all_warps_done,
    
    // Status
    output logic                    dispatch_busy,
    output logic                    dispatch_done
);

    //=========================================================================
    // Command Opcodes
    //=========================================================================
    
    localparam CMD_NOP    = 4'h0;
    localparam CMD_LAUNCH = 4'h1;
    localparam CMD_SYNC   = 4'h2;
    localparam CMD_RESET  = 4'hF;
    
    //=========================================================================
    // State Machine
    //=========================================================================
    
    typedef enum logic [2:0] {
        DISP_IDLE,
        DISP_LAUNCH,
        DISP_DISPATCH,
        DISP_WAIT_CORE,
        DISP_WAIT_DONE,
        DISP_DONE
    } disp_state_t;
    
    disp_state_t state, next_state;
      //=========================================================================
    // Registers
    //=========================================================================
    
    // Kernel configuration
    logic [ADDR_WIDTH-1:0]  kernel_pc;
    logic [31:0]            grid_dim_x, grid_dim_y, grid_dim_z;
    logic [15:0]            block_dim_x, block_dim_y, block_dim_z;
    
    // Thread block tracking
    logic [31:0]            total_blocks;
    logic [31:0]            blocks_dispatched;
    logic [31:0]            blocks_completed;
    
    // Current block position
    logic [31:0]            block_idx_x, block_idx_y, block_idx_z;
    
    // Threads per block
    logic [31:0]            threads_per_block;
    logic [31:0]            warps_per_block;
    
    // Core selection - dispatch ONE warp at a time
    logic [$clog2(NUM_CORES)-1:0] current_core;
    logic [WARP_ID_WIDTH-1:0]     current_warp;
    logic                         dispatch_pending;  // Waiting for core to accept
    
    //=========================================================================
    // Combinational Logic
    //=========================================================================
    
    assign threads_per_block = block_dim_x * block_dim_y * block_dim_z;
    assign warps_per_block = (threads_per_block + WARP_SIZE - 1) / WARP_SIZE;
    
    // Find first available core
    logic [NUM_CORES-1:0] core_available;
    logic                 any_core_available;
    logic [$clog2(NUM_CORES)-1:0] next_available_core;
    
    always_comb begin
        core_available = core_all_warps_done & core_dispatch_ready;
        any_core_available = |core_available;
        
        next_available_core = '0;
        for (int i = 0; i < NUM_CORES; i++) begin
            if (core_available[i]) begin
                next_available_core = i[$clog2(NUM_CORES)-1:0];
                break;
            end
        end
    end
    
    //=========================================================================
    // State Machine
    //=========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= DISP_IDLE;
        end else begin
            state <= next_state;
        end
    end
      always_comb begin
        next_state = state;
        
        case (state)
            DISP_IDLE: begin
                if (cmd_valid && cmd_opcode == CMD_LAUNCH) begin
                    next_state = DISP_LAUNCH;
                end
            end
            
            DISP_LAUNCH: begin
                next_state = DISP_DISPATCH;
            end
            
            DISP_DISPATCH: begin
                if (blocks_dispatched >= total_blocks && !dispatch_pending) begin
                    next_state = DISP_WAIT_DONE;
                end else if (!any_core_available && !dispatch_pending) begin
                    next_state = DISP_WAIT_CORE;
                end
            end
            
            DISP_WAIT_CORE: begin
                if (any_core_available) begin
                    next_state = DISP_DISPATCH;
                end
            end
            
            DISP_WAIT_DONE: begin
                if (&core_all_warps_done) begin
                    next_state = DISP_DONE;
                end
            end
            
            DISP_DONE: begin
                next_state = DISP_IDLE;
            end
            
            default: next_state = DISP_IDLE;
        endcase
    end
      //=========================================================================
    // Dispatch Logic
    //=========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            kernel_pc         <= '0;
            grid_dim_x        <= '0;
            grid_dim_y        <= '0;
            grid_dim_z        <= '0;
            block_dim_x       <= '0;
            block_dim_y       <= '0;
            block_dim_z       <= '0;
            total_blocks      <= '0;
            blocks_dispatched <= '0;
            blocks_completed  <= '0;
            block_idx_x       <= '0;
            block_idx_y       <= '0;
            block_idx_z       <= '0;
            current_core      <= '0;
            current_warp      <= '0;
            dispatch_pending  <= 1'b0;
            
            for (int i = 0; i < NUM_CORES; i++) begin
                core_dispatch_valid[i]   <= 1'b0;
                core_dispatch_warp_id[i] <= '0;
                core_dispatch_pc[i]      <= '0;
                core_dispatch_mask[i]    <= '0;
            end
        end else begin
            // Clear dispatch valid when core accepts (handshake complete)
            for (int i = 0; i < NUM_CORES; i++) begin
                if (core_dispatch_valid[i] && core_dispatch_ready[i]) begin
                    core_dispatch_valid[i] <= 1'b0;
                    dispatch_pending <= 1'b0;
                end
            end
            
            case (state)
                DISP_IDLE: begin
                    // Reset counters
                    blocks_dispatched <= '0;
                    blocks_completed  <= '0;
                    current_warp      <= '0;
                    dispatch_pending  <= 1'b0;
                end
                
                DISP_LAUNCH: begin
                    // Capture kernel configuration
                    kernel_pc   <= cmd_pc;
                    grid_dim_x  <= cmd_grid_dim_x;
                    grid_dim_y  <= cmd_grid_dim_y;
                    grid_dim_z  <= cmd_grid_dim_z;
                    block_dim_x <= cmd_block_dim_x;
                    block_dim_y <= cmd_block_dim_y;
                    block_dim_z <= cmd_block_dim_z;
                    
                    total_blocks <= cmd_grid_dim_x * cmd_grid_dim_y * cmd_grid_dim_z;
                    
                    block_idx_x <= '0;
                    block_idx_y <= '0;
                    block_idx_z <= '0;
                    current_core <= '0;
                    current_warp <= '0;
                end
                
                DISP_DISPATCH: begin
                    // Only dispatch if not waiting for a previous dispatch to complete
                    if (!dispatch_pending && blocks_dispatched < total_blocks && any_core_available) begin
                        // Dispatch warp 0 to available core (simplified: 1 warp per block)
                        core_dispatch_valid[next_available_core]   <= 1'b1;
                        core_dispatch_warp_id[next_available_core] <= '0;  // Warp 0
                        core_dispatch_pc[next_available_core]      <= kernel_pc;
                        core_dispatch_mask[next_available_core]    <= {WARP_SIZE{1'b1}};
                        
                        current_core <= next_available_core;
                        dispatch_pending <= 1'b1;
                        
                        // Advance to next block
                        blocks_dispatched <= blocks_dispatched + 1;
                        
                        if (block_idx_x + 1 < grid_dim_x) begin
                            block_idx_x <= block_idx_x + 1;
                        end else begin
                            block_idx_x <= '0;
                            if (block_idx_y + 1 < grid_dim_y) begin
                                block_idx_y <= block_idx_y + 1;
                            end else begin
                                block_idx_y <= '0;
                                block_idx_z <= block_idx_z + 1;
                            end
                        end
                    end
                end
                
                default: begin
                    // No action
                end
            endcase
        end
    end
    
    //=========================================================================
    // Status Outputs
    //=========================================================================
    
    assign cmd_ready     = (state == DISP_IDLE);
    assign dispatch_busy = (state != DISP_IDLE) && (state != DISP_DONE);
    assign dispatch_done = (state == DISP_DONE);

endmodule


//=============================================================================
// Memory Arbiter
//=============================================================================
// Round-robin arbiter for memory access from multiple cores

module memory_arbiter
    import gpgpu_pkg::*;
#(
    parameter int NUM_CORES = 4
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    //=========================================================================
    // Core Data Memory Interfaces
    //=========================================================================
    
    input  logic [NUM_CORES-1:0]                  core_arvalid,
    output logic [NUM_CORES-1:0]                  core_arready,
    input  logic [NUM_CORES-1:0][ADDR_WIDTH-1:0]  core_araddr,
    input  logic [NUM_CORES-1:0][7:0]             core_arlen,
    input  logic [NUM_CORES-1:0][2:0]             core_arsize,
    
    output logic [NUM_CORES-1:0]                  core_rvalid,
    input  logic [NUM_CORES-1:0]                  core_rready,
    output logic [NUM_CORES-1:0][DATA_WIDTH-1:0]  core_rdata,
    output logic [NUM_CORES-1:0][1:0]             core_rresp,
    output logic [NUM_CORES-1:0]                  core_rlast,
    
    input  logic [NUM_CORES-1:0]                  core_awvalid,
    output logic [NUM_CORES-1:0]                  core_awready,
    input  logic [NUM_CORES-1:0][ADDR_WIDTH-1:0]  core_awaddr,
    input  logic [NUM_CORES-1:0][7:0]             core_awlen,
    input  logic [NUM_CORES-1:0][2:0]             core_awsize,
    
    input  logic [NUM_CORES-1:0]                  core_wvalid,
    output logic [NUM_CORES-1:0]                  core_wready,
    input  logic [NUM_CORES-1:0][DATA_WIDTH-1:0]  core_wdata,
    input  logic [NUM_CORES-1:0][7:0]             core_wstrb,
    input  logic [NUM_CORES-1:0]                  core_wlast,
    
    output logic [NUM_CORES-1:0]                  core_bvalid,
    input  logic [NUM_CORES-1:0]                  core_bready,
    output logic [NUM_CORES-1:0][1:0]             core_bresp,
    
    //=========================================================================
    // Core Instruction Memory Interfaces
    //=========================================================================
    
    input  logic [NUM_CORES-1:0]                  core_imem_req_valid,
    input  logic [NUM_CORES-1:0][ADDR_WIDTH-1:0]  core_imem_req_addr,
    output logic [NUM_CORES-1:0]                  core_imem_req_ready,
    output logic [NUM_CORES-1:0]                  core_imem_resp_valid,
    output logic [NUM_CORES-1:0][255:0]           core_imem_resp_data,
    
    //=========================================================================
    // External AXI Interface
    //=========================================================================
    
    output logic                    axi_arvalid,
    input  logic                    axi_arready,
    output logic [ADDR_WIDTH-1:0]   axi_araddr,
    output logic [7:0]              axi_arlen,
    output logic [2:0]              axi_arsize,
    output logic [1:0]              axi_arburst,
    output logic [3:0]              axi_arid,
    
    input  logic                    axi_rvalid,
    output logic                    axi_rready,
    input  logic [511:0]            axi_rdata,
    input  logic [1:0]              axi_rresp,
    input  logic                    axi_rlast,
    input  logic [3:0]              axi_rid,
    
    output logic                    axi_awvalid,
    input  logic                    axi_awready,
    output logic [ADDR_WIDTH-1:0]   axi_awaddr,
    output logic [7:0]              axi_awlen,
    output logic [2:0]              axi_awsize,
    output logic [1:0]              axi_awburst,
    output logic [3:0]              axi_awid,
    
    output logic                    axi_wvalid,
    input  logic                    axi_wready,
    output logic [511:0]            axi_wdata,
    output logic [63:0]             axi_wstrb,
    output logic                    axi_wlast,
    
    input  logic                    axi_bvalid,
    output logic                    axi_bready,
    input  logic [1:0]              axi_bresp,
    input  logic [3:0]              axi_bid
);

    //=========================================================================
    // Arbiter State
    //=========================================================================
    
    typedef enum logic [2:0] {
        ARB_IDLE,
        ARB_READ_ADDR,
        ARB_READ_DATA,
        ARB_WRITE_ADDR,
        ARB_WRITE_DATA,
        ARB_WRITE_RESP,
        ARB_IMEM_REQ,
        ARB_IMEM_RESP
    } arb_state_t;
    
    arb_state_t state;
    
    // Current grant
    logic [$clog2(NUM_CORES)-1:0] granted_core;
    logic                         is_imem_req;
    
    // Round-robin priority
    logic [$clog2(NUM_CORES)-1:0] rr_priority;
    
    //=========================================================================
    // Request Selection (Round-Robin)
    //=========================================================================
    
    logic [NUM_CORES-1:0] data_read_req;
    logic [NUM_CORES-1:0] data_write_req;
    logic [NUM_CORES-1:0] imem_req;
    logic                 any_data_read;
    logic                 any_data_write;
    logic                 any_imem;
    
    assign data_read_req  = core_arvalid;
    assign data_write_req = core_awvalid;
    assign imem_req       = core_imem_req_valid;
    assign any_data_read  = |data_read_req;
    assign any_data_write = |data_write_req;
    assign any_imem       = |imem_req;
    
    // Find next requestor (round-robin)
    function automatic logic [$clog2(NUM_CORES)-1:0] find_next_req(
        input logic [NUM_CORES-1:0] requests,
        input logic [$clog2(NUM_CORES)-1:0] priority_start
    );
        for (int i = 0; i < NUM_CORES; i++) begin
            logic [$clog2(NUM_CORES)-1:0] idx;
            idx = (priority_start + i) % NUM_CORES;
            if (requests[idx]) begin
                return idx;
            end
        end
        return '0;
    endfunction
    
    //=========================================================================
    // State Machine
    //=========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ARB_IDLE;
            granted_core <= '0;
            is_imem_req  <= 1'b0;
            rr_priority  <= '0;
        end else begin
            case (state)
                ARB_IDLE: begin
                    // Priority: instruction fetch > data read > data write
                    if (any_imem) begin
                        granted_core <= find_next_req(imem_req, rr_priority);
                        is_imem_req  <= 1'b1;
                        state        <= ARB_IMEM_REQ;
                    end else if (any_data_read) begin
                        granted_core <= find_next_req(data_read_req, rr_priority);
                        is_imem_req  <= 1'b0;
                        state        <= ARB_READ_ADDR;
                    end else if (any_data_write) begin
                        granted_core <= find_next_req(data_write_req, rr_priority);
                        is_imem_req  <= 1'b0;
                        state        <= ARB_WRITE_ADDR;
                    end
                end
                
                ARB_READ_ADDR: begin
                    if (axi_arready) begin
                        state <= ARB_READ_DATA;
                    end
                end
                
                ARB_READ_DATA: begin
                    if (axi_rvalid && axi_rlast) begin
                        rr_priority <= granted_core + 1;
                        state <= ARB_IDLE;
                    end
                end
                
                ARB_WRITE_ADDR: begin
                    if (axi_awready) begin
                        state <= ARB_WRITE_DATA;
                    end
                end
                
                ARB_WRITE_DATA: begin
                    if (axi_wready && core_wlast[granted_core]) begin
                        state <= ARB_WRITE_RESP;
                    end
                end
                
                ARB_WRITE_RESP: begin
                    if (axi_bvalid) begin
                        rr_priority <= granted_core + 1;
                        state <= ARB_IDLE;
                    end
                end
                
                ARB_IMEM_REQ: begin
                    if (axi_arready) begin
                        state <= ARB_IMEM_RESP;
                    end
                end
                
                ARB_IMEM_RESP: begin
                    if (axi_rvalid && axi_rlast) begin
                        rr_priority <= granted_core + 1;
                        state <= ARB_IDLE;
                    end
                end
                
                default: state <= ARB_IDLE;
            endcase
        end
    end
    
    //=========================================================================
    // AXI Output Muxing
    //=========================================================================
    
    always_comb begin
        // Default values
        axi_arvalid = 1'b0;
        axi_araddr  = '0;
        axi_arlen   = '0;
        axi_arsize  = 3'b011;  // 8 bytes
        axi_arburst = 2'b01;   // INCR
        axi_arid    = '0;
        
        axi_awvalid = 1'b0;
        axi_awaddr  = '0;
        axi_awlen   = '0;
        axi_awsize  = 3'b011;
        axi_awburst = 2'b01;
        axi_awid    = '0;
        
        axi_wvalid  = 1'b0;
        axi_wdata   = '0;
        axi_wstrb   = '0;
        axi_wlast   = 1'b0;
        
        axi_rready  = 1'b0;
        axi_bready  = 1'b0;
        
        case (state)
            ARB_READ_ADDR: begin
                axi_arvalid = core_arvalid[granted_core];
                axi_araddr  = core_araddr[granted_core];
                axi_arlen   = core_arlen[granted_core];
                axi_arsize  = core_arsize[granted_core];
                axi_arid    = {2'b00, granted_core};
            end
            
            ARB_READ_DATA: begin
                axi_rready = core_rready[granted_core];
            end
            
            ARB_WRITE_ADDR: begin
                axi_awvalid = core_awvalid[granted_core];
                axi_awaddr  = core_awaddr[granted_core];
                axi_awlen   = core_awlen[granted_core];
                axi_awsize  = core_awsize[granted_core];
                axi_awid    = {2'b00, granted_core};
            end
            
            ARB_WRITE_DATA: begin
                axi_wvalid = core_wvalid[granted_core];
                // Expand 64-bit to 512-bit (place in correct position)
                axi_wdata  = {448'b0, core_wdata[granted_core]};
                axi_wstrb  = {56'b0, core_wstrb[granted_core]};
                axi_wlast  = core_wlast[granted_core];
            end
            
            ARB_WRITE_RESP: begin
                axi_bready = core_bready[granted_core];
            end
            
            ARB_IMEM_REQ: begin
                axi_arvalid = 1'b1;
                axi_araddr  = core_imem_req_addr[granted_core];
                axi_arlen   = 8'd0;  // Single beat (256 bits = 32 bytes)
                axi_arsize  = 3'b101;  // 32 bytes
                axi_arid    = {2'b01, granted_core};  // Use upper bits to distinguish imem
            end
            
            ARB_IMEM_RESP: begin
                axi_rready = 1'b1;
            end
            
            default: begin
                // Idle
            end
        endcase
    end
    
    //=========================================================================
    // Core Response Demuxing
    //=========================================================================
    
    always_comb begin
        // Default: no response to any core
        for (int i = 0; i < NUM_CORES; i++) begin
            core_arready[i] = 1'b0;
            core_rvalid[i]  = 1'b0;
            core_rdata[i]   = '0;
            core_rresp[i]   = 2'b00;
            core_rlast[i]   = 1'b0;
            
            core_awready[i] = 1'b0;
            core_wready[i]  = 1'b0;
            core_bvalid[i]  = 1'b0;
            core_bresp[i]   = 2'b00;
            
            core_imem_req_ready[i]  = 1'b0;
            core_imem_resp_valid[i] = 1'b0;
            core_imem_resp_data[i]  = '0;
        end
        
        case (state)
            ARB_READ_ADDR: begin
                core_arready[granted_core] = axi_arready;
            end
            
            ARB_READ_DATA: begin
                core_rvalid[granted_core] = axi_rvalid;
                core_rdata[granted_core]  = axi_rdata[DATA_WIDTH-1:0];  // Take lower 64 bits
                core_rresp[granted_core]  = axi_rresp;
                core_rlast[granted_core]  = axi_rlast;
            end
            
            ARB_WRITE_ADDR: begin
                core_awready[granted_core] = axi_awready;
            end
            
            ARB_WRITE_DATA: begin
                core_wready[granted_core] = axi_wready;
            end
            
            ARB_WRITE_RESP: begin
                core_bvalid[granted_core] = axi_bvalid;
                core_bresp[granted_core]  = axi_bresp;
            end
            
            ARB_IMEM_REQ: begin
                core_imem_req_ready[granted_core] = axi_arready;
            end
            
            ARB_IMEM_RESP: begin
                core_imem_resp_valid[granted_core] = axi_rvalid;
                core_imem_resp_data[granted_core]  = axi_rdata[255:0];  // Lower 256 bits
            end
            
            default: begin
                // Idle - no grants
            end
        endcase
    end

endmodule
