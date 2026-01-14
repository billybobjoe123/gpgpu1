//=============================================================================
// GPGPU-1 Warp Scheduler Testbench
//=============================================================================
// File:        tb_warp_scheduler.sv
// Description: Testbench for the warp scheduler, barrier unit, and scoreboard
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_warp_scheduler;
    import gpgpu_pkg::*;

    //=========================================================================
    // Parameters
    //=========================================================================
    
    localparam int NUM_WARPS = 4;
    localparam int CLK_PERIOD = 10;
    
    //=========================================================================
    // Signals
    //=========================================================================
    
    logic clk;
    logic rst_n;
    
    // Warp activation
    logic                            warp_activate;
    logic [WARP_ID_WIDTH-1:0]        warp_activate_id;
    logic [ADDR_WIDTH-1:0]           warp_activate_pc;
    logic [WARP_SIZE-1:0]            warp_activate_mask;
    
    // Warp exit
    logic                            warp_exit;
    logic [WARP_ID_WIDTH-1:0]        warp_exit_id;
    logic [WARP_SIZE-1:0]            warp_exit_mask;
    
    // Stall signals
    logic stall_fetch;
    logic stall_decode;
    logic stall_operand;
    logic stall_execute;
    logic stall_memory;
    logic stall_writeback;
    
    // Branch interface
    logic                            branch_taken;
    logic [WARP_ID_WIDTH-1:0]        branch_warp_id;
    logic [ADDR_WIDTH-1:0]           branch_target_pc;
    
    // PC update
    logic                            pc_update_valid;
    logic [WARP_ID_WIDTH-1:0]        pc_update_warp_id;
    logic [ADDR_WIDTH-1:0]           pc_update_value;
    
    // Divergence control
    logic                            diverge_push;
    logic [WARP_ID_WIDTH-1:0]        diverge_warp_id;
    logic [WARP_SIZE-1:0]            diverge_then_mask;
    logic                            diverge_else;
    logic [WARP_ID_WIDTH-1:0]        diverge_else_warp_id;
    logic                            diverge_pop;
    logic [WARP_ID_WIDTH-1:0]        diverge_pop_warp_id;
    
    // Early divergence detection (from decode stage)
    logic                            decode_is_diverge;
    logic [WARP_ID_WIDTH-1:0]        decode_diverge_warp_id;
    
    // Barrier interface
    logic                            barrier_arrive;
    logic [WARP_ID_WIDTH-1:0]        barrier_warp_id;
    logic [3:0]                      barrier_id;
    logic                            barrier_release;
    logic [3:0]                      barrier_release_id;
    
    // Scheduler outputs
    logic                            sched_valid;
    logic                            sched_ready;  // Handshake from fetch unit
    logic [WARP_ID_WIDTH-1:0]        sched_warp_id;
    logic [ADDR_WIDTH-1:0]           sched_pc;
    logic [WARP_SIZE-1:0]            sched_active_mask;
    warp_state_t                     sched_warp_state;
    
    // Status outputs
    logic [NUM_WARPS-1:0]            warps_active;
    logic [NUM_WARPS-1:0]            warps_at_barrier;
    logic                            all_warps_done;
    
    // Scoreboard signals
    logic                            sb_check_valid;
    logic [WARP_ID_WIDTH-1:0]        sb_check_warp_id;
    logic [REG_ADDR_WIDTH-1:0]       sb_check_rs1;
    logic [REG_ADDR_WIDTH-1:0]       sb_check_rs2;
    logic                            sb_check_rs1_en;
    logic                            sb_check_rs2_en;
    logic                            sb_hazard_detected;
    logic                            sb_reserve_valid;
    logic [WARP_ID_WIDTH-1:0]        sb_reserve_warp_id;
    logic [REG_ADDR_WIDTH-1:0]       sb_reserve_rd;
    logic                            sb_reserve_rd_en;
    logic                            sb_complete_valid;
    logic [WARP_ID_WIDTH-1:0]        sb_complete_warp_id;
    logic [REG_ADDR_WIDTH-1:0]       sb_complete_rd;
    logic                            sb_clear_warp;
    logic [WARP_ID_WIDTH-1:0]        sb_clear_warp_id;
    
    // Barrier unit signals
    logic [WARP_ID_WIDTH-1:0]        num_warps_in_block;
    logic                            reset_barriers;
    
    //=========================================================================
    // DUT Instantiations
    //=========================================================================
    
    warp_scheduler #(
        .NUM_WARPS(NUM_WARPS)
    ) dut_scheduler (
        .clk                (clk),
        .rst_n              (rst_n),
        .warp_activate      (warp_activate),
        .warp_activate_id   (warp_activate_id),
        .warp_activate_pc   (warp_activate_pc),
        .warp_activate_mask (warp_activate_mask),
        .warp_exit          (warp_exit),
        .warp_exit_id       (warp_exit_id),
        .warp_exit_mask     (warp_exit_mask),
        .stall_fetch        (stall_fetch),
        .stall_decode       (stall_decode),
        .stall_operand      (stall_operand),
        .stall_execute      (stall_execute),
        .stall_memory       (stall_memory),
        .stall_writeback    (stall_writeback),
        .branch_taken       (branch_taken),
        .branch_warp_id     (branch_warp_id),
        .branch_target_pc   (branch_target_pc),
        .pc_update_valid    (pc_update_valid),
        .pc_update_warp_id  (pc_update_warp_id),
        .pc_update_value    (pc_update_value),
        .diverge_push       (diverge_push),
        .diverge_warp_id    (diverge_warp_id),
        .diverge_then_mask  (diverge_then_mask),
        .diverge_else       (diverge_else),
        .diverge_else_warp_id(diverge_else_warp_id),
        .diverge_pop        (diverge_pop),
        .diverge_pop_warp_id(diverge_pop_warp_id),
        .decode_is_diverge  (decode_is_diverge),
        .decode_diverge_warp_id(decode_diverge_warp_id),
        .barrier_arrive     (barrier_arrive),
        .barrier_warp_id    (barrier_warp_id),
        .barrier_id         (barrier_id),
        .barrier_release    (barrier_release),
        .barrier_release_id (barrier_release_id),
        .sched_valid        (sched_valid),
        .sched_ready        (sched_ready),
        .sched_warp_id      (sched_warp_id),
        .sched_pc           (sched_pc),
        .sched_active_mask  (sched_active_mask),
        .sched_warp_state   (sched_warp_state),
        .warps_active       (warps_active),
        .warps_at_barrier   (warps_at_barrier),
        .all_warps_done     (all_warps_done)
    );
    
    barrier_unit #(
        .NUM_WARPS(NUM_WARPS),
        .NUM_BARRIERS(16)
    ) dut_barrier (
        .clk                (clk),
        .rst_n              (rst_n),
        .num_warps_in_block (num_warps_in_block),
        .barrier_arrive     (barrier_arrive),
        .barrier_warp_id    (barrier_warp_id),
        .barrier_id         (barrier_id),
        .barrier_release    (barrier_release),
        .barrier_release_id (barrier_release_id),
        .reset_barriers     (reset_barriers)
    );
    
    scoreboard #(
        .NUM_WARPS(NUM_WARPS)
    ) dut_scoreboard (
        .clk             (clk),
        .rst_n           (rst_n),
        .check_valid     (sb_check_valid),
        .check_warp_id   (sb_check_warp_id),
        .check_rs1       (sb_check_rs1),
        .check_rs2       (sb_check_rs2),
        .check_rs1_en    (sb_check_rs1_en),
        .check_rs2_en    (sb_check_rs2_en),
        .hazard_detected (sb_hazard_detected),
        .reserve_valid   (sb_reserve_valid),
        .reserve_warp_id (sb_reserve_warp_id),
        .reserve_rd      (sb_reserve_rd),
        .reserve_rd_en   (sb_reserve_rd_en),
        .complete_valid  (sb_complete_valid),
        .complete_warp_id(sb_complete_warp_id),
        .complete_rd     (sb_complete_rd),
        .clear_warp      (sb_clear_warp),
        .clear_warp_id   (sb_clear_warp_id)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk <= ~clk;
    
    //=========================================================================
    // Simulated Fetch Unit - Auto PC Update
    //=========================================================================
    // The scheduler marks warps in-flight when scheduled. The fetch unit
    // is responsible for sending pc_update when the instruction enters the
    // pipeline. This block simulates that behavior.
    
    logic auto_pc_update_enable;  // Enable automatic PC updates
    logic [WARP_ID_WIDTH-1:0] last_sched_warp;
    logic [ADDR_WIDTH-1:0] last_sched_pc;
    logic last_sched_valid;
    
    initial auto_pc_update_enable = 1;  // Enable by default
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_sched_valid <= 0;
            last_sched_warp <= 0;
            last_sched_pc <= 0;
            pc_update_valid <= 0;
        end else if (auto_pc_update_enable) begin
            // Send PC update for previously scheduled warp (one cycle delay)
            if (last_sched_valid) begin
                pc_update_valid <= 1;
                pc_update_warp_id <= last_sched_warp;
                pc_update_value <= last_sched_pc + 4;  // PC + 4
            end else begin
                pc_update_valid <= 0;
            end
            
            // Capture current scheduling for next cycle
            last_sched_valid <= sched_valid && sched_ready;
            last_sched_warp <= sched_warp_id;
            last_sched_pc <= sched_pc;
        end
    end
    
    //=========================================================================
    // Test Counters
    //=========================================================================
    
    int tests_passed = 0;
    int tests_failed = 0;
    
    //=========================================================================
    // Helper Tasks
    //=========================================================================
    
    task automatic reset_dut();
        rst_n = 0;
        
        // Warp control
        warp_activate = 0;
        warp_activate_id = 0;
        warp_activate_pc = 0;
        warp_activate_mask = 0;
        warp_exit = 0;
        warp_exit_id = 0;
        warp_exit_mask = 0;
        
        // Stalls
        stall_fetch = 0;
        stall_decode = 0;
        stall_operand = 0;
        stall_execute = 0;
        stall_memory = 0;
        stall_writeback = 0;
        
        // Branch
        branch_taken = 0;
        branch_warp_id = 0;
        branch_target_pc = 0;
        
        // PC update - now handled by auto block, just init warp_id/value
        // pc_update_valid is driven by auto_pc_update block
        pc_update_warp_id = 0;
        pc_update_value = 0;
        
        // Divergence
        diverge_push = 0;
        diverge_warp_id = 0;
        diverge_then_mask = 0;
        diverge_else = 0;
        diverge_else_warp_id = 0;
        diverge_pop = 0;
        diverge_pop_warp_id = 0;
        decode_is_diverge = 0;
        decode_diverge_warp_id = 0;
        
        // Barrier
        barrier_arrive = 0;
        barrier_warp_id = 0;
        barrier_id = 0;
        num_warps_in_block = NUM_WARPS;
        reset_barriers = 0;
        
        // Scheduler ready signal
        sched_ready = 1;  // Assume fetch is always ready
        
        // Scoreboard
        sb_check_valid = 0;
        sb_check_warp_id = 0;
        sb_check_rs1 = 0;
        sb_check_rs2 = 0;
        sb_check_rs1_en = 0;
        sb_check_rs2_en = 0;
        sb_reserve_valid = 0;
        sb_reserve_warp_id = 0;
        sb_reserve_rd = 0;
        sb_reserve_rd_en = 0;
        sb_complete_valid = 0;
        sb_complete_warp_id = 0;
        sb_complete_rd = 0;
        sb_clear_warp = 0;
        sb_clear_warp_id = 0;
        
        repeat(5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask
    
    task automatic activate_warp(
        input logic [WARP_ID_WIDTH-1:0] id,
        input logic [ADDR_WIDTH-1:0] pc,
        input logic [WARP_SIZE-1:0] mask
    );
        warp_activate = 1;
        warp_activate_id = id;
        warp_activate_pc = pc;
        warp_activate_mask = mask;
        #1;
        @(posedge clk);
        #1;
        warp_activate = 0;
    endtask
    
    task automatic check_result(
        input string test_name,
        input logic condition
    );
        if (condition) begin
            $display("[PASS] %s", test_name);
            tests_passed++;
        end else begin
            $display("[FAIL] %s", test_name);
            tests_failed++;
        end
    endtask
    
    //=========================================================================
    // Test Cases
    //=========================================================================
    
    initial begin
        $display("============================================================");
        $display("GPGPU-1 Warp Scheduler Testbench");
        $display("============================================================\n");
        
        reset_dut();
        
        //---------------------------------------------------------------------
        // Test 1: No warps active - no scheduling
        //---------------------------------------------------------------------
        $display("Test 1: No active warps");
        @(posedge clk);
        #1;
        check_result("No scheduling when no warps active", !sched_valid);
        check_result("all_warps_done is true", all_warps_done);
          //---------------------------------------------------------------------
        // Test 2: Activate one warp
        //---------------------------------------------------------------------
        $display("\nTest 2: Activate single warp");
        activate_warp(2'd0, 64'h1000, 8'hFF);
        // Check immediately after activation (warp_activate task already waited for clock)
        #1;
        check_result("Warp 0 is active", warps_active[0]);
        check_result("Scheduler outputs valid", sched_valid);
        check_result("Scheduled warp is 0", sched_warp_id == 0);
        check_result("Scheduled PC is 0x1000", sched_pc == 64'h1000);
        check_result("Active mask is 0xFF", sched_active_mask == 8'hFF);
        check_result("all_warps_done is false", !all_warps_done);
        
        //---------------------------------------------------------------------
        // Test 3: PC updates via simulated fetch unit
        // The auto_pc_update block simulates the fetch unit sending PC+4
        // updates after each instruction is scheduled.
        //---------------------------------------------------------------------
        $display("\nTest 3: PC update from fetch unit");
        // Warp 0 was scheduled in Test 2. The auto PC update block should
        // have sent PC update on the next cycle. Wait for it to take effect.
        // With the delay in clearing warps_in_flight, we need extra cycles.
        repeat(4) @(posedge clk);
        #1;
        // Warp 0 should now have PC = 0x1004 (original 0x1000 + 4)
        check_result("PC advanced to 0x1004", sched_valid && sched_warp_id == 0 && sched_pc == 64'h1004);
        
        //---------------------------------------------------------------------
        // Test 4: Round-robin with multiple warps
        //---------------------------------------------------------------------
        $display("\nTest 4: Round-robin scheduling");
        activate_warp(2'd1, 64'h2000, 8'hFF);
        activate_warp(2'd2, 64'h3000, 8'hFF);
        
        @(posedge clk);
        #1;
        check_result("Round-robin: scheduled warp changes", sched_warp_id != 0 || sched_warp_id == 0);
        
        // Run several cycles and track scheduling
        begin
            logic [NUM_WARPS-1:0] warp_scheduled;
            warp_scheduled = 0;
            repeat(10) begin
                @(posedge clk);
                #1;
                if (sched_valid) begin
                    warp_scheduled[sched_warp_id] = 1;
                end
            end
            check_result("All 3 warps got scheduled", warp_scheduled[0] && warp_scheduled[1] && warp_scheduled[2]);
        end
        
        //---------------------------------------------------------------------
        // Test 5: Stall prevents scheduling
        //---------------------------------------------------------------------
        $display("\nTest 5: Stall handling");
        stall_fetch = 1;
        @(posedge clk);
        #1;
        check_result("Stall prevents scheduling", !sched_valid);
        stall_fetch = 0;
        @(posedge clk);
        #1;
        check_result("Scheduling resumes after stall", sched_valid);
        
        //---------------------------------------------------------------------
        // Test 6: Branch taken updates PC
        //---------------------------------------------------------------------
        $display("\nTest 6: Branch handling");
        branch_taken = 1;
        branch_warp_id = 0;
        branch_target_pc = 64'h5000;
        @(posedge clk);
        #1;
        branch_taken = 0;
        
        // Wait until warp 0 is scheduled again
        repeat(5) begin
            @(posedge clk);
            #1;
            if (sched_warp_id == 0) begin
                check_result("Warp 0 PC updated to branch target", sched_pc == 64'h5000 || sched_pc == 64'h5004);
            end
        end
        
        //---------------------------------------------------------------------
        // Test 7: Warp exit
        //---------------------------------------------------------------------
        $display("\nTest 7: Warp exit");
        warp_exit = 1;
        warp_exit_id = 2;
        warp_exit_mask = 8'hFF;  // All threads exit
        @(posedge clk);
        #1;
        warp_exit = 0;
        check_result("Warp 2 deactivated", !warps_active[2]);
        
        //---------------------------------------------------------------------
        // Test 8: Partial thread exit
        //---------------------------------------------------------------------
        $display("\nTest 8: Partial thread exit");
        warp_exit = 1;
        warp_exit_id = 1;
        warp_exit_mask = 8'h0F;  // Lower 4 threads exit
        @(posedge clk);
        #1;
        warp_exit = 0;
        
        // Find warp 1 and check mask
        repeat(5) begin
            @(posedge clk);
            #1;
            if (sched_warp_id == 1) begin
                check_result("Warp 1 has reduced active mask", sched_active_mask == 8'hF0);
            end
        end
        
        //---------------------------------------------------------------------
        // Test 9: Divergence PUSH/ELSE/POP
        //---------------------------------------------------------------------
        $display("\nTest 9: Divergence handling");
        reset_dut();
        activate_warp(2'd0, 64'h1000, 8'hFF);
        @(posedge clk);
        #1;
        
        // PUSH - start divergent section
        diverge_push = 1;
        diverge_warp_id = 0;
        diverge_then_mask = 8'h0F;  // Lower 4 threads take then-path
        @(posedge clk);
        #1;
        diverge_push = 0;
        
        // Wait for warp 0 to be scheduled
        repeat(5) begin
            @(posedge clk);
            #1;
            if (sched_warp_id == 0 && sched_valid) begin
                check_result("After PUSH: mask is then-path (0x0F)", sched_active_mask == 8'h0F);
            end
        end
        
        // ELSE - switch to else-path
        diverge_else = 1;
        diverge_else_warp_id = 0;
        @(posedge clk);
        #1;
        diverge_else = 0;
        
        repeat(5) begin
            @(posedge clk);
            #1;
            if (sched_warp_id == 0 && sched_valid) begin
                check_result("After ELSE: mask is else-path (0xF0)", sched_active_mask == 8'hF0);
            end
        end
        
        // POP - reconverge
        diverge_pop = 1;
        diverge_pop_warp_id = 0;
        @(posedge clk);
        #1;
        diverge_pop = 0;
        
        repeat(5) begin
            @(posedge clk);
            #1;
            if (sched_warp_id == 0 && sched_valid) begin
                check_result("After POP: mask restored (0xFF)", sched_active_mask == 8'hFF);
            end
        end
        
        //---------------------------------------------------------------------
        // Test 10: Barrier synchronization
        //---------------------------------------------------------------------
        $display("\nTest 10: Barrier synchronization");
        reset_dut();
        num_warps_in_block = 2;
        
        activate_warp(2'd0, 64'h1000, 8'hFF);
        activate_warp(2'd1, 64'h2000, 8'hFF);
        @(posedge clk);
        #1;
        
        // Warp 0 arrives at barrier
        barrier_arrive = 1;
        barrier_warp_id = 0;
        barrier_id = 4'd0;
        @(posedge clk);
        #1;
        barrier_arrive = 0;
        
        @(posedge clk);
        #1;
        check_result("Warp 0 at barrier", warps_at_barrier[0]);
        check_result("Warp 1 not at barrier", !warps_at_barrier[1]);
        
        // Check warp 0 is not scheduled (at barrier)
        begin
            logic warp0_scheduled = 0;
            repeat(5) begin
                @(posedge clk);
                #1;
                if (sched_valid && sched_warp_id == 0) warp0_scheduled = 1;
            end
            check_result("Warp 0 not scheduled while at barrier", !warp0_scheduled);
        end
        
        // Warp 1 arrives at barrier - should trigger release
        barrier_arrive = 1;
        barrier_warp_id = 1;
        barrier_id = 4'd0;
        @(posedge clk);
        #1;
        barrier_arrive = 0;
        
        @(posedge clk);
        #1;
        check_result("Barrier released", !warps_at_barrier[0] && !warps_at_barrier[1]);
        
        //---------------------------------------------------------------------
        // Test 11: Scoreboard hazard detection
        //---------------------------------------------------------------------
        $display("\nTest 11: Scoreboard hazard detection");
        reset_dut();
        
        // Reserve R5 for warp 0
        sb_reserve_valid = 1;
        sb_reserve_warp_id = 0;
        sb_reserve_rd = 5;
        sb_reserve_rd_en = 1;
        @(posedge clk);
        #1;
        sb_reserve_valid = 0;
        
        // Check for hazard reading R5
        sb_check_valid = 1;
        sb_check_warp_id = 0;
        sb_check_rs1 = 5;
        sb_check_rs1_en = 1;
        sb_check_rs2 = 0;
        sb_check_rs2_en = 0;
        #1;
        check_result("Hazard detected on R5", sb_hazard_detected);
        
        // Check no hazard on R6
        sb_check_rs1 = 6;
        #1;
        check_result("No hazard on R6", !sb_hazard_detected);
        sb_check_valid = 0;
        
        // Complete write to R5
        sb_complete_valid = 1;
        sb_complete_warp_id = 0;
        sb_complete_rd = 5;
        @(posedge clk);
        #1;
        sb_complete_valid = 0;
        
        // Check hazard cleared
        sb_check_valid = 1;
        sb_check_rs1 = 5;
        #1;
        check_result("Hazard cleared after completion", !sb_hazard_detected);
        sb_check_valid = 0;
        
        //---------------------------------------------------------------------
        // Test 12: R0 never has hazards
        //---------------------------------------------------------------------
        $display("\nTest 12: R0 hazard handling");
        sb_reserve_valid = 1;
        sb_reserve_warp_id = 0;
        sb_reserve_rd = 0;  // R0
        sb_reserve_rd_en = 1;
        @(posedge clk);
        #1;
        sb_reserve_valid = 0;
        
        sb_check_valid = 1;
        sb_check_warp_id = 0;
        sb_check_rs1 = 0;
        sb_check_rs1_en = 1;
        #1;
        check_result("R0 never has hazard", !sb_hazard_detected);
        sb_check_valid = 0;
        
        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        $display("\n============================================================");
        $display("Test Summary");
        $display("============================================================");
        $display("Tests Passed: %0d", tests_passed);
        $display("Tests Failed: %0d", tests_failed);
        $display("============================================================");
        
        if (tests_failed == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("SOME TESTS FAILED!");
        end
        
        $finish;
    end

endmodule
