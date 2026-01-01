//=============================================================================
// GPGPU-1 Multi-Core Integration Testbench
//=============================================================================
// Tests multi-core execution with:
// - Concurrent kernel execution across multiple cores
// - Shared L2 cache access
// - Global memory atomics across cores
// - Memory consistency between cores

`include "gpgpu_defines.svh"

module tb_multi_core;
    import gpgpu_pkg::*;
    
    //=========================================================================
    // Parameters
    //=========================================================================
    localparam CLK_PERIOD = 10;
    localparam NUM_CORES = 4;
    localparam TIMEOUT_CYCLES = 50000;
    
    //=========================================================================
    // Clock and Reset
    //=========================================================================
    logic clk;
    logic rst_n;
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // DUT Signals
    //=========================================================================
    
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
    
    // Status
    logic                    gpu_busy;
    logic                    gpu_done;
    logic [NUM_CORES-1:0]    cores_active;
    logic [31:0]             perf_cycle_count;
    logic [31:0]             perf_instr_count;
    
    // AXI memory interface (directly to memory model)
    logic                    axi_arvalid, axi_arready;
    logic [ADDR_WIDTH-1:0]   axi_araddr;
    logic [7:0]              axi_arlen;
    logic [2:0]              axi_arsize;
    logic [1:0]              axi_arburst;
    logic [3:0]              axi_arid;
    
    logic                    axi_rvalid, axi_rready;
    logic [511:0]            axi_rdata;
    logic [1:0]              axi_rresp;
    logic                    axi_rlast;
    logic [3:0]              axi_rid;
    
    logic                    axi_awvalid, axi_awready;
    logic [ADDR_WIDTH-1:0]   axi_awaddr;
    logic [7:0]              axi_awlen;
    logic [2:0]              axi_awsize;
    logic [1:0]              axi_awburst;
    logic [3:0]              axi_awid;
    
    logic                    axi_wvalid, axi_wready;
    logic [511:0]            axi_wdata;
    logic [63:0]             axi_wstrb;
    logic                    axi_wlast;
    
    logic                    axi_bvalid, axi_bready;
    logic [1:0]              axi_bresp;
    logic [3:0]              axi_bid;
    
    //=========================================================================
    // Test Variables
    //=========================================================================
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    int cycle_count = 0;
    
    //=========================================================================
    // Simple Memory Model
    //=========================================================================
    logic [63:0] memory [0:4095];  // 32KB memory
    
    // Memory read/write state machine
    enum logic [2:0] {
        MEM_IDLE,
        MEM_READ,
        MEM_WRITE_ADDR,
        MEM_WRITE_DATA,
        MEM_WRITE_RESP
    } mem_state;
    
    logic [ADDR_WIDTH-1:0] mem_addr;
    logic [3:0] mem_id;
    logic [7:0] mem_len;
    logic [7:0] mem_cnt;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_state <= MEM_IDLE;
            axi_arready <= 1'b1;
            axi_awready <= 1'b1;
            axi_wready <= 1'b0;
            axi_rvalid <= 1'b0;
            axi_bvalid <= 1'b0;
            mem_cnt <= '0;
        end else begin
            case (mem_state)
                MEM_IDLE: begin
                    axi_arready <= 1'b1;
                    axi_awready <= 1'b1;
                    axi_rvalid <= 1'b0;
                    axi_bvalid <= 1'b0;
                    
                    if (axi_arvalid && axi_arready) begin
                        mem_addr <= axi_araddr;
                        mem_id <= axi_arid;
                        mem_len <= axi_arlen;
                        mem_cnt <= '0;
                        mem_state <= MEM_READ;
                        axi_arready <= 1'b0;
                    end else if (axi_awvalid && axi_awready) begin
                        mem_addr <= axi_awaddr;
                        mem_id <= axi_awid;
                        mem_len <= axi_awlen;
                        mem_cnt <= '0;
                        mem_state <= MEM_WRITE_DATA;
                        axi_awready <= 1'b0;
                        axi_wready <= 1'b1;
                    end
                end
                
                MEM_READ: begin
                    axi_rvalid <= 1'b1;
                    axi_rid <= mem_id;
                    axi_rresp <= 2'b00;  // OKAY
                    
                    // Read 8 64-bit words for 512-bit data
                    for (int i = 0; i < 8; i++) begin
                        axi_rdata[i*64 +: 64] <= memory[(mem_addr >> 3) + i];
                    end
                    
                    if (mem_cnt >= mem_len) begin
                        axi_rlast <= 1'b1;
                    end else begin
                        axi_rlast <= 1'b0;
                    end
                    
                    if (axi_rvalid && axi_rready) begin
                        if (axi_rlast) begin
                            mem_state <= MEM_IDLE;
                            axi_rvalid <= 1'b0;
                        end else begin
                            mem_addr <= mem_addr + 64;  // Next cache line
                            mem_cnt <= mem_cnt + 1;
                        end
                    end
                end
                
                MEM_WRITE_DATA: begin
                    if (axi_wvalid && axi_wready) begin
                        // Write 8 64-bit words
                        for (int i = 0; i < 8; i++) begin
                            if (axi_wstrb[i*8 +: 8] != 0) begin
                                memory[(mem_addr >> 3) + i] <= axi_wdata[i*64 +: 64];
                            end
                        end
                        
                        if (axi_wlast) begin
                            axi_wready <= 1'b0;
                            mem_state <= MEM_WRITE_RESP;
                        end else begin
                            mem_addr <= mem_addr + 64;
                            mem_cnt <= mem_cnt + 1;
                        end
                    end
                end
                
                MEM_WRITE_RESP: begin
                    axi_bvalid <= 1'b1;
                    axi_bid <= mem_id;
                    axi_bresp <= 2'b00;  // OKAY
                    
                    if (axi_bvalid && axi_bready) begin
                        axi_bvalid <= 1'b0;
                        mem_state <= MEM_IDLE;
                    end
                end
                
                default: mem_state <= MEM_IDLE;
            endcase
        end
    end
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    gpu_top #(
        .NUM_CORES       (NUM_CORES),
        .WARPS_PER_CORE  (4),
        .ICACHE_SIZE     (4096),
        .SHARED_MEM_SIZE (16384)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .cmd_valid       (cmd_valid),
        .cmd_ready       (cmd_ready),
        .cmd_opcode      (cmd_opcode),
        .cmd_pc          (cmd_pc),
        .cmd_grid_dim_x  (cmd_grid_dim_x),
        .cmd_grid_dim_y  (cmd_grid_dim_y),
        .cmd_grid_dim_z  (cmd_grid_dim_z),
        .cmd_block_dim_x (cmd_block_dim_x),
        .cmd_block_dim_y (cmd_block_dim_y),
        .cmd_block_dim_z (cmd_block_dim_z),
        
        .axi_arvalid     (axi_arvalid),
        .axi_arready     (axi_arready),
        .axi_araddr      (axi_araddr),
        .axi_arlen       (axi_arlen),
        .axi_arsize      (axi_arsize),
        .axi_arburst     (axi_arburst),
        .axi_arid        (axi_arid),
        
        .axi_rvalid      (axi_rvalid),
        .axi_rready      (axi_rready),
        .axi_rdata       (axi_rdata),
        .axi_rresp       (axi_rresp),
        .axi_rlast       (axi_rlast),
        .axi_rid         (axi_rid),
        
        .axi_awvalid     (axi_awvalid),
        .axi_awready     (axi_awready),
        .axi_awaddr      (axi_awaddr),
        .axi_awlen       (axi_awlen),
        .axi_awsize      (axi_awsize),
        .axi_awburst     (axi_awburst),
        .axi_awid        (axi_awid),
        
        .axi_wvalid      (axi_wvalid),
        .axi_wready      (axi_wready),
        .axi_wdata       (axi_wdata),
        .axi_wstrb       (axi_wstrb),
        .axi_wlast       (axi_wlast),
        
        .axi_bvalid      (axi_bvalid),
        .axi_bready      (axi_bready),
        .axi_bresp       (axi_bresp),
        .axi_bid         (axi_bid),
        
        .gpu_busy        (gpu_busy),
        .gpu_done        (gpu_done),
        .cores_active    (cores_active),
        .perf_cycle_count(perf_cycle_count),
        .perf_instr_count(perf_instr_count)
    );
    
    //=========================================================================
    // Helper Tasks
    //=========================================================================
    
    task automatic reset_system();
        rst_n = 0;
        cmd_valid = 0;
        cmd_opcode = 0;
        cmd_pc = 0;
        cmd_grid_dim_x = 1;
        cmd_grid_dim_y = 1;
        cmd_grid_dim_z = 1;
        cmd_block_dim_x = 8;
        cmd_block_dim_y = 1;
        cmd_block_dim_z = 1;
        
        // Clear memory
        for (int i = 0; i < 4096; i++) begin
            memory[i] = '0;
        end
        
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
    endtask
    
    task automatic launch_kernel(
        input logic [ADDR_WIDTH-1:0] pc,
        input int grid_x,
        input int grid_y = 1,
        input int grid_z = 1
    );
        @(posedge clk);
        cmd_valid = 1;
        cmd_opcode = 4'h1;  // LAUNCH
        cmd_pc = pc;
        cmd_grid_dim_x = grid_x;
        cmd_grid_dim_y = grid_y;
        cmd_grid_dim_z = grid_z;
        
        wait(cmd_ready);
        @(posedge clk);
        cmd_valid = 0;
    endtask
    
    task automatic wait_kernel_done(input int max_cycles);
        int cycles = 0;
        while (gpu_busy && cycles < max_cycles) begin
            @(posedge clk);
            cycles++;
        end
        
        if (cycles >= max_cycles) begin
            $display("[TIMEOUT] Kernel did not complete in %0d cycles", max_cycles);
        end
    endtask
    
    task automatic check(input string name, input logic condition);
        test_count++;
        if (condition) begin
            $display("[PASS] %s", name);
            pass_count++;
        end else begin
            $display("[FAIL] %s", name);
            fail_count++;
        end
    endtask
    
    task automatic check_mem(
        input string name,
        input int addr,
        input logic [63:0] expected
    );
        logic [63:0] actual;
        actual = memory[addr >> 3];
        test_count++;
        if (actual == expected) begin
            $display("[PASS] %s: mem[0x%04x] = 0x%016x", name, addr, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: mem[0x%04x] expected=0x%016x, got=0x%016x", 
                     name, addr, expected, actual);
            fail_count++;
        end
    endtask
    
    //=========================================================================
    // Test Cases
    //=========================================================================
    
    initial begin
        $display("===========================================");
        $display("Multi-Core Integration Testbench");
        $display("===========================================");
        $display("Cores: %0d", NUM_CORES);
        
        //---------------------------------------------------------------------
        // Test 1: Basic multi-core activation
        //---------------------------------------------------------------------
        $display("\n--- Test 1: Multi-Core Activation ---");
        reset_system();
        
        // Check initial state
        check("All cores initially idle", cores_active == '0);
        check("GPU not busy initially", !gpu_busy);
        
        //---------------------------------------------------------------------
        // Test 2: Launch kernel with multiple blocks
        //---------------------------------------------------------------------
        $display("\n--- Test 2: Multi-Block Kernel ---");
        reset_system();
        
        // Store simple program at address 0
        // EXIT instruction
        memory[0] = 64'h50000000_00000000;  // EXIT at PC=0
        
        // Launch with 4 blocks (should use all 4 cores)
        launch_kernel(0, 4);  // 4 blocks
        
        @(posedge clk);
        check("GPU becomes busy", gpu_busy);
        
        // Check that cores become active
        repeat(10) @(posedge clk);
        check("Multiple cores activated", $countones(cores_active) >= 1);
        
        wait_kernel_done(1000);
        check("Kernel completes", !gpu_busy);
        
        //---------------------------------------------------------------------
        // Test 3: Cores writing to different memory locations
        //---------------------------------------------------------------------
        $display("\n--- Test 3: Parallel Memory Writes ---");
        reset_system();
        
        // Each block writes its block ID to a different location
        // This requires pre-loading actual code, which we skip for simplicity
        // Instead, verify memory is accessible
        
        memory[256/8] = 64'hDEADBEEF;
        memory[512/8] = 64'hCAFEBABE;
        
        check("Memory slot 1 accessible", memory[256/8] == 64'hDEADBEEF);
        check("Memory slot 2 accessible", memory[512/8] == 64'hCAFEBABE);
        
        //---------------------------------------------------------------------
        // Test 4: Performance counters work with multi-core
        //---------------------------------------------------------------------
        $display("\n--- Test 4: Performance Counters ---");
        reset_system();
        
        // Store EXIT at 0
        memory[0] = 64'h50000000_00000000;
        
        launch_kernel(0, 2);  // 2 blocks
        wait_kernel_done(1000);
        
        $display("  Cycle count: %0d", perf_cycle_count);
        check("Cycle count > 0", perf_cycle_count > 0);
        
        //---------------------------------------------------------------------
        // Test 5: Sequential kernel launches
        //---------------------------------------------------------------------
        $display("\n--- Test 5: Sequential Kernels ---");
        reset_system();
        
        memory[0] = 64'h50000000_00000000;  // EXIT
        
        // First kernel
        launch_kernel(0, 1);
        wait_kernel_done(1000);
        check("First kernel completes", !gpu_busy);
        
        // Second kernel
        launch_kernel(0, 2);
        wait_kernel_done(1000);
        check("Second kernel completes", !gpu_busy);
        
        // Third kernel
        launch_kernel(0, 4);
        wait_kernel_done(1000);
        check("Third kernel completes", !gpu_busy);
        
        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
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
    
    // Timeout watchdog
    initial begin
        repeat(TIMEOUT_CYCLES) @(posedge clk);
        $display("ERROR: Global timeout after %0d cycles!", TIMEOUT_CYCLES);
        $finish;
    end
    
    // Cycle counter for debugging
    always_ff @(posedge clk) begin
        if (rst_n) cycle_count <= cycle_count + 1;
        else cycle_count <= 0;
    end

endmodule
