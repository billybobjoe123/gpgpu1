//=============================================================================
// GPGPU-1 Atomic Operations Testbench
//=============================================================================
// File:        tb_atomic.sv
// Description: Tests atomic memory operations in the LSU
// Version:     1.0
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_atomic;
    import gpgpu_pkg::*;
    
    //=========================================================================
    // Parameters
    //=========================================================================
    
    parameter CLK_PERIOD = 10;
    parameter int NUM_THREADS = WARP_SIZE;
    parameter int SHARED_MEM_ADDR_WIDTH = 14;
    
    //=========================================================================
    // Signals
    //=========================================================================
    
    logic clk;
    logic rst_n;
    
    // Request interface
    logic                                      req_valid;
    logic [WARP_ID_WIDTH-1:0]                  req_warp_id;
    logic [NUM_THREADS-1:0]                    req_active_mask;
    logic [NUM_THREADS-1:0]                    req_pred_mask;
    opcode_t                                   req_opcode;
    logic [7:0]                                req_func;
    logic [REG_ADDR_WIDTH-1:0]                 req_rd;
    logic [NUM_THREADS-1:0][ADDR_WIDTH-1:0]    req_base_addr;
    logic signed [12:0]                        req_offset;
    logic [NUM_THREADS-1:0][DATA_WIDTH-1:0]    req_store_data;
    logic                                      req_ready;
    
    // Response interface
    logic                                      resp_valid;
    logic [WARP_ID_WIDTH-1:0]                  resp_warp_id;
    logic [REG_ADDR_WIDTH-1:0]                 resp_rd;
    logic [NUM_THREADS-1:0]                    resp_mask;
    logic [NUM_THREADS-1:0][DATA_WIDTH-1:0]    resp_data;
    logic                                      resp_ready;
    
    // Global memory interface
    logic                                      gmem_req_valid;
    logic                                      gmem_req_we;
    logic [ADDR_WIDTH-1:0]                     gmem_req_addr;
    logic [DATA_WIDTH-1:0]                     gmem_req_wdata;
    logic [7:0]                                gmem_req_wstrb;
    logic                                      gmem_req_ready;
    logic                                      gmem_resp_valid;
    logic [DATA_WIDTH-1:0]                     gmem_resp_rdata;
    logic                                      gmem_store_complete;
    
    // Shared memory interface (not used in atomic tests)
    logic                                      smem_req_valid;
    logic                                      smem_req_we;
    logic [NUM_THREADS-1:0]                    smem_req_mask;
    logic [NUM_THREADS-1:0][SHARED_MEM_ADDR_WIDTH-1:0] smem_req_addr;
    logic [NUM_THREADS-1:0][DATA_WIDTH-1:0]    smem_req_wdata;
    logic [NUM_THREADS-1:0][7:0]               smem_req_wstrb;
    logic                                      smem_req_ready;
    logic                                      smem_resp_valid;
    logic [NUM_THREADS-1:0][DATA_WIDTH-1:0]    smem_resp_rdata;
    
    //=========================================================================
    // Test Variables
    //=========================================================================
    
    int test_count;
    int pass_count;
    int fail_count;
    
    // Simple memory model
    logic [DATA_WIDTH-1:0] global_mem [0:1023];
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    
    lsu #(
        .NUM_THREADS(NUM_THREADS),
        .SHARED_MEM_ADDR_WIDTH(SHARED_MEM_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(req_valid),
        .req_warp_id(req_warp_id),
        .req_active_mask(req_active_mask),
        .req_pred_mask(req_pred_mask),
        .req_opcode(req_opcode),
        .req_func(req_func),
        .req_rd(req_rd),
        .req_base_addr(req_base_addr),
        .req_offset(req_offset),
        .req_store_data(req_store_data),
        .req_ready(req_ready),
        .resp_valid(resp_valid),
        .resp_warp_id(resp_warp_id),
        .resp_rd(resp_rd),
        .resp_mask(resp_mask),
        .resp_data(resp_data),
        .resp_ready(resp_ready),
        .gmem_req_valid(gmem_req_valid),
        .gmem_req_we(gmem_req_we),
        .gmem_req_addr(gmem_req_addr),
        .gmem_req_wdata(gmem_req_wdata),
        .gmem_req_wstrb(gmem_req_wstrb),
        .gmem_req_ready(gmem_req_ready),
        .gmem_resp_valid(gmem_resp_valid),
        .gmem_resp_rdata(gmem_resp_rdata),
        .gmem_store_complete(gmem_store_complete),
        .smem_req_valid(smem_req_valid),
        .smem_req_we(smem_req_we),
        .smem_req_mask(smem_req_mask),
        .smem_req_addr(smem_req_addr),
        .smem_req_wdata(smem_req_wdata),
        .smem_req_wstrb(smem_req_wstrb),
        .smem_req_ready(smem_req_ready),
        .smem_resp_valid(smem_resp_valid),
        .smem_resp_rdata(smem_resp_rdata)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // Global Memory Model with RMW support
    //=========================================================================
    
    // Memory state machine for atomic RMW
    logic gmem_pending;
    logic [ADDR_WIDTH-1:0] gmem_pending_addr;
    logic gmem_pending_we;
    logic [DATA_WIDTH-1:0] gmem_pending_wdata;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gmem_resp_valid     <= 1'b0;
            gmem_resp_rdata     <= '0;
            gmem_store_complete <= 1'b0;
            gmem_pending        <= 1'b0;
        end else begin
            gmem_resp_valid     <= 1'b0;
            gmem_store_complete <= 1'b0;
            
            if (gmem_req_valid && gmem_req_ready) begin
                gmem_pending       <= 1'b1;
                gmem_pending_addr  <= gmem_req_addr;
                gmem_pending_we    <= gmem_req_we;
                gmem_pending_wdata <= gmem_req_wdata;
            end
            
            if (gmem_pending) begin
                gmem_pending <= 1'b0;
                
                if (gmem_pending_we) begin
                    // Write
                    global_mem[gmem_pending_addr[12:3]] <= gmem_pending_wdata;
                    gmem_store_complete <= 1'b1;
                end else begin
                    // Read
                    gmem_resp_rdata <= global_mem[gmem_pending_addr[12:3]];
                    gmem_resp_valid <= 1'b1;
                end
            end
        end
    end
    
    assign gmem_req_ready = !gmem_pending;
    
    // Shared memory not used - tie off
    assign smem_req_ready = 1'b1;
    assign smem_resp_valid = 1'b0;
    assign smem_resp_rdata = '0;
    
    //=========================================================================
    // Test Tasks
    //=========================================================================
    
    task automatic reset_dut();
        begin
            rst_n = 0;
            req_valid = 0;
            req_warp_id = 0;
            req_active_mask = '0;
            req_pred_mask = '1;
            req_opcode = OP_ATOM;
            req_func = 8'h0;
            req_rd = 0;
            req_base_addr = '0;
            req_offset = 0;
            req_store_data = '0;
            resp_ready = 1;
            
            // Initialize memory with known values
            for (int i = 0; i < 1024; i++) begin
                global_mem[i] = 64'h0000_0000_0000_0000 + (i * 8);
            end
            
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
        end
    endtask
    
    task automatic wait_for_response(output logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] result);
        begin
            int timeout = 100;
            while (!resp_valid && timeout > 0) begin
                @(posedge clk);
                timeout--;
            end
            if (timeout == 0) begin
                $display("[ERROR] Timeout waiting for response");
            end
            result = resp_data;
            @(posedge clk);
        end
    endtask
    
    task automatic check_result(
        string test_name,
        logic [DATA_WIDTH-1:0] expected,
        logic [DATA_WIDTH-1:0] actual
    );
        begin
            test_count++;
            if (expected == actual) begin
                pass_count++;
                $display("[PASS] %s", test_name);
            end else begin
                fail_count++;
                $display("[FAIL] %s: expected 0x%016x, got 0x%016x", test_name, expected, actual);
            end
        end
    endtask
    
    //=========================================================================
    // Test result variables
    //=========================================================================
    
    logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] result;
    logic [DATA_WIDTH-1:0] mem_value;
    
    //=========================================================================
    // Test Cases
    //=========================================================================
    
    initial begin
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        $display("==============================================");
        $display("GPGPU-1 Atomic Operations Testbench");
        $display("==============================================");
        
        reset_dut();
        
        //---------------------------------------------------------------------
        // Test 1: ATOM.ADD - Atomic Add
        //---------------------------------------------------------------------
        $display("\n--- Test: ATOM.ADD ---");
        
        // Set initial memory value
        global_mem[0] = 64'h0000_0000_0000_0064;  // 100
        
        // Issue atomic add: mem[0] += 50, return old value
        @(posedge clk);
        req_valid = 1;
        req_opcode = OP_ATOM;
        req_func = 8'h0;  // ATOM_ADD
        req_rd = 1;
        req_active_mask = 8'b00000001;  // Only thread 0
        req_base_addr[0] = 64'h0;  // Address 0
        req_store_data[0] = 64'h32;  // Add 50
        
        @(posedge clk);
        req_valid = 0;
        
        wait_for_response(result);
        
        // Old value should be returned
        check_result("ATOM.ADD returns old value", 64'h64, result[0]);
        
        // Memory should have new value
        mem_value = global_mem[0];
        check_result("ATOM.ADD updates memory", 64'h96, mem_value);  // 100 + 50 = 150
        
        //---------------------------------------------------------------------
        // Test 2: ATOM.MIN - Atomic Signed Minimum
        //---------------------------------------------------------------------
        $display("\n--- Test: ATOM.MIN (signed) ---");
        
        // Set initial memory value
        global_mem[1] = 64'h0000_0000_0000_00C8;  // 200
        
        @(posedge clk);
        req_valid = 1;
        req_opcode = OP_ATOM;
        req_func = 8'h1;  // ATOM_MIN
        req_rd = 2;
        req_active_mask = 8'b00000001;
        req_base_addr[0] = 64'h8;  // Address 8 (word 1)
        req_store_data[0] = 64'h64;  // Compare with 100
        
        @(posedge clk);
        req_valid = 0;
        
        wait_for_response(result);
        
        check_result("ATOM.MIN returns old value", 64'hC8, result[0]);
        
        mem_value = global_mem[1];
        check_result("ATOM.MIN updates to smaller value", 64'h64, mem_value);
        
        //---------------------------------------------------------------------
        // Test 3: ATOM.MAX - Atomic Signed Maximum
        //---------------------------------------------------------------------
        $display("\n--- Test: ATOM.MAX (signed) ---");
        
        global_mem[2] = 64'h0000_0000_0000_0064;  // 100
        
        @(posedge clk);
        req_valid = 1;
        req_opcode = OP_ATOM;
        req_func = 8'h2;  // ATOM_MAX
        req_rd = 3;
        req_active_mask = 8'b00000001;
        req_base_addr[0] = 64'h10;  // Address 16 (word 2)
        req_store_data[0] = 64'hC8;  // Compare with 200
        
        @(posedge clk);
        req_valid = 0;
        
        wait_for_response(result);
        
        check_result("ATOM.MAX returns old value", 64'h64, result[0]);
        
        mem_value = global_mem[2];
        check_result("ATOM.MAX updates to larger value", 64'hC8, mem_value);
        
        //---------------------------------------------------------------------
        // Test 4: ATOM.AND - Atomic Bitwise AND (32-bit)
        //---------------------------------------------------------------------
        $display("\n--- Test: ATOM.AND (32-bit) ---");
        
        global_mem[3] = 64'h0000_0000_FF00_FF00;  // 32-bit value
        
        @(posedge clk);
        req_valid = 1;
        req_opcode = OP_ATOM;
        req_func = 8'h5;  // ATOM_AND
        req_rd = 4;
        req_active_mask = 8'b00000001;
        req_base_addr[0] = 64'h18;
        req_store_data[0] = 64'h0F0F_0F0F;
        
        @(posedge clk);
        req_valid = 0;
        
        wait_for_response(result);
        
        check_result("ATOM.AND returns old value", 64'hFF00_FF00, result[0]);
        
        mem_value = global_mem[3];
        check_result("ATOM.AND computes correctly", 64'h0F00_0F00, mem_value);
        
        //---------------------------------------------------------------------
        // Test 5: ATOM.OR - Atomic Bitwise OR (32-bit)
        //---------------------------------------------------------------------
        $display("\n--- Test: ATOM.OR (32-bit) ---");
        
        global_mem[4] = 64'h0000_0000_F000_F000;  // 32-bit value
        
        @(posedge clk);
        req_valid = 1;
        req_opcode = OP_ATOM;
        req_func = 8'h6;  // ATOM_OR
        req_rd = 5;
        req_active_mask = 8'b00000001;
        req_base_addr[0] = 64'h20;
        req_store_data[0] = 64'h0F00_0F00;
        
        @(posedge clk);
        req_valid = 0;
        
        wait_for_response(result);
        
        check_result("ATOM.OR returns old value", 64'hF000_F000, result[0]);
        
        mem_value = global_mem[4];
        check_result("ATOM.OR computes correctly", 64'hFF00_FF00, mem_value);
        
        //---------------------------------------------------------------------
        // Test 6: ATOM.XOR - Atomic Bitwise XOR (32-bit)
        //---------------------------------------------------------------------
        $display("\n--- Test: ATOM.XOR (32-bit) ---");
        
        global_mem[5] = 64'h0000_0000_AAAA_AAAA;  // 32-bit value
        
        @(posedge clk);
        req_valid = 1;
        req_opcode = OP_ATOM;
        req_func = 8'h7;  // ATOM_XOR
        req_rd = 6;
        req_active_mask = 8'b00000001;
        req_base_addr[0] = 64'h28;
        req_store_data[0] = 64'hFFFF_FFFF;
        
        @(posedge clk);
        req_valid = 0;
        
        wait_for_response(result);
        
        check_result("ATOM.XOR returns old value", 64'hAAAA_AAAA, result[0]);
        
        mem_value = global_mem[5];
        check_result("ATOM.XOR computes correctly", 64'h5555_5555, mem_value);
        
        //---------------------------------------------------------------------
        // Test 7: ATOM.EXCH - Atomic Exchange (32-bit)
        //---------------------------------------------------------------------
        $display("\n--- Test: ATOM.EXCH (32-bit) ---");
        
        global_mem[6] = 64'h0000_0000_CAFE_BABE;  // 32-bit value
        
        @(posedge clk);
        req_valid = 1;
        req_opcode = OP_ATOM;
        req_func = 8'h8;  // ATOM_EXCH
        req_rd = 7;
        req_active_mask = 8'b00000001;
        req_base_addr[0] = 64'h30;
        req_store_data[0] = 64'h9ABC_DEF0;
        
        @(posedge clk);
        req_valid = 0;
        
        wait_for_response(result);
        
        check_result("ATOM.EXCH returns old value", 64'hCAFE_BABE, result[0]);
        
        mem_value = global_mem[6];
        check_result("ATOM.EXCH writes new value", 64'h9ABC_DEF0, mem_value);
        
        //---------------------------------------------------------------------
        // Test 8: Multiple threads with ATOM.ADD
        //---------------------------------------------------------------------
        $display("\n--- Test: Multi-thread ATOM.ADD ---");
        
        // Initialize 8 memory locations
        for (int i = 0; i < 8; i++) begin
            global_mem[10+i] = 64'h100 + i;
        end
        
        @(posedge clk);
        req_valid = 1;
        req_opcode = OP_ATOM;
        req_func = 8'h0;  // ATOM_ADD
        req_rd = 8;
        req_active_mask = 8'b11111111;  // All 8 threads
        for (int t = 0; t < 8; t++) begin
            req_base_addr[t] = 64'h50 + (t * 8);  // Each thread different address
            req_store_data[t] = 64'h10 * (t + 1);  // Add different values
        end
        
        @(posedge clk);
        req_valid = 0;
        
        wait_for_response(result);
        
        // Check each thread got correct old value
        for (int t = 0; t < 8; t++) begin
            check_result($sformatf("Thread %0d ATOM.ADD old value", t), 
                        64'h100 + t, result[t]);
        end
        
        // Check memory updates
        for (int t = 0; t < 8; t++) begin
            mem_value = global_mem[10+t];
            check_result($sformatf("Thread %0d ATOM.ADD new mem value", t),
                        64'h100 + t + (64'h10 * (t + 1)), mem_value);
        end
        
        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        $display("\n==============================================");
        $display("Test Summary");
        $display("==============================================");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("==============================================");
        
        if (fail_count == 0) begin
            $display("\n*** ALL ATOMIC TESTS PASSED ***\n");
        end else begin
            $display("\n*** SOME TESTS FAILED ***\n");
        end
        
        $finish;
    end
    
    //=========================================================================
    // Timeout
    //=========================================================================
    
    initial begin
        #50000;
        $display("[ERROR] Simulation timeout");
        $finish;
    end

endmodule
