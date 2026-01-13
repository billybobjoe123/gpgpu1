//=============================================================================
// GPGPU-1 GPU Top Testbench
//=============================================================================
// File:        tb_gpu_top.sv
// Description: Testbench for the multi-core GPU top-level module.
//              Tests kernel dispatch, multi-core execution, and memory access.
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_gpu_top;
    import gpgpu_pkg::*;

    //=========================================================================
    // Parameters
    //=========================================================================
    
    parameter int P_NUM_CORES       = 4;
    parameter int P_WARPS_PER_CORE  = 4;
    parameter int P_ICACHE_SIZE     = 4096;
    parameter int P_SHARED_MEM_SIZE = 16384;
    parameter int CLK_PERIOD      = 10;
    
    //=========================================================================
    // Signals
    //=========================================================================
    
    logic                    clk;
    logic                    rst_n;
    
    // Command interface
    logic                    cmd_valid;
    logic                    cmd_ready;
    logic [3:0]              cmd_opcode;
    logic [ADDR_WIDTH-1:0]   cmd_pc;
    logic [31:0]             cmd_grid_dim_x;
    logic [31:0]             cmd_grid_dim_y;
    logic [31:0]             cmd_grid_dim_z;
    logic [15:0]             cmd_block_dim_x;
    logic [15:0]             cmd_block_dim_y;
    logic [15:0]             cmd_block_dim_z;
    
    // AXI interface
    logic                    axi_arvalid;
    logic                    axi_arready;
    logic [ADDR_WIDTH-1:0]   axi_araddr;
    logic [7:0]              axi_arlen;
    logic [2:0]              axi_arsize;
    logic [1:0]              axi_arburst;
    logic [3:0]              axi_arid;
    
    logic                    axi_rvalid;
    logic                    axi_rready;
    logic [511:0]            axi_rdata;
    logic [1:0]              axi_rresp;
    logic                    axi_rlast;
    logic [3:0]              axi_rid;
    
    logic                    axi_awvalid;
    logic                    axi_awready;
    logic [ADDR_WIDTH-1:0]   axi_awaddr;
    logic [7:0]              axi_awlen;
    logic [2:0]              axi_awsize;
    logic [1:0]              axi_awburst;
    logic [3:0]              axi_awid;
    
    logic                    axi_wvalid;
    logic                    axi_wready;
    logic [511:0]            axi_wdata;
    logic [63:0]             axi_wstrb;
    logic                    axi_wlast;
    
    logic                    axi_bvalid;
    logic                    axi_bready;
    logic [1:0]              axi_bresp;
    logic [3:0]              axi_bid;
    
    // Status
    logic                    gpu_busy;
    logic                    gpu_done;
    logic [NUM_CORES-1:0]    cores_active;
    logic [31:0]             perf_cycle_count;
    logic [31:0]             perf_instr_count;
    
    //=========================================================================
    // Test Variables
    //=========================================================================
    
    int test_count;
    int pass_count;
    int fail_count;
    
    // Memory model (1MB)
    logic [511:0] memory [0:2047];  // 512-bit words, 2K entries = 1MB
    
    //=========================================================================
    // Command Opcodes
    //=========================================================================
    
    localparam CMD_NOP    = 4'h0;
    localparam CMD_LAUNCH = 4'h1;
    localparam CMD_SYNC   = 4'h2;
    localparam CMD_RESET  = 4'hF;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    
    gpu_top #(
        .P_NUM_CORES(P_NUM_CORES),
        .P_WARPS_PER_CORE(P_WARPS_PER_CORE),
        .P_ICACHE_SIZE(P_ICACHE_SIZE),
        .P_SHARED_MEM_SIZE(P_SHARED_MEM_SIZE)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        
        .cmd_valid        (cmd_valid),
        .cmd_ready        (cmd_ready),
        .cmd_opcode       (cmd_opcode),
        .cmd_pc           (cmd_pc),
        .cmd_grid_dim_x   (cmd_grid_dim_x),
        .cmd_grid_dim_y   (cmd_grid_dim_y),
        .cmd_grid_dim_z   (cmd_grid_dim_z),
        .cmd_block_dim_x  (cmd_block_dim_x),
        .cmd_block_dim_y  (cmd_block_dim_y),
        .cmd_block_dim_z  (cmd_block_dim_z),
        
        .axi_arvalid      (axi_arvalid),
        .axi_arready      (axi_arready),
        .axi_araddr       (axi_araddr),
        .axi_arlen        (axi_arlen),
        .axi_arsize       (axi_arsize),
        .axi_arburst      (axi_arburst),
        .axi_arid         (axi_arid),
        
        .axi_rvalid       (axi_rvalid),
        .axi_rready       (axi_rready),
        .axi_rdata        (axi_rdata),
        .axi_rresp        (axi_rresp),
        .axi_rlast        (axi_rlast),
        .axi_rid          (axi_rid),
        
        .axi_awvalid      (axi_awvalid),
        .axi_awready      (axi_awready),
        .axi_awaddr       (axi_awaddr),
        .axi_awlen        (axi_awlen),
        .axi_awsize       (axi_awsize),
        .axi_awburst      (axi_awburst),
        .axi_awid         (axi_awid),
        
        .axi_wvalid       (axi_wvalid),
        .axi_wready       (axi_wready),
        .axi_wdata        (axi_wdata),
        .axi_wstrb        (axi_wstrb),
        .axi_wlast        (axi_wlast),
        
        .axi_bvalid       (axi_bvalid),
        .axi_bready       (axi_bready),
        .axi_bresp        (axi_bresp),
        .axi_bid          (axi_bid),
        
        .gpu_busy         (gpu_busy),
        .gpu_done         (gpu_done),
        .cores_active     (cores_active),
        .perf_cycle_count (perf_cycle_count),
        .perf_instr_count (perf_instr_count)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // AXI Memory Model
    //=========================================================================
    
    logic [2:0]            mem_rd_latency;
    logic                  mem_rd_pending;
    logic [ADDR_WIDTH-1:0] mem_rd_addr;
    logic [3:0]            mem_rd_id;
    logic [7:0]            mem_rd_len;
    logic [7:0]            mem_rd_beat;
    
    // Read channel
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_rvalid      <= 1'b0;
            axi_rdata       <= '0;
            axi_rresp       <= 2'b00;
            axi_rlast       <= 1'b0;
            axi_rid         <= '0;
            mem_rd_pending  <= 1'b0;
            mem_rd_latency  <= '0;
            mem_rd_addr     <= '0;
            mem_rd_id       <= '0;
            mem_rd_len      <= '0;
            mem_rd_beat     <= '0;
        end else begin
            // Default: deassert valid after handshake
            if (axi_rvalid && axi_rready) begin
                if (axi_rlast) begin
                    axi_rvalid <= 1'b0;
                    mem_rd_pending <= 1'b0;
                end else begin
                    // Next beat
                    mem_rd_beat <= mem_rd_beat + 1;
                    mem_rd_addr <= mem_rd_addr + 64;  // 512 bits = 64 bytes
                    axi_rdata <= memory[(mem_rd_addr + 64) >> 6];
                    axi_rlast <= (mem_rd_beat + 1 >= mem_rd_len);
                end
            end
            
            // Accept new request
            if (axi_arvalid && axi_arready && !mem_rd_pending) begin
                mem_rd_pending  <= 1'b1;
                mem_rd_addr     <= axi_araddr;
                mem_rd_id       <= axi_arid;
                mem_rd_len      <= axi_arlen;
                mem_rd_beat     <= '0;
                mem_rd_latency  <= 3'd3;  // 3 cycle latency
            end              // Count down latency
            if (mem_rd_pending && !axi_rvalid) begin
                if (mem_rd_latency == 0) begin
                    axi_rvalid <= 1'b1;
                    axi_rdata  <= memory[mem_rd_addr >> 6];
                    axi_rresp  <= 2'b00;
                    axi_rid    <= mem_rd_id;
                    axi_rlast  <= (mem_rd_len == 0);
                end else begin
                    mem_rd_latency <= mem_rd_latency - 1;
                end
            end
        end
    end
    
    assign axi_arready = !mem_rd_pending;
    
    // Write channel
    logic                  mem_wr_pending;
    logic [ADDR_WIDTH-1:0] mem_wr_addr;
    logic [3:0]            mem_wr_id;
    logic                  mem_wr_addr_done;
    logic                  mem_wr_data_done;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_bvalid      <= 1'b0;
            axi_bresp       <= 2'b00;
            axi_bid         <= '0;
            mem_wr_pending  <= 1'b0;
            mem_wr_addr     <= '0;
            mem_wr_id       <= '0;
            mem_wr_addr_done <= 1'b0;
            mem_wr_data_done <= 1'b0;
        end else begin
            // Clear bvalid after handshake
            if (axi_bvalid && axi_bready) begin
                axi_bvalid <= 1'b0;
                mem_wr_pending <= 1'b0;
                mem_wr_addr_done <= 1'b0;
                mem_wr_data_done <= 1'b0;
            end
            
            // Address phase
            if (axi_awvalid && axi_awready) begin
                mem_wr_addr <= axi_awaddr;
                mem_wr_id <= axi_awid;
                mem_wr_addr_done <= 1'b1;
                mem_wr_pending <= 1'b1;
            end
            
            // Data phase
            if (axi_wvalid && axi_wready && axi_wlast) begin
                mem_wr_data_done <= 1'b1;
                // Write to memory with byte strobes
                for (int b = 0; b < 64; b++) begin
                    if (axi_wstrb[b]) begin
                        memory[mem_wr_addr >> 6][b*8 +: 8] <= axi_wdata[b*8 +: 8];
                    end
                end
            end
            
            // Response phase
            if (mem_wr_addr_done && mem_wr_data_done && !axi_bvalid) begin
                axi_bvalid <= 1'b1;
                axi_bresp <= 2'b00;
                axi_bid <= mem_wr_id;
            end
        end
    end
    
    assign axi_awready = !mem_wr_pending;
    assign axi_wready = mem_wr_addr_done && !mem_wr_data_done;
    
    //=========================================================================
    // Test Tasks
    //=========================================================================
    
    task automatic reset_dut();
        begin
            rst_n = 0;
            cmd_valid = 0;
            cmd_opcode = CMD_NOP;
            cmd_pc = '0;
            cmd_grid_dim_x = 1;
            cmd_grid_dim_y = 1;
            cmd_grid_dim_z = 1;
            cmd_block_dim_x = WARP_SIZE;
            cmd_block_dim_y = 1;
            cmd_block_dim_z = 1;
            
            // Clear memory
            for (int i = 0; i < 2048; i++) begin
                memory[i] = '0;
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
      task automatic launch_kernel(
        input logic [ADDR_WIDTH-1:0] pc,
        input logic [31:0] grid_x,
        input logic [31:0] grid_y,
        input logic [31:0] grid_z,
        input logic [15:0] block_x,
        input logic [15:0] block_y,
        input logic [15:0] block_z
    );
        begin
            // Wait for dispatch unit to be ready first
            while (!cmd_ready) @(posedge clk);
            
            // Set up command
            cmd_valid = 1;
            cmd_opcode = CMD_LAUNCH;
            cmd_pc = pc;
            cmd_grid_dim_x = grid_x;
            cmd_grid_dim_y = grid_y;
            cmd_grid_dim_z = grid_z;
            cmd_block_dim_x = block_x;
            cmd_block_dim_y = block_y;
            cmd_block_dim_z = block_z;
            
            // Handshake: wait one cycle for valid && ready
            @(posedge clk);
            // Now deassert valid
            cmd_valid = 0;
            @(posedge clk);
        end
    endtask
    
    task automatic wait_for_done();
        begin
            int timeout;
            timeout = 0;
            while (!gpu_done && timeout < 10000) begin
                @(posedge clk);
                timeout++;
            end
            if (timeout >= 10000) begin
                $display("WARNING: Timeout waiting for gpu_done");
            end
        end
    endtask
    
    //=========================================================================
    // Instruction Encoding Helpers
    //=========================================================================
    
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
    
    function automatic logic [31:0] encode_exit();
        encode_exit = {6'b010100, 26'b0};  // OP_EXIT
    endfunction
    
    // Load instructions into memory (8 instructions per 512-bit word)
    // Using fixed-size array to avoid Verilator dynamic array issues
    task automatic load_program_fixed(
        input logic [ADDR_WIDTH-1:0] base_addr,
        input logic [31:0] instr0,
        input logic [31:0] instr1,
        input logic [31:0] instr2,
        input logic [31:0] instr3,
        input int program_size
    );
        logic [31:0] program_data[4];
        begin
            program_data[0] = instr0;
            program_data[1] = instr1;
            program_data[2] = instr2;
            program_data[3] = instr3;
            
            for (int i = 0; i < program_size && i < 4; i++) begin
                int word_idx = (base_addr >> 6) + (i / 16);
                int instr_pos = (i % 16) * 32;
                memory[word_idx][instr_pos +: 32] = program_data[i];
            end
        end
    endtask
    
    //=========================================================================
    // Test Cases
    //=========================================================================
    
    // Test 1: Initial state
    task automatic test_initial_state();
        begin
            $display("\n--- Test: Initial State ---");
            
            check_result("GPU not busy initially", gpu_busy == 1'b0);
            check_result("Command ready initially", cmd_ready == 1'b1);
            check_result("No cores active initially", cores_active == '0);
        end
    endtask    // Test 2: Single block kernel launch
    task automatic test_single_block_launch();
        begin
            $display("\n--- Test: Single Block Kernel Launch ---");
            
            // Simple program: just EXIT
            load_program_fixed(64'h0, encode_exit(), 32'h0, 32'h0, 32'h0, 2);
            
            launch_kernel(64'h0, 1, 1, 1, WARP_SIZE, 1, 1);
            
            check_result("GPU becomes busy after launch", gpu_busy == 1'b1);
            
            wait_for_done();
            
            check_result("Kernel completes", gpu_done == 1'b1);
        end
    endtask
      // Test 3: Multi-block kernel launch
    task automatic test_multi_block_launch();
        begin
            $display("\n--- Test: Multi-Block Kernel Launch ---");
            
            load_program_fixed(64'h0, encode_exit(), 32'h0, 32'h0, 32'h0, 2);
            
            // Launch with 4 blocks (one per core)
            launch_kernel(64'h0, 4, 1, 1, WARP_SIZE, 1, 1);
            
            check_result("GPU busy for multi-block", gpu_busy == 1'b1);
            
            wait_for_done();
            
            check_result("Multi-block kernel completes", gpu_done == 1'b1);
        end
    endtask
    
    // Test 4: Performance counter
    task automatic test_perf_counter();
        logic [31:0] start_cycles;
        begin
            $display("\n--- Test: Performance Counter ---");
            
            // Longer program
            load_program_fixed(64'h0, 
                encode_r_type(6'b000000, 5'd1, 5'd0, 5'd0, 3'd0, 8'h00),  // ADD
                encode_r_type(6'b000000, 5'd2, 5'd0, 5'd0, 3'd0, 8'h00),  // ADD
                encode_exit(),
                32'h0,
                4);
            
            start_cycles = perf_cycle_count;
            
            launch_kernel(64'h0, 1, 1, 1, WARP_SIZE, 1, 1);
            
            wait_for_done();
            
            check_result("Cycle counter incremented", perf_cycle_count > start_cycles);
            $display("Cycles elapsed: %0d", perf_cycle_count - start_cycles);
        end
    endtask
      // Test 5: Memory arbiter
    task automatic test_memory_arbiter();
        begin
            $display("\n--- Test: Memory Arbiter ---");
            
            load_program_fixed(64'h0, encode_exit(), 32'h0, 32'h0, 32'h0, 2);
            
            // Launch multiple blocks to test arbiter
            launch_kernel(64'h0, NUM_CORES, 1, 1, WARP_SIZE, 1, 1);
            
            wait_for_done();
            
            check_result("All cores completed through arbiter", gpu_done == 1'b1);
        end
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    
    initial begin
        $display("===========================================");
        $display("GPGPU-1 GPU Top Testbench");
        $display("===========================================");
        $display("Configuration:");
        $display("  NUM_CORES:       %0d", NUM_CORES);
        $display("  WARPS_PER_CORE:  %0d", WARPS_PER_CORE);
        $display("  WARP_SIZE:       %0d", WARP_SIZE);
        $display("===========================================");
        
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        reset_dut();
        
        test_initial_state();
        
        reset_dut();
        test_single_block_launch();
        
        reset_dut();
        test_multi_block_launch();
        
        reset_dut();
        test_perf_counter();
        
        reset_dut();
        test_memory_arbiter();
        
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
        #500000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
