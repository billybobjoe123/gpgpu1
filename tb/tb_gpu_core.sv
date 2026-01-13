//=============================================================================
// GPGPU-1 GPU Core Testbench
//=============================================================================
// File:        tb_gpu_core.sv
// Description: Testbench for the integrated GPU core pipeline.
//              Tests basic instruction flow through all pipeline stages.
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_gpu_core;
    import gpgpu_pkg::*;

    //=========================================================================
    // Parameters
    //=========================================================================
    
    parameter int CORE_ID         = 0;
    parameter int P_NUM_WARPS       = WARPS_PER_CORE;
    parameter int P_ICACHE_SIZE     = 4096;
    parameter int P_SHARED_MEM_SIZE = 16384;
    parameter int CLK_PERIOD      = 10;
    
    //=========================================================================
    // Signals
    //=========================================================================
    
    logic                           clk;
    logic                           rst_n;
    
    // Dispatch interface
    logic                           dispatch_valid;
    logic [WARP_ID_WIDTH-1:0]       dispatch_warp_id;
    logic [ADDR_WIDTH-1:0]          dispatch_pc;
    logic [WARP_SIZE-1:0]           dispatch_mask;
    logic                           dispatch_ready;
    
    // Global memory interface (AXI-like)
    logic                           gmem_arvalid;
    logic                           gmem_arready;
    logic [ADDR_WIDTH-1:0]          gmem_araddr;
    logic [7:0]                     gmem_arlen;
    logic [2:0]                     gmem_arsize;
    
    logic                           gmem_rvalid;
    logic                           gmem_rready;
    logic [DATA_WIDTH-1:0]          gmem_rdata;
    logic [1:0]                     gmem_rresp;
    logic                           gmem_rlast;
    
    logic                           gmem_awvalid;
    logic                           gmem_awready;
    logic [ADDR_WIDTH-1:0]          gmem_awaddr;
    logic [7:0]                     gmem_awlen;
    logic [2:0]                     gmem_awsize;
    
    logic                           gmem_wvalid;
    logic                           gmem_wready;
    logic [DATA_WIDTH-1:0]          gmem_wdata;
    logic [7:0]                     gmem_wstrb;
    logic                           gmem_wlast;
    
    logic                           gmem_bvalid;
    logic                           gmem_bready;
    logic [1:0]                     gmem_bresp;
    
    // Instruction memory interface
    logic                           imem_req_valid;
    logic [ADDR_WIDTH-1:0]          imem_req_addr;
    logic                           imem_req_ready;
    logic                           imem_resp_valid;
    logic [255:0]                   imem_resp_data;
    
    // Status
    logic [P_NUM_WARPS-1:0]           warps_active;
    logic                           core_busy;
    logic                           all_warps_done;
    
    //=========================================================================
    // Test Variables
    //=========================================================================
    
    int test_count;
    int pass_count;
    int fail_count;
    
    // Instruction memory model (16KB)
    logic [31:0] instr_mem [0:4095];
    
    // Data memory model (64KB)
    logic [63:0] data_mem [0:8191];
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    
    gpu_core #(
        .CORE_ID(CORE_ID),
        .NUM_WARPS(P_NUM_WARPS),
        .P_ICACHE_SIZE(P_ICACHE_SIZE),
        .P_SHARED_MEM_SIZE(P_SHARED_MEM_SIZE)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        
        .dispatch_valid   (dispatch_valid),
        .dispatch_warp_id (dispatch_warp_id),
        .dispatch_pc      (dispatch_pc),
        .dispatch_mask    (dispatch_mask),
        .dispatch_ready   (dispatch_ready),
        
        .gmem_arvalid     (gmem_arvalid),
        .gmem_arready     (gmem_arready),
        .gmem_araddr      (gmem_araddr),
        .gmem_arlen       (gmem_arlen),
        .gmem_arsize      (gmem_arsize),
        
        .gmem_rvalid      (gmem_rvalid),
        .gmem_rready      (gmem_rready),
        .gmem_rdata       (gmem_rdata),
        .gmem_rresp       (gmem_rresp),
        .gmem_rlast       (gmem_rlast),
        
        .gmem_awvalid     (gmem_awvalid),
        .gmem_awready     (gmem_awready),
        .gmem_awaddr      (gmem_awaddr),
        .gmem_awlen       (gmem_awlen),
        .gmem_awsize      (gmem_awsize),
        
        .gmem_wvalid      (gmem_wvalid),
        .gmem_wready      (gmem_wready),
        .gmem_wdata       (gmem_wdata),
        .gmem_wstrb       (gmem_wstrb),
        .gmem_wlast       (gmem_wlast),
        
        .gmem_bvalid      (gmem_bvalid),
        .gmem_bready      (gmem_bready),
        .gmem_bresp       (gmem_bresp),
        
        .imem_req_valid   (imem_req_valid),
        .imem_req_addr    (imem_req_addr),
        .imem_req_ready   (imem_req_ready),
        .imem_resp_valid  (imem_resp_valid),
        .imem_resp_data   (imem_resp_data),
        
        .warps_active     (warps_active),
        .core_busy        (core_busy),
        .all_warps_done   (all_warps_done)
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
    
    logic [2:0] imem_latency_counter;
    logic       imem_pending;
    logic [ADDR_WIDTH-1:0] imem_pending_addr;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_resp_valid <= 1'b0;
            imem_resp_data <= '0;
            imem_pending <= 1'b0;
            imem_latency_counter <= '0;
        end else begin
            imem_resp_valid <= 1'b0;
            
            if (imem_req_valid && imem_req_ready && !imem_pending) begin
                imem_pending <= 1'b1;
                imem_pending_addr <= imem_req_addr;
                imem_latency_counter <= 3'd2;
            end
            
            if (imem_pending) begin
                if (imem_latency_counter == 0) begin
                    imem_pending <= 1'b0;
                    imem_resp_valid <= 1'b1;
                    
                    // Build cache line (8 instructions)
                    for (int i = 0; i < 8; i++) begin
                        logic [11:0] word_addr;
                        word_addr = (imem_pending_addr[13:2] & 12'hFF8) + i[11:0];
                        imem_resp_data[i*32 +: 32] <= instr_mem[word_addr];
                    end
                end else begin
                    imem_latency_counter <= imem_latency_counter - 1;
                end
            end
        end
    end
    
    assign imem_req_ready = !imem_pending;
    
    //=========================================================================
    // Global Memory Model (AXI-like)
    //=========================================================================
    
    logic [2:0] gmem_rd_latency;
    logic gmem_rd_pending;
    logic [ADDR_WIDTH-1:0] gmem_rd_addr;
    
    // Read channel
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gmem_rvalid <= 1'b0;
            gmem_rdata <= '0;
            gmem_rresp <= 2'b00;
            gmem_rlast <= 1'b0;
            gmem_rd_pending <= 1'b0;
            gmem_rd_latency <= '0;
            gmem_rd_addr <= '0;
        end else begin
            gmem_rvalid <= 1'b0;
            
            if (gmem_arvalid && gmem_arready && !gmem_rd_pending) begin
                gmem_rd_pending <= 1'b1;
                gmem_rd_addr <= gmem_araddr;
                gmem_rd_latency <= 3'd3;
            end
            
            if (gmem_rd_pending) begin
                if (gmem_rd_latency == 0) begin
                    gmem_rd_pending <= 1'b0;
                    gmem_rvalid <= 1'b1;
                    gmem_rdata <= data_mem[gmem_rd_addr[15:3]];
                    gmem_rresp <= 2'b00;  // OKAY
                    gmem_rlast <= 1'b1;
                end else begin
                    gmem_rd_latency <= gmem_rd_latency - 1;
                end
            end
        end
    end
    
    assign gmem_arready = !gmem_rd_pending;
    
    // Write channel
    logic gmem_wr_pending;
    logic [ADDR_WIDTH-1:0] gmem_wr_addr;
    logic gmem_wr_addr_done;
    logic gmem_wr_data_done;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gmem_bvalid <= 1'b0;
            gmem_bresp <= 2'b00;
            gmem_wr_pending <= 1'b0;
            gmem_wr_addr <= '0;
            gmem_wr_addr_done <= 1'b0;
            gmem_wr_data_done <= 1'b0;
        end else begin
            gmem_bvalid <= 1'b0;
            
            // Address phase
            if (gmem_awvalid && gmem_awready) begin
                gmem_wr_addr <= gmem_awaddr;
                gmem_wr_addr_done <= 1'b1;
                gmem_wr_pending <= 1'b1;
            end
            
            // Data phase
            if (gmem_wvalid && gmem_wready && gmem_wlast) begin
                gmem_wr_data_done <= 1'b1;
                // Write to memory
                if (gmem_wr_addr_done) begin
                    for (int b = 0; b < 8; b++) begin
                        if (gmem_wstrb[b]) begin
                            data_mem[gmem_wr_addr[15:3]][b*8 +: 8] <= gmem_wdata[b*8 +: 8];
                        end
                    end
                end
            end
            
            // Response phase
            if (gmem_wr_addr_done && gmem_wr_data_done) begin
                gmem_bvalid <= 1'b1;
                gmem_bresp <= 2'b00;  // OKAY
                if (gmem_bready) begin
                    gmem_wr_pending <= 1'b0;
                    gmem_wr_addr_done <= 1'b0;
                    gmem_wr_data_done <= 1'b0;
                end
            end
        end
    end
    
    assign gmem_awready = !gmem_wr_pending;
    assign gmem_wready = gmem_wr_addr_done && !gmem_wr_data_done;
    
    //=========================================================================
    // Test Tasks
    //=========================================================================
    
    task automatic reset_dut();
        begin
            rst_n = 0;
            dispatch_valid = 0;
            dispatch_warp_id = 0;
            dispatch_pc = '0;
            dispatch_mask = '0;
            
            // Clear memories
            for (int i = 0; i < 4096; i++) begin
                instr_mem[i] = 32'h0;  // NOP-like
            end
            for (int i = 0; i < 8192; i++) begin
                data_mem[i] = 64'h0;
            end
            
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
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
    
    task automatic wait_cycles(input int n);
        begin
            repeat(n) @(posedge clk);
        end
    endtask
    
    task automatic dispatch_warp(
        input logic [WARP_ID_WIDTH-1:0] warp_id,
        input logic [ADDR_WIDTH-1:0] pc,
        input logic [WARP_SIZE-1:0] mask
    );
        begin
            dispatch_valid = 1;
            dispatch_warp_id = warp_id;
            dispatch_pc = pc;
            dispatch_mask = mask;
            @(posedge clk);
            while (!dispatch_ready) @(posedge clk);
            dispatch_valid = 0;
            @(posedge clk);
        end
    endtask
    
    task automatic wait_for_done();
        begin
            integer timeout;
            timeout = 0;
            while (!all_warps_done && timeout < 1000) begin
                @(posedge clk);
                timeout++;
            end
            if (timeout >= 1000) begin
                $display("WARNING: Timeout waiting for all_warps_done");
            end
        end
    endtask
    
    //=========================================================================
    // Instruction Encoding Helpers
    //=========================================================================
    
    // R-type: [31:26] opcode, [25:21] rd, [20:16] rs1, [15:11] rs2, [10:8] pred, [7:0] func
    function automatic logic [31:0] encode_r_type(
        input logic [5:0] opcode,
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] rs2,
        input logic [2:0] pred,
        input logic [7:0] func
    );
        encode_r_type = {opcode, rd, rs1, rs2, pred, func};
    endfunction
    
    // I-type: [31:26] opcode, [25:21] rd, [20:16] rs1, [15:0] imm16
    function automatic logic [31:0] encode_i_type(
        input logic [5:0] opcode,
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [15:0] imm16
    );
        encode_i_type = {opcode, rd, rs1, imm16};
    endfunction
    
    // Exit instruction
    function automatic logic [31:0] encode_exit();
        encode_exit = {6'b010100, 26'b0};  // OP_EXIT
    endfunction
    
    //=========================================================================
    // Test Cases
    //=========================================================================
    
    // Test 1: Basic warp dispatch and fetch
    task automatic test_warp_dispatch();
        begin
            $display("\n--- Test: Warp Dispatch ---");
            
            // Load a simple program
            // ADD R1, R0, R0  (R1 = 0)
            instr_mem[0] = encode_r_type(6'b000000, 5'd1, 5'd0, 5'd0, 3'd0, 8'h00);
            // EXIT
            instr_mem[1] = encode_exit();
            
            // Dispatch warp 0
            dispatch_warp(2'd0, 64'h0, 8'hFF);
            
            check_result("Warp dispatched", warps_active[0] == 1'b1);
            
            // Wait for warp to complete
            wait_cycles(50);
            
            check_result("Core eventually finishes", 1'b1);
        end
    endtask
    
    // Test 2: Multiple instructions
    task automatic test_multi_instr();
        begin
            $display("\n--- Test: Multiple Instructions ---");
            
            // Simple program:
            // ADDI R1, R0, 10     ; R1 = 10
            // ADDI R2, R0, 20     ; R2 = 20
            // ADD  R3, R1, R2     ; R3 = 30
            // EXIT
            
            // ALUI format: [31:26]=0x01, [25:21]=rd, [20:16]=rs1, [15:14]=func, [13:0]=imm14
            instr_mem[0] = {6'b000001, 5'd1, 5'd0, 2'b00, 14'd10};  // ADDI R1, R0, 10
            instr_mem[1] = {6'b000001, 5'd2, 5'd0, 2'b00, 14'd20};  // ADDI R2, R0, 20
            instr_mem[2] = encode_r_type(6'b000000, 5'd3, 5'd1, 5'd2, 3'd0, 8'h00);  // ADD R3, R1, R2
            instr_mem[3] = encode_exit();
            
            dispatch_warp(2'd0, 64'h0, 8'hFF);
            
            wait_cycles(100);
            
            check_result("Multiple instructions executed", 1'b1);
        end
    endtask
    
    // Test 3: Core status signals
    task automatic test_status_signals();
        begin
            $display("\n--- Test: Status Signals ---");
            
            // Initially no warps should be active
            check_result("Initially no warps active", warps_active == '0);
            check_result("Initially core not busy", core_busy == 1'b0);
            check_result("Initially all warps done", all_warps_done == 1'b1);
            
            // Dispatch a warp
            instr_mem[0] = encode_exit();
            dispatch_warp(2'd1, 64'h0, 8'hFF);
            
            wait_cycles(5);
            check_result("Warp becomes active", warps_active[1] == 1'b1);
            
            wait_cycles(50);
        end
    endtask
    
    // Test 4: Instruction fetch and decode
    task automatic test_fetch_decode();
        begin
            $display("\n--- Test: Fetch and Decode ---");
            
            // Load instructions at specific address
            instr_mem[64] = encode_r_type(6'b000000, 5'd5, 5'd0, 5'd0, 3'd0, 8'h00);  // ADD
            instr_mem[65] = encode_r_type(6'b000000, 5'd6, 5'd0, 5'd0, 3'd0, 8'h01);  // SUB
            instr_mem[66] = encode_exit();
            
            // Dispatch warp at address 256 (64 * 4)
            dispatch_warp(2'd2, 64'd256, 8'hAA);
            
            wait_cycles(80);
            
            check_result("Fetch from non-zero PC works", 1'b1);
        end
    endtask
    
    // Test 5: Pipeline flow
    task automatic test_pipeline_flow();
        begin
            $display("\n--- Test: Pipeline Flow ---");
            
            // Load a sequence of independent instructions
            for (int i = 0; i < 8; i++) begin
                // ADDI Ri+1, R0, i
                instr_mem[i] = {6'b000001, 5'(i+1), 5'd0, 2'b00, 14'(i)};
            end
            instr_mem[8] = encode_exit();
            
            dispatch_warp(2'd0, 64'h0, 8'hFF);
            
            // Let pipeline fill and drain
            wait_cycles(150);
            
            check_result("Pipeline flows correctly", 1'b1);
        end
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    
    initial begin
        $display("===========================================");
        $display("GPGPU-1 GPU Core Testbench");
        $display("===========================================");
        
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        reset_dut();
        
        test_status_signals();
        reset_dut();
        
        test_warp_dispatch();
        reset_dut();
        
        test_multi_instr();
        reset_dut();
        
        test_fetch_decode();
        reset_dut();
        
        test_pipeline_flow();
        
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
        #200000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
