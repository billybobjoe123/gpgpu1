//=============================================================================
// GPGPU-1 Single-Precision FPU Testbench (Pipelined)
//=============================================================================
// File:        tb_fpu_sp.sv
// Description: Tests single-precision floating-point operations with
//              proper pipeline latency handling.
// Version:     2.0
// Date:        January 2, 2026
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_fpu_sp;
    import gpgpu_pkg::*;
    
    //=========================================================================
    // Parameters
    //=========================================================================
    
    parameter CLK_PERIOD = 10;
    
    // Expected latencies (from FPU module)
    localparam LATENCY_SIMPLE = 1;   // MIN, MAX, ABS, NEG, CMP
    localparam LATENCY_ADD    = 3;   // FADD, FSUB
    localparam LATENCY_MUL    = 4;   // FMUL
    localparam LATENCY_FMA    = 5;   // FMADD
    localparam LATENCY_DIV    = 12;  // FDIV
    
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
    always #(CLK_PERIOD/2) clk <= ~clk;
    
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
    
    // Pack 32-bit SP value into 64-bit data word
    function automatic logic [63:0] sp(input logic [31:0] val);
        return {32'h0, val};
    endfunction
    
    // Common SP values
    localparam logic [31:0] SP_ZERO        = 32'h00000000;  // 0.0
    localparam logic [31:0] SP_ONE         = 32'h3F800000;  // 1.0
    localparam logic [31:0] SP_TWO         = 32'h40000000;  // 2.0
    localparam logic [31:0] SP_THREE       = 32'h40400000;  // 3.0
    localparam logic [31:0] SP_FOUR        = 32'h40800000;  // 4.0
    localparam logic [31:0] SP_FIVE        = 32'h40A00000;  // 5.0
    localparam logic [31:0] SP_SIX         = 32'h40C00000;  // 6.0
    localparam logic [31:0] SP_SEVEN       = 32'h40E00000;  // 7.0
    localparam logic [31:0] SP_EIGHT       = 32'h41000000;  // 8.0
    localparam logic [31:0] SP_NINE        = 32'h41100000;  // 9.0
    localparam logic [31:0] SP_TEN         = 32'h41200000;  // 10.0
    localparam logic [31:0] SP_TWELVE      = 32'h41400000;  // 12.0
    localparam logic [31:0] SP_TWENTY      = 32'h41A00000;  // 20.0
    localparam logic [31:0] SP_HALF        = 32'h3F000000;  // 0.5
    localparam logic [31:0] SP_TWO_HALF    = 32'h40200000;  // 2.5
    localparam logic [31:0] SP_FIVE_HALF   = 32'h40B00000;  // 5.5
    localparam logic [31:0] SP_NEG_ONE     = 32'hBF800000;  // -1.0
    localparam logic [31:0] SP_NEG_TWO     = 32'hC0000000;  // -2.0
    localparam logic [31:0] SP_NEG_THREE   = 32'hC0400000;  // -3.0
    localparam logic [31:0] SP_NEG_TWO_HALF= 32'hC0200000;  // -2.5
    localparam logic [31:0] SP_PI          = 32'h40490FDB;  // pi
    localparam logic [31:0] SP_INF         = 32'h7F800000;  // +Infinity
    localparam logic [31:0] SP_NEG_INF     = 32'hFF800000;  // -Infinity
    localparam logic [31:0] SP_NAN         = 32'h7FC00000;  // Quiet NaN
    
    // func[7] = 0 for single precision (default)
    localparam logic [7:0] FUNC_SP = 8'h00;
    
    //=========================================================================
    // Test Tasks
    //=========================================================================
    
    task automatic reset();
        rst_n = 1'b0;
        valid_in = 1'b0;
        opcode = OP_FADD;
        func = FUNC_SP;
        active_mask = 8'hFF;
        
        for (int i = 0; i < WARP_SIZE; i++) begin
            operand_a[i] = 64'h0;
            operand_b[i] = 64'h0;
            operand_c[i] = 64'h0;
        end
        
        repeat(3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
    endtask
    
    // Issue operation and wait for proper number of cycles
    task automatic issue_and_wait(input int latency);
        $display("[DEBUG] Issuing op, expecting latency %0d", latency);
        valid_in = 1'b1;
        @(posedge clk);
        #1;
        $display("[DEBUG] Cycle 1: valid_out=%b, result[0]=0x%08x", valid_out, result[0][31:0]);
        valid_in = 1'b0;
        
    // Wait for pipeline latency (latency-1 more cycles since we already advanced one)
    for (int i = 2; i <= latency; i++) begin
        @(posedge clk);
        #1;
        $display("[DEBUG] Cycle %0d: valid_out=%b, result[0]=0x%08x", i, valid_out, result[0][31:0]);
    end
    endtask
    
    task automatic check_result_bits(
        input string test_name,
        input logic [31:0] expected,
        input int thread_id = 0
    );
        logic [31:0] actual;
        actual = result[thread_id][31:0];
        test_count++;
        
        if (actual === expected) begin
            $display("[PASS] %s: Expected 0x%08x, Got 0x%08x", test_name, expected, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Expected 0x%08x, Got 0x%08x", test_name, expected, actual);
            fail_count++;
        end
    endtask
    
    function automatic logic is_nan(input logic [31:0] val);
        return (val[30:23] == 8'hFF) && (val[22:0] != 0);
    endfunction
    
    task automatic check_nan(
        input string test_name,
        input int thread_id = 0
    );
        logic [31:0] actual;
        actual = result[thread_id][31:0];
        test_count++;
        
        if (is_nan(actual)) begin
            $display("[PASS] %s: Got NaN 0x%08x", test_name, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Expected NaN, Got 0x%08x", test_name, actual);
            fail_count++;
        end
    endtask
    
    //=========================================================================
    // FADD Tests (Latency = 3)
    //=========================================================================
    
    task automatic test_fadd();
        $display("\n--- FADD Tests (SP, Latency=%0d) ---", LATENCY_ADD);
        
        // Test 1: 1.0 + 2.0 = 3.0
        active_mask = 8'h01;
        operand_a[0] = sp(SP_ONE);
        operand_b[0] = sp(SP_TWO);
        opcode = OP_FADD;
        func = FUNC_SP;
        issue_and_wait(LATENCY_ADD);
        check_result_bits("FADD 1.0 + 2.0 = 3.0", SP_THREE);
        
        // Test 2: 5.5 + (-2.5) = 3.0
        active_mask = 8'h01;
        operand_a[0] = sp(SP_FIVE_HALF);
        operand_b[0] = sp(SP_NEG_TWO_HALF);
        opcode = OP_FADD;
        issue_and_wait(LATENCY_ADD);
        check_result_bits("FADD 5.5 + (-2.5) = 3.0", SP_THREE);
        
        // Test 3: 0.0 + 0.0 = 0.0
        active_mask = 8'h01;
        operand_a[0] = sp(SP_ZERO);
        operand_b[0] = sp(SP_ZERO);
        opcode = OP_FADD;
        issue_and_wait(LATENCY_ADD);
        check_result_bits("FADD 0.0 + 0.0 = 0.0", SP_ZERO);
    endtask
    
    //=========================================================================
    // FMUL Tests (Latency = 4)
    //=========================================================================
    
    task automatic test_fmul();
        $display("\n--- FMUL Tests (SP, Latency=%0d) ---", LATENCY_MUL);
        
        // Test 1: 2.0 * 3.0 = 6.0
        active_mask = 8'h01;
        operand_a[0] = sp(SP_TWO);
        operand_b[0] = sp(SP_THREE);
        opcode = OP_FMUL;
        func = FUNC_SP;
        issue_and_wait(LATENCY_MUL);
        check_result_bits("FMUL 2.0 * 3.0 = 6.0", SP_SIX);
        
        // Test 2: 2.5 * 4.0 = 10.0
        active_mask = 8'h01;
        operand_a[0] = sp(SP_TWO_HALF);
        operand_b[0] = sp(SP_FOUR);
        opcode = OP_FMUL;
        issue_and_wait(LATENCY_MUL);
        check_result_bits("FMUL 2.5 * 4.0 = 10.0", SP_TEN);
        
        // Test 3: x * 0.0 = 0.0
        active_mask = 8'h01;
        operand_a[0] = sp(SP_PI);
        operand_b[0] = sp(SP_ZERO);
        opcode = OP_FMUL;
        issue_and_wait(LATENCY_MUL);
        check_result_bits("FMUL x * 0.0 = 0.0", SP_ZERO);
    endtask
    
    //=========================================================================
    // FMA Tests (Latency = 5)
    //=========================================================================
    
    task automatic test_fma();
        $display("\n--- FMA Tests (SP, Latency=%0d) ---", LATENCY_FMA);
        
        // Test 1: 2.0 * 3.0 + 4.0 = 10.0
        active_mask = 8'h01;
        operand_a[0] = sp(SP_TWO);
        operand_b[0] = sp(SP_THREE);
        operand_c[0] = sp(SP_FOUR);
        opcode = OP_FMADD;
        func = FUNC_SP;
        issue_and_wait(LATENCY_FMA);
        check_result_bits("FMA 2.0 * 3.0 + 4.0 = 10.0", SP_TEN);
        
        // Test 2: 5.0 * 2.0 + (-3.0) = 7.0
        active_mask = 8'h01;
        operand_a[0] = sp(SP_FIVE);
        operand_b[0] = sp(SP_TWO);
        operand_c[0] = sp(SP_NEG_THREE);
        opcode = OP_FMADD;
        issue_and_wait(LATENCY_FMA);
        check_result_bits("FMA 5.0 * 2.0 + (-3.0) = 7.0", SP_SEVEN);
        
        // Test 3: 3.0 * 4.0 + 0.0 = 12.0
        active_mask = 8'h01;
        operand_a[0] = sp(SP_THREE);
        operand_b[0] = sp(SP_FOUR);
        operand_c[0] = sp(SP_ZERO);
        opcode = OP_FMADD;
        issue_and_wait(LATENCY_FMA);
        check_result_bits("FMA 3.0 * 4.0 + 0.0 = 12.0", SP_TWELVE);
        
        // Test 4: 0.0 * 5.0 + 7.0 = 7.0
        active_mask = 8'h01;
        operand_a[0] = sp(SP_ZERO);
        operand_b[0] = sp(SP_FIVE);
        operand_c[0] = sp(SP_SEVEN);
        opcode = OP_FMADD;
        issue_and_wait(LATENCY_FMA);
        check_result_bits("FMA 0.0 * 5.0 + 7.0 = 7.0", SP_SEVEN);
        
        // Test 5: 1.0 * 1.0 + 1.0 = 2.0
        active_mask = 8'h01;
        operand_a[0] = sp(SP_ONE);
        operand_b[0] = sp(SP_ONE);
        operand_c[0] = sp(SP_ONE);
        opcode = OP_FMADD;
        issue_and_wait(LATENCY_FMA);
        check_result_bits("FMA 1.0 * 1.0 + 1.0 = 2.0", SP_TWO);
    endtask
    
    //=========================================================================
    // Special Cases
    //=========================================================================
    
    task automatic test_special_cases();
        $display("\n--- Special Cases ---");
        
        // NaN * x + y should be NaN
        active_mask = 8'h01;
        operand_a[0] = sp(SP_NAN);
        operand_b[0] = sp(SP_TWO);
        operand_c[0] = sp(SP_THREE);
        opcode = OP_FMADD;
        func = FUNC_SP;
        issue_and_wait(LATENCY_FMA);
        check_nan("FMA NaN * x + y = NaN");
        
        // +Inf * 2.0 + 1.0 = +Inf
        active_mask = 8'h01;
        operand_a[0] = sp(SP_INF);
        operand_b[0] = sp(SP_TWO);
        operand_c[0] = sp(SP_ONE);
        opcode = OP_FMADD;
        issue_and_wait(LATENCY_FMA);
        check_result_bits("FMA +Inf * 2.0 + 1.0 = +Inf", SP_INF);
        
        // -Inf * 2.0 + 1.0 = -Inf
        active_mask = 8'h01;
        operand_a[0] = sp(SP_NEG_INF);
        operand_b[0] = sp(SP_TWO);
        operand_c[0] = sp(SP_ONE);
        opcode = OP_FMADD;
        issue_and_wait(LATENCY_FMA);
        check_result_bits("FMA -Inf * 2.0 + 1.0 = -Inf", SP_NEG_INF);
    endtask
    
    //=========================================================================
    // SIMD Test (all 8 threads)
    //=========================================================================
    
    task automatic test_simd();
        logic [31:0] expected_bits [8];
        int all_pass;
        
        $display("\n--- SIMD Test (8 threads, FMA) ---");
        
        // Thread 0: 1.0 * 2.0 + 10.0 = 12.0
        // Thread 1: 2.0 * 3.0 + 20.0 = 26.0
        // Thread 2: 3.0 * 4.0 + 30.0 = 42.0
        // Thread 3: 4.0 * 5.0 + 40.0 = 60.0
        // Thread 4: 5.0 * 6.0 + 50.0 = 80.0
        // Thread 5: 6.0 * 7.0 + 60.0 = 102.0
        // Thread 6: 7.0 * 8.0 + 70.0 = 126.0
        // Thread 7: 8.0 * 9.0 + 80.0 = 152.0
        
        expected_bits[0] = 32'h41400000;  // 12.0
        expected_bits[1] = 32'h41D00000;  // 26.0
        expected_bits[2] = 32'h42280000;  // 42.0
        expected_bits[3] = 32'h42700000;  // 60.0
        expected_bits[4] = 32'h42A00000;  // 80.0
        expected_bits[5] = 32'h42CC0000;  // 102.0
        expected_bits[6] = 32'h42FC0000;  // 126.0
        expected_bits[7] = 32'h43180000;  // 152.0
        
        active_mask = 8'hFF;
        
        operand_a[0] = sp(SP_ONE);   operand_b[0] = sp(SP_TWO);   operand_c[0] = sp(SP_TEN);
        operand_a[1] = sp(SP_TWO);   operand_b[1] = sp(SP_THREE); operand_c[1] = sp(SP_TWENTY);
        operand_a[2] = sp(SP_THREE); operand_b[2] = sp(SP_FOUR);  operand_c[2] = sp(32'h41F00000); // 30.0
        operand_a[3] = sp(SP_FOUR);  operand_b[3] = sp(SP_FIVE);  operand_c[3] = sp(32'h42200000); // 40.0
        operand_a[4] = sp(SP_FIVE);  operand_b[4] = sp(SP_SIX);   operand_c[4] = sp(32'h42480000); // 50.0
        operand_a[5] = sp(SP_SIX);   operand_b[5] = sp(SP_SEVEN); operand_c[5] = sp(32'h42700000); // 60.0
        operand_a[6] = sp(SP_SEVEN); operand_b[6] = sp(SP_EIGHT); operand_c[6] = sp(32'h428C0000); // 70.0
        operand_a[7] = sp(SP_EIGHT); operand_b[7] = sp(SP_NINE);  operand_c[7] = sp(32'h42A00000); // 80.0
        
        opcode = OP_FMADD;
        func = FUNC_SP;
        issue_and_wait(LATENCY_FMA);
        
        all_pass = 1;
        for (int i = 0; i < 8; i++) begin
            if (result[i][31:0] !== expected_bits[i]) begin
                $display("[FAIL] Thread %0d: Expected 0x%08x, Got 0x%08x", 
                         i, expected_bits[i], result[i][31:0]);
                all_pass = 0;
            end
        end
        
        test_count++;
        if (all_pass) begin
            $display("[PASS] SIMD FMA: All 8 threads correct");
            pass_count++;
        end else begin
            fail_count++;
        end
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    
    initial begin
        $display("===========================================");
        $display("GPGPU-1 Single-Precision FPU Testbench");
        $display("(Pipelined Version)");
        $display("===========================================");
        
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        reset();
        
        test_fadd();
        test_fmul();
        test_fma();
        test_special_cases();
        test_simd();
        
        $display("\n===========================================");
        $display("Test Summary");
        $display("===========================================");
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("===========================================");
        
        if (fail_count == 0) begin
            $display("*** ALL SP FPU TESTS PASSED ***");
        end else begin
            $display("*** %0d TESTS FAILED ***", fail_count);
        end
        
        $finish;
    end
    
    //=========================================================================
    // Timeout
    //=========================================================================
    
    initial begin
        #100000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
