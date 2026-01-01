//=============================================================================
// GPGPU-1 Warp Shuffle Unit
//=============================================================================
// File:        warp_shuffle.sv
// Description: Implements warp-level shuffle operations for efficient
//              intra-warp communication. Supports multiple shuffle modes:
//              - SHFL_IDX:   Direct index shuffle (srcLane = RS2 % width)
//              - SHFL_UP:    Shift up (srcLane = lane - delta)
//              - SHFL_DOWN:  Shift down (srcLane = lane + delta)
//              - SHFL_BFLY:  Butterfly/XOR shuffle (srcLane = lane ^ mask)
//              - SHFL_CLAMP: Clamped up (srcLane = max(lane - delta, 0))
//              - SHFL_WRAP:  Wrapped (srcLane = (lane + delta) % width)
//
// Encoding (R-format):
//   [31:26] OPCODE = 0x34 (OP_SHFL)
//   [25:21] RD     = destination register
//   [20:16] RS1    = source register (data to shuffle)
//   [15:11] RS2    = lane index/delta/mask register
//   [10:8]  PRED   = predicate register
//   [7:5]   WIDTH  = shuffle width (0=full warp, 1=2, 2=4, 3=8 lanes)
//   [4:3]   reserved
//   [2:0]   FUNC   = shuffle function (shfl_func_t)
//
// Version:     1.0
// Date:        January 1, 2026
//=============================================================================

`include "gpgpu_defines.svh"

module warp_shuffle
    import gpgpu_pkg::*;
#(
    parameter int NUM_LANES = WARP_SIZE  // 8 threads per warp
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    //=========================================================================
    // Control Interface
    //=========================================================================
    
    input  logic                    valid,
    input  logic [2:0]              shfl_func,    // Shuffle function (shfl_func_t)
    input  logic [2:0]              shfl_width,   // Width encoding (0=8,1=2,2=4,3=8)
    input  logic [NUM_LANES-1:0]    active_mask,  // Active thread mask
    
    //=========================================================================
    // Data Interface
    //=========================================================================
    
    // Source data from all lanes (RS1)
    input  logic [NUM_LANES-1:0][DATA_WIDTH-1:0] src_data,
    
    // Lane selector from all lanes (RS2) - can be index, delta, or mask
    input  logic [NUM_LANES-1:0][DATA_WIDTH-1:0] lane_sel,
    
    // Result data for all lanes
    output logic [NUM_LANES-1:0][DATA_WIDTH-1:0] result,
    
    // Valid mask - which lanes received valid data
    output logic [NUM_LANES-1:0]    result_valid_mask,
    
    //=========================================================================
    // Status
    //=========================================================================
    
    output logic                    ready,
    output logic                    done
);

    //=========================================================================
    // Width Decoding
    //=========================================================================
    
    // Decode shuffle width - determines the "segment" size
    // 0 = full warp (8 lanes), 1 = 2 lanes, 2 = 4 lanes, 3 = 8 lanes
    logic [3:0] width;
    
    always_comb begin
        case (shfl_width)
            3'b000:  width = 4'd8;  // Full warp
            3'b001:  width = 4'd2;  // 2 lanes per segment
            3'b010:  width = 4'd4;  // 4 lanes per segment
            3'b011:  width = 4'd8;  // 8 lanes per segment
            default: width = 4'd8;  // Default to full warp
        endcase
    end
    
    // Width mask for modulo operations
    logic [2:0] width_mask;
    assign width_mask = width[2:0] - 3'd1;  // e.g., width=8 -> mask=7
    
    //=========================================================================
    // Source Lane Calculation
    //=========================================================================
    
    // For each destination lane, calculate the source lane
    logic [NUM_LANES-1:0][2:0] src_lane;
    logic [NUM_LANES-1:0]      lane_valid;  // Is source lane within valid range?
    
    always_comb begin
        for (int i = 0; i < NUM_LANES; i++) begin
            // Get lane selector value (only lower bits matter)
            logic [2:0] sel_val;
            logic signed [3:0] lane_signed;
            logic signed [3:0] result_signed;
            logic [2:0] segment_base;
            logic [2:0] lane_in_segment;
            
            sel_val = lane_sel[i][2:0];
            lane_signed = $signed({1'b0, i[2:0]});
            segment_base = i[2:0] & ~width_mask;  // Base of current segment
            lane_in_segment = i[2:0] & width_mask;  // Position within segment
            
            case (shfl_func_t'(shfl_func))
                SHFL_IDX: begin
                    // Direct index: srcLane = sel_val % width (within segment)
                    src_lane[i] = segment_base | (sel_val & width_mask);
                    lane_valid[i] = 1'b1;  // Always valid for indexed
                end
                
                SHFL_UP: begin
                    // Shift up: srcLane = lane - delta
                    // Source lane is lower, invalid if goes below segment base
                    result_signed = lane_signed - $signed({1'b0, sel_val});
                    if (result_signed < $signed({1'b0, segment_base})) begin
                        src_lane[i] = i[2:0];  // Return own value
                        lane_valid[i] = 1'b0;  // Invalid - no source
                    end else begin
                        src_lane[i] = result_signed[2:0];
                        lane_valid[i] = 1'b1;
                    end
                end
                
                SHFL_DOWN: begin
                    // Shift down: srcLane = lane + delta
                    // Source lane is higher, invalid if goes above segment end
                    logic [3:0] result_lane;  // 4-bit to detect overflow
                    logic [2:0] segment_end_lane;
                    segment_end_lane = segment_base | width_mask;
                    result_lane = {1'b0, i[2:0]} + {1'b0, sel_val};
                    // Check if result exceeds segment end (unsigned comparison)
                    if (result_lane > {1'b0, segment_end_lane}) begin
                        src_lane[i] = i[2:0];  // Return own value
                        lane_valid[i] = 1'b0;  // Invalid - no source
                    end else begin
                        src_lane[i] = result_lane[2:0];
                        lane_valid[i] = 1'b1;
                    end
                end
                
                SHFL_BFLY: begin
                    // Butterfly (XOR): srcLane = lane ^ mask
                    // XOR with mask, stays within segment if mask < width
                    src_lane[i] = segment_base | ((lane_in_segment ^ sel_val) & width_mask);
                    lane_valid[i] = 1'b1;  // Always valid for butterfly
                end
                
                SHFL_CLAMP: begin
                    // Clamped up: srcLane = max(lane - delta, segment_base)
                    result_signed = lane_signed - $signed({1'b0, sel_val});
                    if (result_signed < $signed({1'b0, segment_base})) begin
                        src_lane[i] = segment_base;  // Clamp to segment base
                    end else begin
                        src_lane[i] = result_signed[2:0];
                    end
                    lane_valid[i] = 1'b1;  // Always valid for clamped
                end
                
                SHFL_WRAP: begin
                    // Wrapped: srcLane = (lane + delta) % width (within segment)
                    src_lane[i] = segment_base | ((lane_in_segment + sel_val) & width_mask);
                    lane_valid[i] = 1'b1;  // Always valid for wrapped
                end
                
                default: begin
                    src_lane[i] = i[2:0];  // Identity
                    lane_valid[i] = 1'b0;
                end
            endcase
        end
    end
    
    //=========================================================================
    // Data Shuffle (Crossbar)
    //=========================================================================
    
    always_comb begin
        for (int i = 0; i < NUM_LANES; i++) begin
            if (active_mask[i] && valid) begin
                // Get data from source lane
                result[i] = src_data[src_lane[i]];
                
                // Result is valid if source lane is active and in valid range
                result_valid_mask[i] = lane_valid[i] && active_mask[src_lane[i]];
            end else begin
                // Inactive lanes get zero
                result[i] = '0;
                result_valid_mask[i] = 1'b0;
            end
        end
    end
    
    //=========================================================================
    // Control Logic
    //=========================================================================
    
    // Shuffle is combinational, always ready
    assign ready = 1'b1;
    assign done  = valid;

endmodule


//=============================================================================
// Warp Shuffle Wrapper for GPU Core Integration
//=============================================================================
// This module wraps the shuffle unit with pipeline registers for integration

module warp_shuffle_unit
    import gpgpu_pkg::*;
#(
    parameter int NUM_LANES = WARP_SIZE
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    //=========================================================================
    // Execute Stage Interface
    //=========================================================================
    
    input  logic                    req_valid,
    output logic                    req_ready,
    
    input  decoded_instr_t          decoded,
    input  logic [NUM_LANES-1:0]    active_mask,
    input  logic [NUM_LANES-1:0][DATA_WIDTH-1:0] rs1_data,  // Source data
    input  logic [NUM_LANES-1:0][DATA_WIDTH-1:0] rs2_data,  // Lane selector
    
    //=========================================================================
    // Result Interface
    //=========================================================================
    
    output logic                    resp_valid,
    output logic [NUM_LANES-1:0][DATA_WIDTH-1:0] result,
    output logic [NUM_LANES-1:0]    result_mask  // Which lanes have valid results
);

    //=========================================================================
    // Shuffle Function and Width Extraction
    //=========================================================================
    
    // Extract shuffle function from func field bits [2:0]
    logic [2:0] shfl_func;
    assign shfl_func = decoded.func[2:0];
    
    // Extract shuffle width from func field bits [7:5]
    logic [2:0] shfl_width;
    assign shfl_width = decoded.func[7:5];
    
    //=========================================================================
    // Shuffle Core Instance
    //=========================================================================
    
    logic shuffle_ready;
    logic shuffle_done;
    
    warp_shuffle #(
        .NUM_LANES(NUM_LANES)
    ) u_shuffle (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .valid           (req_valid && decoded.is_shuffle),
        .shfl_func       (shfl_func),
        .shfl_width      (shfl_width),
        .active_mask     (active_mask),
        
        .src_data        (rs1_data),
        .lane_sel        (rs2_data),
        
        .result          (result),
        .result_valid_mask(result_mask),
        
        .ready           (shuffle_ready),
        .done            (shuffle_done)
    );
    
    //=========================================================================
    // Control
    //=========================================================================
    
    assign req_ready  = shuffle_ready;
    assign resp_valid = shuffle_done;

endmodule
