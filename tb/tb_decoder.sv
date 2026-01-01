//=============================================================================
// GPGPU-1 Decoder Testbench
//=============================================================================
// File:        tb_decoder.sv
// Description: Testbench for the instruction decoder module.
//              Tests all instruction formats and key opcodes.
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_decoder;
    import gpgpu_pkg::*;

    //=========================================================================
    // Signals
    //=========================================================================
    
    logic [INST_WIDTH-1:0]   instr;
    logic                    instr_valid;
    decoded_instr_t          decoded;
    logic                    decode_valid;
    logic                    illegal_instr;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    
    decoder dut (
        .instr        (instr),
        .instr_valid  (instr_valid),
        .decoded      (decoded),
        .decode_valid (decode_valid),
        .illegal_instr(illegal_instr)
    );
    
    //=========================================================================
    // Test Counters
    //=========================================================================
    
    int tests_passed = 0;
    int tests_failed = 0;
    
    //=========================================================================
    // Helper Tasks
    //=========================================================================
    
    task automatic check_decode(
        input string test_name,
        input logic expected_valid,
        input opcode_t expected_opcode = OP_ALU,
        input logic [4:0] expected_rd = 5'd0,
        input logic [4:0] expected_rs1 = 5'd0,
        input logic [4:0] expected_rs2 = 5'd0,
        input logic expected_rd_en = 1'b0,
        input exec_unit_t expected_exec = EX_NONE
    );
        #1;
        
        if (decode_valid !== expected_valid) begin
            $display("[FAIL] %s: decode_valid = %b, expected %b", 
                     test_name, decode_valid, expected_valid);
            tests_failed++;
            return;
        end
        
        if (expected_valid) begin
            if (decoded.opcode !== expected_opcode) begin
                $display("[FAIL] %s: opcode = %s, expected %s",
                         test_name, decoded.opcode.name(), expected_opcode.name());
                tests_failed++;
                return;
            end
            
            if (decoded.rd !== expected_rd) begin
                $display("[FAIL] %s: rd = %d, expected %d",
                         test_name, decoded.rd, expected_rd);
                tests_failed++;
                return;
            end
            
            if (decoded.rs1 !== expected_rs1) begin
                $display("[FAIL] %s: rs1 = %d, expected %d",
                         test_name, decoded.rs1, expected_rs1);
                tests_failed++;
                return;
            end
            
            if (expected_exec !== EX_NONE && decoded.exec_unit !== expected_exec) begin
                $display("[FAIL] %s: exec_unit = %s, expected %s",
                         test_name, decoded.exec_unit.name(), expected_exec.name());
                tests_failed++;
                return;
            end
        end
        
        $display("[PASS] %s", test_name);
        tests_passed++;
    endtask
    
    task automatic test_instruction(
        input string name,
        input logic [31:0] instruction
    );
        instr = instruction;
        instr_valid = 1'b1;
        #1;
        $display("  Instruction: 0x%08h", instruction);
        $display("    Opcode:    %s (0x%02h)", decoded.opcode.name(), decoded.opcode);
        $display("    Format:    %s", decoded.format.name());
        $display("    RD:        R%0d (en=%b)", decoded.rd, decoded.rd_en);
        $display("    RS1:       R%0d (en=%b)", decoded.rs1, decoded.rs1_en);
        $display("    RS2:       R%0d (en=%b)", decoded.rs2, decoded.rs2_en);
        $display("    PRED:      P%0d (en=%b)", decoded.pred, decoded.pred_en);
        $display("    Func:      0x%02h", decoded.func);
        $display("    Imm:       0x%016h (en=%b)", decoded.imm, decoded.imm_en);
        $display("    Exec Unit: %s", decoded.exec_unit.name());
        $display("    Valid:     %b, Illegal: %b", decode_valid, illegal_instr);
        $display("");
    endtask
    
    //=========================================================================
    // Test Cases
    //=========================================================================
    
    initial begin
        $display("============================================================");
        $display("GPGPU-1 Decoder Testbench");
        $display("============================================================\n");
        
        instr = 32'h0;
        instr_valid = 1'b0;
        #10;
        
        //---------------------------------------------------------------------
        // Test 1: ADD R3, R1, R2 (Format R)
        //---------------------------------------------------------------------
        $display("Test 1: ADD R3, R1, R2");
        // Encoding: 000000 | 00011 | 00001 | 00010 | 000 | 00000000
        //           opcode   RD      RS1     RS2    PRED   FUNC
        instr = {6'b000000, 5'd3, 5'd1, 5'd2, 3'b000, 8'h00};
        test_instruction("ADD R3, R1, R2", instr);
        check_decode("ADD R3, R1, R2", 1'b1, OP_ALU, 5'd3, 5'd1, 5'd2, 1'b1, EX_ALU);
        
        //---------------------------------------------------------------------
        // Test 2: SUB R5, R10, R15 with P1 predicate
        //---------------------------------------------------------------------
        $display("Test 2: SUB R5, R10, R15 @P1");
        instr = {6'b000000, 5'd5, 5'd10, 5'd15, 3'b001, 8'h01};
        test_instruction("SUB R5, R10, R15 @P1", instr);
        check_decode("SUB @P1", 1'b1, OP_ALU, 5'd5, 5'd10, 5'd15, 1'b1, EX_ALU);
        
        //---------------------------------------------------------------------
        // Test 3: ADDI R7, R3, 100 (Format I)
        //---------------------------------------------------------------------
        $display("Test 3: ADDI R7, R3, 100");
        // Encoding: 000001 | 00111 | 00011 | 00 | 00000001100100
        //           opcode   RD      RS1    func   imm14(100)
        instr = {6'b000001, 5'd7, 5'd3, 2'b00, 14'd100};
        test_instruction("ADDI R7, R3, 100", instr);
        check_decode("ADDI", 1'b1, OP_ALUI, 5'd7, 5'd3, 5'd0, 1'b1, EX_ALU);
        
        //---------------------------------------------------------------------
        // Test 4: LD R5, 16(R10) (Format L)
        //---------------------------------------------------------------------
        $display("Test 4: LD R5, 16(R10)");
        // Encoding: 001000 | 00101 | 01010 | 000 | 0000000010000
        //           opcode   RD      RBASE  PRED   OFFSET(16)
        instr = {6'b001000, 5'd5, 5'd10, 3'b000, 13'd16};
        test_instruction("LD R5, 16(R10)", instr);
        check_decode("LD", 1'b1, OP_LD, 5'd5, 5'd10, 5'd0, 1'b1, EX_LSU);
        if (decoded.mem_access !== MEM_LOAD_64) begin
            $display("[FAIL] LD: mem_access should be MEM_LOAD_64");
            tests_failed++;
        end else begin
            $display("[PASS] LD: mem_access = MEM_LOAD_64");
            tests_passed++;
        end
        
        //---------------------------------------------------------------------
        // Test 5: ST R8, -8(R20) (Format L, negative offset)
        //---------------------------------------------------------------------
        $display("Test 5: ST R8, -8(R20)");
        // Offset -8 in 13-bit signed = 1111111111000
        instr = {6'b001100, 5'd8, 5'd20, 3'b000, 13'b1111111111000};
        test_instruction("ST R8, -8(R20)", instr);
        check_decode("ST", 1'b1, OP_ST, 5'd8, 5'd20, 5'd0, 1'b0, EX_LSU);
        if (decoded.imm !== 64'hFFFFFFFFFFFFFFF8) begin
            $display("[FAIL] ST: imm should be -8 (0xFFFFFFFFFFFFFFF8), got 0x%016h", decoded.imm);
            tests_failed++;
        end else begin
            $display("[PASS] ST: negative offset sign-extended correctly");
            tests_passed++;
        end
        
        //---------------------------------------------------------------------
        // Test 6: BRA -8 (branch back 2 instructions)
        //---------------------------------------------------------------------
        $display("Test 6: BRA -8 (offset -2 words)");
        // Encoding: 010000 | 000 | 000 | 11111111111111111110 (-2)
        instr = {6'b010000, 3'b000, 3'b000, 20'hFFFFE};
        test_instruction("BRA -8", instr);
        check_decode("BRA", 1'b1, OP_BRA, 5'd0, 5'd0, 5'd0, 1'b0, EX_BRANCH);
        // Immediate should be -8 (offset -2 << 2)
        if (decoded.imm !== 64'hFFFFFFFFFFFFFFF8) begin
            $display("[FAIL] BRA: imm should be -8, got 0x%016h", decoded.imm);
            tests_failed++;
        end else begin
            $display("[PASS] BRA: branch offset calculated correctly");
            tests_passed++;
        end
        
        //---------------------------------------------------------------------
        // Test 7: BRC.TRUE P1, +16
        //---------------------------------------------------------------------
        $display("Test 7: BRC.TRUE P1, +16 (offset +4 words)");
        // Encoding: 010001 | 001 | 001 | 00000000000000000100 (+4)
        instr = {6'b010001, 3'b001, 3'b001, 20'd4};
        test_instruction("BRC.TRUE P1, +16", instr);
        check_decode("BRC", 1'b1, OP_BRC, 5'd0, 5'd0, 5'd0, 1'b0, EX_BRANCH);
        if (decoded.pred !== 3'd1) begin
            $display("[FAIL] BRC: pred should be P1");
            tests_failed++;
        end else begin
            $display("[PASS] BRC: predicate P1 extracted correctly");
            tests_passed++;
        end
        
        //---------------------------------------------------------------------
        // Test 8: PUSH P2
        //---------------------------------------------------------------------
        $display("Test 8: PUSH P2");
        // Encoding: 010110 | 00000 | 00000 | 010 | 0000000000000
        instr = {6'b010110, 5'd0, 5'd0, 3'b010, 13'd0};
        test_instruction("PUSH P2", instr);
        check_decode("PUSH", 1'b1, OP_PUSH, 5'd0, 5'd0, 5'd0, 1'b0, EX_SPECIAL);
        if (!decoded.is_push) begin
            $display("[FAIL] PUSH: is_push should be 1");
            tests_failed++;
        end else begin
            $display("[PASS] PUSH: is_push flag set");
            tests_passed++;
        end
        
        //---------------------------------------------------------------------
        // Test 9: POP
        //---------------------------------------------------------------------
        $display("Test 9: POP");
        instr = {6'b010111, 5'd0, 5'd0, 3'b000, 13'd0};
        test_instruction("POP", instr);
        check_decode("POP", 1'b1, OP_POP, 5'd0, 5'd0, 5'd0, 1'b0, EX_SPECIAL);
        
        //---------------------------------------------------------------------
        // Test 10: ELSE
        //---------------------------------------------------------------------
        $display("Test 10: ELSE");
        instr = {6'b011000, 5'd0, 5'd0, 3'b000, 13'd0};
        test_instruction("ELSE", instr);
        check_decode("ELSE", 1'b1, OP_ELSE, 5'd0, 5'd0, 5'd0, 1'b0, EX_SPECIAL);
        
        //---------------------------------------------------------------------
        // Test 11: BAR 5
        //---------------------------------------------------------------------
        $display("Test 11: BAR 5");
        instr = {6'b010101, 5'd0, 5'd0, 3'b000, 13'd5};
        test_instruction("BAR 5", instr);
        if (!decoded.is_barrier) begin
            $display("[FAIL] BAR: is_barrier should be 1");
            tests_failed++;
        end else begin
            $display("[PASS] BAR: is_barrier flag set");
            tests_passed++;
        end
        
        //---------------------------------------------------------------------
        // Test 12: SEQ P3, R5, R10 (Compare)
        //---------------------------------------------------------------------
        $display("Test 12: SEQ P3, R5, R10");
        // Encoding: 000110 | 00011 | 00101 | 01010 | 000 | 00000000
        instr = {6'b000110, 5'd3, 5'd5, 5'd10, 3'b000, 8'h00};
        test_instruction("SEQ P3, R5, R10", instr);
        check_decode("SEQ", 1'b1, OP_CMP, 5'd3, 5'd5, 5'd10, 1'b0, EX_CMP);
        if (!decoded.pred_wr_en) begin
            $display("[FAIL] SEQ: pred_wr_en should be 1");
            tests_failed++;
        end else begin
            $display("[PASS] SEQ: pred_wr_en set correctly");
            tests_passed++;
        end
        
        //---------------------------------------------------------------------
        // Test 13: LUI R10, 0xABCD
        //---------------------------------------------------------------------
        $display("Test 13: LUI R10, 0xABCD");
        // Encoding: 011101 | 01010 | 00000 | 1010101111001101
        instr = {6'b011101, 5'd10, 5'd0, 16'hABCD};
        test_instruction("LUI R10, 0xABCD", instr);
        check_decode("LUI", 1'b1, OP_LUI, 5'd10, 5'd0, 5'd0, 1'b1, EX_ALU);
        if (decoded.imm !== 64'hABCD_0000_0000_0000) begin
            $display("[FAIL] LUI: imm should be 0xABCD000000000000, got 0x%016h", decoded.imm);
            tests_failed++;
        end else begin
            $display("[PASS] LUI: immediate placed in upper bits correctly");
            tests_passed++;
        end
        
        //---------------------------------------------------------------------
        // Test 14: MOVSR R1, SR_TID
        //---------------------------------------------------------------------
        $display("Test 14: MOVSR R1, SR_TID");
        // Encoding: 011011 | 00001 | 00000 | 0000000000000000
        instr = {6'b011011, 5'd1, 5'd0, 16'd0};
        test_instruction("MOVSR R1, SR_TID", instr);
        check_decode("MOVSR", 1'b1, OP_MOVSR, 5'd1, 5'd0, 5'd0, 1'b1, EX_SPECIAL);
        
        //---------------------------------------------------------------------
        // Test 15: MUL R20, R5, R6
        //---------------------------------------------------------------------
        $display("Test 15: MUL R20, R5, R6");
        instr = {6'b000010, 5'd20, 5'd5, 5'd6, 3'b000, 8'h00};
        test_instruction("MUL R20, R5, R6", instr);
        check_decode("MUL", 1'b1, OP_MUL, 5'd20, 5'd5, 5'd6, 1'b1, EX_MUL);
        
        //---------------------------------------------------------------------
        // Test 16: SLLI R3, R1, 5
        //---------------------------------------------------------------------
        $display("Test 16: SLLI R3, R1, 5");
        // Encoding: 000101 | 00011 | 00001 | 00 | 000101 | 00000000
        instr = {6'b000101, 5'd3, 5'd1, 2'b00, 6'd5, 8'd0};
        test_instruction("SLLI R3, R1, 5", instr);
        check_decode("SLLI", 1'b1, OP_SHIFTI, 5'd3, 5'd1, 5'd0, 1'b1, EX_SHIFT);
        if (decoded.imm !== 64'd5) begin
            $display("[FAIL] SLLI: shamt should be 5, got %0d", decoded.imm);
            tests_failed++;
        end else begin
            $display("[PASS] SLLI: shift amount extracted correctly");
            tests_passed++;
        end
        
        //---------------------------------------------------------------------
        // Test 17: LDS R4, 32(R15) (Shared memory load)
        //---------------------------------------------------------------------
        $display("Test 17: LDS R4, 32(R15)");
        instr = {6'b001011, 5'd4, 5'd15, 3'b000, 13'd32};
        test_instruction("LDS R4, 32(R15)", instr);
        if (decoded.mem_space !== MEM_SPACE_SHARED) begin
            $display("[FAIL] LDS: mem_space should be MEM_SPACE_SHARED");
            tests_failed++;
        end else begin
            $display("[PASS] LDS: mem_space = MEM_SPACE_SHARED");
            tests_passed++;
        end
        
        //---------------------------------------------------------------------
        // Test 18: EXIT
        //---------------------------------------------------------------------
        $display("Test 18: EXIT");
        instr = {6'b010100, 5'd0, 5'd0, 16'd0};
        test_instruction("EXIT", instr);
        if (!decoded.is_exit) begin
            $display("[FAIL] EXIT: is_exit should be 1");
            tests_failed++;
        end else begin
            $display("[PASS] EXIT: is_exit flag set");
            tests_passed++;
        end
        
        //---------------------------------------------------------------------
        // Test 19: Illegal instruction (reserved opcode 0x2E)
        // Note: Opcodes 0x20-0x2D are valid FP opcodes, 0x2E+ are reserved
        //---------------------------------------------------------------------
        $display("Test 19: Illegal instruction (opcode 0x2E)");
        instr = {6'b101110, 26'd0};  // Opcode 0x2E (truly reserved)
        instr_valid = 1'b1;
        #1;
        if (!illegal_instr) begin
            $display("[FAIL] Illegal: should be flagged as illegal");
            tests_failed++;
        end else begin
            $display("[PASS] Illegal: correctly flagged as illegal");
            tests_passed++;
        end
        $display("");
        
        //---------------------------------------------------------------------
        // Test 20: Invalid instruction (instr_valid = 0)
        //---------------------------------------------------------------------
        $display("Test 20: Invalid instruction input");
        instr = {6'b000000, 5'd3, 5'd1, 5'd2, 3'b000, 8'h00};
        instr_valid = 1'b0;
        #1;
        if (decode_valid) begin
            $display("[FAIL] Invalid: decode_valid should be 0");
            tests_failed++;
        end else begin
            $display("[PASS] Invalid: decode_valid correctly 0");
            tests_passed++;
        end
        $display("");
        
        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        $display("============================================================");
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
