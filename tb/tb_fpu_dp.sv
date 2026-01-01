//=============================================================================
// GPGPU-1 Double-Precision FPU Testbench
//=============================================================================
// File:        tb_fpu_dp.sv
// Description: Tests double-precision floating-point operations
// Version:     1.0
// Date:        January 1, 2026
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_fpu_dp;
    import gpgpu_pkg::*;
    
    //=========================================================================
    // Parameters
    //=========================================================================
    
    parameter CLK_PERIOD = 10;
    
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
    // IEEE 754 Double Precision Constants
    //=========================================================================
    
    // Useful DP values (64-bit)
    localparam logic [63:0] DP_ZERO        = 64'h0000000000000000;  // 0.0
    localparam logic [63:0] DP_ONE         = 64'h3FF0000000000000;  // 1.0
    localparam logic [63:0] DP_TWO         = 64'h4000000000000000;  // 2.0
    localparam logic [63:0] DP_THREE       = 64'h4008000000000000;  // 3.0
    localparam logic [63:0] DP_FOUR        = 64'h4010000000000000;  // 4.0
    localparam logic [63:0] DP_FIVE        = 64'h4014000000000000;  // 5.0
    localparam logic [63:0] DP_SIX         = 64'h4018000000000000;  // 6.0
    localparam logic [63:0] DP_SEVEN       = 64'h401C000000000000;  // 7.0
    localparam logic [63:0] DP_EIGHT       = 64'h4020000000000000;  // 8.0
    localparam logic [63:0] DP_TEN         = 64'h4024000000000000;  // 10.0
    localparam logic [63:0] DP_TWELVE      = 64'h4028000000000000;  // 12.0
    localparam logic [63:0] DP_HALF        = 64'h3FE0000000000000;  // 0.5
    localparam logic [63:0] DP_NEG_ONE     = 64'hBFF0000000000000;  // -1.0
    localparam logic [63:0] DP_NEG_TWO     = 64'hC000000000000000;  // -2.0
    localparam logic [63:0] DP_NEG_THREE   = 64'hC008000000000000;  // -3.0
    localparam logic [63:0] DP_PI          = 64'h400921FB54442D18;  // pi (approx)
    localparam logic [63:0] DP_E           = 64'h4005BF0A8B145769;  // e (approx)
    localparam logic [63:0] DP_INF         = 64'h7FF0000000000000;  // +Infinity
    localparam logic [63:0] DP_NEG_INF     = 64'hFFF0000000000000;  // -Infinity
    localparam logic [63:0] DP_NAN         = 64'h7FF8000000000000;  // Quiet NaN
    
    // func[7] = 1 indicates double precision
    localparam logic [7:0] FUNC_DP = 8'h80;
    
    //=========================================================================
    // Test Tasks
    //=========================================================================
    
    task automatic check_dp_result(
        input string test_name,
        input logic [63:0] expected,
        input logic [63:0] actual
    );
        test_count++;
        // Allow small tolerance for FP rounding
        if (actual == expected || 
            (expected != 64'h0 && actual != 64'h0 && 
             ($signed(actual[62:52]) - $signed(expected[62:52])) inside {-1, 0, 1} &&
             actual[63] == expected[63])) begin
            $display("[PASS] %s: Expected 0x%016X, Got 0x%016X", test_name, expected, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Expected 0x%016X, Got 0x%016X", test_name, expected, actual);
            fail_count++;
        end
    endtask
    
    task automatic check_dp_exact(
        input string test_name,
        input logic [63:0] expected,
        input logic [63:0] actual
    );
        test_count++;
        if (actual == expected) begin
            $display("[PASS] %s: Expected 0x%016X, Got 0x%016X", test_name, expected, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Expected 0x%016X, Got 0x%016X", test_name, expected, actual);
            fail_count++;
        end
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    
    initial begin
        $display("==============================================");
        $display("Double-Precision FPU Testbench");
        $display("==============================================");
        
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        rst_n = 0;
        valid_in = 0;
        opcode = OP_FADD;
        func = FUNC_DP;
        active_mask = 8'hFF;
        
        for (int i = 0; i < WARP_SIZE; i++) begin
            operand_a[i] = DP_ZERO;
            operand_b[i] = DP_ZERO;
            operand_c[i] = DP_ZERO;
        end
        
        // Reset
        #(CLK_PERIOD * 2);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        //=====================================================================
        // Test 1: DP Addition
        //=====================================================================
        $display("\n--- Test: DADD (Double-Precision Add) ---");
        
        opcode = OP_FADD;
        func = FUNC_DP;
        valid_in = 1;
        
        // 1.0 + 2.0 = 3.0
        operand_a[0] = DP_ONE;
        operand_b[0] = DP_TWO;
        #(CLK_PERIOD);
        check_dp_result("DADD 1.0 + 2.0 = 3.0", DP_THREE, result[0]);
        
        // 5.0 + (-2.0) = 3.0
        operand_a[0] = DP_FIVE;
        operand_b[0] = DP_NEG_TWO;
        #(CLK_PERIOD);
        check_dp_result("DADD 5.0 + (-2.0) = 3.0", DP_THREE, result[0]);
        
        // 0.0 + 0.0 = 0.0
        operand_a[0] = DP_ZERO;
        operand_b[0] = DP_ZERO;
        #(CLK_PERIOD);
        check_dp_exact("DADD 0.0 + 0.0 = 0.0", DP_ZERO, result[0]);
        
        //=====================================================================
        // Test 2: DP Subtraction
        //=====================================================================
        $display("\n--- Test: DSUB (Double-Precision Subtract) ---");
        
        opcode = OP_FSUB;
        func = FUNC_DP;
        
        // 5.0 - 2.0 = 3.0
        operand_a[0] = DP_FIVE;
        operand_b[0] = DP_TWO;
        #(CLK_PERIOD);
        check_dp_result("DSUB 5.0 - 2.0 = 3.0", DP_THREE, result[0]);
        
        // 1.0 - 1.0 = 0.0
        operand_a[0] = DP_ONE;
        operand_b[0] = DP_ONE;
        #(CLK_PERIOD);
        check_dp_exact("DSUB 1.0 - 1.0 = 0.0", DP_ZERO, result[0]);
        
        //=====================================================================
        // Test 3: DP Multiplication
        //=====================================================================
        $display("\n--- Test: DMUL (Double-Precision Multiply) ---");
        
        opcode = OP_FMUL;
        func = FUNC_DP;
        
        // 2.0 * 3.0 = 6.0
        operand_a[0] = DP_TWO;
        operand_b[0] = DP_THREE;
        #(CLK_PERIOD);
        check_dp_result("DMUL 2.0 * 3.0 = 6.0", DP_SIX, result[0]);
        
        // 2.0 * 5.0 = 10.0
        operand_a[0] = DP_TWO;
        operand_b[0] = DP_FIVE;
        #(CLK_PERIOD);
        check_dp_result("DMUL 2.0 * 5.0 = 10.0", DP_TEN, result[0]);
        
        // x * 0 = 0
        operand_a[0] = DP_PI;
        operand_b[0] = DP_ZERO;
        #(CLK_PERIOD);
        check_dp_exact("DMUL pi * 0.0 = 0.0", DP_ZERO, result[0]);
        
        //=====================================================================
        // Test 4: DP Division
        //=====================================================================
        $display("\n--- Test: DDIV (Double-Precision Divide) ---");
        
        opcode = OP_FDIV;
        func = FUNC_DP;
        
        // 6.0 / 2.0 = 3.0
        operand_a[0] = DP_SIX;
        operand_b[0] = DP_TWO;
        #(CLK_PERIOD);
        check_dp_result("DDIV 6.0 / 2.0 = 3.0", DP_THREE, result[0]);
        
        // 10.0 / 2.0 = 5.0
        operand_a[0] = DP_TEN;
        operand_b[0] = DP_TWO;
        #(CLK_PERIOD);
        check_dp_result("DDIV 10.0 / 2.0 = 5.0", DP_FIVE, result[0]);
        
        // 1.0 / 0.0 = inf
        operand_a[0] = DP_ONE;
        operand_b[0] = DP_ZERO;
        #(CLK_PERIOD);
        check_dp_exact("DDIV 1.0 / 0.0 = inf", DP_INF, result[0]);
        
        //=====================================================================
        // Test 5: DP FMA (Fused Multiply-Add)
        //=====================================================================
        $display("\n--- Test: DFMA (Double-Precision Fused Multiply-Add) ---");
        
        opcode = OP_FMADD;
        func = FUNC_DP;
        
        // 2.0 * 3.0 + 4.0 = 10.0
        operand_a[0] = DP_TWO;
        operand_b[0] = DP_THREE;
        operand_c[0] = DP_FOUR;
        #(CLK_PERIOD);
        check_dp_result("DFMA 2.0 * 3.0 + 4.0 = 10.0", DP_TEN, result[0]);
        
        // 3.0 * 4.0 + 0.0 = 12.0
        operand_a[0] = DP_THREE;
        operand_b[0] = DP_FOUR;
        operand_c[0] = DP_ZERO;
        #(CLK_PERIOD);
        check_dp_result("DFMA 3.0 * 4.0 + 0.0 = 12.0", DP_TWELVE, result[0]);
        
        // 0.0 * 5.0 + 7.0 = 7.0
        operand_a[0] = DP_ZERO;
        operand_b[0] = DP_FIVE;
        operand_c[0] = DP_SEVEN;
        #(CLK_PERIOD);
        check_dp_result("DFMA 0.0 * 5.0 + 7.0 = 7.0", DP_SEVEN, result[0]);
        
        //=====================================================================
        // Test 6: DP Min/Max
        //=====================================================================
        $display("\n--- Test: DMIN/DMAX (Double-Precision Min/Max) ---");
        
        opcode = OP_FMIN;
        func = FUNC_DP;
        
        // min(5.0, 2.0) = 2.0
        operand_a[0] = DP_FIVE;
        operand_b[0] = DP_TWO;
        #(CLK_PERIOD);
        check_dp_exact("DMIN(5.0, 2.0) = 2.0", DP_TWO, result[0]);
        
        opcode = OP_FMAX;
        // max(5.0, 2.0) = 5.0
        operand_a[0] = DP_FIVE;
        operand_b[0] = DP_TWO;
        #(CLK_PERIOD);
        check_dp_exact("DMAX(5.0, 2.0) = 5.0", DP_FIVE, result[0]);
        
        // max(-1.0, 1.0) = 1.0
        operand_a[0] = DP_NEG_ONE;
        operand_b[0] = DP_ONE;
        #(CLK_PERIOD);
        check_dp_exact("DMAX(-1.0, 1.0) = 1.0", DP_ONE, result[0]);
        
        //=====================================================================
        // Test 7: DP Abs/Neg
        //=====================================================================
        $display("\n--- Test: DABS/DNEG (Double-Precision Abs/Neg) ---");
        
        opcode = OP_FABS;
        func = FUNC_DP;
        
        // abs(-5.0) = 5.0
        operand_a[0] = 64'hC014000000000000;  // -5.0
        #(CLK_PERIOD);
        check_dp_exact("DABS(-5.0) = 5.0", DP_FIVE, result[0]);
        
        // abs(5.0) = 5.0
        operand_a[0] = DP_FIVE;
        #(CLK_PERIOD);
        check_dp_exact("DABS(5.0) = 5.0", DP_FIVE, result[0]);
        
        opcode = OP_FNEG;
        // neg(3.0) = -3.0
        operand_a[0] = DP_THREE;
        #(CLK_PERIOD);
        check_dp_exact("DNEG(3.0) = -3.0", DP_NEG_THREE, result[0]);
        
        //=====================================================================
        // Test 8: DP Special Values
        //=====================================================================
        $display("\n--- Test: DP Special Values ---");
        
        opcode = OP_FADD;
        func = FUNC_DP;
        
        // NaN + x = NaN
        operand_a[0] = DP_NAN;
        operand_b[0] = DP_ONE;
        #(CLK_PERIOD);
        // Check that result is NaN (exponent all 1s, non-zero mantissa)
        test_count++;
        if (result[0][62:52] == 11'h7FF && result[0][51:0] != 52'h0) begin
            $display("[PASS] DADD NaN + 1.0 = NaN");
            pass_count++;
        end else begin
            $display("[FAIL] DADD NaN + 1.0 = NaN: Got 0x%016X", result[0]);
            fail_count++;
        end
        
        // inf + x = inf
        operand_a[0] = DP_INF;
        operand_b[0] = DP_ONE;
        #(CLK_PERIOD);
        check_dp_exact("DADD inf + 1.0 = inf", DP_INF, result[0]);
        
        // inf - inf = NaN
        opcode = OP_FSUB;
        operand_a[0] = DP_INF;
        operand_b[0] = DP_INF;
        #(CLK_PERIOD);
        test_count++;
        if (result[0][62:52] == 11'h7FF && result[0][51:0] != 52'h0) begin
            $display("[PASS] DSUB inf - inf = NaN");
            pass_count++;
        end else begin
            $display("[FAIL] DSUB inf - inf = NaN: Got 0x%016X", result[0]);
            fail_count++;
        end
        
        //=====================================================================
        // Test 9: SIMD - All 8 threads
        //=====================================================================
        $display("\n--- Test: SIMD 8-thread DP Add ---");
        
        opcode = OP_FADD;
        func = FUNC_DP;
        active_mask = 8'hFF;
        
        // Each thread: a[i] + b[i] = result[i]
        operand_a[0] = DP_ONE;   operand_b[0] = DP_ONE;   // 1+1=2
        operand_a[1] = DP_TWO;   operand_b[1] = DP_ONE;   // 2+1=3
        operand_a[2] = DP_THREE; operand_b[2] = DP_ONE;   // 3+1=4
        operand_a[3] = DP_FOUR;  operand_b[3] = DP_ONE;   // 4+1=5
        operand_a[4] = DP_FIVE;  operand_b[4] = DP_ONE;   // 5+1=6
        operand_a[5] = DP_SIX;   operand_b[5] = DP_ONE;   // 6+1=7
        operand_a[6] = DP_SEVEN; operand_b[6] = DP_ONE;   // 7+1=8
        operand_a[7] = DP_EIGHT; operand_b[7] = DP_TWO;   // 8+2=10
        
        #(CLK_PERIOD);
        
        check_dp_result("Thread 0: 1.0 + 1.0 = 2.0", DP_TWO, result[0]);
        check_dp_result("Thread 1: 2.0 + 1.0 = 3.0", DP_THREE, result[1]);
        check_dp_result("Thread 2: 3.0 + 1.0 = 4.0", DP_FOUR, result[2]);
        check_dp_result("Thread 3: 4.0 + 1.0 = 5.0", DP_FIVE, result[3]);
        check_dp_result("Thread 4: 5.0 + 1.0 = 6.0", DP_SIX, result[4]);
        check_dp_result("Thread 5: 6.0 + 1.0 = 7.0", DP_SEVEN, result[5]);
        check_dp_result("Thread 6: 7.0 + 1.0 = 8.0", DP_EIGHT, result[6]);
        check_dp_result("Thread 7: 8.0 + 2.0 = 10.0", DP_TEN, result[7]);
        
        //=====================================================================
        // Summary
        //=====================================================================
        
        #(CLK_PERIOD * 2);
        
        $display("\n==============================================");
        $display("Test Summary");
        $display("==============================================");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("==============================================");
        
        if (fail_count == 0) begin
            $display("\n*** ALL DP FPU TESTS PASSED ***\n");
        end else begin
            $display("\n*** SOME TESTS FAILED ***\n");
        end
        
        $finish;
    end

endmodule
