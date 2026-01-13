//=============================================================================
// GPGPU-1 Instruction Decoder
//=============================================================================
// File:        decoder.sv
// Description: Decodes 32-bit instructions into control signals and operand
//              addresses. Supports all 6 instruction formats (R, I, L, B, S, M).
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`default_nettype none

`include "gpgpu_defines.svh"

module decoder
    import gpgpu_pkg::*;
(
    // Inputs
    input  logic [INST_WIDTH-1:0]   instr,          // 32-bit instruction
    input  logic                    instr_valid,    // Instruction valid
    
    // Decoded outputs
    output decoded_instr_t          decoded,        // Decoded instruction struct
    output logic                    decode_valid,   // Decode successful
    output logic                    illegal_instr   // Illegal instruction detected
);

    //=========================================================================
    // Instruction Field Extraction
    //=========================================================================
    
    // Common fields
    logic [OPCODE_WIDTH-1:0]    opcode;
    logic [REG_ADDR_WIDTH-1:0]  rd_field;
    logic [REG_ADDR_WIDTH-1:0]  rs1_field;
    logic [REG_ADDR_WIDTH-1:0]  rs2_field;
    logic [PRED_ADDR_WIDTH-1:0] pred_field;
    logic [FUNC_WIDTH-1:0]      func_field;
    logic [FUNC13_WIDTH-1:0]    func13_field;
    
    // Immediate fields
    logic [15:0]                imm16_field;
    logic [13:0]                imm14_field;
    logic [12:0]                imm13_field;
    logic [19:0]                imm20_field;
    logic [5:0]                 shamt_field;
    
    // Branch fields
    logic [COND_WIDTH-1:0]      cond_field;
    
    // Extract fields from instruction
    assign opcode      = instr[31:26];
    assign rd_field    = instr[25:21];
    assign rs1_field   = instr[20:16];
    assign rs2_field   = instr[15:11];
    assign pred_field  = instr[10:8];   // Format R predicate location
    assign func_field  = instr[7:0];
    assign func13_field = instr[12:0];
    
    assign imm16_field = instr[15:0];
    assign imm14_field = instr[13:0];
    assign imm13_field = instr[12:0];
    assign imm20_field = instr[19:0];
    assign shamt_field = instr[13:8];
    
    assign cond_field  = instr[22:20];
    
    //=========================================================================
    // Instruction Format Detection
    //=========================================================================
    
    instr_format_t instr_format;
    opcode_t       opcode_enum;
    
    assign opcode_enum = opcode_t'(opcode);
      always_comb begin
        case (opcode_enum)
            // Format R: Register-Register
            OP_ALU, OP_MUL, OP_SHIFT, OP_CMP, OP_SEL:
                instr_format = FMT_R;
            
            // Format I: Immediate
            OP_ALUI, OP_MULI, OP_SHIFTI, OP_CMPI, OP_MOV, OP_LUI, OP_AUIPC:
                instr_format = FMT_I;
            
            // Format L: Load/Store
            OP_LD, OP_LD32, OP_LD32S, OP_LDS, OP_LDS32,
            OP_ST, OP_ST32, OP_STS, OP_STS32:
                instr_format = FMT_L;
            
            // Format B: Branch
            OP_BRA, OP_BRC, OP_CALL:
                instr_format = FMT_B;
            
            // Format S: Special/System
            OP_RET, OP_EXIT, OP_MOVSR:
                instr_format = FMT_S;
            
            // Format M: Mask/Divergence
            OP_BAR, OP_PUSH, OP_POP, OP_ELSE, OP_VOTE:
                instr_format = FMT_M;
            
            // Format R: Floating-Point (uses R-type format)
            OP_FADD, OP_FSUB, OP_FMUL, OP_FDIV, OP_FMIN, OP_FMAX,
            OP_FSQRT, OP_FABS, OP_FNEG, OP_FMADD, OP_FCMP, OP_FCVT,
            OP_FRCP, OP_FRSQRT:
                instr_format = FMT_R;
            
            // Format L: Atomic memory operations (like loads/stores)
            OP_ATOM, OP_ATOMS, OP_ATOM64, OP_ATOMS64:
                instr_format = FMT_L;
            
            // Format R: Warp shuffle (uses R-type format)
            OP_SHFL:
                instr_format = FMT_R;
            
            default:
                instr_format = FMT_R;
        endcase
    end
    
    //=========================================================================
    // Predicate Field Extraction (varies by format)
    //=========================================================================
    
    logic [PRED_ADDR_WIDTH-1:0] pred_extracted;
    
    always_comb begin
        case (instr_format)
            FMT_R:   pred_extracted = instr[10:8];   // PRED in [10:8]
            FMT_L:   pred_extracted = instr[15:13];  // PRED in [15:13]
            FMT_B:   pred_extracted = instr[25:23];  // PRED in [25:23]
            FMT_M:   pred_extracted = instr[15:13];  // PRED in [15:13]
            default: pred_extracted = 3'b000;        // P0 = always true
        endcase
    end
    
    //=========================================================================
    // Immediate Value Generation
    //=========================================================================
    
    logic [DATA_WIDTH-1:0] immediate;
    
    always_comb begin
        case (opcode_enum)
            // ALU Immediate: sign/zero extend based on operation
            OP_ALUI: begin
                case (imm16_field[15:14])
                    ALUI_ADD: immediate = {{50{imm14_field[13]}}, imm14_field}; // Sign-extend
                    default:  immediate = {50'b0, imm14_field};                  // Zero-extend
                endcase
            end
            
            // Multiply Immediate: sign-extend 16-bit
            OP_MULI: begin
                immediate = {{48{imm16_field[15]}}, imm16_field};
            end
            
            // Shift Immediate: zero-extend 6-bit shift amount
            OP_SHIFTI: begin
                immediate = {58'b0, shamt_field};
            end
            
            // Compare Immediate: sign-extend 16-bit
            OP_CMPI: begin
                immediate = {{48{imm16_field[15]}}, imm16_field};
            end
            
            // Load/Store: sign-extend 13-bit offset
            OP_LD, OP_LD32, OP_LD32S, OP_LDS, OP_LDS32,
            OP_ST, OP_ST32, OP_STS, OP_STS32: begin
                immediate = {{51{imm13_field[12]}}, imm13_field};
            end
            
            // Branch: sign-extend 20-bit offset, shift left by 2
            OP_BRA, OP_BRC, OP_CALL: begin
                immediate = {{42{imm20_field[19]}}, imm20_field, 2'b00};
            end
            
            // MOV: sign-extend 16-bit immediate
            OP_MOV: begin
                immediate = {{48{imm16_field[15]}}, imm16_field};
            end
            
            // LUI: place 16-bit immediate in upper bits [63:48]
            OP_LUI: begin
                immediate = {imm16_field, 48'b0};
            end
            
            // AUIPC: same as LUI, added to PC
            OP_AUIPC: begin
                immediate = {imm16_field, 48'b0};
            end
            
            // Barrier: zero-extend barrier ID from func13
            OP_BAR: begin
                immediate = {60'b0, func13_field[3:0]};
            end
            
            default: begin
                immediate = 64'b0;
            end
        endcase
    end
    
    //=========================================================================
    // Execution Unit Selection
    //=========================================================================
    
    exec_unit_t exec_unit;
      always_comb begin
        case (opcode_enum)
            OP_ALU, OP_ALUI:
                exec_unit = EX_ALU;
            
            OP_MUL, OP_MULI:
                exec_unit = EX_MUL;
            
            OP_SHIFT, OP_SHIFTI:
                exec_unit = EX_SHIFT;
            
            OP_CMP, OP_CMPI:
                exec_unit = EX_CMP;
            
            OP_BRA, OP_BRC, OP_CALL, OP_RET:
                exec_unit = EX_BRANCH;
            
            OP_LD, OP_LD32, OP_LD32S, OP_LDS, OP_LDS32,
            OP_ST, OP_ST32, OP_STS, OP_STS32,
            OP_ATOM, OP_ATOMS, OP_ATOM64, OP_ATOMS64:
                exec_unit = EX_LSU;
            
            OP_MOVSR, OP_EXIT, OP_BAR, OP_PUSH, OP_POP, OP_ELSE, OP_VOTE:
                exec_unit = EX_SPECIAL;
            
            OP_MOV, OP_LUI, OP_AUIPC, OP_SEL:
                exec_unit = EX_ALU;  // Simple operations go through ALU
            
            // Floating-Point operations
            OP_FADD, OP_FSUB, OP_FMUL, OP_FDIV, OP_FMIN, OP_FMAX,
            OP_FSQRT, OP_FABS, OP_FNEG, OP_FMADD, OP_FCMP, OP_FCVT,
            OP_FRCP, OP_FRSQRT:
                exec_unit = EX_FPU;
            
            // Warp shuffle operations
            OP_SHFL:
                exec_unit = EX_SHFL;
            
            default:
                exec_unit = EX_NONE;
        endcase
    end
    
    //=========================================================================
    // Memory Access Type Detection
    //=========================================================================
    
    mem_access_t mem_access;
    mem_space_t  mem_space;
    
    always_comb begin
        case (opcode_enum)
            OP_LD, OP_LDS:      mem_access = MEM_LOAD_64;
            OP_LD32, OP_LDS32:  mem_access = MEM_LOAD_32U;
            OP_LD32S:           mem_access = MEM_LOAD_32S;
            OP_ST, OP_STS:      mem_access = MEM_STORE_64;
            OP_ST32, OP_STS32:  mem_access = MEM_STORE_32;
            OP_ATOM, OP_ATOMS:  mem_access = MEM_ATOMIC_32;
            OP_ATOM64, OP_ATOMS64: mem_access = MEM_ATOMIC_64;
            default:            mem_access = MEM_NONE;
        endcase
        
        case (opcode_enum)
            OP_LDS, OP_LDS32, OP_STS, OP_STS32: mem_space = MEM_SPACE_SHARED;
            OP_ATOMS, OP_ATOMS64:               mem_space = MEM_SPACE_SHARED;
            default:                             mem_space = MEM_SPACE_GLOBAL;
        endcase
    end
    
    //=========================================================================
    // Control Signal Generation
    //=========================================================================
    
    logic rd_write_en;
    logic rs1_read_en;
    logic rs2_read_en;
    logic pred_enable;
    logic use_immediate;
    logic pred_write_en;
      // Destination register write enable
    always_comb begin
        case (opcode_enum)
            // Instructions that write to RD
            OP_ALU, OP_ALUI, OP_MUL, OP_MULI, OP_SHIFT, OP_SHIFTI,
            OP_LD, OP_LD32, OP_LD32S, OP_LDS, OP_LDS32,
            OP_MOV, OP_MOVSR, OP_LUI, OP_AUIPC, OP_SEL,
            OP_ATOM, OP_ATOMS, OP_ATOM64, OP_ATOMS64:  // Atomics return old value
                rd_write_en = 1'b1;
            
            // FPU instructions that write to RD (all except FCMP which writes predicate)
            OP_FADD, OP_FSUB, OP_FMUL, OP_FDIV, OP_FMIN, OP_FMAX,
            OP_FSQRT, OP_FABS, OP_FNEG, OP_FMADD, OP_FCVT,
            OP_FRCP, OP_FRSQRT:
                rd_write_en = 1'b1;
            
            // Warp shuffle writes to RD
            OP_SHFL:
                rd_write_en = 1'b1;
            
            // VOTE_BALLOT writes to RD (integer register)
            OP_VOTE:
                rd_write_en = (func13_field[3:0] == VOTE_BALLOT) || 
                              (func13_field[3:0] == VOTE_POPC);
            
            default:
                rd_write_en = 1'b0;
        endcase
    end
      // Source register 1 read enable
    always_comb begin
        case (opcode_enum)
            // Instructions that read RS1
            OP_ALU, OP_ALUI, OP_MUL, OP_MULI, OP_SHIFT, OP_SHIFTI,
            OP_CMP, OP_CMPI, OP_SEL:
                rs1_read_en = 1'b1;
            
            // Load/Store read base register (RS1 position = RBASE)
            OP_LD, OP_LD32, OP_LD32S, OP_LDS, OP_LDS32,
            OP_ST, OP_ST32, OP_STS, OP_STS32,
            OP_ATOM, OP_ATOMS, OP_ATOM64, OP_ATOMS64:
                rs1_read_en = 1'b1;
            
            // MOV reads RS1 if not immediate move
            OP_MOV:
                rs1_read_en = (rs1_field != 5'b0);
            
            // FPU instructions that read RS1
            OP_FADD, OP_FSUB, OP_FMUL, OP_FDIV, OP_FMIN, OP_FMAX,
            OP_FSQRT, OP_FABS, OP_FNEG, OP_FMADD, OP_FCMP, OP_FCVT,
            OP_FRCP, OP_FRSQRT:
                rs1_read_en = 1'b1;
            
            // Warp shuffle reads RS1 (source data to shuffle)
            OP_SHFL:
                rs1_read_en = 1'b1;
            
            default:
                rs1_read_en = 1'b0;
        endcase
    end
      // Source register 2 read enable
    always_comb begin
        case (opcode_enum)
            // R-format instructions with RS2
            OP_ALU, OP_MUL, OP_SHIFT, OP_CMP, OP_SEL:
                rs2_read_en = 1'b1;
            
            // Store instructions read data from RD field (which is RS for stores)
            OP_ST, OP_ST32, OP_STS, OP_STS32:
                rs2_read_en = 1'b0;  // RD field is store data, handled separately
            
            // Atomic operations read operand from RS2 (or RD for some encodings)
            OP_ATOM, OP_ATOMS, OP_ATOM64, OP_ATOMS64:
                rs2_read_en = 1'b1;
            
            // FPU binary operations read RS2
            OP_FADD, OP_FSUB, OP_FMUL, OP_FDIV, OP_FMIN, OP_FMAX, OP_FCMP:
                rs2_read_en = 1'b1;
            
            // FPU ternary operation (FMADD) also reads RS2
            OP_FMADD:
                rs2_read_en = 1'b1;
            
            // Warp shuffle reads RS2 (lane index / delta / mask)
            OP_SHFL:
                rs2_read_en = 1'b1;
            
            default:
                rs2_read_en = 1'b0;
        endcase
    end
    
    // Predicate enable (instruction is predicated)
    always_comb begin
        case (instr_format)
            FMT_R: pred_enable = 1'b1;  // R-format always has predicate
            FMT_L: pred_enable = 1'b1;  // Load/Store has predicate
            FMT_M: pred_enable = 1'b1;  // Mask operations have predicate
            default: pred_enable = 1'b0;
        endcase
    end
    
    // Use immediate operand
    always_comb begin
        case (opcode_enum)
            OP_ALUI, OP_MULI, OP_SHIFTI, OP_CMPI,
            OP_MOV, OP_LUI, OP_AUIPC,
            OP_LD, OP_LD32, OP_LD32S, OP_LDS, OP_LDS32,
            OP_ST, OP_ST32, OP_STS, OP_STS32:
                use_immediate = 1'b1;
            default:
                use_immediate = 1'b0;
        endcase
    end
      // Predicate register write enable (for compare instructions)
    always_comb begin
        case (opcode_enum)
            OP_CMP, OP_CMPI:
                pred_write_en = 1'b1;
            
            // FP compare writes to predicate register
            OP_FCMP:
                pred_write_en = 1'b1;
            
            // VOTE operations that write predicates
            OP_VOTE:
                pred_write_en = (func13_field[3:0] == VOTE_ANY) ||
                                (func13_field[3:0] == VOTE_ALL) ||
                                (func13_field[3:0] == VOTE_NONE);
            
            default:
                pred_write_en = 1'b0;
        endcase
    end
    
    //=========================================================================
    // Control Flow Signal Generation
    //=========================================================================
    
    logic is_branch_instr;
    logic is_call_instr;
    logic is_ret_instr;
    logic is_exit_instr;
    logic is_push_instr;
    logic is_pop_instr;
    logic is_else_instr;
    logic is_barrier_instr;
    
    assign is_branch_instr  = (opcode_enum == OP_BRA) || (opcode_enum == OP_BRC);
    assign is_call_instr    = (opcode_enum == OP_CALL);
    assign is_ret_instr     = (opcode_enum == OP_RET);
    assign is_exit_instr    = (opcode_enum == OP_EXIT);
    assign is_push_instr    = (opcode_enum == OP_PUSH);
    assign is_pop_instr     = (opcode_enum == OP_POP);
    assign is_else_instr    = (opcode_enum == OP_ELSE);
    assign is_barrier_instr = (opcode_enum == OP_BAR);
    
    //=========================================================================
    // Function Code Processing
    //=========================================================================
    
    logic [FUNC_WIDTH-1:0] effective_func;
    
    always_comb begin
        case (opcode_enum)
            // For immediate ALU, extract function from IMM[15:14]
            OP_ALUI: begin
                case (imm16_field[15:14])
                    ALUI_ADD: effective_func = ALU_ADD;
                    ALUI_AND: effective_func = ALU_AND;
                    ALUI_OR:  effective_func = ALU_OR;
                    ALUI_XOR: effective_func = ALU_XOR;
                    default:  effective_func = ALU_ADD;
                endcase
            end
            
            // For shift immediate, extract function from bits [15:14]
            OP_SHIFTI: begin
                case (instr[15:14])
                    SHIFTI_SLL: effective_func = SHIFT_SLL;
                    SHIFTI_SRL: effective_func = SHIFT_SRL;
                    SHIFTI_SRA: effective_func = SHIFT_SRA;
                    default:    effective_func = SHIFT_SLL;
                endcase
            end
            
            // MOV is implemented as ADD with R0 or immediate
            OP_MOV: begin
                effective_func = ALU_ADD;
            end
            
            // LUI places immediate in upper bits (special handling in ALU)
            OP_LUI: begin
                effective_func = 8'hFF;  // Special code for LUI
            end
            
            // AUIPC adds upper immediate to PC
            OP_AUIPC: begin
                effective_func = 8'hFE;  // Special code for AUIPC
            end
            
            // Default: use the function field directly
            default: begin
                effective_func = func_field;
            end
        endcase
    end
    
    //=========================================================================
    // Illegal Instruction Detection
    //=========================================================================
    
    logic illegal;
      always_comb begin
        illegal = 1'b0;
        
        if (instr_valid) begin
            // Check for reserved opcodes (0x2E-0x2F and 0x35-0x3F are reserved)
            // Note: 0x30-0x33 are atomic operations
            // Note: 0x34 is warp shuffle (OP_SHFL)
            if ((opcode >= 6'h2E && opcode <= 6'h2F) || (opcode >= 6'h35)) begin
                illegal = 1'b1;
            end
            
            // Check for reserved function codes
            case (opcode_enum)
                OP_ALU: begin
                    if (func_field > 8'h0F) illegal = 1'b1;
                end
                
                OP_MUL: begin
                    if (func_field > 8'h07) illegal = 1'b1;
                end
                
                OP_SHIFT: begin
                    if (func_field > 8'h04) illegal = 1'b1;
                end
                
                OP_SHIFTI: begin
                    if (instr[15:14] == 2'b11) illegal = 1'b1;
                end
                
                OP_CMP: begin
                    if (func_field > 8'h0D) illegal = 1'b1;
                end
                
                OP_BRC: begin
                    if (cond_field >= 3'b110) illegal = 1'b1;
                end
                
                OP_VOTE: begin
                    if (func13_field[3:0] > 4'b0100) illegal = 1'b1;
                end
                
                // FP compare: check valid compare function
                OP_FCMP: begin
                    if (func_field[3:0] > 4'h7) illegal = 1'b1;
                end
                
                // FP convert: check valid convert function
                OP_FCVT: begin
                    if (func_field[4:0] > 5'h0D) illegal = 1'b1;
                end
                
                // Atomic operations: check valid atomic function (0-9)
                OP_ATOM, OP_ATOMS, OP_ATOM64, OP_ATOMS64: begin
                    if (func_field[3:0] > 4'h9) illegal = 1'b1;
                end
                
                default: begin
                    // No additional checks
                end
            endcase
        end
    end
    
    //=========================================================================
    // Output Assignment
    //=========================================================================
    
    always_comb begin
        // Default values
        decoded = '0;
        
        // Opcode and format
        decoded.opcode     = opcode_enum;
        decoded.format     = instr_format;
        
        // Register addresses - format-dependent
        case (instr_format)
            FMT_B: begin
                // Branch format: no RD/RS1/RS2 fields
                decoded.rd  = 5'b0;
                decoded.rs1 = 5'b0;
                decoded.rs2 = 5'b0;
            end
            FMT_S, FMT_M: begin
                // Special/Mask formats may not have all register fields
                decoded.rd  = rd_field;
                decoded.rs1 = rs1_field;
                decoded.rs2 = 5'b0;
            end
            default: begin
                decoded.rd  = rd_field;
                decoded.rs1 = rs1_field;
                decoded.rs2 = rs2_field;
            end
        endcase
        
        decoded.pred       = pred_extracted;
        
        // Function codes
        decoded.func       = effective_func;
        decoded.func13     = func13_field;
        
        // Immediate value
        decoded.imm        = immediate;
        
        // Control signals
        decoded.rd_en      = rd_write_en;
        decoded.rs1_en     = rs1_read_en;
        decoded.rs2_en     = rs2_read_en;
        decoded.pred_en    = pred_enable;
        decoded.imm_en     = use_immediate;
        decoded.pred_wr_en = pred_write_en;
        
        // Execution unit
        decoded.exec_unit  = exec_unit;
        
        // Memory access
        decoded.mem_access = mem_access;
        decoded.mem_space  = mem_space;
        
        // Control flow
        decoded.is_branch  = is_branch_instr;
        decoded.is_call    = is_call_instr;
        decoded.is_ret     = is_ret_instr;
        decoded.is_exit    = is_exit_instr;
        
        // Divergence control
        decoded.is_push    = is_push_instr;
        decoded.is_pop     = is_pop_instr;
        decoded.is_else    = is_else_instr;
        decoded.is_barrier = is_barrier_instr;
        
        // Atomic operation flag
        decoded.is_atomic  = (opcode_enum == OP_ATOM || opcode_enum == OP_ATOMS ||
                             opcode_enum == OP_ATOM64 || opcode_enum == OP_ATOMS64);
        
        // Warp shuffle flag
        decoded.is_shuffle = (opcode_enum == OP_SHFL);
        
        // Validity
        decoded.valid      = instr_valid && !illegal;
    end
    
    // Output signals
    assign decode_valid  = instr_valid && !illegal;
    assign illegal_instr = illegal && instr_valid;

endmodule
