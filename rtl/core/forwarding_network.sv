//=============================================================================
// GPGPU-1 Forwarding Network
//=============================================================================
// File:        forwarding_network.sv
// Description: Data forwarding network to reduce pipeline stalls due to RAW
//              hazards. Forwards results from Execute, Memory, and Writeback
//              stages back to the Operand Fetch stage.
//
// Forwarding Sources (in priority order):
//   1. Execute stage result (E2M) - 1 cycle latency
//   2. Memory stage result (M2W)  - 2 cycle latency
//   3. Writeback stage (WB)       - 3 cycle latency (being written this cycle)
//
// Note: Forwarding only occurs for same-warp dependencies. Cross-warp
//       dependencies are handled by the warp scheduler.
//
// Version:     1.0
// Date:        January 1, 2026
//=============================================================================

`default_nettype none

`include "gpgpu_defines.svh"

module forwarding_network
    import gpgpu_pkg::*;
#(
    parameter int NUM_WARPS = 8
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    //=========================================================================
    // Operand Fetch Stage - Source Registers
    //=========================================================================
    
    input  logic                            operand_valid,
    input  logic [WARP_ID_WIDTH-1:0]        operand_warp_id,
    input  logic [REG_ADDR_WIDTH-1:0]       operand_rs1,
    input  logic [REG_ADDR_WIDTH-1:0]       operand_rs2,
    input  logic                            operand_rs1_en,
    input  logic                            operand_rs2_en,
    
    // Original register file data
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rf_rs1_data,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rf_rs2_data,
    
    //=========================================================================
    // Execute Stage - Forwarding Source 1 (highest priority)
    //=========================================================================
    
    input  logic                            e2m_valid,
    input  logic [WARP_ID_WIDTH-1:0]        e2m_warp_id,
    input  logic [REG_ADDR_WIDTH-1:0]       e2m_rd,
    input  logic                            e2m_rd_en,
    input  logic [WARP_SIZE-1:0]            e2m_mask,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] e2m_result,
    input  logic                            e2m_is_mem,      // Memory op - result not ready
    
    //=========================================================================
    // Memory Stage - Forwarding Source 2
    //=========================================================================
    
    input  logic                            m2w_valid,
    input  logic [WARP_ID_WIDTH-1:0]        m2w_warp_id,
    input  logic [REG_ADDR_WIDTH-1:0]       m2w_rd,
    input  logic                            m2w_rd_en,
    input  logic [WARP_SIZE-1:0]            m2w_mask,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] m2w_data,
    
    //=========================================================================
    // Writeback Stage - Forwarding Source 3 (lowest priority)
    //=========================================================================
    
    input  logic                            wb_valid,
    input  logic [WARP_ID_WIDTH-1:0]        wb_warp_id,
    input  logic [REG_ADDR_WIDTH-1:0]       wb_rd,
    input  logic                            wb_rd_en,
    input  logic [WARP_SIZE-1:0]            wb_mask,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] wb_data,
    
    //=========================================================================
    // Forwarded Output Data
    //=========================================================================
    
    output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] fwd_rs1_data,
    output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] fwd_rs2_data,
    
    // Forwarding status (for debugging/performance counters)
    output logic                            fwd_rs1_from_e2m,
    output logic                            fwd_rs1_from_m2w,
    output logic                            fwd_rs1_from_wb,
    output logic                            fwd_rs2_from_e2m,
    output logic                            fwd_rs2_from_m2w,
    output logic                            fwd_rs2_from_wb,
    
    // Stall required (when forwarding not possible, e.g., load-use)
    output logic                            fwd_stall_required
);

    //=========================================================================
    // Forwarding Match Detection
    //=========================================================================
    
    // RS1 forwarding matches (warp must match, register must match, must be valid)
    logic rs1_match_e2m, rs1_match_m2w, rs1_match_wb;
    logic rs2_match_e2m, rs2_match_m2w, rs2_match_wb;
    
    // E2M match - can't forward if it's a memory operation (load hasn't completed)
    assign rs1_match_e2m = operand_valid && operand_rs1_en && 
                           e2m_valid && e2m_rd_en && !e2m_is_mem &&
                           (operand_warp_id == e2m_warp_id) &&
                           (operand_rs1 == e2m_rd) && (operand_rs1 != '0);
    
    assign rs2_match_e2m = operand_valid && operand_rs2_en && 
                           e2m_valid && e2m_rd_en && !e2m_is_mem &&
                           (operand_warp_id == e2m_warp_id) &&
                           (operand_rs2 == e2m_rd) && (operand_rs2 != '0);
    
    // M2W match
    assign rs1_match_m2w = operand_valid && operand_rs1_en && 
                           m2w_valid && m2w_rd_en &&
                           (operand_warp_id == m2w_warp_id) &&
                           (operand_rs1 == m2w_rd) && (operand_rs1 != '0);
    
    assign rs2_match_m2w = operand_valid && operand_rs2_en && 
                           m2w_valid && m2w_rd_en &&
                           (operand_warp_id == m2w_warp_id) &&
                           (operand_rs2 == m2w_rd) && (operand_rs2 != '0);
    
    // WB match
    assign rs1_match_wb = operand_valid && operand_rs1_en && 
                          wb_valid && wb_rd_en &&
                          (operand_warp_id == wb_warp_id) &&
                          (operand_rs1 == wb_rd) && (operand_rs1 != '0);
    
    assign rs2_match_wb = operand_valid && operand_rs2_en && 
                          wb_valid && wb_rd_en &&
                          (operand_warp_id == wb_warp_id) &&
                          (operand_rs2 == wb_rd) && (operand_rs2 != '0);
    
    //=========================================================================
    // Load-Use Hazard Detection
    //=========================================================================
    
    // Load-use hazard: operand depends on E2M which is a memory operation
    // Must stall because load data isn't available yet
    logic rs1_load_use, rs2_load_use;
    
    assign rs1_load_use = operand_valid && operand_rs1_en && 
                          e2m_valid && e2m_rd_en && e2m_is_mem &&
                          (operand_warp_id == e2m_warp_id) &&
                          (operand_rs1 == e2m_rd) && (operand_rs1 != '0);
    
    assign rs2_load_use = operand_valid && operand_rs2_en && 
                          e2m_valid && e2m_rd_en && e2m_is_mem &&
                          (operand_warp_id == e2m_warp_id) &&
                          (operand_rs2 == e2m_rd) && (operand_rs2 != '0);
    
    // Stall required for load-use hazards
    assign fwd_stall_required = rs1_load_use || rs2_load_use;
    
    //=========================================================================
    // Forwarding Source Selection (Priority: E2M > M2W > WB > RF)
    //=========================================================================
    
    // RS1 forwarding selection
    assign fwd_rs1_from_e2m = rs1_match_e2m;
    assign fwd_rs1_from_m2w = rs1_match_m2w && !rs1_match_e2m;
    assign fwd_rs1_from_wb  = rs1_match_wb && !rs1_match_e2m && !rs1_match_m2w;
    
    // RS2 forwarding selection
    assign fwd_rs2_from_e2m = rs2_match_e2m;
    assign fwd_rs2_from_m2w = rs2_match_m2w && !rs2_match_e2m;
    assign fwd_rs2_from_wb  = rs2_match_wb && !rs2_match_e2m && !rs2_match_m2w;
    
    //=========================================================================
    // Forwarded Data Muxing - RS1
    //=========================================================================
    
    always_comb begin
        if (rs1_match_e2m) begin
            // Forward from Execute stage
            for (int t = 0; t < WARP_SIZE; t++) begin
                fwd_rs1_data[t] = e2m_mask[t] ? e2m_result[t] : rf_rs1_data[t];
            end
        end else if (rs1_match_m2w) begin
            // Forward from Memory stage
            for (int t = 0; t < WARP_SIZE; t++) begin
                fwd_rs1_data[t] = m2w_mask[t] ? m2w_data[t] : rf_rs1_data[t];
            end
        end else if (rs1_match_wb) begin
            // Forward from Writeback stage
            for (int t = 0; t < WARP_SIZE; t++) begin
                fwd_rs1_data[t] = wb_mask[t] ? wb_data[t] : rf_rs1_data[t];
            end
        end else begin
            // No forwarding - use register file data
            fwd_rs1_data = rf_rs1_data;
        end
    end
    
    //=========================================================================
    // Forwarded Data Muxing - RS2
    //=========================================================================
    
    always_comb begin
        if (rs2_match_e2m) begin
            // Forward from Execute stage
            for (int t = 0; t < WARP_SIZE; t++) begin
                fwd_rs2_data[t] = e2m_mask[t] ? e2m_result[t] : rf_rs2_data[t];
            end
        end else if (rs2_match_m2w) begin
            // Forward from Memory stage
            for (int t = 0; t < WARP_SIZE; t++) begin
                fwd_rs2_data[t] = m2w_mask[t] ? m2w_data[t] : rf_rs2_data[t];
            end
        end else if (rs2_match_wb) begin
            // Forward from Writeback stage
            for (int t = 0; t < WARP_SIZE; t++) begin
                fwd_rs2_data[t] = wb_mask[t] ? wb_data[t] : rf_rs2_data[t];
            end
        end else begin
            // No forwarding - use register file data
            fwd_rs2_data = rf_rs2_data;
        end
    end

endmodule
