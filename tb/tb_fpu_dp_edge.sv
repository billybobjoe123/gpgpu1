//=============================================================================
// GPGPU-1 Double-Precision FPU Edge Cases Testbench
//=============================================================================
// Tests IEEE 754 edge cases: denormals, NaN, infinity, rounding modes

`include "gpgpu_defines.svh"

module tb_fpu_dp_edge;
    import gpgpu_pkg::*;
    
    logic clk;
    logic rst_n;
    
    // DUT signals
    logic              valid;
    fpu_op_t           operation;
    logic [63:0]       operand_a;
    logic [63:0]       operand_b;
    logic [63:0]       operand_c;
    logic [63:0]       result;
    logic              ready;
    
    // Test tracking
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // DUT instantiation
    fpu_dp dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid      (valid),
        .operation  (operation),
        .operand_a  (operand_a),
        .operand_b  (operand_b),
        .operand_c  (operand_c),
        .result     (result),
        .ready      (ready)
    );
    
    //=========================================================================
    // IEEE 754 Constants
    //=========================================================================
    
    // Special values
    localparam logic [63:0] POS_ZERO     = 64'h0000000000000000;
    localparam logic [63:0] NEG_ZERO     = 64'h8000000000000000;
    localparam logic [63:0] POS_INF      = 64'h7FF0000000000000;
    localparam logic [63:0] NEG_INF      = 64'hFFF0000000000000;
    localparam logic [63:0] QNAN         = 64'h7FF8000000000000;  // Quiet NaN
    localparam logic [63:0] SNAN         = 64'h7FF0000000000001;  // Signaling NaN
    
    // Denormalized numbers (exponent = 0, mantissa != 0)
    localparam logic [63:0] DENORM_MIN   = 64'h0000000000000001;  // Smallest denorm
    localparam logic [63:0] DENORM_MAX   = 64'h000FFFFFFFFFFFFF;  // Largest denorm
    localparam logic [63:0] NORM_MIN     = 64'h0010000000000000;  // Smallest normal
    
    // Test values near rounding boundaries
    localparam logic [63:0] ONE          = 64'h3FF0000000000000;  // 1.0
    localparam logic [63:0] TWO          = 64'h4000000000000000;  // 2.0
    localparam logic [63:0] HALF         = 64'h3FE0000000000000;  // 0.5
    
    //=========================================================================
    // Helper Tasks
    //=========================================================================
    
    task reset_dut();
        rst_n = 0;
        valid = 0;
        operation = FPU_ADD;
        operand_a = 0;
        operand_b = 0;
        operand_c = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask
    
    task perform_op(
        input fpu_op_t op,
        input logic [63:0] a,
        input logic [63:0] b,
        input logic [63:0] c = 0
    );
        valid = 1;
        operation = op;
        operand_a = a;
        operand_b = b;
        operand_c = c;
        @(posedge clk);
        valid = 0;
        wait(ready);
        @(posedge clk);
    endtask
    
    function automatic logic is_nan(logic [63:0] val);
        logic [10:0] exp;
        logic [51:0] frac;
        exp = val[62:52];
        frac = val[51:0];
        return (exp == 11'h7FF) && (frac != 0);
    endfunction
    
    function automatic logic is_inf(logic [63:0] val);
        logic [10:0] exp;
        logic [51:0] frac;
        exp = val[62:52];
        frac = val[51:0];
        return (exp == 11'h7FF) && (frac == 0);
    endfunction
    
    function automatic logic is_zero(logic [63:0] val);
        return (val[62:0] == 63'h0);
    endfunction
    
    task check(input string name, input logic [63:0] expected, input logic [63:0] actual);
        test_count++;
        if (expected == actual) begin
            $display("[PASS] %s", name);
            pass_count++;
        end else begin
            $display("[FAIL] %s: expected=%h, got=%h", name, expected, actual);
            fail_count++;
        end
    endtask
    
    task check_condition(input string name, input logic condition);
        test_count++;
        if (condition) begin
            $display("[PASS] %s", name);
            pass_count++;
        end else begin
            $display("[FAIL] %s", name);
            fail_count++;
        end
    endtask
    
    //=========================================================================
    // Test Sequence
    //=========================================================================
    
    initial begin
        $display("===========================================");
        $display("FPU Double-Precision Edge Cases Test");
        $display("===========================================");
        
        reset_dut();
        
        //---------------------------------------------------------------------
        // Test 1: Operations with Zero
        //---------------------------------------------------------------------
        $display("\n--- Test 1: Operations with Zero ---");
        
        // 0 + 0 = 0
        perform_op(FPU_ADD, POS_ZERO, POS_ZERO);
        check("0.0 + 0.0 = 0.0", POS_ZERO, result);
        
        // 0 + (-0) = 0 (sign of zero is positive by default)
        perform_op(FPU_ADD, POS_ZERO, NEG_ZERO);
        check_condition("0.0 + (-0.0) is zero", is_zero(result));
        
        // (-0) + (-0) = -0
        perform_op(FPU_ADD, NEG_ZERO, NEG_ZERO);
        check("-0.0 + (-0.0) = -0.0", NEG_ZERO, result);
        
        // 1 * 0 = 0
        perform_op(FPU_MUL, ONE, POS_ZERO);
        check("1.0 * 0.0 = 0.0", POS_ZERO, result);
        
        // 0 / 1 = 0
        perform_op(FPU_DIV, POS_ZERO, ONE);
        check("0.0 / 1.0 = 0.0", POS_ZERO, result);
        
        //---------------------------------------------------------------------
        // Test 2: Operations with Infinity
        //---------------------------------------------------------------------
        $display("\n--- Test 2: Operations with Infinity ---");
        
        // 1 + inf = inf
        perform_op(FPU_ADD, ONE, POS_INF);
        check("1.0 + inf = inf", POS_INF, result);
        
        // inf + inf = inf
        perform_op(FPU_ADD, POS_INF, POS_INF);
        check("inf + inf = inf", POS_INF, result);
        
        // inf - inf = NaN (indeterminate)
        perform_op(FPU_SUB, POS_INF, POS_INF);
        check_condition("inf - inf = NaN", is_nan(result));
        
        // 2 * inf = inf
        perform_op(FPU_MUL, TWO, POS_INF);
        check("2.0 * inf = inf", POS_INF, result);
        
        // inf / 2 = inf
        perform_op(FPU_DIV, POS_INF, TWO);
        check("inf / 2.0 = inf", POS_INF, result);
        
        // 1 / inf = 0
        perform_op(FPU_DIV, ONE, POS_INF);
        check("1.0 / inf = 0.0", POS_ZERO, result);
        
        // inf / inf = NaN
        perform_op(FPU_DIV, POS_INF, POS_INF);
        check_condition("inf / inf = NaN", is_nan(result));
        
        //---------------------------------------------------------------------
        // Test 3: Operations with NaN
        //---------------------------------------------------------------------
        $display("\n--- Test 3: Operations with NaN ---");
        
        // NaN + 1 = NaN (NaN propagates)
        perform_op(FPU_ADD, QNAN, ONE);
        check_condition("NaN + 1.0 = NaN", is_nan(result));
        
        // 1 + NaN = NaN
        perform_op(FPU_ADD, ONE, QNAN);
        check_condition("1.0 + NaN = NaN", is_nan(result));
        
        // NaN * 0 = NaN (not 0)
        perform_op(FPU_MUL, QNAN, POS_ZERO);
        check_condition("NaN * 0.0 = NaN", is_nan(result));
        
        // sqrt(-1) = NaN
        perform_op(FPU_SQRT, 64'hBFF0000000000000);  // -1.0
        check_condition("sqrt(-1.0) = NaN", is_nan(result));
        
        //---------------------------------------------------------------------
        // Test 4: Division Edge Cases
        //---------------------------------------------------------------------
        $display("\n--- Test 4: Division Edge Cases ---");
        
        // 1 / 0 = inf
        perform_op(FPU_DIV, ONE, POS_ZERO);
        check("1.0 / 0.0 = inf", POS_INF, result);
        
        // -1 / 0 = -inf
        perform_op(FPU_DIV, 64'hBFF0000000000000, POS_ZERO);  // -1.0
        check("-1.0 / 0.0 = -inf", NEG_INF, result);
        
        // 0 / 0 = NaN
        perform_op(FPU_DIV, POS_ZERO, POS_ZERO);
        check_condition("0.0 / 0.0 = NaN", is_nan(result));
        
        //---------------------------------------------------------------------
        // Test 5: Denormalized Numbers
        //---------------------------------------------------------------------
        $display("\n--- Test 5: Denormalized Numbers ---");
        
        // Denorm + 0 = Denorm
        perform_op(FPU_ADD, DENORM_MIN, POS_ZERO);
        check("denorm + 0.0 = denorm", DENORM_MIN, result);
        
        // Denorm * 1 = Denorm
        perform_op(FPU_MUL, DENORM_MIN, ONE);
        check("denorm * 1.0 = denorm", DENORM_MIN, result);
        
        // Denorm / 2 might underflow to zero (depends on implementation)
        perform_op(FPU_DIV, DENORM_MIN, TWO);
        check_condition("denorm / 2.0 underflows", is_zero(result) || result == DENORM_MIN);
        
        // Smallest normal - epsilon = denorm (gradual underflow)
        perform_op(FPU_SUB, NORM_MIN, DENORM_MIN);
        check_condition("norm_min - denorm_min produces denorm or norm", 
                       result <= NORM_MIN);
        
        //---------------------------------------------------------------------
        // Test 6: Rounding (Round-to-Nearest-Even)
        //---------------------------------------------------------------------
        $display("\n--- Test 6: Rounding Behavior ---");
        
        // 1.5 rounded (not exactly representable in some ops)
        // This is more about FMA: 1.5 * 1.0 + 0.0 should maintain precision
        perform_op(FPU_FMADD, 64'h3FF8000000000000, ONE, POS_ZERO);  // 1.5 * 1.0 + 0.0
        check("1.5 * 1.0 + 0.0 = 1.5", 64'h3FF8000000000000, result);
        
        //---------------------------------------------------------------------
        // Test 7: Min/Max with NaN and Inf
        //---------------------------------------------------------------------
        $display("\n--- Test 7: Min/Max Edge Cases ---");
        
        // min(1, NaN) = 1 (NaN is ignored in min/max)
        perform_op(FPU_MIN, ONE, QNAN);
        check("min(1.0, NaN) = 1.0", ONE, result);
        
        // max(1, inf) = inf
        perform_op(FPU_MAX, ONE, POS_INF);
        check("max(1.0, inf) = inf", POS_INF, result);
        
        // min(0, -0) = -0 (negative zero is less)
        perform_op(FPU_MIN, POS_ZERO, NEG_ZERO);
        check("min(0.0, -0.0) = -0.0", NEG_ZERO, result);
        
        //---------------------------------------------------------------------
        // Test 8: Absolute Value and Negation
        //---------------------------------------------------------------------
        $display("\n--- Test 8: Abs and Neg ---");
        
        // abs(-1) = 1
        perform_op(FPU_ABS, 64'hBFF0000000000000);  // -1.0
        check("abs(-1.0) = 1.0", ONE, result);
        
        // abs(-0) = 0
        perform_op(FPU_ABS, NEG_ZERO);
        check("abs(-0.0) = 0.0", POS_ZERO, result);
        
        // abs(inf) = inf
        perform_op(FPU_ABS, NEG_INF);
        check("abs(-inf) = inf", POS_INF, result);
        
        // neg(inf) = -inf
        perform_op(FPU_NEG, POS_INF);
        check("neg(inf) = -inf", NEG_INF, result);
        
        // neg(-0) = 0
        perform_op(FPU_NEG, NEG_ZERO);
        check("neg(-0.0) = 0.0", POS_ZERO, result);
        
        //---------------------------------------------------------------------
        // Test 9: Square Root Edge Cases
        //---------------------------------------------------------------------
        $display("\n--- Test 9: Square Root ---");
        
        // sqrt(0) = 0
        perform_op(FPU_SQRT, POS_ZERO);
        check("sqrt(0.0) = 0.0", POS_ZERO, result);
        
        // sqrt(inf) = inf
        perform_op(FPU_SQRT, POS_INF);
        check("sqrt(inf) = inf", POS_INF, result);
        
        // sqrt(negative) = NaN (already tested above)
        
        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        $display("\n===========================================");
        $display("Test Summary");
        $display("===========================================");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("===========================================");
        
        if (fail_count == 0) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("*** SOME TESTS FAILED ***");
        end
        
        $finish;
    end
    
    // Timeout
    initial begin
        #50000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
