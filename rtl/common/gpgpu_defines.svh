//=============================================================================
// GPGPU-1 Defines - Preprocessor Macros and Constants
//=============================================================================
// File:        gpgpu_defines.svh
// Description: Preprocessor macros, compile-time constants, and synthesis
//              pragmas for the GPGPU-1 architecture.
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`ifndef GPGPU_DEFINES_SVH
`define GPGPU_DEFINES_SVH

//=============================================================================
// Simulation vs Synthesis
//=============================================================================

`ifdef SIMULATION
    `define SIM_ONLY(x) x
    `define SYNTH_ONLY(x)
`else
    `define SIM_ONLY(x)
    `define SYNTH_ONLY(x) x
`endif

//=============================================================================
// Debug and Assertions
//=============================================================================

`ifdef DEBUG
    `define DEBUG_PRINT(msg) $display("[DEBUG] %0t: %s", $time, msg)
    `define DEBUG_PRINTF(fmt, args) $display("[DEBUG] %0t: " fmt, $time, args)
`else
    `define DEBUG_PRINT(msg)
    `define DEBUG_PRINTF(fmt, args)
`endif

// Assertion macros
`ifdef ENABLE_ASSERTIONS
    `define ASSERT(cond, msg) \
        assert (cond) else $error("[ASSERT FAIL] %0t: %s", $time, msg)
    `define ASSERT_NEVER(cond, msg) \
        assert property (@(posedge clk) !(cond)) else $error("[ASSERT NEVER] %0t: %s", $time, msg)
`else
    `define ASSERT(cond, msg)
    `define ASSERT_NEVER(cond, msg)
`endif

//=============================================================================
// Instruction Field Extraction Macros
//=============================================================================

// Primary opcode [31:26]
`define INST_OPCODE(inst)    inst[31:26]

// Format R fields
`define INST_RD(inst)        inst[25:21]
`define INST_RS1(inst)       inst[20:16]
`define INST_RS2(inst)       inst[15:11]
`define INST_PRED_R(inst)    inst[10:8]
`define INST_FUNC(inst)      inst[7:0]

// Format I fields
`define INST_IMM16(inst)     inst[15:0]

// Format L fields (Load/Store)
`define INST_PRED_L(inst)    inst[15:13]
`define INST_OFFSET13(inst)  inst[12:0]

// Format B fields (Branch)
`define INST_PRED_B(inst)    inst[25:23]
`define INST_COND(inst)      inst[22:20]
`define INST_OFFSET20(inst)  inst[19:0]

// Format S fields (Special)
`define INST_SR(inst)        inst[20:16]

// Format M fields (Mask/Divergence)
`define INST_PRED_M(inst)    inst[15:13]
`define INST_FUNC13(inst)    inst[12:0]

// Shift immediate encoding
`define INST_SHIFTI_FUNC(inst) inst[15:14]
`define INST_SHAMT(inst)       inst[13:8]

// ALU immediate encoding
`define INST_ALUI_FUNC(inst)   inst[15:14]
`define INST_IMM14(inst)       inst[13:0]

//=============================================================================
// Register File Constants
//=============================================================================

// R0 is hardwired to zero
`define ZERO_REG    5'd0

// P0 is hardwired to true
`define TRUE_PRED   3'd0

//=============================================================================
// Memory Constants
//=============================================================================

// Memory alignment requirements
`define ALIGN_64BIT     3'b111    // 8-byte alignment mask
`define ALIGN_32BIT     3'b011    // 4-byte alignment mask

// Address space boundaries (example configuration)
`define GLOBAL_MEM_BASE     64'h0000_0000_0000_0000
`define GLOBAL_MEM_END      64'h0000_0000_FFFF_FFFF
`define SHARED_MEM_BASE     64'h0000_0001_0000_0000
`define SHARED_MEM_END      64'h0000_0001_0000_3FFF
`define IO_SPACE_BASE       64'h0000_0002_0000_0000
`define IO_SPACE_END        64'h0000_0002_0000_FFFF

// Address space detection
`define IS_GLOBAL_ADDR(addr)  (addr >= `GLOBAL_MEM_BASE && addr <= `GLOBAL_MEM_END)
`define IS_SHARED_ADDR(addr)  (addr >= `SHARED_MEM_BASE && addr <= `SHARED_MEM_END)
`define IS_IO_ADDR(addr)      (addr >= `IO_SPACE_BASE && addr <= `IO_SPACE_END)

//=============================================================================
// Pipeline Constants
//=============================================================================

// Pipeline stage count
`define NUM_PIPELINE_STAGES  6

// Stall conditions
`define STALL_NONE      3'b000
`define STALL_ICACHE    3'b001
`define STALL_DCACHE    3'b010
`define STALL_HAZARD    3'b011
`define STALL_BARRIER   3'b100

//=============================================================================
// Barrier Constants
//=============================================================================

`define NUM_BARRIERS    16
`define BARRIER_ID_BITS 4

//=============================================================================
// AXI Interface Constants
//=============================================================================

// AXI response codes
`define AXI_RESP_OKAY    2'b00
`define AXI_RESP_EXOKAY  2'b01
`define AXI_RESP_SLVERR  2'b10
`define AXI_RESP_DECERR  2'b11

// AXI burst types
`define AXI_BURST_FIXED  2'b00
`define AXI_BURST_INCR   2'b01
`define AXI_BURST_WRAP   2'b10

// AXI sizes (for 64-bit data width)
`define AXI_SIZE_8       3'b011   // 8 bytes = 64 bits

//=============================================================================
// Performance Counter Events
//=============================================================================

`define PERF_CYCLES              0
`define PERF_INSTRUCTIONS        1
`define PERF_BRANCHES            2
`define PERF_BRANCHES_TAKEN      3
`define PERF_LOADS               4
`define PERF_STORES              5
`define PERF_ICACHE_HITS         6
`define PERF_ICACHE_MISSES       7
`define PERF_DCACHE_HITS         8
`define PERF_DCACHE_MISSES       9
`define PERF_STALL_CYCLES       10
`define PERF_DIVERGENT_WARPS    11

//=============================================================================
// Error Codes
//=============================================================================

`define ERR_NONE                 4'h0
`define ERR_ILLEGAL_INSTR        4'h1
`define ERR_MISALIGNED_ADDR      4'h2
`define ERR_MASK_STACK_OVERFLOW  4'h3
`define ERR_MASK_STACK_UNDERFLOW 4'h4
`define ERR_RET_STACK_OVERFLOW   4'h5
`define ERR_RET_STACK_UNDERFLOW  4'h6
`define ERR_DIV_BY_ZERO          4'h7
`define ERR_BUS_ERROR            4'h8

//=============================================================================
// Synthesis Pragmas
//=============================================================================

// Parallel case - for synthesis optimization
`define PARALLEL_CASE (* parallel_case *)

// Full case - when all cases are covered
`define FULL_CASE (* full_case *)

// Don't optimize - prevent logic optimization
`define DONT_TOUCH (* dont_touch = "true" *)

// Keep hierarchy
`define KEEP_HIERARCHY (* keep_hierarchy = "yes" *)

// RAM style
`define RAM_BLOCK (* ram_style = "block" *)
`define RAM_DISTRIBUTED (* ram_style = "distributed" *)

// Register balancing
`define REG_BALANCE (* register_balancing = "yes" *)

//=============================================================================
// Utility Macros
//=============================================================================

// Maximum of two values
`define MAX(a, b) ((a) > (b) ? (a) : (b))

// Minimum of two values
`define MIN(a, b) ((a) < (b) ? (a) : (b))

// Ceiling of log2
`define CLOG2(x) $clog2(x)

// Generate range
`define RANGE(high, low) high:low

// Bit selection with width
`define BITS(signal, start, width) signal[start +: width]

//=============================================================================
// Testbench Utilities
//=============================================================================

`ifdef SIMULATION

// Wait for clock cycles
`define WAIT_CYCLES(n) repeat(n) @(posedge clk)

// Wait for reset to complete
`define WAIT_RESET begin \
    @(negedge rst_n); \
    @(posedge rst_n); \
    @(posedge clk); \
end

// Random delay
`define RANDOM_DELAY(min, max) \
    repeat($urandom_range(max, min)) @(posedge clk)

// Assert with timeout
`define ASSERT_TIMEOUT(cond, timeout, msg) begin \
    integer _timeout_count = 0; \
    while (!(cond) && _timeout_count < timeout) begin \
        @(posedge clk); \
        _timeout_count = _timeout_count + 1; \
    end \
    if (_timeout_count >= timeout) $error("[TIMEOUT] %s", msg); \
end

`endif // SIMULATION

`endif // GPGPU_DEFINES_SVH
