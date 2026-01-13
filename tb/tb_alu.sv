//=============================================================================
// GPGPU-1 ALU and Execution Unit Testbench
//=============================================================================
// File:        tb_alu.sv
// Description: Comprehensive testbench for ALU, Shift, Compare, Mul/Div,
//              and top-level execution unit
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_alu;
    import gpgpu_pkg::*;
    
    //=========================================================================
    // Parameters
    //=========================================================================
    
    localparam CLK_PERIOD = 10;
    
    //=========================================================================
    // Signals
    //=========================================================================
    
    logic clk;
    logic rst_n;
    
    // ALU signals
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] alu_operand_a;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] alu_operand_b;
    logic [FUNC_WIDTH-1:0]                alu_func;
    logic [WARP_SIZE-1:0]                 alu_active_mask;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] alu_result;
    
    // Shift unit signals
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] shift_operand_a;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] shift_operand_b;
    logic [FUNC_WIDTH-1:0]                shift_func;
    logic [WARP_SIZE-1:0]                 shift_active_mask;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] shift_result;
    
    // Compare unit signals
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] cmp_operand_a;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] cmp_operand_b;
    logic [WARP_SIZE-1:0]                 cmp_pred_a;
    logic [WARP_SIZE-1:0]                 cmp_pred_b;
    logic [FUNC_WIDTH-1:0]                cmp_func;
    logic [WARP_SIZE-1:0]                 cmp_active_mask;
    logic [WARP_SIZE-1:0]                 cmp_pred_result;
    
    // Mul/Div unit signals
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] mul_operand_a;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] mul_operand_b;
    logic [FUNC_WIDTH-1:0]                mul_func;
    logic [WARP_SIZE-1:0]                 mul_active_mask;
    logic                                 mul_valid_in;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] mul_result;
    logic                                 mul_valid_out;
    logic                                 mul_ready;
    
    // Execution unit signals
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] ex_operand_a;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] ex_operand_b;
    logic [WARP_SIZE-1:0]                 ex_pred_a;
    logic [WARP_SIZE-1:0]                 ex_pred_b;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] ex_special_data;
    exec_unit_t                           ex_select;
    opcode_t                              ex_opcode;
    logic [FUNC_WIDTH-1:0]                ex_func;
    logic [WARP_SIZE-1:0]                 ex_active_mask;
    logic                                 ex_valid_in;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] ex_result;
    logic [WARP_SIZE-1:0]                 ex_pred_result;
    logic                                 ex_valid_out;
    logic                                 ex_ready;
    
    // Test control
    int test_count;
    int pass_count;
    int fail_count;
    
    //=========================================================================
    // DUT Instances
    //=========================================================================
    
    alu u_alu (
        .operand_a   (alu_operand_a),
        .operand_b   (alu_operand_b),
        .func        (alu_func),
        .active_mask (alu_active_mask),
        .result      (alu_result)
    );
    
    shift_unit u_shift (
        .operand_a   (shift_operand_a),
        .operand_b   (shift_operand_b),
        .func        (shift_func),
        .active_mask (shift_active_mask),
        .result      (shift_result)
    );
    
    compare_unit u_compare (
        .operand_a   (cmp_operand_a),
        .operand_b   (cmp_operand_b),
        .pred_a      (cmp_pred_a),
        .pred_b      (cmp_pred_b),
        .func        (cmp_func),
        .active_mask (cmp_active_mask),
        .pred_result (cmp_pred_result)
    );
    
    mul_div_unit u_mul_div (
        .clk         (clk),
        .rst_n       (rst_n),
        .operand_a   (mul_operand_a),
        .operand_b   (mul_operand_b),
        .func        (mul_func),
        .active_mask (mul_active_mask),
        .valid_in    (mul_valid_in),
        .result      (mul_result),
        .valid_out   (mul_valid_out),
        .ready       (mul_ready)
    );
    
    execution_unit u_execution_unit (
        .clk          (clk),
        .rst_n        (rst_n),
        .operand_a    (ex_operand_a),
        .operand_b    (ex_operand_b),
        .pred_a       (ex_pred_a),
        .pred_b       (ex_pred_b),
        .special_data (ex_special_data),
        .exec_select  (ex_select),
        .opcode       (ex_opcode),
        .func         (ex_func),
        .active_mask  (ex_active_mask),
        .valid_in     (ex_valid_in),
        .result       (ex_result),
        .pred_result  (ex_pred_result),
        .valid_out    (ex_valid_out),
        .ready        (ex_ready)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    //=========================================================================
    // Test Tasks
    //=========================================================================
    
    // Initialize all inputs
    task initialize();
        // ALU inputs
        alu_operand_a = '0;
        alu_operand_b = '0;
        alu_func = '0;
        alu_active_mask = '1;
        
        // Shift inputs
        shift_operand_a = '0;
        shift_operand_b = '0;
        shift_func = '0;
        shift_active_mask = '1;
        
        // Compare inputs
        cmp_operand_a = '0;
        cmp_operand_b = '0;
        cmp_pred_a = '0;
        cmp_pred_b = '0;
        cmp_func = '0;
        cmp_active_mask = '1;
        
        // Mul/Div inputs
        mul_operand_a = '0;
        mul_operand_b = '0;
        mul_func = '0;
        mul_active_mask = '1;
        mul_valid_in = 0;
        
        // Execution unit inputs
        ex_operand_a = '0;
        ex_operand_b = '0;
        ex_pred_a = '0;
        ex_pred_b = '0;
        ex_special_data = '0;
        ex_select = EX_ALU;
        ex_opcode = OP_ALU;
        ex_func = '0;
        ex_active_mask = '1;
        ex_valid_in = 0;
        
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
    endtask
    
    // Check ALU result for all threads
    task check_alu_result(
        input string name,
        input logic [DATA_WIDTH-1:0] expected
    );
        test_count++;
        if (alu_result[0] === expected) begin
            $display("[PASS] %s: Expected 0x%016h, Got 0x%016h", name, expected, alu_result[0]);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Expected 0x%016h, Got 0x%016h", name, expected, alu_result[0]);
            fail_count++;
        end
    endtask
    
    // Check shift result
    task check_shift_result(
        input string name,
        input logic [DATA_WIDTH-1:0] expected
    );
        test_count++;
        if (shift_result[0] === expected) begin
            $display("[PASS] %s: Expected 0x%016h, Got 0x%016h", name, expected, shift_result[0]);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Expected 0x%016h, Got 0x%016h", name, expected, shift_result[0]);
            fail_count++;
        end
    endtask
    
    // Check compare result
    task check_cmp_result(
        input string name,
        input logic [WARP_SIZE-1:0] expected
    );
        test_count++;
        if (cmp_pred_result === expected) begin
            $display("[PASS] %s: Expected 0x%02h, Got 0x%02h", name, expected, cmp_pred_result);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Expected 0x%02h, Got 0x%02h", name, expected, cmp_pred_result);
            fail_count++;
        end
    endtask
    
    // Check mul/div result
    task check_mul_result(
        input string name,
        input logic [DATA_WIDTH-1:0] expected
    );
        test_count++;
        if (mul_result[0] === expected) begin
            $display("[PASS] %s: Expected 0x%016h, Got 0x%016h", name, expected, mul_result[0]);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Expected 0x%016h, Got 0x%016h", name, expected, mul_result[0]);
            fail_count++;
        end
    endtask
    
    // Check execution unit result
    task check_ex_result(
        input string name,
        input logic [DATA_WIDTH-1:0] expected
    );
        test_count++;
        if (ex_result[0] === expected) begin
            $display("[PASS] %s: Expected 0x%016h, Got 0x%016h", name, expected, ex_result[0]);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Expected 0x%016h, Got 0x%016h", name, expected, ex_result[0]);
            fail_count++;
        end
    endtask
    
    //=========================================================================
    // ALU Tests
    //=========================================================================
    
    task test_alu();
        $display("\n=== Testing ALU Unit ===\n");
        
        //--- Test ADD ---
        alu_operand_a[0] = 64'h0000_0000_0000_0100;
        alu_operand_b[0] = 64'h0000_0000_0000_0200;
        alu_func = ALU_ADD;
        #1;
        check_alu_result("ADD (0x100 + 0x200)", 64'h0000_0000_0000_0300);
        
        //--- Test ADD with overflow ---
        alu_operand_a[0] = 64'hFFFF_FFFF_FFFF_FFFF;
        alu_operand_b[0] = 64'h0000_0000_0000_0001;
        #1;
        check_alu_result("ADD (wrap around)", 64'h0000_0000_0000_0000);
        
        //--- Test SUB ---
        alu_operand_a[0] = 64'h0000_0000_0000_0500;
        alu_operand_b[0] = 64'h0000_0000_0000_0200;
        alu_func = ALU_SUB;
        #1;
        check_alu_result("SUB (0x500 - 0x200)", 64'h0000_0000_0000_0300);
        
        //--- Test SUB underflow ---
        alu_operand_a[0] = 64'h0000_0000_0000_0000;
        alu_operand_b[0] = 64'h0000_0000_0000_0001;
        #1;
        check_alu_result("SUB underflow", 64'hFFFF_FFFF_FFFF_FFFF);
        
        //--- Test AND ---
        alu_operand_a[0] = 64'hFFFF_0000_FFFF_0000;
        alu_operand_b[0] = 64'h0000_FFFF_FFFF_0000;
        alu_func = ALU_AND;
        #1;
        check_alu_result("AND", 64'h0000_0000_FFFF_0000);
        
        //--- Test OR ---
        alu_operand_a[0] = 64'hFFFF_0000_0000_0000;
        alu_operand_b[0] = 64'h0000_FFFF_0000_0000;
        alu_func = ALU_OR;
        #1;
        check_alu_result("OR", 64'hFFFF_FFFF_0000_0000);
        
        //--- Test XOR ---
        alu_operand_a[0] = 64'hFFFF_FFFF_0000_0000;
        alu_operand_b[0] = 64'h0000_FFFF_FFFF_0000;
        alu_func = ALU_XOR;
        #1;
        check_alu_result("XOR", 64'hFFFF_0000_FFFF_0000);
        
        //--- Test NOR ---
        alu_operand_a[0] = 64'hFFFF_0000_0000_0000;
        alu_operand_b[0] = 64'h0000_FFFF_0000_0000;
        alu_func = ALU_NOR;
        #1;
        check_alu_result("NOR", 64'h0000_0000_FFFF_FFFF);
        
        //--- Test MIN (signed) ---
        alu_operand_a[0] = 64'h0000_0000_0000_000A;  // 10
        alu_operand_b[0] = 64'hFFFF_FFFF_FFFF_FFF6;  // -10
        alu_func = ALU_MIN;
        #1;
        check_alu_result("MIN signed", 64'hFFFF_FFFF_FFFF_FFF6);
        
        //--- Test MAX (signed) ---
        alu_operand_a[0] = 64'h0000_0000_0000_000A;  // 10
        alu_operand_b[0] = 64'hFFFF_FFFF_FFFF_FFF6;  // -10
        alu_func = ALU_MAX;
        #1;
        check_alu_result("MAX signed", 64'h0000_0000_0000_000A);
        
        //--- Test MINU (unsigned) ---
        alu_operand_a[0] = 64'h0000_0000_0000_000A;
        alu_operand_b[0] = 64'hFFFF_FFFF_FFFF_FFF6;  // Large unsigned
        alu_func = ALU_MINU;
        #1;
        check_alu_result("MINU unsigned", 64'h0000_0000_0000_000A);
        
        //--- Test MAXU (unsigned) ---
        alu_operand_a[0] = 64'h0000_0000_0000_000A;
        alu_operand_b[0] = 64'hFFFF_FFFF_FFFF_FFF6;
        alu_func = ALU_MAXU;
        #1;
        check_alu_result("MAXU unsigned", 64'hFFFF_FFFF_FFFF_FFF6);
        
        //--- Test ABS (positive) ---
        alu_operand_a[0] = 64'h0000_0000_0000_0064;  // 100
        alu_func = ALU_ABS;
        #1;
        check_alu_result("ABS positive", 64'h0000_0000_0000_0064);
        
        //--- Test ABS (negative) ---
        alu_operand_a[0] = 64'hFFFF_FFFF_FFFF_FF9C;  // -100
        #1;
        check_alu_result("ABS negative", 64'h0000_0000_0000_0064);
        
        //--- Test NEG ---
        alu_operand_a[0] = 64'h0000_0000_0000_000A;  // 10
        alu_func = ALU_NEG;
        #1;
        check_alu_result("NEG", 64'hFFFF_FFFF_FFFF_FFF6);
        
        //--- Test NOT ---
        alu_operand_a[0] = 64'h0000_0000_FFFF_FFFF;
        alu_func = ALU_NOT;
        #1;
        check_alu_result("NOT", 64'hFFFF_FFFF_0000_0000);
        
        //--- Test CLZ (Count Leading Zeros) ---
        alu_operand_a[0] = 64'h0001_0000_0000_0000;  // Single bit at position 48
        alu_func = ALU_CLZ;
        #1;
        check_alu_result("CLZ", 64'h0000_0000_0000_000F);  // 15 leading zeros
        
        //--- Test CLZ (all zeros) ---
        alu_operand_a[0] = 64'h0000_0000_0000_0000;
        #1;
        check_alu_result("CLZ all zeros", 64'h0000_0000_0000_0040);  // 64 leading zeros
        
        //--- Test CTZ (Count Trailing Zeros) ---
        alu_operand_a[0] = 64'h0000_0000_0000_0100;  // Single bit at position 8
        alu_func = ALU_CTZ;
        #1;
        check_alu_result("CTZ", 64'h0000_0000_0000_0008);  // 8 trailing zeros
        
        //--- Test CTZ (all zeros) ---
        alu_operand_a[0] = 64'h0000_0000_0000_0000;
        #1;
        check_alu_result("CTZ all zeros", 64'h0000_0000_0000_0040);  // 64 trailing zeros
        
        //--- Test POPC (Population Count) ---
        alu_operand_a[0] = 64'h0000_0000_0000_000F;  // 4 bits set
        alu_func = ALU_POPC;
        #1;
        check_alu_result("POPC 4 bits", 64'h0000_0000_0000_0004);
        
        //--- Test POPC (all ones) ---
        alu_operand_a[0] = 64'hFFFF_FFFF_FFFF_FFFF;
        #1;
        check_alu_result("POPC all ones", 64'h0000_0000_0000_0040);  // 64 bits
        
        //--- Test active mask ---
        alu_operand_a[0] = 64'h0000_0000_0000_0100;
        alu_operand_b[0] = 64'h0000_0000_0000_0200;
        alu_func = ALU_ADD;
        alu_active_mask[0] = 1'b0;  // Disable thread 0
        #1;
        check_alu_result("ADD with inactive thread", 64'h0000_0000_0000_0000);
        alu_active_mask[0] = 1'b1;  // Re-enable
    endtask
    
    //=========================================================================
    // Shift Unit Tests
    //=========================================================================
    
    task test_shift();
        $display("\n=== Testing Shift Unit ===\n");
        
        //--- Test SLL (Shift Left Logical) ---
        shift_operand_a[0] = 64'h0000_0000_0000_0001;
        shift_operand_b[0] = 64'h0000_0000_0000_0004;  // Shift by 4
        shift_func = SHIFT_SLL;
        #1;
        check_shift_result("SLL by 4", 64'h0000_0000_0000_0010);
        
        //--- Test SLL max shift ---
        shift_operand_a[0] = 64'h0000_0000_0000_0001;
        shift_operand_b[0] = 64'h0000_0000_0000_003F;  // Shift by 63
        #1;
        check_shift_result("SLL by 63", 64'h8000_0000_0000_0000);
        
        //--- Test SRL (Shift Right Logical) ---
        shift_operand_a[0] = 64'h8000_0000_0000_0000;
        shift_operand_b[0] = 64'h0000_0000_0000_0004;  // Shift by 4
        shift_func = SHIFT_SRL;
        #1;
        check_shift_result("SRL by 4", 64'h0800_0000_0000_0000);
        
        //--- Test SRA (Shift Right Arithmetic) positive ---
        shift_operand_a[0] = 64'h0800_0000_0000_0000;  // Positive number
        shift_operand_b[0] = 64'h0000_0000_0000_0004;
        shift_func = SHIFT_SRA;
        #1;
        check_shift_result("SRA positive by 4", 64'h0080_0000_0000_0000);
        
        //--- Test SRA negative (sign extension) ---
        shift_operand_a[0] = 64'h8000_0000_0000_0000;  // Negative number
        shift_operand_b[0] = 64'h0000_0000_0000_0004;
        #1;
        check_shift_result("SRA negative by 4", 64'hF800_0000_0000_0000);
        
        //--- Test ROL (Rotate Left) ---
        shift_operand_a[0] = 64'h8000_0000_0000_0001;
        shift_operand_b[0] = 64'h0000_0000_0000_0004;  // Rotate by 4
        shift_func = SHIFT_ROL;
        #1;
        check_shift_result("ROL by 4", 64'h0000_0000_0000_0018);
        
        //--- Test ROR (Rotate Right) ---
        shift_operand_a[0] = 64'h0000_0000_0000_000F;
        shift_operand_b[0] = 64'h0000_0000_0000_0004;  // Rotate by 4
        shift_func = SHIFT_ROR;
        #1;
        check_shift_result("ROR by 4", 64'hF000_0000_0000_0000);
        
        //--- Test inactive thread ---
        shift_operand_a[0] = 64'h0000_0000_0000_0001;
        shift_operand_b[0] = 64'h0000_0000_0000_0004;
        shift_func = SHIFT_SLL;
        shift_active_mask[0] = 1'b0;
        #1;
        check_shift_result("SLL with inactive thread", 64'h0000_0000_0000_0000);
        shift_active_mask[0] = 1'b1;
    endtask
    
    //=========================================================================
    // Compare Unit Tests
    //=========================================================================
    
    task test_compare();
        integer i;
        
        $display("\n=== Testing Compare Unit ===\n");
        
        // Set all threads to same operands for testing
        for (i = 0; i < WARP_SIZE; i = i + 1) begin
            cmp_operand_a[i] = 64'h0000_0000_0000_000A;  // 10
            cmp_operand_b[i] = 64'h0000_0000_0000_0005;  // 5
        end
        
        //--- Test SEQ (Set if Equal) - not equal ---
        cmp_func = CMP_SEQ;
        #1;
        check_cmp_result("SEQ (10 == 5)", 8'h00);  // All false
        
        //--- Test SEQ - equal ---
        for (i = 0; i < WARP_SIZE; i = i + 1) begin
            cmp_operand_b[i] = 64'h0000_0000_0000_000A;
        end
        #1;
        check_cmp_result("SEQ (10 == 10)", 8'hFF);  // All true
        
        //--- Test SNE (Set if Not Equal) ---
        for (i = 0; i < WARP_SIZE; i = i + 1) begin
            cmp_operand_b[i] = 64'h0000_0000_0000_0005;
        end
        cmp_func = CMP_SNE;
        #1;
        check_cmp_result("SNE (10 != 5)", 8'hFF);  // All true
        
        //--- Test SLT (Set if Less Than signed) ---
        for (i = 0; i < WARP_SIZE; i = i + 1) begin
            cmp_operand_a[i] = 64'hFFFF_FFFF_FFFF_FFF6;  // -10
            cmp_operand_b[i] = 64'h0000_0000_0000_0005;  // 5
        end
        cmp_func = CMP_SLT;
        #1;
        check_cmp_result("SLT (-10 < 5)", 8'hFF);  // All true
        
        //--- Test SLTU (Set if Less Than unsigned) ---
        cmp_func = CMP_SLTU;
        #1;
        check_cmp_result("SLTU (-10 < 5 unsigned)", 8'h00);  // All false (large unsigned)
        
        //--- Test SLE (Set if Less or Equal) ---
        for (i = 0; i < WARP_SIZE; i = i + 1) begin
            cmp_operand_a[i] = 64'h0000_0000_0000_0005;
            cmp_operand_b[i] = 64'h0000_0000_0000_0005;
        end
        cmp_func = CMP_SLE;
        #1;
        check_cmp_result("SLE (5 <= 5)", 8'hFF);  // All true
        
        //--- Test SGT (Set if Greater Than) ---
        for (i = 0; i < WARP_SIZE; i = i + 1) begin
            cmp_operand_a[i] = 64'h0000_0000_0000_000A;
            cmp_operand_b[i] = 64'h0000_0000_0000_0005;
        end
        cmp_func = CMP_SGT;
        #1;
        check_cmp_result("SGT (10 > 5)", 8'hFF);
        
        //--- Test SGE (Set if Greater or Equal) ---
        cmp_func = CMP_SGE;
        #1;
        check_cmp_result("SGE (10 >= 5)", 8'hFF);
        
        //--- Test PAND (Predicate AND) ---
        cmp_pred_a = 8'b1111_0000;
        cmp_pred_b = 8'b0011_0011;
        cmp_func = CMP_PAND;
        #1;
        check_cmp_result("PAND", 8'b0011_0000);
        
        //--- Test POR (Predicate OR) ---
        cmp_func = CMP_POR;
        #1;
        check_cmp_result("POR", 8'b1111_0011);
        
        //--- Test PXOR (Predicate XOR) ---
        cmp_func = CMP_PXOR;
        #1;
        check_cmp_result("PXOR", 8'b1100_0011);
        
        //--- Test PNOT (Predicate NOT) ---
        cmp_pred_a = 8'b1010_0101;
        cmp_func = CMP_PNOT;
        #1;
        check_cmp_result("PNOT", 8'b0101_1010);
        
        //--- Test with mixed active mask ---
        for (i = 0; i < WARP_SIZE; i = i + 1) begin
            cmp_operand_a[i] = 64'h0000_0000_0000_000A;
            cmp_operand_b[i] = 64'h0000_0000_0000_0005;
        end
        cmp_func = CMP_SGT;
        cmp_active_mask = 8'b0000_1111;  // Only lower 4 threads active
        #1;
        check_cmp_result("SGT with partial mask", 8'b0000_1111);
        cmp_active_mask = 8'hFF;
    endtask
    
    //=========================================================================
    // Mul/Div Unit Tests
    //=========================================================================
    
    task test_mul_div();
        $display("\n=== Testing Mul/Div Unit ===\n");
        
        //--- Test MUL (lower 64 bits) ---
        mul_operand_a[0] = 64'h0000_0000_0000_000A;  // 10
        mul_operand_b[0] = 64'h0000_0000_0000_0014;  // 20
        mul_func = MUL_MUL;
        mul_valid_in = 1;
        @(posedge clk);
        #1;
        check_mul_result("MUL (10 * 20)", 64'h0000_0000_0000_00C8);  // 200
        
        //--- Test MULH (signed upper 64 bits) ---
        mul_operand_a[0] = 64'h8000_0000_0000_0000;  // Large negative
        mul_operand_b[0] = 64'h0000_0000_0000_0002;  // 2
        mul_func = MUL_MULH;
        @(posedge clk);
        #1;
        check_mul_result("MULH signed", 64'hFFFF_FFFF_FFFF_FFFF);
        
        //--- Test MULHU (unsigned upper 64 bits) ---
        mul_operand_a[0] = 64'h8000_0000_0000_0000;
        mul_operand_b[0] = 64'h0000_0000_0000_0002;
        mul_func = MUL_MULHU;
        @(posedge clk);
        #1;
        check_mul_result("MULHU unsigned", 64'h0000_0000_0000_0001);
        
        //--- Test DIV signed ---
        mul_operand_a[0] = 64'h0000_0000_0000_0064;  // 100
        mul_operand_b[0] = 64'h0000_0000_0000_0005;  // 5
        mul_func = MUL_DIV;
        @(posedge clk);
        #1;
        check_mul_result("DIV (100 / 5)", 64'h0000_0000_0000_0014);  // 20
        
        //--- Test DIV negative ---
        mul_operand_a[0] = 64'hFFFF_FFFF_FFFF_FF9C;  // -100
        mul_operand_b[0] = 64'h0000_0000_0000_0005;  // 5
        @(posedge clk);
        #1;
        check_mul_result("DIV (-100 / 5)", 64'hFFFF_FFFF_FFFF_FFEC);  // -20
        
        //--- Test DIVU unsigned ---
        mul_operand_a[0] = 64'h0000_0000_0000_0064;  // 100
        mul_operand_b[0] = 64'h0000_0000_0000_0005;  // 5
        mul_func = MUL_DIVU;
        @(posedge clk);
        #1;
        check_mul_result("DIVU (100 / 5)", 64'h0000_0000_0000_0014);
        
        //--- Test REM signed ---
        mul_operand_a[0] = 64'h0000_0000_0000_0065;  // 101
        mul_operand_b[0] = 64'h0000_0000_0000_0005;  // 5
        mul_func = MUL_REM;
        @(posedge clk);
        #1;
        check_mul_result("REM (101 % 5)", 64'h0000_0000_0000_0001);  // 1
        
        //--- Test REMU unsigned ---
        mul_func = MUL_REMU;
        @(posedge clk);
        #1;
        check_mul_result("REMU (101 % 5)", 64'h0000_0000_0000_0001);
        
        //--- Test division by zero ---
        mul_operand_a[0] = 64'h0000_0000_0000_0064;  // 100
        mul_operand_b[0] = 64'h0000_0000_0000_0000;  // 0
        mul_func = MUL_DIV;
        @(posedge clk);
        #1;
        check_mul_result("DIV by zero", 64'hFFFF_FFFF_FFFF_FFFF);  // -1
        
        mul_valid_in = 0;
    endtask
    
    //=========================================================================
    // Execution Unit Integration Tests
    //=========================================================================
    
    task test_execution_unit();
        $display("\n=== Testing Execution Unit Integration ===\n");
        
        //--- Test ALU through execution unit ---
        ex_operand_a[0] = 64'h0000_0000_0000_0100;
        ex_operand_b[0] = 64'h0000_0000_0000_0200;
        ex_select = EX_ALU;
        ex_func = ALU_ADD;
        ex_valid_in = 1;
        #1;
        check_ex_result("Execution Unit: ALU ADD", 64'h0000_0000_0000_0300);
        
        //--- Test Shift through execution unit ---
        ex_operand_a[0] = 64'h0000_0000_0000_0001;
        ex_operand_b[0] = 64'h0000_0000_0000_0008;
        ex_select = EX_SHIFT;
        ex_func = SHIFT_SLL;
        #1;
        check_ex_result("Execution Unit: Shift SLL", 64'h0000_0000_0000_0100);
        
        //--- Test Mul through execution unit ---
        ex_operand_a[0] = 64'h0000_0000_0000_000A;
        ex_operand_b[0] = 64'h0000_0000_0000_000A;
        ex_select = EX_MUL;
        ex_func = MUL_MUL;
        @(posedge clk);
        #1;
        check_ex_result("Execution Unit: MUL", 64'h0000_0000_0000_0064);  // 100
        
        //--- Check ready and valid signals ---
        test_count++;
        if (ex_ready && ex_valid_out) begin
            $display("[PASS] Execution Unit: ready and valid signals correct");
            pass_count++;
        end else begin
            $display("[FAIL] Execution Unit: ready=%b, valid_out=%b", ex_ready, ex_valid_out);
            fail_count++;
        end
        
        ex_valid_in = 0;
    endtask
    
    //=========================================================================
    // SIMD Tests (All 8 threads)
    //=========================================================================
    
    task test_simd();
        logic all_correct;
        logic [DATA_WIDTH-1:0] expected;
        integer i;
        
        $display("\n=== Testing SIMD Operations (All 8 Threads) ===\n");
        
        // Set different values for each thread
        for (i = 0; i < WARP_SIZE; i = i + 1) begin
            alu_operand_a[i] = i * 10;      // 0, 10, 20, 30, 40, 50, 60, 70
            alu_operand_b[i] = i + 1;       // 1, 2, 3, 4, 5, 6, 7, 8
        end
        alu_func = ALU_ADD;
        alu_active_mask = 8'hFF;
        #1;
        
        // Check each thread result
        test_count++;
        all_correct = 1;
        for (i = 0; i < WARP_SIZE; i = i + 1) begin
            expected = (i * 10) + (i + 1);
            if (alu_result[i] !== expected) begin
                $display("[FAIL] SIMD ADD Thread %0d: Expected %0d, Got %0d", 
                         i, expected, alu_result[i]);
                all_correct = 0;
            end
        end
        if (all_correct) begin
            $display("[PASS] SIMD ADD: All 8 threads computed correctly");
            pass_count++;
        end else begin
            fail_count++;
        end
        
        // Test with partial mask
        alu_active_mask = 8'b1010_1010;  // Only even threads active
        #1;
        
        test_count++;
        all_correct = 1;
        for (i = 0; i < WARP_SIZE; i = i + 1) begin
            expected = alu_active_mask[i] ? ((i * 10) + (i + 1)) : 0;
            if (alu_result[i] !== expected) begin
                $display("[FAIL] SIMD masked ADD Thread %0d: Expected %0d, Got %0d",
                         i, expected, alu_result[i]);
                all_correct = 0;
            end
        end
        if (all_correct) begin
            $display("[PASS] SIMD masked ADD: Inactive threads produce 0");
            pass_count++;
        end else begin
            fail_count++;
        end
        
        alu_active_mask = 8'hFF;
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    
    initial begin
        $display("================================================================");
        $display("   GPGPU-1 ALU and Execution Unit Testbench");
        $display("================================================================");
        
        // Initialize
        rst_n = 0;
        initialize();
        
        // Reset sequence
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        
        // Run all tests
        test_alu();
        test_shift();
        test_compare();
        test_mul_div();
        test_execution_unit();
        test_simd();
        
        // Summary
        $display("\n================================================================");
        $display("   Test Summary");
        $display("================================================================");
        $display("   Total Tests: %0d", test_count);
        $display("   Passed:      %0d", pass_count);
        $display("   Failed:      %0d", fail_count);
        $display("================================================================\n");
        
        if (fail_count == 0) begin
            $display("*** ALL TESTS PASSED ***\n");
        end else begin
            $display("*** SOME TESTS FAILED ***\n");
        end
        
        $finish;
    end

endmodule
