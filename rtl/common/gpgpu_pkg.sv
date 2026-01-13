//=============================================================================
// GPGPU-1 Package - Architectural Parameters and Type Definitions
//=============================================================================
// File:        gpgpu_pkg.sv
// Description: Central package containing all parameters, types, opcodes,
//              and function codes for the GPGPU-1 architecture.
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`ifndef GPGPU_PKG_SV
`define GPGPU_PKG_SV

package gpgpu_pkg;

    timeunit 1ns;
    timeprecision 1ps;

    //=========================================================================
    // Fixed Architectural Parameters
    //=========================================================================
    
    parameter int INST_WIDTH      = 32;    // Instruction width in bits
    parameter int DATA_WIDTH      = 64;    // Data path width in bits
    parameter int REG_WIDTH       = 64;    // Register width in bits
    parameter int WARP_SIZE       = 8;     // Number of threads per warp
    parameter int NUM_REGS        = 32;    // General-purpose registers per thread
    parameter int NUM_PRED        = 8;     // Predicate registers per thread
    parameter int ADDR_WIDTH      = 64;    // Address bus width
    
    // Derived parameters
    parameter int REG_ADDR_WIDTH  = $clog2(NUM_REGS);     // 5 bits
    parameter int PRED_ADDR_WIDTH = $clog2(NUM_PRED);     // 3 bits
    parameter int THREAD_ID_WIDTH = $clog2(WARP_SIZE);    // 3 bits
    
    //=========================================================================
    // Configurable Parameters (defaults)
    //=========================================================================
    
    parameter int NUM_CORES          = 4;     // Number of GPU cores
    parameter int WARPS_PER_CORE     = 4;     // Warps per core
    parameter int SHARED_MEM_SIZE    = 16384; // 16KB shared memory per core
    parameter int ICACHE_SIZE        = 4096;  // 4KB instruction cache per core
    parameter int MASK_STACK_DEPTH   = 8;     // Divergence mask stack depth
    parameter int RETURN_STACK_DEPTH = 8;     // Call return stack depth
    
    // Derived configurable parameters
    parameter int WARP_ID_WIDTH = $clog2(WARPS_PER_CORE);  // 2 bits for 4 warps
    parameter int CORE_ID_WIDTH = $clog2(NUM_CORES);        // 2 bits for 4 cores
    parameter int MASK_SP_WIDTH = $clog2(MASK_STACK_DEPTH); // 3 bits
    
    //=========================================================================
    // Instruction Field Widths
    //=========================================================================
    
    parameter int OPCODE_WIDTH   = 6;
    parameter int FUNC_WIDTH     = 8;
    parameter int FUNC13_WIDTH   = 13;
    parameter int IMM16_WIDTH    = 16;
    parameter int IMM14_WIDTH    = 14;
    parameter int IMM13_WIDTH    = 13;
    parameter int IMM20_WIDTH    = 20;
    parameter int SHAMT_WIDTH    = 6;
    parameter int COND_WIDTH     = 3;
    
    //=========================================================================
    // Primary Opcodes (6 bits)
    //=========================================================================
    
    typedef enum logic [OPCODE_WIDTH-1:0] {
        // Integer ALU Operations
        OP_ALU      = 6'b000000,  // 0x00: Register-Register ALU
        OP_ALUI     = 6'b000001,  // 0x01: ALU with Immediate
        OP_MUL      = 6'b000010,  // 0x02: Multiply operations
        OP_MULI     = 6'b000011,  // 0x03: Multiply with Immediate
        OP_SHIFT    = 6'b000100,  // 0x04: Shift/Rotate operations
        OP_SHIFTI   = 6'b000101,  // 0x05: Shift with Immediate
        OP_CMP      = 6'b000110,  // 0x06: Compare (set predicate)
        OP_CMPI     = 6'b000111,  // 0x07: Compare with Immediate
        
        // Memory Operations
        OP_LD       = 6'b001000,  // 0x08: Load 64-bit global
        OP_LD32     = 6'b001001,  // 0x09: Load 32-bit unsigned global
        OP_LD32S    = 6'b001010,  // 0x0A: Load 32-bit signed global
        OP_LDS      = 6'b001011,  // 0x0B: Load 64-bit shared
        OP_ST       = 6'b001100,  // 0x0C: Store 64-bit global
        OP_ST32     = 6'b001101,  // 0x0D: Store 32-bit global
        OP_STS      = 6'b001110,  // 0x0E: Store 64-bit shared
        OP_LDS32    = 6'b001111,  // 0x0F: Load 32-bit shared
        
        // Control Flow
        OP_BRA      = 6'b010000,  // 0x10: Branch Always
        OP_BRC      = 6'b010001,  // 0x11: Branch Conditional
        OP_CALL     = 6'b010010,  // 0x12: Call Subroutine
        OP_RET      = 6'b010011,  // 0x13: Return
        OP_EXIT     = 6'b010100,  // 0x14: Thread/Warp Exit
        
        // Synchronization and Divergence
        OP_BAR      = 6'b010101,  // 0x15: Barrier
        OP_PUSH     = 6'b010110,  // 0x16: Push Mask
        OP_POP      = 6'b010111,  // 0x17: Pop Mask
        OP_ELSE     = 6'b011000,  // 0x18: Else (switch mask)
        OP_VOTE     = 6'b011001,  // 0x19: Warp Voting
        
        // Data Movement
        OP_MOV      = 6'b011010,  // 0x1A: Move Register/Immediate
        OP_MOVSR    = 6'b011011,  // 0x1B: Move from Special Register
        OP_SEL      = 6'b011100,  // 0x1C: Select based on Predicate
        OP_LUI      = 6'b011101,  // 0x1D: Load Upper Immediate
        OP_AUIPC    = 6'b011110,  // 0x1E: Add Upper Immediate to PC
        OP_STS32    = 6'b011111,  // 0x1F: Store 32-bit shared
        
        // Floating-Point Operations (0x20-0x2F)
        OP_FADD     = 6'b100000,  // 0x20: FP Add (single/double)
        OP_FSUB     = 6'b100001,  // 0x21: FP Subtract
        OP_FMUL     = 6'b100010,  // 0x22: FP Multiply
        OP_FDIV     = 6'b100011,  // 0x23: FP Divide
        OP_FMIN     = 6'b100100,  // 0x24: FP Minimum
        OP_FMAX     = 6'b100101,  // 0x25: FP Maximum
        OP_FSQRT    = 6'b100110,  // 0x26: FP Square Root
        OP_FABS     = 6'b100111,  // 0x27: FP Absolute Value
        OP_FNEG     = 6'b101000,  // 0x28: FP Negate
        OP_FMADD    = 6'b101001,  // 0x29: FP Fused Multiply-Add
        OP_FCMP     = 6'b101010,  // 0x2A: FP Compare
        OP_FCVT     = 6'b101011,  // 0x2B: FP Convert (int<->float, float<->double)
        OP_FRCP     = 6'b101100,  // 0x2C: FP Reciprocal (approx)
        OP_FRSQRT   = 6'b101101,  // 0x2D: FP Reciprocal Square Root (approx)
        
        // 0x2E-0x2F: Reserved for future FP extensions
        
        // Atomic Operations (0x30-0x33)
        OP_ATOM     = 6'b110000,  // 0x30: Atomic operation (global memory)
        OP_ATOMS    = 6'b110001,  // 0x31: Atomic operation (shared memory)
        OP_ATOM64   = 6'b110010,  // 0x32: 64-bit atomic operation (global)
        OP_ATOMS64  = 6'b110011,  // 0x33: 64-bit atomic operation (shared)
        
        // Warp Shuffle Operations (0x34)
        OP_SHFL     = 6'b110100   // 0x34: Warp shuffle operations
        
        // 0x35-0x3F: Reserved for future extensions
    } opcode_t;
    
    //=========================================================================
    // ALU Function Codes (8 bits, Opcode 0x00)
    //=========================================================================
    
    typedef enum logic [FUNC_WIDTH-1:0] {
        ALU_ADD     = 8'h00,  // RD = RS1 + RS2
        ALU_SUB     = 8'h01,  // RD = RS1 - RS2
        ALU_AND     = 8'h02,  // RD = RS1 & RS2
        ALU_OR      = 8'h03,  // RD = RS1 | RS2
        ALU_XOR     = 8'h04,  // RD = RS1 ^ RS2
        ALU_NOR     = 8'h05,  // RD = ~(RS1 | RS2)
        ALU_MIN     = 8'h06,  // RD = min(RS1, RS2) signed
        ALU_MAX     = 8'h07,  // RD = max(RS1, RS2) signed
        ALU_MINU    = 8'h08,  // RD = min(RS1, RS2) unsigned
        ALU_MAXU    = 8'h09,  // RD = max(RS1, RS2) unsigned
        ALU_ABS     = 8'h0A,  // RD = |RS1|
        ALU_NEG     = 8'h0B,  // RD = -RS1
        ALU_NOT     = 8'h0C,  // RD = ~RS1
        ALU_CLZ     = 8'h0D,  // RD = count_leading_zeros(RS1)
        ALU_CTZ     = 8'h0E,  // RD = count_trailing_zeros(RS1)
        ALU_POPC    = 8'h0F   // RD = population_count(RS1)
    } alu_func_t;
    
    //=========================================================================
    // ALU Immediate Function Codes (2 bits in IMM[15:14])
    //=========================================================================
    
    typedef enum logic [1:0] {
        ALUI_ADD    = 2'b00,  // RD = RS1 + sign_ext(IMM14)
        ALUI_AND    = 2'b01,  // RD = RS1 & zero_ext(IMM14)
        ALUI_OR     = 2'b10,  // RD = RS1 | zero_ext(IMM14)
        ALUI_XOR    = 2'b11   // RD = RS1 ^ zero_ext(IMM14)
    } alui_func_t;
    
    //=========================================================================
    // Multiply/Divide Function Codes (8 bits, Opcode 0x02)
    //=========================================================================
    
    typedef enum logic [FUNC_WIDTH-1:0] {
        MUL_MUL     = 8'h00,  // RD = (RS1 * RS2)[63:0]
        MUL_MULH    = 8'h01,  // RD = (RS1 * RS2)[127:64] signed
        MUL_MULHU   = 8'h02,  // RD = (RS1 * RS2)[127:64] unsigned
        MUL_MULHSU  = 8'h03,  // RD = (RS1 * RS2)[127:64] signed*unsigned
        MUL_DIV     = 8'h04,  // RD = RS1 / RS2 signed
        MUL_DIVU    = 8'h05,  // RD = RS1 / RS2 unsigned
        MUL_REM     = 8'h06,  // RD = RS1 % RS2 signed
        MUL_REMU    = 8'h07   // RD = RS1 % RS2 unsigned
    } mul_func_t;
    
    //=========================================================================
    // Atomic Function Codes (8 bits, Opcode 0x30-0x33)
    //=========================================================================
    
    typedef enum logic [FUNC_WIDTH-1:0] {
        ATOM_ADD    = 8'h00,  // *addr = *addr + data; return old
        ATOM_MIN    = 8'h01,  // *addr = min(*addr, data); return old (signed)
        ATOM_MAX    = 8'h02,  // *addr = max(*addr, data); return old (signed)
        ATOM_MINU   = 8'h03,  // *addr = min(*addr, data); return old (unsigned)
        ATOM_MAXU   = 8'h04,  // *addr = max(*addr, data); return old (unsigned)
        ATOM_AND    = 8'h05,  // *addr = *addr & data; return old
        ATOM_OR     = 8'h06,  // *addr = *addr | data; return old
        ATOM_XOR    = 8'h07,  // *addr = *addr ^ data; return old
        ATOM_EXCH   = 8'h08,  // *addr = data; return old
        ATOM_CAS    = 8'h09   // if (*addr == compare) *addr = data; return old
    } atom_func_t;
    
    //=========================================================================
    // Shift Function Codes (8 bits, Opcode 0x04)
    //=========================================================================
    
    typedef enum logic [FUNC_WIDTH-1:0] {
        SHIFT_SLL   = 8'h00,  // RD = RS1 << RS2[5:0]
        SHIFT_SRL   = 8'h01,  // RD = RS1 >> RS2[5:0] logical
        SHIFT_SRA   = 8'h02,  // RD = RS1 >> RS2[5:0] arithmetic
        SHIFT_ROL   = 8'h03,  // RD = rotate_left(RS1, RS2[5:0])
        SHIFT_ROR   = 8'h04   // RD = rotate_right(RS1, RS2[5:0])
    } shift_func_t;
    
    //=========================================================================
    // Shift Immediate Function Codes (2 bits, Opcode 0x05)
    //=========================================================================
    
    typedef enum logic [1:0] {
        SHIFTI_SLL  = 2'b00,  // RD = RS1 << SHAMT
        SHIFTI_SRL  = 2'b01,  // RD = RS1 >> SHAMT logical
        SHIFTI_SRA  = 2'b10   // RD = RS1 >> SHAMT arithmetic
        // 2'b11 reserved
    } shifti_func_t;
    
    //=========================================================================
    // Compare Function Codes (8 bits, Opcode 0x06)
    //=========================================================================
    
    typedef enum logic [FUNC_WIDTH-1:0] {
        CMP_SEQ     = 8'h00,  // P[RD] = (RS1 == RS2)
        CMP_SNE     = 8'h01,  // P[RD] = (RS1 != RS2)
        CMP_SLT     = 8'h02,  // P[RD] = (RS1 < RS2) signed
        CMP_SLE     = 8'h03,  // P[RD] = (RS1 <= RS2) signed
        CMP_SGT     = 8'h04,  // P[RD] = (RS1 > RS2) signed
        CMP_SGE     = 8'h05,  // P[RD] = (RS1 >= RS2) signed
        CMP_SLTU    = 8'h06,  // P[RD] = (RS1 < RS2) unsigned
        CMP_SLEU    = 8'h07,  // P[RD] = (RS1 <= RS2) unsigned
        CMP_SGTU    = 8'h08,  // P[RD] = (RS1 > RS2) unsigned
        CMP_SGEU    = 8'h09,  // P[RD] = (RS1 >= RS2) unsigned
        CMP_PAND    = 8'h0A,  // P[RD] = P[RS1] & P[RS2]
        CMP_POR     = 8'h0B,  // P[RD] = P[RS1] | P[RS2]
        CMP_PXOR    = 8'h0C,  // P[RD] = P[RS1] ^ P[RS2]
        CMP_PNOT    = 8'h0D   // P[RD] = ~P[RS1]
    } cmp_func_t;
    
    //=========================================================================
    // FPU Function Codes (8 bits)
    //=========================================================================
    
    // FP Precision (bit 7 of func)
    parameter logic FP_SINGLE = 1'b0;   // 32-bit IEEE 754 single precision
    parameter logic FP_DOUBLE = 1'b1;   // 64-bit IEEE 754 double precision
    
    // FP Rounding Mode (bits 1:0 of func)
    typedef enum logic [1:0] {
        FP_RND_RNE  = 2'b00,  // Round to Nearest, ties to Even
        FP_RND_RTZ  = 2'b01,  // Round Toward Zero
        FP_RND_RDN  = 2'b10,  // Round Down (toward -infinity)
        FP_RND_RUP  = 2'b11   // Round Up (toward +infinity)
    } fp_round_mode_t;
    
    // FP Compare Function (bits 3:0 of func for FCMP)
    typedef enum logic [3:0] {
        FCMP_EQ     = 4'h0,   // a == b
        FCMP_NE     = 4'h1,   // a != b
        FCMP_LT     = 4'h2,   // a < b
        FCMP_LE     = 4'h3,   // a <= b
        FCMP_GT     = 4'h4,   // a > b
        FCMP_GE     = 4'h5,   // a >= b
        FCMP_ORD    = 4'h6,   // ordered (neither is NaN)
        FCMP_UNO    = 4'h7    // unordered (either is NaN)
    } fp_cmp_func_t;
    
    // FP Convert Function (bits 4:0 of func for FCVT)
    typedef enum logic [4:0] {
        FCVT_S2D    = 5'h00,  // Single to Double
        FCVT_D2S    = 5'h01,  // Double to Single
        FCVT_S2I    = 5'h02,  // Single to Int64 (signed)
        FCVT_S2U    = 5'h03,  // Single to Int64 (unsigned)
        FCVT_I2S    = 5'h04,  // Int64 to Single (signed)
        FCVT_U2S    = 5'h05,  // Int64 to Single (unsigned)
        FCVT_D2I    = 5'h06,  // Double to Int64 (signed)
        FCVT_D2U    = 5'h07,  // Double to Int64 (unsigned)
        FCVT_I2D    = 5'h08,  // Int64 to Double (signed)
        FCVT_U2D    = 5'h09,  // Int64 to Double (unsigned)
        FCVT_S2I32  = 5'h0A,  // Single to Int32 (signed)
        FCVT_S2U32  = 5'h0B,  // Single to Int32 (unsigned)
        FCVT_I322S  = 5'h0C,  // Int32 to Single (signed)
        FCVT_U322S  = 5'h0D   // Int32 to Single (unsigned)
    } fp_cvt_func_t;
    
    //=========================================================================
    // Branch Condition Codes (3 bits)
    //=========================================================================
    
    typedef enum logic [COND_WIDTH-1:0] {
        BR_ALWAYS   = 3'b000,  // Always branch (unconditional)
        BR_TRUE     = 3'b001,  // Branch if P[PRED] == 1
        BR_FALSE    = 3'b010,  // Branch if P[PRED] == 0
        BR_ANY      = 3'b011,  // Branch if any active thread has P[PRED]==1
        BR_ALL      = 3'b100,  // Branch if all active threads have P[PRED]==1
        BR_NONE     = 3'b101   // Branch if no active thread has P[PRED]==1
        // 3'b110, 3'b111 reserved
    } branch_cond_t;
    
    //=========================================================================
    // Vote Function Codes (4 bits in FUNC13[3:0])
    //=========================================================================
    
    typedef enum logic [3:0] {
        VOTE_ANY    = 4'b0000,  // P[RD] = any active thread has P[PRED]==1
        VOTE_ALL    = 4'b0001,  // P[RD] = all active threads have P[PRED]==1
        VOTE_NONE   = 4'b0010,  // P[RD] = no active thread has P[PRED]==1
        VOTE_BALLOT = 4'b0011,  // RD = ballot of P[PRED]
        VOTE_POPC   = 4'b0100   // RD = popcount(ballot of P[PRED])
    } vote_func_t;
    
    //=========================================================================
    // Shuffle Function Codes (3 bits in FUNC field, Opcode 0x34)
    // Format: RD = shuffle(RS1, lane_selector, width)
    //=========================================================================
    
    typedef enum logic [2:0] {
        SHFL_IDX    = 3'b000,  // RD[lane] = RS1[RS2 % width] - direct index shuffle
        SHFL_UP     = 3'b001,  // RD[lane] = RS1[lane - delta] - shift up (lower lanes)
        SHFL_DOWN   = 3'b010,  // RD[lane] = RS1[lane + delta] - shift down (higher lanes)
        SHFL_BFLY   = 3'b011,  // RD[lane] = RS1[lane ^ mask] - butterfly (XOR) shuffle
        SHFL_CLAMP  = 3'b100,  // RD[lane] = RS1[clamp(lane-delta, 0)] - clamped up
        SHFL_WRAP   = 3'b101   // RD[lane] = RS1[(lane + delta) % width] - wrapped
        // 3'b110, 3'b111 reserved
    } shfl_func_t;
    
    //=========================================================================
    // Special Register IDs (4 bits)
    //=========================================================================
    
    typedef enum logic [3:0] {
        SR_TID        = 4'b0000,  // Thread ID within warp
        SR_WID        = 4'b0001,  // Warp ID within core
        SR_CID        = 4'b0010,  // Core ID
        SR_BID_X      = 4'b0011,  // Block ID, X dimension
        SR_BID_Y      = 4'b0100,  // Block ID, Y dimension
        SR_BID_Z      = 4'b0101,  // Block ID, Z dimension
        SR_NTID       = 4'b0110,  // Number of threads per block
        SR_NCTAID_X   = 4'b0111,  // Number of blocks, X dimension
        SR_NCTAID_Y   = 4'b1000,  // Number of blocks, Y dimension
        SR_NCTAID_Z   = 4'b1001,  // Number of blocks, Z dimension
        SR_CLOCK      = 4'b1010,  // Clock cycle counter (lower 64 bits)
        SR_CLOCK_HI   = 4'b1011   // Clock cycle counter (upper 64 bits)
    } special_reg_t;
    
    //=========================================================================
    // Instruction Format Types
    //=========================================================================
    
    typedef enum logic [2:0] {
        FMT_R   = 3'b000,  // Register-Register
        FMT_I   = 3'b001,  // Immediate
        FMT_L   = 3'b010,  // Load/Store
        FMT_B   = 3'b011,  // Branch
        FMT_S   = 3'b100,  // Special/System
        FMT_M   = 3'b101   // Mask/Divergence
    } instr_format_t;
    
    //=========================================================================
    // Memory Access Types
    //=========================================================================
    
    typedef enum logic [2:0] {
        MEM_NONE      = 3'b000,
        MEM_LOAD_64   = 3'b001,
        MEM_LOAD_32U  = 3'b010,  // Zero-extend
        MEM_LOAD_32S  = 3'b011,  // Sign-extend
        MEM_STORE_64  = 3'b100,
        MEM_STORE_32  = 3'b101,
        MEM_ATOMIC_32 = 3'b110,  // 32-bit atomic read-modify-write
        MEM_ATOMIC_64 = 3'b111   // 64-bit atomic read-modify-write
    } mem_access_t;
    
    typedef enum logic [1:0] {
        MEM_SPACE_GLOBAL = 2'b00,
        MEM_SPACE_SHARED = 2'b01,
        MEM_SPACE_LOCAL  = 2'b10
    } mem_space_t;
    
    //=========================================================================
    // Execution Unit Selection
    //=========================================================================
    
    typedef enum logic [3:0] {
        EX_NONE     = 4'b0000,
        EX_ALU      = 4'b0001,
        EX_MUL      = 4'b0010,
        EX_SHIFT    = 4'b0011,
        EX_CMP      = 4'b0100,
        EX_BRANCH   = 4'b0101,
        EX_LSU      = 4'b0110,
        EX_SPECIAL  = 4'b0111,
        EX_FPU      = 4'b1000,  // Floating-Point Unit
        EX_SHFL     = 4'b1001   // Warp Shuffle Unit
    } exec_unit_t;
    
    //=========================================================================
    // Decoded Instruction Structure
    //=========================================================================
    
    typedef struct packed {
        // Opcode and format
        opcode_t                    opcode;
        instr_format_t              format;
        
        // Register addresses
        logic [REG_ADDR_WIDTH-1:0]  rd;
        logic [REG_ADDR_WIDTH-1:0]  rs1;
        logic [REG_ADDR_WIDTH-1:0]  rs2;
        logic [PRED_ADDR_WIDTH-1:0] pred;
        
        // Function codes
        logic [FUNC_WIDTH-1:0]      func;
        logic [FUNC13_WIDTH-1:0]    func13;
        
        // Immediates (sign-extended as needed)
        logic [DATA_WIDTH-1:0]      imm;
        
        // Control signals
        logic                       rd_en;       // Write to RD
        logic                       rs1_en;      // Read from RS1
        logic                       rs2_en;      // Read from RS2
        logic                       pred_en;     // Predicated execution
        logic                       imm_en;      // Use immediate
        logic                       pred_wr_en;  // Write to predicate register
        
        // Execution unit
        exec_unit_t                 exec_unit;
        
        // Memory access
        mem_access_t                mem_access;
        mem_space_t                 mem_space;
        
        // Control flow
        logic                       is_branch;
        logic                       is_call;
        logic                       is_ret;
        logic                       is_exit;
        
        // Divergence
        logic                       is_push;
        logic                       is_pop;
        logic                       is_else;
        logic                       is_barrier;
        
        // Atomic operations
        logic                       is_atomic;   // Atomic memory operation
        
        // Warp shuffle
        logic                       is_shuffle;  // Warp shuffle operation
        
        // Valid instruction
        logic                       valid;
    } decoded_instr_t;
    
    //=========================================================================
    // Warp State Structure
    //=========================================================================
    
    typedef struct packed {
        logic [ADDR_WIDTH-1:0]                  pc;           // Program counter
        logic [WARP_SIZE-1:0]                   active_mask;  // Active thread mask
        logic [MASK_STACK_DEPTH-1:0][WARP_SIZE-1:0] mask_stack;   // Divergence mask stack
        logic [MASK_SP_WIDTH-1:0]               mask_sp;      // Mask stack pointer
        logic [RETURN_STACK_DEPTH-1:0][ADDR_WIDTH-1:0] return_stack; // Call return stack
        logic [MASK_SP_WIDTH-1:0]               return_sp;    // Return stack pointer
        logic                                   active;       // Warp is active
        logic                                   at_barrier;   // Warp waiting at barrier
        logic [3:0]                             barrier_id;   // Barrier ID waiting on
    } warp_state_t;
    
    //=========================================================================
    // Thread Block Configuration
    //=========================================================================
    
    typedef struct packed {
        logic [DATA_WIDTH-1:0] block_id_x;
        logic [DATA_WIDTH-1:0] block_id_y;
        logic [DATA_WIDTH-1:0] block_id_z;
        logic [DATA_WIDTH-1:0] num_threads;
        logic [DATA_WIDTH-1:0] num_blocks_x;
        logic [DATA_WIDTH-1:0] num_blocks_y;
        logic [DATA_WIDTH-1:0] num_blocks_z;
    } block_config_t;
    
    //=========================================================================
    // Memory Request Structure
    //=========================================================================
    
    typedef struct packed {
        logic                       valid;
        logic                       is_write;
        mem_space_t                 mem_space;
        logic [ADDR_WIDTH-1:0]      addr;
        logic [DATA_WIDTH-1:0]      wdata;
        logic [7:0]                 wstrb;      // Byte strobes for 64-bit
        logic [WARP_ID_WIDTH-1:0]   warp_id;
        logic [THREAD_ID_WIDTH-1:0] thread_id;
        logic [REG_ADDR_WIDTH-1:0]  rd;         // Destination register for loads
    } mem_request_t;
    
    typedef struct packed {
        logic                       valid;
        logic [DATA_WIDTH-1:0]      rdata;
        logic [WARP_ID_WIDTH-1:0]   warp_id;
        logic [THREAD_ID_WIDTH-1:0] thread_id;
        logic [REG_ADDR_WIDTH-1:0]  rd;
    } mem_response_t;
    
    //=========================================================================
    // Pipeline Stages
    //=========================================================================
    
    typedef enum logic [2:0] {
        STAGE_FETCH     = 3'b000,
        STAGE_DECODE    = 3'b001,
        STAGE_OPERAND   = 3'b010,
        STAGE_EXECUTE   = 3'b011,
        STAGE_MEMORY    = 3'b100,
        STAGE_WRITEBACK = 3'b101
    } pipeline_stage_t;
    
    //=========================================================================
    // Helper Functions
    //=========================================================================
    
    // Sign extend from 13 bits to DATA_WIDTH
    function automatic logic [DATA_WIDTH-1:0] sign_extend_13;
        input logic [12:0] value;
        begin
            sign_extend_13 = {{(DATA_WIDTH-13){value[12]}}, value};
        end
    endfunction
    
    // Sign extend from 14 bits to DATA_WIDTH
    function automatic logic [DATA_WIDTH-1:0] sign_extend_14;
        input logic [13:0] value;
        begin
            sign_extend_14 = {{(DATA_WIDTH-14){value[13]}}, value};
        end
    endfunction
    
    // Sign extend from 16 bits to DATA_WIDTH
    function automatic logic [DATA_WIDTH-1:0] sign_extend_16;
        input logic [15:0] value;
        begin
            sign_extend_16 = {{(DATA_WIDTH-16){value[15]}}, value};
        end
    endfunction
    
    // Sign extend from 20 bits to DATA_WIDTH
    function automatic logic [DATA_WIDTH-1:0] sign_extend_20;
        input logic [19:0] value;
        begin
            sign_extend_20 = {{(DATA_WIDTH-20){value[19]}}, value};
        end
    endfunction
    
    // Zero extend from 14 bits to DATA_WIDTH
    function automatic logic [DATA_WIDTH-1:0] zero_extend_14;
        input logic [13:0] value;
        begin
            zero_extend_14 = {{(DATA_WIDTH-14){1'b0}}, value};
        end
    endfunction
    
    // Zero extend from 16 bits to DATA_WIDTH
    function automatic logic [DATA_WIDTH-1:0] zero_extend_16;
        input logic [15:0] value;
        begin
            zero_extend_16 = {{(DATA_WIDTH-16){1'b0}}, value};
        end
    endfunction
    
    // Count leading zeros
    function automatic logic [6:0] count_leading_zeros;
        input logic [DATA_WIDTH-1:0] value;
        integer i;
        logic found;
        begin
            count_leading_zeros = DATA_WIDTH[6:0];
            found = 0;
            for (i = DATA_WIDTH-1; i >= 0; i = i - 1) begin
                if (value[i] && !found) begin
                    count_leading_zeros = (DATA_WIDTH - 1 - i);
                    found = 1;
                end
            end
        end
    endfunction
    
    // Count trailing zeros
    function automatic logic [6:0] count_trailing_zeros;
        input logic [DATA_WIDTH-1:0] value;
        integer i;
        logic found;
        begin
            count_trailing_zeros = DATA_WIDTH[6:0];
            found = 0;
            for (i = 0; i < DATA_WIDTH; i = i + 1) begin
                if (value[i] && !found) begin
                    count_trailing_zeros = i[6:0];
                    found = 1;
                end
            end
        end
    endfunction
    
    // Population count (number of 1s)
    function automatic logic [6:0] population_count;
        input logic [DATA_WIDTH-1:0] value;
        integer i;
        begin
            population_count = 0;
            for (i = 0; i < DATA_WIDTH; i = i + 1) begin
                population_count = population_count + value[i];
            end
        end
    endfunction
    
    // Determine instruction format from opcode
    function automatic instr_format_t get_instr_format;
        input opcode_t op;
        begin
            case (op)
                OP_ALU, OP_MUL, OP_SHIFT, OP_CMP, OP_SEL:
                    get_instr_format = FMT_R;
                    
                OP_ALUI, OP_MULI, OP_SHIFTI, OP_CMPI, OP_MOV, OP_LUI, OP_AUIPC:
                    get_instr_format = FMT_I;
                    
                OP_LD, OP_LD32, OP_LD32S, OP_LDS, OP_LDS32,
                OP_ST, OP_ST32, OP_STS, OP_STS32:
                    get_instr_format = FMT_L;
                    
                OP_BRA, OP_BRC, OP_CALL:
                    get_instr_format = FMT_B;
                    
                OP_RET, OP_EXIT, OP_MOVSR:
                    get_instr_format = FMT_S;
                    
                OP_BAR, OP_PUSH, OP_POP, OP_ELSE, OP_VOTE:
                    get_instr_format = FMT_M;
                    
                default:
                    get_instr_format = FMT_R;
            endcase
        end
    endfunction
    
    // Determine if opcode is a memory operation
    function automatic logic is_memory_op;
        input opcode_t op;
        begin
            case (op)
                OP_LD, OP_LD32, OP_LD32S, OP_LDS, OP_LDS32,
                OP_ST, OP_ST32, OP_STS, OP_STS32:
                    is_memory_op = 1'b1;
                default:
                    is_memory_op = 1'b0;
            endcase
        end
    endfunction
    
    // Determine if opcode is a load
    function automatic logic is_load_op;
        input opcode_t op;
        begin
            case (op)
                OP_LD, OP_LD32, OP_LD32S, OP_LDS, OP_LDS32:
                    is_load_op = 1'b1;
                default:
                    is_load_op = 1'b0;
            endcase
        end
    endfunction
    
    // Determine if opcode is a store
    function automatic logic is_store_op;
        input opcode_t op;
        begin
            case (op)
                OP_ST, OP_ST32, OP_STS, OP_STS32:
                    is_store_op = 1'b1;
                default:
                    is_store_op = 1'b0;
            endcase
        end
    endfunction
    
    // Determine memory space from opcode
    function automatic mem_space_t get_mem_space;
        input opcode_t op;
        begin
            case (op)
                OP_LDS, OP_LDS32, OP_STS, OP_STS32:
                    get_mem_space = MEM_SPACE_SHARED;
                default:
                    get_mem_space = MEM_SPACE_GLOBAL;
            endcase
        end
    endfunction

endpackage

`endif // GPGPU_PKG_SV
