//=============================================================================
// GPGPU-1 Warp Vote Unit
//=============================================================================
// File:        warp_vote.sv
// Description: Implements warp-level voting operations for collective
//              thread decisions within a warp. These operations allow
//              threads to communicate simple boolean results.
//              
// Operations:
//   - VOTE.ANY:    Returns 1 if any active thread has predicate true
//   - VOTE.ALL:    Returns 1 if all active threads have predicate true
//   - VOTE.NONE:   Returns 1 if no active thread has predicate true
//   - VOTE.BALLOT: Returns bitmask of which threads have predicate true
//   - VOTE.POPC:   Returns count of threads with predicate true
//
// Encoding (Format M):
//   [31:26] OPCODE = 0x19 (OP_VOTE)
//   [25:21] RD     = destination register (for BALLOT/POPC) or ignored
//   [15:13] PRED   = predicate register to test
//   [12:0]  FUNC13 = [3:0] vote function (vote_func_t)
//
// For VOTE.ANY/ALL/NONE: writes to predicate register (from RD field)
// For VOTE.BALLOT/POPC: writes to integer register RD
//
// Version:     1.0
// Date:        January 1, 2026
//=============================================================================

`default_nettype none

`include "gpgpu_defines.svh"

module warp_vote
    import gpgpu_pkg::*;
#(
    parameter int NUM_LANES = WARP_SIZE  // Typically 8
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Control
    input  logic                    valid,
    input  logic [3:0]              vote_func,     // Vote function (vote_func_t)
    input  logic [NUM_LANES-1:0]    active_mask,   // Which threads are active
    input  logic [NUM_LANES-1:0]    pred_input,    // Predicate value for each thread
    
    // Results
    output logic                    pred_result,   // Result for ANY/ALL/NONE
    output logic [DATA_WIDTH-1:0]   data_result,   // Result for BALLOT/POPC
    output logic                    ready,
    output logic                    done
);

    //=========================================================================
    // Combinational Vote Logic
    //=========================================================================
    
    logic [NUM_LANES-1:0] active_preds;
    logic vote_any, vote_all, vote_none;
    logic [NUM_LANES-1:0] ballot;
    logic [$clog2(NUM_LANES):0] popc_count;
    
    // Mask predicates to only consider active threads
    assign active_preds = pred_input & active_mask;
    
    // VOTE.ANY: true if any active thread has predicate true
    assign vote_any = |active_preds;
    
    // VOTE.ALL: true if all active threads have predicate true
    // This is true when (active_preds == active_mask) for non-zero masks
    assign vote_all = (active_mask != '0) && (active_preds == active_mask);
    
    // VOTE.NONE: true if no active thread has predicate true
    assign vote_none = ~|active_preds;
    
    // VOTE.BALLOT: bitmask of (active threads with predicate true)
    assign ballot = active_preds;
    
    // VOTE.POPC: population count of ballot
    always_comb begin
        popc_count = '0;
        for (int i = 0; i < NUM_LANES; i++) begin
            popc_count = popc_count + {3'b0, active_preds[i]};
        end
    end
    
    //=========================================================================
    // Result Multiplexing
    //=========================================================================
    
    always_comb begin
        pred_result = 1'b0;
        data_result = '0;
        
        case (vote_func[3:0])
            VOTE_ANY: begin
                pred_result = vote_any;
            end
            
            VOTE_ALL: begin
                pred_result = vote_all;
            end
            
            VOTE_NONE: begin
                pred_result = vote_none;
            end
            
            VOTE_BALLOT: begin
                // Ballot returns the bitmask in lower bits
                data_result = {{(DATA_WIDTH-NUM_LANES){1'b0}}, ballot};
            end
            
            VOTE_POPC: begin
                // POPC returns the count
                data_result = {{(DATA_WIDTH-$clog2(NUM_LANES)-1){1'b0}}, popc_count};
            end
            
            default: begin
                pred_result = 1'b0;
                data_result = '0;
            end
        endcase
    end
    
    //=========================================================================
    // Control Signals
    //=========================================================================
    
    // Vote operations are single-cycle
    assign ready = 1'b1;
    assign done  = valid;

endmodule
