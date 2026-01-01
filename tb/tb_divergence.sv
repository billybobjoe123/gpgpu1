//=============================================================================
// GPGPU-1 Divergence Test Testbench
//=============================================================================
// File:        tb_divergence.sv
// Description: End-to-end testbench for control flow divergence handling.
//              Loads actual assembled programs and verifies computed results.
// Version:     1.0
//=============================================================================

`timescale 1ns/1ps

`include "gpgpu_defines.svh"

module tb_divergence;
    import gpgpu_pkg::*;

    //=========================================================================
    // Parameters
    //=========================================================================
    
    parameter int NUM_CORES       = 1;      // Single core for predictable testing
    parameter int WARPS_PER_CORE  = 4;
    parameter int ICACHE_SIZE     = 4096;
    parameter int SHARED_MEM_SIZE = 16384;
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
    
    // Memory model (16KB - enough for our tests)
    logic [511:0] memory [0:255];  // 512-bit words, 256 entries = 16KB
    
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
        .NUM_CORES(NUM_CORES),
        .WARPS_PER_CORE(WARPS_PER_CORE),
        .ICACHE_SIZE(ICACHE_SIZE),
        .SHARED_MEM_SIZE(SHARED_MEM_SIZE)
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
            if (axi_rvalid && axi_rready) begin
                if (axi_rlast) begin
                    axi_rvalid <= 1'b0;
                    mem_rd_pending <= 1'b0;
                end else begin
                    mem_rd_beat <= mem_rd_beat + 1;
                    mem_rd_addr <= mem_rd_addr + 64;
                    axi_rdata <= memory[(mem_rd_addr + 64) >> 6];
                    axi_rlast <= (mem_rd_beat + 1 >= mem_rd_len);
                end
            end
            
            if (axi_arvalid && axi_arready && !mem_rd_pending) begin
                mem_rd_pending  <= 1'b1;
                mem_rd_addr     <= axi_araddr;
                mem_rd_id       <= axi_arid;
                mem_rd_len      <= axi_arlen;
                mem_rd_beat     <= '0;
                mem_rd_latency  <= 3'd2;  // 2 cycle latency
            end
            
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
            if (axi_bvalid && axi_bready) begin
                axi_bvalid <= 1'b0;
                mem_wr_pending <= 1'b0;
                mem_wr_addr_done <= 1'b0;
                mem_wr_data_done <= 1'b0;
            end
            
            if (axi_awvalid && axi_awready) begin
                mem_wr_addr <= axi_awaddr;
                mem_wr_id <= axi_awid;
                mem_wr_addr_done <= 1'b1;
                mem_wr_pending <= 1'b1;
            end
            
            if (axi_wvalid && axi_wready && axi_wlast) begin
                mem_wr_data_done <= 1'b1;
                for (int b = 0; b < 64; b++) begin
                    if (axi_wstrb[b]) begin
                        memory[mem_wr_addr >> 6][b*8 +: 8] <= axi_wdata[b*8 +: 8];
                    end
                end
            end
            
            if (mem_wr_addr_done && mem_wr_data_done && !axi_bvalid) begin
                axi_bvalid <= 1'b1;
                axi_bresp <= 2'b00;
                axi_bid <= mem_wr_id;
            end
        end
    end
    
    assign axi_awready = !mem_wr_pending;
    assign axi_wready  = mem_wr_pending && mem_wr_addr_done && !mem_wr_data_done;
    
    //=========================================================================
    // Test Helper Tasks
    //=========================================================================
    
    task automatic reset_dut();
        rst_n <= 1'b0;
        cmd_valid <= 1'b0;
        cmd_opcode <= CMD_NOP;
        cmd_pc <= '0;
        cmd_grid_dim_x <= 1;
        cmd_grid_dim_y <= 1;
        cmd_grid_dim_z <= 1;
        cmd_block_dim_x <= 8;
        cmd_block_dim_y <= 1;
        cmd_block_dim_z <= 1;
        
        for (int i = 0; i < 256; i++) begin
            memory[i] = '0;
        end
        
        repeat(10) @(posedge clk);
        rst_n <= 1'b1;
        repeat(5) @(posedge clk);
    endtask
    
    task automatic launch_kernel(
        input logic [ADDR_WIDTH-1:0] pc,
        input int grid_x, grid_y, grid_z,
        input int block_x, block_y, block_z
    );
        @(posedge clk);
        wait(cmd_ready);
        cmd_valid <= 1'b1;
        cmd_opcode <= CMD_LAUNCH;
        cmd_pc <= pc;
        cmd_grid_dim_x <= grid_x;
        cmd_grid_dim_y <= grid_y;
        cmd_grid_dim_z <= grid_z;
        cmd_block_dim_x <= block_x;
        cmd_block_dim_y <= block_y;
        cmd_block_dim_z <= block_z;
        @(posedge clk);
        cmd_valid <= 1'b0;
    endtask
    
    task automatic wait_for_done();
        int timeout;
        timeout = 0;
        while (!gpu_done && timeout < 10000) begin
            @(posedge clk);
            timeout++;
        end
        if (timeout >= 10000) begin
            $display("[ERROR] Timeout waiting for kernel completion!");
        end
    endtask
    
    task automatic check_result(input string test_name, input logic condition);
        test_count++;
        if (condition) begin
            pass_count++;
            $display("[PASS] %s", test_name);
        end else begin
            fail_count++;
            $display("[FAIL] %s", test_name);
        end
    endtask
    
    // Load a program into memory at the specified base address
    // program_data is an array of 32-bit instructions
    task automatic load_program(
        input logic [ADDR_WIDTH-1:0] base_addr,
        input logic [31:0] program_data[],
        input int size
    );
        int word_idx, instr_pos;
        for (int i = 0; i < size; i++) begin
            word_idx = (base_addr >> 6) + (i / 16);  // 16 instructions per 512-bit word
            instr_pos = (i % 16) * 32;
            memory[word_idx][instr_pos +: 32] = program_data[i];
        end
    endtask
    
    // Read a 64-bit value from memory
    function automatic logic [63:0] read_mem64(input logic [ADDR_WIDTH-1:0] addr);
        int word_idx, byte_pos;
        word_idx = addr >> 6;
        byte_pos = (addr & 6'h3F) * 8;
        read_mem64 = memory[word_idx][byte_pos +: 64];
    endfunction
    
    //=========================================================================
    // Divergence Test Program
    //=========================================================================
    // Assembled from programs/divergence_test.asm:
    // if (tid < 4) { R5 = 100; } else { R5 = 200; }
    // R6 = R5 + tid;
    // store result at 0x400 + tid*8
    //
    // Expected results:
    //   tid 0: 100 + 0 = 100
    //   tid 1: 100 + 1 = 101
    //   tid 2: 100 + 2 = 102
    //   tid 3: 100 + 3 = 103
    //   tid 4: 200 + 4 = 204
    //   tid 5: 200 + 5 = 205
    //   tid 6: 200 + 6 = 206
    //   tid 7: 200 + 7 = 207
    
    logic [31:0] divergence_program [0:14];
    initial begin
        divergence_program[0]  = 32'h6c200000;  // MOVSR R1, SR_TID
        divergence_program[1]  = 32'h68400004;  // MOVI R2, 4
        divergence_program[2]  = 32'h18211002;  // SLT P1, R1, R2
        divergence_program[3]  = 32'h58002000;  // PUSH P1
        divergence_program[4]  = 32'h68a00064;  // MOVI R5, 100
        divergence_program[5]  = 32'h60000000;  // ELSE
        divergence_program[6]  = 32'h68a000c8;  // MOVI R5, 200
        divergence_program[7]  = 32'h5c000000;  // POP
        divergence_program[8]  = 32'h00c50800;  // ADD R6, R5, R1
        divergence_program[9]  = 32'h69400008;  // MOVI R10, 8
        divergence_program[10] = 32'h09415000;  // MUL R10, R1, R10
        divergence_program[11] = 32'h69600400;  // MOVI R11, 0x400
        divergence_program[12] = 32'h016b5000;  // ADD R11, R11, R10
        divergence_program[13] = 32'h30cb0000;  // ST R6, 0(R11)
        divergence_program[14] = 32'h50000000;  // EXIT
    end
    
    //=========================================================================
    // Test Sequence
    //=========================================================================
    
    initial begin
        $display("===========================================");
        $display("GPGPU-1 Divergence Test Testbench");
        $display("===========================================");
        
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        //=====================================================================
        // Test 1: Basic Divergence (PUSH/ELSE/POP)
        //=====================================================================
        $display("\n--- Test 1: Basic PUSH/ELSE/POP Divergence ---");
        
        reset_dut();
        
        // Load program at address 0
        for (int i = 0; i < 15; i++) begin
            memory[i / 16][(i % 16) * 32 +: 32] = divergence_program[i];
        end
        
        // Launch kernel with 8 threads (1 warp)
        launch_kernel(64'h0, 1, 1, 1, 8, 1, 1);
        
        check_result("GPU becomes busy", gpu_busy);
        
        wait_for_done();
        
        check_result("Kernel completes", gpu_done);
        
        // Check results at 0x400 (memory word index = 0x400/64 = 16)
        // Each thread stores its result at 0x400 + tid * 8
        begin
            logic [63:0] result;
            logic [63:0] expected;
            
            for (int tid = 0; tid < 8; tid++) begin
                // Calculate memory location
                // Address: 0x400 + tid*8
                // Word index: (0x400 + tid*8) / 64
                // Byte offset within word: (0x400 + tid*8) % 64
                int addr = 64'h400 + tid * 8;
                int word_idx = addr >> 6;
                int byte_offset = addr & 6'h3F;
                
                result = memory[word_idx][(byte_offset * 8) +: 64];
                
                if (tid < 4) begin
                    expected = 100 + tid;
                end else begin
                    expected = 200 + tid;
                end
                
                check_result($sformatf("Thread %0d result: expected %0d, got %0d", 
                    tid, expected, result), result == expected);
            end
        end
        
        //=====================================================================
        // Test Summary
        //=====================================================================
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
            $display("*** %0d TESTS FAILED ***", fail_count);
        end
        
        $finish;
    end
    
    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    
    initial begin
        #200000;  // 200us timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
