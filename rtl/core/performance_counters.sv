//=============================================================================
// GPGPU-1 Performance Counter Unit
//=============================================================================
// File:        performance_counters.sv
// Description: Comprehensive performance monitoring unit that tracks:
//              - Cycle counts (total, busy, stall, idle)
//              - Instruction counts (by type, retired, issued)
//              - Memory statistics (loads, stores, cache hits/misses)
//              - Warp statistics (active, divergent, barriers)
//              - Pipeline stall reasons
//              - FPU utilization
// Version:     1.0
// Date:        January 1, 2026
//=============================================================================

`include "gpgpu_defines.svh"

module performance_counters
    import gpgpu_pkg::*;
#(
    parameter int NUM_COUNTERS    = 32,
    parameter int COUNTER_WIDTH   = 48,  // 48-bit counters (good for hours of operation)
    parameter int NUM_CORES       = 4
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    //=========================================================================
    // Control Interface
    //=========================================================================
    input  logic                    enable,          // Global enable
    input  logic                    clear,           // Clear all counters
    input  logic [4:0]              read_select,     // Counter to read
    output logic [63:0]             read_data,       // Counter value (zero-extended)
    
    //=========================================================================
    // Global Events
    //=========================================================================
    input  logic                    gpu_busy,        // GPU is executing
    input  logic [NUM_CORES-1:0]    cores_active,    // Active cores bitmap
    
    //=========================================================================
    // Per-Core Events (from aggregated core signals)
    //=========================================================================
    input  logic [NUM_CORES-1:0]    core_instr_valid,     // Instruction retired
    input  logic [NUM_CORES-1:0]    core_instr_is_alu,    // ALU instruction
    input  logic [NUM_CORES-1:0]    core_instr_is_fpu,    // FPU instruction
    input  logic [NUM_CORES-1:0]    core_instr_is_mem,    // Memory instruction
    input  logic [NUM_CORES-1:0]    core_instr_is_branch, // Branch instruction
    input  logic [NUM_CORES-1:0]    core_instr_is_shuffle,// Shuffle instruction
    input  logic [NUM_CORES-1:0]    core_instr_is_atomic, // Atomic instruction
    
    input  logic [NUM_CORES-1:0]    core_branch_taken,    // Branch taken
    input  logic [NUM_CORES-1:0]    core_branch_divergent,// Divergent branch
    
    input  logic [NUM_CORES-1:0]    core_stall_fetch,     // Fetch stage stall
    input  logic [NUM_CORES-1:0]    core_stall_decode,    // Decode stage stall
    input  logic [NUM_CORES-1:0]    core_stall_operand,   // Operand fetch stall
    input  logic [NUM_CORES-1:0]    core_stall_execute,   // Execute stage stall
    input  logic [NUM_CORES-1:0]    core_stall_memory,    // Memory stage stall
    input  logic [NUM_CORES-1:0]    core_stall_scoreboard,// Scoreboard stall
    
    input  logic [NUM_CORES-1:0]    core_warp_at_barrier, // Warp waiting at barrier
    
    //=========================================================================
    // Memory Events
    //=========================================================================
    input  logic                    l2_hit,
    input  logic                    l2_miss,
    input  logic                    l2_writeback,
    
    input  logic                    mem_read,
    input  logic                    mem_write,
    input  logic                    mem_row_hit,
    input  logic                    mem_row_miss,
    
    //=========================================================================
    // Atomic Events
    //=========================================================================
    input  logic                    atomic_issued,
    input  logic                    atomic_completed,
    input  logic                    atomic_retry,      // Atomic had to retry (contention)
    
    //=========================================================================
    // FPU Events
    //=========================================================================
    input  logic                    fpu_sp_issued,     // Single-precision op
    input  logic                    fpu_dp_issued,     // Double-precision op
    input  logic                    fpu_div_issued,    // Division/sqrt (slow)
    input  logic                    fpu_fma_issued,    // FMA operation
    
    //=========================================================================
    // Shuffle Events
    //=========================================================================
    input  logic                    shuffle_issued,
    input  logic                    shuffle_inactive    // Shuffle with inactive lanes
);

    //=========================================================================
    // Counter Indices (match to defines in gpgpu_defines.svh)
    //=========================================================================
    localparam CTR_CYCLES            = 5'd0;   // Total cycles
    localparam CTR_BUSY_CYCLES       = 5'd1;   // GPU busy cycles
    localparam CTR_IDLE_CYCLES       = 5'd2;   // GPU idle cycles
    localparam CTR_STALL_CYCLES      = 5'd3;   // Total stall cycles (any core)
    
    localparam CTR_INSTR_RETIRED     = 5'd4;   // Total instructions retired
    localparam CTR_INSTR_ALU         = 5'd5;   // ALU instructions
    localparam CTR_INSTR_FPU         = 5'd6;   // FPU instructions
    localparam CTR_INSTR_MEM         = 5'd7;   // Memory instructions
    localparam CTR_INSTR_BRANCH      = 5'd8;   // Branch instructions
    localparam CTR_INSTR_SHUFFLE     = 5'd9;   // Shuffle instructions
    localparam CTR_INSTR_ATOMIC      = 5'd10;  // Atomic instructions
    
    localparam CTR_BRANCH_TAKEN      = 5'd11;  // Branches taken
    localparam CTR_BRANCH_DIVERGENT  = 5'd12;  // Divergent branches
    
    localparam CTR_L2_HITS           = 5'd13;  // L2 cache hits
    localparam CTR_L2_MISSES         = 5'd14;  // L2 cache misses
    localparam CTR_L2_WRITEBACKS     = 5'd15;  // L2 writebacks
    
    localparam CTR_MEM_READS         = 5'd16;  // Memory controller reads
    localparam CTR_MEM_WRITES        = 5'd17;  // Memory controller writes
    localparam CTR_MEM_ROW_HITS      = 5'd18;  // DRAM row hits
    localparam CTR_MEM_ROW_MISSES    = 5'd19;  // DRAM row misses
    
    localparam CTR_STALL_FETCH       = 5'd20;  // Fetch stall cycles
    localparam CTR_STALL_DECODE      = 5'd21;  // Decode stall cycles
    localparam CTR_STALL_OPERAND     = 5'd22;  // Operand stall cycles
    localparam CTR_STALL_EXECUTE     = 5'd23;  // Execute stall cycles
    localparam CTR_STALL_MEMORY      = 5'd24;  // Memory stall cycles
    localparam CTR_STALL_SCOREBOARD  = 5'd25;  // Scoreboard stall cycles
    
    localparam CTR_WARP_BARRIER_WAIT = 5'd26;  // Warp-cycles at barriers
    
    localparam CTR_FPU_SP_OPS        = 5'd27;  // Single precision FP ops
    localparam CTR_FPU_DP_OPS        = 5'd28;  // Double precision FP ops
    localparam CTR_FPU_DIV_OPS       = 5'd29;  // FP divides/sqrts
    localparam CTR_FPU_FMA_OPS       = 5'd30;  // FMA operations
    
    localparam CTR_ATOMIC_RETRIES    = 5'd31;  // Atomic retries (contention)
    
    //=========================================================================
    // Counter Storage
    //=========================================================================
    logic [COUNTER_WIDTH-1:0] counters [NUM_COUNTERS];
    
    //=========================================================================
    // Counter Update Logic
    //=========================================================================
    
    // Helper: count set bits (popcount) for aggregating across cores
    function automatic logic [$clog2(NUM_CORES+1)-1:0] popcount(input logic [NUM_CORES-1:0] v);
        popcount = '0;
        for (int i = 0; i < NUM_CORES; i++) begin
            popcount = popcount + v[i];
        end
    endfunction
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_COUNTERS; i++) begin
                counters[i] <= '0;
            end
        end else if (clear) begin
            for (int i = 0; i < NUM_COUNTERS; i++) begin
                counters[i] <= '0;
            end
        end else if (enable) begin
            // =================================================================
            // Cycle Counters
            // =================================================================
            
            // Total cycles (always increments when enabled)
            counters[CTR_CYCLES] <= counters[CTR_CYCLES] + 1;
            
            // Busy/idle cycles
            if (gpu_busy) begin
                counters[CTR_BUSY_CYCLES] <= counters[CTR_BUSY_CYCLES] + 1;
            end else begin
                counters[CTR_IDLE_CYCLES] <= counters[CTR_IDLE_CYCLES] + 1;
            end
            
            // Total stall cycles (any core stalling)
            if ((|core_stall_fetch) || (|core_stall_decode) || 
                (|core_stall_operand) || (|core_stall_execute) ||
                (|core_stall_memory) || (|core_stall_scoreboard)) begin
                counters[CTR_STALL_CYCLES] <= counters[CTR_STALL_CYCLES] + 1;
            end
            
            // =================================================================
            // Instruction Counters
            // =================================================================
            
            // Total instructions retired (sum across cores)
            counters[CTR_INSTR_RETIRED] <= counters[CTR_INSTR_RETIRED] + 
                                           popcount(core_instr_valid);
            
            // By type
            counters[CTR_INSTR_ALU] <= counters[CTR_INSTR_ALU] + 
                                       popcount(core_instr_valid & core_instr_is_alu);
            counters[CTR_INSTR_FPU] <= counters[CTR_INSTR_FPU] + 
                                       popcount(core_instr_valid & core_instr_is_fpu);
            counters[CTR_INSTR_MEM] <= counters[CTR_INSTR_MEM] + 
                                       popcount(core_instr_valid & core_instr_is_mem);
            counters[CTR_INSTR_BRANCH] <= counters[CTR_INSTR_BRANCH] + 
                                          popcount(core_instr_valid & core_instr_is_branch);
            counters[CTR_INSTR_SHUFFLE] <= counters[CTR_INSTR_SHUFFLE] + 
                                           popcount(core_instr_valid & core_instr_is_shuffle);
            counters[CTR_INSTR_ATOMIC] <= counters[CTR_INSTR_ATOMIC] + 
                                          popcount(core_instr_valid & core_instr_is_atomic);
            
            // =================================================================
            // Branch Counters
            // =================================================================
            
            counters[CTR_BRANCH_TAKEN] <= counters[CTR_BRANCH_TAKEN] + 
                                          popcount(core_branch_taken);
            counters[CTR_BRANCH_DIVERGENT] <= counters[CTR_BRANCH_DIVERGENT] + 
                                              popcount(core_branch_divergent);
            
            // =================================================================
            // L2 Cache Counters
            // =================================================================
            
            if (l2_hit)
                counters[CTR_L2_HITS] <= counters[CTR_L2_HITS] + 1;
            if (l2_miss)
                counters[CTR_L2_MISSES] <= counters[CTR_L2_MISSES] + 1;
            if (l2_writeback)
                counters[CTR_L2_WRITEBACKS] <= counters[CTR_L2_WRITEBACKS] + 1;
            
            // =================================================================
            // Memory Controller Counters
            // =================================================================
            
            if (mem_read)
                counters[CTR_MEM_READS] <= counters[CTR_MEM_READS] + 1;
            if (mem_write)
                counters[CTR_MEM_WRITES] <= counters[CTR_MEM_WRITES] + 1;
            if (mem_row_hit)
                counters[CTR_MEM_ROW_HITS] <= counters[CTR_MEM_ROW_HITS] + 1;
            if (mem_row_miss)
                counters[CTR_MEM_ROW_MISSES] <= counters[CTR_MEM_ROW_MISSES] + 1;
            
            // =================================================================
            // Per-Stage Stall Counters
            // =================================================================
            
            counters[CTR_STALL_FETCH] <= counters[CTR_STALL_FETCH] + 
                                         popcount(core_stall_fetch);
            counters[CTR_STALL_DECODE] <= counters[CTR_STALL_DECODE] + 
                                          popcount(core_stall_decode);
            counters[CTR_STALL_OPERAND] <= counters[CTR_STALL_OPERAND] + 
                                           popcount(core_stall_operand);
            counters[CTR_STALL_EXECUTE] <= counters[CTR_STALL_EXECUTE] + 
                                           popcount(core_stall_execute);
            counters[CTR_STALL_MEMORY] <= counters[CTR_STALL_MEMORY] + 
                                          popcount(core_stall_memory);
            counters[CTR_STALL_SCOREBOARD] <= counters[CTR_STALL_SCOREBOARD] + 
                                              popcount(core_stall_scoreboard);
            
            // =================================================================
            // Warp Barrier Waiting
            // =================================================================
            
            counters[CTR_WARP_BARRIER_WAIT] <= counters[CTR_WARP_BARRIER_WAIT] + 
                                               popcount(core_warp_at_barrier);
            
            // =================================================================
            // FPU Counters
            // =================================================================
            
            if (fpu_sp_issued)
                counters[CTR_FPU_SP_OPS] <= counters[CTR_FPU_SP_OPS] + 1;
            if (fpu_dp_issued)
                counters[CTR_FPU_DP_OPS] <= counters[CTR_FPU_DP_OPS] + 1;
            if (fpu_div_issued)
                counters[CTR_FPU_DIV_OPS] <= counters[CTR_FPU_DIV_OPS] + 1;
            if (fpu_fma_issued)
                counters[CTR_FPU_FMA_OPS] <= counters[CTR_FPU_FMA_OPS] + 1;
            
            // =================================================================
            // Atomic Retry Counter
            // =================================================================
            
            if (atomic_retry)
                counters[CTR_ATOMIC_RETRIES] <= counters[CTR_ATOMIC_RETRIES] + 1;
        end
    end
    
    //=========================================================================
    // Counter Read Logic
    //=========================================================================
    
    always_comb begin
        if (read_select < NUM_COUNTERS) begin
            read_data = {{(64-COUNTER_WIDTH){1'b0}}, counters[read_select]};
        end else begin
            read_data = '0;
        end
    end
    
    //=========================================================================
    // Derived Metrics (computed from counters)
    //=========================================================================
    
    // These are available for external monitoring
    logic [COUNTER_WIDTH-1:0] ipc_numerator;    // Instructions per cycle numerator
    logic [COUNTER_WIDTH-1:0] l2_hit_rate;      // L2 hit rate (0-100 scaled)
    logic [COUNTER_WIDTH-1:0] mem_row_hit_rate; // Memory row hit rate (0-100)
    
    always_comb begin
        // IPC = instructions / cycles (scaled by 1000 for fixed point)
        if (counters[CTR_CYCLES] != 0) begin
            ipc_numerator = (counters[CTR_INSTR_RETIRED] * 1000) / counters[CTR_CYCLES];
        end else begin
            ipc_numerator = 0;
        end
        
        // L2 hit rate = hits / (hits + misses) * 100
        if ((counters[CTR_L2_HITS] + counters[CTR_L2_MISSES]) != 0) begin
            l2_hit_rate = (counters[CTR_L2_HITS] * 100) / 
                          (counters[CTR_L2_HITS] + counters[CTR_L2_MISSES]);
        end else begin
            l2_hit_rate = 0;
        end
        
        // Memory row hit rate
        if ((counters[CTR_MEM_ROW_HITS] + counters[CTR_MEM_ROW_MISSES]) != 0) begin
            mem_row_hit_rate = (counters[CTR_MEM_ROW_HITS] * 100) / 
                               (counters[CTR_MEM_ROW_HITS] + counters[CTR_MEM_ROW_MISSES]);
        end else begin
            mem_row_hit_rate = 0;
        end
    end

endmodule
