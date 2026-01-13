//=============================================================================
// GPGPU-1 Interfaces - Common Interface Definitions
//=============================================================================
// File:        gpgpu_interfaces.sv
// Description: SystemVerilog interfaces for core interconnections,
//              memory interfaces, and pipeline stages.
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`ifndef GPGPU_INTERFACES_SV
`define GPGPU_INTERFACES_SV

`default_nettype none

`include "gpgpu_defines.svh"

//=============================================================================
// Instruction Memory Interface
//=============================================================================

interface imem_if #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 32
);
    logic                      req;       // Request valid
    logic [ADDR_WIDTH-1:0]     addr;      // Instruction address
    logic                      ready;     // Memory ready to accept request
    logic                      valid;     // Response valid
    logic [DATA_WIDTH-1:0]     rdata;     // Instruction data
    
    // Core (master) side
    modport master (
        output req, addr,
        input  ready, valid, rdata
    );
    
    // Memory (slave) side
    modport slave (
        input  req, addr,
        output ready, valid, rdata
    );
    
endinterface

//=============================================================================
// Data Memory Interface (Simplified)
//=============================================================================

interface dmem_if #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64
);
    logic                      req;       // Request valid
    logic                      we;        // Write enable
    logic [ADDR_WIDTH-1:0]     addr;      // Memory address
    logic [DATA_WIDTH-1:0]     wdata;     // Write data
    logic [DATA_WIDTH/8-1:0]   wstrb;     // Byte write strobe
    logic                      ready;     // Memory ready
    logic                      valid;     // Response valid
    logic [DATA_WIDTH-1:0]     rdata;     // Read data
    
    modport master (
        output req, we, addr, wdata, wstrb,
        input  ready, valid, rdata
    );
    
    modport slave (
        input  req, we, addr, wdata, wstrb,
        output ready, valid, rdata
    );
    
endinterface

//=============================================================================
// AXI4 Memory Interface (Full)
//=============================================================================

interface axi4_if #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH   = 4
);
    // Write Address Channel
    logic [ID_WIDTH-1:0]       awid;
    logic [ADDR_WIDTH-1:0]     awaddr;
    logic [7:0]                awlen;
    logic [2:0]                awsize;
    logic [1:0]                awburst;
    logic                      awvalid;
    logic                      awready;
    
    // Write Data Channel
    logic [DATA_WIDTH-1:0]     wdata;
    logic [DATA_WIDTH/8-1:0]   wstrb;
    logic                      wlast;
    logic                      wvalid;
    logic                      wready;
    
    // Write Response Channel
    logic [ID_WIDTH-1:0]       bid;
    logic [1:0]                bresp;
    logic                      bvalid;
    logic                      bready;
    
    // Read Address Channel
    logic [ID_WIDTH-1:0]       arid;
    logic [ADDR_WIDTH-1:0]     araddr;
    logic [7:0]                arlen;
    logic [2:0]                arsize;
    logic [1:0]                arburst;
    logic                      arvalid;
    logic                      arready;
    
    // Read Data Channel
    logic [ID_WIDTH-1:0]       rid;
    logic [DATA_WIDTH-1:0]     rdata;
    logic [1:0]                rresp;
    logic                      rlast;
    logic                      rvalid;
    logic                      rready;
    
    // Master port (core side)
    modport master (
        output awid, awaddr, awlen, awsize, awburst, awvalid,
        input  awready,
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        input  bid, bresp, bvalid,
        output bready,
        output arid, araddr, arlen, arsize, arburst, arvalid,
        input  arready,
        input  rid, rdata, rresp, rlast, rvalid,
        output rready
    );
    
    // Slave port (memory side)
    modport slave (
        input  awid, awaddr, awlen, awsize, awburst, awvalid,
        output awready,
        input  wdata, wstrb, wlast, wvalid,
        output wready,
        output bid, bresp, bvalid,
        input  bready,
        input  arid, araddr, arlen, arsize, arburst, arvalid,
        output arready,
        output rid, rdata, rresp, rlast, rvalid,
        input  rready
    );
    
endinterface

//=============================================================================
// Register File Interface
//=============================================================================

interface regfile_if #(
    parameter int DATA_WIDTH     = 64,
    parameter int REG_ADDR_WIDTH = 5,
    parameter int WARP_SIZE      = 8
);
    // Read port 1
    logic [REG_ADDR_WIDTH-1:0]               rs1_addr;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]    rs1_data;
    
    // Read port 2
    logic [REG_ADDR_WIDTH-1:0]               rs2_addr;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]    rs2_data;
    
    // Write port
    logic                                    wr_en;
    logic [WARP_SIZE-1:0]                    wr_mask;  // Per-thread write enable
    logic [REG_ADDR_WIDTH-1:0]               wr_addr;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]    wr_data;
    
    modport read (
        output rs1_addr, rs2_addr,
        input  rs1_data, rs2_data
    );
    
    modport write (
        output wr_en, wr_mask, wr_addr, wr_data
    );
    
    modport regfile (
        input  rs1_addr, rs2_addr,
        output rs1_data, rs2_data,
        input  wr_en, wr_mask, wr_addr, wr_data
    );
    
endinterface

//=============================================================================
// Predicate Register File Interface
//=============================================================================

interface predfile_if #(
    parameter int PRED_ADDR_WIDTH = 3,
    parameter int WARP_SIZE       = 8
);
    // Read port (for condition evaluation)
    logic [PRED_ADDR_WIDTH-1:0]    pred_addr;
    logic [WARP_SIZE-1:0]          pred_data;  // One bit per thread
    
    // Write port (for compare results)
    logic                          wr_en;
    logic [WARP_SIZE-1:0]          wr_mask;
    logic [PRED_ADDR_WIDTH-1:0]    wr_addr;
    logic [WARP_SIZE-1:0]          wr_data;
    
    modport read (
        output pred_addr,
        input  pred_data
    );
    
    modport write (
        output wr_en, wr_mask, wr_addr, wr_data
    );
    
    modport predfile (
        input  pred_addr,
        output pred_data,
        input  wr_en, wr_mask, wr_addr, wr_data
    );
    
endinterface

//=============================================================================
// Warp Scheduler Interface
//=============================================================================

interface warp_sched_if #(
    parameter int WARP_ID_WIDTH = 2,
    parameter int WARP_SIZE     = 8,
    parameter int ADDR_WIDTH    = 64
);
    // Warp selection
    logic                          warp_valid;
    logic [WARP_ID_WIDTH-1:0]      warp_id;
    logic [WARP_SIZE-1:0]          active_mask;
    logic [ADDR_WIDTH-1:0]         pc;
    
    // Warp state updates
    logic                          update_pc;
    logic [ADDR_WIDTH-1:0]         next_pc;
    logic                          update_mask;
    logic [WARP_SIZE-1:0]          next_mask;
    
    // Stall signals
    logic                          stall;
    logic                          ready;
    
    // Barrier interface
    logic                          barrier_req;
    logic [3:0]                    barrier_id;
    logic                          barrier_release;
    
    modport scheduler (
        output warp_valid, warp_id, active_mask, pc,
        input  update_pc, next_pc, update_mask, next_mask,
        input  stall, barrier_req, barrier_id,
        output ready, barrier_release
    );
    
    modport pipeline (
        input  warp_valid, warp_id, active_mask, pc,
        output update_pc, next_pc, update_mask, next_mask,
        output stall, barrier_req, barrier_id,
        input  ready, barrier_release
    );
    
endinterface

//=============================================================================
// Execution Unit Interface
//=============================================================================

interface exec_if #(
    parameter int DATA_WIDTH = 64,
    parameter int WARP_SIZE  = 8
);
    // Input operands (per thread)
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   operand_a;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   operand_b;
    logic [WARP_SIZE-1:0]                   active_mask;
    
    // Operation select
    logic [7:0]                             func;
    logic                                   valid;
    
    // Result (per thread)
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   result;
    logic [WARP_SIZE-1:0]                   result_valid;
    logic                                   ready;
    
    modport driver (
        output operand_a, operand_b, active_mask, func, valid,
        input  result, result_valid, ready
    );
    
    modport exec_unit (
        input  operand_a, operand_b, active_mask, func, valid,
        output result, result_valid, ready
    );
    
endinterface

//=============================================================================
// Pipeline Stage Interfaces
//=============================================================================

// Fetch to Decode
interface if_id_if #(
    parameter int INST_WIDTH = 32,
    parameter int ADDR_WIDTH = 64,
    parameter int WARP_ID_WIDTH = 2,
    parameter int WARP_SIZE = 8
);
    logic                          valid;
    logic [INST_WIDTH-1:0]         instruction;
    logic [ADDR_WIDTH-1:0]         pc;
    logic [WARP_ID_WIDTH-1:0]      warp_id;
    logic [WARP_SIZE-1:0]          active_mask;
    logic                          ready;
    
    modport fetch (
        output valid, instruction, pc, warp_id, active_mask,
        input  ready
    );
    
    modport decode (
        input  valid, instruction, pc, warp_id, active_mask,
        output ready
    );
    
endinterface

// Decode to Execute (uses decoded_instr_t from package)
interface id_ex_if #(
    parameter int DATA_WIDTH = 64,
    parameter int ADDR_WIDTH = 64,
    parameter int WARP_ID_WIDTH = 2,
    parameter int WARP_SIZE = 8
);
    import gpgpu_pkg::*;
    
    logic                                   valid;
    decoded_instr_t                         decoded;
    logic [ADDR_WIDTH-1:0]                  pc;
    logic [WARP_ID_WIDTH-1:0]               warp_id;
    logic [WARP_SIZE-1:0]                   active_mask;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   rs1_data;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   rs2_data;
    logic [WARP_SIZE-1:0]                   pred_data;
    logic                                   ready;
    
    modport decode (
        output valid, decoded, pc, warp_id, active_mask,
               rs1_data, rs2_data, pred_data,
        input  ready
    );
    
    modport execute (
        input  valid, decoded, pc, warp_id, active_mask,
               rs1_data, rs2_data, pred_data,
        output ready
    );
    
endinterface

// Execute to Memory
interface ex_mem_if #(
    parameter int DATA_WIDTH = 64,
    parameter int ADDR_WIDTH = 64,
    parameter int WARP_ID_WIDTH = 2,
    parameter int WARP_SIZE = 8,
    parameter int REG_ADDR_WIDTH = 5
);
    import gpgpu_pkg::*;
    
    logic                                   valid;
    logic [WARP_ID_WIDTH-1:0]               warp_id;
    logic [WARP_SIZE-1:0]                   active_mask;
    
    // Register writeback info
    logic                                   rd_en;
    logic [REG_ADDR_WIDTH-1:0]              rd_addr;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   rd_data;
    
    // Predicate writeback info
    logic                                   pred_wr_en;
    logic [2:0]                             pred_wr_addr;
    logic [WARP_SIZE-1:0]                   pred_wr_data;
    
    // Memory operation
    mem_access_t                            mem_access;
    mem_space_t                             mem_space;
    logic [WARP_SIZE-1:0][ADDR_WIDTH-1:0]   mem_addr;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   mem_wdata;
    
    logic                                   ready;
    
    modport execute (
        output valid, warp_id, active_mask,
               rd_en, rd_addr, rd_data,
               pred_wr_en, pred_wr_addr, pred_wr_data,
               mem_access, mem_space, mem_addr, mem_wdata,
        input  ready
    );
    
    modport memory (
        input  valid, warp_id, active_mask,
               rd_en, rd_addr, rd_data,
               pred_wr_en, pred_wr_addr, pred_wr_data,
               mem_access, mem_space, mem_addr, mem_wdata,
        output ready
    );
    
endinterface

// Memory to Writeback
interface mem_wb_if #(
    parameter int DATA_WIDTH = 64,
    parameter int WARP_ID_WIDTH = 2,
    parameter int WARP_SIZE = 8,
    parameter int REG_ADDR_WIDTH = 5
);
    logic                                   valid;
    logic [WARP_ID_WIDTH-1:0]               warp_id;
    logic [WARP_SIZE-1:0]                   active_mask;
    
    // Register writeback
    logic                                   rd_en;
    logic [REG_ADDR_WIDTH-1:0]              rd_addr;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   rd_data;
    
    // Predicate writeback
    logic                                   pred_wr_en;
    logic [2:0]                             pred_wr_addr;
    logic [WARP_SIZE-1:0]                   pred_wr_data;
    
    logic                                   ready;
    
    modport memory (
        output valid, warp_id, active_mask,
               rd_en, rd_addr, rd_data,
               pred_wr_en, pred_wr_addr, pred_wr_data,
        input  ready
    );
    
    modport writeback (
        input  valid, warp_id, active_mask,
               rd_en, rd_addr, rd_data,
               pred_wr_en, pred_wr_addr, pred_wr_data,
        output ready
    );
    
endinterface

//=============================================================================
// Shared Memory Interface
//=============================================================================

interface shared_mem_if #(
    parameter int ADDR_WIDTH = 14,   // 16KB = 14-bit address
    parameter int DATA_WIDTH = 64,
    parameter int WARP_SIZE  = 8
);
    // Request (can be multiple threads)
    logic                                   req;
    logic                                   we;
    logic [WARP_SIZE-1:0]                   mask;      // Which threads active
    logic [WARP_SIZE-1:0][ADDR_WIDTH-1:0]   addr;      // Per-thread address
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   wdata;     // Per-thread write data
    
    // Response
    logic                                   ready;
    logic                                   valid;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   rdata;     // Per-thread read data
    
    modport master (
        output req, we, mask, addr, wdata,
        input  ready, valid, rdata
    );
    
    modport slave (
        input  req, we, mask, addr, wdata,
        output ready, valid, rdata
    );
    
endinterface

`endif // GPGPU_INTERFACES_SV
