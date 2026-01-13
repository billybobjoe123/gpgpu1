//=============================================================================
// GPGPU-1 Register File
//=============================================================================
// File:        register_file.sv
// Description: SIMT register file supporting 8 threads per warp.
//              Each thread has 32 general-purpose 64-bit registers.
//              R0 is hardwired to zero for all threads.
//              Supports 2 read ports and 1 write port per cycle.
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`default_nettype none

/* verilator lint_off DECLFILENAME */

`include "gpgpu_defines.svh"

module register_file
    import gpgpu_pkg::*;
#(
    parameter int NUM_WARPS = WARPS_PER_CORE  // Number of warps this RF serves
)(
    input  logic                            clk,
    input  logic                            rst_n,
    
    // Warp selection
    input  logic [WARP_ID_WIDTH-1:0]        warp_id,
    
    // Read port 1
    input  logic [REG_ADDR_WIDTH-1:0]       rs1_addr,
    output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rs1_data,
    
    // Read port 2
    input  logic [REG_ADDR_WIDTH-1:0]       rs2_addr,
    output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rs2_data,
    
    // Write port
    input  logic                            wr_en,
    input  logic [WARP_SIZE-1:0]            wr_mask,     // Per-thread write enable
    input  logic [REG_ADDR_WIDTH-1:0]       wr_addr,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] wr_data,
    
    // Optional: Write port warp ID (for out-of-order writeback)
    input  logic [WARP_ID_WIDTH-1:0]        wr_warp_id
);

    //=========================================================================
    // Register File Storage
    //=========================================================================
    // Organization: [warp][thread][register] = data
    // Total size: NUM_WARPS * WARP_SIZE * NUM_REGS * DATA_WIDTH bits
    //           = 4 * 8 * 32 * 64 = 65,536 bits = 8KB per warp set
    
    // Using a 3D array for clarity
    // Synthesis tools will infer appropriate memory structure
    `RAM_BLOCK
    logic [DATA_WIDTH-1:0] registers [NUM_WARPS-1:0][WARP_SIZE-1:0][NUM_REGS-1:0];
    
    //=========================================================================
    // Read Logic
    //=========================================================================
    // Combinational read with R0 returning zero
    
    // Read port 1
    always_comb begin
        for (int t = 0; t < WARP_SIZE; t++) begin
            if (rs1_addr == `ZERO_REG) begin
                rs1_data[t] = '0;
            end else begin
                rs1_data[t] = registers[warp_id][t][rs1_addr];
            end
        end
    end
    
    // Read port 2
    always_comb begin
        for (int t = 0; t < WARP_SIZE; t++) begin
            if (rs2_addr == `ZERO_REG) begin
                rs2_data[t] = '0;
            end else begin
                rs2_data[t] = registers[warp_id][t][rs2_addr];
            end
        end
    end
    
    //=========================================================================
    // Write Logic
    //=========================================================================
    // Synchronous write with per-thread mask
    // Writes to R0 are ignored
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all registers to zero
            for (int w = 0; w < NUM_WARPS; w++) begin
                for (int t = 0; t < WARP_SIZE; t++) begin
                    for (int r = 0; r < NUM_REGS; r++) begin
                        registers[w][t][r] <= '0;
                    end
                end
            end
        end else begin
            // Write operation
            if (wr_en && (wr_addr != `ZERO_REG)) begin
                for (int t = 0; t < WARP_SIZE; t++) begin
                    if (wr_mask[t]) begin
                        registers[wr_warp_id][t][wr_addr] <= wr_data[t];
                    end
                end
            end
        end
    end

    //=========================================================================
    // Debug / Assertions
    //=========================================================================
    
    `ifdef ENABLE_ASSERTIONS
        // Check that R0 always reads as zero
        always_comb begin
            for (int t = 0; t < WARP_SIZE; t++) begin
                assert (rs1_addr != `ZERO_REG || rs1_data[t] == '0)
                    else $error("R0 should always read as zero on port 1");
                assert (rs2_addr != `ZERO_REG || rs2_data[t] == '0)
                    else $error("R0 should always read as zero on port 2");
            end
        end
    `endif
    
    `ifdef SIMULATION
        // Debug: Monitor writes
        always_ff @(posedge clk) begin
            if (wr_en && (wr_addr != `ZERO_REG)) begin
                for (int t = 0; t < WARP_SIZE; t++) begin
                    if (wr_mask[t]) begin
                        `DEBUG_PRINTF("RF Write: Warp[%0d] Thread[%0d] R%0d <= 0x%016h",
                                      wr_warp_id, t, wr_addr, wr_data[t]);
                    end
                end
            end
        end
    `endif

endmodule

//=============================================================================
// GPGPU-1 Predicate Register File
//=============================================================================
// File:        predicate_file.sv
// Description: Predicate register file for conditional execution.
//              Each thread has 8 predicate registers (1-bit each).
//              P0 is hardwired to true (1).
//=============================================================================

module predicate_file
    import gpgpu_pkg::*;
#(
    parameter int NUM_WARPS = WARPS_PER_CORE
)(
    input  logic                            clk,
    input  logic                            rst_n,
    
    // Warp selection
    input  logic [WARP_ID_WIDTH-1:0]        warp_id,
    
    // Read port (for predicate evaluation)
    input  logic [PRED_ADDR_WIDTH-1:0]      pred_addr,
    output logic [WARP_SIZE-1:0]            pred_data,   // One bit per thread
    
    // Additional read port for second predicate (e.g., PAND, POR)
    input  logic [PRED_ADDR_WIDTH-1:0]      pred2_addr,
    output logic [WARP_SIZE-1:0]            pred2_data,
    
    // Write port
    input  logic                            wr_en,
    input  logic [WARP_SIZE-1:0]            wr_mask,
    input  logic [PRED_ADDR_WIDTH-1:0]      wr_addr,
    input  logic [WARP_SIZE-1:0]            wr_data,     // One bit per thread
    
    // Write port warp ID
    input  logic [WARP_ID_WIDTH-1:0]        wr_warp_id
);

    //=========================================================================
    // Predicate Register Storage
    //=========================================================================
    // Organization: [warp][thread][predicate] = 1 bit
    // Much smaller than GPR file: NUM_WARPS * WARP_SIZE * NUM_PRED bits
    //                           = 4 * 8 * 8 = 256 bits = 32 bytes
    
    `RAM_DISTRIBUTED
    logic [NUM_PRED-1:0] predicates [NUM_WARPS-1:0][WARP_SIZE-1:0];
    
    //=========================================================================
    // Read Logic
    //=========================================================================
    // P0 is hardwired to 1 (true)
    
    // Read port 1
    always_comb begin
        for (int t = 0; t < WARP_SIZE; t++) begin
            if (pred_addr == `TRUE_PRED) begin
                pred_data[t] = 1'b1;
            end else begin
                pred_data[t] = predicates[warp_id][t][pred_addr];
            end
        end
    end
    
    // Read port 2
    always_comb begin
        for (int t = 0; t < WARP_SIZE; t++) begin
            if (pred2_addr == `TRUE_PRED) begin
                pred2_data[t] = 1'b1;
            end else begin
                pred2_data[t] = predicates[warp_id][t][pred2_addr];
            end
        end
    end
    
    //=========================================================================
    // Write Logic
    //=========================================================================
    // Writes to P0 are ignored
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all predicates to 0 (except P0 which is hardwired)
            for (int w = 0; w < NUM_WARPS; w++) begin
                for (int t = 0; t < WARP_SIZE; t++) begin
                    predicates[w][t] <= '0;
                end
            end
        end else begin
            if (wr_en && (wr_addr != `TRUE_PRED)) begin
                for (int t = 0; t < WARP_SIZE; t++) begin
                    if (wr_mask[t]) begin
                        predicates[wr_warp_id][t][wr_addr] <= wr_data[t];
                    end
                end
            end
        end
    end

    //=========================================================================
    // Debug
    //=========================================================================
    
    `ifdef SIMULATION
        always_ff @(posedge clk) begin
            if (wr_en && (wr_addr != `TRUE_PRED)) begin
                for (int t = 0; t < WARP_SIZE; t++) begin
                    if (wr_mask[t]) begin
                        `DEBUG_PRINTF("PRED Write: Warp[%0d] Thread[%0d] P%0d <= %b",
                                      wr_warp_id, t, wr_addr, wr_data[t]);
                    end
                end
            end
        end
    `endif

endmodule

//=============================================================================
// GPGPU-1 Special Register File
//=============================================================================
// Description: Read-only special registers providing thread/warp/block IDs
//              and other system information.
//=============================================================================

module special_register_file
    import gpgpu_pkg::*;
#(
    parameter int CORE_ID = 0
)(
    input  logic                            clk,
    input  logic                            rst_n,
    
    // Warp selection
    input  logic [WARP_ID_WIDTH-1:0]        warp_id,
    
    // Block configuration (set by dispatch unit)
    input  block_config_t                   block_config,
    
    // Read port
    input  logic [3:0]                      sr_addr,     // Special register address
    output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] sr_data, // Per-thread data
    
    // Clock counter (128-bit)
    input  logic [127:0]                    clock_counter
);

    //=========================================================================
    // Special Register Read Logic
    //=========================================================================
    
    always_comb begin
        for (int t = 0; t < WARP_SIZE; t++) begin
            case (sr_addr)
                SR_TID: begin
                    // Thread ID within warp (0 to WARP_SIZE-1)
                    // Each thread gets its own ID
                    sr_data[t] = DATA_WIDTH'(t);
                end
                
                SR_WID: begin
                    // Warp ID within core (same for all threads in warp)
                    sr_data[t] = DATA_WIDTH'(warp_id);
                end
                
                SR_CID: begin
                    // Core ID (same for all threads)
                    sr_data[t] = DATA_WIDTH'(CORE_ID);
                end
                
                SR_BID_X: begin
                    // Block ID, X dimension
                    sr_data[t] = block_config.block_id_x;
                end
                
                SR_BID_Y: begin
                    // Block ID, Y dimension
                    sr_data[t] = block_config.block_id_y;
                end
                
                SR_BID_Z: begin
                    // Block ID, Z dimension
                    sr_data[t] = block_config.block_id_z;
                end
                
                SR_NTID: begin
                    // Number of threads per block
                    sr_data[t] = block_config.num_threads;
                end
                
                SR_NCTAID_X: begin
                    // Number of blocks, X dimension
                    sr_data[t] = block_config.num_blocks_x;
                end
                
                SR_NCTAID_Y: begin
                    // Number of blocks, Y dimension
                    sr_data[t] = block_config.num_blocks_y;
                end
                
                SR_NCTAID_Z: begin
                    // Number of blocks, Z dimension
                    sr_data[t] = block_config.num_blocks_z;
                end
                
                SR_CLOCK: begin
                    // Clock cycle counter (lower 64 bits)
                    sr_data[t] = clock_counter[63:0];
                end
                
                SR_CLOCK_HI: begin
                    // Clock cycle counter (upper 64 bits)
                    sr_data[t] = clock_counter[127:64];
                end
                
                default: begin
                    sr_data[t] = '0;
                end
            endcase
        end
    end

endmodule

//=============================================================================
// GPGPU-1 Combined Register File Wrapper
//=============================================================================
// Description: Top-level wrapper combining GPR, predicate, and special
//              register files for a complete operand fetch unit.
//=============================================================================

module register_file_unit
    import gpgpu_pkg::*;
#(
    parameter int NUM_WARPS = WARPS_PER_CORE,
    parameter int CORE_ID   = 0
)(
    input  logic                            clk,
    input  logic                            rst_n,
    
    // Warp selection for reads
    input  logic [WARP_ID_WIDTH-1:0]        rd_warp_id,
    
    // GPR Read ports
    input  logic [REG_ADDR_WIDTH-1:0]       rs1_addr,
    input  logic [REG_ADDR_WIDTH-1:0]       rs2_addr,
    output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rs1_data,
    output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rs2_data,
    
    // GPR Write port
    input  logic                            gpr_wr_en,
    input  logic [WARP_ID_WIDTH-1:0]        gpr_wr_warp_id,
    input  logic [WARP_SIZE-1:0]            gpr_wr_mask,
    input  logic [REG_ADDR_WIDTH-1:0]       gpr_wr_addr,
    input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] gpr_wr_data,
    
    // Predicate Read port
    input  logic [PRED_ADDR_WIDTH-1:0]      pred_addr,
    input  logic [PRED_ADDR_WIDTH-1:0]      pred2_addr,
    output logic [WARP_SIZE-1:0]            pred_data,
    output logic [WARP_SIZE-1:0]            pred2_data,
    
    // Predicate Write port
    input  logic                            pred_wr_en,
    input  logic [WARP_ID_WIDTH-1:0]        pred_wr_warp_id,
    input  logic [WARP_SIZE-1:0]            pred_wr_mask,
    input  logic [PRED_ADDR_WIDTH-1:0]      pred_wr_addr,
    input  logic [WARP_SIZE-1:0]            pred_wr_data,
    
    // Special Register Read
    input  logic [3:0]                      sr_addr,
    output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] sr_data,
    
    // Block configuration
    input  block_config_t                   block_config
);

    //=========================================================================
    // Clock Counter
    //=========================================================================
    
    logic [127:0] clock_counter;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clock_counter <= '0;
        end else begin
            clock_counter <= clock_counter + 1'b1;
        end
    end
    
    //=========================================================================
    // GPR File Instance
    //=========================================================================
    
    register_file #(
        .NUM_WARPS(NUM_WARPS)
    ) u_gpr (
        .clk        (clk),
        .rst_n      (rst_n),
        .warp_id    (rd_warp_id),
        .rs1_addr   (rs1_addr),
        .rs1_data   (rs1_data),
        .rs2_addr   (rs2_addr),
        .rs2_data   (rs2_data),
        .wr_en      (gpr_wr_en),
        .wr_mask    (gpr_wr_mask),
        .wr_addr    (gpr_wr_addr),
        .wr_data    (gpr_wr_data),
        .wr_warp_id (gpr_wr_warp_id)
    );
    
    //=========================================================================
    // Predicate File Instance
    //=========================================================================
    
    predicate_file #(
        .NUM_WARPS(NUM_WARPS)
    ) u_pred (
        .clk        (clk),
        .rst_n      (rst_n),
        .warp_id    (rd_warp_id),
        .pred_addr  (pred_addr),
        .pred_data  (pred_data),
        .pred2_addr (pred2_addr),
        .pred2_data (pred2_data),
        .wr_en      (pred_wr_en),
        .wr_mask    (pred_wr_mask),
        .wr_addr    (pred_wr_addr),
        .wr_data    (pred_wr_data),
        .wr_warp_id (pred_wr_warp_id)
    );
    
    //=========================================================================
    // Special Register File Instance
    //=========================================================================
    
    special_register_file #(
        .CORE_ID(CORE_ID)
    ) u_sr (
        .clk           (clk),
        .rst_n         (rst_n),
        .warp_id       (rd_warp_id),
        .block_config  (block_config),
        .sr_addr       (sr_addr),
        .sr_data       (sr_data),
        .clock_counter (clock_counter)
    );

endmodule
