//=============================================================================
// GPGPU-1 Forwarding Network Testbench
//=============================================================================
// File:        tb_forwarding_network.sv
// Description: Tests the data forwarding network for RAW hazard resolution
// Version:     1.0
// Date:        January 1, 2026
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_forwarding_network;
    import gpgpu_pkg::*;
    
    //=========================================================================
    // Parameters
    //=========================================================================
    
    parameter CLK_PERIOD = 10;
    parameter NUM_WARPS = 8;
    
    //=========================================================================
    // DUT Signals
    //=========================================================================
    
    logic                    clk;
    logic                    rst_n;
    
    // Operand fetch stage
    logic                            operand_valid;
    logic [WARP_ID_WIDTH-1:0]        operand_warp_id;
    logic [REG_ADDR_WIDTH-1:0]       operand_rs1;
    logic [REG_ADDR_WIDTH-1:0]       operand_rs2;
    logic                            operand_rs1_en;
    logic                            operand_rs2_en;
    
    // Register file data
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rf_rs1_data;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rf_rs2_data;
    
    // E2M forwarding source
    logic                            e2m_valid;
    logic [WARP_ID_WIDTH-1:0]        e2m_warp_id;
    logic [REG_ADDR_WIDTH-1:0]       e2m_rd;
    logic                            e2m_rd_en;
    logic [WARP_SIZE-1:0]            e2m_mask;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] e2m_result;
    logic                            e2m_is_mem;
    
    // M2W forwarding source
    logic                            m2w_valid;
    logic [WARP_ID_WIDTH-1:0]        m2w_warp_id;
    logic [REG_ADDR_WIDTH-1:0]       m2w_rd;
    logic                            m2w_rd_en;
    logic [WARP_SIZE-1:0]            m2w_mask;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] m2w_data;
    
    // WB forwarding source
    logic                            wb_valid;
    logic [WARP_ID_WIDTH-1:0]        wb_warp_id;
    logic [REG_ADDR_WIDTH-1:0]       wb_rd;
    logic                            wb_rd_en;
    logic [WARP_SIZE-1:0]            wb_mask;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] wb_data;
    
    // Outputs
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] fwd_rs1_data;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] fwd_rs2_data;
    logic                            fwd_rs1_from_e2m;
    logic                            fwd_rs1_from_m2w;
    logic                            fwd_rs1_from_wb;
    logic                            fwd_rs2_from_e2m;
    logic                            fwd_rs2_from_m2w;
    logic                            fwd_rs2_from_wb;
    logic                            fwd_stall_required;
    
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
    
    forwarding_network #(
        .NUM_WARPS(NUM_WARPS)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .operand_valid      (operand_valid),
        .operand_warp_id    (operand_warp_id),
        .operand_rs1        (operand_rs1),
        .operand_rs2        (operand_rs2),
        .operand_rs1_en     (operand_rs1_en),
        .operand_rs2_en     (operand_rs2_en),
        .rf_rs1_data        (rf_rs1_data),
        .rf_rs2_data        (rf_rs2_data),
        .e2m_valid          (e2m_valid),
        .e2m_warp_id        (e2m_warp_id),
        .e2m_rd             (e2m_rd),
        .e2m_rd_en          (e2m_rd_en),
        .e2m_mask           (e2m_mask),
        .e2m_result         (e2m_result),
        .e2m_is_mem         (e2m_is_mem),
        .m2w_valid          (m2w_valid),
        .m2w_warp_id        (m2w_warp_id),
        .m2w_rd             (m2w_rd),
        .m2w_rd_en          (m2w_rd_en),
        .m2w_mask           (m2w_mask),
        .m2w_data           (m2w_data),
        .wb_valid           (wb_valid),
        .wb_warp_id         (wb_warp_id),
        .wb_rd              (wb_rd),
        .wb_rd_en           (wb_rd_en),
        .wb_mask            (wb_mask),
        .wb_data            (wb_data),
        .fwd_rs1_data       (fwd_rs1_data),
        .fwd_rs2_data       (fwd_rs2_data),
        .fwd_rs1_from_e2m   (fwd_rs1_from_e2m),
        .fwd_rs1_from_m2w   (fwd_rs1_from_m2w),
        .fwd_rs1_from_wb    (fwd_rs1_from_wb),
        .fwd_rs2_from_e2m   (fwd_rs2_from_e2m),
        .fwd_rs2_from_m2w   (fwd_rs2_from_m2w),
        .fwd_rs2_from_wb    (fwd_rs2_from_wb),
        .fwd_stall_required (fwd_stall_required)
    );
    
    //=========================================================================
    // Test Tasks
    //=========================================================================
    
    task automatic reset();
        rst_n = 1'b0;
        operand_valid = 1'b0;
        operand_warp_id = '0;
        operand_rs1 = '0;
        operand_rs2 = '0;
        operand_rs1_en = 1'b0;
        operand_rs2_en = 1'b0;
        
        for (int i = 0; i < WARP_SIZE; i++) begin
            rf_rs1_data[i] = 64'hDEAD_BEEF_0000_0000 | i;
            rf_rs2_data[i] = 64'hCAFE_BABE_0000_0000 | i;
        end
        
        e2m_valid = 1'b0;
        e2m_warp_id = '0;
        e2m_rd = '0;
        e2m_rd_en = 1'b0;
        e2m_mask = '0;
        e2m_is_mem = 1'b0;
        for (int i = 0; i < WARP_SIZE; i++) e2m_result[i] = '0;
        
        m2w_valid = 1'b0;
        m2w_warp_id = '0;
        m2w_rd = '0;
        m2w_rd_en = 1'b0;
        m2w_mask = '0;
        for (int i = 0; i < WARP_SIZE; i++) m2w_data[i] = '0;
        
        wb_valid = 1'b0;
        wb_warp_id = '0;
        wb_rd = '0;
        wb_rd_en = 1'b0;
        wb_mask = '0;
        for (int i = 0; i < WARP_SIZE; i++) wb_data[i] = '0;
        
        @(posedge clk);
        #1;
        rst_n = 1'b1;
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
    
    task automatic check_data(
        input string test_name,
        input logic [DATA_WIDTH-1:0] expected,
        input logic [DATA_WIDTH-1:0] actual
    );
        test_count++;
        if (actual == expected) begin
            $display("[PASS] %s", test_name);
            pass_count++;
        end else begin
            $display("[FAIL] %s: expected 0x%016X, got 0x%016X", test_name, expected, actual);
            fail_count++;
        end
    endtask
    
    //=========================================================================
    // Main Test
    //=========================================================================
    
    initial begin
        $display("==============================================");
        $display("Forwarding Network Testbench");
        $display("==============================================");
        
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        reset();
        
        //=====================================================================
        // Test 1: No forwarding - use register file data
        //=====================================================================
        $display("\n--- Test 1: No Forwarding ---");
        
        operand_valid = 1'b1;
        operand_warp_id = 3'd0;
        operand_rs1 = 5'd5;
        operand_rs2 = 5'd6;
        operand_rs1_en = 1'b1;
        operand_rs2_en = 1'b1;
        
        #1;  // Combinational settling
        
        check_result("No RS1 forwarding", 1'b0, fwd_rs1_from_e2m || fwd_rs1_from_m2w || fwd_rs1_from_wb);
        check_result("No RS2 forwarding", 1'b0, fwd_rs2_from_e2m || fwd_rs2_from_m2w || fwd_rs2_from_wb);
        check_data("RS1 from RF", rf_rs1_data[0], fwd_rs1_data[0]);
        check_data("RS2 from RF", rf_rs2_data[0], fwd_rs2_data[0]);
        check_result("No stall required", 1'b0, fwd_stall_required);
        
        //=====================================================================
        // Test 2: Forward RS1 from E2M
        //=====================================================================
        $display("\n--- Test 2: Forward RS1 from E2M ---");
        
        // E2M has result for R5
        e2m_valid = 1'b1;
        e2m_warp_id = 3'd0;
        e2m_rd = 5'd5;
        e2m_rd_en = 1'b1;
        e2m_mask = 8'hFF;
        e2m_is_mem = 1'b0;
        for (int i = 0; i < WARP_SIZE; i++) e2m_result[i] = 64'hE200_DA7A_0000_0000 | i;
        
        #1;
        
        check_result("RS1 from E2M", 1'b1, fwd_rs1_from_e2m);
        check_result("RS1 not from M2W", 1'b0, fwd_rs1_from_m2w);
        check_result("RS1 not from WB", 1'b0, fwd_rs1_from_wb);
        check_data("RS1 forwarded from E2M", e2m_result[0], fwd_rs1_data[0]);
        check_result("RS2 not forwarded", 1'b0, fwd_rs2_from_e2m);
        
        //=====================================================================
        // Test 3: Forward RS2 from M2W
        //=====================================================================
        $display("\n--- Test 3: Forward RS2 from M2W ---");
        
        // M2W has result for R6
        m2w_valid = 1'b1;
        m2w_warp_id = 3'd0;
        m2w_rd = 5'd6;
        m2w_rd_en = 1'b1;
        m2w_mask = 8'hFF;
        for (int i = 0; i < WARP_SIZE; i++) m2w_data[i] = 64'h0200_DA7A_0000_0000 | i;
        
        #1;
        
        check_result("RS1 still from E2M", 1'b1, fwd_rs1_from_e2m);
        check_result("RS2 from M2W", 1'b1, fwd_rs2_from_m2w);
        check_data("RS2 forwarded from M2W", m2w_data[0], fwd_rs2_data[0]);
        
        //=====================================================================
        // Test 4: E2M has priority over M2W
        //=====================================================================
        $display("\n--- Test 4: E2M Priority over M2W ---");
        
        // Both E2M and M2W have R5
        m2w_rd = 5'd5;
        for (int i = 0; i < WARP_SIZE; i++) m2w_data[i] = 64'h02A0_01D0_0000_0000 | i;
        
        #1;
        
        check_result("RS1 from E2M (priority)", 1'b1, fwd_rs1_from_e2m);
        check_result("RS1 not from M2W", 1'b0, fwd_rs1_from_m2w);
        check_data("RS1 is E2M data (newer)", e2m_result[0], fwd_rs1_data[0]);
        
        //=====================================================================
        // Test 5: WB forwarding
        //=====================================================================
        $display("\n--- Test 5: WB Forwarding ---");
        
        // Reset E2M and M2W
        e2m_valid = 1'b0;
        m2w_valid = 1'b0;
        
        // WB has R5
        wb_valid = 1'b1;
        wb_warp_id = 3'd0;
        wb_rd = 5'd5;
        wb_rd_en = 1'b1;
        wb_mask = 8'hFF;
        for (int i = 0; i < WARP_SIZE; i++) wb_data[i] = 64'h0B00_DA7A_0000_0000 | i;
        
        #1;
        
        check_result("RS1 from WB", 1'b1, fwd_rs1_from_wb);
        check_result("RS1 not from E2M", 1'b0, fwd_rs1_from_e2m);
        check_result("RS1 not from M2W", 1'b0, fwd_rs1_from_m2w);
        check_data("RS1 forwarded from WB", wb_data[0], fwd_rs1_data[0]);
        
        //=====================================================================
        // Test 6: Different warp - no forwarding
        //=====================================================================
        $display("\n--- Test 6: Different Warp - No Forwarding ---");
        
        operand_warp_id = 3'd1;  // Warp 1
        wb_warp_id = 3'd0;        // WB is for warp 0
        
        #1;
        
        check_result("No forwarding (diff warp)", 1'b0, fwd_rs1_from_e2m || fwd_rs1_from_m2w || fwd_rs1_from_wb);
        check_data("RS1 from RF (no match)", rf_rs1_data[0], fwd_rs1_data[0]);
        
        //=====================================================================
        // Test 7: R0 never forwarded
        //=====================================================================
        $display("\n--- Test 7: R0 Never Forwarded ---");
        
        operand_warp_id = 3'd0;
        operand_rs1 = 5'd0;  // R0
        wb_rd = 5'd0;
        wb_warp_id = 3'd0;
        
        #1;
        
        check_result("R0 not forwarded", 1'b0, fwd_rs1_from_wb);
        
        //=====================================================================
        // Test 8: Load-use hazard
        //=====================================================================
        $display("\n--- Test 8: Load-Use Hazard (Stall) ---");
        
        operand_rs1 = 5'd5;
        wb_valid = 1'b0;
        
        // E2M is a memory operation
        e2m_valid = 1'b1;
        e2m_warp_id = 3'd0;
        e2m_rd = 5'd5;
        e2m_rd_en = 1'b1;
        e2m_is_mem = 1'b1;  // This is a load
        
        #1;
        
        check_result("Load-use stall required", 1'b1, fwd_stall_required);
        check_result("No forwarding from memory op", 1'b0, fwd_rs1_from_e2m);
        
        //=====================================================================
        // Test 9: RS2 load-use hazard
        //=====================================================================
        $display("\n--- Test 9: RS2 Load-Use Hazard ---");
        
        operand_rs1 = 5'd10;
        operand_rs2 = 5'd5;
        
        #1;
        
        check_result("RS2 load-use stall", 1'b1, fwd_stall_required);
        
        //=====================================================================
        // Test 10: Partial mask forwarding
        //=====================================================================
        $display("\n--- Test 10: Partial Mask Forwarding ---");
        
        e2m_is_mem = 1'b0;
        e2m_rd = 5'd10;
        e2m_mask = 8'b10101010;  // Only even threads
        
        operand_rs1 = 5'd10;
        
        // Set distinctive RF data
        for (int i = 0; i < WARP_SIZE; i++) rf_rs1_data[i] = 64'h0F00_DA7A_0000_0000 | i;
        for (int i = 0; i < WARP_SIZE; i++) e2m_result[i] = 64'hE200_0E00_0000_0000 | i;
        
        #1;
        
        check_result("RS1 forwarded from E2M", 1'b1, fwd_rs1_from_e2m);
        // Thread 0: mask=0, use RF
        check_data("Thread 0 from RF (mask=0)", rf_rs1_data[0], fwd_rs1_data[0]);
        // Thread 1: mask=1, use E2M
        check_data("Thread 1 from E2M (mask=1)", e2m_result[1], fwd_rs1_data[1]);
        // Thread 2: mask=0, use RF
        check_data("Thread 2 from RF (mask=0)", rf_rs1_data[2], fwd_rs1_data[2]);
        
        //=====================================================================
        // Test 11: RS1 disabled - no forwarding needed
        //=====================================================================
        $display("\n--- Test 11: RS1 Disabled ---");
        
        operand_rs1_en = 1'b0;
        
        #1;
        
        check_result("RS1 disabled - no fwd", 1'b0, fwd_rs1_from_e2m);
        
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
            $display("\n*** ALL FORWARDING TESTS PASSED ***\n");
        end else begin
            $display("\n*** SOME TESTS FAILED ***\n");
        end
        
        $finish;
    end

endmodule
