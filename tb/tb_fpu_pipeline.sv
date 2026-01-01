//=============================================================================
// GPGPU-1 Pipelined FPU Testbench
//=============================================================================
// File:        tb_fpu_pipeline.sv
// Description: Tests the pipelined FPU with operation-specific latencies
// Version:     1.0
// Date:        January 1, 2026
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_fpu_pipeline;
    import gpgpu_pkg::*;
    
    //=========================================================================
    // Parameters
    //=========================================================================
    
    parameter CLK_PERIOD = 10;
    
    // Expected latencies (from FPU module)
    localparam LATENCY_SIMPLE = 1;
    localparam LATENCY_ADD    = 3;
    localparam LATENCY_MUL    = 4;
    localparam LATENCY_FMA    = 5;
    localparam LATENCY_DIV    = 12;
    localparam LATENCY_SQRT   = 12;
    localparam LATENCY_CVT    = 2;
    
    //=========================================================================
    // DUT Signals
    //=========================================================================
    
    logic                                    clk;
    logic                                    rst_n;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]    operand_a;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]    operand_b;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]    operand_c;
    opcode_t                                 opcode;
    logic [FUNC_WIDTH-1:0]                   func;
    logic [WARP_SIZE-1:0]                    active_mask;
    logic                                    valid_in;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]    result;
    logic [WARP_SIZE-1:0]                    pred_result;
    logic                                    valid_out;
    logic                                    ready;
    
    //=========================================================================
    // Test Variables
    //=========================================================================
    
    int test_count;
    int pass_count;
    int fail_count;
    int cycle_count;
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    
    fpu dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .operand_a  (operand_a),
        .operand_b  (operand_b),
        .operand_c  (operand_c),
        .opcode     (opcode),
        .func       (func),
        .active_mask(active_mask),
        .valid_in   (valid_in),
        .result     (result),
        .pred_result(pred_result),
        .valid_out  (valid_out),
        .ready      (ready)
    );
    
    //=========================================================================
    // IEEE 754 Single Precision Constants
    //=========================================================================
    
    localparam logic [31:0] SP_ZERO      = 32'h00000000;
    localparam logic [31:0] SP_ONE       = 32'h3F800000;
    localparam logic [31:0] SP_TWO       = 32'h40000000;
    localparam logic [31:0] SP_THREE     = 32'h40400000;
    localparam logic [31:0] SP_FOUR      = 32'h40800000;
    localparam logic [31:0] SP_FIVE      = 32'h40A00000;
    localparam logic [31:0] SP_SIX       = 32'h40C00000;
    localparam logic [31:0] SP_TEN       = 32'h41200000;
    localparam logic [31:0] SP_FOURTEEN  = 32'h41600000;
    localparam logic [31:0] SP_NEG_ONE   = 32'hBF800000;
    
    //=========================================================================
    // Test Tasks
    //=========================================================================
    
    task automatic reset();
        rst_n = 1'b0;
        valid_in = 1'b0;
        opcode = OP_FADD;
        func = 8'h00;
        active_mask = 8'hFF;
        
        for (int i = 0; i < WARP_SIZE; i++) begin
            operand_a[i] = '0;
            operand_b[i] = '0;
            operand_c[i] = '0;
        end
        
        repeat(3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
    endtask
    
    task automatic check_latency(
        input string test_name,
        input opcode_t op,
        input int expected_latency
    );
        int actual_latency;
        
        test_count++;
        
        // Set up operation
        opcode = op;
        operand_a[0] = {32'h0, SP_TWO};
        operand_b[0] = {32'h0, SP_THREE};
        operand_c[0] = {32'h0, SP_ONE};
        valid_in = 1'b1;
        
        // Wait one cycle for input to be sampled
        @(posedge clk);
        #1;  // Let combinational logic settle
        valid_in = 1'b0;
        
        // Debug: check valid_out right after first edge
        if (expected_latency > 1)
            $display("  DEBUG: After edge 1: valid_out=%b", valid_out);
        
        // Count cycles until valid_out
        // We start at 1 because the pipeline registers the input on the first clock
        actual_latency = 1;
        while (!valid_out && actual_latency < 20) begin
            @(posedge clk);
            #1;  // Let combinational logic settle
            actual_latency++;
        end
        
        if (actual_latency == expected_latency) begin
            $display("[PASS] %s: Latency = %0d cycles (expected %0d)", 
                     test_name, actual_latency, expected_latency);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Latency = %0d cycles (expected %0d)", 
                     test_name, actual_latency, expected_latency);
            fail_count++;
        end
        
        // Drain pipeline - wait for valid_out to go low
        @(posedge clk);
        #1;
    endtask
    
    task automatic check_result(
        input string test_name,
        input logic expected_pass,
        input logic actual
    );
        test_count++;
        if (actual == expected_pass) begin
            $display("[PASS] %s", test_name);
            pass_count++;
        end else begin
            $display("[FAIL] %s: expected %b, got %b", test_name, expected_pass, actual);
            fail_count++;
        end
    endtask
    
    task automatic check_data_approx(
        input string test_name,
        input logic [31:0] expected,
        input logic [31:0] actual
    );
        // Allow 1 ULP difference for FP approximations
        logic [22:0] exp_mant, act_mant;
        logic [7:0]  exp_exp, act_exp;
        logic        exp_sign, act_sign;
        int          mant_diff;
        
        exp_sign = expected[31];
        exp_exp  = expected[30:23];
        exp_mant = expected[22:0];
        act_sign = actual[31];
        act_exp  = actual[30:23];
        act_mant = actual[22:0];
        
        test_count++;
        
        if (actual == expected) begin
            $display("[PASS] %s: 0x%08X", test_name, actual);
            pass_count++;
        end else if (exp_sign == act_sign && exp_exp == act_exp) begin
            mant_diff = (act_mant > exp_mant) ? (act_mant - exp_mant) : (exp_mant - act_mant);
            if (mant_diff <= 1) begin
                $display("[PASS] %s: 0x%08X (within 1 ULP of 0x%08X)", test_name, actual, expected);
                pass_count++;
            end else begin
                $display("[FAIL] %s: Expected 0x%08X, Got 0x%08X", test_name, expected, actual);
                fail_count++;
            end
        end else begin
            $display("[FAIL] %s: Expected 0x%08X, Got 0x%08X", test_name, expected, actual);
            fail_count++;
        end
    endtask
    
    //=========================================================================
    // Main Test
    //=========================================================================
    
    initial begin
        $display("==============================================");
        $display("Pipelined FPU Testbench");
        $display("==============================================");
        
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        reset();
        
        //=====================================================================
        // Test 1: Latency Tests
        //=====================================================================
        $display("\n--- Test 1: Operation Latency Tests ---");
        
        check_latency("FABS (simple)", OP_FABS, LATENCY_SIMPLE);
        check_latency("FNEG (simple)", OP_FNEG, LATENCY_SIMPLE);
        check_latency("FMIN (simple)", OP_FMIN, LATENCY_SIMPLE);
        check_latency("FMAX (simple)", OP_FMAX, LATENCY_SIMPLE);
        check_latency("FADD", OP_FADD, LATENCY_ADD);
        check_latency("FSUB", OP_FSUB, LATENCY_ADD);
        check_latency("FMUL", OP_FMUL, LATENCY_MUL);
        check_latency("FMADD", OP_FMADD, LATENCY_FMA);
        check_latency("FDIV", OP_FDIV, LATENCY_DIV);
        check_latency("FSQRT", OP_FSQRT, LATENCY_SQRT);
        
        //=====================================================================
        // Test 2: Pipeline Overlap
        //=====================================================================
        $display("\n--- Test 2: Pipeline Overlap Test ---");
        
        reset();
        
        // First, verify FABS works after reset (using same timing as check_latency)
        opcode = OP_FABS;
        operand_a[0] = {32'h0, SP_NEG_ONE};
        valid_in = 1'b1;
        @(posedge clk);  // FABS enters
        #1;
        valid_in = 1'b0;
        $display("DEBUG: Standalone FABS: valid_out=%b, result[0]=%h", valid_out, result[0][31:0]);
        if (result[0][31:0] != SP_ONE) begin
            $display("[DEBUG FAIL] Standalone FABS expected 0x3f800000, got 0x%08h", result[0][31:0]);
        end
        
        // Drain - wait for valid_out to go low
        @(posedge clk);
        #1;
        while (valid_out) begin
            @(posedge clk);
            #1;
        end
        
        // Now test overlap: Issue FADD (3 cycles), then immediately issue FABS (1 cycle)
        opcode = OP_FADD;
        operand_a[0] = {32'h0, SP_ONE};
        operand_b[0] = {32'h0, SP_ONE};
        valid_in = 1'b1;
        @(posedge clk);  // Cycle 1: FADD enters pipeline
        #1;
        
        // Issue FABS while FADD is in flight
        opcode = OP_FABS;
        operand_a[0] = {32'h0, SP_NEG_ONE};
        operand_b[0] = '0;
        @(posedge clk);  // Cycle 2: FABS enters pipeline
        #1;
        valid_in = 1'b0;
        // After cycle 2: FABS is in stage 0 with countdown=0, outputs now
        $display("DEBUG: Overlap FABS: valid_out=%b, result[0]=%h", valid_out, result[0][31:0]);
        check_result("FABS completes first", 1'b1, valid_out);
        check_data_approx("FABS result = 1.0", SP_ONE, result[0][31:0]);
        
        // Wait for FADD to complete
        @(posedge clk);  // Cycle 3
        #1;
        check_result("FADD completes after", 1'b1, valid_out);
        check_data_approx("FADD result = 2.0", SP_TWO, result[0][31:0]);
        
        //=====================================================================
        // Test 3: Back-to-back Operations
        //=====================================================================
        $display("\n--- Test 3: Back-to-back Same Operations ---");
        
        reset();
        
        // Issue 3 back-to-back FMUL operations
        opcode = OP_FMUL;
        
        // Op 1: 2 * 3 = 6
        operand_a[0] = {32'h0, SP_TWO};
        operand_b[0] = {32'h0, SP_THREE};
        valid_in = 1'b1;
        @(posedge clk);  // Cycle 1: Op1 enters
        #1;
        
        // Op 2: 1 * 5 = 5
        operand_a[0] = {32'h0, SP_ONE};
        operand_b[0] = {32'h0, SP_FIVE};
        @(posedge clk);  // Cycle 2: Op2 enters
        #1;
        
        // Op 3: 2 * 2 = 4
        operand_a[0] = {32'h0, SP_TWO};
        operand_b[0] = {32'h0, SP_TWO};
        @(posedge clk);  // Cycle 3: Op3 enters
        #1;
        valid_in = 1'b0;
        
        // FMUL latency = 4, so Op1 exits after 4 cycles from entering
        @(posedge clk);  // Cycle 4: Op1 should exit
        #1;
        check_result("First FMUL completes", 1'b1, valid_out);
        check_data_approx("First FMUL = 6.0", SP_SIX, result[0][31:0]);
        
        // Results should come out every cycle now
        @(posedge clk);  // Cycle 5: Op2 exits
        #1;
        check_result("Second FMUL completes", 1'b1, valid_out);
        check_data_approx("Second FMUL = 5.0", SP_FIVE, result[0][31:0]);
        
        @(posedge clk);  // Cycle 6: Op3 exits
        #1;
        check_result("Third FMUL completes", 1'b1, valid_out);
        check_data_approx("Third FMUL = 4.0", SP_FOUR, result[0][31:0]);
        
        //=====================================================================
        // Test 4: Ready Signal
        //=====================================================================
        $display("\n--- Test 4: Ready Signal ---");
        
        reset();
        check_result("FPU ready after reset", 1'b1, ready);
        
        // Issue an operation
        opcode = OP_FDIV;
        operand_a[0] = {32'h0, SP_SIX};
        operand_b[0] = {32'h0, SP_TWO};
        valid_in = 1'b1;
        @(posedge clk);
        #1;
        valid_in = 1'b0;
        
        // Ready should remain high (fully pipelined)
        check_result("FPU ready during FDIV", 1'b1, ready);
        
        //=====================================================================
        // Test 5: Multi-thread SIMD
        //=====================================================================
        $display("\n--- Test 5: Multi-thread SIMD ---");
        
        reset();
        
        opcode = OP_FADD;
        active_mask = 8'hFF;
        
        // Different operations per thread
        operand_a[0] = {32'h0, SP_ONE};   operand_b[0] = {32'h0, SP_ONE};   // 1+1=2
        operand_a[1] = {32'h0, SP_TWO};   operand_b[1] = {32'h0, SP_ONE};   // 2+1=3
        operand_a[2] = {32'h0, SP_THREE}; operand_b[2] = {32'h0, SP_ONE};   // 3+1=4
        operand_a[3] = {32'h0, SP_FOUR};  operand_b[3] = {32'h0, SP_ONE};   // 4+1=5
        operand_a[4] = {32'h0, SP_FIVE};  operand_b[4] = {32'h0, SP_ONE};   // 5+1=6
        operand_a[5] = {32'h0, SP_SIX};   operand_b[5] = {32'h0, SP_ONE};   // 6+1=7
        operand_a[6] = {32'h0, SP_ONE};   operand_b[6] = {32'h0, SP_SIX};   // 1+6=7
        operand_a[7] = {32'h0, SP_FOUR};  operand_b[7] = {32'h0, SP_TEN};   // 4+10=14
        
        valid_in = 1'b1;
        @(posedge clk);  // Cycle 1: FADD enters pipeline
        #1;
        valid_in = 1'b0;
        
        // FADD latency = 3, so result ready after 3 cycles total
        @(posedge clk);  // Cycle 2
        #1;
        
        @(posedge clk);  // Cycle 3: result ready
        #1;
        
        check_result("SIMD valid", 1'b1, valid_out);
        check_data_approx("Thread 0: 1+1=2", SP_TWO, result[0][31:0]);
        check_data_approx("Thread 1: 2+1=3", SP_THREE, result[1][31:0]);
        check_data_approx("Thread 2: 3+1=4", SP_FOUR, result[2][31:0]);
        check_data_approx("Thread 3: 4+1=5", SP_FIVE, result[3][31:0]);
        check_data_approx("Thread 4: 5+1=6", SP_SIX, result[4][31:0]);
        check_data_approx("Thread 7: 4+10=14", SP_FOURTEEN, result[7][31:0]);
        
        //=====================================================================
        // Summary
        //=====================================================================
        
        $display("\n==============================================");
        $display("Test Summary");
        $display("==============================================");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("==============================================");
        
        if (fail_count == 0) begin
            $display("\n*** ALL FPU PIPELINE TESTS PASSED ***\n");
        end else begin
            $display("\n*** SOME TESTS FAILED ***\n");
        end
        
        $finish;
    end

endmodule
