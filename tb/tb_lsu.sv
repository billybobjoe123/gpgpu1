//=============================================================================
// GPGPU-1 Load/Store Unit Testbench
//=============================================================================
// File:        tb_lsu.sv
// Description: Comprehensive testbench for the LSU module
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_lsu;
    import gpgpu_pkg::*;

    //=========================================================================
    // Parameters
    //=========================================================================
    
    parameter int NUM_THREADS = WARP_SIZE;
    parameter int SHARED_MEM_ADDR_WIDTH = 14;
    parameter int CLK_PERIOD = 10;
    
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
    
    // Shared memory interface
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
    
    // Simple memory model for testing
    logic [DATA_WIDTH-1:0] global_mem [0:1023];
    logic [DATA_WIDTH-1:0] shared_mem [0:255];
    
    // Captured response data (captured when resp_valid goes high)
    logic                                   capt_resp_valid;
    logic [WARP_ID_WIDTH-1:0]               capt_resp_warp_id;
    logic [REG_ADDR_WIDTH-1:0]              capt_resp_rd;
    logic [NUM_THREADS-1:0]                 capt_resp_mask;
    logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] capt_resp_data;
    
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
    // Global Memory Model
    //=========================================================================
    
    // Simple memory model with 1-cycle latency
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
    
    //=========================================================================
    // Shared Memory Model
    //=========================================================================
    
    // Simple parallel memory model with 1-cycle latency
    logic smem_pending;
    logic [NUM_THREADS-1:0] smem_pending_mask;
    logic [NUM_THREADS-1:0][SHARED_MEM_ADDR_WIDTH-1:0] smem_pending_addr;
    logic smem_pending_we;
    logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] smem_pending_wdata;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            smem_resp_valid <= 1'b0;
            smem_resp_rdata <= '0;
            smem_pending <= 1'b0;
        end else begin
            smem_resp_valid <= 1'b0;
            
            if (smem_req_valid && smem_req_ready) begin
                smem_pending <= 1'b1;
                smem_pending_mask <= smem_req_mask;
                smem_pending_addr <= smem_req_addr;
                smem_pending_we <= smem_req_we;
                smem_pending_wdata <= smem_req_wdata;
            end
            
            if (smem_pending) begin
                smem_pending <= 1'b0;
                smem_resp_valid <= 1'b1;
                
                for (int t = 0; t < NUM_THREADS; t++) begin
                    if (smem_pending_mask[t]) begin
                        if (smem_pending_we) begin
                            // Write - convert byte address to word address (divide by 8)
                            shared_mem[smem_pending_addr[t][10:3]] <= smem_pending_wdata[t];
                        end else begin
                            // Read - convert byte address to word address (divide by 8)
                            smem_resp_rdata[t] <= shared_mem[smem_pending_addr[t][10:3]];
                        end
                    end
                end
            end
        end
    end
    
    assign smem_req_ready = !smem_pending;
    
    //=========================================================================
    // Test Tasks
    //=========================================================================
    
    task automatic reset_dut();
        begin
            rst_n = 0;
            req_valid = 0;
            req_warp_id = 0;
            req_active_mask = '0;
            req_pred_mask = '1;  // All predicates true by default
            req_opcode = OP_LD;
            req_func = 8'h0;
            req_rd = 0;
            req_base_addr = '0;
            req_offset = 0;
            req_store_data = '0;
            resp_ready = 1;
            
            // Initialize memories
            for (int i = 0; i < 1024; i++) begin
                global_mem[i] = 64'hDEAD_BEEF_0000_0000 | i;
            end
            for (int i = 0; i < 256; i++) begin
                shared_mem[i] = 64'hCAFE_BABE_0000_0000 | i;
            end
            
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
        end
    endtask
    
    task automatic wait_for_ready();
        begin
            while (!req_ready) @(posedge clk);
        end
    endtask
    
    task automatic wait_for_response();
        begin
            integer timeout;
            timeout = 0;
            capt_resp_valid = 1'b0;
            while (!resp_valid && timeout < 100) begin
                @(posedge clk);
                timeout++;
            end
            if (timeout >= 100) begin
                $display("ERROR: Timeout waiting for response");
            end else begin
                // Capture response data immediately when valid
                capt_resp_valid = resp_valid;
                capt_resp_warp_id = resp_warp_id;
                capt_resp_rd = resp_rd;
                capt_resp_mask = resp_mask;
                capt_resp_data = resp_data;
            end
        end
    endtask
    
    task automatic wait_cycles(input int n);
        begin
            repeat(n) @(posedge clk);
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
    
    // Test 1: Single thread 64-bit global load
    task automatic test_single_thread_load_64();
        begin
            $display("\n--- Test: Single Thread 64-bit Global Load ---");
            
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd1;
            req_active_mask = 8'b0000_0001;  // Only thread 0
            req_pred_mask = 8'b1111_1111;
            req_opcode = OP_LD;
            req_rd = 5'd5;
            req_base_addr[0] = 64'h0000_0000_0000_0040;  // Address 64 (word 8)
            req_offset = 13'd0;
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            wait_for_response();
            
            check_result("Response valid", capt_resp_valid == 1'b1);
            check_result("Warp ID correct", capt_resp_warp_id == 2'd1);
            check_result("RD correct", capt_resp_rd == 5'd5);
            check_result("Thread 0 mask set", capt_resp_mask[0] == 1'b1);
            check_result("Load data correct", capt_resp_data[0] == global_mem[8]);
            
            @(posedge clk);
        end
    endtask
    
    // Test 2: All threads 64-bit global load (stride-1 access)
    task automatic test_all_threads_load_64();
        begin
            $display("\n--- Test: All Threads 64-bit Global Load ---");
            
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd0;
            req_active_mask = 8'b1111_1111;  // All threads
            req_pred_mask = 8'b1111_1111;
            req_opcode = OP_LD;
            req_rd = 5'd10;
            
            // Each thread accesses consecutive 64-bit words
            for (int t = 0; t < NUM_THREADS; t++) begin
                req_base_addr[t] = 64'h0000_0000_0000_0000 + (t * 8);
            end
            req_offset = 13'd0;
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            wait_for_response();
            #1;
            
            check_result("Response valid", capt_resp_valid == 1'b1);
            check_result("All threads mask set", capt_resp_mask == 8'b1111_1111);
            
            begin
                logic all_correct;
                all_correct = 1'b1;
                for (int t = 0; t < NUM_THREADS; t++) begin
                    if (capt_resp_data[t] != global_mem[t]) begin
                        all_correct = 1'b0;
                        $display("  Thread %0d: expected %h, got %h", t, global_mem[t], capt_resp_data[t]);
                    end
                end
                check_result("All thread data correct", all_correct);
            end
            
            @(posedge clk);
        end
    endtask
    
    // Test 3: 64-bit global store
    task automatic test_global_store_64();
        begin
            $display("\n--- Test: 64-bit Global Store ---");
            
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd2;
            req_active_mask = 8'b0000_0011;  // Threads 0 and 1
            req_pred_mask = 8'b1111_1111;
            req_opcode = OP_ST;
            req_rd = 5'd0;  // Not used for stores (this is source reg)
            req_base_addr[0] = 64'h0000_0000_0000_0400;  // Address 1024 (word 128)
            req_base_addr[1] = 64'h0000_0000_0000_0408;  // Address 1032 (word 129)
            req_offset = 13'd0;
            req_store_data[0] = 64'h1234_5678_9ABC_DEF0;
            req_store_data[1] = 64'hFEDC_BA98_7654_3210;
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            // Wait for store to complete
            wait_cycles(20);
            
            check_result("Store thread 0 data", global_mem[128] == 64'h1234_5678_9ABC_DEF0);
            check_result("Store thread 1 data", global_mem[129] == 64'hFEDC_BA98_7654_3210);
            
            @(posedge clk);
        end
    endtask
    
    // Test 4: 32-bit unsigned global load
    task automatic test_load_32u();
        begin
            $display("\n--- Test: 32-bit Unsigned Global Load ---");
            
            // Prepare test data
            global_mem[16] = 64'hFFFF_FFFF_8000_0001;
            
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd0;
            req_active_mask = 8'b0000_0001;
            req_pred_mask = 8'b1111_1111;
            req_opcode = OP_LD32;
            req_rd = 5'd7;
            req_base_addr[0] = 64'h0000_0000_0000_0080;  // Address 128 (word 16)
            req_offset = 13'd0;
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            wait_for_response();
            #1;
            
            check_result("Response valid", capt_resp_valid == 1'b1);
            // 32-bit unsigned should zero-extend: 0x8000_0001 -> 0x0000_0000_8000_0001
            check_result("32-bit unsigned zero-extended", capt_resp_data[0] == 64'h0000_0000_8000_0001);
            
            @(posedge clk);
        end
    endtask
    
    // Test 5: 32-bit signed global load
    task automatic test_load_32s();
        begin
            $display("\n--- Test: 32-bit Signed Global Load ---");
            
            // Prepare test data
            global_mem[20] = 64'h0000_0000_8000_0001;
            
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd0;
            req_active_mask = 8'b0000_0001;
            req_pred_mask = 8'b1111_1111;
            req_opcode = OP_LD32S;
            req_rd = 5'd8;
            req_base_addr[0] = 64'h0000_0000_0000_00A0;  // Address 160 (word 20)
            req_offset = 13'd0;
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            wait_for_response();
            #1;
            
            check_result("Response valid", capt_resp_valid == 1'b1);
            // 32-bit signed should sign-extend: 0x8000_0001 -> 0xFFFF_FFFF_8000_0001
            check_result("32-bit signed sign-extended", capt_resp_data[0] == 64'hFFFF_FFFF_8000_0001);
            
            @(posedge clk);
        end
    endtask
    
    // Test 6: Shared memory 64-bit load
    task automatic test_shared_load_64();
        begin
            $display("\n--- Test: Shared Memory 64-bit Load ---");
            
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd1;
            req_active_mask = 8'b0000_1111;  // Threads 0-3
            req_pred_mask = 8'b1111_1111;
            req_opcode = OP_LDS;
            req_rd = 5'd12;
            
            // Each thread accesses different shared memory location
            for (int t = 0; t < 4; t++) begin
                req_base_addr[t] = 64'h0000_0000_0000_0000 + (t * 8);
            end
            req_offset = 13'd0;
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            wait_for_response();
            #1;
            
            check_result("Response valid", capt_resp_valid == 1'b1);
            check_result("Thread mask correct", (capt_resp_mask & 8'h0F) == 8'h0F);
            
            begin
                logic all_correct;
                all_correct = 1'b1;
                for (int t = 0; t < 4; t++) begin
                    if (capt_resp_data[t] != shared_mem[t]) begin
                        all_correct = 1'b0;
                        $display("  Thread %0d: expected %h, got %h", t, shared_mem[t], capt_resp_data[t]);
                    end
                end
                check_result("Shared memory data correct", all_correct);
            end
            
            @(posedge clk);
        end
    endtask
    
    // Test 7: Shared memory 64-bit store
    task automatic test_shared_store_64();
        begin
            $display("\n--- Test: Shared Memory 64-bit Store ---");
            
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd3;
            req_active_mask = 8'b0000_0011;  // Threads 0 and 1
            req_pred_mask = 8'b1111_1111;
            req_opcode = OP_STS;
            req_rd = 5'd0;
            req_base_addr[0] = 64'h0000_0000_0000_0100;  // Address 256 (shared word 32)
            req_base_addr[1] = 64'h0000_0000_0000_0108;  // Address 264 (shared word 33)
            req_offset = 13'd0;
            req_store_data[0] = 64'hAAAA_BBBB_CCCC_DDDD;
            req_store_data[1] = 64'h1111_2222_3333_4444;
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            // Wait for store to complete
            wait_cycles(10);
            
            check_result("Shared store thread 0", shared_mem[32] == 64'hAAAA_BBBB_CCCC_DDDD);
            check_result("Shared store thread 1", shared_mem[33] == 64'h1111_2222_3333_4444);
            
            @(posedge clk);
        end
    endtask
    
    // Test 8: Load with positive offset
    task automatic test_load_with_offset();
        begin
            $display("\n--- Test: Load with Positive Offset ---");
            
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd0;
            req_active_mask = 8'b0000_0001;
            req_pred_mask = 8'b1111_1111;
            req_opcode = OP_LD;
            req_rd = 5'd15;
            req_base_addr[0] = 64'h0000_0000_0000_0000;  // Base address 0
            req_offset = 13'd64;  // Offset 64 bytes (word 8)
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            wait_for_response();
            #1;
            
            check_result("Response valid", capt_resp_valid == 1'b1);
            check_result("Load with offset correct", capt_resp_data[0] == global_mem[8]);
            
            @(posedge clk);
        end
    endtask
    
    // Test 9: Load with negative offset
    task automatic test_load_with_negative_offset();
        begin
            $display("\n--- Test: Load with Negative Offset ---");
            
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd0;
            req_active_mask = 8'b0000_0001;
            req_pred_mask = 8'b1111_1111;
            req_opcode = OP_LD;
            req_rd = 5'd16;
            req_base_addr[0] = 64'h0000_0000_0000_0080;  // Base address 128 (word 16)
            req_offset = -13'sd64;  // Offset -64 bytes (word 8)
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            wait_for_response();
            #1;
            
            check_result("Response valid", capt_resp_valid == 1'b1);
            check_result("Load with negative offset correct", capt_resp_data[0] == global_mem[8]);
            
            @(posedge clk);
        end
    endtask
    
    // Test 10: Predicated load (some threads masked out)
    task automatic test_predicated_load();
        begin
            $display("\n--- Test: Predicated Load ---");
            
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd0;
            req_active_mask = 8'b1111_1111;  // All threads active
            req_pred_mask = 8'b1010_1010;    // Only even threads predicated true
            req_opcode = OP_LD;
            req_rd = 5'd20;
            
            for (int t = 0; t < NUM_THREADS; t++) begin
                req_base_addr[t] = 64'h0000_0000_0000_0000 + (t * 8);
            end
            req_offset = 13'd0;
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            wait_for_response();
            #1;
            
            check_result("Response valid", capt_resp_valid == 1'b1);
            // Only even threads should have valid data
            check_result("Predicate mask applied", (capt_resp_mask & 8'b0101_0101) == 8'b0000_0000);
            check_result("Even threads mask set", (capt_resp_mask & 8'b1010_1010) == 8'b1010_1010);
            
            @(posedge clk);
        end
    endtask
    
    // Test 11: Partial active mask load
    task automatic test_partial_active_mask();
        begin
            $display("\n--- Test: Partial Active Mask Load ---");
            
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd0;
            req_active_mask = 8'b0000_1111;  // Only lower 4 threads active
            req_pred_mask = 8'b1111_1111;    // All predicates true
            req_opcode = OP_LD;
            req_rd = 5'd21;
            
            for (int t = 0; t < NUM_THREADS; t++) begin
                req_base_addr[t] = 64'h0000_0000_0000_0000 + (t * 8);
            end
            req_offset = 13'd0;
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            wait_for_response();
            #1;
            
            check_result("Response valid", capt_resp_valid == 1'b1);
            check_result("Only active threads in mask", (capt_resp_mask & 8'b1111_0000) == 8'b0000_0000);
            check_result("Active threads mask set", (capt_resp_mask & 8'b0000_1111) == 8'b0000_1111);
            
            @(posedge clk);
        end
    endtask
    
    // Test 12: 32-bit store
    task automatic test_store_32();
        begin
            $display("\n--- Test: 32-bit Global Store ---");
            
            // Clear target location
            global_mem[200] = 64'h0000_0000_0000_0000;
            
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd0;
            req_active_mask = 8'b0000_0001;
            req_pred_mask = 8'b1111_1111;
            req_opcode = OP_ST32;
            req_rd = 5'd0;
            req_base_addr[0] = 64'h0000_0000_0000_0640;  // Address 1600 (word 200)
            req_offset = 13'd0;
            req_store_data[0] = 64'hFFFF_FFFF_DEAD_BEEF;  // Only lower 32 bits stored
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            // Wait for store to complete
            wait_cycles(20);
            
            // Only lower 32 bits should be written
            check_result("32-bit store lower bits", (global_mem[200] & 64'h0000_0000_FFFF_FFFF) == 64'h0000_0000_DEAD_BEEF);
            
            @(posedge clk);
        end
    endtask
    
    // Test 13: Address generation with various offsets
    task automatic test_address_generation();
        logic [63:0] expected_addr;
        begin
            $display("\n--- Test: Address Generation ---");
            
            // Test various offset combinations
            
            wait_for_ready();
            
            // Test 1: Large positive offset
            req_valid = 1;
            req_warp_id = 2'd0;
            req_active_mask = 8'b0000_0001;
            req_pred_mask = 8'b1111_1111;
            req_opcode = OP_LD;
            req_rd = 5'd22;
            req_base_addr[0] = 64'h0000_0000_0000_0000;
            req_offset = 13'd4095;  // Max positive offset
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            // Just check that we complete without hanging
            wait_for_response();
            #1;
            
            check_result("Large positive offset completes", capt_resp_valid == 1'b1);
            
            @(posedge clk);
        end
    endtask
    
    // Test 14: LDS32 (32-bit shared memory load)
    task automatic test_shared_load_32();
        begin
            $display("\n--- Test: 32-bit Shared Memory Load ---");
            
            // Prepare test data
            shared_mem[50] = 64'hAAAA_BBBB_8765_4321;
            
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd0;
            req_active_mask = 8'b0000_0001;
            req_pred_mask = 8'b1111_1111;
            req_opcode = OP_LDS32;
            req_rd = 5'd23;
            req_base_addr[0] = 64'h0000_0000_0000_0190;  // Address 400 (word 50)
            req_offset = 13'd0;
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            wait_for_response();
            #1;
            
            check_result("Response valid", capt_resp_valid == 1'b1);
            // Should zero-extend 32-bit value
            check_result("LDS32 zero-extended", capt_resp_data[0] == 64'h0000_0000_8765_4321);
            
            @(posedge clk);
        end
    endtask
    
    // Test 15: STS32 (32-bit shared memory store)
    task automatic test_shared_store_32();
        begin
            $display("\n--- Test: 32-bit Shared Memory Store ---");
            
            // Clear target
            shared_mem[60] = 64'h0000_0000_0000_0000;
            
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd0;
            req_active_mask = 8'b0000_0001;
            req_pred_mask = 8'b1111_1111;
            req_opcode = OP_STS32;
            req_rd = 5'd0;
            req_base_addr[0] = 64'h0000_0000_0000_01E0;  // Address 480 (word 60)
            req_offset = 13'd0;
            req_store_data[0] = 64'hFFFF_FFFF_CAFE_BABE;
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            // Wait for store to complete
            wait_cycles(10);
            
            check_result("STS32 lower bits stored", (shared_mem[60] & 64'h0000_0000_FFFF_FFFF) == 64'h0000_0000_CAFE_BABE);
            
            @(posedge clk);
        end
    endtask
    
    // Test 16: Back-to-back requests
    task automatic test_back_to_back();
        begin
            $display("\n--- Test: Back-to-back Requests ---");
            
            // First request
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd0;
            req_active_mask = 8'b0000_0001;
            req_pred_mask = 8'b1111_1111;
            req_opcode = OP_LD;
            req_rd = 5'd24;
            req_base_addr[0] = 64'h0000_0000_0000_0000;
            req_offset = 13'd0;
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            wait_for_response();
            #1;
            
            check_result("First request complete", capt_resp_valid == 1'b1);
            
            // Second request immediately after
            wait_for_ready();
            
            req_valid = 1;
            req_warp_id = 2'd1;
            req_active_mask = 8'b0000_0001;
            req_pred_mask = 8'b1111_1111;
            req_opcode = OP_LD;
            req_rd = 5'd25;
            req_base_addr[0] = 64'h0000_0000_0000_0008;
            req_offset = 13'd0;
            
            @(posedge clk);
            #1;
            req_valid = 0;
            
            wait_for_response();
            #1;
            
            check_result("Second request complete", capt_resp_valid == 1'b1);
            check_result("Second request warp ID", capt_resp_warp_id == 2'd1);
            
            @(posedge clk);
        end
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    
    initial begin
        $display("===========================================");
        $display("GPGPU-1 Load/Store Unit Testbench");
        $display("===========================================\n");
        
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        reset_dut();
        
        // Run all tests
        test_single_thread_load_64();
        test_all_threads_load_64();
        test_global_store_64();
        test_load_32u();
        test_load_32s();
        test_shared_load_64();
        test_shared_store_64();
        test_load_with_offset();
        test_load_with_negative_offset();
        test_predicated_load();
        test_partial_active_mask();
        test_store_32();
        test_address_generation();
        test_shared_load_32();
        test_shared_store_32();
        test_back_to_back();
        
        // Summary
        $display("\n===========================================");
        $display("Test Summary");
        $display("===========================================");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("===========================================\n");
        
        if (fail_count == 0) begin
            $display("*** ALL TESTS PASSED ***\n");
        end else begin
            $display("*** SOME TESTS FAILED ***\n");
        end
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #100000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
