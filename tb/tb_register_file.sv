//=============================================================================
// GPGPU-1 Register File Testbench
//=============================================================================
// File:        tb_register_file.sv
// Description: Testbench for the register file modules including GPR,
//              predicate, and special register files.
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_register_file;
    import gpgpu_pkg::*;

    //=========================================================================
    // Parameters
    //=========================================================================
    
    localparam int NUM_WARPS = 4;
    localparam int CORE_ID = 2;
    localparam int CLK_PERIOD = 10;
    
    //=========================================================================
    // Signals
    //=========================================================================
    
    logic clk;
    logic rst_n;
    
    // Warp selection
    logic [WARP_ID_WIDTH-1:0] rd_warp_id;
    
    // GPR ports
    logic [REG_ADDR_WIDTH-1:0] rs1_addr;
    logic [REG_ADDR_WIDTH-1:0] rs2_addr;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rs1_data;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rs2_data;
    
    logic gpr_wr_en;
    logic [WARP_ID_WIDTH-1:0] gpr_wr_warp_id;
    logic [WARP_SIZE-1:0] gpr_wr_mask;
    logic [REG_ADDR_WIDTH-1:0] gpr_wr_addr;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] gpr_wr_data;
    
    // Predicate ports
    logic [PRED_ADDR_WIDTH-1:0] pred_addr;
    logic [PRED_ADDR_WIDTH-1:0] pred2_addr;
    logic [WARP_SIZE-1:0] pred_data;
    logic [WARP_SIZE-1:0] pred2_data;
    
    logic pred_wr_en;
    logic [WARP_ID_WIDTH-1:0] pred_wr_warp_id;
    logic [WARP_SIZE-1:0] pred_wr_mask;
    logic [PRED_ADDR_WIDTH-1:0] pred_wr_addr;
    logic [WARP_SIZE-1:0] pred_wr_data;
    
    // Special register ports
    logic [3:0] sr_addr;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] sr_data;
    
    // Block configuration
    block_config_t block_config;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    
    register_file_unit #(
        .NUM_WARPS(NUM_WARPS),
        .CORE_ID(CORE_ID)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .rd_warp_id     (rd_warp_id),
        .rs1_addr       (rs1_addr),
        .rs2_addr       (rs2_addr),
        .rs1_data       (rs1_data),
        .rs2_data       (rs2_data),
        .gpr_wr_en      (gpr_wr_en),
        .gpr_wr_warp_id (gpr_wr_warp_id),
        .gpr_wr_mask    (gpr_wr_mask),
        .gpr_wr_addr    (gpr_wr_addr),
        .gpr_wr_data    (gpr_wr_data),
        .pred_addr      (pred_addr),
        .pred2_addr     (pred2_addr),
        .pred_data      (pred_data),
        .pred2_data     (pred2_data),
        .pred_wr_en     (pred_wr_en),
        .pred_wr_warp_id(pred_wr_warp_id),
        .pred_wr_mask   (pred_wr_mask),
        .pred_wr_addr   (pred_wr_addr),
        .pred_wr_data   (pred_wr_data),
        .sr_addr        (sr_addr),
        .sr_data        (sr_data),
        .block_config   (block_config)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk <= ~clk;
      //=========================================================================
    // Test Counters
    //=========================================================================
    
    int tests_passed = 0;
    int tests_failed = 0;
    integer t;  // Loop variable for SIMT operations
    
    //=========================================================================
    // Helper Tasks
    //=========================================================================
    
    task automatic reset_dut();
        rst_n = 0;
        rd_warp_id = 0;
        rs1_addr = 0;
        rs2_addr = 0;
        gpr_wr_en = 0;
        gpr_wr_warp_id = 0;
        gpr_wr_mask = 0;
        gpr_wr_addr = 0;
        gpr_wr_data = '{default: '0};
        pred_addr = 0;
        pred2_addr = 0;
        pred_wr_en = 0;
        pred_wr_warp_id = 0;
        pred_wr_mask = 0;
        pred_wr_addr = 0;
        pred_wr_data = 0;
        sr_addr = 0;
        block_config = '{default: '0};
        
        repeat(5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask    task automatic write_gpr(
        input logic [WARP_ID_WIDTH-1:0] warp,
        input logic [REG_ADDR_WIDTH-1:0] reg_addr,
        input logic [WARP_SIZE-1:0] mask,
        input logic [DATA_WIDTH-1:0] base_value
    );
        integer i;
        gpr_wr_en = 1;
        gpr_wr_warp_id = warp;
        gpr_wr_addr = reg_addr;
        gpr_wr_mask = mask;
        for (i = 0; i < WARP_SIZE; i = i + 1) begin
            gpr_wr_data[i] = base_value + i;  // Each thread gets unique value
        end
        #1;  // Allow signals to settle
        @(posedge clk);
        #1;  // Wait after clock edge for write to complete
        gpr_wr_en = 0;
    endtask
    
    task automatic read_gpr(
        input logic [WARP_ID_WIDTH-1:0] warp,
        input logic [REG_ADDR_WIDTH-1:0] addr1,
        input logic [REG_ADDR_WIDTH-1:0] addr2
    );
        rd_warp_id = warp;
        rs1_addr = addr1;
        rs2_addr = addr2;
        @(posedge clk);  // Wait for read
    endtask
    
    task automatic check_result(
        input string test_name,
        input logic condition
    );
        if (condition) begin
            $display("[PASS] %s", test_name);
            tests_passed++;
        end else begin
            $display("[FAIL] %s", test_name);
            tests_failed++;
        end
    endtask
    
    //=========================================================================
    // Test Cases
    //=========================================================================
      initial begin
        // Local variables for tests
        logic all_zero;
        logic match;
        logic [63:0] clock_val1;
        logic [63:0] clock_val2;
        
        $display("============================================================");
        $display("GPGPU-1 Register File Testbench");
        $display("============================================================\n");
        
        reset_dut();
        
        //---------------------------------------------------------------------
        // Test 1: R0 reads as zero
        //---------------------------------------------------------------------
        $display("Test 1: R0 reads as zero");
        read_gpr(0, 5'd0, 5'd0);
        #1;
        all_zero = 1;
        for (t = 0; t < WARP_SIZE; t = t + 1) begin
            if (rs1_data[t] != 0 || rs2_data[t] != 0) all_zero = 0;
        end
        check_result("R0 reads zero", all_zero);
        
        //---------------------------------------------------------------------
        // Test 2: Write and read back R5 in Warp 0
        //---------------------------------------------------------------------
        $display("\nTest 2: Write and read R5 in Warp 0");
        write_gpr(2'd0, 5'd5, 8'hFF, 64'h1000);  // All threads, base 0x1000
        read_gpr(2'd0, 5'd5, 5'd0);
        #1;
        match = 1;
        for (t = 0; t < WARP_SIZE; t = t + 1) begin
            if (rs1_data[t] != (64'h1000 + t)) begin
                $display("  Thread %0d: Expected 0x%016h, Got 0x%016h", 
                         t, 64'h1000 + t, rs1_data[t]);
                match = 0;
            end
        end
        check_result("R5 write/read in Warp 0", match);
        
        //---------------------------------------------------------------------
        // Test 3: Write to R0 should be ignored
        //---------------------------------------------------------------------
        $display("\nTest 3: Write to R0 is ignored");
        write_gpr(2'd0, 5'd0, 8'hFF, 64'hDEAD);
        read_gpr(2'd0, 5'd0, 5'd0);
        #1;
        all_zero = 1;
        for (t = 0; t < WARP_SIZE; t = t + 1) begin
            if (rs1_data[t] != 0) all_zero = 0;
        end
        check_result("R0 still zero after write", all_zero);
        
        //---------------------------------------------------------------------
        // Test 4: Masked write (only threads 0,2,4,6)
        //---------------------------------------------------------------------
        $display("\nTest 4: Masked write to R10");
        write_gpr(2'd1, 5'd10, 8'b01010101, 64'h2000);  // Even threads only
        read_gpr(2'd1, 5'd10, 5'd0);
        #1;
        match = 1;
        for (t = 0; t < WARP_SIZE; t = t + 1) begin
            if (t % 2 == 0) begin
                // Even threads should have written value
                if (rs1_data[t] != (64'h2000 + t)) match = 0;
            end else begin
                // Odd threads should be zero (from reset)
                if (rs1_data[t] != 0) match = 0;
            end
        end        check_result("Masked write to R10", match);
        
        //---------------------------------------------------------------------
        // Test 5: Warp isolation (write to Warp 2, read from Warp 0)
        //---------------------------------------------------------------------
        $display("\nTest 5: Warp isolation");
        write_gpr(2'd2, 5'd15, 8'hFF, 64'h3000);  // Write to Warp 2
        read_gpr(2'd0, 5'd15, 5'd0);               // Read from Warp 0
        #1;
        all_zero = 1;
        for (t = 0; t < WARP_SIZE; t = t + 1) begin
            if (rs1_data[t] != 0) all_zero = 0;
        end
        check_result("Warp 0 R15 still zero", all_zero);
        
        // Verify Warp 2 has the data
        read_gpr(2'd2, 5'd15, 5'd0);
        #1;
        match = 1;
        for (t = 0; t < WARP_SIZE; t = t + 1) begin
            if (rs1_data[t] != (64'h3000 + t)) match = 0;
        end
        check_result("Warp 2 R15 has written data", match);
        
        //---------------------------------------------------------------------
        // Test 6: Two simultaneous reads
        //---------------------------------------------------------------------        $display("\nTest 6: Dual port read");
        write_gpr(2'd0, 5'd20, 8'hFF, 64'h4000);
        write_gpr(2'd0, 5'd21, 8'hFF, 64'h5000);
        read_gpr(2'd0, 5'd20, 5'd21);
        #1;
        match = 1;
        for (t = 0; t < WARP_SIZE; t = t + 1) begin
            if (rs1_data[t] != (64'h4000 + t)) match = 0;
            if (rs2_data[t] != (64'h5000 + t)) match = 0;
        end
        check_result("Dual read port 1 (R20)", match);
        match = 1;
        for (t = 0; t < WARP_SIZE; t = t + 1) begin
            if (rs2_data[t] != (64'h5000 + t)) match = 0;
        end
        check_result("Dual read port 2 (R21)", match);
        
        //---------------------------------------------------------------------
        // Test 7: Predicate P0 always true
        //---------------------------------------------------------------------
        $display("\nTest 7: Predicate P0 always true");
        pred_addr = 3'd0;
        rd_warp_id = 0;
        @(posedge clk);
        #1;
        check_result("P0 all true", pred_data == 8'hFF);
          //---------------------------------------------------------------------
        // Test 8: Write and read predicate P3
        //---------------------------------------------------------------------
        $display("\nTest 8: Write predicate P3");
        pred_wr_en = 1;
        pred_wr_warp_id = 0;
        pred_wr_addr = 3'd3;
        pred_wr_mask = 8'hFF;
        pred_wr_data = 8'b10101010;  // Alternating pattern
        #1;  // Allow signals to settle
        @(posedge clk);
        #1;  // Wait after clock edge for write to complete
        pred_wr_en = 0;
        
        pred_addr = 3'd3;
        rd_warp_id = 0;
        @(posedge clk);
        #1;
        check_result("P3 write/read", pred_data == 8'b10101010);
        
        //---------------------------------------------------------------------
        // Test 9: Write to P0 ignored
        //---------------------------------------------------------------------
        $display("\nTest 9: Write to P0 ignored");
        pred_wr_en = 1;
        pred_wr_warp_id = 0;
        pred_wr_addr = 3'd0;
        pred_wr_mask = 8'hFF;
        pred_wr_data = 8'b00000000;
        @(posedge clk);
        pred_wr_en = 0;
        
        pred_addr = 3'd0;
        @(posedge clk);
        #1;
        check_result("P0 still all true", pred_data == 8'hFF);
        
        //---------------------------------------------------------------------
        // Test 10: Special register SR_TID
        //---------------------------------------------------------------------        $display("\nTest 10: Special register SR_TID");
        sr_addr = SR_TID;
        rd_warp_id = 0;
        @(posedge clk);
        #1;
        match = 1;
        for (t = 0; t < WARP_SIZE; t = t + 1) begin
            if (sr_data[t] != t) begin
                $display("  Thread %0d: TID = %0d (expected %0d)", t, sr_data[t], t);
                match = 0;
            end
        end
        check_result("SR_TID returns correct thread IDs", match);
        
        //---------------------------------------------------------------------
        // Test 11: Special register SR_WID
        //---------------------------------------------------------------------        $display("\nTest 11: Special register SR_WID");
        sr_addr = SR_WID;
        rd_warp_id = 2'd3;
        @(posedge clk);
        #1;
        match = 1;
        for (t = 0; t < WARP_SIZE; t = t + 1) begin
            if (sr_data[t] != 3) match = 0;
        end
        check_result("SR_WID returns warp ID 3", match);
        
        //---------------------------------------------------------------------
        // Test 12: Special register SR_CID
        //---------------------------------------------------------------------        $display("\nTest 12: Special register SR_CID");
        sr_addr = SR_CID;
        @(posedge clk);
        #1;
        match = 1;
        for (t = 0; t < WARP_SIZE; t = t + 1) begin
            if (sr_data[t] != CORE_ID) match = 0;
        end
        check_result("SR_CID returns core ID", match);
        
        //---------------------------------------------------------------------
        // Test 13: Block configuration registers
        //---------------------------------------------------------------------
        $display("\nTest 13: Block configuration registers");
        block_config.block_id_x = 64'd5;
        block_config.block_id_y = 64'd3;
        block_config.block_id_z = 64'd1;
        block_config.num_threads = 64'd256;
        block_config.num_blocks_x = 64'd10;
        block_config.num_blocks_y = 64'd8;
        block_config.num_blocks_z = 64'd4;
        
        sr_addr = SR_BID_X;
        @(posedge clk);
        #1;
        check_result("SR_BID_X = 5", sr_data[0] == 64'd5);
        
        sr_addr = SR_BID_Y;
        @(posedge clk);
        #1;
        check_result("SR_BID_Y = 3", sr_data[0] == 64'd3);
        
        sr_addr = SR_NTID;
        @(posedge clk);
        #1;
        check_result("SR_NTID = 256", sr_data[0] == 64'd256);
        
        //---------------------------------------------------------------------
        // Test 14: Clock counter increments
        //---------------------------------------------------------------------
        $display("\nTest 14: Clock counter increments");
        sr_addr = SR_CLOCK;
        @(posedge clk);
        #1;
        clock_val1 = sr_data[0];
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1;
        clock_val2 = sr_data[0];
        check_result("Clock counter incremented", clock_val2 > clock_val1);
        $display("  Clock: %0d -> %0d", clock_val1, clock_val2);
        
        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        $display("\n============================================================");
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
