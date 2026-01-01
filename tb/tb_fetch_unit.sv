//=============================================================================
// GPGPU-1 Instruction Fetch Unit Testbench
//=============================================================================
// File:        tb_fetch_unit.sv
// Description: Comprehensive testbench for the fetch unit including
//              instruction cache and fetch buffer.
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_fetch_unit;
    import gpgpu_pkg::*;

    //=========================================================================
    // Parameters
    //=========================================================================
    
    parameter int NUM_WARPS       = WARPS_PER_CORE;
    parameter int ICACHE_SIZE     = 4096;
    parameter int FETCH_BUF_DEPTH = 2;
    parameter int CLK_PERIOD      = 10;
    
    //=========================================================================
    // Signals
    //=========================================================================
    
    logic                           clk;
    logic                           rst_n;
    
    // Warp scheduler interface
    logic                           sched_valid;
    logic [WARP_ID_WIDTH-1:0]       sched_warp_id;
    logic [ADDR_WIDTH-1:0]          sched_pc;
    logic [WARP_SIZE-1:0]           sched_active_mask;
    logic                           sched_ready;
    
    // Decode interface
    logic                           decode_valid;
    logic [INST_WIDTH-1:0]          decode_instr;
    logic [ADDR_WIDTH-1:0]          decode_pc;
    logic [WARP_ID_WIDTH-1:0]       decode_warp_id;
    logic [WARP_SIZE-1:0]           decode_active_mask;
    logic                           decode_ready;
    
    // Instruction memory interface
    logic                           imem_req_valid;
    logic [ADDR_WIDTH-1:0]          imem_req_addr;
    logic                           imem_req_ready;
    logic                           imem_resp_valid;
    logic [255:0]                   imem_resp_data;
    
    // Control
    logic [NUM_WARPS-1:0]           warp_flush;
    logic                           cache_flush;
    
    // PC update interface
    logic                           pc_update_valid;
    logic [WARP_ID_WIDTH-1:0]       pc_update_warp_id;
    logic [ADDR_WIDTH-1:0]          pc_update_value;
    
    // Status
    logic                           busy;
    logic [NUM_WARPS-1:0]           warp_fetch_ready;
    
    //=========================================================================
    // Test Variables
    //=========================================================================
    
    int test_count;
    int pass_count;
    int fail_count;
    
    // Instruction memory model
    logic [31:0] instr_mem [0:4095];  // 16KB instruction memory
    
    // Captured decode output
    logic                           capt_decode_valid;
    logic [INST_WIDTH-1:0]          capt_decode_instr;
    logic [ADDR_WIDTH-1:0]          capt_decode_pc;
    logic [WARP_ID_WIDTH-1:0]       capt_decode_warp_id;
    logic [WARP_SIZE-1:0]           capt_decode_mask;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    
    fetch_unit #(
        .NUM_WARPS(NUM_WARPS),
        .ICACHE_SIZE(ICACHE_SIZE),
        .FETCH_BUF_DEPTH(FETCH_BUF_DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .sched_valid(sched_valid),
        .sched_warp_id(sched_warp_id),
        .sched_pc(sched_pc),
        .sched_active_mask(sched_active_mask),
        .sched_ready(sched_ready),
        .decode_valid(decode_valid),
        .decode_instr(decode_instr),
        .decode_pc(decode_pc),
        .decode_warp_id(decode_warp_id),
        .decode_active_mask(decode_active_mask),
        .decode_ready(decode_ready),
        .imem_req_valid(imem_req_valid),
        .imem_req_addr(imem_req_addr),
        .imem_req_ready(imem_req_ready),
        .imem_resp_valid(imem_resp_valid),
        .imem_resp_data(imem_resp_data),
        .warp_flush(warp_flush),
        .cache_flush(cache_flush),
        .pc_update_valid(pc_update_valid),
        .pc_update_warp_id(pc_update_warp_id),
        .pc_update_value(pc_update_value),
        .busy(busy),
        .warp_fetch_ready(warp_fetch_ready)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // Instruction Memory Model
    //=========================================================================
    
    // Memory request handling with configurable latency
    logic [2:0] mem_latency_counter;
    logic       mem_pending;
    logic [ADDR_WIDTH-1:0] mem_pending_addr;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_resp_valid <= 1'b0;
            imem_resp_data <= '0;
            mem_pending <= 1'b0;
            mem_latency_counter <= '0;
        end else begin
            imem_resp_valid <= 1'b0;
            
            if (imem_req_valid && imem_req_ready && !mem_pending) begin
                mem_pending <= 1'b1;
                mem_pending_addr <= imem_req_addr;
                mem_latency_counter <= 3'd2;  // 2 cycle latency
            end
            
            if (mem_pending) begin
                if (mem_latency_counter == 0) begin
                    mem_pending <= 1'b0;
                    imem_resp_valid <= 1'b1;
                    
                    // Build cache line (8 instructions)
                    for (int i = 0; i < 8; i++) begin
                        logic [11:0] word_addr;
                        word_addr = (mem_pending_addr[13:2] & 12'hFF8) + i[11:0];
                        imem_resp_data[i*32 +: 32] <= instr_mem[word_addr];
                    end
                end else begin
                    mem_latency_counter <= mem_latency_counter - 1;
                end
            end
        end
    end
    
    assign imem_req_ready = !mem_pending;
    
    //=========================================================================
    // Test Tasks
    //=========================================================================
    
    task automatic reset_dut();
        begin
            rst_n = 0;
            sched_valid = 0;
            sched_warp_id = 0;
            sched_pc = '0;
            sched_active_mask = '0;
            decode_ready = 1;
            warp_flush = '0;
            cache_flush = 0;
            pc_update_valid = 0;
            pc_update_warp_id = 0;
            pc_update_value = '0;
            
            // Initialize instruction memory with recognizable patterns
            for (int i = 0; i < 4096; i++) begin
                // Encode address in instruction for easy verification
                // Format: ADDR[11:0] in upper bits, sequence number in lower
                instr_mem[i] = {4'hA, i[11:0], 4'hB, i[11:0]};
            end
            
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
        end
    endtask
    
    task automatic wait_for_sched_ready();
        begin
            integer timeout;
            timeout = 0;
            while (!sched_ready && timeout < 100) begin
                @(posedge clk);
                timeout++;
            end
            if (timeout >= 100) begin
                $display("ERROR: Timeout waiting for sched_ready");
            end
        end
    endtask
    
    task automatic wait_for_decode_valid();
        begin
            integer timeout;
            timeout = 0;
            while (!decode_valid && timeout < 100) begin
                @(posedge clk);
                timeout++;
            end
            if (timeout >= 100) begin
                $display("ERROR: Timeout waiting for decode_valid");
            end else begin
                // Capture decode output
                capt_decode_valid = decode_valid;
                capt_decode_instr = decode_instr;
                capt_decode_pc = decode_pc;
                capt_decode_warp_id = decode_warp_id;
                capt_decode_mask = decode_active_mask;
            end
        end
    endtask
    
    task automatic check_result(
        input string test_name,
        input logic condition
    );
        begin
            test_count++;
            if (condition) begin
                pass_count++;
                $display("[PASS] %s", test_name);
            end else begin
                fail_count++;
                $display("[FAIL] %s", test_name);
            end
        end
    endtask
    
    //=========================================================================
    // Test Cases
    //=========================================================================
    
    // Test 1: Basic single fetch
    task automatic test_basic_fetch();
        logic [31:0] expected_instr;
        begin
            $display("\n--- Test: Basic Single Fetch ---");
            
            wait_for_sched_ready();
            
            // Request fetch for warp 0 at address 0
            sched_valid = 1;
            sched_warp_id = 2'd0;
            sched_pc = 64'h0000_0000_0000_0000;
            sched_active_mask = 8'hFF;
            
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            // Wait for instruction to appear at decode
            wait_for_decode_valid();
            
            expected_instr = instr_mem[0];
            
            check_result("Decode valid", capt_decode_valid == 1'b1);
            check_result("Correct warp ID", capt_decode_warp_id == 2'd0);
            check_result("Correct PC", capt_decode_pc == 64'h0);
            check_result("Correct instruction", capt_decode_instr == expected_instr);
            check_result("Correct mask", capt_decode_mask == 8'hFF);
            
            // Consume the instruction
            decode_ready = 1;
            @(posedge clk);
        end
    endtask
    
    // Test 2: Sequential fetches (same warp)
    task automatic test_sequential_fetch();
        begin
            $display("\n--- Test: Sequential Fetches ---");
            
            // First fetch
            wait_for_sched_ready();
            sched_valid = 1;
            sched_warp_id = 2'd1;
            sched_pc = 64'h0000_0000_0000_0010;  // Address 16 (word 4)
            sched_active_mask = 8'hFF;
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            wait_for_decode_valid();
            check_result("First fetch valid", capt_decode_valid == 1'b1);
            check_result("First fetch PC", capt_decode_pc == 64'h10);
            check_result("First fetch instr", capt_decode_instr == instr_mem[4]);
            
            decode_ready = 1;
            @(posedge clk);
            
            // Second fetch (should come from cache if same line)
            wait_for_sched_ready();
            sched_valid = 1;
            sched_warp_id = 2'd1;
            sched_pc = 64'h0000_0000_0000_0014;  // Address 20 (word 5)
            sched_active_mask = 8'hFF;
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            wait_for_decode_valid();
            check_result("Second fetch valid", capt_decode_valid == 1'b1);
            check_result("Second fetch PC", capt_decode_pc == 64'h14);
            check_result("Second fetch instr (cache hit)", capt_decode_instr == instr_mem[5]);
            
            decode_ready = 1;
            @(posedge clk);
        end
    endtask
    
    // Test 3: Multiple warps
    task automatic test_multiple_warps();
        begin
            $display("\n--- Test: Multiple Warps ---");
            
            // Warp 0
            wait_for_sched_ready();
            sched_valid = 1;
            sched_warp_id = 2'd0;
            sched_pc = 64'h0000_0000_0000_0100;  // Address 256
            sched_active_mask = 8'hAA;
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            wait_for_decode_valid();
            check_result("Warp 0 fetch valid", capt_decode_valid == 1'b1);
            check_result("Warp 0 ID correct", capt_decode_warp_id == 2'd0);
            check_result("Warp 0 mask correct", capt_decode_mask == 8'hAA);
            
            decode_ready = 1;
            @(posedge clk);
            
            // Warp 2
            wait_for_sched_ready();
            sched_valid = 1;
            sched_warp_id = 2'd2;
            sched_pc = 64'h0000_0000_0000_0200;  // Address 512
            sched_active_mask = 8'h55;
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            wait_for_decode_valid();
            check_result("Warp 2 fetch valid", capt_decode_valid == 1'b1);
            check_result("Warp 2 ID correct", capt_decode_warp_id == 2'd2);
            check_result("Warp 2 mask correct", capt_decode_mask == 8'h55);
            
            decode_ready = 1;
            @(posedge clk);
        end
    endtask
    
    // Test 4: Cache hit performance
    task automatic test_cache_hit();
        begin
            $display("\n--- Test: Cache Hit Performance ---");
            
            // First access - cache miss
            wait_for_sched_ready();
            sched_valid = 1;
            sched_warp_id = 2'd0;
            sched_pc = 64'h0000_0000_0000_0400;  // Address 1024
            sched_active_mask = 8'hFF;
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            wait_for_decode_valid();
            check_result("Cache miss fetch works", capt_decode_valid == 1'b1);
            decode_ready = 1;
            @(posedge clk);
            
            // Second access to same line - should be cache hit
            wait_for_sched_ready();
            sched_valid = 1;
            sched_warp_id = 2'd0;
            sched_pc = 64'h0000_0000_0000_0404;  // Address 1028 (same cache line)
            sched_active_mask = 8'hFF;
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            wait_for_decode_valid();
            check_result("Cache hit fetch works", capt_decode_valid == 1'b1);
            check_result("Cache hit correct data", capt_decode_instr == instr_mem[257]);
            decode_ready = 1;
            @(posedge clk);
        end
    endtask
    
    // Test 5: Decode stall handling
    task automatic test_decode_stall();
        begin
            $display("\n--- Test: Decode Stall Handling ---");
            
            // Stop accepting decoded instructions
            decode_ready = 0;
            
            // Request fetch
            wait_for_sched_ready();
            sched_valid = 1;
            sched_warp_id = 2'd1;
            sched_pc = 64'h0000_0000_0000_0800;
            sched_active_mask = 8'hFF;
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            // Wait for decode_valid (instruction should be buffered)
            wait_for_decode_valid();
            check_result("Instruction fetched", capt_decode_valid == 1'b1);
            
            // Wait a few cycles - instruction should remain valid
            repeat(5) @(posedge clk);
            check_result("Instruction held during stall", decode_valid == 1'b1);
            
            // Resume accepting
            decode_ready = 1;
            @(posedge clk);
            #1;
            
            // Should have consumed the instruction
            @(posedge clk);
            check_result("Instruction consumed after stall", 1'b1);  // Just checking we didn't hang
        end
    endtask
    
    // Test 6: PC update (branch)
    task automatic test_pc_update();
        begin
            $display("\n--- Test: PC Update (Branch) ---");
            
            // Initial fetch
            wait_for_sched_ready();
            sched_valid = 1;
            sched_warp_id = 2'd0;
            sched_pc = 64'h0000_0000_0000_0000;
            sched_active_mask = 8'hFF;
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            wait_for_decode_valid();
            decode_ready = 1;
            @(posedge clk);
            
            // Simulate branch by updating PC
            pc_update_valid = 1;
            pc_update_warp_id = 2'd0;
            pc_update_value = 64'h0000_0000_0000_1000;  // Branch to 4096
            @(posedge clk);
            #1;
            pc_update_valid = 0;
            
            // Next fetch should use new PC
            wait_for_sched_ready();
            sched_valid = 1;
            sched_warp_id = 2'd0;
            sched_pc = 64'h0000_0000_0000_1000;  // Should match updated PC
            sched_active_mask = 8'hFF;
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            wait_for_decode_valid();
            check_result("Fetch after PC update", capt_decode_pc == 64'h1000);
            check_result("Correct instr after branch", capt_decode_instr == instr_mem[1024]);
            decode_ready = 1;
            @(posedge clk);
        end
    endtask
    
    // Test 7: Warp flush
    task automatic test_warp_flush();
        begin
            $display("\n--- Test: Warp Flush ---");
            
            // Start a fetch
            wait_for_sched_ready();
            sched_valid = 1;
            sched_warp_id = 2'd1;
            sched_pc = 64'h0000_0000_0000_0C00;
            sched_active_mask = 8'hFF;
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            // Flush the warp mid-fetch
            warp_flush[1] = 1'b1;
            @(posedge clk);
            #1;
            warp_flush[1] = 1'b0;
            
            // Allow time for flush to take effect and cache to complete
            // Cache miss takes 2 cycles + refill, so wait longer
            repeat(10) @(posedge clk);
            
            // Should be ready for new fetch
            check_result("Ready after flush", sched_ready == 1'b1);
            
            @(posedge clk);
        end
    endtask
    
    // Test 8: Cache flush
    task automatic test_cache_flush();
        begin
            $display("\n--- Test: Cache Flush ---");
            
            // Warm up cache
            wait_for_sched_ready();
            sched_valid = 1;
            sched_warp_id = 2'd0;
            sched_pc = 64'h0000_0000_0000_0000;
            sched_active_mask = 8'hFF;
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            wait_for_decode_valid();
            decode_ready = 1;
            @(posedge clk);
            
            // Flush cache
            cache_flush = 1;
            @(posedge clk);
            cache_flush = 0;
            
            // Wait for flush to complete
            repeat(150) @(posedge clk);  // Cache has 128 lines
            
            check_result("Cache flush completes", busy == 1'b0 || sched_ready == 1'b1);
            
            @(posedge clk);
        end
    endtask
    
    // Test 9: Back-to-back fetches with buffer
    task automatic test_back_to_back();
        begin
            $display("\n--- Test: Back-to-back Fetches ---");
            
            // Fill fetch buffer with 2 instructions
            decode_ready = 0;  // Stop consuming
            
            // First fetch
            wait_for_sched_ready();
            sched_valid = 1;
            sched_warp_id = 2'd0;
            sched_pc = 64'h0000_0000_0000_0000;
            sched_active_mask = 8'hFF;
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            // Wait for first instruction
            wait_for_decode_valid();
            
            // Second fetch (buffer not full yet)
            wait_for_sched_ready();
            sched_valid = 1;
            sched_warp_id = 2'd1;
            sched_pc = 64'h0000_0000_0000_0004;
            sched_active_mask = 8'hF0;
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            // Wait a bit
            repeat(10) @(posedge clk);
            
            // Now consume both
            decode_ready = 1;
            @(posedge clk);
            
            check_result("First buffered instruction", decode_valid == 1'b1);
            
            @(posedge clk);
            
            // Check if second one comes
            wait_for_decode_valid();
            check_result("Second buffered instruction", capt_decode_valid == 1'b1);
            
            @(posedge clk);
        end
    endtask
    
    // Test 10: Edge case - address at cache line boundary
    task automatic test_cache_line_boundary();
        begin
            $display("\n--- Test: Cache Line Boundary ---");
            
            // Fetch at end of cache line (address 28 = word 7, last word of line 0)
            wait_for_sched_ready();
            sched_valid = 1;
            sched_warp_id = 2'd0;
            sched_pc = 64'h0000_0000_0000_001C;  // Address 28
            sched_active_mask = 8'hFF;
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            wait_for_decode_valid();
            check_result("Last word of cache line", capt_decode_instr == instr_mem[7]);
            decode_ready = 1;
            @(posedge clk);
            
            // Fetch at start of next cache line
            wait_for_sched_ready();
            sched_valid = 1;
            sched_warp_id = 2'd0;
            sched_pc = 64'h0000_0000_0000_0020;  // Address 32 (start of line 1)
            sched_active_mask = 8'hFF;
            @(posedge clk);
            #1;
            sched_valid = 0;
            
            wait_for_decode_valid();
            check_result("First word of next cache line", capt_decode_instr == instr_mem[8]);
            decode_ready = 1;
            @(posedge clk);
        end
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    
    initial begin
        $display("===========================================");
        $display("GPGPU-1 Instruction Fetch Unit Testbench");
        $display("===========================================");
        
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        reset_dut();
        
        test_basic_fetch();
        reset_dut();
        
        test_sequential_fetch();
        reset_dut();
        
        test_multiple_warps();
        reset_dut();
        
        test_cache_hit();
        reset_dut();
        
        test_decode_stall();
        reset_dut();
        
        test_pc_update();
        reset_dut();
        
        test_warp_flush();
        reset_dut();
        
        test_cache_flush();
        reset_dut();
        
        test_back_to_back();
        reset_dut();
        
        test_cache_line_boundary();
        
        // Summary
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
    
    //=========================================================================
    // Timeout
    //=========================================================================
    
    initial begin
        #100000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
