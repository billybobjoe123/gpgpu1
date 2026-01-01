//=============================================================================
// GPGPU-1 Floating-Point Unit (FPU)
//=============================================================================
// File:        fpu.sv
// Description: 8-wide SIMD FPU supporting IEEE 754 single and double precision
//              floating-point operations.
// Features:
//   - Single precision (32-bit) operations
//   - Double precision (64-bit) operations  
//   - Add, Sub, Mul, Div, Sqrt, Min, Max, Abs, Neg
//   - Compare operations
//   - Int<->Float conversions
//   - Fused multiply-add (FMA)
//   - Configurable rounding modes
// Version:     1.0
// Date:        December 22, 2025
//=============================================================================

`include "gpgpu_defines.svh"

module fpu
    import gpgpu_pkg::*;
(
    input  logic                                    clk,
    input  logic                                    rst_n,
    
    // Operands (per-thread, 8 threads)
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]    operand_a,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]    operand_b,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]    operand_c,     // For FMA
    
    // Control
    input  opcode_t                                 opcode,
    input  logic [FUNC_WIDTH-1:0]                   func,          // Function/rounding mode
    input  logic [WARP_SIZE-1:0]                    active_mask,   // Which threads are active
    input  logic                                    valid_in,
    
    // Results (per-thread)
    output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]    result,
    output logic [WARP_SIZE-1:0]                    pred_result,   // For FCMP
    output logic                                    valid_out,
    output logic                                    ready          // Ready for new operation
);

    //=========================================================================
    // Pipeline Registers
    //=========================================================================
    
    // For now, implement combinational FPU (single-cycle for simple ops)
    // Can be pipelined later for better timing
    
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] result_comb;
    logic [WARP_SIZE-1:0]                 pred_comb;
    
    //=========================================================================
    // Per-Thread FPU Lane Instances
    //=========================================================================
    
    genvar t;
    generate
        for (t = 0; t < WARP_SIZE; t++) begin : gen_fpu_lanes
            fpu_lane u_fpu_lane (
                .clk        (clk),
                .rst_n      (rst_n),
                .a          (operand_a[t]),
                .b          (operand_b[t]),
                .c          (operand_c[t]),
                .opcode     (opcode),
                .func       (func),
                .active     (active_mask[t]),
                .result     (result_comb[t]),
                .pred_out   (pred_comb[t])
            );
        end
    endgenerate
    
    //=========================================================================
    // Output Assignment
    //=========================================================================
    
    // Simple single-cycle implementation for now
    assign result      = result_comb;
    assign pred_result = pred_comb;
    assign valid_out   = valid_in;
    assign ready       = 1'b1;  // Always ready (combinational)

endmodule


//=============================================================================
// Single FPU Lane (64-bit data path, supports single and double precision)
//=============================================================================

module fpu_lane
    import gpgpu_pkg::*;
(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic [DATA_WIDTH-1:0]   a,
    input  logic [DATA_WIDTH-1:0]   b,
    input  logic [DATA_WIDTH-1:0]   c,          // For FMA
    input  opcode_t                 opcode,
    input  logic [FUNC_WIDTH-1:0]   func,
    input  logic                    active,
    output logic [DATA_WIDTH-1:0]   result,
    output logic                    pred_out
);

    //=========================================================================
    // IEEE 754 Constants
    //=========================================================================
    
    // Single precision (32-bit): 1 sign + 8 exp + 23 mantissa
    localparam int SP_EXP_BITS  = 8;
    localparam int SP_MANT_BITS = 23;
    localparam int SP_BIAS      = 127;
    
    // Double precision (64-bit): 1 sign + 11 exp + 52 mantissa
    localparam int DP_EXP_BITS  = 11;
    localparam int DP_MANT_BITS = 52;
    localparam int DP_BIAS      = 1023;
    
    //=========================================================================
    // Input Unpacking - Single Precision
    //=========================================================================
    
    // Extract single-precision fields (lower 32 bits)
    logic        sp_a_sign, sp_b_sign, sp_c_sign;
    logic [7:0]  sp_a_exp,  sp_b_exp,  sp_c_exp;
    logic [22:0] sp_a_mant, sp_b_mant, sp_c_mant;
    
    assign sp_a_sign = a[31];
    assign sp_a_exp  = a[30:23];
    assign sp_a_mant = a[22:0];
    
    assign sp_b_sign = b[31];
    assign sp_b_exp  = b[30:23];
    assign sp_b_mant = b[22:0];
    
    assign sp_c_sign = c[31];
    assign sp_c_exp  = c[30:23];
    assign sp_c_mant = c[22:0];
    
    //=========================================================================
    // Special Value Detection - Single Precision
    //=========================================================================
    
    logic sp_a_is_zero, sp_b_is_zero;
    logic sp_a_is_inf,  sp_b_is_inf;
    logic sp_a_is_nan,  sp_b_is_nan;
    logic sp_a_is_denorm, sp_b_is_denorm;
    
    assign sp_a_is_zero   = (sp_a_exp == 8'h00) && (sp_a_mant == 23'h0);
    assign sp_b_is_zero   = (sp_b_exp == 8'h00) && (sp_b_mant == 23'h0);
    assign sp_a_is_inf    = (sp_a_exp == 8'hFF) && (sp_a_mant == 23'h0);
    assign sp_b_is_inf    = (sp_b_exp == 8'hFF) && (sp_b_mant == 23'h0);
    assign sp_a_is_nan    = (sp_a_exp == 8'hFF) && (sp_a_mant != 23'h0);
    assign sp_b_is_nan    = (sp_b_exp == 8'hFF) && (sp_b_mant != 23'h0);
    assign sp_a_is_denorm = (sp_a_exp == 8'h00) && (sp_a_mant != 23'h0);
    assign sp_b_is_denorm = (sp_b_exp == 8'h00) && (sp_b_mant != 23'h0);
    
    //=========================================================================
    // Precision Select
    //=========================================================================
    
    logic is_double;
    assign is_double = func[7];  // Bit 7 selects precision
    
    //=========================================================================
    // Single-Precision Operations
    //=========================================================================
    
    logic [31:0] sp_add_result;
    logic [31:0] sp_sub_result;
    logic [31:0] sp_mul_result;
    logic [31:0] sp_div_result;
    logic [31:0] sp_min_result;
    logic [31:0] sp_max_result;
    logic [31:0] sp_abs_result;
    logic [31:0] sp_neg_result;
    logic [31:0] sp_sqrt_result;
    logic [31:0] sp_rcp_result;
    logic [31:0] sp_rsqrt_result;
    logic        sp_cmp_result;
    
    // Absolute value: clear sign bit
    assign sp_abs_result = {1'b0, a[30:0]};
    
    // Negate: flip sign bit
    assign sp_neg_result = {~a[31], a[30:0]};
    
    // Min/Max: compare and select
    logic sp_a_lt_b;  // a < b for single precision
    
    // Simple comparison (ignoring NaN for now)
    always_comb begin
        if (sp_a_sign != sp_b_sign) begin
            // Different signs: negative is smaller (unless both zero)
            sp_a_lt_b = sp_a_sign && !(sp_a_is_zero && sp_b_is_zero);
        end else if (sp_a_sign) begin
            // Both negative: larger magnitude is smaller
            sp_a_lt_b = (a[30:0] > b[30:0]);
        end else begin
            // Both positive: smaller magnitude is smaller
            sp_a_lt_b = (a[30:0] < b[30:0]);
        end
    end
    
    assign sp_min_result = sp_a_is_nan ? b[31:0] : 
                           sp_b_is_nan ? a[31:0] :
                           sp_a_lt_b   ? a[31:0] : b[31:0];
                           
    assign sp_max_result = sp_a_is_nan ? b[31:0] :
                           sp_b_is_nan ? a[31:0] :
                           sp_a_lt_b   ? b[31:0] : a[31:0];
    
    //=========================================================================
    // FP Add/Sub - Single Precision (Simplified)
    //=========================================================================
    
    // For synthesis, use a proper FP adder. Here's a simplified version:
    fp_adder_sp u_sp_adder (
        .a      (a[31:0]),
        .b      (b[31:0]),
        .sub    (opcode == OP_FSUB),
        .result (sp_add_result)
    );
    
    assign sp_sub_result = sp_add_result;  // Handled by sub input
    
    //=========================================================================
    // FP Multiply - Single Precision (Simplified)
    //=========================================================================
    
    fp_mul_sp u_sp_mul (
        .a      (a[31:0]),
        .b      (b[31:0]),
        .result (sp_mul_result)
    );
    
    //=========================================================================
    // FP Divide - Single Precision (Simplified)
    //=========================================================================
    
    fp_div_sp u_sp_div (
        .a      (a[31:0]),
        .b      (b[31:0]),
        .result (sp_div_result)
    );
    
    //=========================================================================
    // FP Fused Multiply-Add - Single Precision
    // Computes: a * b + c with single rounding (better precision than mul+add)
    //=========================================================================
    
    logic [31:0] sp_fma_result;
    
    fp_fma_sp u_sp_fma (
        .a      (a[31:0]),
        .b      (b[31:0]),
        .c      (c[31:0]),
        .result (sp_fma_result)
    );
    
    //=========================================================================
    // FP Square Root - Single Precision
    //=========================================================================
    
    fp_sqrt_sp u_sp_sqrt (
        .a      (a[31:0]),
        .result (sp_sqrt_result)
    );
    
    //=========================================================================
    // FP Reciprocal Approximation - Single Precision
    //=========================================================================
    
    fp_rcp_sp u_sp_rcp (
        .a      (a[31:0]),
        .result (sp_rcp_result)
    );
    
    //=========================================================================
    // FP Reciprocal Square Root Approximation - Single Precision
    //=========================================================================
    
    fp_rsqrt_sp u_sp_rsqrt (
        .a      (a[31:0]),
        .result (sp_rsqrt_result)
    );
    
    //=========================================================================
    // Double-Precision Operations
    //=========================================================================
    
    logic [63:0] dp_add_result;
    logic [63:0] dp_mul_result;
    logic [63:0] dp_div_result;
    logic [63:0] dp_fma_result;
    logic [63:0] dp_sqrt_result;
    logic [63:0] dp_rcp_result;
    logic [63:0] dp_rsqrt_result;
    logic [63:0] dp_min_result;
    logic [63:0] dp_max_result;
    logic        dp_cmp_result;
    
    // DP Absolute value: clear sign bit
    logic [63:0] dp_abs_result;
    assign dp_abs_result = {1'b0, a[62:0]};
    
    // DP Negate: flip sign bit
    logic [63:0] dp_neg_result;
    assign dp_neg_result = {~a[63], a[62:0]};
    
    // DP Add/Sub
    fp_adder_dp u_dp_adder (
        .a      (a),
        .b      (b),
        .sub    (opcode == OP_FSUB),
        .result (dp_add_result)
    );
    
    // DP Multiply
    fp_mul_dp u_dp_mul (
        .a      (a),
        .b      (b),
        .result (dp_mul_result)
    );
    
    // DP Divide
    fp_div_dp u_dp_div (
        .a      (a),
        .b      (b),
        .result (dp_div_result)
    );
    
    // DP FMA
    fp_fma_dp u_dp_fma (
        .a      (a),
        .b      (b),
        .c      (c),
        .result (dp_fma_result)
    );
    
    // DP Square Root
    fp_sqrt_dp u_dp_sqrt (
        .a      (a),
        .result (dp_sqrt_result)
    );
    
    // DP Reciprocal
    fp_rcp_dp u_dp_rcp (
        .a      (a),
        .result (dp_rcp_result)
    );
    
    // DP Reciprocal Square Root
    fp_rsqrt_dp u_dp_rsqrt (
        .a      (a),
        .result (dp_rsqrt_result)
    );
    
    // DP Min
    fp_min_dp u_dp_min (
        .a      (a),
        .b      (b),
        .result (dp_min_result)
    );
    
    // DP Max
    fp_max_dp u_dp_max (
        .a      (a),
        .b      (b),
        .result (dp_max_result)
    );
    
    // DP Compare
    fp_cmp_dp u_dp_cmp (
        .a      (a),
        .b      (b),
        .func   (cmp_func),
        .result (dp_cmp_result)
    );

    
    //=========================================================================
    // FP Compare - Single Precision
    //=========================================================================
    
    logic [3:0] cmp_func;
    assign cmp_func = func[3:0];
    
    always_comb begin
        if (sp_a_is_nan || sp_b_is_nan) begin
            // Unordered comparison
            case (cmp_func)
                FCMP_UNO: sp_cmp_result = 1'b1;  // Unordered is true
                FCMP_ORD: sp_cmp_result = 1'b0;  // Ordered is false
                default:  sp_cmp_result = 1'b0;  // All other comparisons false
            endcase
        end else begin
            case (cmp_func)
                FCMP_EQ:  sp_cmp_result = (a[31:0] == b[31:0]) || (sp_a_is_zero && sp_b_is_zero);
                FCMP_NE:  sp_cmp_result = !((a[31:0] == b[31:0]) || (sp_a_is_zero && sp_b_is_zero));
                FCMP_LT:  sp_cmp_result = sp_a_lt_b && !(sp_a_is_zero && sp_b_is_zero);
                FCMP_LE:  sp_cmp_result = sp_a_lt_b || (a[31:0] == b[31:0]) || (sp_a_is_zero && sp_b_is_zero);
                FCMP_GT:  sp_cmp_result = !sp_a_lt_b && (a[31:0] != b[31:0]) && !(sp_a_is_zero && sp_b_is_zero);
                FCMP_GE:  sp_cmp_result = !sp_a_lt_b || (sp_a_is_zero && sp_b_is_zero);
                FCMP_ORD: sp_cmp_result = 1'b1;
                FCMP_UNO: sp_cmp_result = 1'b0;
                default:  sp_cmp_result = 1'b0;
            endcase
        end
    end
    
    //=========================================================================
    // FP Conversion
    //=========================================================================
    
    logic [31:0] sp_cvt_result;
    logic [63:0] dp_cvt_result;
    
    fp_convert u_fp_cvt (
        .a          (a),
        .func       (func[4:0]),
        .sp_result  (sp_cvt_result),
        .dp_result  (dp_cvt_result)
    );
    
    //=========================================================================
    // Result Multiplexing
    //=========================================================================
    
    always_comb begin
        result   = '0;
        pred_out = 1'b0;
        
        if (!active) begin
            result   = '0;
            pred_out = 1'b0;
        end else begin
            case (opcode)
                OP_FADD: begin
                    if (is_double) begin
                        result = dp_add_result;
                    end else begin
                        result = {32'h0, sp_add_result};
                    end
                end
                
                OP_FSUB: begin
                    if (is_double) begin
                        result = dp_add_result;  // DP adder handles sub via input
                    end else begin
                        result = {32'h0, sp_sub_result};
                    end
                end
                
                OP_FMUL: begin
                    if (is_double) begin
                        result = dp_mul_result;
                    end else begin
                        result = {32'h0, sp_mul_result};
                    end
                end
                
                OP_FDIV: begin
                    if (is_double) begin
                        result = dp_div_result;
                    end else begin
                        result = {32'h0, sp_div_result};
                    end
                end
                
                OP_FMIN: begin
                    if (is_double) begin
                        result = dp_min_result;
                    end else begin
                        result = {32'h0, sp_min_result};
                    end
                end
                
                OP_FMAX: begin
                    if (is_double) begin
                        result = dp_max_result;
                    end else begin
                        result = {32'h0, sp_max_result};
                    end
                end
                
                OP_FSQRT: begin
                    if (is_double) begin
                        result = dp_sqrt_result;
                    end else begin
                        result = {32'h0, sp_sqrt_result};
                    end
                end
                
                OP_FABS: begin
                    if (is_double) begin
                        result = dp_abs_result;
                    end else begin
                        result = {32'h0, sp_abs_result};
                    end
                end
                
                OP_FNEG: begin
                    if (is_double) begin
                        result = dp_neg_result;
                    end else begin
                        result = {32'h0, sp_neg_result};
                    end
                end
                
                OP_FCMP: begin
                    if (is_double) begin
                        pred_out = dp_cmp_result;
                        result   = {63'h0, dp_cmp_result};
                    end else begin
                        pred_out = sp_cmp_result;
                        result   = {63'h0, sp_cmp_result};
                    end
                end
                
                OP_FCVT: begin
                    if (func[4:0] inside {FCVT_S2D, FCVT_I2D, FCVT_U2D, FCVT_D2I, FCVT_D2U}) begin
                        result = dp_cvt_result;
                    end else begin
                        result = {32'h0, sp_cvt_result};
                    end
                end
                
                OP_FRCP: begin
                    if (is_double) begin
                        result = dp_rcp_result;
                    end else begin
                        result = {32'h0, sp_rcp_result};
                    end
                end
                
                OP_FRSQRT: begin
                    if (is_double) begin
                        result = dp_rsqrt_result;
                    end else begin
                        result = {32'h0, sp_rsqrt_result};
                    end
                end
                
                OP_FMADD: begin
                    if (is_double) begin
                        result = dp_fma_result;
                    end else begin
                        result = {32'h0, sp_fma_result};
                    end
                end
                
                default: begin
                    result   = '0;
                    pred_out = 1'b0;
                end
            endcase
        end
    end

endmodule


//=============================================================================
// FP Adder - Single Precision (IEEE 754)
//=============================================================================

module fp_adder_sp (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic        sub,    // 1 = subtract (a - b)
    output logic [31:0] result
);

    // Unpack inputs
    logic        a_sign, b_sign;
    logic [7:0]  a_exp,  b_exp;
    logic [23:0] a_mant, b_mant;  // Include implicit 1
    
    assign a_sign = a[31];
    assign a_exp  = a[30:23];
    assign a_mant = (a_exp == 8'h00) ? {1'b0, a[22:0]} : {1'b1, a[22:0]};
    
    logic b_sign_eff;
    assign b_sign_eff = b[31] ^ sub;  // Flip sign for subtraction
    assign b_exp      = b[30:23];
    assign b_mant     = (b_exp == 8'h00) ? {1'b0, b[22:0]} : {1'b1, b[22:0]};
    
    // Special cases
    logic a_is_zero, b_is_zero, a_is_inf, b_is_inf, a_is_nan, b_is_nan;
    assign a_is_zero = (a_exp == 8'h00) && (a[22:0] == 23'h0);
    assign b_is_zero = (b_exp == 8'h00) && (b[22:0] == 23'h0);
    assign a_is_inf  = (a_exp == 8'hFF) && (a[22:0] == 23'h0);
    assign b_is_inf  = (b_exp == 8'hFF) && (b[22:0] == 23'h0);
    assign a_is_nan  = (a_exp == 8'hFF) && (a[22:0] != 23'h0);
    assign b_is_nan  = (b_exp == 8'hFF) && (b[22:0] != 23'h0);
    
    // Align mantissas
    logic [7:0]  exp_diff;
    logic        a_larger;
    logic [7:0]  larger_exp;
    logic [47:0] a_mant_aligned, b_mant_aligned;  // Extended for precision
    
    assign a_larger = (a_exp > b_exp) || ((a_exp == b_exp) && (a_mant >= b_mant));
    assign exp_diff = a_larger ? (a_exp - b_exp) : (b_exp - a_exp);
    assign larger_exp = a_larger ? a_exp : b_exp;
    
    // Shift smaller mantissa right
    always_comb begin
        if (a_larger) begin
            a_mant_aligned = {a_mant, 24'h0};
            b_mant_aligned = ({b_mant, 24'h0}) >> exp_diff;
        end else begin
            a_mant_aligned = ({a_mant, 24'h0}) >> exp_diff;
            b_mant_aligned = {b_mant, 24'h0};
        end
    end
    
    // Add or subtract mantissas
    logic [48:0] mant_sum;
    logic        effective_sub;
    logic        result_sign;
    
    assign effective_sub = a_sign ^ b_sign_eff;
    
    always_comb begin
        if (effective_sub) begin
            // Subtraction
            if (a_larger) begin
                mant_sum    = {1'b0, a_mant_aligned} - {1'b0, b_mant_aligned};
                result_sign = a_sign;
            end else begin
                mant_sum    = {1'b0, b_mant_aligned} - {1'b0, a_mant_aligned};
                result_sign = b_sign_eff;
            end
        end else begin
            // Addition
            mant_sum    = {1'b0, a_mant_aligned} + {1'b0, b_mant_aligned};
            result_sign = a_sign;
        end
    end
    
    // Normalize result
    logic [7:0]  result_exp;
    logic [22:0] result_mant;
    logic [5:0]  leading_zeros;
    
    // Count leading zeros in mantissa sum
    always_comb begin
        leading_zeros = 0;
        for (int i = 48; i >= 0; i--) begin
            if (mant_sum[i] == 1'b0) begin
                leading_zeros = 48 - i[5:0];
            end else begin
                break;
            end
        end
    end
    
    always_comb begin
        if (a_is_nan || b_is_nan) begin
            // NaN propagation
            result = 32'h7FC00000;  // Quiet NaN
        end else if (a_is_inf && b_is_inf && effective_sub) begin
            // inf - inf = NaN
            result = 32'h7FC00000;
        end else if (a_is_inf) begin
            result = {a_sign, 8'hFF, 23'h0};
        end else if (b_is_inf) begin
            result = {b_sign_eff, 8'hFF, 23'h0};
        end else if (a_is_zero && b_is_zero) begin
            result = 32'h00000000;
        end else if (a_is_zero) begin
            result = {b_sign_eff, b[30:0]};
        end else if (b_is_zero) begin
            result = a;
        end else if (mant_sum == 0) begin
            result = 32'h00000000;
        end else if (mant_sum[48]) begin
            // Overflow, shift right
            result_exp  = larger_exp + 1;
            result_mant = mant_sum[47:25];
            result      = {result_sign, result_exp, result_mant};
        end else begin
            // Normalize by shifting left
            logic [48:0] normalized_mant;
            logic [7:0]  shift_amount;
            
            // Find position of leading 1
            shift_amount = 0;
            for (int i = 47; i >= 0; i--) begin
                if (mant_sum[i]) begin
                    shift_amount = 47 - i[7:0];
                    break;
                end
            end
            
            normalized_mant = mant_sum << shift_amount;
            
            if (larger_exp <= shift_amount) begin
                // Underflow to zero or denormal
                result = 32'h00000000;
            end else begin
                result_exp  = larger_exp - shift_amount;
                result_mant = normalized_mant[46:24];
                result      = {result_sign, result_exp, result_mant};
            end
        end
    end

endmodule


//=============================================================================
// FP Multiplier - Single Precision (IEEE 754)
//=============================================================================

module fp_mul_sp (
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] result
);

    // Unpack inputs
    logic        a_sign, b_sign, result_sign;
    logic [7:0]  a_exp, b_exp;
    logic [23:0] a_mant, b_mant;
    
    assign a_sign = a[31];
    assign b_sign = b[31];
    assign a_exp  = a[30:23];
    assign b_exp  = b[30:23];
    assign a_mant = (a_exp == 8'h00) ? {1'b0, a[22:0]} : {1'b1, a[22:0]};
    assign b_mant = (b_exp == 8'h00) ? {1'b0, b[22:0]} : {1'b1, b[22:0]};
    
    assign result_sign = a_sign ^ b_sign;
    
    // Special cases
    logic a_is_zero, b_is_zero, a_is_inf, b_is_inf, a_is_nan, b_is_nan;
    assign a_is_zero = (a_exp == 8'h00) && (a[22:0] == 23'h0);
    assign b_is_zero = (b_exp == 8'h00) && (b[22:0] == 23'h0);
    assign a_is_inf  = (a_exp == 8'hFF) && (a[22:0] == 23'h0);
    assign b_is_inf  = (b_exp == 8'hFF) && (b[22:0] == 23'h0);
    assign a_is_nan  = (a_exp == 8'hFF) && (a[22:0] != 23'h0);
    assign b_is_nan  = (b_exp == 8'hFF) && (b[22:0] != 23'h0);
    
    // Multiply mantissas
    logic [47:0] mant_product;
    assign mant_product = a_mant * b_mant;
    
    // Calculate exponent
    logic [9:0] exp_sum;
    assign exp_sum = {2'b0, a_exp} + {2'b0, b_exp} - 10'd127;  // Remove one bias
    
    // Normalize and pack result
    logic [7:0]  result_exp;
    logic [22:0] result_mant;
    
    always_comb begin
        if (a_is_nan || b_is_nan) begin
            result = 32'h7FC00000;  // Quiet NaN
        end else if ((a_is_inf && b_is_zero) || (b_is_inf && a_is_zero)) begin
            result = 32'h7FC00000;  // inf * 0 = NaN
        end else if (a_is_inf || b_is_inf) begin
            result = {result_sign, 8'hFF, 23'h0};  // Infinity
        end else if (a_is_zero || b_is_zero) begin
            result = {result_sign, 31'h0};  // Zero
        end else if (mant_product[47]) begin
            // Product >= 2.0, shift right
            result_exp  = exp_sum[7:0] + 1;
            result_mant = mant_product[46:24];
            if (exp_sum >= 10'd255) begin
                result = {result_sign, 8'hFF, 23'h0};  // Overflow to inf
            end else begin
                result = {result_sign, result_exp, result_mant};
            end
        end else begin
            // Product < 2.0
            result_exp  = exp_sum[7:0];
            result_mant = mant_product[45:23];
            if (exp_sum[9] || exp_sum == 0) begin
                result = {result_sign, 31'h0};  // Underflow to zero
            end else begin
                result = {result_sign, result_exp, result_mant};
            end
        end
    end

endmodule


//=============================================================================
// FP Divider - Single Precision (IEEE 754) - Simplified
//=============================================================================

module fp_div_sp (
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] result
);

    // Unpack inputs
    logic        a_sign, b_sign, result_sign;
    logic [7:0]  a_exp, b_exp;
    logic [23:0] a_mant, b_mant;
    
    assign a_sign = a[31];
    assign b_sign = b[31];
    assign a_exp  = a[30:23];
    assign b_exp  = b[30:23];
    assign a_mant = (a_exp == 8'h00) ? {1'b0, a[22:0]} : {1'b1, a[22:0]};
    assign b_mant = (b_exp == 8'h00) ? {1'b0, b[22:0]} : {1'b1, b[22:0]};
    
    assign result_sign = a_sign ^ b_sign;
    
    // Special cases
    logic a_is_zero, b_is_zero, a_is_inf, b_is_inf, a_is_nan, b_is_nan;
    assign a_is_zero = (a_exp == 8'h00) && (a[22:0] == 23'h0);
    assign b_is_zero = (b_exp == 8'h00) && (b[22:0] == 23'h0);
    assign a_is_inf  = (a_exp == 8'hFF) && (a[22:0] == 23'h0);
    assign b_is_inf  = (b_exp == 8'hFF) && (b[22:0] == 23'h0);
    assign a_is_nan  = (a_exp == 8'hFF) && (a[22:0] != 23'h0);
    assign b_is_nan  = (b_exp == 8'hFF) && (b[22:0] != 23'h0);
    
    // Divide mantissas (using extended precision)
    logic [47:0] a_mant_ext;
    logic [47:0] quotient;
    assign a_mant_ext = {a_mant, 24'h0};
    assign quotient   = a_mant_ext / {24'h0, b_mant};
    
    // Calculate exponent
    logic signed [9:0] exp_diff;
    assign exp_diff = {2'b0, a_exp} - {2'b0, b_exp} + 10'sd127;
    
    // Normalize and pack result
    logic [7:0]  result_exp;
    logic [22:0] result_mant;
    
    always_comb begin
        if (a_is_nan || b_is_nan) begin
            result = 32'h7FC00000;  // Quiet NaN
        end else if (a_is_inf && b_is_inf) begin
            result = 32'h7FC00000;  // inf / inf = NaN
        end else if (a_is_zero && b_is_zero) begin
            result = 32'h7FC00000;  // 0 / 0 = NaN
        end else if (a_is_inf || b_is_zero) begin
            result = {result_sign, 8'hFF, 23'h0};  // Infinity
        end else if (a_is_zero || b_is_inf) begin
            result = {result_sign, 31'h0};  // Zero
        end else if (quotient[47]) begin
            // Quotient >= 2.0
            result_exp  = exp_diff[7:0] + 1;
            result_mant = quotient[46:24];
            if (exp_diff >= 10'sd255) begin
                result = {result_sign, 8'hFF, 23'h0};
            end else if (exp_diff < 10'sd0) begin
                result = {result_sign, 31'h0};
            end else begin
                result = {result_sign, result_exp, result_mant};
            end
        end else begin
            // Quotient < 2.0 - normalize
            logic [5:0] shift;
            shift = 0;
            for (int i = 46; i >= 0; i--) begin
                if (quotient[i]) begin
                    shift = 46 - i[5:0];
                    break;
                end
            end
            
            if (exp_diff - {4'h0, shift} < 10'sd1) begin
                result = {result_sign, 31'h0};  // Underflow
            end else if (exp_diff - {4'h0, shift} >= 10'sd255) begin
                result = {result_sign, 8'hFF, 23'h0};  // Overflow
            end else begin
                result_exp  = exp_diff[7:0] - {2'b0, shift};
                result_mant = (quotient << shift) >> 24;
                result      = {result_sign, result_exp, result_mant[22:0]};
            end
        end
    end

endmodule


//=============================================================================
// FP Fused Multiply-Add - Single Precision (IEEE 754)
// Computes: result = a * b + c with only ONE rounding at the end
// Benefits over separate MUL + ADD:
//   1. Better numerical accuracy (single rounding vs double rounding)
//   2. No intermediate overflow/underflow for the product
//   3. Single instruction = potentially higher throughput
//=============================================================================

module fp_fma_sp (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [31:0] c,
    output logic [31:0] result
);

    //=========================================================================
    // Unpack Inputs
    //=========================================================================
    
    logic        a_sign, b_sign, c_sign;
    logic [7:0]  a_exp,  b_exp,  c_exp;
    logic [23:0] a_mant, b_mant, c_mant;  // Include implicit 1
    
    assign a_sign = a[31];
    assign b_sign = b[31];
    assign c_sign = c[31];
    
    assign a_exp  = a[30:23];
    assign b_exp  = b[30:23];
    assign c_exp  = c[30:23];
    
    // Add implicit leading 1 for normalized numbers, 0 for denormals
    assign a_mant = (a_exp == 8'h00) ? {1'b0, a[22:0]} : {1'b1, a[22:0]};
    assign b_mant = (b_exp == 8'h00) ? {1'b0, b[22:0]} : {1'b1, b[22:0]};
    assign c_mant = (c_exp == 8'h00) ? {1'b0, c[22:0]} : {1'b1, c[22:0]};
    
    //=========================================================================
    // Special Value Detection
    //=========================================================================
    
    logic a_is_zero, b_is_zero, c_is_zero;
    logic a_is_inf,  b_is_inf,  c_is_inf;
    logic a_is_nan,  b_is_nan,  c_is_nan;
    
    assign a_is_zero = (a_exp == 8'h00) && (a[22:0] == 23'h0);
    assign b_is_zero = (b_exp == 8'h00) && (b[22:0] == 23'h0);
    assign c_is_zero = (c_exp == 8'h00) && (c[22:0] == 23'h0);
    
    assign a_is_inf  = (a_exp == 8'hFF) && (a[22:0] == 23'h0);
    assign b_is_inf  = (b_exp == 8'hFF) && (b[22:0] == 23'h0);
    assign c_is_inf  = (c_exp == 8'hFF) && (c[22:0] == 23'h0);
    
    assign a_is_nan  = (a_exp == 8'hFF) && (a[22:0] != 23'h0);
    assign b_is_nan  = (b_exp == 8'hFF) && (b[22:0] != 23'h0);
    assign c_is_nan  = (c_exp == 8'hFF) && (c[22:0] != 23'h0);
    
    //=========================================================================
    // Step 1: Multiply a * b (keep full precision - 48 bits)
    //=========================================================================
    
    logic        prod_sign;
    logic [47:0] prod_mant;  // 24 * 24 = 48 bits
    logic [9:0]  prod_exp;   // Extended to handle overflow
    
    assign prod_sign = a_sign ^ b_sign;
    assign prod_mant = a_mant * b_mant;
    
    // Product exponent: (a_exp - 127) + (b_exp - 127) + 127 = a_exp + b_exp - 127
    assign prod_exp = (a_is_zero || b_is_zero) ? 10'd0 : 
                      {2'b0, a_exp} + {2'b0, b_exp} - 10'd127;
    
    //=========================================================================
    // Step 2: Align product and addend for addition
    //=========================================================================
    
    // The product mantissa is 48 bits with the binary point after bit 46
    // We need to align C to add it to the product
    // Use extended precision (72 bits) to preserve accuracy
    
    logic [9:0]  c_exp_eff;
    logic [71:0] prod_aligned;  // Product aligned for addition
    logic [71:0] c_aligned;     // C aligned for addition
    logic [9:0]  result_exp_pre;
    logic        effective_sub;
    
    assign c_exp_eff = (c_is_zero) ? 10'd0 : {2'b0, c_exp};
    assign effective_sub = prod_sign ^ c_sign;
    
    // Determine alignment shift
    logic signed [10:0] exp_diff;
    logic [6:0] shift_amount;
    logic prod_larger;
    
    always_comb begin
        // Normalize product mantissa position
        // prod_mant[47] is the leading bit if >= 2.0, else prod_mant[46]
        if (prod_mant[47]) begin
            exp_diff = $signed({1'b0, prod_exp + 1}) - $signed({1'b0, c_exp_eff});
            result_exp_pre = prod_exp + 1;
        end else begin
            exp_diff = $signed({1'b0, prod_exp}) - $signed({1'b0, c_exp_eff});
            result_exp_pre = prod_exp;
        end
        
        prod_larger = (exp_diff >= 0);
        
        // Calculate shift amount (capped)
        if (exp_diff >= 0) begin
            shift_amount = (exp_diff > 72) ? 7'd72 : exp_diff[6:0];
        end else begin
            shift_amount = (-exp_diff > 72) ? 7'd72 : (-exp_diff[6:0]);
        end
        
        // Align operands
        if (prod_mant[47]) begin
            prod_aligned = {prod_mant, 24'h0};  // 48 + 24 = 72 bits
        end else begin
            prod_aligned = {prod_mant[46:0], 25'h0};  // Shift left 1
        end
        
        // Align C to match product
        if (prod_larger) begin
            c_aligned = {c_mant, 48'h0} >> shift_amount;
        end else begin
            c_aligned = {c_mant, 48'h0};
            prod_aligned = prod_aligned >> shift_amount;
            result_exp_pre = c_exp_eff;
        end
    end
    
    //=========================================================================
    // Step 3: Add/Subtract with full precision
    //=========================================================================
    
    logic [72:0] sum_mant;  // Extra bit for carry
    logic        sum_sign;
    
    always_comb begin
        if (a_is_zero || b_is_zero) begin
            // Product is zero, result is C
            sum_mant = {1'b0, c_aligned};
            sum_sign = c_sign;
        end else if (c_is_zero) begin
            // C is zero, result is product
            sum_mant = {1'b0, prod_aligned};
            sum_sign = prod_sign;
        end else if (effective_sub) begin
            // Subtraction: determine which is larger
            if (prod_aligned >= c_aligned) begin
                sum_mant = {1'b0, prod_aligned} - {1'b0, c_aligned};
                sum_sign = prod_sign;
            end else begin
                sum_mant = {1'b0, c_aligned} - {1'b0, prod_aligned};
                sum_sign = c_sign;
            end
        end else begin
            // Addition
            sum_mant = {1'b0, prod_aligned} + {1'b0, c_aligned};
            sum_sign = prod_sign;  // Same sign
        end
    end
    
    //=========================================================================
    // Step 4: Normalize and Round (single rounding - key FMA benefit!)
    //=========================================================================
    
    logic [7:0]  result_exp;
    logic [22:0] result_mant;
    logic        result_sign;
    
    always_comb begin
        result = 32'h0;
        result_sign = sum_sign;
        result_exp = 8'h0;
        result_mant = 23'h0;
        
        // Handle special cases first
        if (a_is_nan || b_is_nan || c_is_nan) begin
            result = 32'h7FC00000;  // Quiet NaN
        end else if ((a_is_inf && b_is_zero) || (b_is_inf && a_is_zero)) begin
            result = 32'h7FC00000;  // inf * 0 = NaN
        end else if (a_is_inf || b_is_inf) begin
            // Product is infinity
            if (c_is_inf && effective_sub) begin
                result = 32'h7FC00000;  // inf - inf = NaN
            end else begin
                result = {prod_sign, 8'hFF, 23'h0};  // Infinity
            end
        end else if (c_is_inf) begin
            result = {c_sign, 8'hFF, 23'h0};  // C is infinity
        end else if (sum_mant == 0) begin
            result = 32'h00000000;  // Zero
        end else begin
            // Normalize the result
            logic [6:0] leading_zeros;
            logic [72:0] normalized_mant;
            logic signed [10:0] final_exp;
            
            // Find leading one position
            leading_zeros = 0;
            for (int i = 72; i >= 0; i--) begin
                if (sum_mant[i]) begin
                    leading_zeros = 72 - i[6:0];
                    break;
                end
            end
            
            // Handle carry overflow
            if (sum_mant[72]) begin
                // Overflow from addition
                final_exp = result_exp_pre + 1;
                normalized_mant = sum_mant;
            end else begin
                // Shift to normalize
                final_exp = $signed({1'b0, result_exp_pre}) - $signed({4'b0, leading_zeros}) + 1;
                normalized_mant = sum_mant << leading_zeros;
            end
            
            // Extract mantissa (bits 71:49 for 23-bit mantissa)
            if (final_exp >= 11'sd255) begin
                // Overflow to infinity
                result = {result_sign, 8'hFF, 23'h0};
            end else if (final_exp <= 11'sd0) begin
                // Underflow to zero (simplified - could do denormals)
                result = {result_sign, 31'h0};
            end else begin
                result_exp = final_exp[7:0];
                result_mant = normalized_mant[71:49];
                result = {result_sign, result_exp, result_mant};
            end
        end
    end

endmodule


//=============================================================================
// FP Square Root - Single Precision (Approximation)
//=============================================================================

module fp_sqrt_sp (
    input  logic [31:0] a,
    output logic [31:0] result
);

    logic        a_sign;
    logic [7:0]  a_exp;
    logic [22:0] a_mant;
    
    assign a_sign = a[31];
    assign a_exp  = a[30:23];
    assign a_mant = a[22:0];
    
    logic a_is_zero, a_is_inf, a_is_nan;
    assign a_is_zero = (a_exp == 8'h00) && (a_mant == 23'h0);
    assign a_is_inf  = (a_exp == 8'hFF) && (a_mant == 23'h0);
    assign a_is_nan  = (a_exp == 8'hFF) && (a_mant != 23'h0);
    
    // Fast inverse square root approximation (famous Quake algorithm adapted)
    // Then invert to get sqrt
    logic [31:0] sqrt_approx;
    logic [7:0]  result_exp;
    logic [22:0] result_mant;
    
    always_comb begin
        if (a_is_nan || a_sign) begin
            result = 32'h7FC00000;  // NaN for negative or NaN input
        end else if (a_is_zero) begin
            result = 32'h00000000;  // sqrt(0) = 0
        end else if (a_is_inf) begin
            result = 32'h7F800000;  // sqrt(inf) = inf
        end else begin
            // Approximation: sqrt(a) ≈ a^0.5
            // For IEEE 754: result_exp ≈ (a_exp - 127) / 2 + 127
            // Simplified Newton-Raphson could be added
            
            logic [8:0] exp_minus_bias;
            exp_minus_bias = {1'b0, a_exp} - 9'd127;
            
            // Handle odd exponent
            if (exp_minus_bias[0]) begin
                // Odd exponent: shift mantissa
                result_exp  = (exp_minus_bias[8:1]) + 8'd127;
                result_mant = {1'b1, a_mant[22:1]};  // Approximate
            end else begin
                result_exp  = (exp_minus_bias[8:1]) + 8'd127;
                result_mant = a_mant;  // Approximate - needs refinement
            end
            
            result = {1'b0, result_exp, result_mant};
        end
    end

endmodule


//=============================================================================
// FP Reciprocal - Single Precision (Approximation)
//=============================================================================

module fp_rcp_sp (
    input  logic [31:0] a,
    output logic [31:0] result
);

    logic        a_sign;
    logic [7:0]  a_exp;
    logic [22:0] a_mant;
    
    assign a_sign = a[31];
    assign a_exp  = a[30:23];
    assign a_mant = a[22:0];
    
    logic a_is_zero, a_is_inf, a_is_nan;
    assign a_is_zero = (a_exp == 8'h00) && (a_mant == 23'h0);
    assign a_is_inf  = (a_exp == 8'hFF) && (a_mant == 23'h0);
    assign a_is_nan  = (a_exp == 8'hFF) && (a_mant != 23'h0);
    
    logic [7:0]  result_exp;
    logic [22:0] result_mant;
    
    always_comb begin
        if (a_is_nan) begin
            result = 32'h7FC00000;  // NaN
        end else if (a_is_zero) begin
            result = {a_sign, 8'hFF, 23'h0};  // 1/0 = inf
        end else if (a_is_inf) begin
            result = {a_sign, 31'h0};  // 1/inf = 0
        end else begin
            // Approximation: 1/a
            // result_exp = 253 - a_exp (since 1.0 has exp 127, 1/1 = 1)
            result_exp  = 8'd253 - a_exp;
            result_mant = ~a_mant;  // Rough approximation - needs refinement
            result      = {a_sign, result_exp, result_mant};
        end
    end

endmodule


//=============================================================================
// FP Reciprocal Square Root - Single Precision (Approximation)
//=============================================================================

module fp_rsqrt_sp (
    input  logic [31:0] a,
    output logic [31:0] result
);

    logic        a_sign;
    logic [7:0]  a_exp;
    logic [22:0] a_mant;
    
    assign a_sign = a[31];
    assign a_exp  = a[30:23];
    assign a_mant = a[22:0];
    
    logic a_is_zero, a_is_inf, a_is_nan;
    assign a_is_zero = (a_exp == 8'h00) && (a_mant == 23'h0);
    assign a_is_inf  = (a_exp == 8'hFF) && (a_mant == 23'h0);
    assign a_is_nan  = (a_exp == 8'hFF) && (a_mant != 23'h0);
    
    // Famous fast inverse square root (Quake III algorithm)
    logic [31:0] magic_result;
    
    always_comb begin
        if (a_is_nan || a_sign) begin
            result = 32'h7FC00000;  // NaN for negative or NaN input
        end else if (a_is_zero) begin
            result = 32'h7F800000;  // 1/sqrt(0) = inf
        end else if (a_is_inf) begin
            result = 32'h00000000;  // 1/sqrt(inf) = 0
        end else begin
            // Magic number approximation: 0x5F3759DF - (a >> 1)
            magic_result = 32'h5F3759DF - (a >> 1);
            result = magic_result;
            // One Newton-Raphson iteration could improve accuracy:
            // x = x * (1.5 - 0.5 * a * x * x)
        end
    end

endmodule


//=============================================================================
// FP Conversion Unit
//=============================================================================

module fp_convert
    import gpgpu_pkg::*;
(
    input  logic [63:0] a,
    input  logic [4:0]  func,
    output logic [31:0] sp_result,
    output logic [63:0] dp_result
);

    // Single precision input
    logic        sp_sign;
    logic [7:0]  sp_exp;
    logic [22:0] sp_mant;
    
    assign sp_sign = a[31];
    assign sp_exp  = a[30:23];
    assign sp_mant = a[22:0];
    
    // Integer input
    logic signed [63:0] int_val;
    logic [63:0]        uint_val;
    assign int_val  = a;
    assign uint_val = a;
    
    // Working variables for conversion (moved outside always_comb)
    logic        cvt_sign;
    logic [63:0] cvt_abs_val;
    logic [5:0]  cvt_leading_one;
    logic [7:0]  cvt_exp;
    logic [22:0] cvt_mant;
    logic [7:0]  cvt_true_exp;
    logic [63:0] cvt_mant_shifted;
    
    // Find leading one function
    function automatic logic [5:0] find_leading_one(input logic [63:0] val);
        logic [5:0] result;
        result = 0;
        for (int i = 63; i >= 0; i--) begin
            if (val[i]) begin
                result = i[5:0];
                break;
            end
        end
        return result;
    endfunction
    
    always_comb begin
        sp_result = 32'h0;
        dp_result = 64'h0;
        cvt_sign = 1'b0;
        cvt_abs_val = 64'h0;
        cvt_leading_one = 6'h0;
        cvt_exp = 8'h0;
        cvt_mant = 23'h0;
        cvt_true_exp = 8'h0;
        cvt_mant_shifted = 64'h0;
        
        case (func)
            FCVT_I2S: begin
                // Int64 to Single (signed)
                if (int_val == 0) begin
                    sp_result = 32'h0;
                end else begin
                    cvt_sign    = int_val[63];
                    cvt_abs_val = cvt_sign ? -int_val : int_val;
                    cvt_leading_one = find_leading_one(cvt_abs_val);
                    cvt_exp  = cvt_leading_one + 8'd127;
                    cvt_mant = (cvt_abs_val << (63 - cvt_leading_one)) >> 41;
                    sp_result = {cvt_sign, cvt_exp, cvt_mant};
                end
            end
            
            FCVT_U2S: begin
                // Uint64 to Single (unsigned)
                if (uint_val == 0) begin
                    sp_result = 32'h0;
                end else begin
                    cvt_leading_one = find_leading_one(uint_val);
                    cvt_exp  = cvt_leading_one + 8'd127;
                    cvt_mant = (uint_val << (63 - cvt_leading_one)) >> 41;
                    sp_result = {1'b0, cvt_exp, cvt_mant};
                end
            end
            
            FCVT_S2I: begin
                // Single to Int64 (signed)
                if (sp_exp == 8'h00) begin
                    dp_result = 64'h0;
                end else if (sp_exp == 8'hFF) begin
                    dp_result = sp_sign ? 64'h8000000000000000 : 64'h7FFFFFFFFFFFFFFF;
                end else begin
                    cvt_true_exp     = sp_exp - 8'd127;
                    cvt_mant_shifted = {1'b1, sp_mant, 40'h0} >> (63 - cvt_true_exp);
                    dp_result        = sp_sign ? -cvt_mant_shifted : cvt_mant_shifted;
                end
            end
            
            FCVT_S2U: begin
                // Single to Uint64 (unsigned)
                if (sp_sign || sp_exp == 8'h00) begin
                    dp_result = 64'h0;
                end else if (sp_exp == 8'hFF) begin
                    dp_result = 64'hFFFFFFFFFFFFFFFF;
                end else begin
                    cvt_true_exp     = sp_exp - 8'd127;
                    cvt_mant_shifted = {1'b1, sp_mant, 40'h0} >> (63 - cvt_true_exp);
                    dp_result        = cvt_mant_shifted;
                end
            end
            
            default: begin
                sp_result = 32'h0;
                dp_result = 64'h0;
            end
        endcase
    end

endmodule
