//=============================================================================
// GPGPU-1 GPU Core
//=============================================================================
// File:        gpu_core.sv
// Description: Top-level GPU core integrating all pipeline stages:
//              - Fetch Unit with Instruction Cache
//              - Decoder
//              - Register File (Operand Fetch)
//              - Execution Units (ALU, Shift, Compare, Mul/Div)
//              - Load/Store Unit
//              - Warp Scheduler
//              Implements a 6-stage in-order pipeline with SIMT execution.
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`include "gpgpu_defines.svh"

module gpu_core
    import gpgpu_pkg::*;
#(
    parameter int CORE_ID         = 0,
    parameter int NUM_WARPS       = WARPS_PER_CORE,
    parameter int ICACHE_SIZE     = 4096,
    parameter int SHARED_MEM_SIZE = 16384
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    //=========================================================================
    // Dispatch Interface (from GPU top)
    //=========================================================================
    
    input  logic                    dispatch_valid,
    input  logic [WARP_ID_WIDTH-1:0] dispatch_warp_id,
    input  logic [ADDR_WIDTH-1:0]   dispatch_pc,
    input  logic [WARP_SIZE-1:0]    dispatch_mask,
    output logic                    dispatch_ready,
    
    //=========================================================================
    // Global Memory Interface (AXI-like)
    //=========================================================================
    
    // Read Address Channel
    output logic                    gmem_arvalid,
    input  logic                    gmem_arready,
    output logic [ADDR_WIDTH-1:0]   gmem_araddr,
    output logic [7:0]              gmem_arlen,
    output logic [2:0]              gmem_arsize,
    
    // Read Data Channel
    input  logic                    gmem_rvalid,
    output logic                    gmem_rready,
    input  logic [DATA_WIDTH-1:0]   gmem_rdata,
    input  logic [1:0]              gmem_rresp,
    input  logic                    gmem_rlast,
    
    // Write Address Channel
    output logic                    gmem_awvalid,
    input  logic                    gmem_awready,
    output logic [ADDR_WIDTH-1:0]   gmem_awaddr,
    output logic [7:0]              gmem_awlen,
    output logic [2:0]              gmem_awsize,
    
    // Write Data Channel
    output logic                    gmem_wvalid,
    input  logic                    gmem_wready,
    output logic [DATA_WIDTH-1:0]   gmem_wdata,
    output logic [7:0]              gmem_wstrb,
    output logic                    gmem_wlast,
    
    // Write Response Channel
    input  logic                    gmem_bvalid,
    output logic                    gmem_bready,
    input  logic [1:0]              gmem_bresp,
    
    // Instruction Memory Interface
    output logic                    imem_req_valid,
    output logic [ADDR_WIDTH-1:0]   imem_req_addr,
    input  logic                    imem_req_ready,
    input  logic                    imem_resp_valid,
    input  logic [255:0]            imem_resp_data,
    
    //=========================================================================
    // Status Outputs
    //=========================================================================
    
    output logic [NUM_WARPS-1:0]    warps_active,
    output logic                    core_busy,
    output logic                    all_warps_done
);

    //=========================================================================
    // Internal Signals - Fetch Stage
    //=========================================================================
    
    // Scheduler -> Fetch
    logic                           sched_fetch_valid;
    logic [WARP_ID_WIDTH-1:0]       sched_fetch_warp_id;
    logic [ADDR_WIDTH-1:0]          sched_fetch_pc;
    logic [WARP_SIZE-1:0]           sched_fetch_mask;
    logic                           sched_fetch_ready;
    
    // Fetch -> Decode
    logic                           fetch_decode_valid;
    logic [INST_WIDTH-1:0]          fetch_decode_instr;
    logic [ADDR_WIDTH-1:0]          fetch_decode_pc;
    logic [WARP_ID_WIDTH-1:0]       fetch_decode_warp_id;
    logic [WARP_SIZE-1:0]           fetch_decode_mask;
    logic                           fetch_decode_ready;
    
    // Fetch control
    logic [NUM_WARPS-1:0]           warp_flush;
    logic                           cache_flush;
    logic                           fetch_busy;
    
    // Fetch -> Scheduler PC advance
    logic                           fetch_pc_advance_valid;
    logic [WARP_ID_WIDTH-1:0]       fetch_pc_advance_warp_id;
    logic [ADDR_WIDTH-1:0]          fetch_pc_advance_value;
    
    //=========================================================================
    // Internal Signals - Decode Stage
    //=========================================================================
    
    // Decode -> Operand
    decoded_instr_t                 decode_operand_decoded;
    logic                           decode_operand_valid;
    logic [ADDR_WIDTH-1:0]          decode_operand_pc;
    logic [WARP_ID_WIDTH-1:0]       decode_operand_warp_id;
    logic [WARP_SIZE-1:0]           decode_operand_mask;
    logic                           decode_operand_ready;
    logic                           decode_illegal;
    
    //=========================================================================
    // Internal Signals - Operand Fetch Stage
    //=========================================================================
    
    // Operand -> Execute
    logic                           operand_exec_valid;
    logic [WARP_ID_WIDTH-1:0]       operand_exec_warp_id;
    logic [WARP_SIZE-1:0]           operand_exec_mask;
    logic [ADDR_WIDTH-1:0]          operand_exec_pc;
    decoded_instr_t                 operand_exec_decoded;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] operand_exec_rs1_data;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] operand_exec_rs2_data;
    logic [WARP_SIZE-1:0]           operand_exec_pred_data;
    logic                           operand_exec_ready;
    
    //=========================================================================
    // Internal Signals - Execute Stage
    //=========================================================================
    
    // Execute -> Memory/Writeback
    logic                           exec_mem_valid;
    logic [WARP_ID_WIDTH-1:0]       exec_mem_warp_id;
    logic [WARP_SIZE-1:0]           exec_mem_mask;
    decoded_instr_t                 exec_mem_decoded;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] exec_mem_result;
    logic [WARP_SIZE-1:0]           exec_mem_pred_result;
    logic                           exec_mem_ready;
    
    // Execute -> LSU
    logic                           exec_lsu_valid;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] exec_lsu_addr;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] exec_lsu_store_data;
    logic                           exec_lsu_ready;
    
    // Branch control
    logic                           branch_taken;
    logic [ADDR_WIDTH-1:0]          branch_target;
    
    //=========================================================================
    // Internal Signals - Memory Stage
    //=========================================================================
    
    // LSU -> Writeback
    logic                           lsu_wb_valid;
    logic [WARP_ID_WIDTH-1:0]       lsu_wb_warp_id;
    logic [REG_ADDR_WIDTH-1:0]      lsu_wb_rd;
    logic [WARP_SIZE-1:0]           lsu_wb_mask;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] lsu_wb_data;
    logic                           lsu_wb_ready;
    
    // LSU internal signals
    logic                           lsu_req_ready;
    logic                           lsu_gmem_req_valid;
    logic                           lsu_gmem_req_we;
    logic [ADDR_WIDTH-1:0]          lsu_gmem_req_addr;
    logic [DATA_WIDTH-1:0]          lsu_gmem_req_wdata;
    logic [7:0]                     lsu_gmem_req_wstrb;
    logic                           lsu_gmem_req_ready;
    logic                           lsu_gmem_resp_valid;
    logic [DATA_WIDTH-1:0]          lsu_gmem_resp_rdata;
    logic                           lsu_gmem_store_complete;
    
    //=========================================================================
    // Internal Signals - Writeback Stage
    //=========================================================================
    
    // Writeback to Register File
    logic                           wb_rf_en;
    logic [WARP_ID_WIDTH-1:0]       wb_rf_warp_id;
    logic [REG_ADDR_WIDTH-1:0]      wb_rf_addr;
    logic [WARP_SIZE-1:0]           wb_rf_mask;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] wb_rf_data;
    
    // Writeback to Predicate File
    logic                           wb_pred_en;
    logic [WARP_ID_WIDTH-1:0]       wb_pred_warp_id;
    logic [PRED_ADDR_WIDTH-1:0]     wb_pred_addr;
    logic [WARP_SIZE-1:0]           wb_pred_mask;
    logic [WARP_SIZE-1:0]           wb_pred_data;
    
    //=========================================================================
    // Internal Signals - Warp Scheduler
    //=========================================================================
    
    warp_state_t                    sched_warp_state;
    logic [NUM_WARPS-1:0]           warps_at_barrier;
    
    //=========================================================================
    // Internal Signals - Scoreboard (Data Hazard Detection)
    //=========================================================================
    
    // Hazard check at decode stage
    logic                           scoreboard_check_valid;
    logic [WARP_ID_WIDTH-1:0]       scoreboard_check_warp_id;
    logic [REG_ADDR_WIDTH-1:0]      scoreboard_check_rs1;
    logic [REG_ADDR_WIDTH-1:0]      scoreboard_check_rs2;
    logic                           scoreboard_check_rs1_en;
    logic                           scoreboard_check_rs2_en;
    logic                           scoreboard_hazard_detected;
    
    // Register reservation at issue (decode->operand transition)
    logic                           scoreboard_reserve_valid;
    logic [WARP_ID_WIDTH-1:0]       scoreboard_reserve_warp_id;
    logic [REG_ADDR_WIDTH-1:0]      scoreboard_reserve_rd;
    logic                           scoreboard_reserve_rd_en;
    
    // Register completion at writeback
    logic                           scoreboard_complete_valid;
    logic [WARP_ID_WIDTH-1:0]       scoreboard_complete_warp_id;
    logic [REG_ADDR_WIDTH-1:0]      scoreboard_complete_rd;
    
    // Warp clear on termination
    logic                           scoreboard_clear_warp;
    logic [WARP_ID_WIDTH-1:0]       scoreboard_clear_warp_id;
    
    //=========================================================================
    // Internal Signals - Forwarding Network
    //=========================================================================
    
    // Forwarded operand data
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] fwd_rs1_data;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] fwd_rs2_data;
    
    // Forwarding status (for performance monitoring)
    logic                           fwd_rs1_from_e2m;
    logic                           fwd_rs1_from_m2w;
    logic                           fwd_rs1_from_wb;
    logic                           fwd_rs2_from_e2m;
    logic                           fwd_rs2_from_m2w;
    logic                           fwd_rs2_from_wb;
    
    // Load-use stall (can't forward from memory op in E2M)
    logic                           fwd_stall_required;
    
    // Stall signals
    logic                           stall_fetch;
    logic                           stall_decode;
    logic                           stall_operand;
    logic                           stall_execute;
    logic                           stall_memory;
    logic                           stall_writeback;
    
    // Divergence control
    logic                           diverge_push;
    logic [WARP_ID_WIDTH-1:0]       diverge_warp_id;
    logic [WARP_SIZE-1:0]           diverge_then_mask;
    logic                           diverge_else;
    logic [WARP_ID_WIDTH-1:0]       diverge_else_warp_id;
    logic                           diverge_pop;
    logic [WARP_ID_WIDTH-1:0]       diverge_pop_warp_id;
    
    // Early divergence detection (from decode stage)
    logic                           decode_is_diverge;
    logic [WARP_ID_WIDTH-1:0]       decode_diverge_warp_id;
    
    // Barrier control
    logic                           barrier_arrive;
    logic [WARP_ID_WIDTH-1:0]       barrier_warp_id;
    logic [3:0]                     barrier_id;
    logic                           barrier_release;
    logic [3:0]                     barrier_release_id;
    
    //=========================================================================
    // Pipeline Registers
    //=========================================================================
    
    // Fetch -> Decode pipeline register
    logic                           f2d_valid;
    logic [INST_WIDTH-1:0]          f2d_instr;
    logic [ADDR_WIDTH-1:0]          f2d_pc;
    logic [WARP_ID_WIDTH-1:0]       f2d_warp_id;
    logic [WARP_SIZE-1:0]           f2d_mask;
    
    // Decode -> Operand pipeline register
    logic                           d2o_valid;
    decoded_instr_t                 d2o_decoded;
    logic [ADDR_WIDTH-1:0]          d2o_pc;
    logic [WARP_ID_WIDTH-1:0]       d2o_warp_id;
    logic [WARP_SIZE-1:0]           d2o_mask;
    
    // Operand -> Execute pipeline register
    logic                           o2e_valid;
    decoded_instr_t                 o2e_decoded;
    logic [ADDR_WIDTH-1:0]          o2e_pc;
    logic [WARP_ID_WIDTH-1:0]       o2e_warp_id;
    logic [WARP_SIZE-1:0]           o2e_mask;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] o2e_rs1_data;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] o2e_rs2_data;
    logic [WARP_SIZE-1:0]           o2e_pred_data;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] o2e_sr_data;  // Special register data
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] o2e_store_data;  // Store data from RD register for ST instructions

    // Execute -> Memory/Writeback pipeline register
    logic                           e2m_valid;
    decoded_instr_t                 e2m_decoded;
    logic [WARP_ID_WIDTH-1:0]       e2m_warp_id;
    logic [WARP_SIZE-1:0]           e2m_mask;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] e2m_result;
    logic [WARP_SIZE-1:0]           e2m_pred_result;
    logic                           e2m_is_mem;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] e2m_store_data;  // Store data for ST instructions
    
    // Memory -> Writeback pipeline register
    logic                           m2w_valid;
    logic [WARP_ID_WIDTH-1:0]       m2w_warp_id;
    logic [REG_ADDR_WIDTH-1:0]      m2w_rd;
    logic [WARP_SIZE-1:0]           m2w_mask;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] m2w_data;
    logic [WARP_SIZE-1:0]           m2w_pred_data;
    logic                           m2w_rd_en;
    logic                           m2w_pred_wr_en;
    logic [PRED_ADDR_WIDTH-1:0]     m2w_pred_addr;
    
    //=========================================================================
    // Stall Logic
    //=========================================================================
    
    // Data hazard stall - stall decode stage if RAW hazard detected (without forwarding)
    // Forwarding stall - stall operand stage if load-use hazard (can't forward from memory op)
    logic stall_hazard;
    assign stall_hazard = scoreboard_hazard_detected && !fwd_can_bypass_hazard;
    
    // Forwarding can bypass scoreboard hazard if data is available from E2M/M2W/WB
    logic fwd_can_bypass_hazard;
    logic fwd_can_bypass_rs1, fwd_can_bypass_rs2;
    assign fwd_can_bypass_rs1 = !decoded_raw.rs1_en || 
                                 fwd_rs1_from_e2m || fwd_rs1_from_m2w || fwd_rs1_from_wb;
    assign fwd_can_bypass_rs2 = !decoded_raw.rs2_en || decoded_raw.imm_en ||
                                 fwd_rs2_from_e2m || fwd_rs2_from_m2w || fwd_rs2_from_wb;
    assign fwd_can_bypass_hazard = fwd_can_bypass_rs1 && fwd_can_bypass_rs2;
    
    assign stall_fetch     = !fetch_decode_ready;
    assign stall_decode    = !decode_operand_ready || stall_hazard;
    assign stall_operand   = !operand_exec_ready || fwd_stall_required;
    assign stall_execute   = !exec_mem_ready;
    // Memory stage stalls when LSU is busy processing any memory operation
    // This ensures all thread stores complete before subsequent instructions advance
    assign stall_memory    = !lsu_req_ready;
    assign stall_writeback = 1'b0;  // Writeback never stalls
    
    //=========================================================================
    // Scoreboard Instance (Data Hazard Detection)
    //=========================================================================
    
    // Hazard check: Check at decode stage before issuing instruction
    assign scoreboard_check_valid    = f2d_valid && decode_valid_raw && !illegal_instr_raw;
    assign scoreboard_check_warp_id  = f2d_warp_id;
    assign scoreboard_check_rs1      = decoded_raw.rs1;
    assign scoreboard_check_rs2      = decoded_raw.rs2;
    assign scoreboard_check_rs1_en   = decoded_raw.rs1_en;
    assign scoreboard_check_rs2_en   = decoded_raw.rs2_en && !decoded_raw.imm_en;
    
    // Reservation: Reserve destination register when instruction advances to operand stage
    assign scoreboard_reserve_valid   = d2o_valid && !stall_operand && !warp_flush[d2o_warp_id];
    assign scoreboard_reserve_warp_id = d2o_warp_id;
    assign scoreboard_reserve_rd      = d2o_decoded.rd;
    assign scoreboard_reserve_rd_en   = d2o_decoded.rd_en;
    
    // Completion: Clear scoreboard entry when writeback completes
    assign scoreboard_complete_valid   = m2w_valid && m2w_rd_en;
    assign scoreboard_complete_warp_id = m2w_warp_id;
    assign scoreboard_complete_rd      = m2w_rd;
    
    // Clear warp's scoreboard on termination (EXIT instruction)
    assign scoreboard_clear_warp    = o2e_valid && o2e_decoded.is_exit;
    assign scoreboard_clear_warp_id = o2e_warp_id;
    
    scoreboard #(
        .NUM_WARPS(NUM_WARPS)
    ) u_scoreboard (
        .clk              (clk),
        .rst_n            (rst_n),
        
        // Hazard check
        .check_valid      (scoreboard_check_valid),
        .check_warp_id    (scoreboard_check_warp_id),
        .check_rs1        (scoreboard_check_rs1),
        .check_rs2        (scoreboard_check_rs2),
        .check_rs1_en     (scoreboard_check_rs1_en),
        .check_rs2_en     (scoreboard_check_rs2_en),
        .hazard_detected  (scoreboard_hazard_detected),
        
        // Register reservation
        .reserve_valid    (scoreboard_reserve_valid),
        .reserve_warp_id  (scoreboard_reserve_warp_id),
        .reserve_rd       (scoreboard_reserve_rd),
        .reserve_rd_en    (scoreboard_reserve_rd_en),
        
        // Completion
        .complete_valid   (scoreboard_complete_valid),
        .complete_warp_id (scoreboard_complete_warp_id),
        .complete_rd      (scoreboard_complete_rd),
        
        // Clear warp
        .clear_warp       (scoreboard_clear_warp),
        .clear_warp_id    (scoreboard_clear_warp_id)
    );
    
    //=========================================================================
    // Warp Scheduler Instance
    //=========================================================================
    
    warp_scheduler #(
        .NUM_WARPS(NUM_WARPS)
    ) u_warp_scheduler (
        .clk                 (clk),
        .rst_n               (rst_n),
        
        // Warp activation
        .warp_activate       (dispatch_valid),
        .warp_activate_id    (dispatch_warp_id),
        .warp_activate_pc    (dispatch_pc),
        .warp_activate_mask  (dispatch_mask),
        
        // Warp termination - from execute stage EXIT instruction
        .warp_exit           (o2e_valid && o2e_decoded.is_exit),
        .warp_exit_id        (o2e_warp_id),
        .warp_exit_mask      (o2e_mask),
        
        // Stalls
        .stall_fetch         (stall_fetch),
        .stall_decode        (stall_decode),
        .stall_operand       (stall_operand),
        .stall_execute       (stall_execute),
        .stall_memory        (stall_memory),
        .stall_writeback     (stall_writeback),
        
        // Branch control
        .branch_taken        (branch_taken),
        .branch_warp_id      (o2e_warp_id),
        .branch_target_pc    (branch_target),
        
        // PC update (from fetch unit - PC+4 after instruction enters decode)
        .pc_update_valid     (fetch_pc_advance_valid),
        .pc_update_warp_id   (fetch_pc_advance_warp_id),
        .pc_update_value     (fetch_pc_advance_value),
        
        // Divergence
        .diverge_push        (diverge_push),
        .diverge_warp_id     (diverge_warp_id),
        .diverge_then_mask   (diverge_then_mask),
        .diverge_else        (diverge_else),
        .diverge_else_warp_id(diverge_else_warp_id),
        .diverge_pop         (diverge_pop),
        .diverge_pop_warp_id (diverge_pop_warp_id),
        .decode_is_diverge   (decode_is_diverge),
        .decode_diverge_warp_id(decode_diverge_warp_id),
        
        // Barrier
        .barrier_arrive      (barrier_arrive),
        .barrier_warp_id     (barrier_warp_id),
        .barrier_id          (barrier_id),
        .barrier_release     (barrier_release),
        .barrier_release_id  (barrier_release_id),
        
        // Scheduled output
        .sched_valid         (sched_fetch_valid),
        .sched_ready         (sched_fetch_ready),  // Handshake from fetch
        .sched_warp_id       (sched_fetch_warp_id),
        .sched_pc            (sched_fetch_pc),
        .sched_active_mask   (sched_fetch_mask),
        .sched_warp_state    (sched_warp_state),
        
        // Status
        .warps_active        (warps_active),
        .warps_at_barrier    (warps_at_barrier),
        .all_warps_done      (all_warps_done)
    );
    
    assign dispatch_ready = !sched_fetch_valid || sched_fetch_ready;
    
    //=========================================================================
    // Fetch Unit Instance
    //=========================================================================
    
    fetch_unit #(
        .NUM_WARPS(NUM_WARPS),
        .ICACHE_SIZE(ICACHE_SIZE)
    ) u_fetch_unit (
        .clk                 (clk),
        .rst_n               (rst_n),
        
        // Scheduler interface
        .sched_valid         (sched_fetch_valid),
        .sched_warp_id       (sched_fetch_warp_id),
        .sched_pc            (sched_fetch_pc),
        .sched_active_mask   (sched_fetch_mask),
        .sched_ready         (sched_fetch_ready),
        
        // Decode interface
        .decode_valid        (fetch_decode_valid),
        .decode_instr        (fetch_decode_instr),
        .decode_pc           (fetch_decode_pc),
        .decode_warp_id      (fetch_decode_warp_id),
        .decode_active_mask  (fetch_decode_mask),
        .decode_ready        (fetch_decode_ready),
        
        // Instruction memory interface
        .imem_req_valid      (imem_req_valid),
        .imem_req_addr       (imem_req_addr),
        .imem_req_ready      (imem_req_ready),
        .imem_resp_valid     (imem_resp_valid),
        .imem_resp_data      (imem_resp_data),
        
        // Control
        .warp_flush          (warp_flush),
        .cache_flush         (cache_flush),
        .pc_update_valid     (branch_taken),
        .pc_update_warp_id   (o2e_warp_id),
        .pc_update_value     (branch_target),
        
        // PC advance output (to scheduler)
        .pc_advance_valid    (fetch_pc_advance_valid),
        .pc_advance_warp_id  (fetch_pc_advance_warp_id),
        .pc_advance_value    (fetch_pc_advance_value),
        
        // Status
        .busy                (fetch_busy),
        .warp_fetch_ready    ()  // Unused
    );
    
    //=========================================================================
    // Fetch -> Decode Pipeline Register
    //=========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            f2d_valid   <= 1'b0;
            f2d_instr   <= '0;
            f2d_pc      <= '0;
            f2d_warp_id <= '0;
            f2d_mask    <= '0;
        end else if (warp_flush[fetch_decode_warp_id]) begin
            f2d_valid <= 1'b0;
        end else if (!stall_decode) begin
            f2d_valid   <= fetch_decode_valid;
            f2d_instr   <= fetch_decode_instr;
            f2d_pc      <= fetch_decode_pc;
            f2d_warp_id <= fetch_decode_warp_id;
            f2d_mask    <= fetch_decode_mask;
        end
    end
    
    assign fetch_decode_ready = !stall_decode;
    
    //=========================================================================
    // Decoder Instance
    //=========================================================================
    
    decoded_instr_t decoded_raw;
    logic           decode_valid_raw;
    logic           illegal_instr_raw;
    
    decoder u_decoder (
        .instr        (f2d_instr),
        .instr_valid  (f2d_valid),
        .decoded      (decoded_raw),
        .decode_valid (decode_valid_raw),
        .illegal_instr(illegal_instr_raw)
    );
    
    assign decode_operand_valid   = decode_valid_raw && !illegal_instr_raw;
    assign decode_operand_decoded = decoded_raw;
    assign decode_operand_pc      = f2d_pc;
    assign decode_operand_warp_id = f2d_warp_id;
    assign decode_operand_mask    = f2d_mask;
    assign decode_illegal         = illegal_instr_raw;
    
    // Early divergence detection - tell scheduler when a PUSH/ELSE/POP is decoded
    assign decode_is_diverge = decode_valid_raw && !illegal_instr_raw && 
                               (decoded_raw.is_push || decoded_raw.is_else || decoded_raw.is_pop);
    assign decode_diverge_warp_id = f2d_warp_id;
    
    //=========================================================================
    // Decode -> Operand Pipeline Register
    //=========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d2o_valid   <= 1'b0;
            d2o_decoded <= '0;
            d2o_pc      <= '0;
            d2o_warp_id <= '0;
            d2o_mask    <= '0;
        end else if (warp_flush[f2d_warp_id]) begin
            d2o_valid <= 1'b0;
        end else if (!stall_operand) begin
            d2o_valid   <= decode_operand_valid;
            d2o_decoded <= decode_operand_decoded;
            d2o_pc      <= decode_operand_pc;
            d2o_warp_id <= decode_operand_warp_id;
            d2o_mask    <= decode_operand_mask;
        end
    end
    
    assign decode_operand_ready = !stall_operand;
    
    //=========================================================================
    // Register File Instance
    //=========================================================================
    
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rf_rs1_data;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rf_rs2_data;
    
    // For store instructions, use RD field as store data source (via RS2 port)
    logic [REG_ADDR_WIDTH-1:0] rf_rs2_addr;
    logic is_store_instr;
    assign is_store_instr = (d2o_decoded.opcode == OP_ST) || 
                            (d2o_decoded.opcode == OP_ST32) ||
                            (d2o_decoded.opcode == OP_STS) ||
                            (d2o_decoded.opcode == OP_STS32);
    assign rf_rs2_addr = is_store_instr ? d2o_decoded.rd : d2o_decoded.rs2;
    
    register_file #(
        .NUM_WARPS(NUM_WARPS)
    ) u_register_file (
        .clk        (clk),
        .rst_n      (rst_n),
        
        // Read port - use warp from decode stage
        .warp_id    (d2o_warp_id),
        .rs1_addr   (d2o_decoded.rs1),
        .rs1_data   (rf_rs1_data),
        .rs2_addr   (rf_rs2_addr),  // Use RD for stores, RS2 otherwise
        .rs2_data   (rf_rs2_data),
        
        // Write port - from writeback stage
        .wr_en      (wb_rf_en),
        .wr_mask    (wb_rf_mask),
        .wr_addr    (wb_rf_addr),
        .wr_data    (wb_rf_data),
        .wr_warp_id (wb_rf_warp_id)
    );
    
    //=========================================================================
    // Predicate File Instance
    //=========================================================================
    
    logic [WARP_SIZE-1:0] pf_pred_data;
    logic [WARP_SIZE-1:0] pf_pred_a;
    logic [WARP_SIZE-1:0] pf_pred_b;
    
    predicate_file #(
        .NUM_WARPS(NUM_WARPS)
    ) u_predicate_file (
        .clk        (clk),
        .rst_n      (rst_n),
        
        // Read ports
        .warp_id    (d2o_warp_id),
        .pred_addr  (d2o_decoded.pred),
        .pred_data  (pf_pred_data),
        .pred2_addr (d2o_decoded.rs2[PRED_ADDR_WIDTH-1:0]),
        .pred2_data (pf_pred_b),
        
        // Write port
        .wr_en      (wb_pred_en),
        .wr_mask    (wb_pred_mask),
        .wr_addr    (wb_pred_addr),
        .wr_data    (wb_pred_data),
        .wr_warp_id (wb_pred_warp_id)
    );
    
    // For predicate operations, pred_a typically comes from the same source as predication
    // This is a simplification - a full implementation would add another read port
    assign pf_pred_a = pf_pred_data;
    
    //=========================================================================
    // Special Register File Instance
    //=========================================================================
    
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] sr_data;
    logic [127:0] clock_counter;
    block_config_t block_config;
    
    // Clock counter for special registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clock_counter <= '0;
        else
            clock_counter <= clock_counter + 1;
    end
    
    // Connect block configuration (defaults for now - would come from dispatch unit)
    assign block_config.block_id_x   = '0;
    assign block_config.block_id_y   = '0;
    assign block_config.block_id_z   = '0;
    assign block_config.num_threads  = WARP_SIZE;
    assign block_config.num_blocks_x = 1;
    assign block_config.num_blocks_y = 1;
    assign block_config.num_blocks_z = 1;
    
    special_register_file #(
        .CORE_ID(CORE_ID)
    ) u_special_register_file (
        .clk           (clk),
        .rst_n         (rst_n),
        .warp_id       (d2o_warp_id),
        .block_config  (block_config),
        .sr_addr       (d2o_decoded.rs1[3:0]),  // SR address is in RS1 field
        .sr_data       (sr_data),
        .clock_counter (clock_counter)
    );
    
    //=========================================================================
    // Forwarding Network Instance
    //=========================================================================
    
    // For stores, use RD as the source register for RS2 port
    logic store_rs2_en;
    assign store_rs2_en = is_store_instr;  // Store needs to read from RD
    
    forwarding_network #(
        .NUM_WARPS(NUM_WARPS)
    ) u_forwarding_network (
        .clk                (clk),
        .rst_n              (rst_n),
        
        // Operand fetch stage
        .operand_valid      (d2o_valid),
        .operand_warp_id    (d2o_warp_id),
        .operand_rs1        (d2o_decoded.rs1),
        .operand_rs2        (rf_rs2_addr),  // Use RD for stores
        .operand_rs1_en     (d2o_decoded.rs1_en),
        .operand_rs2_en     ((d2o_decoded.rs2_en && !d2o_decoded.imm_en) || store_rs2_en),
        
        // Register file data
        .rf_rs1_data        (rf_rs1_data),
        .rf_rs2_data        (rf_rs2_data),
        
        // E2M forwarding source
        .e2m_valid          (e2m_valid),
        .e2m_warp_id        (e2m_warp_id),
        .e2m_rd             (e2m_decoded.rd),
        .e2m_rd_en          (e2m_decoded.rd_en),
        .e2m_mask           (e2m_mask),
        .e2m_result         (e2m_result),
        .e2m_is_mem         (e2m_is_mem),
        
        // M2W forwarding source
        .m2w_valid          (m2w_valid),
        .m2w_warp_id        (m2w_warp_id),
        .m2w_rd             (m2w_rd),
        .m2w_rd_en          (m2w_rd_en),
        .m2w_mask           (m2w_mask),
        .m2w_data           (m2w_data),
        
        // WB forwarding source (same as m2w, being written this cycle)
        .wb_valid           (wb_rf_en),
        .wb_warp_id         (wb_rf_warp_id),
        .wb_rd              (wb_rf_addr),
        .wb_rd_en           (wb_rf_en),
        .wb_mask            (wb_rf_mask),
        .wb_data            (wb_rf_data),
        
        // Forwarded data output
        .fwd_rs1_data       (fwd_rs1_data),
        .fwd_rs2_data       (fwd_rs2_data),
        
        // Forwarding status
        .fwd_rs1_from_e2m   (fwd_rs1_from_e2m),
        .fwd_rs1_from_m2w   (fwd_rs1_from_m2w),
        .fwd_rs1_from_wb    (fwd_rs1_from_wb),
        .fwd_rs2_from_e2m   (fwd_rs2_from_e2m),
        .fwd_rs2_from_m2w   (fwd_rs2_from_m2w),
        .fwd_rs2_from_wb    (fwd_rs2_from_wb),
        
        // Load-use stall
        .fwd_stall_required (fwd_stall_required)
    );
    
    //=========================================================================
    // Operand -> Execute Pipeline Register
    //=========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o2e_valid     <= 1'b0;
            o2e_decoded   <= '0;
            o2e_pc        <= '0;
            o2e_warp_id   <= '0;
            o2e_mask      <= '0;
            o2e_rs1_data  <= '0;
            o2e_rs2_data  <= '0;
            o2e_pred_data <= '0;
            o2e_sr_data   <= '0;
            o2e_store_data <= '0;
        end else if (warp_flush[d2o_warp_id]) begin
            o2e_valid <= 1'b0;
        end else if (!stall_execute && !stall_operand) begin
            o2e_valid     <= d2o_valid;
            o2e_decoded   <= d2o_decoded;
            o2e_pc        <= d2o_pc;
            o2e_warp_id   <= d2o_warp_id;
            o2e_mask      <= d2o_mask;
            
            // Operand selection for address computation (operand B):
            // - For stores: immediate is the offset, store data comes from RD (via o2e_store_data)
            // - For loads: immediate is the offset
            // - For other imm_en instructions: immediate is the operand
            if (d2o_decoded.imm_en) begin
                // Use immediate for operand B (for address calculation on loads/stores, 
                // or as actual operand for other immediate instructions)
                for (int t = 0; t < WARP_SIZE; t++) begin
                    o2e_rs2_data[t] <= d2o_decoded.imm;
                end
            end else begin
                // Use forwarded RS2 data
                o2e_rs2_data <= fwd_rs2_data;
            end
            
            // Capture store data from RD register (read via RS2 port when is_store_instr)
            // fwd_rs2_data contains rd value because rf_rs2_addr selects rd for stores
            o2e_store_data <= is_store_instr ? fwd_rs2_data : '0;
            
            // Use forwarded RS1 data (forwarding network handles muxing)
            o2e_rs1_data  <= fwd_rs1_data;
            o2e_pred_data <= pf_pred_data;
            o2e_sr_data   <= sr_data;  // Special register data for MOVSR
        end else if (stall_operand && !stall_execute) begin
            // Clear valid if operand stage is stalled but execute stage can accept
            o2e_valid <= 1'b0;
        end
    end
    
    // Operand stage can pass to execute when execute is not stalled
    assign operand_exec_ready = !stall_execute;
    
    //=========================================================================
    // Execution Unit Instance
    //=========================================================================
    
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] exec_result;
    logic [WARP_SIZE-1:0]                 exec_pred_result;
    logic                                  exec_valid_out;
    logic                                  exec_ready;
    
    // Apply predicate mask to active mask
    logic [WARP_SIZE-1:0] exec_active_mask;
    always_comb begin
        for (int t = 0; t < WARP_SIZE; t++) begin
            if (o2e_decoded.pred_en) begin
                exec_active_mask[t] = o2e_mask[t] && o2e_pred_data[t];
            end else begin
                exec_active_mask[t] = o2e_mask[t];
            end
        end
    end
    
    execution_unit u_execution_unit (
        .clk          (clk),
        .rst_n        (rst_n),
        
        .operand_a    (o2e_rs1_data),
        .operand_b    (o2e_rs2_data),
        .pred_a       (pf_pred_a),
        .pred_b       (pf_pred_b),
        .special_data (o2e_sr_data),  // Special register data for MOVSR
        
        .exec_select  (o2e_decoded.exec_unit),
        .opcode       (o2e_decoded.opcode),
        .func         (o2e_decoded.func),
        .active_mask  (exec_active_mask),
        .valid_in     (o2e_valid),
        
        .result       (exec_result),
        .pred_result  (exec_pred_result),
        .valid_out    (exec_valid_out),
        .ready        (exec_ready)
    );
    
    //=========================================================================
    // Branch Logic
    //=========================================================================
    
    // Simple branch calculation
    logic branch_condition_met;
    
    always_comb begin
        branch_taken = 1'b0;
        branch_target = o2e_pc + 4;  // Default: next instruction
        branch_condition_met = 1'b0;
        
        if (o2e_valid && o2e_decoded.is_branch) begin
            case (o2e_decoded.opcode)
                OP_BRA: begin
                    // Unconditional branch
                    branch_taken = 1'b1;
                    branch_target = o2e_pc + o2e_decoded.imm;
                end
                OP_BRC: begin
                    // Conditional branch - check if any active thread has predicate true
                    branch_condition_met = |(exec_active_mask & o2e_pred_data);
                    branch_taken = branch_condition_met;
                    branch_target = o2e_pc + o2e_decoded.imm;
                end
                default: begin
                    branch_taken = 1'b0;
                end
            endcase
        end
    end
    
    // Flush on branch
    always_comb begin
        warp_flush = '0;
        if (branch_taken) begin
            warp_flush[o2e_warp_id] = 1'b1;
        end
    end
    
    assign cache_flush = 1'b0;  // No cache flush in normal operation
    
    //=========================================================================
    // Divergence Control
    //=========================================================================
    
    always_comb begin
        diverge_push = o2e_valid && o2e_decoded.is_push;
        diverge_warp_id = o2e_warp_id;
        diverge_then_mask = o2e_mask & o2e_pred_data;  // Threads taking "then" path
        
        diverge_else = o2e_valid && o2e_decoded.is_else;
        diverge_else_warp_id = o2e_warp_id;
        
        diverge_pop = o2e_valid && o2e_decoded.is_pop;
        diverge_pop_warp_id = o2e_warp_id;
    end
    
    //=========================================================================
    // Barrier Control
    //=========================================================================
    
    always_comb begin
        barrier_arrive = o2e_valid && o2e_decoded.is_barrier;
        barrier_warp_id = o2e_warp_id;
        barrier_id = o2e_decoded.imm[3:0];
    end
    
    // Barrier release logic (simplified - releases when all warps arrive)
    // In a full implementation, this would be handled by a separate barrier unit
    assign barrier_release = 1'b0;  // Handled by warp_scheduler
    assign barrier_release_id = '0;
    
    //=========================================================================
    // Execute -> Memory Pipeline Register
    //=========================================================================
    
    logic mem_op_flag;
    assign mem_op_flag = (o2e_decoded.exec_unit == EX_LSU);
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            e2m_valid       <= 1'b0;
            e2m_decoded     <= '0;
            e2m_warp_id     <= '0;
            e2m_mask        <= '0;
            e2m_result      <= '0;
            e2m_pred_result <= '0;
            e2m_is_mem      <= 1'b0;
            e2m_store_data  <= '0;
        end else if (warp_flush[o2e_warp_id]) begin
            e2m_valid <= 1'b0;
        end else if (!stall_memory) begin
            e2m_valid       <= exec_valid_out && !o2e_decoded.is_branch && 
                               !o2e_decoded.is_exit && !o2e_decoded.is_barrier;
            e2m_decoded     <= o2e_decoded;
            e2m_warp_id     <= o2e_warp_id;
            e2m_mask        <= exec_active_mask;
            e2m_result      <= exec_result;
            e2m_pred_result <= exec_pred_result;
            e2m_is_mem      <= mem_op_flag;
            e2m_store_data  <= o2e_store_data;  // Store data from RD register (captured in o2e stage)
        end
    end
    
    assign exec_mem_ready = !stall_memory && exec_ready;
    
    //=========================================================================
    // Load/Store Unit Instance
    //=========================================================================
    
    // Shared memory interface (directly connected to shared memory)
    logic                                      smem_req_valid;
    logic                                      smem_req_we;
    logic [WARP_SIZE-1:0]                      smem_req_mask;
    logic [WARP_SIZE-1:0][13:0]                smem_req_addr;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]      smem_req_wdata;
    logic [WARP_SIZE-1:0][7:0]                 smem_req_wstrb;
    logic                                      smem_req_ready;
    logic                                      smem_resp_valid;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]      smem_resp_rdata;
    
    lsu u_lsu (
        .clk             (clk),
        .rst_n           (rst_n),
        
        // Request interface
        .req_valid       (e2m_valid && e2m_is_mem),
        .req_warp_id     (e2m_warp_id),
        .req_active_mask (e2m_mask),
        .req_pred_mask   ({WARP_SIZE{1'b1}}),  // Already applied
        .req_opcode      (e2m_decoded.opcode),
        .req_func        (e2m_decoded.func),   // Function code for atomics
        .req_rd          (e2m_decoded.rd),
        .req_base_addr   (e2m_result),  // Address calculated in execute
        .req_offset      (13'b0),  // Offset already applied
        .req_store_data  (e2m_store_data),  // Store data (captured from RD register)
        .req_ready       (lsu_req_ready),
        
        // Response interface
        .resp_valid      (lsu_wb_valid),
        .resp_warp_id    (lsu_wb_warp_id),
        .resp_rd         (lsu_wb_rd),
        .resp_mask       (lsu_wb_mask),
        .resp_data       (lsu_wb_data),
        .resp_ready      (1'b1),  // Always accept
        
        // Global memory interface
        .gmem_req_valid  (lsu_gmem_req_valid),
        .gmem_req_we     (lsu_gmem_req_we),
        .gmem_req_addr   (lsu_gmem_req_addr),
        .gmem_req_wdata  (lsu_gmem_req_wdata),
        .gmem_req_wstrb  (lsu_gmem_req_wstrb),
        .gmem_req_ready  (lsu_gmem_req_ready),
        .gmem_resp_valid (lsu_gmem_resp_valid),
        .gmem_resp_rdata (lsu_gmem_resp_rdata),
        .gmem_store_complete (lsu_gmem_store_complete),
        
        // Shared memory interface
        .smem_req_valid  (smem_req_valid),
        .smem_req_we     (smem_req_we),
        .smem_req_mask   (smem_req_mask),
        .smem_req_addr   (smem_req_addr),
        .smem_req_wdata  (smem_req_wdata),
        .smem_req_wstrb  (smem_req_wstrb),
        .smem_req_ready  (smem_req_ready),
        .smem_resp_valid (smem_resp_valid),
        .smem_resp_rdata (smem_resp_rdata)
    );
    
    //=========================================================================
    // Shared Memory Instance
    //=========================================================================
    
    shared_memory #(
        .NUM_BANKS (WARP_SIZE),
        .BANK_SIZE (SHARED_MEM_SIZE / WARP_SIZE / 8)  // Convert to words per bank
    ) u_shared_memory (
        .clk       (clk),
        .rst_n     (rst_n),
        .req_valid (smem_req_valid),
        .req_we    (smem_req_we),
        .req_mask  (smem_req_mask),
        .req_addr  (smem_req_addr),
        .req_wdata (smem_req_wdata),
        .req_wstrb (smem_req_wstrb),
        .req_ready (smem_req_ready),
        .resp_valid(smem_resp_valid),
        .resp_rdata(smem_resp_rdata)
    );
    
    //=========================================================================
    // Global Memory Interface Adapter (Simplified)
    //=========================================================================
    
    // Convert simple interface to AXI-like interface
    // This is a simplified adapter - a full implementation would handle
    // pipelining, burst transactions, and proper AXI protocol
    
    typedef enum logic [2:0] {
        GMEM_IDLE,
        GMEM_READ_ADDR,
        GMEM_READ_DATA,
        GMEM_WRITE_ADDR,
        GMEM_WRITE_DATA,
        GMEM_WRITE_RESP
    } gmem_state_t;
    
    gmem_state_t gmem_state;
    logic [ADDR_WIDTH-1:0] gmem_addr_r;
    logic [DATA_WIDTH-1:0] gmem_wdata_r;
    logic [7:0] gmem_wstrb_r;
    logic gmem_we_r;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gmem_state <= GMEM_IDLE;
            gmem_addr_r <= '0;
            gmem_wdata_r <= '0;
            gmem_wstrb_r <= '0;
            gmem_we_r <= 1'b0;
        end else begin
            case (gmem_state)
                GMEM_IDLE: begin
                    if (lsu_gmem_req_valid && lsu_gmem_req_ready) begin
                        gmem_addr_r <= lsu_gmem_req_addr;
                        gmem_wdata_r <= lsu_gmem_req_wdata;
                        gmem_wstrb_r <= lsu_gmem_req_wstrb;
                        gmem_we_r <= lsu_gmem_req_we;
                        if (lsu_gmem_req_we) begin
                            gmem_state <= GMEM_WRITE_ADDR;
                        end else begin
                            gmem_state <= GMEM_READ_ADDR;
                        end
                    end
                end
                
                GMEM_READ_ADDR: begin
                    if (gmem_arready) begin
                        gmem_state <= GMEM_READ_DATA;
                    end
                end
                
                GMEM_READ_DATA: begin
                    if (gmem_rvalid && gmem_rlast) begin
                        gmem_state <= GMEM_IDLE;
                    end
                end
                
                GMEM_WRITE_ADDR: begin
                    if (gmem_awready) begin
                        gmem_state <= GMEM_WRITE_DATA;
                    end
                end
                
                GMEM_WRITE_DATA: begin
                    if (gmem_wready) begin
                        gmem_state <= GMEM_WRITE_RESP;
                    end
                end
                
                GMEM_WRITE_RESP: begin
                    if (gmem_bvalid) begin
                        gmem_state <= GMEM_IDLE;
                    end
                end
                
                default: gmem_state <= GMEM_IDLE;
            endcase
        end
    end
    
    // AXI Read Address Channel
    assign gmem_arvalid = (gmem_state == GMEM_READ_ADDR);
    assign gmem_araddr  = gmem_addr_r;
    assign gmem_arlen   = 8'd0;  // Single beat
    assign gmem_arsize  = 3'b011;  // 8 bytes
    
    // AXI Read Data Channel
    assign gmem_rready = (gmem_state == GMEM_READ_DATA);
    
    // AXI Write Address Channel
    assign gmem_awvalid = (gmem_state == GMEM_WRITE_ADDR);
    assign gmem_awaddr  = gmem_addr_r;
    assign gmem_awlen   = 8'd0;  // Single beat
    assign gmem_awsize  = 3'b011;  // 8 bytes
    
    // AXI Write Data Channel
    assign gmem_wvalid = (gmem_state == GMEM_WRITE_DATA);
    assign gmem_wdata  = gmem_wdata_r;
    assign gmem_wstrb  = gmem_wstrb_r;
    assign gmem_wlast  = 1'b1;  // Single beat
    
    // AXI Write Response Channel
    assign gmem_bready = (gmem_state == GMEM_WRITE_RESP);
    
    // LSU interface signals
    assign lsu_gmem_req_ready = (gmem_state == GMEM_IDLE);
    assign lsu_gmem_resp_valid = gmem_rvalid && (gmem_state == GMEM_READ_DATA);
    assign lsu_gmem_resp_rdata = gmem_rdata;
    assign lsu_gmem_store_complete = gmem_bvalid && (gmem_state == GMEM_WRITE_RESP);
    
    //=========================================================================
    // Memory -> Writeback Pipeline Register
    //=========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m2w_valid      <= 1'b0;
            m2w_warp_id    <= '0;
            m2w_rd         <= '0;
            m2w_mask       <= '0;
            m2w_data       <= '0;
            m2w_pred_data  <= '0;
            m2w_rd_en      <= 1'b0;
            m2w_pred_wr_en <= 1'b0;
            m2w_pred_addr  <= '0;
        end else begin
            // Select between ALU result and LSU result
            if (lsu_wb_valid) begin
                // LSU result has priority
                m2w_valid      <= 1'b1;
                m2w_warp_id    <= lsu_wb_warp_id;
                m2w_rd         <= lsu_wb_rd;
                m2w_mask       <= lsu_wb_mask;
                m2w_data       <= lsu_wb_data;
                m2w_rd_en      <= 1'b1;
                m2w_pred_wr_en <= 1'b0;
                m2w_pred_data  <= '0;
                m2w_pred_addr  <= '0;
            end else if (e2m_valid && !e2m_is_mem) begin
                // ALU/Shift/Mul result
                m2w_valid      <= 1'b1;
                m2w_warp_id    <= e2m_warp_id;
                m2w_rd         <= e2m_decoded.rd;
                m2w_mask       <= e2m_mask;
                m2w_data       <= e2m_result;
                m2w_rd_en      <= e2m_decoded.rd_en;
                m2w_pred_wr_en <= e2m_decoded.pred_wr_en;
                m2w_pred_data  <= e2m_pred_result;
                m2w_pred_addr  <= e2m_decoded.rd[PRED_ADDR_WIDTH-1:0];
            end else begin
                m2w_valid <= 1'b0;
            end
        end
    end
    
    //=========================================================================
    // Writeback Stage
    //=========================================================================
    
    // Register file writeback
    assign wb_rf_en      = m2w_valid && m2w_rd_en;
    assign wb_rf_warp_id = m2w_warp_id;
    assign wb_rf_addr    = m2w_rd;
    assign wb_rf_mask    = m2w_mask;
    assign wb_rf_data    = m2w_data;
    
    // Predicate file writeback
    assign wb_pred_en      = m2w_valid && m2w_pred_wr_en;
    assign wb_pred_warp_id = m2w_warp_id;
    assign wb_pred_addr    = m2w_pred_addr;
    assign wb_pred_mask    = m2w_mask;
    assign wb_pred_data    = m2w_pred_data;
    
    //=========================================================================
    // Core Status
    //=========================================================================
    
    assign core_busy = fetch_busy || |warps_active || 
                       f2d_valid || d2o_valid || o2e_valid || 
                       e2m_valid || m2w_valid;

    //=========================================================================
    // Debug: Pipeline Trace
    //=========================================================================
    
    `ifdef DEBUG_PIPELINE
    always_ff @(posedge clk) begin
        if (rst_n) begin
            // Only print when something is happening
            if (fetch_decode_valid || f2d_valid || d2o_valid || o2e_valid || e2m_valid || m2w_valid) begin
                $display("t=%0t PIPE: f_dv=%b f2d=%b d2o=%b o2e=%b e2m=%b m2w=%b | stall(d=%b o=%b e=%b m=%b) | opc=%0d rd=%0d", 
                         $time, fetch_decode_valid, f2d_valid, d2o_valid, o2e_valid, e2m_valid, m2w_valid,
                         stall_decode, stall_operand, stall_execute, stall_memory,
                         f2d_valid ? f2d_instr[31:26] : 0,
                         f2d_valid ? decoded_raw.rd : 0);
            end
            
            // Debug stall reasons when stalled
            if (stall_decode && f2d_valid && $time > 1700000) begin
                $display("t=%0t STALL: hazard=%b bypass=%b fwd_stall=%b scoreboard=%b",
                         $time, stall_hazard, fwd_can_bypass_hazard, fwd_stall_required, scoreboard_hazard_detected);
            end
            
            if (decode_valid_raw && !illegal_instr_raw) begin
                $display("t=%0t DECODE: valid instr=0x%08x opc=%0d rd=%0d rs1=%0d imm=0x%x mask=%b",
                         $time, f2d_instr, decoded_raw.opcode, decoded_raw.rd, decoded_raw.rs1, decoded_raw.imm, f2d_mask);
            end
            
            // Debug operand stage - check when ST instruction is in d2o
            if (d2o_valid && (d2o_decoded.opcode == OP_ST || d2o_decoded.opcode == OP_ST32)) begin
                $display("t=%0t OPND_STORE: is_store=%b rf_rs2_addr=%0d(rd=%0d) rf_rs2_data[0..3]=%0d,%0d,%0d,%0d",
                         $time, is_store_instr, rf_rs2_addr, d2o_decoded.rd, rf_rs2_data[0], rf_rs2_data[1], rf_rs2_data[2], rf_rs2_data[3]);
            end
            
            if (illegal_instr_raw && f2d_valid) begin
                $display("t=%0t DECODE: ILLEGAL instr=0x%08x opc=%0d",
                         $time, f2d_instr, f2d_instr[31:26]);
            end
            
            if (o2e_valid) begin
                $display("t=%0t EXEC: warp=%0d opc=%0d rd=%0d rd_en=%b mask=%b exec_vld=%b exec_rdy=%b",
                         $time, o2e_warp_id, o2e_decoded.opcode, o2e_decoded.rd, o2e_decoded.rd_en, 
                         o2e_mask, exec_valid_out, exec_ready);
                // Debug MOVSR: show exec_unit and sr_data
                if (o2e_decoded.exec_unit == EX_SPECIAL) begin
                    $display("t=%0t MOVSR: exec_unit=SPECIAL sr_data[0..3]=%0d,%0d,%0d,%0d o2e_sr_data[0]=%0d",
                             $time, o2e_sr_data[0], o2e_sr_data[1], o2e_sr_data[2], o2e_sr_data[3], o2e_sr_data[0]);
                end
                // Debug store data
                if (o2e_decoded.opcode == OP_ST || o2e_decoded.opcode == OP_ST32) begin
                    $display("t=%0t STORE_DATA: o2e_rs2_data[0..3]=%0d,%0d,%0d,%0d rs2_data[4..7]=%0d,%0d,%0d,%0d",
                             $time, o2e_rs2_data[0], o2e_rs2_data[1], o2e_rs2_data[2], o2e_rs2_data[3],
                             o2e_rs2_data[4], o2e_rs2_data[5], o2e_rs2_data[6], o2e_rs2_data[7]);
                end
            end
            
            if (m2w_valid) begin
                $display("t=%0t WB: warp=%0d rd=r%0d en=%b mask=%b data[0..7]=%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                         $time, m2w_warp_id, m2w_rd, m2w_rd_en, m2w_mask, 
                         m2w_data[0], m2w_data[1], m2w_data[2], m2w_data[3],
                         m2w_data[4], m2w_data[5], m2w_data[6], m2w_data[7]);
            end
            
            if (o2e_valid && o2e_decoded.is_exit) begin
                $display("t=%0t WARP_EXIT: warp=%0d mask=%b", $time, o2e_warp_id, o2e_mask);
            end
        end
    end
    `endif

    // Debug: gmem adapter
    `ifdef DEBUG_GMEM
    always @(posedge clk) begin
        if (rst_n && (lsu_gmem_req_valid || gmem_state != GMEM_IDLE)) begin
            $display("t=%0t GMEM: state=%0d lsu_valid=%b lsu_ready=%b we=%b addr=0x%h wdata=0x%h awready=%b wready=%b bvalid=%b",
                     $time, gmem_state, lsu_gmem_req_valid, lsu_gmem_req_ready, lsu_gmem_req_we, lsu_gmem_req_addr,
                     lsu_gmem_req_wdata, gmem_awready, gmem_wready, gmem_bvalid);
        end
    end
    `endif

endmodule
