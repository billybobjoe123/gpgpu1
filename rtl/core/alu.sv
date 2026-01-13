//=============================================================================
// GPGPU-1 Arithmetic Logic Unit (ALU)
//=============================================================================
// File:        alu.sv
// Description: 8-wide SIMD ALU supporting all integer arithmetic, logical,
//              and bit manipulation operations defined in the ISA.
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`default_nettype none

/* verilator lint_off DECLFILENAME */

`include "gpgpu_defines.svh"

module alu
    import gpgpu_pkg::*;
(
    // Operands (per-thread, 8 threads)
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   operand_a,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   operand_b,
    
    // Control
    input  logic [FUNC_WIDTH-1:0]                  func,       // ALU function select
    input  logic [WARP_SIZE-1:0]                   active_mask,// Which threads are active
    
    // Results (per-thread)
    output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   result
);

    //=========================================================================
    // Per-Thread ALU Instances
    //=========================================================================
    
    genvar t;
    generate
        for (t = 0; t < WARP_SIZE; t++) begin : gen_alu_lanes
            alu_lane u_alu_lane (
                .a      (operand_a[t]),
                .b      (operand_b[t]),
                .func   (func),
                .active (active_mask[t]),
                .result (result[t])
            );
        end
    endgenerate

endmodule

//=============================================================================
// Single ALU Lane (64-bit)
//=============================================================================

module alu_lane
    import gpgpu_pkg::*;
(
    input  logic [DATA_WIDTH-1:0]   a,
    input  logic [DATA_WIDTH-1:0]   b,
    input  logic [FUNC_WIDTH-1:0]   func,
    input  logic                    active,
    output logic [DATA_WIDTH-1:0]   result
);

    //=========================================================================
    // Intermediate Results
    //=========================================================================
    
    logic [DATA_WIDTH-1:0] add_result;
    logic [DATA_WIDTH-1:0] sub_result;
    logic [DATA_WIDTH-1:0] and_result;
    logic [DATA_WIDTH-1:0] or_result;
    logic [DATA_WIDTH-1:0] xor_result;
    logic [DATA_WIDTH-1:0] nor_result;
    logic [DATA_WIDTH-1:0] min_result;
    logic [DATA_WIDTH-1:0] max_result;
    logic [DATA_WIDTH-1:0] minu_result;
    logic [DATA_WIDTH-1:0] maxu_result;
    logic [DATA_WIDTH-1:0] abs_result;
    logic [DATA_WIDTH-1:0] neg_result;
    logic [DATA_WIDTH-1:0] not_result;
    logic [DATA_WIDTH-1:0] clz_result;
    logic [DATA_WIDTH-1:0] ctz_result;
    logic [DATA_WIDTH-1:0] popc_result;
    
    //=========================================================================
    // Basic Arithmetic
    //=========================================================================
    
    assign add_result = a + b;
    assign sub_result = a - b;
    assign neg_result = -a;
    
    // Absolute value
    assign abs_result = a[DATA_WIDTH-1] ? (-a) : a;
    
    //=========================================================================
    // Logical Operations
    //=========================================================================
    
    assign and_result = a & b;
    assign or_result  = a | b;
    assign xor_result = a ^ b;
    assign nor_result = ~(a | b);
    assign not_result = ~a;
    
    //=========================================================================
    // Comparison for MIN/MAX
    //=========================================================================
    
    // Signed comparison
    logic signed_lt;
    assign signed_lt = $signed(a) < $signed(b);
    
    assign min_result = signed_lt ? a : b;
    assign max_result = signed_lt ? b : a;
    
    // Unsigned comparison
    logic unsigned_lt;
    assign unsigned_lt = a < b;
    
    assign minu_result = unsigned_lt ? a : b;
    assign maxu_result = unsigned_lt ? b : a;
    
    //=========================================================================
    // Bit Counting Operations
    //=========================================================================
    
    assign clz_result  = {57'b0, count_leading_zeros(a)};
    assign ctz_result  = {57'b0, count_trailing_zeros(a)};
    assign popc_result = {57'b0, population_count(a)};
    
    //=========================================================================
    // Result Multiplexer
    //=========================================================================
    
    always_comb begin
        if (!active) begin
            result = '0;
        end else begin
            case (func)
                ALU_ADD:  result = add_result;
                ALU_SUB:  result = sub_result;
                ALU_AND:  result = and_result;
                ALU_OR:   result = or_result;
                ALU_XOR:  result = xor_result;
                ALU_NOR:  result = nor_result;
                ALU_MIN:  result = min_result;
                ALU_MAX:  result = max_result;
                ALU_MINU: result = minu_result;
                ALU_MAXU: result = maxu_result;
                ALU_ABS:  result = abs_result;
                ALU_NEG:  result = neg_result;
                ALU_NOT:  result = not_result;
                ALU_CLZ:  result = clz_result;
                ALU_CTZ:  result = ctz_result;
                ALU_POPC: result = popc_result;
                
                // Special cases for MOV, LUI, etc.
                8'hFF:    result = b;          // LUI: pass through immediate
                8'hFE:    result = a + b;      // AUIPC: add PC + immediate
                
                default:  result = '0;
            endcase
        end
    end

endmodule

//=============================================================================
// GPGPU-1 Shift Unit
//=============================================================================
// Description: 8-wide SIMD shifter supporting SLL, SRL, SRA, ROL, ROR
//=============================================================================

module shift_unit
    import gpgpu_pkg::*;
(
    // Operands
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   operand_a,    // Value to shift
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   operand_b,    // Shift amount (or immediate)
    
    // Control
    input  logic [FUNC_WIDTH-1:0]                  func,
    input  logic [WARP_SIZE-1:0]                   active_mask,
    
    // Results
    output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   result
);

    genvar t;
    generate
        for (t = 0; t < WARP_SIZE; t++) begin : gen_shift_lanes
            shift_lane u_shift_lane (
                .a      (operand_a[t]),
                .shamt  (operand_b[t][5:0]),  // Only use lower 6 bits
                .func   (func),
                .active (active_mask[t]),
                .result (result[t])
            );
        end
    endgenerate

endmodule

//=============================================================================
// Single Shift Lane (64-bit)
//=============================================================================

module shift_lane
    import gpgpu_pkg::*;
(
    input  logic [DATA_WIDTH-1:0]   a,
    input  logic [5:0]              shamt,
    input  logic [FUNC_WIDTH-1:0]   func,
    input  logic                    active,
    output logic [DATA_WIDTH-1:0]   result
);

    logic [DATA_WIDTH-1:0] sll_result;
    logic [DATA_WIDTH-1:0] srl_result;
    logic [DATA_WIDTH-1:0] sra_result;
    logic [DATA_WIDTH-1:0] rol_result;
    logic [DATA_WIDTH-1:0] ror_result;
    
    // Shift left logical
    assign sll_result = a << shamt;
    
    // Shift right logical
    assign srl_result = a >> shamt;
    
    // Shift right arithmetic
    assign sra_result = $signed(a) >>> shamt;
    
    // Rotate left
    assign rol_result = (a << shamt) | (a >> (DATA_WIDTH - shamt));
    
    // Rotate right
    assign ror_result = (a >> shamt) | (a << (DATA_WIDTH - shamt));
    
    always_comb begin
        if (!active) begin
            result = '0;
        end else begin
            case (func[2:0])  // Only need lower 3 bits for shift selection
                SHIFT_SLL[2:0]: result = sll_result;
                SHIFT_SRL[2:0]: result = srl_result;
                SHIFT_SRA[2:0]: result = sra_result;
                SHIFT_ROL[2:0]: result = rol_result;
                SHIFT_ROR[2:0]: result = ror_result;
                default:        result = '0;
            endcase
        end
    end

endmodule

//=============================================================================
// GPGPU-1 Compare Unit
//=============================================================================
// Description: 8-wide SIMD comparison unit that outputs predicate results
//=============================================================================

module compare_unit
    import gpgpu_pkg::*;
(
    // Operands
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   operand_a,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   operand_b,
    
    // Predicate inputs (for PAND, POR, PXOR, PNOT)
    input  logic [WARP_SIZE-1:0]                   pred_a,
    input  logic [WARP_SIZE-1:0]                   pred_b,
    
    // Control
    input  logic [FUNC_WIDTH-1:0]                  func,
    input  logic [WARP_SIZE-1:0]                   active_mask,
    
    // Predicate results (1-bit per thread)
    output logic [WARP_SIZE-1:0]                   pred_result
);

    genvar t;
    generate
        for (t = 0; t < WARP_SIZE; t++) begin : gen_cmp_lanes
            compare_lane u_cmp_lane (
                .a        (operand_a[t]),
                .b        (operand_b[t]),
                .pred_a   (pred_a[t]),
                .pred_b   (pred_b[t]),
                .func     (func),
                .active   (active_mask[t]),
                .result   (pred_result[t])
            );
        end
    endgenerate

endmodule

//=============================================================================
// Single Compare Lane
//=============================================================================

module compare_lane
    import gpgpu_pkg::*;
(
    input  logic [DATA_WIDTH-1:0]   a,
    input  logic [DATA_WIDTH-1:0]   b,
    input  logic                    pred_a,
    input  logic                    pred_b,
    input  logic [FUNC_WIDTH-1:0]   func,
    input  logic                    active,
    output logic                    result
);

    // Signed comparison flags
    logic eq, ne, lt_s, le_s, gt_s, ge_s;
    logic lt_u, le_u, gt_u, ge_u;
    
    assign eq   = (a == b);
    assign ne   = (a != b);
    assign lt_s = $signed(a) < $signed(b);
    assign le_s = $signed(a) <= $signed(b);
    assign gt_s = $signed(a) > $signed(b);
    assign ge_s = $signed(a) >= $signed(b);
    assign lt_u = a < b;
    assign le_u = a <= b;
    assign gt_u = a > b;
    assign ge_u = a >= b;
    
    always_comb begin
        if (!active) begin
            result = 1'b0;
        end else begin
            case (func)
                CMP_SEQ:  result = eq;
                CMP_SNE:  result = ne;
                CMP_SLT:  result = lt_s;
                CMP_SLE:  result = le_s;
                CMP_SGT:  result = gt_s;
                CMP_SGE:  result = ge_s;
                CMP_SLTU: result = lt_u;
                CMP_SLEU: result = le_u;
                CMP_SGTU: result = gt_u;
                CMP_SGEU: result = ge_u;
                
                // Predicate operations
                CMP_PAND: result = pred_a & pred_b;
                CMP_POR:  result = pred_a | pred_b;
                CMP_PXOR: result = pred_a ^ pred_b;
                CMP_PNOT: result = ~pred_a;
                
                default:  result = 1'b0;
            endcase
        end
    end

endmodule

//=============================================================================
// GPGPU-1 Multiply/Divide Unit
//=============================================================================
// Description: 8-wide multiply and divide unit
// Note: Division is typically multi-cycle; this is a simplified model
//=============================================================================

module mul_div_unit
    import gpgpu_pkg::*;
(
    /* verilator lint_off UNUSED */
    input  logic                                   clk,
    input  logic                                   rst_n,
    /* verilator lint_on UNUSED */
    
    // Operands
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   operand_a,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   operand_b,
    
    // Control
    input  logic [FUNC_WIDTH-1:0]                  func,
    input  logic [WARP_SIZE-1:0]                   active_mask,
    input  logic                                   valid_in,
    
    // Results
    output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   result,
    output logic                                   valid_out,
    output logic                                   ready       // Ready for new operation
);

    // For simplicity, this is a combinational implementation
    // A real implementation would have multi-cycle division
    
    assign ready = 1'b1;  // Always ready (simplified)
    assign valid_out = valid_in;
    
    genvar t;
    generate
        for (t = 0; t < WARP_SIZE; t++) begin : gen_mul_lanes
            mul_div_lane u_mul_lane (
                .a      (operand_a[t]),
                .b      (operand_b[t]),
                .func   (func),
                .active (active_mask[t]),
                .result (result[t])
            );
        end
    endgenerate

endmodule

//=============================================================================
// Single Multiply/Divide Lane
//=============================================================================

module mul_div_lane
    import gpgpu_pkg::*;
(
    input  logic [DATA_WIDTH-1:0]   a,
    input  logic [DATA_WIDTH-1:0]   b,
    input  logic [FUNC_WIDTH-1:0]   func,
    input  logic                    active,
    output logic [DATA_WIDTH-1:0]   result
);

    // Full 128-bit multiplication results
    logic [127:0] mul_ss;  // signed × signed
    logic [127:0] mul_uu;  // unsigned × unsigned
    logic [127:0] mul_su;  // signed × unsigned
    
    // Division results
    logic [DATA_WIDTH-1:0] div_s;
    logic [DATA_WIDTH-1:0] div_u;
    logic [DATA_WIDTH-1:0] rem_s;
    logic [DATA_WIDTH-1:0] rem_u;
    
    // Signed multiplication
    assign mul_ss = $signed(a) * $signed(b);
    
    // Unsigned multiplication  
    assign mul_uu = a * b;
    
    // Signed × unsigned (a is signed, b is unsigned)
    assign mul_su = $signed({{64{a[63]}}, a}) * $signed({64'b0, b});
    
    // Division with divide-by-zero handling
    always_comb begin
        if (b == '0) begin
            div_s = '1;  // -1 for signed div by zero
            div_u = '1;  // All 1s for unsigned div by zero
            rem_s = a;   // Return dividend as remainder
            rem_u = a;
        end else begin
            div_s = $signed(a) / $signed(b);
            div_u = a / b;
            rem_s = $signed(a) % $signed(b);
            rem_u = a % b;
        end
    end
    
    // Result selection
    always_comb begin
        if (!active) begin
            result = '0;
        end else begin
            case (func)
                MUL_MUL:    result = mul_ss[63:0];    // Lower 64 bits
                MUL_MULH:   result = mul_ss[127:64];  // Upper 64 bits, signed
                MUL_MULHU:  result = mul_uu[127:64];  // Upper 64 bits, unsigned
                MUL_MULHSU: result = mul_su[127:64];  // Upper 64 bits, signed×unsigned
                MUL_DIV:    result = div_s;
                MUL_DIVU:   result = div_u;
                MUL_REM:    result = rem_s;
                MUL_REMU:   result = rem_u;
                default:    result = '0;
            endcase
        end
    end

endmodule

//=============================================================================
// GPGPU-1 Execution Unit Wrapper
//=============================================================================
// Description: Top-level wrapper combining ALU, Shift, Compare, and Mul/Div
//=============================================================================

module execution_unit
    import gpgpu_pkg::*;
(
    input  logic                                   clk,
    input  logic                                   rst_n,
    
    // Operands
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   operand_a,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   operand_b,
    input  logic [WARP_SIZE-1:0]                   pred_a,      // For predicate ops
    input  logic [WARP_SIZE-1:0]                   pred_b,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   special_data, // Special register data for MOVSR
    
    // Control
    input  exec_unit_t                             exec_select, // Which unit to use
    input  opcode_t                                opcode,      // For FPU operation selection
    input  logic [FUNC_WIDTH-1:0]                  func,
    input  logic [WARP_SIZE-1:0]                   active_mask,
    input  logic                                   valid_in,
    
    // Results
    output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]   result,
    output logic [WARP_SIZE-1:0]                   pred_result, // For compare unit
    output logic                                   valid_out,
    output logic                                   ready
);//=========================================================================
    // Unit Results
    //=========================================================================
    
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] alu_result;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] shift_result;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] mul_result;
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] fpu_result;
    logic [WARP_SIZE-1:0]                 cmp_pred_result;
    logic [WARP_SIZE-1:0]                 fpu_pred_result;
    
    logic mul_valid, mul_ready;
    logic mul_selected;
    
    logic fpu_valid, fpu_ready;
    logic fpu_selected;
    
    assign mul_selected = (exec_select == EX_MUL);
    assign fpu_selected = (exec_select == EX_FPU);
    
    //=========================================================================
    // ALU Instance
    //=========================================================================
    
    alu u_alu (
        .operand_a   (operand_a),
        .operand_b   (operand_b),
        .func        (func),
        .active_mask (active_mask),
        .result      (alu_result)
    );
    
    //=========================================================================
    // Shift Unit Instance
    //=========================================================================
    
    shift_unit u_shift (
        .operand_a   (operand_a),
        .operand_b   (operand_b),
        .func        (func),
        .active_mask (active_mask),
        .result      (shift_result)
    );
    
    //=========================================================================
    // Compare Unit Instance
    //=========================================================================
    
    compare_unit u_compare (
        .operand_a   (operand_a),
        .operand_b   (operand_b),
        .pred_a      (pred_a),
        .pred_b      (pred_b),
        .func        (func),
        .active_mask (active_mask),
        .pred_result (cmp_pred_result)
    );
    
    //=========================================================================
    // Multiply/Divide Unit Instance
    //=========================================================================
    
    mul_div_unit u_mul_div (
        .clk         (clk),
        .rst_n       (rst_n),
        .operand_a   (operand_a),
        .operand_b   (operand_b),
        .func        (func),
        .active_mask (active_mask),
        .valid_in    (valid_in && mul_selected),
        .result      (mul_result),
        .valid_out   (mul_valid),
        .ready       (mul_ready)
    );
    
    //=========================================================================
    // Floating-Point Unit Instance
    //=========================================================================
    
    fpu u_fpu (
        .clk         (clk),
        .rst_n       (rst_n),
        .operand_a   (operand_a),
        .operand_b   (operand_b),
        .operand_c   ('0),           // FMA third operand (not used for now)
        .opcode      (opcode),
        .func        (func),
        .active_mask (active_mask),
        .valid_in    (valid_in && fpu_selected),
        .result      (fpu_result),
        .pred_result (fpu_pred_result),
        .valid_out   (fpu_valid),
        .ready       (fpu_ready)
    );
    
    //=========================================================================
    // Result Selection
    //=========================================================================
    
    always_comb begin
        case (exec_select)
            EX_ALU:     result = alu_result;
            EX_SHIFT:   result = shift_result;
            EX_MUL:     result = mul_result;
            EX_FPU:     result = fpu_result;
            EX_CMP:     result = '0;  // Compare outputs to pred_result
            EX_SPECIAL: result = special_data;  // MOVSR uses special register data
            EX_LSU: begin
                // For load/store: compute address = base + offset
                for (int t = 0; t < WARP_SIZE; t++) begin
                    result[t] = operand_a[t] + operand_b[t];
                end
            end
            default:    result = '0;
        endcase
        
        // Select predicate result based on execution unit
        case (exec_select)
            EX_FPU:   pred_result = fpu_pred_result;
            default:  pred_result = cmp_pred_result;
        endcase
    end
      //=========================================================================
    // Control Outputs
    //=========================================================================
    
    always_comb begin
        case (exec_select)
            EX_MUL: begin
                valid_out = mul_valid;
                ready = mul_ready;
            end
            EX_FPU: begin
                valid_out = fpu_valid;
                ready = fpu_ready;
            end
            default: begin
                valid_out = valid_in;
                ready = 1'b1;
            end
        endcase
    end

endmodule
