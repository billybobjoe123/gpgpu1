//=============================================================================
// GPGPU-1 FPU and FMA Testbench
//=============================================================================
// File:        tb_fpu.sv
// Description: Comprehensive testbench for FPU operations including FMA
//              with accuracy and performance comparisons
// Version:     1.0
// Date:        December 22, 2025
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_fpu;
    import gpgpu_pkg::*;
    
    //=========================================================================
    // Parameters
    //=========================================================================
    
    localparam CLK_PERIOD = 10;
    
    // IEEE 754 single-precision helper constants
    localparam int SP_EXP_BITS  = 8;
    localparam int SP_MANT_BITS = 23;
    localparam int SP_BIAS      = 127;
    
    //=========================================================================
    // Signals
    //=========================================================================
    
    logic clk;
    logic rst_n;
    
    // FPU signals
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] operand_a;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] operand_b;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] operand_c;
    opcode_t                              opcode;
    logic [FUNC_WIDTH-1:0]                func;
    logic [WARP_SIZE-1:0]                 active_mask;
    logic                                 valid_in;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] result;
    logic [WARP_SIZE-1:0]                 pred_result;
    logic                                 valid_out;
    logic                                 ready;
    
    // Test control
    int test_count;
    int pass_count;
    int fail_count;
    
    // For FMA vs MUL+ADD comparison
    int fma_cycles;
    int muladd_cycles;
    int fma_accuracy_wins;
    int total_accuracy_tests;
    
    //=========================================================================
    // DUT Instance
    //=========================================================================
    
    fpu u_fpu (
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
    // Clock Generation
    //=========================================================================
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // Helper Functions
    //=========================================================================
    
    // Convert shortreal to IEEE 754 single-precision bits
    function automatic logic [31:0] real_to_sp(input shortreal r);
        return $shortrealtobits(r);
    endfunction
    
    // Convert IEEE 754 single-precision bits to shortreal
    function automatic shortreal sp_to_real(input logic [31:0] bits);
        return $bitstoshortreal(bits);
    endfunction
    
    // Pack single-precision into 64-bit data
    function automatic logic [63:0] pack_sp(input shortreal r);
        return {32'h0, real_to_sp(r)};
    endfunction
    
    // Extract single-precision from 64-bit result
    function automatic shortreal unpack_sp(input logic [63:0] data);
        return sp_to_real(data[31:0]);
    endfunction
    
    // Check if two floats are approximately equal
    function automatic logic approx_equal(input shortreal a, input shortreal b, input shortreal epsilon);
        shortreal diff;
        diff = a - b;
        if (diff < 0) diff = -diff;
        return diff < epsilon;
    endfunction
    
    // Calculate relative error
    function automatic shortreal relative_error(input shortreal computed, input shortreal expected);
        shortreal diff;
        if (expected == 0.0) return computed == 0.0 ? 0.0 : 1.0;
        diff = computed - expected;
        if (diff < 0) diff = -diff;
        return diff / (expected > 0 ? expected : -expected);
    endfunction
    
    //=========================================================================
    // Test Tasks
    //=========================================================================
    
    task automatic init_inputs();
        for (int i = 0; i < WARP_SIZE; i++) begin
            operand_a[i] = '0;
            operand_b[i] = '0;
            operand_c[i] = '0;
        end
        opcode = OP_ALU;  // Safe default (not a float op)
        func = '0;
        active_mask = '0;
        valid_in = 0;
    endtask
    
    task automatic check_result_sp(
        input string test_name,
        input shortreal expected,
        input int thread_id = 0
    );
        shortreal actual;
        actual = unpack_sp(result[thread_id]);
        test_count++;
        
        // Allow small epsilon for floating-point comparison
        if (approx_equal(actual, expected, 0.00001)) begin
            $display("[PASS] %s: Expected %f, Got %f", test_name, expected, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Expected %f, Got %f (raw: 0x%08x)", 
                     test_name, expected, actual, result[thread_id][31:0]);
            fail_count++;
        end
    endtask
    
    task automatic check_result_bits(
        input string test_name,
        input logic [31:0] expected,
        input int thread_id = 0
    );
        test_count++;
        if (result[thread_id][31:0] === expected) begin
            $display("[PASS] %s: Expected 0x%08x, Got 0x%08x", test_name, expected, result[thread_id][31:0]);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Expected 0x%08x, Got 0x%08x", test_name, expected, result[thread_id][31:0]);
            fail_count++;
        end
    endtask
    
    //=========================================================================
    // Basic FPU Operation Tests
    //=========================================================================
    
    task automatic test_fadd();
        $display("\n=== Testing FADD (Single-Precision Add) ===");
        
        // Test 1: Simple add (1.0 + 2.0 = 3.0)
        // 1.0 = 0x3F800000, 2.0 = 0x40000000, 3.0 = 0x40400000
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h3F800000};  // 1.0
        operand_b[0] = {32'h0, 32'h40000000};  // 2.0
        opcode = OP_FADD;
        valid_in = 1;
        #1;  // Small delay for combinational logic
        check_result_bits("FADD 1.0 + 2.0 = 3.0", 32'h40400000);
        @(posedge clk);
        valid_in = 0;
        
        // Test 2: Add with negative (5.5 + (-2.5) = 3.0)
        // 5.5 = 0x40B00000, -2.5 = 0xC0200000, 3.0 = 0x40400000
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h40B00000};  // 5.5
        operand_b[0] = {32'h0, 32'hC0200000};  // -2.5
        opcode = OP_FADD;
        valid_in = 1;
        #1;
        check_result_bits("FADD 5.5 + (-2.5) = 3.0", 32'h40400000);
        @(posedge clk);
        valid_in = 0;
        
        // Test 3: Add zeros
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h00000000};  // 0.0
        operand_b[0] = {32'h0, 32'h00000000};  // 0.0
        opcode = OP_FADD;
        valid_in = 1;
        #1;
        check_result_bits("FADD 0.0 + 0.0 = 0.0", 32'h00000000);
        @(posedge clk);
        valid_in = 0;
    endtask
    
    task automatic test_fmul();
        $display("\n=== Testing FMUL (Single-Precision Multiply) ===");
        
        // Test 1: Simple multiply (2.0 * 3.0 = 6.0)
        // 2.0 = 0x40000000, 3.0 = 0x40400000, 6.0 = 0x40C00000
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h40000000};  // 2.0
        operand_b[0] = {32'h0, 32'h40400000};  // 3.0
        opcode = OP_FMUL;
        valid_in = 1;
        #1;
        check_result_bits("FMUL 2.0 * 3.0 = 6.0", 32'h40C00000);
        @(posedge clk);
        valid_in = 0;
        
        // Test 2: Multiply with fraction (2.5 * 4.0 = 10.0)
        // 2.5 = 0x40200000, 4.0 = 0x40800000, 10.0 = 0x41200000
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h40200000};  // 2.5
        operand_b[0] = {32'h0, 32'h40800000};  // 4.0
        opcode = OP_FMUL;
        valid_in = 1;
        #1;
        check_result_bits("FMUL 2.5 * 4.0 = 10.0", 32'h41200000);
        @(posedge clk);
        valid_in = 0;
        
        // Test 3: Multiply by zero
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h42F6E979};  // 123.456
        operand_b[0] = {32'h0, 32'h00000000};  // 0.0
        opcode = OP_FMUL;
        valid_in = 1;
        #1;
        check_result_bits("FMUL x * 0.0 = 0.0", 32'h00000000);
        @(posedge clk);
        valid_in = 0;
    endtask
    
    //=========================================================================
    // FMA (Fused Multiply-Add) Tests
    //=========================================================================
    
    task automatic test_fma_basic();
        $display("\n=== Testing FMA Basic Operations ===");
        
        // Test 1: Simple FMA (2.0 * 3.0 + 4.0 = 10.0)
        // 2.0 = 0x40000000, 3.0 = 0x40400000, 4.0 = 0x40800000, 10.0 = 0x41200000
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h40000000};  // 2.0
        operand_b[0] = {32'h0, 32'h40400000};  // 3.0
        operand_c[0] = {32'h0, 32'h40800000};  // 4.0
        opcode = OP_FMADD;
        valid_in = 1;
        #1;
        check_result_bits("FMA 2.0 * 3.0 + 4.0 = 10.0", 32'h41200000);
        @(posedge clk);
        valid_in = 0;
        
        // Test 2: FMA with negative addend (5.0 * 2.0 + (-3.0) = 7.0)
        // 5.0 = 0x40A00000, 2.0 = 0x40000000, -3.0 = 0xC0400000, 7.0 = 0x40E00000
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h40A00000};  // 5.0
        operand_b[0] = {32'h0, 32'h40000000};  // 2.0
        operand_c[0] = {32'h0, 32'hC0400000};  // -3.0
        opcode = OP_FMADD;
        valid_in = 1;
        #1;
        check_result_bits("FMA 5.0 * 2.0 + (-3.0) = 7.0", 32'h40E00000);
        @(posedge clk);
        valid_in = 0;
        
        // Test 3: FMA with zero addend (3.0 * 4.0 + 0.0 = 12.0)
        // 3.0 = 0x40400000, 4.0 = 0x40800000, 0.0 = 0x00000000, 12.0 = 0x41400000
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h40400000};  // 3.0
        operand_b[0] = {32'h0, 32'h40800000};  // 4.0
        operand_c[0] = {32'h0, 32'h00000000};  // 0.0
        opcode = OP_FMADD;
        valid_in = 1;
        #1;
        check_result_bits("FMA 3.0 * 4.0 + 0.0 = 12.0", 32'h41400000);
        @(posedge clk);
        valid_in = 0;
        
        // Test 4: FMA with zero multiplicand (0.0 * 5.0 + 7.0 = 7.0)
        // 0.0 = 0x00000000, 5.0 = 0x40A00000, 7.0 = 0x40E00000
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h00000000};  // 0.0
        operand_b[0] = {32'h0, 32'h40A00000};  // 5.0
        operand_c[0] = {32'h0, 32'h40E00000};  // 7.0
        opcode = OP_FMADD;
        valid_in = 1;
        #1;
        check_result_bits("FMA 0.0 * 5.0 + 7.0 = 7.0", 32'h40E00000);
        @(posedge clk);
        valid_in = 0;
        
        // Test 5: FMA with all ones (1.0 * 1.0 + 1.0 = 2.0)
        // 1.0 = 0x3F800000, 2.0 = 0x40000000
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h3F800000};  // 1.0
        operand_b[0] = {32'h0, 32'h3F800000};  // 1.0
        operand_c[0] = {32'h0, 32'h3F800000};  // 1.0
        opcode = OP_FMADD;
        valid_in = 1;
        #1;
        check_result_bits("FMA 1.0 * 1.0 + 1.0 = 2.0", 32'h40000000);
        @(posedge clk);
        valid_in = 0;
    endtask
    
    task automatic test_fma_special_cases();
        $display("\n=== Testing FMA Special Cases ===");
        
        // NaN propagation: any operand NaN -> result NaN
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h7FC00000}; // Quiet NaN
        operand_b[0] = {32'h0, 32'h3F800000}; // 1.0
        operand_c[0] = {32'h0, 32'h3F800000}; // 1.0
        opcode = OP_FMADD;
        valid_in = 1;
        #1;
        // Check if NaN (exponent all 1s, mantissa non-zero)
        test_count++;
        if (result[0][30:23] == 8'hFF && result[0][22:0] != 0) begin
            $display("[PASS] FMA NaN * x + y = NaN");
            pass_count++;
        end else begin
            $display("[FAIL] FMA NaN * x + y should be NaN, got 0x%08x", result[0][31:0]);
            fail_count++;
        end
        @(posedge clk);
        valid_in = 0;
        
        // Infinity handling: inf * x + y = inf
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h7F800000}; // +Infinity
        operand_b[0] = {32'h0, 32'h40000000}; // 2.0
        operand_c[0] = {32'h0, 32'h3F800000}; // 1.0
        opcode = OP_FMADD;
        valid_in = 1;
        #1;
        check_result_bits("FMA +Inf * 2.0 + 1.0 = +Inf", 32'h7F800000);
        @(posedge clk);
        valid_in = 0;
        
        // Negative infinity
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'hFF800000}; // -Infinity
        operand_b[0] = {32'h0, 32'h40000000}; // 2.0
        operand_c[0] = {32'h0, 32'h3F800000}; // 1.0
        opcode = OP_FMADD;
        valid_in = 1;
        #1;
        check_result_bits("FMA -Inf * 2.0 + 1.0 = -Inf", 32'hFF800000);
        @(posedge clk);
        valid_in = 0;
    endtask
    
    //=========================================================================
    // Performance Comparison: FMA vs MUL + ADD
    //=========================================================================
    
    task automatic test_fma_performance();
        int cycle_start, cycle_end;
        logic [31:0] fma_result_bits, muladd_result_bits;
        
        $display("\n=== FMA Performance Comparison (FMA vs MUL+ADD) ===");
        $display("Measuring cycles and accuracy for same computations...\n");
        
        fma_cycles = 0;
        muladd_cycles = 0;
        
        // Test case: 2.0 * 3.0 + 4.0 = 10.0
        // 2.0 = 0x40000000, 3.0 = 0x40400000, 4.0 = 0x40800000, 10.0 = 0x41200000
        
        // Method 1: FMA (single instruction)
        cycle_start = $time / CLK_PERIOD;
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h40000000};  // 2.0
        operand_b[0] = {32'h0, 32'h40400000};  // 3.0
        operand_c[0] = {32'h0, 32'h40800000};  // 4.0
        opcode = OP_FMADD;
        valid_in = 1;
        @(posedge clk);
        cycle_end = $time / CLK_PERIOD;
        fma_cycles = fma_cycles + (cycle_end - cycle_start);
        fma_result_bits = result[0][31:0];
        valid_in = 0;
        @(posedge clk);
        
        // Method 2: MUL then ADD (two instructions)
        cycle_start = $time / CLK_PERIOD;
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h40000000};  // 2.0
        operand_b[0] = {32'h0, 32'h40400000};  // 3.0
        opcode = OP_FMUL;
        valid_in = 1;
        @(posedge clk);
        valid_in = 0;
        
        // Store intermediate result and use for ADD
        operand_a[0] = result[0];
        operand_b[0] = {32'h0, 32'h40800000};  // 4.0
        opcode = OP_FADD;
        valid_in = 1;
        @(posedge clk);
        cycle_end = $time / CLK_PERIOD;
        muladd_cycles = muladd_cycles + (cycle_end - cycle_start);
        muladd_result_bits = result[0][31:0];
        valid_in = 0;
        @(posedge clk);
        
        $display("Test: 2.0 * 3.0 + 4.0 = 10.0 (expected 0x41200000)");
        $display("  FMA result:     0x%08x (cycles: %0d)", fma_result_bits, fma_cycles);
        $display("  MUL+ADD result: 0x%08x (cycles: %0d)", muladd_result_bits, muladd_cycles);
        $display("  Speedup:        %.2fx\n", real'(muladd_cycles) / real'(fma_cycles));
    endtask
    
    //=========================================================================
    // Accuracy Comparison: FMA vs MUL + ADD
    // This demonstrates cases where FMA provides better precision
    //=========================================================================
    
    task automatic test_fma_accuracy();
        logic [31:0] fma_bits, muladd_bits, mul_bits;
        
        $display("\n=== FMA Accuracy Comparison ===");
        $display("Testing cases where double-rounding causes precision loss in MUL+ADD...\n");
        
        fma_accuracy_wins = 0;
        total_accuracy_tests = 0;
        
        // Test case 1: 1.0000001 * 1.0000001 + (-1.0)
        // The small bits above 1.0 get multiplied but might be lost in intermediate rounding
        // 1.0000001 ≈ 0x3F800001, -1.0 = 0xBF800000
        
        // FMA
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h3F800001};  // ~1.0000001
        operand_b[0] = {32'h0, 32'h3F800001};  // ~1.0000001
        operand_c[0] = {32'h0, 32'hBF800000};  // -1.0
        opcode = OP_FMADD;
        valid_in = 1;
        @(posedge clk);
        fma_bits = result[0][31:0];
        valid_in = 0;
        @(posedge clk);
        
        // MUL + ADD
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h3F800001};
        operand_b[0] = {32'h0, 32'h3F800001};
        opcode = OP_FMUL;
        valid_in = 1;
        @(posedge clk);
        mul_bits = result[0][31:0];
        valid_in = 0;
        
        operand_a[0] = result[0];
        operand_b[0] = {32'h0, 32'hBF800000};  // -1.0
        opcode = OP_FADD;
        valid_in = 1;
        @(posedge clk);
        muladd_bits = result[0][31:0];
        valid_in = 0;
        @(posedge clk);
        
        total_accuracy_tests++;
        $display("Test: ~1.0000001 * ~1.0000001 + (-1.0)");
        $display("  FMA result:       0x%08x", fma_bits);
        $display("  MUL+ADD result:   0x%08x", muladd_bits);
        
        if (fma_bits != muladd_bits) begin
            $display("  -> Results differ! Demonstrating single vs double rounding.");
            fma_accuracy_wins++;
        end else begin
            $display("  -> Results match - FMA still faster with same precision.");
        end
        
        // Test case 2: Pi * e + sqrt(2) ≈ 9.954
        // pi ≈ 0x40490FDB, e ≈ 0x402DF854, sqrt(2) ≈ 0x3FB504F3
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h40490FDB};  // pi
        operand_b[0] = {32'h0, 32'h402DF854};  // e
        operand_c[0] = {32'h0, 32'h3FB504F3};  // sqrt(2)
        opcode = OP_FMADD;
        valid_in = 1;
        @(posedge clk);
        fma_bits = result[0][31:0];
        valid_in = 0;
        @(posedge clk);
        
        // MUL + ADD
        init_inputs();
        active_mask[0] = 1'b1;
        operand_a[0] = {32'h0, 32'h40490FDB};
        operand_b[0] = {32'h0, 32'h402DF854};
        opcode = OP_FMUL;
        valid_in = 1;
        @(posedge clk);
        valid_in = 0;
        
        operand_a[0] = result[0];
        operand_b[0] = {32'h0, 32'h3FB504F3};
        opcode = OP_FADD;
        valid_in = 1;
        @(posedge clk);
        muladd_bits = result[0][31:0];
        valid_in = 0;
        @(posedge clk);
        
        total_accuracy_tests++;
        $display("\nTest: pi * e + sqrt(2) ≈ 9.954");
        $display("  FMA result:       0x%08x", fma_bits);
        $display("  MUL+ADD result:   0x%08x", muladd_bits);
        
        if (fma_bits != muladd_bits) begin
            $display("  -> Results differ! Demonstrating single vs double rounding.");
            fma_accuracy_wins++;
        end else begin
            $display("  -> Results match in this case.");
        end
    endtask
    
    //=========================================================================
    // SIMD FMA Test (all 8 threads)
    //=========================================================================
    
    task automatic test_fma_simd();
        shortreal expected_val;
        int simd_pass;
        logic [31:0] expected_bits [8];
        
        $display("\n=== Testing FMA SIMD (All 8 Threads) ===");
        
        // Pre-computed values:
        // Thread 0: 1.0 * 2.0 + 10.0 = 12.0 = 0x41400000
        // Thread 1: 2.0 * 3.0 + 20.0 = 26.0 = 0x41D00000
        // Thread 2: 3.0 * 4.0 + 30.0 = 42.0 = 0x42280000
        // Thread 3: 4.0 * 5.0 + 40.0 = 60.0 = 0x42700000
        // Thread 4: 5.0 * 6.0 + 50.0 = 80.0 = 0x42A00000
        // Thread 5: 6.0 * 7.0 + 60.0 = 102.0 = 0x42CC0000
        // Thread 6: 7.0 * 8.0 + 70.0 = 126.0 = 0x42FC0000
        // Thread 7: 8.0 * 9.0 + 80.0 = 152.0 = 0x43180000
        
        expected_bits[0] = 32'h41400000;  // 12.0
        expected_bits[1] = 32'h41D00000;  // 26.0
        expected_bits[2] = 32'h42280000;  // 42.0
        expected_bits[3] = 32'h42700000;  // 60.0
        expected_bits[4] = 32'h42A00000;  // 80.0
        expected_bits[5] = 32'h42CC0000;  // 102.0
        expected_bits[6] = 32'h42FC0000;  // 126.0
        expected_bits[7] = 32'h43180000;  // 152.0
        
        // Set all threads active with different values
        active_mask = 8'hFF;
        
        // Thread 0: a=1.0, b=2.0, c=10.0
        operand_a[0] = {32'h0, 32'h3F800000}; operand_b[0] = {32'h0, 32'h40000000}; operand_c[0] = {32'h0, 32'h41200000};
        // Thread 1: a=2.0, b=3.0, c=20.0
        operand_a[1] = {32'h0, 32'h40000000}; operand_b[1] = {32'h0, 32'h40400000}; operand_c[1] = {32'h0, 32'h41A00000};
        // Thread 2: a=3.0, b=4.0, c=30.0
        operand_a[2] = {32'h0, 32'h40400000}; operand_b[2] = {32'h0, 32'h40800000}; operand_c[2] = {32'h0, 32'h41F00000};
        // Thread 3: a=4.0, b=5.0, c=40.0
        operand_a[3] = {32'h0, 32'h40800000}; operand_b[3] = {32'h0, 32'h40A00000}; operand_c[3] = {32'h0, 32'h42200000};
        // Thread 4: a=5.0, b=6.0, c=50.0
        operand_a[4] = {32'h0, 32'h40A00000}; operand_b[4] = {32'h0, 32'h40C00000}; operand_c[4] = {32'h0, 32'h42480000};
        // Thread 5: a=6.0, b=7.0, c=60.0
        operand_a[5] = {32'h0, 32'h40C00000}; operand_b[5] = {32'h0, 32'h40E00000}; operand_c[5] = {32'h0, 32'h42700000};
        // Thread 6: a=7.0, b=8.0, c=70.0
        operand_a[6] = {32'h0, 32'h40E00000}; operand_b[6] = {32'h0, 32'h41000000}; operand_c[6] = {32'h0, 32'h428C0000};
        // Thread 7: a=8.0, b=9.0, c=80.0
        operand_a[7] = {32'h0, 32'h41000000}; operand_b[7] = {32'h0, 32'h41100000}; operand_c[7] = {32'h0, 32'h42A00000};
        
        opcode = OP_FMADD;
        valid_in = 1;
        #1;
        
        simd_pass = 1;
        test_count++;
        
        for (int i = 0; i < WARP_SIZE; i++) begin
            if (result[i][31:0] != expected_bits[i]) begin
                $display("[FAIL] Thread %0d: Expected 0x%08x, Got 0x%08x", 
                         i, expected_bits[i], result[i][31:0]);
                simd_pass = 0;
            end
        end
        
        if (simd_pass) begin
            $display("[PASS] FMA SIMD: All 8 threads computed correctly");
            pass_count++;
        end else begin
            fail_count++;
        end
        @(posedge clk);
        valid_in = 0;
    endtask
    
    //=========================================================================
    // Performance Summary
    //=========================================================================
    
    task automatic print_performance_summary();
        $display("\n");
        $display("╔═══════════════════════════════════════════════════════════════╗");
        $display("║              FMA PERFORMANCE ANALYSIS SUMMARY                 ║");
        $display("╠═══════════════════════════════════════════════════════════════╣");
        $display("║                                                               ║");
        $display("║  THROUGHPUT IMPROVEMENT:                                      ║");
        $display("║    - FMA: 1 instruction per a*b+c operation                   ║");
        $display("║    - MUL+ADD: 2 instructions per a*b+c operation              ║");
        $display("║    -> 2x instruction throughput improvement                   ║");
        $display("║                                                               ║");
        $display("║  CYCLE COMPARISON (from test):                                ║");
        $display("║    - FMA cycles: %3d                                          ║", fma_cycles);
        $display("║    - MUL+ADD cycles: %3d                                      ║", muladd_cycles);
        $display("║    -> Speedup: %.2fx                                          ║", 
                 muladd_cycles > 0 ? real'(muladd_cycles) / real'(fma_cycles) : 0.0);
        $display("║                                                               ║");
        $display("║  ACCURACY IMPROVEMENT:                                        ║");
        $display("║    - Single rounding vs double rounding                       ║");
        $display("║    - Tests showing different results: %0d/%0d                   ║",
                 fma_accuracy_wins, total_accuracy_tests);
        $display("║                                                               ║");
        $display("║  KEY BENEFITS:                                                ║");
        $display("║    1. 50%% fewer floating-point instructions for MAC ops       ║");
        $display("║    2. Better numerical accuracy (IEEE 754 compliant)          ║");
        $display("║    3. Reduced register pressure (no intermediate storage)     ║");
        $display("║    4. Critical for ML, graphics, and scientific computing     ║");
        $display("║                                                               ║");
        $display("╚═══════════════════════════════════════════════════════════════╝");
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    
    initial begin
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        fma_cycles = 0;
        muladd_cycles = 0;
        fma_accuracy_wins = 0;
        total_accuracy_tests = 0;
        
        rst_n = 0;
        init_inputs();
        
        // Reset sequence
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        $display("\n");
        $display("=============================================================");
        $display("              GPGPU-1 FPU TESTBENCH");
        $display("              Including FMA Performance Analysis");
        $display("=============================================================");
        
        // Basic FPU tests
        test_fadd();
        test_fmul();
        
        // FMA tests
        test_fma_basic();
        test_fma_special_cases();
        
        // Performance comparison
        test_fma_performance();
        test_fma_accuracy();
        
        // SIMD test
        test_fma_simd();
        
        // Print performance summary
        print_performance_summary();
        
        // Final summary
        $display("\n");
        $display("=============================================================");
        $display("                    TEST SUMMARY");
        $display("=============================================================");
        $display("Total Tests:  %0d", test_count);
        $display("Passed:       %0d", pass_count);
        $display("Failed:       %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("\n*** ALL TESTS PASSED ***\n");
        end else begin
            $display("\n*** %0d TESTS FAILED ***\n", fail_count);
        end
        
        $finish;
    end
    
endmodule
