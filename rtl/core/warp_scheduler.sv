//=============================================================================
// GPGPU-1 Warp Scheduler
//=============================================================================
// File:        warp_scheduler.sv
// Description: Manages warp scheduling for SIMT execution. Implements
//              round-robin scheduling with support for stalls, barriers,
//              and divergence. Selects which warp executes each cycle.
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`default_nettype none

/* verilator lint_off DECLFILENAME */

`include "gpgpu_defines.svh"

module warp_scheduler
    import gpgpu_pkg::*;
#(
    parameter int NUM_WARPS = WARPS_PER_CORE
)(
    input  logic                            clk,
    input  logic                            rst_n,
    
    //=========================================================================
    // Warp Control Interface
    //=========================================================================
    
    // Warp activation (from dispatch unit)
    input  logic                            warp_activate,
    input  logic [WARP_ID_WIDTH-1:0]        warp_activate_id,
    input  logic [ADDR_WIDTH-1:0]           warp_activate_pc,
    input  logic [WARP_SIZE-1:0]            warp_activate_mask,
    
    // Warp termination (from execution)
    input  logic                            warp_exit,
    input  logic [WARP_ID_WIDTH-1:0]        warp_exit_id,
    input  logic [WARP_SIZE-1:0]            warp_exit_mask,  // Threads exiting
    
    //=========================================================================
    // Pipeline Stall Interface
    //=========================================================================
    
    // Stall signals from various sources
    input  logic                            stall_fetch,      // I-cache miss
    input  logic                            stall_decode,     // Decode hazard
    input  logic                            stall_operand,    // Operand fetch stall
    input  logic                            stall_execute,    // Execution stall
    input  logic                            stall_memory,     // Memory stall
    input  logic                            stall_writeback,  // Writeback stall
    
    //=========================================================================
    // Branch/Control Flow Interface
    //=========================================================================
    
    // Branch resolution
    input  logic                            branch_taken,
    input  logic [WARP_ID_WIDTH-1:0]        branch_warp_id,
    input  logic [ADDR_WIDTH-1:0]           branch_target_pc,
    
    // PC update from execution (for non-branch PC+4)
    input  logic                            pc_update_valid,
    input  logic [WARP_ID_WIDTH-1:0]        pc_update_warp_id,
    input  logic [ADDR_WIDTH-1:0]           pc_update_value,
    
    //=========================================================================
    // Divergence Control Interface
    //=========================================================================
    
    // PUSH operation
    input  logic                            diverge_push,
    input  logic [WARP_ID_WIDTH-1:0]        diverge_warp_id,
    input  logic [WARP_SIZE-1:0]            diverge_then_mask,
    
    // ELSE operation
    input  logic                            diverge_else,
    input  logic [WARP_ID_WIDTH-1:0]        diverge_else_warp_id,
    
    // POP operation  
    input  logic                            diverge_pop,
    input  logic [WARP_ID_WIDTH-1:0]        diverge_pop_warp_id,
    
    // Early divergence detection (from decode stage)
    input  logic                            decode_is_diverge,
    input  logic [WARP_ID_WIDTH-1:0]        decode_diverge_warp_id,
    
    //=========================================================================
    // Barrier Interface
    //=========================================================================
    
    // Barrier arrival
    input  logic                            barrier_arrive,
    input  logic [WARP_ID_WIDTH-1:0]        barrier_warp_id,
    input  logic [3:0]                      barrier_id,
    
    // Barrier release (from barrier unit)
    input  logic                            barrier_release,
    input  logic [3:0]                      barrier_release_id,
    
    //=========================================================================
    // Scheduled Warp Output
    //=========================================================================
    
    output logic                            sched_valid,
    input  logic                            sched_ready,       // Handshake from fetch unit
    output logic [WARP_ID_WIDTH-1:0]        sched_warp_id,
    output logic [ADDR_WIDTH-1:0]           sched_pc,
    output logic [WARP_SIZE-1:0]            sched_active_mask,
    output warp_state_t                     sched_warp_state,
    
    //=========================================================================
    // Status Outputs
    //=========================================================================
    
    output logic [NUM_WARPS-1:0]            warps_active,      // Bitmap of active warps
    output logic [NUM_WARPS-1:0]            warps_at_barrier,  // Warps waiting at barrier
    output logic                            all_warps_done     // All warps completed
);

    //=========================================================================
    // Warp State Storage
    //=========================================================================
    
    warp_state_t warp_state [NUM_WARPS-1:0];
    
    // Track which warps are ready to execute (not stalled, not at barrier)
    logic [NUM_WARPS-1:0] warps_ready;
    
    // Round-robin priority pointer
    logic [WARP_ID_WIDTH-1:0] priority_warp;
    
    // Selected warp
    logic [WARP_ID_WIDTH-1:0] selected_warp;
    logic                     warp_found;
    
    // Track warps with in-flight instructions (waiting for fetch to complete)
    logic [NUM_WARPS-1:0] warps_in_flight;
    
    // Track warps with divergence instruction in pipeline (waiting for mask update)
    logic [NUM_WARPS-1:0] warps_diverge_pending;
    
    // Delayed pc_update signals (for one-cycle delay in clearing warps_in_flight)
    logic                     pc_update_valid_r;
    logic [WARP_ID_WIDTH-1:0] pc_update_warp_id_r;
    
    // Pipeline stall combined
    logic pipeline_stall;
    assign pipeline_stall = stall_fetch | stall_decode | stall_operand | 
                            stall_execute | stall_memory | stall_writeback;
    
    //=========================================================================
    // Warp Ready Logic
    //=========================================================================
    
    always_comb begin
        for (int w = 0; w < NUM_WARPS; w++) begin
            // A warp is ready if:
            // 1. It is active (has threads)
            // 2. It is not waiting at a barrier
            // 3. It has at least one active thread
            // 4. It does not have an instruction in-flight
            // 5. It does not have a divergence instruction pending mask update
            warps_ready[w] = warp_state[w].active && 
                             !warp_state[w].at_barrier &&
                             (|warp_state[w].active_mask) &&
                             !warps_in_flight[w] &&
                             !warps_diverge_pending[w];
        end
    end
    
    //=========================================================================
    // Round-Robin Warp Selection
    //=========================================================================
    // Find the next ready warp starting from priority_warp
    
    always_comb begin
        warp_found = 1'b0;
        selected_warp = priority_warp;
        
        // Search from priority_warp to NUM_WARPS-1
        for (int i = 0; i < NUM_WARPS; i++) begin
            automatic int w = (priority_warp + i) % NUM_WARPS;
            if (!warp_found && warps_ready[w]) begin
                selected_warp = w[WARP_ID_WIDTH-1:0];
                warp_found = 1'b1;
            end
        end
    end
    
    //=========================================================================
    // Status Outputs
    //=========================================================================
    
    always_comb begin
        for (int w = 0; w < NUM_WARPS; w++) begin
            warps_active[w] = warp_state[w].active;
            warps_at_barrier[w] = warp_state[w].at_barrier;
        end
    end
    
    assign all_warps_done = ~(|warps_active);
    
    //=========================================================================
    // Scheduled Output
    //=========================================================================
    
    always_comb begin
        sched_valid = warp_found && !pipeline_stall;
        sched_warp_id = selected_warp;
        sched_pc = warp_state[selected_warp].pc;
        sched_active_mask = warp_state[selected_warp].active_mask;
        sched_warp_state = warp_state[selected_warp];
    end
    
    // Debug output
    `ifdef DEBUG_SCHEDULER
    always @(posedge clk) begin
        if (rst_n) begin
            $display("t=%0t SCHED: warp_found=%b stall=%b(f=%b d=%b o=%b e=%b m=%b w=%b) active=%b in_flight=%b ready=%b",
                     $time, warp_found, pipeline_stall, 
                     stall_fetch, stall_decode, stall_operand, stall_execute, stall_memory, stall_writeback,
                     warps_active, warps_in_flight, warps_ready);
            if (sched_valid && sched_ready) begin
                $display("t=%0t SCHED: DISPATCH warp=%0d pc=0x%h mask=%b",
                         $time, sched_warp_id, sched_pc, sched_active_mask);
            end
            if (warp_activate) begin
                $display("t=%0t SCHED: ACTIVATE warp=%0d pc=0x%h mask=%b",
                         $time, warp_activate_id, warp_activate_pc, warp_activate_mask);
            end
        end
    end
    `endif
    
    //=========================================================================
    // Warp State Update Logic
    //=========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all warp states
            for (int w = 0; w < NUM_WARPS; w++) begin
                warp_state[w].pc <= '0;
                warp_state[w].active_mask <= '0;
                warp_state[w].mask_stack <= '0;
                warp_state[w].mask_sp <= '0;
                warp_state[w].return_stack <= '0;
                warp_state[w].return_sp <= '0;
                warp_state[w].active <= 1'b0;
                warp_state[w].at_barrier <= 1'b0;
                warp_state[w].barrier_id <= '0;
            end
            priority_warp <= '0;
            warps_in_flight <= '0;
            warps_diverge_pending <= '0;
            pc_update_valid_r <= 1'b0;
            pc_update_warp_id_r <= '0;
            
        end else begin
            //=================================================================
            // In-Flight Tracking
            //=================================================================
            // Mark warp as in-flight when scheduled and fetch accepts
            if (sched_valid && sched_ready) begin
                warps_in_flight[selected_warp] <= 1'b1;
            end
            
            // Delay clearing in-flight by one cycle to allow decode_is_diverge to set
            // warps_diverge_pending first. Use registered pc_update signals.
            if (pc_update_valid_r) begin
                warps_in_flight[pc_update_warp_id_r] <= 1'b0;
            end
            
            // Register pc_update for delayed clearing
            pc_update_valid_r <= pc_update_valid;
            pc_update_warp_id_r <= pc_update_warp_id;
            
            // Also clear in-flight on warp exit
            if (warp_exit) begin
                warps_in_flight[warp_exit_id] <= 1'b0;
            end
            
            //=================================================================
            // Divergence Instruction Tracking
            //=================================================================
            // Mark warp as having divergence pending when PUSH/ELSE/POP is decoded
            if (decode_is_diverge) begin
                warps_diverge_pending[decode_diverge_warp_id] <= 1'b1;
            end
            
            // Clear divergence pending when the corresponding diverge signal fires
            if (diverge_push) begin
                warps_diverge_pending[diverge_warp_id] <= 1'b0;
            end
            if (diverge_else) begin
                warps_diverge_pending[diverge_else_warp_id] <= 1'b0;
            end
            if (diverge_pop) begin
                warps_diverge_pending[diverge_pop_warp_id] <= 1'b0;
            end
            
            //=================================================================
            // Warp Activation
            //=================================================================
            if (warp_activate) begin
                warp_state[warp_activate_id].pc <= warp_activate_pc;
                warp_state[warp_activate_id].active_mask <= warp_activate_mask;
                warp_state[warp_activate_id].mask_stack <= '0;
                warp_state[warp_activate_id].mask_sp <= '0;
                warp_state[warp_activate_id].return_stack <= '0;
                warp_state[warp_activate_id].return_sp <= '0;
                warp_state[warp_activate_id].active <= 1'b1;
                warp_state[warp_activate_id].at_barrier <= 1'b0;
                warp_state[warp_activate_id].barrier_id <= '0;
                warps_in_flight[warp_activate_id] <= 1'b0;  // New warp not in-flight
            end
            
            //=================================================================
            // Warp Exit (thread termination)
            //=================================================================
            if (warp_exit) begin
                // Clear exiting threads from active mask
                warp_state[warp_exit_id].active_mask <= 
                    warp_state[warp_exit_id].active_mask & ~warp_exit_mask;
                
                // If all threads exited, deactivate warp
                if ((warp_state[warp_exit_id].active_mask & ~warp_exit_mask) == '0) begin
                    warp_state[warp_exit_id].active <= 1'b0;
                end
            end
            
            //=================================================================
            // PC Updates
            //=================================================================
            
            // Branch taken - update PC to target
            if (branch_taken) begin
                warp_state[branch_warp_id].pc <= branch_target_pc;
            end
              // Normal PC update (PC+4 from fetch completion)
            if (pc_update_valid && !branch_taken) begin
                warp_state[pc_update_warp_id].pc <= pc_update_value;
            end
            
            // NOTE: We no longer auto-increment PC here.
            // The fetch unit manages PC advancement and reports back via pc_update_valid.
            // This prevents the scheduler from advancing PC multiple times while
            // fetch is still in progress (which takes multiple cycles).
            
            //=================================================================
            // Divergence Control - PUSH
            //=================================================================
            if (diverge_push) begin
                automatic logic [MASK_SP_WIDTH-1:0] sp = warp_state[diverge_warp_id].mask_sp;
                
                // Push current mask onto stack
                warp_state[diverge_warp_id].mask_stack[sp] <= 
                    warp_state[diverge_warp_id].active_mask;
                warp_state[diverge_warp_id].mask_sp <= sp + 1;
                
                // Set active mask to then-path threads
                warp_state[diverge_warp_id].active_mask <= diverge_then_mask;
            end
            
            //=================================================================
            // Divergence Control - ELSE
            //=================================================================
            if (diverge_else) begin
                automatic logic [MASK_SP_WIDTH-1:0] sp = warp_state[diverge_else_warp_id].mask_sp;
                
                // Switch to else-path: threads that were active but not in then-path
                // else_mask = saved_mask & ~current_active_mask
                if (sp > 0) begin
                    warp_state[diverge_else_warp_id].active_mask <= 
                        warp_state[diverge_else_warp_id].mask_stack[sp-1] &
                        ~warp_state[diverge_else_warp_id].active_mask;
                end
            end
            
            //=================================================================
            // Divergence Control - POP
            //=================================================================
            if (diverge_pop) begin
                automatic logic [MASK_SP_WIDTH-1:0] sp = warp_state[diverge_pop_warp_id].mask_sp;
                
                // Pop mask from stack
                if (sp > 0) begin
                    warp_state[diverge_pop_warp_id].active_mask <= 
                        warp_state[diverge_pop_warp_id].mask_stack[sp-1];
                    warp_state[diverge_pop_warp_id].mask_sp <= sp - 1;
                end
            end
            
            //=================================================================
            // Barrier Handling
            //=================================================================
            
            // Warp arrives at barrier
            if (barrier_arrive) begin
                warp_state[barrier_warp_id].at_barrier <= 1'b1;
                warp_state[barrier_warp_id].barrier_id <= barrier_id;
            end
            
            // Barrier release - wake up all warps at this barrier
            if (barrier_release) begin
                for (int w = 0; w < NUM_WARPS; w++) begin
                    if (warp_state[w].at_barrier && 
                        warp_state[w].barrier_id == barrier_release_id) begin
                        warp_state[w].at_barrier <= 1'b0;
                    end
                end
            end
            
            //=================================================================
            // Round-Robin Priority Update
            //=================================================================
            // Advance priority after successful scheduling
            if (sched_valid) begin
                priority_warp <= (selected_warp + 1) % NUM_WARPS;
            end
        end
    end
    
    //=========================================================================
    // Debug / Assertions
    //=========================================================================
    
    `ifdef ENABLE_ASSERTIONS
        // Check mask stack doesn't overflow
        always_ff @(posedge clk) begin
            if (diverge_push) begin
                assert (warp_state[diverge_warp_id].mask_sp < MASK_STACK_DEPTH)
                    else $error("Mask stack overflow for warp %0d", diverge_warp_id);
            end
        end
        
        // Check mask stack doesn't underflow
        always_ff @(posedge clk) begin
            if (diverge_pop) begin
                assert (warp_state[diverge_pop_warp_id].mask_sp > 0)
                    else $error("Mask stack underflow for warp %0d", diverge_pop_warp_id);
            end
        end
    `endif
    
    `ifdef SIMULATION
        // Debug: Monitor warp scheduling
        always_ff @(posedge clk) begin
            if (sched_valid) begin
                `DEBUG_PRINTF("Scheduler: Warp[%0d] PC=0x%016h Mask=0x%02h",
                              sched_warp_id, sched_pc, sched_active_mask);
            end
        end
        
        // Debug: Monitor warp activation
        always_ff @(posedge clk) begin
            if (warp_activate) begin
                `DEBUG_PRINTF("Scheduler: Activating Warp[%0d] PC=0x%016h Mask=0x%02h",
                              warp_activate_id, warp_activate_pc, warp_activate_mask);
            end
        end
        
        // Debug: Monitor barrier events
        always_ff @(posedge clk) begin
            if (barrier_arrive) begin
                `DEBUG_PRINTF("Scheduler: Warp[%0d] arrived at barrier %0d",
                              barrier_warp_id, barrier_id);
            end
            if (barrier_release) begin
                `DEBUG_PRINTF("Scheduler: Barrier %0d released", barrier_release_id);
            end
        end
    `endif

endmodule

//=============================================================================
// Barrier Synchronization Unit
//=============================================================================
// Manages barrier synchronization across warps within a thread block.
// When all active warps reach the same barrier, they are released together.
//=============================================================================

module barrier_unit
    import gpgpu_pkg::*;
#(
    parameter int NUM_WARPS = WARPS_PER_CORE,
    parameter int NUM_BARRIERS = 16
)(
    input  logic                            clk,
    input  logic                            rst_n,
    
    // Configuration: number of warps in current block
    input  logic [WARP_ID_WIDTH-1:0]        num_warps_in_block,
    
    // Barrier arrival from warp scheduler
    input  logic                            barrier_arrive,
    input  logic [WARP_ID_WIDTH-1:0]        barrier_warp_id,
    input  logic [3:0]                      barrier_id,
    
    // Barrier release to warp scheduler
    output logic                            barrier_release,
    output logic [3:0]                      barrier_release_id,
    
    // Reset barrier (when block finishes)
    input  logic                            reset_barriers
);

    //=========================================================================
    // Barrier State
    //=========================================================================
    
    // Count of warps arrived at each barrier
    logic [WARP_ID_WIDTH:0] barrier_count [NUM_BARRIERS-1:0];
    
    // Track which warps have arrived at each barrier (avoid double counting)
    logic [NUM_WARPS-1:0] barrier_arrived [NUM_BARRIERS-1:0];
    
    //=========================================================================
    // Barrier Logic
    //=========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || reset_barriers) begin
            barrier_release <= 1'b0;
            barrier_release_id <= '0;
            for (int b = 0; b < NUM_BARRIERS; b++) begin
                barrier_count[b] <= '0;
                barrier_arrived[b] <= '0;
            end
        end else begin
            barrier_release <= 1'b0;
            
            if (barrier_arrive) begin
                // Check if this warp hasn't already arrived at this barrier
                if (!barrier_arrived[barrier_id][barrier_warp_id]) begin
                    barrier_arrived[barrier_id][barrier_warp_id] <= 1'b1;
                    barrier_count[barrier_id] <= barrier_count[barrier_id] + 1;
                    
                    // Check if all warps have arrived
                    if (barrier_count[barrier_id] + 1 == num_warps_in_block) begin
                        // Release barrier
                        barrier_release <= 1'b1;
                        barrier_release_id <= barrier_id;
                        
                        // Reset this barrier for reuse
                        barrier_count[barrier_id] <= '0;
                        barrier_arrived[barrier_id] <= '0;
                    end
                end
            end
        end
    end

endmodule

//=============================================================================
// Scoreboard for Data Hazard Detection
//=============================================================================
// Tracks in-flight register writes to detect RAW hazards.
// Used by the scheduler to avoid issuing dependent instructions.
//=============================================================================

module scoreboard
    import gpgpu_pkg::*;
#(
    parameter int NUM_WARPS = WARPS_PER_CORE
)(
    input  logic                            clk,
    input  logic                            rst_n,
    
    // Register read check (from decode stage)
    input  logic                            check_valid,
    input  logic [WARP_ID_WIDTH-1:0]        check_warp_id,
    input  logic [REG_ADDR_WIDTH-1:0]       check_rs1,
    input  logic [REG_ADDR_WIDTH-1:0]       check_rs2,
    input  logic                            check_rs1_en,
    input  logic                            check_rs2_en,
    output logic                            hazard_detected,
    
    // Register write reservation (from decode/issue stage)
    input  logic                            reserve_valid,
    input  logic [WARP_ID_WIDTH-1:0]        reserve_warp_id,
    input  logic [REG_ADDR_WIDTH-1:0]       reserve_rd,
    input  logic                            reserve_rd_en,
    
    // Register write completion (from writeback stage)
    input  logic                            complete_valid,
    input  logic [WARP_ID_WIDTH-1:0]        complete_warp_id,
    input  logic [REG_ADDR_WIDTH-1:0]       complete_rd,
    
    // Clear all entries for a warp (on warp termination)
    input  logic                            clear_warp,
    input  logic [WARP_ID_WIDTH-1:0]        clear_warp_id
);

    //=========================================================================
    // Scoreboard Storage
    //=========================================================================
    // One bit per register per warp indicating pending write
    
    logic [NUM_REGS-1:0] pending [NUM_WARPS-1:0];
    
    //=========================================================================
    // Hazard Detection
    //=========================================================================
    
    always_comb begin
        hazard_detected = 1'b0;
        
        if (check_valid) begin
            // Check RS1 for RAW hazard
            if (check_rs1_en && check_rs1 != '0) begin
                if (pending[check_warp_id][check_rs1]) begin
                    hazard_detected = 1'b1;
                end
            end
            
            // Check RS2 for RAW hazard
            if (check_rs2_en && check_rs2 != '0) begin
                if (pending[check_warp_id][check_rs2]) begin
                    hazard_detected = 1'b1;
                end
            end
        end
    end
    
    //=========================================================================
    // Scoreboard Update
    //=========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int w = 0; w < NUM_WARPS; w++) begin
                pending[w] <= '0;
            end
        end else begin
            // Clear warp's scoreboard
            if (clear_warp) begin
                pending[clear_warp_id] <= '0;
            end
            
            // Reserve destination register (mark as pending)
            if (reserve_valid && reserve_rd_en && reserve_rd != '0) begin
                pending[reserve_warp_id][reserve_rd] <= 1'b1;
            end
            
            // Complete write (clear pending)
            if (complete_valid && complete_rd != '0) begin
                pending[complete_warp_id][complete_rd] <= 1'b0;
            end
        end
    end

endmodule
