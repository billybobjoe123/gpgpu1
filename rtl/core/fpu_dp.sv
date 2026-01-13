//=============================================================================
// GPGPU-1 Double-Precision Floating-Point Units
//=============================================================================
// File:        fpu_dp.sv
// Description: IEEE 754 double-precision (64-bit) floating-point operations
// Features:
//   - Add, Sub, Mul, Div, Sqrt
//   - Min, Max, Abs, Neg
//   - Compare operations
//   - Fused Multiply-Add (FMA)
// Version:     1.0
// Date:        January 1, 2026
//=============================================================================

`default_nettype none

/* verilator lint_off DECLFILENAME */

`include "gpgpu_defines.svh"

//=============================================================================
// FP Adder - Double Precision (IEEE 754)
//=============================================================================

module fp_adder_dp (
    input  logic [63:0] a,
    input  logic [63:0] b,
    input  logic        sub,    // 1 = subtract (a - b)
    output logic [63:0] result
);

    // IEEE 754 Double: 1 sign + 11 exp + 52 mantissa
    localparam int DP_EXP_BITS  = 11;
    localparam int DP_MANT_BITS = 52;
    localparam int DP_BIAS      = 1023;

    // Unpack inputs
    logic        a_sign, b_sign;
    logic [10:0] a_exp,  b_exp;
    logic [52:0] a_mant, b_mant;  // Include implicit 1
    
    assign a_sign = a[63];
    assign a_exp  = a[62:52];
    assign a_mant = (a_exp == 11'h000) ? {1'b0, a[51:0]} : {1'b1, a[51:0]};
    
    logic b_sign_eff;
    assign b_sign_eff = b[63] ^ sub;  // Flip sign for subtraction
    assign b_exp      = b[62:52];
    assign b_mant     = (b_exp == 11'h000) ? {1'b0, b[51:0]} : {1'b1, b[51:0]};
    
    // Special cases
    logic a_is_zero, b_is_zero, a_is_inf, b_is_inf, a_is_nan, b_is_nan;
    assign a_is_zero = (a_exp == 11'h000) && (a[51:0] == 52'h0);
    assign b_is_zero = (b_exp == 11'h000) && (b[51:0] == 52'h0);
    assign a_is_inf  = (a_exp == 11'h7FF) && (a[51:0] == 52'h0);
    assign b_is_inf  = (b_exp == 11'h7FF) && (b[51:0] == 52'h0);
    assign a_is_nan  = (a_exp == 11'h7FF) && (a[51:0] != 52'h0);
    assign b_is_nan  = (b_exp == 11'h7FF) && (b[51:0] != 52'h0);
    
    // Align mantissas
    logic [10:0] exp_diff;
    logic        a_larger;
    logic [10:0] larger_exp;
    logic [105:0] a_mant_aligned, b_mant_aligned;  // Extended for precision
    
    assign a_larger = (a_exp > b_exp) || ((a_exp == b_exp) && (a_mant >= b_mant));
    assign exp_diff = a_larger ? (a_exp - b_exp) : (b_exp - a_exp);
    assign larger_exp = a_larger ? a_exp : b_exp;
    
    // Shift smaller mantissa right
    always_comb begin
        if (a_larger) begin
            a_mant_aligned = {a_mant, 53'h0};
            b_mant_aligned = ({b_mant, 53'h0}) >> exp_diff;
        end else begin
            a_mant_aligned = ({a_mant, 53'h0}) >> exp_diff;
            b_mant_aligned = {b_mant, 53'h0};
        end
    end
    
    // Add or subtract mantissas
    logic [106:0] mant_sum;
    logic         effective_sub;
    logic         result_sign;
    
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
    logic [10:0] result_exp;
    logic [51:0] result_mant;
    logic [106:0] normalized_mant;
    logic [10:0]  shift_amount;
    
    always_comb begin
        result_exp  = '0;
        result_mant = '0;
        normalized_mant = '0;
        shift_amount = '0;
        if (a_is_nan || b_is_nan) begin
            // NaN propagation
            result = 64'h7FF8000000000000;  // Quiet NaN
        end else if (a_is_inf && b_is_inf && effective_sub) begin
            // inf - inf = NaN
            result = 64'h7FF8000000000000;
        end else if (a_is_inf) begin
            result = {a_sign, 11'h7FF, 52'h0};
        end else if (b_is_inf) begin
            result = {b_sign_eff, 11'h7FF, 52'h0};
        end else if (a_is_zero && b_is_zero) begin
            result = 64'h0000000000000000;
        end else if (a_is_zero) begin
            result = {b_sign_eff, b[62:0]};
        end else if (b_is_zero) begin
            result = a;
        end else if (mant_sum == 0) begin
            result = 64'h0000000000000000;
        end else if (mant_sum[106]) begin
            // Overflow, shift right
            result_exp  = larger_exp + 11'd1;
            result_mant = mant_sum[105:54];
            result      = {result_sign, result_exp, result_mant};
        end else begin
            // Normalize by shifting left
            
            // Find position of leading 1
            shift_amount = 0;
            for (int i = 105; i >= 0; i--) begin
                if (mant_sum[i]) begin
                    shift_amount = 105 - i[10:0];
                    break;
                end
            end
            
            normalized_mant = mant_sum << shift_amount;
            
            if (larger_exp <= shift_amount) begin
                // Underflow to zero or denormal
                result = 64'h0000000000000000;
            end else begin
                result_exp  = larger_exp - shift_amount;
                result_mant = normalized_mant[104:53];
                result      = {result_sign, result_exp, result_mant};
            end
        end
    end

endmodule


//=============================================================================
// FP Multiplier - Double Precision (IEEE 754)
//=============================================================================

module fp_mul_dp (
    input  logic [63:0] a,
    input  logic [63:0] b,
    output logic [63:0] result
);

    // Unpack inputs
    logic        a_sign, b_sign, result_sign;
    logic [10:0] a_exp, b_exp;
    logic [52:0] a_mant, b_mant;
    
    assign a_sign = a[63];
    assign b_sign = b[63];
    assign a_exp  = a[62:52];
    assign b_exp  = b[62:52];
    assign a_mant = (a_exp == 11'h000) ? {1'b0, a[51:0]} : {1'b1, a[51:0]};
    assign b_mant = (b_exp == 11'h000) ? {1'b0, b[51:0]} : {1'b1, b[51:0]};
    
    assign result_sign = a_sign ^ b_sign;
    
    // Special cases
    logic a_is_zero, b_is_zero, a_is_inf, b_is_inf, a_is_nan, b_is_nan;
    assign a_is_zero = (a_exp == 11'h000) && (a[51:0] == 52'h0);
    assign b_is_zero = (b_exp == 11'h000) && (b[51:0] == 52'h0);
    assign a_is_inf  = (a_exp == 11'h7FF) && (a[51:0] == 52'h0);
    assign b_is_inf  = (b_exp == 11'h7FF) && (b[51:0] == 52'h0);
    assign a_is_nan  = (a_exp == 11'h7FF) && (a[51:0] != 52'h0);
    assign b_is_nan  = (b_exp == 11'h7FF) && (b[51:0] != 52'h0);
    
    // Multiply mantissas (53 * 53 = 106 bits)
    logic [105:0] mant_product;
    assign mant_product = a_mant * b_mant;
    
    // Calculate exponent
    logic [12:0] exp_sum;
    assign exp_sum = {2'b0, a_exp} + {2'b0, b_exp} - 13'd1023;  // Remove one bias
    
    // Normalize and pack result
    logic [10:0] result_exp;
    logic [51:0] result_mant;
    
    always_comb begin
        result_exp  = '0;
        result_mant = '0;
        if (a_is_nan || b_is_nan) begin
            result = 64'h7FF8000000000000;  // Quiet NaN
        end else if ((a_is_inf && b_is_zero) || (b_is_inf && a_is_zero)) begin
            result = 64'h7FF8000000000000;  // inf * 0 = NaN
        end else if (a_is_inf || b_is_inf) begin
            result = {result_sign, 11'h7FF, 52'h0};  // Infinity
        end else if (a_is_zero || b_is_zero) begin
            result = {result_sign, 63'h0};  // Zero
        end else if (mant_product[105]) begin
            // Product >= 2.0, shift right
            result_exp  = exp_sum[10:0] + 11'd1;
            result_mant = mant_product[104:53];
            if (exp_sum >= 13'd2047) begin
                result = {result_sign, 11'h7FF, 52'h0};  // Overflow to inf
            end else begin
                result = {result_sign, result_exp, result_mant};
            end
        end else begin
            // Product < 2.0
            result_exp  = exp_sum[10:0];
            result_mant = mant_product[103:52];
            if (exp_sum[12] || exp_sum == 0) begin
                result = {result_sign, 63'h0};  // Underflow to zero
            end else begin
                result = {result_sign, result_exp, result_mant};
            end
        end
    end

endmodule


//=============================================================================
// FP Divider - Double Precision (IEEE 754)
//=============================================================================

module fp_div_dp (
    input  logic [63:0] a,
    input  logic [63:0] b,
    output logic [63:0] result
);

    // Unpack inputs
    logic        a_sign, b_sign, result_sign;
    logic [10:0] a_exp, b_exp;
    logic [52:0] a_mant, b_mant;  // Include implicit 1
    
    assign a_sign = a[63];
    assign b_sign = b[63];
    assign a_exp  = a[62:52];
    assign b_exp  = b[62:52];
    // Mantissa with implicit 1 (or 0 for denormals)
    assign a_mant = (a_exp == 11'h000) ? {1'b0, a[51:0]} : {1'b1, a[51:0]};
    assign b_mant = (b_exp == 11'h000) ? {1'b0, b[51:0]} : {1'b1, b[51:0]};
    
    assign result_sign = a_sign ^ b_sign;
    
    // Special cases
    logic a_is_zero, b_is_zero, a_is_inf, b_is_inf, a_is_nan, b_is_nan;
    assign a_is_zero = (a_exp == 11'h000) && (a[51:0] == 52'h0);
    assign b_is_zero = (b_exp == 11'h000) && (b[51:0] == 52'h0);
    assign a_is_inf  = (a_exp == 11'h7FF) && (a[51:0] == 52'h0);
    assign b_is_inf  = (b_exp == 11'h7FF) && (b[51:0] == 52'h0);
    assign a_is_nan  = (a_exp == 11'h7FF) && (a[51:0] != 52'h0);
    assign b_is_nan  = (b_exp == 11'h7FF) && (b[51:0] != 52'h0);
    
    // Divide mantissas with proper scaling
    // We need quotient in format 1.xxx... or 0.1xxx...
    // Shift dividend left by 53 bits for precision
    logic [106:0] dividend;
    logic [106:0] quotient_raw;
    assign dividend     = {1'b0, a_mant, 53'h0};  // 107 bits total
    assign quotient_raw = dividend / {54'h0, b_mant};
    
    // Calculate exponent (with bias adjustment)
    logic signed [12:0] exp_diff;
    assign exp_diff = $signed({2'b0, a_exp}) - $signed({2'b0, b_exp}) + 13'sd1023;
    
    // Normalize and pack result
    logic [10:0] result_exp;
    logic [51:0] result_mant;
    logic signed [12:0] final_exp;
    logic [52:0] final_mant;
    logic [6:0] lz_count;
    
    always_comb begin
        result_exp  = '0;
        result_mant = '0;
        final_exp   = '0;
        final_mant  = '0;
        lz_count    = '0;
        if (a_is_nan || b_is_nan) begin
            result = 64'h7FF8000000000000;  // Quiet NaN
        end else if (a_is_inf && b_is_inf) begin
            result = 64'h7FF8000000000000;  // inf / inf = NaN
        end else if (a_is_zero && b_is_zero) begin
            result = 64'h7FF8000000000000;  // 0 / 0 = NaN
        end else if (a_is_inf || b_is_zero) begin
            result = {result_sign, 11'h7FF, 52'h0};  // Infinity
        end else if (a_is_zero || b_is_inf) begin
            result = {result_sign, 63'h0};  // Zero
        end else begin
            // Normal division case
            // quotient_raw has the quotient of (a_mant << 53) / b_mant
            // If a_mant >= b_mant, quotient_raw[53] = 1 (result >= 1.0)
            // If a_mant <  b_mant, quotient_raw[53] = 0 (result < 1.0, need to normalize)
            
            if (quotient_raw[53]) begin
                // Quotient >= 1.0, format is 1.xxx...
                final_exp  = exp_diff;
                final_mant = quotient_raw[53:1];  // Take bits [53:1], [52:0] is fractional
            end else begin
                // Quotient < 1.0, need to shift left and adjust exponent
                // Find leading 1
                lz_count = 0;
                for (int i = 52; i >= 0; i--) begin
                    if (!quotient_raw[i]) begin
                        lz_count = lz_count + 1;
                    end else begin
                        break;
                    end
                end
                // Shift is number of zeros after bit 53 until first 1
                final_exp  = exp_diff - $signed({6'b0, lz_count}) - 13'sd1;
                final_mant = quotient_raw[52:0] << lz_count;
            end
            
            // Check for overflow/underflow
            if (final_exp >= 13'sd2047) begin
                result = {result_sign, 11'h7FF, 52'h0};  // Overflow to infinity
            end else if (final_exp <= 13'sd0) begin
                result = {result_sign, 63'h0};  // Underflow to zero
            end else begin
                result_exp  = final_exp[10:0];
                result_mant = final_mant[51:0];  // Remove implicit 1
                result      = {result_sign, result_exp, result_mant};
            end
        end
    end

endmodule


//=============================================================================
// FP Fused Multiply-Add - Double Precision (IEEE 754)
// Computes: result = a * b + c with only ONE rounding at the end
//=============================================================================

module fp_fma_dp (
    input  logic [63:0] a,
    input  logic [63:0] b,
    input  logic [63:0] c,
    output logic [63:0] result
);

    //=========================================================================
    // Unpack Inputs
    //=========================================================================
    
    logic        a_sign, b_sign, c_sign;
    logic [10:0] a_exp,  b_exp,  c_exp;
    logic [52:0] a_mant, b_mant, c_mant;  // Include implicit 1
    
    assign a_sign = a[63];
    assign b_sign = b[63];
    assign c_sign = c[63];
    
    assign a_exp  = a[62:52];
    assign b_exp  = b[62:52];
    assign c_exp  = c[62:52];
    
    assign a_mant = (a_exp == 11'h000) ? {1'b0, a[51:0]} : {1'b1, a[51:0]};
    assign b_mant = (b_exp == 11'h000) ? {1'b0, b[51:0]} : {1'b1, b[51:0]};
    assign c_mant = (c_exp == 11'h000) ? {1'b0, c[51:0]} : {1'b1, c[51:0]};
    
    //=========================================================================
    // Special Value Detection
    //=========================================================================
    
    logic a_is_zero, b_is_zero, c_is_zero;
    logic a_is_inf,  b_is_inf,  c_is_inf;
    logic a_is_nan,  b_is_nan,  c_is_nan;
    
    assign a_is_zero = (a_exp == 11'h000) && (a[51:0] == 52'h0);
    assign b_is_zero = (b_exp == 11'h000) && (b[51:0] == 52'h0);
    assign c_is_zero = (c_exp == 11'h000) && (c[51:0] == 52'h0);
    
    assign a_is_inf  = (a_exp == 11'h7FF) && (a[51:0] == 52'h0);
    assign b_is_inf  = (b_exp == 11'h7FF) && (b[51:0] == 52'h0);
    assign c_is_inf  = (c_exp == 11'h7FF) && (c[51:0] == 52'h0);
    
    assign a_is_nan  = (a_exp == 11'h7FF) && (a[51:0] != 52'h0);
    assign b_is_nan  = (b_exp == 11'h7FF) && (b[51:0] != 52'h0);
    assign c_is_nan  = (c_exp == 11'h7FF) && (c[51:0] != 52'h0);
    
    //=========================================================================
    // Step 1: Multiply a * b (keep full precision - 106 bits)
    //=========================================================================
    
    logic         prod_sign;
    logic [105:0] prod_mant;  // 53 * 53 = 106 bits
    logic [12:0]  prod_exp;   // Extended to handle overflow
    
    assign prod_sign = a_sign ^ b_sign;
    assign prod_mant = a_mant * b_mant;
    
    // Product exponent: (a_exp - 1023) + (b_exp - 1023) + 1023 = a_exp + b_exp - 1023
    assign prod_exp = (a_is_zero || b_is_zero) ? 13'd0 : 
                      {2'b0, a_exp} + {2'b0, b_exp} - 13'd1023;
    
    //=========================================================================
    // Step 2: Align product and addend for addition
    //=========================================================================
    
    logic [12:0]  c_exp_eff;
    logic [159:0] prod_aligned;  // Extended precision
    logic [159:0] c_aligned;
    logic [12:0]  result_exp_pre;
    logic         effective_sub;
    
    assign c_exp_eff = (c_is_zero) ? 13'd0 : {2'b0, c_exp};
    assign effective_sub = prod_sign ^ c_sign;
    
    // Determine alignment shift
    logic signed [13:0] exp_diff;
    logic [7:0] shift_amount;
    logic prod_larger;
    
    always_comb begin
        // Normalize product mantissa position
        if (prod_mant[105]) begin
            exp_diff = $signed({1'b0, prod_exp + 13'd1}) - $signed({1'b0, c_exp_eff});
            result_exp_pre = prod_exp + 13'd1;
        end else begin
            exp_diff = $signed({1'b0, prod_exp}) - $signed({1'b0, c_exp_eff});
            result_exp_pre = prod_exp;
        end
        
        prod_larger = (exp_diff >= 0);
        
        // Calculate shift amount (capped)
        if (exp_diff >= 0) begin
            shift_amount = (exp_diff > 14'sd160) ? 8'd160 : exp_diff[7:0];
        end else begin
            shift_amount = (-exp_diff > 14'sd160) ? 8'd160 : (-exp_diff[7:0]);
        end
        
        // Align operands
        if (prod_mant[105]) begin
            prod_aligned = {prod_mant, 54'h0};
        end else begin
            prod_aligned = {prod_mant[104:0], 55'h0};
        end
        
        // Align C to match product
        if (prod_larger) begin
            c_aligned = {c_mant, 107'h0} >> shift_amount;
        end else begin
            c_aligned = {c_mant, 107'h0};
            prod_aligned = prod_aligned >> shift_amount;
            result_exp_pre = c_exp_eff;
        end
    end
    
    //=========================================================================
    // Step 3: Add/Subtract with full precision
    //=========================================================================
    
    logic [160:0] sum_mant;  // Extra bit for carry
    logic         sum_sign;
    
    always_comb begin
        if (a_is_zero || b_is_zero) begin
            sum_mant = {1'b0, c_aligned};
            sum_sign = c_sign;
        end else if (c_is_zero) begin
            sum_mant = {1'b0, prod_aligned};
            sum_sign = prod_sign;
        end else if (effective_sub) begin
            if (prod_aligned >= c_aligned) begin
                sum_mant = {1'b0, prod_aligned} - {1'b0, c_aligned};
                sum_sign = prod_sign;
            end else begin
                sum_mant = {1'b0, c_aligned} - {1'b0, prod_aligned};
                sum_sign = c_sign;
            end
        end else begin
            sum_mant = {1'b0, prod_aligned} + {1'b0, c_aligned};
            sum_sign = prod_sign;
        end
    end
    
    //=========================================================================
    // Step 4: Normalize and Round
    //=========================================================================
    
    logic [10:0] result_exp;
    logic [51:0] result_mant;
    logic        result_sign;
    logic [7:0] leading_zeros_count;
    logic [160:0] normalized_mant_fma;
    logic signed [13:0] final_exp;
    
    always_comb begin
        result = 64'h0;
        result_sign = sum_sign;
        result_exp = 11'h0;
        result_mant = 52'h0;
        leading_zeros_count = '0;
        normalized_mant_fma = '0;
        final_exp = '0;
        
        if (a_is_nan || b_is_nan || c_is_nan) begin
            result = 64'h7FF8000000000000;  // Quiet NaN
        end else if ((a_is_inf && b_is_zero) || (b_is_inf && a_is_zero)) begin
            result = 64'h7FF8000000000000;  // inf * 0 = NaN
        end else if (a_is_inf || b_is_inf) begin
            if (c_is_inf && effective_sub) begin
                result = 64'h7FF8000000000000;  // inf - inf = NaN
            end else begin
                result = {prod_sign, 11'h7FF, 52'h0};
            end
        end else if (c_is_inf) begin
            result = {c_sign, 11'h7FF, 52'h0};
        end else if (sum_mant == 0) begin
            result = 64'h0000000000000000;
        end else begin
            // Normalize the result
            
            // Find leading one position
            leading_zeros_count = 0;
            for (int i = 160; i >= 0; i--) begin
                if (sum_mant[i]) begin
                    leading_zeros_count = 160 - i[7:0];
                    break;
                end
            end
            
            // Handle carry overflow
            if (sum_mant[160]) begin
                final_exp = result_exp_pre + 14'sd1;
                normalized_mant_fma = sum_mant;
            end else begin
                final_exp = $signed({1'b0, result_exp_pre}) - $signed({6'b0, leading_zeros_count}) + 14'sd1;
                normalized_mant_fma = sum_mant << leading_zeros_count;
            end
            
            // Extract mantissa
            if (final_exp >= 14'sd2047) begin
                result = {result_sign, 11'h7FF, 52'h0};  // Overflow
            end else if (final_exp <= 14'sd0) begin
                result = {result_sign, 63'h0};  // Underflow
            end else begin
                result_exp = final_exp[10:0];
                result_mant = normalized_mant_fma[159:108];
                result = {result_sign, result_exp, result_mant};
            end
        end
    end

endmodule


//=============================================================================
// FP Square Root - Double Precision (Approximation)
//=============================================================================

module fp_sqrt_dp (
    input  logic [63:0] a,
    output logic [63:0] result
);

    logic        a_sign;
    logic [10:0] a_exp;
    logic [51:0] a_mant;
    
    assign a_sign = a[63];
    assign a_exp  = a[62:52];
    assign a_mant = a[51:0];
    
    logic a_is_zero, a_is_inf, a_is_nan;
    assign a_is_zero = (a_exp == 11'h000) && (a_mant == 52'h0);
    assign a_is_inf  = (a_exp == 11'h7FF) && (a_mant == 52'h0);
    assign a_is_nan  = (a_exp == 11'h7FF) && (a_mant != 52'h0);
    
    logic [10:0] result_exp;
    logic [51:0] result_mant;
    logic [11:0] exp_minus_bias;
    
    always_comb begin
        result_exp = '0;
        result_mant = '0;
        exp_minus_bias = '0;
        if (a_is_nan || a_sign) begin
            result = 64'h7FF8000000000000;  // NaN for negative or NaN input
        end else if (a_is_zero) begin
            result = 64'h0000000000000000;  // sqrt(0) = 0
        end else if (a_is_inf) begin
            result = 64'h7FF0000000000000;  // sqrt(inf) = inf
        end else begin
            // Approximation: sqrt(a) ≈ a^0.5
            // result_exp ≈ (a_exp - 1023) / 2 + 1023
            exp_minus_bias = {1'b0, a_exp} - 12'd1023;
            
            if (exp_minus_bias[0]) begin
                // Odd exponent
                result_exp  = (exp_minus_bias[11:1]) + 11'd1023;
                result_mant = {1'b1, a_mant[51:1]};
            end else begin
                result_exp  = (exp_minus_bias[11:1]) + 11'd1023;
                result_mant = a_mant;
            end
            
            result = {1'b0, result_exp, result_mant};
        end
    end

endmodule


//=============================================================================
// FP Reciprocal - Double Precision (Approximation)
//=============================================================================

module fp_rcp_dp (
    input  logic [63:0] a,
    output logic [63:0] result
);

    logic        a_sign;
    logic [10:0] a_exp;
    logic [51:0] a_mant;
    
    assign a_sign = a[63];
    assign a_exp  = a[62:52];
    assign a_mant = a[51:0];
    
    logic a_is_zero, a_is_inf, a_is_nan;
    assign a_is_zero = (a_exp == 11'h000) && (a_mant == 52'h0);
    assign a_is_inf  = (a_exp == 11'h7FF) && (a_mant == 52'h0);
    assign a_is_nan  = (a_exp == 11'h7FF) && (a_mant != 52'h0);
    
    logic [10:0] result_exp;
    logic [51:0] result_mant;
    
    always_comb begin
        result_exp = '0;
        result_mant = '0;
        if (a_is_nan) begin
            result = 64'h7FF8000000000000;  // NaN
        end else if (a_is_zero) begin
            result = {a_sign, 11'h7FF, 52'h0};  // 1/0 = inf
        end else if (a_is_inf) begin
            result = {a_sign, 63'h0};  // 1/inf = 0
        end else begin
            // Approximation: 1/a
            result_exp  = 11'd2045 - a_exp;
            result_mant = ~a_mant;
            result      = {a_sign, result_exp, result_mant};
        end
    end

endmodule


//=============================================================================
// FP Reciprocal Square Root - Double Precision (Approximation)
//=============================================================================

module fp_rsqrt_dp (
    input  logic [63:0] a,
    output logic [63:0] result
);

    logic        a_sign;
    logic [10:0] a_exp;
    logic [51:0] a_mant;
    
    assign a_sign = a[63];
    assign a_exp  = a[62:52];
    assign a_mant = a[51:0];
    
    logic a_is_zero, a_is_inf, a_is_nan;
    assign a_is_zero = (a_exp == 11'h000) && (a_mant == 52'h0);
    assign a_is_inf  = (a_exp == 11'h7FF) && (a_mant == 52'h0);
    assign a_is_nan  = (a_exp == 11'h7FF) && (a_mant != 52'h0);
    
    // Magic number for double precision fast inverse sqrt
    logic [63:0] magic_result;
    
    always_comb begin
        magic_result = '0;
        if (a_is_nan || a_sign) begin
            result = 64'h7FF8000000000000;  // NaN
        end else if (a_is_zero) begin
            result = 64'h7FF0000000000000;  // 1/sqrt(0) = inf
        end else if (a_is_inf) begin
            result = 64'h0000000000000000;  // 1/sqrt(inf) = 0
        end else begin
            // Magic number approximation for DP: 0x5FE6EB50C7B537A9 - (a >> 1)
            magic_result = 64'h5FE6EB50C7B537A9 - (a >> 1);
            result = magic_result;
        end
    end

endmodule


//=============================================================================
// FP Min - Double Precision
//=============================================================================

module fp_min_dp (
    input  logic [63:0] a,
    input  logic [63:0] b,
    output logic [63:0] result
);

    logic a_sign, b_sign;
    logic [10:0] a_exp, b_exp;
    logic [51:0] a_mant, b_mant;
    
    assign a_sign = a[63];
    assign b_sign = b[63];
    assign a_exp  = a[62:52];
    assign b_exp  = b[62:52];
    assign a_mant = a[51:0];
    assign b_mant = b[51:0];
    
    logic a_is_nan, b_is_nan;
    logic a_is_zero, b_is_zero;
    logic a_lt_b;
    
    assign a_is_nan  = (a_exp == 11'h7FF) && (a_mant != 52'h0);
    assign b_is_nan  = (b_exp == 11'h7FF) && (b_mant != 52'h0);
    assign a_is_zero = (a_exp == 11'h000) && (a_mant == 52'h0);
    assign b_is_zero = (b_exp == 11'h000) && (b[51:0] == 52'h0);
    
    always_comb begin
        if (a_sign != b_sign) begin
            a_lt_b = a_sign && !(a_is_zero && b_is_zero);
        end else if (a_sign) begin
            a_lt_b = (a[62:0] > b[62:0]);
        end else begin
            a_lt_b = (a[62:0] < b[62:0]);
        end
    end
    
    assign result = a_is_nan ? b :
                    b_is_nan ? a :
                    a_lt_b   ? a : b;

endmodule


//=============================================================================
// FP Max - Double Precision
//=============================================================================

module fp_max_dp (
    input  logic [63:0] a,
    input  logic [63:0] b,
    output logic [63:0] result
);

    logic a_sign, b_sign;
    logic [10:0] a_exp, b_exp;
    logic [51:0] a_mant, b_mant;
    
    assign a_sign = a[63];
    assign b_sign = b[63];
    assign a_exp  = a[62:52];
    assign b_exp  = b[62:52];
    assign a_mant = a[51:0];
    assign b_mant = b[51:0];
    
    logic a_is_nan, b_is_nan;
    logic a_is_zero, b_is_zero;
    logic a_lt_b;
    
    assign a_is_nan  = (a_exp == 11'h7FF) && (a_mant != 52'h0);
    assign b_is_nan  = (b_exp == 11'h7FF) && (b_mant != 52'h0);
    assign a_is_zero = (a_exp == 11'h000) && (a_mant == 52'h0);
    assign b_is_zero = (b_exp == 11'h000) && (b[51:0] == 52'h0);
    
    always_comb begin
        if (a_sign != b_sign) begin
            a_lt_b = a_sign && !(a_is_zero && b_is_zero);
        end else if (a_sign) begin
            a_lt_b = (a[62:0] > b[62:0]);
        end else begin
            a_lt_b = (a[62:0] < b[62:0]);
        end
    end
    
    assign result = a_is_nan ? b :
                    b_is_nan ? a :
                    a_lt_b   ? b : a;

endmodule


//=============================================================================
// FP Compare - Double Precision
//=============================================================================

module fp_cmp_dp
    import gpgpu_pkg::*;
(
    input  logic [63:0] a,
    input  logic [63:0] b,
    input  logic [3:0]  func,
    output logic        result
);

    logic a_sign, b_sign;
    logic [10:0] a_exp, b_exp;
    logic [51:0] a_mant, b_mant;
    
    assign a_sign = a[63];
    assign b_sign = b[63];
    assign a_exp  = a[62:52];
    assign b_exp  = b[62:52];
    assign a_mant = a[51:0];
    assign b_mant = b[51:0];
    
    logic a_is_nan, b_is_nan;
    logic a_is_zero, b_is_zero;
    logic a_lt_b;
    
    assign a_is_nan  = (a_exp == 11'h7FF) && (a_mant != 52'h0);
    assign b_is_nan  = (b_exp == 11'h7FF) && (b_mant != 52'h0);
    assign a_is_zero = (a_exp == 11'h000) && (a_mant == 52'h0);
    assign b_is_zero = (b_exp == 11'h000) && (b[51:0] == 52'h0);
    
    always_comb begin
        if (a_sign != b_sign) begin
            a_lt_b = a_sign && !(a_is_zero && b_is_zero);
        end else if (a_sign) begin
            a_lt_b = (a[62:0] > b[62:0]);
        end else begin
            a_lt_b = (a[62:0] < b[62:0]);
        end
    end
    
    always_comb begin
        if (a_is_nan || b_is_nan) begin
            case (func)
                FCMP_UNO: result = 1'b1;
                FCMP_ORD: result = 1'b0;
                default:  result = 1'b0;
            endcase
        end else begin
            case (func)
                FCMP_EQ:  result = (a == b) || (a_is_zero && b_is_zero);
                FCMP_NE:  result = !((a == b) || (a_is_zero && b_is_zero));
                FCMP_LT:  result = a_lt_b && !(a_is_zero && b_is_zero);
                FCMP_LE:  result = a_lt_b || (a == b) || (a_is_zero && b_is_zero);
                FCMP_GT:  result = !a_lt_b && (a != b) && !(a_is_zero && b_is_zero);
                FCMP_GE:  result = !a_lt_b || (a_is_zero && b_is_zero);
                FCMP_ORD: result = 1'b1;
                FCMP_UNO: result = 1'b0;
                default:  result = 1'b0;
            endcase
        end
    end

endmodule
