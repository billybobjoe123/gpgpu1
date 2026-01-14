//=============================================================================
// GPGPU-1 Floating-Point Unit (FPU)
//=============================================================================
// File:        fpu.sv
// Description: 8-wide SIMD FPU supporting IEEE 754 single and double precision
//              floating-point operations with realistic pipeline latencies.
// Version:     3.0
//=============================================================================

`default_nettype none

/* verilator lint_off DECLFILENAME */

`include "gpgpu_defines.svh"

module fpu
    import gpgpu_pkg::*;
#(
    parameter int LATENCY_SIMPLE = 1,
    parameter int LATENCY_ADD    = 3,
    parameter int LATENCY_MUL    = 4,
    parameter int LATENCY_FMA    = 5,
    parameter int LATENCY_DIV    = 12,
    parameter int LATENCY_SQRT   = 12,
    parameter int LATENCY_CVT    = 2,
    parameter int MAX_LATENCY    = 12
)(
    input  logic                                    clk,
    input  logic                                    rst_n,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]    operand_a,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]    operand_b,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]    operand_c,
    input  opcode_t                                 opcode,
    input  logic [FUNC_WIDTH-1:0]                   func,
    input  logic [WARP_SIZE-1:0]                    active_mask,
    input  logic                                    valid_in,
    output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0]    result,
    output logic [WARP_SIZE-1:0]                    pred_result,
    output logic                                    valid_out,
    output logic                                    ready
);

    logic [3:0] op_latency;
    always_comb begin
        case (opcode)
            OP_FMIN, OP_FMAX, OP_FABS, OP_FNEG, OP_FCMP: op_latency = LATENCY_SIMPLE[3:0];
            OP_FADD, OP_FSUB: op_latency = LATENCY_ADD[3:0];
            OP_FMUL: op_latency = LATENCY_MUL[3:0];
            OP_FMADD: op_latency = LATENCY_FMA[3:0];
            OP_FDIV, OP_FRCP: op_latency = LATENCY_DIV[3:0];
            OP_FSQRT, OP_FRSQRT: op_latency = LATENCY_SQRT[3:0];
            OP_FCVT: op_latency = LATENCY_CVT[3:0];
            default: op_latency = LATENCY_SIMPLE[3:0];
        endcase
    end

    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] result_comb;
    logic [WARP_SIZE-1:0]                 pred_comb;

    genvar t;
    generate
        for (t = 0; t < WARP_SIZE; t++) begin : gen_fpu_lanes
            fpu_lane u_fpu_lane (
                .clk(clk), .rst_n(rst_n),
                .a(operand_a[t]), .b(operand_b[t]), .c(operand_c[t]),
                .opcode(opcode), .func(func), .active(active_mask[t]),
                .result(result_comb[t]), .pred_out(pred_comb[t])
            );
        end
    endgenerate

    logic [MAX_LATENCY-1:0][WARP_SIZE-1:0][DATA_WIDTH-1:0] result_pipe;
    logic [MAX_LATENCY-1:0][WARP_SIZE-1:0]                 pred_pipe;
    logic [MAX_LATENCY-1:0]                                valid_pipe;
    logic [MAX_LATENCY-1:0][3:0]                           cycles_remaining;
    logic [MAX_LATENCY-1:0]                                output_consumed;
    logic [MAX_LATENCY-1:0]                                stage_output_ready;

    always_comb begin
        for (int i = 0; i < MAX_LATENCY; i++) begin
            stage_output_ready[i] = valid_pipe[i] && (cycles_remaining[i] == 0) && !output_consumed[i];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < MAX_LATENCY; i++) begin
                result_pipe[i] <= '0; pred_pipe[i] <= '0; valid_pipe[i] <= 1'b0;
                cycles_remaining[i] <= '0; output_consumed[i] <= 1'b0;
            end
        end else begin
            result_pipe[0] <= result_comb;
            pred_pipe[0] <= pred_comb;
            valid_pipe[0] <= valid_in;
            cycles_remaining[0] <= (op_latency > 0) ? (op_latency - 4'd1) : 4'd0;
            output_consumed[0] <= 1'b0;
            for (int i = 1; i < MAX_LATENCY; i++) begin
                result_pipe[i] <= result_pipe[i-1];
                pred_pipe[i] <= pred_pipe[i-1];
                valid_pipe[i] <= valid_pipe[i-1];
                cycles_remaining[i] <= (cycles_remaining[i-1] > 0) ? (cycles_remaining[i-1] - 4'd1) : 4'd0;
                output_consumed[i] <= output_consumed[i-1] || stage_output_ready[i-1];
            end
        end
    end

    always_comb begin
        result = '0; pred_result = '0; valid_out = 1'b0;
        for (int i = 0; i < MAX_LATENCY; i++) begin
            if (stage_output_ready[i]) begin
                result = result_pipe[i]; pred_result = pred_pipe[i]; valid_out = 1'b1;
                break;
            end
        end
    end
    assign ready = 1'b1;
endmodule

module fpu_lane import gpgpu_pkg::*; (
    input  logic clk, rst_n,
    input  logic [DATA_WIDTH-1:0] a, b, c,
    input  opcode_t opcode,
    input  logic [FUNC_WIDTH-1:0] func,
    input  logic active,
    output logic [DATA_WIDTH-1:0] result,
    output logic pred_out
);
    logic is_double; assign is_double = func[7];

    // Helper logic for SP->DP conversion
    logic [63:0] a_sp2dp, b_sp2dp, c_sp2dp;
    assign a_sp2dp = (a[30:23] == 8'hFF) ? {a[31], 11'h7FF, a[22:0], 29'h0} :
                     (a[30:23] == 8'h00) ? {a[31], 11'h000, 52'h0} :
                     {a[31], ({3'b0, a[30:23]} + 11'd896), a[22:0], 29'h0};
    assign b_sp2dp = (b[30:23] == 8'hFF) ? {b[31], 11'h7FF, b[22:0], 29'h0} :
                     (b[30:23] == 8'h00) ? {b[31], 11'h000, 52'h0} :
                     {b[31], ({3'b0, b[30:23]} + 11'd896), b[22:0], 29'h0};
    assign c_sp2dp = (c[30:23] == 8'hFF) ? {c[31], 11'h7FF, c[22:0], 29'h0} :
                     (c[30:23] == 8'h00) ? {c[31], 11'h000, 52'h0} :
                     {c[31], ({3'b0, c[30:23]} + 11'd896), c[22:0], 29'h0};

    real ra, rb, rc, rr;
    logic [63:0] res_d;

    always_comb begin
        result = '0; pred_out = 1'b0;
        ra = 0.0; rb = 0.0; rc = 0.0; rr = 0.0; res_d = '0;

        if (active) begin
            if (is_double) begin
                ra = $bitstoreal(a);
                rb = $bitstoreal(b);
                rc = $bitstoreal(c);
            end else begin
                ra = $bitstoreal(a_sp2dp);
                rb = $bitstoreal(b_sp2dp);
                rc = $bitstoreal(c_sp2dp);
            end

            case (opcode)
                OP_FADD:  rr = ra + rb;
                OP_FSUB:  rr = ra - rb;
                OP_FMUL:  rr = ra * rb;
                OP_FMADD: rr = (ra * rb) + rc;
                OP_FDIV:  rr = ra / rb;
                OP_FMIN:  rr = (ra < rb) ? ra : rb;
                OP_FMAX:  rr = (ra > rb) ? ra : rb;
                OP_FABS:  rr = (ra < 0) ? -ra : ra;
                OP_FNEG:  rr = -ra;
                OP_FCMP: begin
                    pred_out = (ra == rb);
                    rr = pred_out ? 1.0 : 0.0;
                end
                default: rr = 0.0;
            endcase

            res_d = $realtobits(rr);

            if (is_double) begin
                if (opcode == OP_FCMP) result = {63'h0, pred_out};
                else result = res_d;
            end else begin
                // DP to SP conversion logic
                if (opcode == OP_FCMP) result = {63'h0, pred_out};
                else begin
                    result[31:0] = (res_d[62:52] == 11'h7FF) ? {res_d[63], 8'hFF, res_d[51:29]} :
                                   (res_d[62:52] == 11'h000) ? {res_d[63], 8'h00, 23'h0} :
                                   (res_d[62:52] < 11'd897)  ? {res_d[63], 8'h00, 23'h0} :
                                   (res_d[62:52] > 11'd1150) ? {res_d[63], 8'hFF, 23'h0} :
                                   {res_d[63], (res_d[59:52] - 8'd128), res_d[51:29]};
                    result[63:32] = 32'h0;
                end
            end
        end
    end
endmodule

module fp_convert import gpgpu_pkg::*; (input logic [63:0] a, input logic [4:0] func, output logic [31:0] sp_result, output logic [63:0] dp_result);
    assign sp_result = '0; assign dp_result = '0;
endmodule
