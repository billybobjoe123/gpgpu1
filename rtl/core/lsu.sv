//=============================================================================
// GPGPU-1 Load/Store Unit (LSU)
//=============================================================================
// File:        lsu.sv
// Description: Memory access unit supporting SIMT execution with 8-thread warps.
//              Handles global and shared memory operations with coalescing.
//              Supports 64-bit and 32-bit loads/stores with predication.
// Version:     1.0
// Date:        December 20, 2025
//=============================================================================

`include "gpgpu_defines.svh"

//=============================================================================
// Address Generation Unit
//=============================================================================
// Calculates effective addresses for all threads in a warp

module address_gen_unit
    import gpgpu_pkg::*;
#(
    parameter int NUM_THREADS = WARP_SIZE
)(
    // Base addresses from register file (per thread)
    input  logic [NUM_THREADS-1:0][ADDR_WIDTH-1:0]  base_addr,
    // Signed offset from instruction
    input  logic signed [12:0]                       offset,
    // Active thread mask
    input  logic [NUM_THREADS-1:0]                   active_mask,
    // Predicate mask
    input  logic [NUM_THREADS-1:0]                   pred_mask,
    
    // Effective addresses (per thread)
    output logic [NUM_THREADS-1:0][ADDR_WIDTH-1:0]  eff_addr,
    // Combined execution mask (active & predicate)
    output logic [NUM_THREADS-1:0]                   exec_mask
);

    // Sign-extend offset to 64 bits
    logic signed [ADDR_WIDTH-1:0] offset_ext;
    assign offset_ext = {{(ADDR_WIDTH-13){offset[12]}}, offset};
    
    // Calculate effective address for each thread
    always_comb begin
        exec_mask = active_mask & pred_mask;
        for (int t = 0; t < NUM_THREADS; t++) begin
            if (exec_mask[t]) begin
                eff_addr[t] = base_addr[t] + offset_ext;
            end else begin
                eff_addr[t] = '0;
            end
        end
    end

endmodule

//=============================================================================
// Atomic ALU
//=============================================================================
// Performs the read-modify-write compute operation for atomic instructions

module atomic_alu
    import gpgpu_pkg::*;
(
    input  logic [DATA_WIDTH-1:0]  mem_data,      // Original data from memory
    input  logic [DATA_WIDTH-1:0]  operand,       // Operand from register (RS2)
    input  logic [DATA_WIDTH-1:0]  compare_val,   // Compare value for CAS (from RD)
    input  atom_func_t             atom_func,     // Atomic function type
    input  logic                   is_64bit,      // 64-bit or 32-bit operation
    
    output logic [DATA_WIDTH-1:0]  result,        // New value to write to memory
    output logic [DATA_WIDTH-1:0]  return_val     // Old value to return to register
);

    // 32-bit operands (zero-extended from lower 32 bits)
    logic [31:0] mem_data_32, operand_32, compare_32;
    logic [31:0] result_32;
    
    assign mem_data_32 = mem_data[31:0];
    assign operand_32 = operand[31:0];
    assign compare_32 = compare_val[31:0];
    
    // Return old memory value regardless of operation
    assign return_val = mem_data;
    
    // Compute new value based on atomic function
    always_comb begin
        result = mem_data;  // Default: no change
        result_32 = mem_data_32;
        
        case (atom_func)
            ATOM_ADD: begin
                if (is_64bit) begin
                    result = mem_data + operand;
                end else begin
                    result_32 = mem_data_32 + operand_32;
                    result = {32'b0, result_32};
                end
            end
            
            ATOM_MIN: begin
                // Signed minimum
                if (is_64bit) begin
                    result = ($signed(mem_data) < $signed(operand)) ? mem_data : operand;
                end else begin
                    result_32 = ($signed(mem_data_32) < $signed(operand_32)) ? mem_data_32 : operand_32;
                    result = {32'b0, result_32};
                end
            end
            
            ATOM_MAX: begin
                // Signed maximum
                if (is_64bit) begin
                    result = ($signed(mem_data) > $signed(operand)) ? mem_data : operand;
                end else begin
                    result_32 = ($signed(mem_data_32) > $signed(operand_32)) ? mem_data_32 : operand_32;
                    result = {32'b0, result_32};
                end
            end
            
            ATOM_MINU: begin
                // Unsigned minimum
                if (is_64bit) begin
                    result = (mem_data < operand) ? mem_data : operand;
                end else begin
                    result_32 = (mem_data_32 < operand_32) ? mem_data_32 : operand_32;
                    result = {32'b0, result_32};
                end
            end
            
            ATOM_MAXU: begin
                // Unsigned maximum
                if (is_64bit) begin
                    result = (mem_data > operand) ? mem_data : operand;
                end else begin
                    result_32 = (mem_data_32 > operand_32) ? mem_data_32 : operand_32;
                    result = {32'b0, result_32};
                end
            end
            
            ATOM_AND: begin
                if (is_64bit) begin
                    result = mem_data & operand;
                end else begin
                    result_32 = mem_data_32 & operand_32;
                    result = {32'b0, result_32};
                end
            end
            
            ATOM_OR: begin
                if (is_64bit) begin
                    result = mem_data | operand;
                end else begin
                    result_32 = mem_data_32 | operand_32;
                    result = {32'b0, result_32};
                end
            end
            
            ATOM_XOR: begin
                if (is_64bit) begin
                    result = mem_data ^ operand;
                end else begin
                    result_32 = mem_data_32 ^ operand_32;
                    result = {32'b0, result_32};
                end
            end
            
            ATOM_EXCH: begin
                // Exchange: write operand, return old value
                if (is_64bit) begin
                    result = operand;
                end else begin
                    result = {32'b0, operand_32};
                end
            end
            
            ATOM_CAS: begin
                // Compare-and-swap: if mem == compare, write operand
                if (is_64bit) begin
                    result = (mem_data == compare_val) ? operand : mem_data;
                end else begin
                    result_32 = (mem_data_32 == compare_32) ? operand_32 : mem_data_32;
                    result = {32'b0, result_32};
                end
            end
            
            default: begin
                result = mem_data;
            end
        endcase
    end

endmodule

//=============================================================================
// Memory Coalescing Unit
//=============================================================================
// Coalesces memory requests from multiple threads into fewer transactions
// Groups addresses that fall within the same cache line

module coalescing_unit
    import gpgpu_pkg::*;
#(
    parameter int NUM_THREADS     = WARP_SIZE,
    parameter int CACHE_LINE_SIZE = 64,         // 64 bytes per cache line
    parameter int MAX_TRANSACTIONS = 4          // Max coalesced transactions
)(
    input  logic                                      clk,
    input  logic                                      rst_n,
    
    // Input request
    input  logic                                      req_valid,
    input  logic [NUM_THREADS-1:0]                    exec_mask,
    input  logic [NUM_THREADS-1:0][ADDR_WIDTH-1:0]   addresses,
    input  logic                                      is_write,
    input  logic [NUM_THREADS-1:0][DATA_WIDTH-1:0]   wdata,
    input  logic                                      is_64bit,      // 64-bit or 32-bit access
    
    // Coalesced output
    output logic                                      coalesced_valid,
    output logic [MAX_TRANSACTIONS-1:0]               trans_valid,
    output logic [MAX_TRANSACTIONS-1:0][ADDR_WIDTH-1:0] trans_addr,
    output logic [MAX_TRANSACTIONS-1:0][CACHE_LINE_SIZE*8-1:0] trans_wdata,
    output logic [MAX_TRANSACTIONS-1:0][CACHE_LINE_SIZE-1:0]   trans_wstrb,
    output logic [MAX_TRANSACTIONS-1:0][NUM_THREADS-1:0]       trans_thread_mask,
    output logic [MAX_TRANSACTIONS-1:0][NUM_THREADS-1:0][5:0]  trans_byte_offset,
    
    // Handshake
    input  logic                                      coalesced_ready,
    output logic                                      req_ready
);

    localparam int CL_OFFSET_BITS = $clog2(CACHE_LINE_SIZE);  // 6 bits for 64 bytes
    localparam int CL_ADDR_BITS = ADDR_WIDTH - CL_OFFSET_BITS;
    
    // Extract cache line addresses and offsets
    logic [NUM_THREADS-1:0][CL_ADDR_BITS-1:0] cl_addr;
    logic [NUM_THREADS-1:0][CL_OFFSET_BITS-1:0] cl_offset;
    
    always_comb begin
        for (int t = 0; t < NUM_THREADS; t++) begin
            cl_addr[t] = addresses[t][ADDR_WIDTH-1:CL_OFFSET_BITS];
            cl_offset[t] = addresses[t][CL_OFFSET_BITS-1:0];
        end
    end
    
    // Find unique cache lines (simplified - find up to MAX_TRANSACTIONS unique lines)
    logic [MAX_TRANSACTIONS-1:0][CL_ADDR_BITS-1:0] unique_cl_addr;
    logic [MAX_TRANSACTIONS-1:0] unique_valid;
    logic [NUM_THREADS-1:0][MAX_TRANSACTIONS-1:0] thread_to_trans;
    
    always_comb begin
        // Initialize
        unique_valid = '0;
        unique_cl_addr = '0;
        thread_to_trans = '0;
        trans_valid = '0;
        trans_addr = '0;
        trans_wdata = '0;
        trans_wstrb = '0;
        trans_thread_mask = '0;
        trans_byte_offset = '0;
        
        // Find unique cache lines and map threads to transactions
        for (int t = 0; t < NUM_THREADS; t++) begin
            if (exec_mask[t]) begin
                logic found;
                found = 1'b0;
                
                // Check if this cache line is already in our list
                for (int u = 0; u < MAX_TRANSACTIONS; u++) begin
                    if (!found && unique_valid[u] && (unique_cl_addr[u] == cl_addr[t])) begin
                        // Found matching cache line
                        thread_to_trans[t][u] = 1'b1;
                        trans_thread_mask[u][t] = 1'b1;
                        trans_byte_offset[u][t] = cl_offset[t];
                        found = 1'b1;
                    end
                end
                
                // If not found, add new cache line
                if (!found) begin
                    for (int u = 0; u < MAX_TRANSACTIONS; u++) begin
                        if (!found && !unique_valid[u]) begin
                            unique_valid[u] = 1'b1;
                            unique_cl_addr[u] = cl_addr[t];
                            thread_to_trans[t][u] = 1'b1;
                            trans_thread_mask[u][t] = 1'b1;
                            trans_byte_offset[u][t] = cl_offset[t];
                            found = 1'b1;
                        end
                    end
                end
            end
        end
        
        // Generate transaction addresses and data
        for (int u = 0; u < MAX_TRANSACTIONS; u++) begin
            if (unique_valid[u]) begin
                trans_valid[u] = 1'b1;
                trans_addr[u] = {unique_cl_addr[u], {CL_OFFSET_BITS{1'b0}}};
                
                // Merge write data from all threads in this transaction
                for (int t = 0; t < NUM_THREADS; t++) begin
                    if (trans_thread_mask[u][t]) begin
                        if (is_64bit) begin
                            // 64-bit access: 8 bytes at offset
                            for (int b = 0; b < 8; b++) begin
                                logic [5:0] byte_idx;
                                byte_idx = trans_byte_offset[u][t] + b[5:0];
                                if (byte_idx < CACHE_LINE_SIZE) begin
                                    trans_wdata[u][byte_idx*8 +: 8] = wdata[t][b*8 +: 8];
                                    trans_wstrb[u][byte_idx] = is_write;
                                end
                            end
                        end else begin
                            // 32-bit access: 4 bytes at offset
                            for (int b = 0; b < 4; b++) begin
                                logic [5:0] byte_idx;
                                byte_idx = trans_byte_offset[u][t] + b[5:0];
                                if (byte_idx < CACHE_LINE_SIZE) begin
                                    trans_wdata[u][byte_idx*8 +: 8] = wdata[t][b*8 +: 8];
                                    trans_wstrb[u][byte_idx] = is_write;
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    // Output valid when we have a request
    assign coalesced_valid = req_valid;
    assign req_ready = coalesced_ready;

endmodule

//=============================================================================
// Memory Request Sequencer
//=============================================================================
// Sequences coalesced memory transactions one at a time

module mem_request_sequencer
    import gpgpu_pkg::*;
#(
    parameter int NUM_THREADS     = WARP_SIZE,
    parameter int CACHE_LINE_SIZE = 64,
    parameter int MAX_TRANSACTIONS = 4
)(
    input  logic                                      clk,
    input  logic                                      rst_n,
    
    // Coalesced input
    input  logic                                      coalesced_valid,
    input  logic [MAX_TRANSACTIONS-1:0]               trans_valid,
    input  logic [MAX_TRANSACTIONS-1:0][ADDR_WIDTH-1:0] trans_addr,
    input  logic [MAX_TRANSACTIONS-1:0][CACHE_LINE_SIZE*8-1:0] trans_wdata,
    input  logic [MAX_TRANSACTIONS-1:0][CACHE_LINE_SIZE-1:0]   trans_wstrb,
    input  logic [MAX_TRANSACTIONS-1:0][NUM_THREADS-1:0]       trans_thread_mask,
    input  logic [MAX_TRANSACTIONS-1:0][NUM_THREADS-1:0][5:0]  trans_byte_offset,
    input  logic                                      is_write,
    input  logic                                      is_64bit,
    input  logic                                      is_signed,  // For 32-bit loads
    output logic                                      coalesced_ready,
    
    // Memory interface (simplified single transaction)
    output logic                                      mem_req_valid,
    output logic                                      mem_req_we,
    output logic [ADDR_WIDTH-1:0]                     mem_req_addr,
    output logic [DATA_WIDTH-1:0]                     mem_req_wdata,
    output logic [7:0]                                mem_req_wstrb,
    input  logic                                      mem_req_ready,
    input  logic                                      mem_resp_valid,
    input  logic [DATA_WIDTH-1:0]                     mem_resp_rdata,
    
    // Result output (per thread)
    output logic                                      result_valid,
    output logic [NUM_THREADS-1:0][DATA_WIDTH-1:0]    result_data,
    output logic [NUM_THREADS-1:0]                    result_mask
);

    // State machine states
    typedef enum logic [2:0] {
        S_IDLE,
        S_ISSUE,
        S_WAIT_RESP,
        S_COLLECT,
        S_DONE
    } state_t;
    
    state_t state, next_state;
    
    // Transaction tracking
    logic [$clog2(MAX_TRANSACTIONS)-1:0] current_trans;
    logic [MAX_TRANSACTIONS-1:0] trans_complete;
    logic [NUM_THREADS-1:0] pending_threads;
    
    // Latched request info
    logic [MAX_TRANSACTIONS-1:0] trans_valid_r;
    logic [MAX_TRANSACTIONS-1:0][ADDR_WIDTH-1:0] trans_addr_r;
    logic [MAX_TRANSACTIONS-1:0][CACHE_LINE_SIZE*8-1:0] trans_wdata_r;
    logic [MAX_TRANSACTIONS-1:0][CACHE_LINE_SIZE-1:0] trans_wstrb_r;
    logic [MAX_TRANSACTIONS-1:0][NUM_THREADS-1:0] trans_thread_mask_r;
    logic [MAX_TRANSACTIONS-1:0][NUM_THREADS-1:0][5:0] trans_byte_offset_r;
    logic is_write_r, is_64bit_r, is_signed_r;
    
    // Result accumulator
    logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] result_accum;
    logic [NUM_THREADS-1:0] result_mask_accum;
    
    // Sub-transaction index for multi-beat accesses
    logic [2:0] beat_idx;
    
    // Count pending transactions
    logic [$clog2(MAX_TRANSACTIONS):0] pending_count;
    always_comb begin
        pending_count = '0;
        for (int i = 0; i < MAX_TRANSACTIONS; i++) begin
            if (trans_valid_r[i] && !trans_complete[i]) begin
                pending_count = pending_count + 1;
            end
        end
    end
    
    // Find next pending transaction
    logic [$clog2(MAX_TRANSACTIONS)-1:0] next_trans;
    logic next_trans_valid;
    always_comb begin
        next_trans = '0;
        next_trans_valid = 1'b0;
        for (int i = 0; i < MAX_TRANSACTIONS; i++) begin
            if (!next_trans_valid && trans_valid_r[i] && !trans_complete[i]) begin
                next_trans = i[$clog2(MAX_TRANSACTIONS)-1:0];
                next_trans_valid = 1'b1;
            end
        end
    end
    
    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            current_trans <= '0;
            trans_complete <= '0;
            trans_valid_r <= '0;
            trans_addr_r <= '0;
            trans_wdata_r <= '0;
            trans_wstrb_r <= '0;
            trans_thread_mask_r <= '0;
            trans_byte_offset_r <= '0;
            is_write_r <= 1'b0;
            is_64bit_r <= 1'b0;
            is_signed_r <= 1'b0;
            result_accum <= '0;
            result_mask_accum <= '0;
            pending_threads <= '0;
            beat_idx <= '0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (coalesced_valid) begin
                        // Latch request
                        trans_valid_r <= trans_valid;
                        trans_addr_r <= trans_addr;
                        trans_wdata_r <= trans_wdata;
                        trans_wstrb_r <= trans_wstrb;
                        trans_thread_mask_r <= trans_thread_mask;
                        trans_byte_offset_r <= trans_byte_offset;
                        is_write_r <= is_write;
                        is_64bit_r <= is_64bit;
                        is_signed_r <= is_signed;
                        trans_complete <= '0;
                        result_accum <= '0;
                        result_mask_accum <= '0;
                        beat_idx <= '0;
                        
                        // Find first transaction
                        if (next_trans_valid) begin
                            current_trans <= next_trans;
                            state <= S_ISSUE;
                        end else begin
                            state <= S_DONE;
                        end
                    end
                end
                
                S_ISSUE: begin
                    if (mem_req_ready) begin
                        state <= S_WAIT_RESP;
                    end
                end
                
                S_WAIT_RESP: begin
                    if (mem_resp_valid) begin
                        state <= S_COLLECT;
                    end
                end
                
                S_COLLECT: begin
                    // Collect data for all threads in this transaction
                    for (int t = 0; t < NUM_THREADS; t++) begin
                        if (trans_thread_mask_r[current_trans][t]) begin
                            logic [5:0] byte_off;
                            byte_off = trans_byte_offset_r[current_trans][t];
                            
                            if (!is_write_r) begin
                                if (is_64bit_r) begin
                                    // 64-bit load - extract 8 bytes
                                    result_accum[t] <= mem_resp_rdata;
                                end else begin
                                    // 32-bit load - extract 4 bytes
                                    logic [31:0] data32;
                                    data32 = mem_resp_rdata[31:0];
                                    if (is_signed_r) begin
                                        result_accum[t] <= {{32{data32[31]}}, data32};
                                    end else begin
                                        result_accum[t] <= {32'b0, data32};
                                    end
                                end
                                result_mask_accum[t] <= 1'b1;
                            end
                        end
                    end
                    
                    // Mark transaction complete
                    trans_complete[current_trans] <= 1'b1;
                    
                    // Move to next transaction or done
                    if (pending_count > 1) begin
                        current_trans <= next_trans;
                        state <= S_ISSUE;
                    end else begin
                        state <= S_DONE;
                    end
                end
                
                S_DONE: begin
                    state <= S_IDLE;
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end
    
    // Memory request outputs
    assign mem_req_valid = (state == S_ISSUE);
    assign mem_req_we = is_write_r;
    assign mem_req_addr = trans_addr_r[current_trans] + {58'b0, beat_idx, 3'b0};
    
    // Extract write data for current beat
    always_comb begin
        mem_req_wdata = '0;
        mem_req_wstrb = '0;
        if (state == S_ISSUE && is_write_r) begin
            // For simplified implementation, output 64-bit data
            mem_req_wdata = trans_wdata_r[current_trans][beat_idx*64 +: 64];
            mem_req_wstrb = trans_wstrb_r[current_trans][beat_idx*8 +: 8];
        end
    end
    
    // Control outputs
    assign coalesced_ready = (state == S_IDLE);
    assign result_valid = (state == S_DONE) && !is_write_r;
    assign result_data = result_accum;
    assign result_mask = result_mask_accum;

endmodule

//=============================================================================
// Load/Store Unit Top Module
//=============================================================================

module lsu
    import gpgpu_pkg::*;
#(
    parameter int NUM_THREADS = WARP_SIZE,
    parameter int SHARED_MEM_ADDR_WIDTH = 14  // 16KB = 14 bits
)(
    input  logic                                      clk,
    input  logic                                      rst_n,
    
    // Request interface (from execute stage)
    input  logic                                      req_valid,
    input  logic [WARP_ID_WIDTH-1:0]                  req_warp_id,
    input  logic [NUM_THREADS-1:0]                    req_active_mask,
    input  logic [NUM_THREADS-1:0]                    req_pred_mask,
    input  opcode_t                                   req_opcode,
    input  logic [7:0]                                req_func,        // Function code for atomics
    input  logic [REG_ADDR_WIDTH-1:0]                 req_rd,
    input  logic [NUM_THREADS-1:0][ADDR_WIDTH-1:0]    req_base_addr,
    input  logic signed [12:0]                        req_offset,
    input  logic [NUM_THREADS-1:0][DATA_WIDTH-1:0]    req_store_data,
    output logic                                      req_ready,
    
    // Response interface (to writeback stage)
    output logic                                      resp_valid,
    output logic [WARP_ID_WIDTH-1:0]                  resp_warp_id,
    output logic [REG_ADDR_WIDTH-1:0]                 resp_rd,
    output logic [NUM_THREADS-1:0]                    resp_mask,
    output logic [NUM_THREADS-1:0][DATA_WIDTH-1:0]    resp_data,
    input  logic                                      resp_ready,
    
    // Global memory interface (AXI-like simplified)
    output logic                                      gmem_req_valid,
    output logic                                      gmem_req_we,
    output logic [ADDR_WIDTH-1:0]                     gmem_req_addr,
    output logic [DATA_WIDTH-1:0]                     gmem_req_wdata,
    output logic [7:0]                                gmem_req_wstrb,
    input  logic                                      gmem_req_ready,
    input  logic                                      gmem_resp_valid,
    input  logic [DATA_WIDTH-1:0]                     gmem_resp_rdata,
    
    // Shared memory interface
    output logic                                      smem_req_valid,
    output logic                                      smem_req_we,
    output logic [NUM_THREADS-1:0]                    smem_req_mask,
    output logic [NUM_THREADS-1:0][SHARED_MEM_ADDR_WIDTH-1:0] smem_req_addr,
    output logic [NUM_THREADS-1:0][DATA_WIDTH-1:0]    smem_req_wdata,
    output logic [NUM_THREADS-1:0][7:0]               smem_req_wstrb,
    input  logic                                      smem_req_ready,
    input  logic                                      smem_resp_valid,
    input  logic [NUM_THREADS-1:0][DATA_WIDTH-1:0]    smem_resp_rdata
);

    //=========================================================================
    // Decode memory operation type
    //=========================================================================
    
    logic is_load, is_store, is_atomic;
    logic is_global, is_shared;
    logic is_64bit, is_signed;
    atom_func_t atom_func;
    
    always_comb begin
        is_load = 1'b0;
        is_store = 1'b0;
        is_atomic = 1'b0;
        is_global = 1'b0;
        is_shared = 1'b0;
        is_64bit = 1'b0;
        is_signed = 1'b0;
        atom_func = ATOM_ADD;
        
        case (req_opcode)
            OP_LD: begin
                is_load = 1'b1;
                is_global = 1'b1;
                is_64bit = 1'b1;
            end
            OP_LD32: begin
                is_load = 1'b1;
                is_global = 1'b1;
                is_64bit = 1'b0;
                is_signed = 1'b0;
            end
            OP_LD32S: begin
                is_load = 1'b1;
                is_global = 1'b1;
                is_64bit = 1'b0;
                is_signed = 1'b1;
            end
            OP_LDS: begin
                is_load = 1'b1;
                is_shared = 1'b1;
                is_64bit = 1'b1;
            end
            OP_LDS32: begin
                is_load = 1'b1;
                is_shared = 1'b1;
                is_64bit = 1'b0;
            end
            OP_ST: begin
                is_store = 1'b1;
                is_global = 1'b1;
                is_64bit = 1'b1;
            end
            OP_ST32: begin
                is_store = 1'b1;
                is_global = 1'b1;
                is_64bit = 1'b0;
            end
            OP_STS: begin
                is_store = 1'b1;
                is_shared = 1'b1;
                is_64bit = 1'b1;
            end
            OP_STS32: begin
                is_store = 1'b1;
                is_shared = 1'b1;
                is_64bit = 1'b0;
            end
            // Atomic operations - global memory, 32-bit
            OP_ATOM: begin
                is_atomic = 1'b1;
                is_global = 1'b1;
                is_64bit = 1'b0;
                atom_func = atom_func_t'(req_func[3:0]);
            end
            // Atomic operations - shared memory, 32-bit
            OP_ATOMS: begin
                is_atomic = 1'b1;
                is_shared = 1'b1;
                is_64bit = 1'b0;
                atom_func = atom_func_t'(req_func[3:0]);
            end
            // Atomic operations - global memory, 64-bit
            OP_ATOM64: begin
                is_atomic = 1'b1;
                is_global = 1'b1;
                is_64bit = 1'b1;
                atom_func = atom_func_t'(req_func[3:0]);
            end
            // Atomic operations - shared memory, 64-bit
            OP_ATOMS64: begin
                is_atomic = 1'b1;
                is_shared = 1'b1;
                is_64bit = 1'b1;
                atom_func = atom_func_t'(req_func[3:0]);
            end
            default: begin
                // Not a memory operation
            end
        endcase
    end
    
    //=========================================================================
    // Address Generation
    //=========================================================================
    
    logic [NUM_THREADS-1:0][ADDR_WIDTH-1:0] eff_addr;
    logic [NUM_THREADS-1:0] exec_mask;
    
    address_gen_unit #(
        .NUM_THREADS(NUM_THREADS)
    ) addr_gen (
        .base_addr(req_base_addr),
        .offset(req_offset),
        .active_mask(req_active_mask),
        .pred_mask(req_pred_mask),
        .eff_addr(eff_addr),
        .exec_mask(exec_mask)
    );
    
    //=========================================================================
    // State Machine
    //=========================================================================
    
    typedef enum logic [3:0] {
        LSU_IDLE,
        LSU_GLOBAL_ACCESS,
        LSU_SHARED_ACCESS,
        LSU_WAIT_GLOBAL,
        LSU_WAIT_SHARED,
        LSU_ATOMIC_READ,      // Read phase of atomic RMW
        LSU_ATOMIC_WAIT_READ, // Wait for read response
        LSU_ATOMIC_WRITE,     // Write phase of atomic RMW
        LSU_ATOMIC_WAIT_WRITE,// Wait for write complete
        LSU_COMPLETE
    } lsu_state_t;
    
    lsu_state_t state, next_state;
    
    // Registered request data
    logic [WARP_ID_WIDTH-1:0] warp_id_r;
    logic [REG_ADDR_WIDTH-1:0] rd_r;
    logic [NUM_THREADS-1:0] exec_mask_r;
    logic [NUM_THREADS-1:0][ADDR_WIDTH-1:0] eff_addr_r;
    logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] store_data_r;
    logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] compare_data_r;  // For CAS: compare value from RD
    logic is_load_r, is_store_r, is_atomic_r, is_global_r, is_shared_r;
    logic is_64bit_r, is_signed_r;
    atom_func_t atom_func_r;
    
    // Atomic ALU signals
    logic [DATA_WIDTH-1:0] atomic_mem_data;
    logic [DATA_WIDTH-1:0] atomic_new_value;
    logic [DATA_WIDTH-1:0] atomic_old_value;
    
    // Result data
    logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] result_data_r;
    logic [NUM_THREADS-1:0] result_mask_r;
    
    // Thread iterator for sequential global access
    logic [THREAD_ID_WIDTH:0] thread_idx;
    logic thread_found;
    
    // Temporary data for 32-bit operations
    logic [31:0] gmem_data32;
    logic [DATA_WIDTH-1:0] gmem_data_extended;
    logic [NUM_THREADS-1:0][31:0] smem_data32;
    logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] smem_data_extended;
    
    always_comb begin
        gmem_data32 = gmem_resp_rdata[31:0];
        if (is_signed_r) begin
            gmem_data_extended = {{32{gmem_data32[31]}}, gmem_data32};
        end else begin
            gmem_data_extended = {32'b0, gmem_data32};
        end
        
        for (int t = 0; t < NUM_THREADS; t++) begin
            smem_data32[t] = smem_resp_rdata[t][31:0];
            if (is_signed_r) begin
                smem_data_extended[t] = {{32{smem_data32[t][31]}}, smem_data32[t]};
            end else begin
                smem_data_extended[t] = {32'b0, smem_data32[t]};
            end
        end
    end
    
    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= LSU_IDLE;
            warp_id_r <= '0;
            rd_r <= '0;
            exec_mask_r <= '0;
            eff_addr_r <= '0;
            store_data_r <= '0;
            compare_data_r <= '0;
            is_load_r <= 1'b0;
            is_store_r <= 1'b0;
            is_atomic_r <= 1'b0;
            is_global_r <= 1'b0;
            is_shared_r <= 1'b0;
            is_64bit_r <= 1'b0;
            is_signed_r <= 1'b0;
            atom_func_r <= ATOM_ADD;
            result_data_r <= '0;
            result_mask_r <= '0;
            thread_idx <= '0;
        end else begin
            case (state)
                LSU_IDLE: begin
                    if (req_valid && (is_load || is_store || is_atomic)) begin
                        // Latch request
                        warp_id_r <= req_warp_id;
                        rd_r <= req_rd;
                        exec_mask_r <= exec_mask;
                        eff_addr_r <= eff_addr;
                        store_data_r <= req_store_data;
                        compare_data_r <= req_store_data;  // For CAS, compare value
                        is_load_r <= is_load;
                        is_store_r <= is_store;
                        is_atomic_r <= is_atomic;
                        is_global_r <= is_global;
                        is_shared_r <= is_shared;
                        is_64bit_r <= is_64bit;
                        is_signed_r <= is_signed;
                        atom_func_r <= atom_func;
                        result_data_r <= '0;
                        result_mask_r <= '0;
                        thread_idx <= '0;
                        
                        if (is_atomic) begin
                            // Atomic operations go to read phase first
                            state <= LSU_ATOMIC_READ;
                        end else if (is_global) begin
                            state <= LSU_GLOBAL_ACCESS;
                        end else begin
                            state <= LSU_SHARED_ACCESS;
                        end
                    end
                end
                
                LSU_GLOBAL_ACCESS: begin
                    // Find next active thread for sequential access
                    // If current thread is not active, skip to next
                    if (!exec_mask_r[thread_idx[THREAD_ID_WIDTH-1:0]]) begin
                        // Skip inactive thread
                        if (thread_idx >= NUM_THREADS - 1) begin
                            state <= LSU_COMPLETE;
                        end else begin
                            thread_idx <= thread_idx + 1;
                            // Stay in this state to check next thread
                        end
                    end else if (gmem_req_ready) begin
                        state <= LSU_WAIT_GLOBAL;
                    end
                end
                
                LSU_WAIT_GLOBAL: begin
                    if (gmem_resp_valid || is_store_r) begin
                        // Store response data
                        if (is_load_r) begin
                            if (is_64bit_r) begin
                                result_data_r[thread_idx[THREAD_ID_WIDTH-1:0]] <= gmem_resp_rdata;
                            end else begin
                                // 32-bit load - use pre-computed extended value
                                result_data_r[thread_idx[THREAD_ID_WIDTH-1:0]] <= gmem_data_extended;
                            end
                            result_mask_r[thread_idx[THREAD_ID_WIDTH-1:0]] <= 1'b1;
                        end
                        
                        // Find next thread
                        thread_idx <= thread_idx + 1;
                        
                        // Check if more threads
                        if (thread_idx >= NUM_THREADS - 1) begin
                            state <= LSU_COMPLETE;
                        end else begin
                            // Look for next active thread
                            state <= LSU_GLOBAL_ACCESS;
                        end
                    end
                end
                
                LSU_SHARED_ACCESS: begin
                    if (smem_req_ready) begin
                        state <= LSU_WAIT_SHARED;
                    end
                end
                
                LSU_WAIT_SHARED: begin
                    if (smem_resp_valid || is_store_r) begin
                        // Shared memory handles all threads at once
                        if (is_load_r) begin
                            for (int t = 0; t < NUM_THREADS; t++) begin
                                if (exec_mask_r[t]) begin
                                    if (is_64bit_r) begin
                                        result_data_r[t] <= smem_resp_rdata[t];
                                    end else begin
                                        // 32-bit load - use pre-computed extended value
                                        result_data_r[t] <= smem_data_extended[t];
                                    end
                                    result_mask_r[t] <= 1'b1;
                                end
                            end
                        end
                        state <= LSU_COMPLETE;
                    end
                end
                
                //=============================================================
                // Atomic operation states (serialized read-modify-write)
                //=============================================================
                
                LSU_ATOMIC_READ: begin
                    // Issue read to memory for current thread
                    if (!exec_mask_r[thread_idx[THREAD_ID_WIDTH-1:0]]) begin
                        // Skip inactive thread
                        if (thread_idx >= NUM_THREADS - 1) begin
                            state <= LSU_COMPLETE;
                        end else begin
                            thread_idx <= thread_idx + 1;
                        end
                    end else if (gmem_req_ready) begin
                        state <= LSU_ATOMIC_WAIT_READ;
                    end
                end
                
                LSU_ATOMIC_WAIT_READ: begin
                    if (gmem_resp_valid) begin
                        // Store old value for return
                        if (is_64bit_r) begin
                            result_data_r[thread_idx[THREAD_ID_WIDTH-1:0]] <= gmem_resp_rdata;
                        end else begin
                            result_data_r[thread_idx[THREAD_ID_WIDTH-1:0]] <= gmem_data_extended;
                        end
                        result_mask_r[thread_idx[THREAD_ID_WIDTH-1:0]] <= 1'b1;
                        // Proceed to write phase
                        state <= LSU_ATOMIC_WRITE;
                    end
                end
                
                LSU_ATOMIC_WRITE: begin
                    // Write new value to memory
                    if (gmem_req_ready) begin
                        state <= LSU_ATOMIC_WAIT_WRITE;
                    end
                end
                
                LSU_ATOMIC_WAIT_WRITE: begin
                    // For stores, we assume completion when ready was asserted
                    // Move to next thread or complete
                    thread_idx <= thread_idx + 1;
                    if (thread_idx >= NUM_THREADS - 1) begin
                        state <= LSU_COMPLETE;
                    end else begin
                        state <= LSU_ATOMIC_READ;
                    end
                end
                
                LSU_COMPLETE: begin
                    if (resp_ready || is_store_r) begin
                        state <= LSU_IDLE;
                    end
                end
                
                default: state <= LSU_IDLE;
            endcase
        end
    end
    
    // Find current active thread for global access
    always_comb begin
        thread_found = 1'b0;
        for (int t = 0; t < NUM_THREADS; t++) begin
            if (!thread_found && (t >= thread_idx) && exec_mask_r[t]) begin
                thread_found = 1'b1;
            end
        end
    end
    
    // Find the actual thread index we're working on
    logic [THREAD_ID_WIDTH-1:0] current_thread;
    always_comb begin
        current_thread = thread_idx[THREAD_ID_WIDTH-1:0];
        for (int t = 0; t < NUM_THREADS; t++) begin
            if ((t >= thread_idx) && exec_mask_r[t]) begin
                current_thread = t[THREAD_ID_WIDTH-1:0];
            end
        end
    end
    
    //=========================================================================
    // Atomic ALU Instance
    //=========================================================================
    
    atomic_alu atomic_alu_inst (
        .mem_data(atomic_mem_data),
        .operand(store_data_r[thread_idx[THREAD_ID_WIDTH-1:0]]),
        .compare_val(compare_data_r[thread_idx[THREAD_ID_WIDTH-1:0]]),
        .atom_func(atom_func_r),
        .is_64bit(is_64bit_r),
        .result(atomic_new_value),
        .return_val(atomic_old_value)
    );
    
    // Atomic memory data comes from global memory response
    assign atomic_mem_data = gmem_resp_rdata;
    
    //=========================================================================
    // Output Generation
    //=========================================================================
    
    // Request ready when idle
    assign req_ready = (state == LSU_IDLE);
    
    // Global memory interface - includes atomic operations
    logic gmem_valid_load_store, gmem_valid_atomic;
    assign gmem_valid_load_store = (state == LSU_GLOBAL_ACCESS) && exec_mask_r[thread_idx[THREAD_ID_WIDTH-1:0]];
    assign gmem_valid_atomic = ((state == LSU_ATOMIC_READ) || (state == LSU_ATOMIC_WRITE)) && 
                               exec_mask_r[thread_idx[THREAD_ID_WIDTH-1:0]];
    
    assign gmem_req_valid = gmem_valid_load_store || gmem_valid_atomic;
    assign gmem_req_we = is_store_r || (state == LSU_ATOMIC_WRITE);
    assign gmem_req_addr = eff_addr_r[thread_idx[THREAD_ID_WIDTH-1:0]];
    
    // Write data: for atomics in write phase, use computed new value
    always_comb begin
        if (is_atomic_r && (state == LSU_ATOMIC_WRITE)) begin
            gmem_req_wdata = atomic_new_value;
        end else begin
            gmem_req_wdata = store_data_r[thread_idx[THREAD_ID_WIDTH-1:0]];
        end
    end
    
    assign gmem_req_wstrb = is_64bit_r ? 8'hFF : 8'h0F;
    
    // Shared memory interface
    assign smem_req_valid = (state == LSU_SHARED_ACCESS);
    assign smem_req_we = is_store_r;
    assign smem_req_mask = exec_mask_r;
    
    always_comb begin
        for (int t = 0; t < NUM_THREADS; t++) begin
            smem_req_addr[t] = eff_addr_r[t][SHARED_MEM_ADDR_WIDTH-1:0];
            smem_req_wdata[t] = store_data_r[t];
            smem_req_wstrb[t] = is_64bit_r ? 8'hFF : 8'h0F;
        end
    end
    
    // Response interface - atomics also return old value to register
    assign resp_valid = (state == LSU_COMPLETE) && (is_load_r || is_atomic_r);
    assign resp_warp_id = warp_id_r;
    assign resp_rd = rd_r;
    assign resp_mask = result_mask_r;
    assign resp_data = result_data_r;

endmodule

//=============================================================================
// Shared Memory Bank
//=============================================================================
// Single-ported memory bank for shared memory

module shared_mem_bank
    import gpgpu_pkg::*;
#(
    parameter int BANK_SIZE  = 2048,    // Words per bank
    parameter int DATA_WIDTH = 64,
    parameter int ADDR_WIDTH = 11       // log2(2048)
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Access port
    input  logic                    req,
    input  logic                    we,
    input  logic [ADDR_WIDTH-1:0]   addr,
    input  logic [DATA_WIDTH-1:0]   wdata,
    input  logic [7:0]              wstrb,
    output logic                    valid,
    output logic [DATA_WIDTH-1:0]   rdata
);

    // Memory array
    logic [DATA_WIDTH-1:0] mem [0:BANK_SIZE-1];
    
    // Registered outputs
    logic [DATA_WIDTH-1:0] rdata_r;
    logic valid_r;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_r <= 1'b0;
            rdata_r <= '0;
        end else begin
            valid_r <= req && !we;
            
            if (req) begin
                if (we) begin
                    // Write with byte strobes
                    for (int i = 0; i < 8; i++) begin
                        if (wstrb[i]) begin
                            mem[addr][i*8 +: 8] <= wdata[i*8 +: 8];
                        end
                    end
                end else begin
                    // Read
                    rdata_r <= mem[addr];
                end
            end
        end
    end
    
    assign valid = valid_r;
    assign rdata = rdata_r;

endmodule

//=============================================================================
// Shared Memory Unit (Banked)
//=============================================================================
// Multi-banked shared memory with bank conflict detection

module shared_memory
    import gpgpu_pkg::*;
#(
    parameter int NUM_BANKS   = 8,           // Number of banks (match WARP_SIZE)
    parameter int BANK_SIZE   = 2048,        // Words per bank
    parameter int DATA_WIDTH  = 64,
    parameter int ADDR_WIDTH  = 14           // Total address width (16KB)
)(
    input  logic                                      clk,
    input  logic                                      rst_n,
    
    // Request interface (from LSU)
    input  logic                                      req_valid,
    input  logic                                      req_we,
    input  logic [NUM_BANKS-1:0]                      req_mask,
    input  logic [NUM_BANKS-1:0][ADDR_WIDTH-1:0]      req_addr,
    input  logic [NUM_BANKS-1:0][DATA_WIDTH-1:0]      req_wdata,
    input  logic [NUM_BANKS-1:0][7:0]                 req_wstrb,
    output logic                                      req_ready,
    
    // Response interface
    output logic                                      resp_valid,
    output logic [NUM_BANKS-1:0][DATA_WIDTH-1:0]      resp_rdata
);

    localparam int BANK_ADDR_WIDTH = $clog2(BANK_SIZE);  // 11 bits
    localparam int BANK_SEL_WIDTH = $clog2(NUM_BANKS);   // 3 bits
    
    // Extract bank and offset from address
    // Address layout: [BANK_ADDR | BANK_SEL]
    // This provides interleaved access for stride-1 patterns
    
    logic [NUM_BANKS-1:0][BANK_SEL_WIDTH-1:0] bank_sel;
    logic [NUM_BANKS-1:0][BANK_ADDR_WIDTH-1:0] bank_addr;
    
    always_comb begin
        for (int t = 0; t < NUM_BANKS; t++) begin
            bank_sel[t] = req_addr[t][BANK_SEL_WIDTH-1:0];
            bank_addr[t] = req_addr[t][BANK_SEL_WIDTH +: BANK_ADDR_WIDTH];
        end
    end
    
    // Bank conflict detection
    logic [NUM_BANKS-1:0] bank_busy;
    logic [NUM_BANKS-1:0] thread_conflict;
    logic has_conflict;
    
    always_comb begin
        bank_busy = '0;
        thread_conflict = '0;
        has_conflict = 1'b0;
        
        for (int t = 0; t < NUM_BANKS; t++) begin
            if (req_mask[t]) begin
                if (bank_busy[bank_sel[t]]) begin
                    thread_conflict[t] = 1'b1;
                    has_conflict = 1'b1;
                end else begin
                    bank_busy[bank_sel[t]] = 1'b1;
                end
            end
        end
    end
    
    // Bank access multiplexing (simplified - no conflict handling)
    logic [NUM_BANKS-1:0] bank_req;
    logic [NUM_BANKS-1:0] bank_we;
    logic [NUM_BANKS-1:0][BANK_ADDR_WIDTH-1:0] bank_access_addr;
    logic [NUM_BANKS-1:0][DATA_WIDTH-1:0] bank_wdata;
    logic [NUM_BANKS-1:0][7:0] bank_wstrb;
    logic [NUM_BANKS-1:0] bank_valid;
    logic [NUM_BANKS-1:0][DATA_WIDTH-1:0] bank_rdata;
    
    // Map thread requests to banks
    always_comb begin
        bank_req = '0;
        bank_we = '0;
        bank_access_addr = '0;
        bank_wdata = '0;
        bank_wstrb = '0;
        
        for (int t = 0; t < NUM_BANKS; t++) begin
            if (req_valid && req_mask[t] && !thread_conflict[t]) begin
                bank_req[bank_sel[t]] = 1'b1;
                bank_we[bank_sel[t]] = req_we;
                bank_access_addr[bank_sel[t]] = bank_addr[t];
                bank_wdata[bank_sel[t]] = req_wdata[t];
                bank_wstrb[bank_sel[t]] = req_wstrb[t];
            end
        end
    end
    
    // Instantiate banks
    genvar b;
    generate
        for (b = 0; b < NUM_BANKS; b++) begin : gen_banks
            shared_mem_bank #(
                .BANK_SIZE(BANK_SIZE),
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(BANK_ADDR_WIDTH)
            ) bank (
                .clk(clk),
                .rst_n(rst_n),
                .req(bank_req[b]),
                .we(bank_we[b]),
                .addr(bank_access_addr[b]),
                .wdata(bank_wdata[b]),
                .wstrb(bank_wstrb[b]),
                .valid(bank_valid[b]),
                .rdata(bank_rdata[b])
            );
        end
    endgenerate
    
    // Demux bank read data back to threads
    logic [NUM_BANKS-1:0][DATA_WIDTH-1:0] resp_rdata_r;
    logic [NUM_BANKS-1:0][BANK_SEL_WIDTH-1:0] bank_sel_r;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bank_sel_r <= '0;
        end else begin
            bank_sel_r <= bank_sel;
        end
    end
    
    always_comb begin
        for (int t = 0; t < NUM_BANKS; t++) begin
            resp_rdata_r[t] = bank_rdata[bank_sel_r[t]];
        end
    end
    
    // Response valid when all accessed banks are valid
    logic all_banks_valid;
    always_comb begin
        all_banks_valid = 1'b1;
        for (int b = 0; b < NUM_BANKS; b++) begin
            if (bank_req[b] && !bank_valid[b]) begin
                all_banks_valid = 1'b0;
            end
        end
    end
    
    assign req_ready = !has_conflict;  // Simplified: don't accept if conflict
    assign resp_valid = all_banks_valid && (|bank_valid);
    assign resp_rdata = resp_rdata_r;

endmodule
