//=============================================================================
// GPGPU-1 Performance Counters Testbench
//=============================================================================

`include "gpgpu_defines.svh"

module tb_performance_counters;
    import gpgpu_pkg::*;
    
    //=========================================================================
    // Parameters
    //=========================================================================
    localparam int NUM_CORES     = 4;
    localparam int NUM_COUNTERS  = 32;
    localparam int COUNTER_WIDTH = 48;
    
    //=========================================================================
    // Clock and Reset
    //=========================================================================
    logic clk;
    logic rst_n;
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    //=========================================================================
    // DUT Signals
    //=========================================================================
    
    // Control
    logic                    enable;
    logic                    clear;
    logic [4:0]              read_select;
    logic [63:0]             read_data;
    
    // Global events
    logic                    gpu_busy;
    logic [NUM_CORES-1:0]    cores_active;
    
    // Per-core events
    logic [NUM_CORES-1:0]    core_instr_valid;
    logic [NUM_CORES-1:0]    core_instr_is_alu;
    logic [NUM_CORES-1:0]    core_instr_is_fpu;
    logic [NUM_CORES-1:0]    core_instr_is_mem;
    logic [NUM_CORES-1:0]    core_instr_is_branch;
    logic [NUM_CORES-1:0]    core_instr_is_shuffle;
    logic [NUM_CORES-1:0]    core_instr_is_atomic;
    logic [NUM_CORES-1:0]    core_branch_taken;
    logic [NUM_CORES-1:0]    core_branch_divergent;
    logic [NUM_CORES-1:0]    core_stall_fetch;
    logic [NUM_CORES-1:0]    core_stall_decode;
    logic [NUM_CORES-1:0]    core_stall_operand;
    logic [NUM_CORES-1:0]    core_stall_execute;
    logic [NUM_CORES-1:0]    core_stall_memory;
    logic [NUM_CORES-1:0]    core_stall_scoreboard;
    logic [NUM_CORES-1:0]    core_warp_at_barrier;
    
    // Memory events
    logic                    l2_hit;
    logic                    l2_miss;
    logic                    l2_writeback;
    logic                    mem_read;
    logic                    mem_write;
    logic                    mem_row_hit;
    logic                    mem_row_miss;
    
    // Atomic events
    logic                    atomic_issued;
    logic                    atomic_completed;
    logic                    atomic_retry;
    
    // FPU events
    logic                    fpu_sp_issued;
    logic                    fpu_dp_issued;
    logic                    fpu_div_issued;
    logic                    fpu_fma_issued;
    
    // Shuffle events
    logic                    shuffle_issued;
    logic                    shuffle_inactive;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    
    performance_counters #(
        .NUM_COUNTERS    (NUM_COUNTERS),
        .COUNTER_WIDTH   (COUNTER_WIDTH),
        .NUM_CORES       (NUM_CORES)
    ) dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        
        .enable               (enable),
        .clear                (clear),
        .read_select          (read_select),
        .read_data            (read_data),
        
        .gpu_busy             (gpu_busy),
        .cores_active         (cores_active),
        
        .core_instr_valid     (core_instr_valid),
        .core_instr_is_alu    (core_instr_is_alu),
        .core_instr_is_fpu    (core_instr_is_fpu),
        .core_instr_is_mem    (core_instr_is_mem),
        .core_instr_is_branch (core_instr_is_branch),
        .core_instr_is_shuffle(core_instr_is_shuffle),
        .core_instr_is_atomic (core_instr_is_atomic),
        
        .core_branch_taken    (core_branch_taken),
        .core_branch_divergent(core_branch_divergent),
        
        .core_stall_fetch     (core_stall_fetch),
        .core_stall_decode    (core_stall_decode),
        .core_stall_operand   (core_stall_operand),
        .core_stall_execute   (core_stall_execute),
        .core_stall_memory    (core_stall_memory),
        .core_stall_scoreboard(core_stall_scoreboard),
        
        .core_warp_at_barrier (core_warp_at_barrier),
        
        .l2_hit               (l2_hit),
        .l2_miss              (l2_miss),
        .l2_writeback         (l2_writeback),
        
        .mem_read             (mem_read),
        .mem_write            (mem_write),
        .mem_row_hit          (mem_row_hit),
        .mem_row_miss         (mem_row_miss),
        
        .atomic_issued        (atomic_issued),
        .atomic_completed     (atomic_completed),
        .atomic_retry         (atomic_retry),
        
        .fpu_sp_issued        (fpu_sp_issued),
        .fpu_dp_issued        (fpu_dp_issued),
        .fpu_div_issued       (fpu_div_issued),
        .fpu_fma_issued       (fpu_fma_issued),
        
        .shuffle_issued       (shuffle_issued),
        .shuffle_inactive     (shuffle_inactive)
    );
    
    //=========================================================================
    // Counter Indices
    //=========================================================================
    localparam CTR_CYCLES            = 5'd0;
    localparam CTR_BUSY_CYCLES       = 5'd1;
    localparam CTR_IDLE_CYCLES       = 5'd2;
    localparam CTR_STALL_CYCLES      = 5'd3;
    localparam CTR_INSTR_RETIRED     = 5'd4;
    localparam CTR_INSTR_ALU         = 5'd5;
    localparam CTR_INSTR_FPU         = 5'd6;
    localparam CTR_INSTR_MEM         = 5'd7;
    localparam CTR_INSTR_BRANCH      = 5'd8;
    localparam CTR_INSTR_SHUFFLE     = 5'd9;
    localparam CTR_INSTR_ATOMIC      = 5'd10;
    localparam CTR_BRANCH_TAKEN      = 5'd11;
    localparam CTR_BRANCH_DIVERGENT  = 5'd12;
    localparam CTR_L2_HITS           = 5'd13;
    localparam CTR_L2_MISSES         = 5'd14;
    localparam CTR_L2_WRITEBACKS     = 5'd15;
    localparam CTR_MEM_READS         = 5'd16;
    localparam CTR_MEM_WRITES        = 5'd17;
    localparam CTR_MEM_ROW_HITS      = 5'd18;
    localparam CTR_MEM_ROW_MISSES    = 5'd19;
    localparam CTR_STALL_FETCH       = 5'd20;
    localparam CTR_FPU_SP_OPS        = 5'd27;
    localparam CTR_FPU_DP_OPS        = 5'd28;
    localparam CTR_FPU_FMA_OPS       = 5'd30;
    localparam CTR_ATOMIC_RETRIES    = 5'd31;
    
    //=========================================================================
    // Test Variables
    //=========================================================================
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    
    //=========================================================================
    // Helper Tasks
    //=========================================================================
    
    task reset_dut();
        rst_n = 0;
        enable = 0;
        clear = 0;
        read_select = 0;
        gpu_busy = 0;
        cores_active = 0;
        core_instr_valid = 0;
        core_instr_is_alu = 0;
        core_instr_is_fpu = 0;
        core_instr_is_mem = 0;
        core_instr_is_branch = 0;
        core_instr_is_shuffle = 0;
        core_instr_is_atomic = 0;
        core_branch_taken = 0;
        core_branch_divergent = 0;
        core_stall_fetch = 0;
        core_stall_decode = 0;
        core_stall_operand = 0;
        core_stall_execute = 0;
        core_stall_memory = 0;
        core_stall_scoreboard = 0;
        core_warp_at_barrier = 0;
        l2_hit = 0;
        l2_miss = 0;
        l2_writeback = 0;
        mem_read = 0;
        mem_write = 0;
        mem_row_hit = 0;
        mem_row_miss = 0;
        atomic_issued = 0;
        atomic_completed = 0;
        atomic_retry = 0;
        fpu_sp_issued = 0;
        fpu_dp_issued = 0;
        fpu_div_issued = 0;
        fpu_fma_issued = 0;
        shuffle_issued = 0;
        shuffle_inactive = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask
    
    function automatic logic [63:0] read_counter(input logic [4:0] idx);
        read_select = idx;
        return read_data;
    endfunction
    
    task check(input string name, input logic [63:0] expected, input logic [63:0] actual);
        test_count++;
        if (expected == actual) begin
            $display("[PASS] %s: expected=%0d, got=%0d", name, expected, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s: expected=%0d, got=%0d", name, expected, actual);
            fail_count++;
        end
    endtask
    
    //=========================================================================
    // Test Cases
    //=========================================================================
    
    initial begin
        $display("===========================================");
        $display("Performance Counters Testbench");
        $display("===========================================");
        
        //---------------------------------------------------------------------
        // Test 1: Reset clears all counters
        //---------------------------------------------------------------------
        $display("\n--- Test 1: Reset ---");
        reset_dut();
        
        read_select = CTR_CYCLES;
        @(posedge clk);
        check("Cycles after reset", 0, read_data);
        
        read_select = CTR_INSTR_RETIRED;
        @(posedge clk);
        check("Instructions after reset", 0, read_data);
        
        //---------------------------------------------------------------------
        // Test 2: Cycle counting when enabled and busy
        //---------------------------------------------------------------------
        $display("\n--- Test 2: Cycle Counting ---");
        enable = 1;
        gpu_busy = 1;
        
        repeat(10) @(posedge clk);
        
        // Wait an extra cycle to let read_data settle after read_select change
        read_select = CTR_CYCLES;
        @(posedge clk);
        // Account for cycles during test setup and this read
        check("Total cycles >= 10", 1, (read_data >= 10) ? 1 : 0);
        
        read_select = CTR_BUSY_CYCLES;
        @(posedge clk);
        check("Busy cycles >= 10", 1, (read_data >= 10) ? 1 : 0);
        
        read_select = CTR_IDLE_CYCLES;
        @(posedge clk);
        check("Idle cycles", 0, read_data);
        
        //---------------------------------------------------------------------
        // Test 3: Instruction counting
        //---------------------------------------------------------------------
        $display("\n--- Test 3: Instruction Counting ---");
        
        // Clear counters first
        clear = 1;
        @(posedge clk);
        clear = 0;
        @(posedge clk);
        
        // Retire 1 instruction from core 0 (ALU)
        core_instr_valid = 4'b0001;
        core_instr_is_alu = 4'b0001;
        @(posedge clk);
        
        // Retire 2 instructions from cores 0 and 1 (FPU)
        core_instr_valid = 4'b0011;
        core_instr_is_alu = 4'b0000;
        core_instr_is_fpu = 4'b0011;
        @(posedge clk);
        
        // Retire 4 instructions from all cores (MEM)
        core_instr_valid = 4'b1111;
        core_instr_is_fpu = 4'b0000;
        core_instr_is_mem = 4'b1111;
        @(posedge clk);
        
        core_instr_valid = 4'b0000;
        core_instr_is_mem = 4'b0000;
        @(posedge clk);
        
        read_select = CTR_INSTR_RETIRED;
        @(posedge clk);
        check("Total instructions retired", 7, read_data);
        
        read_select = CTR_INSTR_ALU;
        @(posedge clk);
        check("ALU instructions", 1, read_data);
        
        read_select = CTR_INSTR_FPU;
        @(posedge clk);
        check("FPU instructions", 2, read_data);
        
        read_select = CTR_INSTR_MEM;
        @(posedge clk);
        check("MEM instructions", 4, read_data);
        
        //---------------------------------------------------------------------
        // Test 4: L2 Cache counters
        //---------------------------------------------------------------------
        $display("\n--- Test 4: L2 Cache Counters ---");
        
        clear = 1;
        @(posedge clk);
        clear = 0;
        @(posedge clk);
        
        // Generate some cache events
        repeat(5) begin
            l2_hit = 1;
            @(posedge clk);
        end
        l2_hit = 0;
        
        repeat(2) begin
            l2_miss = 1;
            @(posedge clk);
        end
        l2_miss = 0;
        
        l2_writeback = 1;
        @(posedge clk);
        l2_writeback = 0;
        @(posedge clk);
        
        read_select = CTR_L2_HITS;
        @(posedge clk);
        check("L2 hits", 5, read_data);
        
        read_select = CTR_L2_MISSES;
        @(posedge clk);
        check("L2 misses", 2, read_data);
        
        read_select = CTR_L2_WRITEBACKS;
        @(posedge clk);
        check("L2 writebacks", 1, read_data);
        
        //---------------------------------------------------------------------
        // Test 5: FPU operation counters
        //---------------------------------------------------------------------
        $display("\n--- Test 5: FPU Operation Counters ---");
        
        clear = 1;
        @(posedge clk);
        clear = 0;
        @(posedge clk);
        
        // SP operations
        repeat(10) begin
            fpu_sp_issued = 1;
            @(posedge clk);
        end
        fpu_sp_issued = 0;
        
        // DP operations
        repeat(5) begin
            fpu_dp_issued = 1;
            @(posedge clk);
        end
        fpu_dp_issued = 0;
        
        // FMA operations
        repeat(3) begin
            fpu_fma_issued = 1;
            @(posedge clk);
        end
        fpu_fma_issued = 0;
        @(posedge clk);
        
        read_select = CTR_FPU_SP_OPS;
        @(posedge clk);
        check("FPU SP operations", 10, read_data);
        
        read_select = CTR_FPU_DP_OPS;
        @(posedge clk);
        check("FPU DP operations", 5, read_data);
        
        read_select = CTR_FPU_FMA_OPS;
        @(posedge clk);
        check("FPU FMA operations", 3, read_data);
        
        //---------------------------------------------------------------------
        // Test 6: Stall cycle counting
        //---------------------------------------------------------------------
        $display("\n--- Test 6: Stall Cycles ---");
        
        clear = 1;
        @(posedge clk);
        clear = 0;
        @(posedge clk);
        
        // Stall from core 0 for 3 cycles
        core_stall_fetch = 4'b0001;
        repeat(3) @(posedge clk);
        core_stall_fetch = 0;
        
        // Stall from cores 0 and 1 for 2 cycles
        core_stall_memory = 4'b0011;
        repeat(2) @(posedge clk);
        core_stall_memory = 0;
        @(posedge clk);
        
        read_select = CTR_STALL_CYCLES;
        @(posedge clk);
        check("Total stall cycles", 5, read_data);
        
        read_select = CTR_STALL_FETCH;
        @(posedge clk);
        check("Fetch stall cycles", 3, read_data);  // 3 cycles * 1 core
        
        //---------------------------------------------------------------------
        // Test 7: Clear functionality
        //---------------------------------------------------------------------
        $display("\n--- Test 7: Clear Functionality ---");
        
        // Counters should have values from previous tests
        read_select = CTR_CYCLES;
        @(posedge clk);
        assert(read_data > 0) else $error("Cycles should be > 0 before clear");
        
        clear = 1;
        @(posedge clk);
        clear = 0;
        @(posedge clk);
        
        read_select = CTR_CYCLES;
        @(posedge clk);
        // After clear, we have 1-2 cycles elapsed
        check("Cycles after clear <= 3", 1, (read_data <= 3) ? 1 : 0);
        
        //---------------------------------------------------------------------
        // Test 8: Enable/disable
        //---------------------------------------------------------------------
        $display("\n--- Test 8: Enable/Disable ---");
        
        clear = 1;
        @(posedge clk);
        clear = 0;
        @(posedge clk);
        
        enable = 0;  // Disable counting
        repeat(10) @(posedge clk);
        
        read_select = CTR_CYCLES;
        @(posedge clk);
        check("Cycles when disabled", 1, read_data);  // Should not increment
        
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
    
    // Timeout
    initial begin
        #100000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
