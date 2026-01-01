//=============================================================================
// GPGPU-1 GPU System - Full Memory Hierarchy
//=============================================================================
// File:        gpu_system.sv
// Description: Complete GPU system with integrated memory hierarchy:
//              - GPU Top (multi-core with dispatch and arbiter)
//              - L2 Cache
//              - Memory Controller
//              - External DDR interface
// Version:     1.0
// Date:        December 21, 2025
//=============================================================================

`include "gpgpu_defines.svh"

module gpu_system
    import gpgpu_pkg::*;
#(
    // GPU Parameters
    parameter int NUM_CORES       = 4,
    parameter int WARPS_PER_CORE  = 4,
    parameter int ICACHE_SIZE     = 4096,
    parameter int SHARED_MEM_SIZE = 16384,
    
    // L2 Cache Parameters
    parameter int L2_SIZE_KB      = 256,
    parameter int L2_LINE_SIZE    = 64,      // 64 bytes = 512 bits
    parameter int L2_NUM_WAYS     = 4,
    parameter int L2_NUM_MSHR     = 8,
    
    // Memory Controller Parameters
    parameter int MEM_CHANNELS    = 2,
    parameter int MEM_BANKS       = 8,
    parameter int MEM_ROWS        = 16384,
    parameter int MEM_DATA_WIDTH  = 512
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    //=========================================================================
    // Command Interface (from Host)
    //=========================================================================
    
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
    
    //=========================================================================
    // External DDR Interface (Memory Controller to DRAM)
    //=========================================================================
    
    output logic [MEM_CHANNELS-1:0]                                 ddr_cs_n,
    output logic [MEM_CHANNELS-1:0]                                 ddr_ras_n,
    output logic [MEM_CHANNELS-1:0]                                 ddr_cas_n,
    output logic [MEM_CHANNELS-1:0]                                 ddr_we_n,
    output logic [MEM_CHANNELS-1:0][$clog2(MEM_BANKS)-1:0]          ddr_ba,
    output logic [MEM_CHANNELS-1:0][$clog2(MEM_ROWS)-1:0]           ddr_addr,
    output logic [MEM_CHANNELS-1:0][MEM_DATA_WIDTH-1:0]             ddr_wdata,
    input  logic [MEM_CHANNELS-1:0][MEM_DATA_WIDTH-1:0]             ddr_rdata,
    input  logic [MEM_CHANNELS-1:0]                                 ddr_rdata_valid,
    
    //=========================================================================
    // Status Outputs
    //=========================================================================
    
    output logic                    gpu_busy,
    output logic                    gpu_done,
    output logic [NUM_CORES-1:0]    cores_active,
    
    // Performance counters
    output logic [31:0]             perf_cycle_count,
    output logic [31:0]             perf_instr_count,
    output logic [31:0]             perf_l2_hits,
    output logic [31:0]             perf_l2_misses,
    output logic [31:0]             perf_l2_writebacks,
    output logic [31:0]             perf_mem_reads,
    output logic [31:0]             perf_mem_writes,
    output logic [31:0]             perf_mem_row_hits,
    output logic [31:0]             perf_mem_row_misses
);

    //=========================================================================
    // Internal Signals: GPU Top <-> L2 Cache
    //=========================================================================
    
    // Read Address Channel
    logic                    gpu_l2_arvalid;
    logic                    gpu_l2_arready;
    logic [ADDR_WIDTH-1:0]   gpu_l2_araddr;
    logic [7:0]              gpu_l2_arlen;
    logic [2:0]              gpu_l2_arsize;
    logic [1:0]              gpu_l2_arburst;
    logic [3:0]              gpu_l2_arid;
    
    // Read Data Channel
    logic                    gpu_l2_rvalid;
    logic                    gpu_l2_rready;
    logic [511:0]            gpu_l2_rdata;
    logic [1:0]              gpu_l2_rresp;
    logic                    gpu_l2_rlast;
    logic [3:0]              gpu_l2_rid;
    
    // Write Address Channel
    logic                    gpu_l2_awvalid;
    logic                    gpu_l2_awready;
    logic [ADDR_WIDTH-1:0]   gpu_l2_awaddr;
    logic [7:0]              gpu_l2_awlen;
    logic [2:0]              gpu_l2_awsize;
    logic [1:0]              gpu_l2_awburst;
    logic [3:0]              gpu_l2_awid;
    
    // Write Data Channel
    logic                    gpu_l2_wvalid;
    logic                    gpu_l2_wready;
    logic [511:0]            gpu_l2_wdata;
    logic [63:0]             gpu_l2_wstrb;
    logic                    gpu_l2_wlast;
    
    // Write Response Channel
    logic                    gpu_l2_bvalid;
    logic                    gpu_l2_bready;
    logic [1:0]              gpu_l2_bresp;
    logic [3:0]              gpu_l2_bid;
    
    //=========================================================================
    // Internal Signals: L2 Cache <-> Memory Controller
    //=========================================================================
    
    // Read Address Channel
    logic                    l2_mem_arvalid;
    logic                    l2_mem_arready;
    logic [ADDR_WIDTH-1:0]   l2_mem_araddr;
    logic [7:0]              l2_mem_arlen;
    logic [2:0]              l2_mem_arsize;
    logic [1:0]              l2_mem_arburst;
    logic [3:0]              l2_mem_arid;
    
    // Read Data Channel
    logic                    l2_mem_rvalid;
    logic                    l2_mem_rready;
    logic [511:0]            l2_mem_rdata;
    logic [1:0]              l2_mem_rresp;
    logic                    l2_mem_rlast;
    logic [3:0]              l2_mem_rid;
    
    // Write Address Channel
    logic                    l2_mem_awvalid;
    logic                    l2_mem_awready;
    logic [ADDR_WIDTH-1:0]   l2_mem_awaddr;
    logic [7:0]              l2_mem_awlen;
    logic [2:0]              l2_mem_awsize;
    logic [1:0]              l2_mem_awburst;
    logic [3:0]              l2_mem_awid;
    
    // Write Data Channel
    logic                    l2_mem_wvalid;
    logic                    l2_mem_wready;
    logic [511:0]            l2_mem_wdata;
    logic [63:0]             l2_mem_wstrb;
    logic                    l2_mem_wlast;
    
    // Write Response Channel
    logic                    l2_mem_bvalid;
    logic                    l2_mem_bready;
    logic [1:0]              l2_mem_bresp;
    logic [3:0]              l2_mem_bid;
    
    //=========================================================================
    // GPU Top Instance
    //=========================================================================
    
    gpu_top #(
        .NUM_CORES(NUM_CORES),
        .WARPS_PER_CORE(WARPS_PER_CORE),
        .ICACHE_SIZE(ICACHE_SIZE),
        .SHARED_MEM_SIZE(SHARED_MEM_SIZE)
    ) u_gpu_top (
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
        
        // AXI interface -> connected to L2 cache
        .axi_arvalid      (gpu_l2_arvalid),
        .axi_arready      (gpu_l2_arready),
        .axi_araddr       (gpu_l2_araddr),
        .axi_arlen        (gpu_l2_arlen),
        .axi_arsize       (gpu_l2_arsize),
        .axi_arburst      (gpu_l2_arburst),
        .axi_arid         (gpu_l2_arid),
        
        .axi_rvalid       (gpu_l2_rvalid),
        .axi_rready       (gpu_l2_rready),
        .axi_rdata        (gpu_l2_rdata),
        .axi_rresp        (gpu_l2_rresp),
        .axi_rlast        (gpu_l2_rlast),
        .axi_rid          (gpu_l2_rid),
        
        .axi_awvalid      (gpu_l2_awvalid),
        .axi_awready      (gpu_l2_awready),
        .axi_awaddr       (gpu_l2_awaddr),
        .axi_awlen        (gpu_l2_awlen),
        .axi_awsize       (gpu_l2_awsize),
        .axi_awburst      (gpu_l2_awburst),
        .axi_awid         (gpu_l2_awid),
        
        .axi_wvalid       (gpu_l2_wvalid),
        .axi_wready       (gpu_l2_wready),
        .axi_wdata        (gpu_l2_wdata),
        .axi_wstrb        (gpu_l2_wstrb),
        .axi_wlast        (gpu_l2_wlast),
        
        .axi_bvalid       (gpu_l2_bvalid),
        .axi_bready       (gpu_l2_bready),
        .axi_bresp        (gpu_l2_bresp),
        .axi_bid          (gpu_l2_bid),
        
        // Status
        .gpu_busy         (gpu_busy),
        .gpu_done         (gpu_done),
        .cores_active     (cores_active),
        .perf_cycle_count (perf_cycle_count),
        .perf_instr_count (perf_instr_count)
    );
    
    //=========================================================================
    // L2 Cache Instance
    //=========================================================================
    
    l2_cache #(
        .CACHE_SIZE_KB(L2_SIZE_KB),
        .LINE_SIZE_BYTES(L2_LINE_SIZE),
        .NUM_WAYS(L2_NUM_WAYS),
        .NUM_MSHR(L2_NUM_MSHR)
    ) u_l2_cache (
        .clk             (clk),
        .rst_n           (rst_n),
        
        // Request interface (from GPU)
        .req_arvalid     (gpu_l2_arvalid),
        .req_arready     (gpu_l2_arready),
        .req_araddr      (gpu_l2_araddr),
        .req_arlen       (gpu_l2_arlen),
        .req_arsize      (gpu_l2_arsize),
        .req_arid        (gpu_l2_arid),
        
        .req_rvalid      (gpu_l2_rvalid),
        .req_rready      (gpu_l2_rready),
        .req_rdata       (gpu_l2_rdata),
        .req_rresp       (gpu_l2_rresp),
        .req_rlast       (gpu_l2_rlast),
        .req_rid         (gpu_l2_rid),
        
        .req_awvalid     (gpu_l2_awvalid),
        .req_awready     (gpu_l2_awready),
        .req_awaddr      (gpu_l2_awaddr),
        .req_awlen       (gpu_l2_awlen),
        .req_awsize      (gpu_l2_awsize),
        .req_awid        (gpu_l2_awid),
        
        .req_wvalid      (gpu_l2_wvalid),
        .req_wready      (gpu_l2_wready),
        .req_wdata       (gpu_l2_wdata),
        .req_wstrb       (gpu_l2_wstrb),
        .req_wlast       (gpu_l2_wlast),
        
        .req_bvalid      (gpu_l2_bvalid),
        .req_bready      (gpu_l2_bready),
        .req_bresp       (gpu_l2_bresp),
        .req_bid         (gpu_l2_bid),
        
        // Memory interface (to memory controller)
        .mem_arvalid     (l2_mem_arvalid),
        .mem_arready     (l2_mem_arready),
        .mem_araddr      (l2_mem_araddr),
        .mem_arlen       (l2_mem_arlen),
        .mem_arsize      (l2_mem_arsize),
        .mem_arburst     (l2_mem_arburst),
        .mem_arid        (l2_mem_arid),
        
        .mem_rvalid      (l2_mem_rvalid),
        .mem_rready      (l2_mem_rready),
        .mem_rdata       (l2_mem_rdata),
        .mem_rresp       (l2_mem_rresp),
        .mem_rlast       (l2_mem_rlast),
        .mem_rid         (l2_mem_rid),
        
        .mem_awvalid     (l2_mem_awvalid),
        .mem_awready     (l2_mem_awready),
        .mem_awaddr      (l2_mem_awaddr),
        .mem_awlen       (l2_mem_awlen),
        .mem_awsize      (l2_mem_awsize),
        .mem_awburst     (l2_mem_awburst),
        .mem_awid        (l2_mem_awid),
        
        .mem_wvalid      (l2_mem_wvalid),
        .mem_wready      (l2_mem_wready),
        .mem_wdata       (l2_mem_wdata),
        .mem_wstrb       (l2_mem_wstrb),
        .mem_wlast       (l2_mem_wlast),
        
        .mem_bvalid      (l2_mem_bvalid),
        .mem_bready      (l2_mem_bready),
        .mem_bresp       (l2_mem_bresp),
        .mem_bid         (l2_mem_bid),
        
        // Performance counters
        .perf_hits       (perf_l2_hits),
        .perf_misses     (perf_l2_misses),
        .perf_writebacks (perf_l2_writebacks)
    );
    
    //=========================================================================
    // Memory Controller Instance
    //=========================================================================
    
    memory_controller #(
        .NUM_CHANNELS(MEM_CHANNELS),
        .NUM_BANKS(MEM_BANKS),
        .NUM_ROWS(MEM_ROWS),
        .DATA_WIDTH(MEM_DATA_WIDTH),
        .QUEUE_DEPTH(16)
    ) u_memory_controller (
        .clk             (clk),
        .rst_n           (rst_n),
        
        // Request interface (from L2 cache)
        .req_arvalid     (l2_mem_arvalid),
        .req_arready     (l2_mem_arready),
        .req_araddr      (l2_mem_araddr),
        .req_arlen       (l2_mem_arlen),
        .req_arsize      (l2_mem_arsize),
        .req_arburst     (l2_mem_arburst),
        .req_arid        (l2_mem_arid),
        
        .req_rvalid      (l2_mem_rvalid),
        .req_rready      (l2_mem_rready),
        .req_rdata       (l2_mem_rdata),
        .req_rresp       (l2_mem_rresp),
        .req_rlast       (l2_mem_rlast),
        .req_rid         (l2_mem_rid),
        
        .req_awvalid     (l2_mem_awvalid),
        .req_awready     (l2_mem_awready),
        .req_awaddr      (l2_mem_awaddr),
        .req_awlen       (l2_mem_awlen),
        .req_awsize      (l2_mem_awsize),
        .req_awburst     (l2_mem_awburst),
        .req_awid        (l2_mem_awid),
        
        .req_wvalid      (l2_mem_wvalid),
        .req_wready      (l2_mem_wready),
        .req_wdata       (l2_mem_wdata),
        .req_wstrb       (l2_mem_wstrb),
        .req_wlast       (l2_mem_wlast),
        
        .req_bvalid      (l2_mem_bvalid),
        .req_bready      (l2_mem_bready),
        .req_bresp       (l2_mem_bresp),
        .req_bid         (l2_mem_bid),
        
        // DDR interface
        .ddr_cs_n        (ddr_cs_n),
        .ddr_ras_n       (ddr_ras_n),
        .ddr_cas_n       (ddr_cas_n),
        .ddr_we_n        (ddr_we_n),
        .ddr_ba          (ddr_ba),
        .ddr_addr        (ddr_addr),
        .ddr_wdata       (ddr_wdata),
        .ddr_rdata       (ddr_rdata),
        .ddr_rdata_valid (ddr_rdata_valid),
        
        // Performance counters
        .perf_read_count  (perf_mem_reads),
        .perf_write_count (perf_mem_writes),
        .perf_row_hits    (perf_mem_row_hits),
        .perf_row_misses  (perf_mem_row_misses)
    );

endmodule
