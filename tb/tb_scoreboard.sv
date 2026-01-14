//=============================================================================
// Scoreboard Testbench
//=============================================================================
// File:        tb_scoreboard.sv
// Description: Testbench for the scoreboard data hazard detection module
// Version:     1.0
//=============================================================================

`timescale 1ns/1ps

module tb_scoreboard;

    import gpgpu_pkg::*;

    //=========================================================================
    // Parameters
    //=========================================================================
    
    parameter int NUM_WARPS = 4;
    
    //=========================================================================
    // Signals
    //=========================================================================
    
    logic                       clk;
    logic                       rst_n;
    
    // Check interface
    logic                       check_valid;
    logic [WARP_ID_WIDTH-1:0]   check_warp_id;
    logic [REG_ADDR_WIDTH-1:0]  check_rs1;
    logic [REG_ADDR_WIDTH-1:0]  check_rs2;
    logic                       check_rs1_en;
    logic                       check_rs2_en;
    logic                       hazard_detected;
    
    // Reserve interface
    logic                       reserve_valid;
    logic [WARP_ID_WIDTH-1:0]   reserve_warp_id;
    logic [REG_ADDR_WIDTH-1:0]  reserve_rd;
    logic                       reserve_rd_en;
    
    // Complete interface
    logic                       complete_valid;
    logic [WARP_ID_WIDTH-1:0]   complete_warp_id;
    logic [REG_ADDR_WIDTH-1:0]  complete_rd;
    
    // Clear interface
    logic                       clear_warp;
    logic [WARP_ID_WIDTH-1:0]   clear_warp_id;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    
    scoreboard #(
        .NUM_WARPS(NUM_WARPS)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .check_valid      (check_valid),
        .check_warp_id    (check_warp_id),
        .check_rs1        (check_rs1),
        .check_rs2        (check_rs2),
        .check_rs1_en     (check_rs1_en),
        .check_rs2_en     (check_rs2_en),
        .hazard_detected  (hazard_detected),
        .reserve_valid    (reserve_valid),
        .reserve_warp_id  (reserve_warp_id),
        .reserve_rd       (reserve_rd),
        .reserve_rd_en    (reserve_rd_en),
        .complete_valid   (complete_valid),
        .complete_warp_id (complete_warp_id),
        .complete_rd      (complete_rd),
        .clear_warp       (clear_warp),
        .clear_warp_id    (clear_warp_id)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    
    initial clk = 0;
    always #5 clk <= ~clk;
    
    //=========================================================================
    // Test Counters
    //=========================================================================
    
    int tests_passed = 0;
    int tests_failed = 0;
    
    //=========================================================================
    // Helper Tasks
    //=========================================================================
    
    task automatic reset();
        rst_n = 1'b0;
        check_valid = 1'b0;
        check_warp_id = '0;
        check_rs1 = '0;
        check_rs2 = '0;
        check_rs1_en = 1'b0;
        check_rs2_en = 1'b0;
        reserve_valid = 1'b0;
        reserve_warp_id = '0;
        reserve_rd = '0;
        reserve_rd_en = 1'b0;
        complete_valid = 1'b0;
        complete_warp_id = '0;
        complete_rd = '0;
        clear_warp = 1'b0;
        clear_warp_id = '0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
    endtask
    
    task automatic check_hazard(
        input logic [WARP_ID_WIDTH-1:0] warp_id,
        input logic [REG_ADDR_WIDTH-1:0] rs1,
        input logic [REG_ADDR_WIDTH-1:0] rs2,
        input logic rs1_en,
        input logic rs2_en
    );
        check_valid = 1'b1;
        check_warp_id = warp_id;
        check_rs1 = rs1;
        check_rs2 = rs2;
        check_rs1_en = rs1_en;
        check_rs2_en = rs2_en;
        #1; // Combinational - just need small delay
    endtask
    
    task automatic reserve_reg(
        input logic [WARP_ID_WIDTH-1:0] warp_id,
        input logic [REG_ADDR_WIDTH-1:0] rd,
        input logic rd_en
    );
        // Set signals before clock edge
        reserve_valid = 1'b1;
        reserve_warp_id = warp_id;
        reserve_rd = rd;
        reserve_rd_en = rd_en;
        
        // Wait for posedge - the always_ff samples on this edge
        @(posedge clk);
        
        // After the posedge, the register has sampled, now we can clear
        // But wait until after combinational settling
        #1;
        reserve_valid = 1'b0;
        
        // Wait for the registered output to be visible
        @(posedge clk);
    endtask
    
    task automatic complete_reg(
        input logic [WARP_ID_WIDTH-1:0] warp_id,
        input logic [REG_ADDR_WIDTH-1:0] rd
    );
        // Set signals before clock edge
        complete_valid = 1'b1;
        complete_warp_id = warp_id;
        complete_rd = rd;
        
        // Wait for posedge - the always_ff samples on this edge
        @(posedge clk);
        
        // After the posedge, the register has sampled, now we can clear
        #1;
        complete_valid = 1'b0;
        
        // Wait for the registered output to be visible
        @(posedge clk);
    endtask
    
    task automatic clear_warp_scoreboard(
        input logic [WARP_ID_WIDTH-1:0] warp_id
    );
        // Set signals before clock edge
        clear_warp = 1'b1;
        clear_warp_id = warp_id;
        
        // Wait for posedge - the always_ff samples on this edge
        @(posedge clk);
        
        // After the posedge, the register has sampled, now we can clear
        #1;
        clear_warp = 1'b0;
        
        // Wait for the registered output to be visible
        @(posedge clk);
    endtask
    
    task automatic check_result(input string test_name, input logic expected);
        if (hazard_detected == expected) begin
            $display("[PASS] %s", test_name);
            tests_passed++;
        end else begin
            $display("[FAIL] %s: expected=%b, got=%b", test_name, expected, hazard_detected);
            tests_failed++;
        end
        check_valid = 1'b0;
    endtask
    
    //=========================================================================
    // Test Sequence
    //=========================================================================
    
    initial begin
        $display("===========================================");
        $display("Scoreboard Testbench");
        $display("===========================================");
        
        reset();
        
        //=====================================================================
        // Test 1: No hazard on empty scoreboard
        //=====================================================================
        $display("\n--- Test 1: Empty scoreboard ---");
        check_hazard(0, 5'd1, 5'd2, 1'b1, 1'b1);
        check_result("Empty scoreboard - no hazard", 1'b0);
        
        //=====================================================================
        // Test 2: Reserve R1, check RS1 = R1 for hazard
        //=====================================================================
        $display("\n--- Test 2: RAW hazard on RS1 ---");
        reserve_reg(0, 5'd1, 1'b1);  // Reserve R1 in warp 0
        check_hazard(0, 5'd1, 5'd2, 1'b1, 1'b1);  // Check RS1=R1
        check_result("RAW hazard on RS1=R1", 1'b1);
        
        //=====================================================================
        // Test 3: Check different register - no hazard
        //=====================================================================
        $display("\n--- Test 3: No hazard on different register ---");
        check_hazard(0, 5'd3, 5'd4, 1'b1, 1'b1);  // Check RS1=R3, RS2=R4
        check_result("No hazard on R3/R4", 1'b0);
        
        //=====================================================================
        // Test 4: RAW hazard on RS2
        //=====================================================================
        $display("\n--- Test 4: RAW hazard on RS2 ---");
        reserve_reg(0, 5'd5, 1'b1);  // Reserve R5 in warp 0
        check_hazard(0, 5'd10, 5'd5, 1'b1, 1'b1);  // Check RS2=R5
        check_result("RAW hazard on RS2=R5", 1'b1);
        
        //=====================================================================
        // Test 5: Complete R1, hazard should clear
        //=====================================================================
        $display("\n--- Test 5: Complete clears hazard ---");
        complete_reg(0, 5'd1);  // Complete R1
        check_hazard(0, 5'd1, 5'd2, 1'b1, 1'b1);  // Check RS1=R1
        check_result("No hazard after R1 complete", 1'b0);
        
        //=====================================================================
        // Test 6: R5 still pending
        //=====================================================================
        $display("\n--- Test 6: R5 still pending ---");
        check_hazard(0, 5'd5, 5'd0, 1'b1, 1'b0);  // Check RS1=R5
        check_result("R5 still pending", 1'b1);
        
        //=====================================================================
        // Test 7: Register 0 should never cause hazard
        //=====================================================================
        $display("\n--- Test 7: R0 never causes hazard ---");
        reserve_reg(0, 5'd0, 1'b1);  // Try to reserve R0 (should be ignored)
        check_hazard(0, 5'd0, 5'd0, 1'b1, 1'b1);  // Check R0
        check_result("R0 never causes hazard", 1'b0);
        
        //=====================================================================
        // Test 8: Different warp - no hazard
        //=====================================================================
        $display("\n--- Test 8: Different warp isolation ---");
        check_hazard(1, 5'd5, 5'd0, 1'b1, 1'b0);  // Warp 1, check R5
        check_result("Warp 1 has no R5 hazard", 1'b0);
        
        //=====================================================================
        // Test 9: Reserve in warp 1
        //=====================================================================
        $display("\n--- Test 9: Multi-warp tracking ---");
        reserve_reg(1, 5'd10, 1'b1);  // Reserve R10 in warp 1
        check_hazard(1, 5'd10, 5'd0, 1'b1, 1'b0);
        check_result("Warp 1 R10 hazard", 1'b1);
        check_hazard(0, 5'd10, 5'd0, 1'b1, 1'b0);
        check_result("Warp 0 no R10 hazard", 1'b0);
        
        //=====================================================================
        // Test 10: Multiple pending registers
        //=====================================================================
        $display("\n--- Test 10: Multiple pending registers ---");
        reserve_reg(2, 5'd15, 1'b1);  // Reserve R15 in warp 2
        reserve_reg(2, 5'd16, 1'b1);  // Reserve R16 in warp 2
        reserve_reg(2, 5'd17, 1'b1);  // Reserve R17 in warp 2
        check_hazard(2, 5'd15, 5'd16, 1'b1, 1'b1);
        check_result("Both RS1=R15 and RS2=R16 hazard", 1'b1);
        check_hazard(2, 5'd20, 5'd17, 1'b1, 1'b1);
        check_result("RS2=R17 hazard", 1'b1);
        check_hazard(2, 5'd20, 5'd21, 1'b1, 1'b1);
        check_result("No hazard on R20/R21", 1'b0);
        
        //=====================================================================
        // Test 11: Clear warp
        //=====================================================================
        $display("\n--- Test 11: Clear warp ---");
        clear_warp_scoreboard(2);
        check_hazard(2, 5'd15, 5'd16, 1'b1, 1'b1);
        check_result("After clear, no hazard on R15/R16", 1'b0);
        check_hazard(2, 5'd17, 5'd0, 1'b1, 1'b0);
        check_result("After clear, no hazard on R17", 1'b0);
        
        //=====================================================================
        // Test 12: RS1/RS2 enable flags
        //=====================================================================
        $display("\n--- Test 12: Enable flags ---");
        reserve_reg(3, 5'd8, 1'b1);  // Reserve R8 in warp 3
        check_hazard(3, 5'd8, 5'd0, 1'b0, 1'b0);  // Both disabled
        check_result("No hazard when RS1 disabled", 1'b0);
        check_hazard(3, 5'd8, 5'd0, 1'b1, 1'b0);  // RS1 enabled
        check_result("Hazard when RS1 enabled", 1'b1);
        
        //=====================================================================
        // Test 13: rd_en flag
        //=====================================================================
        $display("\n--- Test 13: rd_en flag ---");
        complete_reg(3, 5'd8);  // Clear previous
        reserve_reg(3, 5'd9, 1'b0);  // rd_en = 0, should not reserve
        check_hazard(3, 5'd9, 5'd0, 1'b1, 1'b0);
        check_result("No hazard when rd_en was 0", 1'b0);
        
        //=====================================================================
        // Summary
        //=====================================================================
        $display("\n===========================================");
        $display("Test Summary");
        $display("===========================================");
        $display("Tests Passed: %0d", tests_passed);
        $display("Tests Failed: %0d", tests_failed);
        $display("===========================================");
        
        if (tests_failed == 0) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("*** SOME TESTS FAILED ***");
        end
        
        $finish;
    end

endmodule
