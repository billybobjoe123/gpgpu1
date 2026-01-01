//=============================================================================
// GPGPU-1 Warp Vote Unit Testbench
//=============================================================================
// File:        tb_warp_vote.sv
// Description: Comprehensive testbench for the warp vote unit.
//              Tests all vote modes: ANY, ALL, NONE, BALLOT, POPC
// Version:     1.0
// Date:        January 1, 2026
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_warp_vote;
    import gpgpu_pkg::*;
    
    //=========================================================================
    // Parameters
    //=========================================================================
    
    localparam int NUM_LANES = WARP_SIZE;  // 8 lanes
    localparam int CLK_PERIOD = 10;
    
    //=========================================================================
    // Signals
    //=========================================================================
    
    logic clk;
    logic rst_n;
    
    // Vote control
    logic                    valid;
    logic [3:0]              vote_func;
    logic [NUM_LANES-1:0]    active_mask;
    logic [NUM_LANES-1:0]    pred_input;
    
    // Results
    logic                    pred_result;
    logic [DATA_WIDTH-1:0]   data_result;
    logic                    ready;
    logic                    done;
    
    // Test counters
    int tests_passed = 0;
    int tests_failed = 0;
    int total_tests = 0;
    
    //=========================================================================
    // DUT Instance
    //=========================================================================
    
    warp_vote #(
        .NUM_LANES(NUM_LANES)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .valid       (valid),
        .vote_func   (vote_func),
        .active_mask (active_mask),
        .pred_input  (pred_input),
        .pred_result (pred_result),
        .data_result (data_result),
        .ready       (ready),
        .done        (done)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    //=========================================================================
    // Test Tasks
    //=========================================================================
    
    task automatic check_pred_result(
        input string test_name,
        input logic expected,
        input logic actual
    );
        total_tests++;
        if (actual === expected) begin
            $display("[PASS] %s: expected=%b, got=%b", test_name, expected, actual);
            tests_passed++;
        end else begin
            $display("[FAIL] %s: expected=%b, got=%b", test_name, expected, actual);
            tests_failed++;
        end
    endtask
    
    task automatic check_data_result(
        input string test_name,
        input logic [DATA_WIDTH-1:0] expected,
        input logic [DATA_WIDTH-1:0] actual
    );
        total_tests++;
        if (actual === expected) begin
            $display("[PASS] %s: expected=0x%016X, got=0x%016X", test_name, expected, actual);
            tests_passed++;
        end else begin
            $display("[FAIL] %s: expected=0x%016X, got=0x%016X", test_name, expected, actual);
            tests_failed++;
        end
    endtask
    
    task automatic reset();
        rst_n = 0;
        valid = 0;
        vote_func = VOTE_ANY;
        active_mask = 8'hFF;
        pred_input = 8'h00;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    
    initial begin
        $display("==============================================");
        $display("Warp Vote Unit Testbench");
        $display("==============================================");
        
        reset();
        
        //=====================================================================
        // Test 1: VOTE.ANY - Basic tests
        //=====================================================================
        $display("\n--- Test: VOTE.ANY ---");
        
        vote_func = VOTE_ANY;
        valid = 1;
        
        // All threads active, none have predicate true
        active_mask = 8'hFF;
        pred_input  = 8'h00;
        #1;
        check_pred_result("VOTE.ANY all active, none true", 1'b0, pred_result);
        
        // All threads active, one has predicate true
        pred_input = 8'h01;  // Thread 0 only
        #1;
        check_pred_result("VOTE.ANY all active, one true", 1'b1, pred_result);
        
        // All threads active, all have predicate true
        pred_input = 8'hFF;
        #1;
        check_pred_result("VOTE.ANY all active, all true", 1'b1, pred_result);
        
        // Partial mask, only inactive threads have predicate true
        active_mask = 8'h0F;  // Threads 0-3 active
        pred_input  = 8'hF0;  // Threads 4-7 true (but inactive)
        #1;
        check_pred_result("VOTE.ANY partial active, none active have true", 1'b0, pred_result);
        
        // Partial mask, one active thread has predicate true
        pred_input = 8'h02;  // Thread 1 true
        #1;
        check_pred_result("VOTE.ANY partial active, one active has true", 1'b1, pred_result);
        
        //=====================================================================
        // Test 2: VOTE.ALL - Basic tests
        //=====================================================================
        $display("\n--- Test: VOTE.ALL ---");
        
        vote_func = VOTE_ALL;
        
        // All threads active, all have predicate true
        active_mask = 8'hFF;
        pred_input  = 8'hFF;
        #1;
        check_pred_result("VOTE.ALL all active, all true", 1'b1, pred_result);
        
        // All threads active, one is false
        pred_input = 8'hFE;  // Thread 0 false
        #1;
        check_pred_result("VOTE.ALL all active, one false", 1'b0, pred_result);
        
        // All threads active, none are true
        pred_input = 8'h00;
        #1;
        check_pred_result("VOTE.ALL all active, none true", 1'b0, pred_result);
        
        // Partial mask, all active threads have predicate true
        active_mask = 8'h0F;  // Threads 0-3 active
        pred_input  = 8'h0F;  // Threads 0-3 true
        #1;
        check_pred_result("VOTE.ALL partial active, all active true", 1'b1, pred_result);
        
        // Partial mask, some inactive threads false doesn't matter
        pred_input = 8'h0F;  // Only active threads true
        #1;
        check_pred_result("VOTE.ALL partial, inactive threads ignored", 1'b1, pred_result);
        
        // Partial mask, one active thread is false
        pred_input = 8'h0E;  // Thread 0 false, others true
        #1;
        check_pred_result("VOTE.ALL partial, one active false", 1'b0, pred_result);
        
        //=====================================================================
        // Test 3: VOTE.NONE - Basic tests
        //=====================================================================
        $display("\n--- Test: VOTE.NONE ---");
        
        vote_func = VOTE_NONE;
        
        // All threads active, none have predicate true
        active_mask = 8'hFF;
        pred_input  = 8'h00;
        #1;
        check_pred_result("VOTE.NONE all active, none true", 1'b1, pred_result);
        
        // All threads active, one has predicate true
        pred_input = 8'h01;
        #1;
        check_pred_result("VOTE.NONE all active, one true", 1'b0, pred_result);
        
        // All threads active, all have predicate true
        pred_input = 8'hFF;
        #1;
        check_pred_result("VOTE.NONE all active, all true", 1'b0, pred_result);
        
        // Partial mask, inactive threads have predicate true (ignored)
        active_mask = 8'h0F;
        pred_input  = 8'hF0;  // Only inactive threads true
        #1;
        check_pred_result("VOTE.NONE partial, only inactive true", 1'b1, pred_result);
        
        //=====================================================================
        // Test 4: VOTE.BALLOT - Returns bitmask
        //=====================================================================
        $display("\n--- Test: VOTE.BALLOT ---");
        
        vote_func = VOTE_BALLOT;
        
        // All threads active, various patterns
        active_mask = 8'hFF;
        pred_input  = 8'hA5;  // 10100101
        #1;
        check_data_result("VOTE.BALLOT all active, pattern 0xA5", 64'h00000000000000A5, data_result);
        
        pred_input = 8'h00;
        #1;
        check_data_result("VOTE.BALLOT all active, none true", 64'h0000000000000000, data_result);
        
        pred_input = 8'hFF;
        #1;
        check_data_result("VOTE.BALLOT all active, all true", 64'h00000000000000FF, data_result);
        
        // Partial mask: result is (active_mask & pred_input)
        active_mask = 8'h0F;
        pred_input  = 8'hFF;  // All predicates true
        #1;
        check_data_result("VOTE.BALLOT partial mask, all preds true", 64'h000000000000000F, data_result);
        
        active_mask = 8'hF0;
        pred_input  = 8'hAA;  // Pattern 10101010
        #1;
        check_data_result("VOTE.BALLOT partial mask 0xF0, preds 0xAA", 64'h00000000000000A0, data_result);
        
        //=====================================================================
        // Test 5: VOTE.POPC - Population count of ballot
        //=====================================================================
        $display("\n--- Test: VOTE.POPC ---");
        
        vote_func = VOTE_POPC;
        
        // All threads active
        active_mask = 8'hFF;
        
        pred_input = 8'h00;  // 0 threads
        #1;
        check_data_result("VOTE.POPC none true", 64'd0, data_result);
        
        pred_input = 8'h01;  // 1 thread
        #1;
        check_data_result("VOTE.POPC 1 true", 64'd1, data_result);
        
        pred_input = 8'h03;  // 2 threads
        #1;
        check_data_result("VOTE.POPC 2 true", 64'd2, data_result);
        
        pred_input = 8'h0F;  // 4 threads
        #1;
        check_data_result("VOTE.POPC 4 true", 64'd4, data_result);
        
        pred_input = 8'hFF;  // 8 threads
        #1;
        check_data_result("VOTE.POPC 8 true", 64'd8, data_result);
        
        pred_input = 8'hA5;  // 4 threads (10100101)
        #1;
        check_data_result("VOTE.POPC pattern 0xA5 (4 bits)", 64'd4, data_result);
        
        // Partial mask
        active_mask = 8'h0F;  // Only threads 0-3 active
        pred_input  = 8'hFF;  // All preds true, but only 4 are active
        #1;
        check_data_result("VOTE.POPC partial mask 4 active", 64'd4, data_result);
        
        active_mask = 8'h55;  // Threads 0, 2, 4, 6 (4 threads)
        pred_input  = 8'h55;  // Same pattern
        #1;
        check_data_result("VOTE.POPC checkerboard mask", 64'd4, data_result);
        
        //=====================================================================
        // Test 6: Edge cases
        //=====================================================================
        $display("\n--- Test: Edge Cases ---");
        
        vote_func = VOTE_ANY;
        
        // No active threads
        active_mask = 8'h00;
        pred_input  = 8'hFF;
        #1;
        check_pred_result("VOTE.ANY no active threads", 1'b0, pred_result);
        
        vote_func = VOTE_ALL;
        // No active threads - ALL should be false for empty set
        #1;
        check_pred_result("VOTE.ALL no active threads", 1'b0, pred_result);
        
        vote_func = VOTE_NONE;
        // No active threads - NONE should be true (vacuous truth)
        #1;
        check_pred_result("VOTE.NONE no active threads", 1'b1, pred_result);
        
        vote_func = VOTE_BALLOT;
        // No active threads
        #1;
        check_data_result("VOTE.BALLOT no active threads", 64'd0, data_result);
        
        vote_func = VOTE_POPC;
        // No active threads
        #1;
        check_data_result("VOTE.POPC no active threads", 64'd0, data_result);
        
        // Single thread active
        active_mask = 8'h01;
        
        vote_func = VOTE_ANY;
        pred_input = 8'h01;
        #1;
        check_pred_result("VOTE.ANY single thread true", 1'b1, pred_result);
        
        pred_input = 8'h00;
        #1;
        check_pred_result("VOTE.ANY single thread false", 1'b0, pred_result);
        
        vote_func = VOTE_ALL;
        pred_input = 8'h01;
        #1;
        check_pred_result("VOTE.ALL single thread true", 1'b1, pred_result);
        
        pred_input = 8'h00;
        #1;
        check_pred_result("VOTE.ALL single thread false", 1'b0, pred_result);
        
        //=====================================================================
        // Test 7: Control signals
        //=====================================================================
        $display("\n--- Test: Control Signals ---");
        
        total_tests++;
        if (ready === 1'b1) begin
            $display("[PASS] Vote unit always ready");
            tests_passed++;
        end else begin
            $display("[FAIL] Vote unit should be ready");
            tests_failed++;
        end
        
        valid = 1;
        #1;
        total_tests++;
        if (done === 1'b1) begin
            $display("[PASS] Done asserted when valid");
            tests_passed++;
        end else begin
            $display("[FAIL] Done should be asserted when valid");
            tests_failed++;
        end
        
        valid = 0;
        #1;
        total_tests++;
        if (done === 1'b0) begin
            $display("[PASS] Done deasserted when not valid");
            tests_passed++;
        end else begin
            $display("[FAIL] Done should be deasserted when not valid");
            tests_failed++;
        end
        
        //=====================================================================
        // Summary
        //=====================================================================
        
        @(posedge clk);
        
        $display("\n==============================================");
        $display("Test Summary");
        $display("==============================================");
        $display("Total Tests: %0d", total_tests);
        $display("Passed:      %0d", tests_passed);
        $display("Failed:      %0d", tests_failed);
        $display("==============================================");
        
        if (tests_failed == 0) begin
            $display("\n*** ALL WARP VOTE TESTS PASSED ***\n");
        end else begin
            $display("\n*** SOME TESTS FAILED ***\n");
        end
        
        $finish;
    end

endmodule
