//=============================================================================
// GPGPU-1 FPGA Wrapper for Artix-7 Student Boards
//=============================================================================
// File:        gpgpu_artix7_wrapper.sv
// Description: Simplified FPGA wrapper for Artix-7 based student boards
//              - Nexys A7-100T, Arty A7-100T, Basys3 (limited)
//              - No Zynq PS - uses UART for host communication
//              - Uses on-chip BRAM for program/data memory (no DDR)
//              - Reduced resource configuration for smaller FPGAs
// Target:      Xilinx Artix-7 (XC7A100T)
// Version:     1.0
//=============================================================================

`include "gpgpu_defines.svh"

module gpgpu_artix7_wrapper
    import gpgpu_pkg::*;
#(
    //=========================================================================
    // REDUCED CONFIGURATION for Artix-7 100T
    //=========================================================================
    // Resource budget (approximate):
    //   - LUTs: ~63,400 available, target <80% = 50,000
    //   - BRAM: ~135 x 36Kb = 4,860 Kb, target <70% = 3,400 Kb  
    //   - DSP:  ~240 available, target <80% = 190
    //=========================================================================
    
    parameter int NUM_CORES       = 1,     // Single core for Artix-7 (was 4)
    parameter int WARPS_PER_CORE  = 2,     // Reduced warps (was 4)
    parameter int ICACHE_SIZE     = 2048,  // 2KB instruction cache (was 4KB)
    parameter int SHARED_MEM_SIZE = 4096,  // 4KB shared memory (was 16KB)
    
    // Clock configuration
    parameter int INPUT_CLK_FREQ  = 100,   // 100 MHz input from oscillator
    parameter int CORE_CLK_FREQ   = 50,    // Run GPU at 50 MHz for timing
    
    // Memory configuration (on-chip BRAM based)
    parameter int PROG_MEM_SIZE   = 8192,  // 8KB program memory
    parameter int DATA_MEM_SIZE   = 16384, // 16KB data memory
    
    // Feature flags
    parameter bit ENABLE_DP_FPU   = 0,     // Disable DP FPU to save DSPs
    parameter bit ENABLE_7SEG     = 1,     // Enable 7-segment display
    parameter bit ENABLE_UART     = 1      // Enable UART control
)(
    //=========================================================================
    // Board-Level I/O
    //=========================================================================
    
    input  logic        sys_clk,          // 100 MHz single-ended clock
    input  logic        sys_rst_n,        // Active-low reset (CPU_RESETN)
    
    // User interface
    input  logic [3:0]  sw,               // Slide switches
    input  logic        btn_start,        // Start kernel button (BTNC)
    input  logic        btn_up,           // Up button
    input  logic        btn_down,         // Down button
    output logic [7:0]  led,              // Status LEDs
    
    // 7-segment display
    output logic [7:0]  seg_an,           // Anodes (active low)
    output logic [7:0]  seg_ca,           // Cathodes (active low)
    
    // UART interface
    input  logic        uart_rx,
    output logic        uart_tx
);

    //=========================================================================
    // Local Signals
    //=========================================================================
    
    // Clock and reset
    logic core_clk;
    logic core_rst_n;
    logic clk_locked;
    
    // Reset synchronizer
    logic [3:0] rst_sync_reg;
    
    // GPU command interface
    logic                    cmd_valid;
    logic                    cmd_ready;
    logic [3:0]              cmd_opcode;
    logic [ADDR_WIDTH-1:0]   cmd_pc;
    logic [31:0]             cmd_grid_dim_x;
    logic [31:0]             cmd_grid_dim_y;
    logic [31:0]             cmd_grid_dim_z;
    logic [15:0]             cmd_block_dim_x;
    logic [15:0]             cmd_block_dim_y;
    logic [15:0]             cmd_block_dim_z;
    
    // GPU status
    logic                    gpu_busy;
    logic                    gpu_done;
    logic [NUM_CORES-1:0]    cores_active;
    logic [31:0]             perf_cycle_count;
    logic [31:0]             perf_instr_count;
    
    // Memory interface (simplified for BRAM)
    logic                    mem_req_valid;
    logic                    mem_req_ready;
    logic                    mem_req_write;
    logic [31:0]             mem_req_addr;
    logic [63:0]             mem_req_wdata;
    logic [7:0]              mem_req_wmask;
    logic                    mem_resp_valid;
    logic [63:0]             mem_resp_data;
    
    // Button debouncing
    logic btn_start_db, btn_start_prev, btn_start_pulse;
    logic [19:0] debounce_cnt;
    
    // UART signals
    logic [7:0] uart_rx_data;
    logic       uart_rx_valid;
    logic [7:0] uart_tx_data;
    logic       uart_tx_valid;
    logic       uart_tx_ready;
    
    // 7-segment display
    logic [31:0] display_value;
    logic [2:0]  digit_sel;
    logic [19:0] refresh_cnt;
    
    //=========================================================================
    // Clock Management (MMCME2 for Artix-7)
    //=========================================================================
    
    `ifdef SYNTHESIS
    
    logic mmcm_clk_fb;
    logic mmcm_clk_out0;
    
    // MMCME2_ADV for Artix-7 (different from Ultrascale MMCME4)
    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKFBOUT_MULT_F      (10.0),         // VCO = 1000 MHz
        .CLKFBOUT_PHASE       (0.0),
        .CLKIN1_PERIOD        (10.0),         // 100 MHz input
        .CLKOUT0_DIVIDE_F     (20.0),         // 50 MHz output (slower for timing)
        .CLKOUT0_DUTY_CYCLE   (0.5),
        .CLKOUT0_PHASE        (0.0),
        .DIVCLK_DIVIDE        (1),
        .REF_JITTER1          (0.010),
        .STARTUP_WAIT         ("FALSE")
    ) u_mmcm (
        .CLKFBOUT     (mmcm_clk_fb),
        .CLKFBOUTB    (),
        .CLKOUT0      (mmcm_clk_out0),
        .CLKOUT0B     (),
        .CLKOUT1      (),
        .CLKOUT1B     (),
        .CLKOUT2      (),
        .CLKOUT2B     (),
        .CLKOUT3      (),
        .CLKOUT3B     (),
        .CLKOUT4      (),
        .CLKOUT5      (),
        .CLKOUT6      (),
        .LOCKED       (clk_locked),
        .CLKFBIN      (mmcm_clk_fb),
        .CLKIN1       (sys_clk),
        .CLKIN2       (1'b0),
        .CLKINSEL     (1'b1),
        .DADDR        (7'h0),
        .DCLK         (1'b0),
        .DEN          (1'b0),
        .DI           (16'h0),
        .DO           (),
        .DRDY         (),
        .DWE          (1'b0),
        .PSCLK        (1'b0),
        .PSDONE       (),
        .PSEN         (1'b0),
        .PSINCDEC     (1'b0),
        .PWRDWN       (1'b0),
        .RST          (~sys_rst_n)
    );
    
    BUFG u_bufg_core_clk (
        .O (core_clk),
        .I (mmcm_clk_out0)
    );
    
    `else
    
    // Simulation bypass
    assign core_clk   = sys_clk;
    assign clk_locked = 1'b1;
    
    `endif
    
    //=========================================================================
    // Reset Synchronization
    //=========================================================================
    
    always_ff @(posedge core_clk or negedge sys_rst_n) begin
        if (~sys_rst_n) begin
            rst_sync_reg <= 4'b0;
        end else if (clk_locked) begin
            rst_sync_reg <= {rst_sync_reg[2:0], 1'b1};
        end else begin
            rst_sync_reg <= 4'b0;
        end
    end
    
    assign core_rst_n = rst_sync_reg[3];
    
    //=========================================================================
    // Button Debouncing
    //=========================================================================
    
    always_ff @(posedge core_clk or negedge core_rst_n) begin
        if (~core_rst_n) begin
            debounce_cnt   <= '0;
            btn_start_db   <= 1'b0;
            btn_start_prev <= 1'b0;
        end else begin
            btn_start_prev <= btn_start_db;
            
            if (debounce_cnt == '1) begin
                btn_start_db <= btn_start;
                debounce_cnt <= '0;
            end else begin
                debounce_cnt <= debounce_cnt + 1;
            end
        end
    end
    
    assign btn_start_pulse = btn_start_db && ~btn_start_prev;
    
    //=========================================================================
    // Simple Command Interface (Button + Switch based)
    //=========================================================================
    
    // For demo: use switches to select pre-loaded program, button to start
    
    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_LOAD_PROG,
        STATE_RUNNING,
        STATE_DONE
    } ctrl_state_e;
    
    ctrl_state_e ctrl_state;
    logic [15:0] load_cnt;
    
    always_ff @(posedge core_clk or negedge core_rst_n) begin
        if (~core_rst_n) begin
            ctrl_state     <= STATE_IDLE;
            cmd_valid      <= 1'b0;
            cmd_opcode     <= 4'h1;  // LAUNCH_KERNEL
            cmd_pc         <= '0;
            cmd_grid_dim_x <= 32'd1;
            cmd_grid_dim_y <= 32'd1;
            cmd_grid_dim_z <= 32'd1;
            cmd_block_dim_x <= 16'd8;  // One warp
            cmd_block_dim_y <= 16'd1;
            cmd_block_dim_z <= 16'd1;
            load_cnt       <= '0;
        end else begin
            case (ctrl_state)
                STATE_IDLE: begin
                    cmd_valid <= 1'b0;
                    if (btn_start_pulse && ~gpu_busy) begin
                        // Select program based on switches
                        case (sw[1:0])
                            2'b00: cmd_pc <= 64'h0000;  // Program 0
                            2'b01: cmd_pc <= 64'h0400;  // Program 1
                            2'b10: cmd_pc <= 64'h0800;  // Program 2
                            2'b11: cmd_pc <= 64'h0C00;  // Program 3
                        endcase
                        ctrl_state <= STATE_LOAD_PROG;
                    end
                end
                
                STATE_LOAD_PROG: begin
                    // Small delay for setup
                    if (load_cnt == 16'hFFFF) begin
                        cmd_valid  <= 1'b1;
                        ctrl_state <= STATE_RUNNING;
                    end else begin
                        load_cnt <= load_cnt + 1;
                    end
                end
                
                STATE_RUNNING: begin
                    if (cmd_ready) begin
                        cmd_valid <= 1'b0;
                    end
                    
                    if (gpu_done) begin
                        ctrl_state <= STATE_DONE;
                    end
                end
                
                STATE_DONE: begin
                    if (btn_start_pulse) begin
                        ctrl_state <= STATE_IDLE;
                        load_cnt   <= '0;
                    end
                end
                
                default: ctrl_state <= STATE_IDLE;
            endcase
        end
    end
    
    //=========================================================================
    // On-Chip Memory (Program + Data BRAM)
    //=========================================================================
    
    // Program memory (read-only during execution)
    logic [31:0] prog_mem [0:PROG_MEM_SIZE/4-1];
    logic [31:0] prog_data_out;
    logic [12:0] prog_addr;
    
    // Initialize with test programs (would be loaded via UART in practice)
    initial begin
        // Simple test program at address 0x0000
        prog_mem[0] = 32'h00000000;  // NOP
        prog_mem[1] = 32'h00000000;  // NOP
        // ... initialization would continue
    end
    
    always_ff @(posedge core_clk) begin
        prog_data_out <= prog_mem[prog_addr];
    end
    
    // Data memory (read/write)
    logic [63:0] data_mem [0:DATA_MEM_SIZE/8-1];
    logic [63:0] data_read;
    
    always_ff @(posedge core_clk) begin
        if (mem_req_valid && mem_req_ready) begin
            if (mem_req_write) begin
                // Byte-level write enable
                for (int i = 0; i < 8; i++) begin
                    if (mem_req_wmask[i])
                        data_mem[mem_req_addr[15:3]][i*8 +: 8] <= mem_req_wdata[i*8 +: 8];
                end
            end
            data_read <= data_mem[mem_req_addr[15:3]];
        end
    end
    
    assign mem_req_ready  = 1'b1;  // BRAM always ready
    assign mem_resp_valid = 1'b1;  // Single-cycle response
    assign mem_resp_data  = data_read;
    
    //=========================================================================
    // GPU Top Instance (Reduced Configuration)
    //=========================================================================
    
    // Note: For Artix-7, we instantiate a reduced configuration
    // This may require creating a gpu_top_lite module or using generate
    // to disable features like DP FPU
    
    gpu_top #(
        .NUM_CORES       (NUM_CORES),       // 1 core
        .WARPS_PER_CORE  (WARPS_PER_CORE),  // 2 warps
        .ICACHE_SIZE     (ICACHE_SIZE),     // 2KB
        .SHARED_MEM_SIZE (SHARED_MEM_SIZE)  // 4KB
    ) u_gpu_top (
        .clk             (core_clk),
        .rst_n           (core_rst_n),
        
        // Command interface
        .cmd_valid       (cmd_valid),
        .cmd_ready       (cmd_ready),
        .cmd_opcode      (cmd_opcode),
        .cmd_pc          (cmd_pc),
        .cmd_grid_dim_x  (cmd_grid_dim_x),
        .cmd_grid_dim_y  (cmd_grid_dim_y),
        .cmd_grid_dim_z  (cmd_grid_dim_z),
        .cmd_block_dim_x (cmd_block_dim_x),
        .cmd_block_dim_y (cmd_block_dim_y),
        .cmd_block_dim_z (cmd_block_dim_z),
        
        // Simplified memory interface (directly to BRAM, no AXI)
        // In practice, would need an adapter or modify gpu_top
        .axi_arvalid     (),
        .axi_arready     (1'b1),
        .axi_araddr      (),
        .axi_arlen       (),
        .axi_arsize      (),
        .axi_arburst     (),
        .axi_arid        (),
        
        .axi_rvalid      (mem_resp_valid),
        .axi_rready      (),
        .axi_rdata       ({448'b0, mem_resp_data}),  // 64-bit in 512-bit field
        .axi_rresp       (2'b00),
        .axi_rlast       (1'b1),
        .axi_rid         (4'b0),
        
        .axi_awvalid     (),
        .axi_awready     (1'b1),
        .axi_awaddr      (),
        .axi_awlen       (),
        .axi_awsize      (),
        .axi_awburst     (),
        .axi_awid        (),
        
        .axi_wvalid      (),
        .axi_wready      (1'b1),
        .axi_wdata       (),
        .axi_wstrb       (),
        .axi_wlast       (),
        
        .axi_bvalid      (1'b1),
        .axi_bready      (),
        .axi_bresp       (2'b00),
        .axi_bid         (4'b0),
        
        // Status
        .gpu_busy        (gpu_busy),
        .gpu_done        (gpu_done),
        .cores_active    (cores_active),
        .perf_cycle_count(perf_cycle_count),
        .perf_instr_count(perf_instr_count)
    );
    
    //=========================================================================
    // LED Status Display
    //=========================================================================
    
    logic [26:0] heartbeat_cnt;
    logic        led_done_latch;
    
    always_ff @(posedge core_clk or negedge core_rst_n) begin
        if (~core_rst_n) begin
            heartbeat_cnt  <= '0;
            led_done_latch <= 1'b0;
        end else begin
            heartbeat_cnt <= heartbeat_cnt + 1;
            
            if (gpu_done)
                led_done_latch <= 1'b1;
            else if (btn_start_pulse)
                led_done_latch <= 1'b0;
        end
    end
    
    assign led[0] = clk_locked;
    assign led[1] = gpu_busy;
    assign led[2] = led_done_latch;
    assign led[3] = heartbeat_cnt[26];  // ~0.37 Hz at 50 MHz
    assign led[4] = (ctrl_state == STATE_IDLE);
    assign led[5] = (ctrl_state == STATE_RUNNING);
    assign led[6] = cores_active[0];
    assign led[7] = sw[3];  // Echo switch 3
    
    //=========================================================================
    // 7-Segment Display (Performance Counter Display)
    //=========================================================================
    
    generate
        if (ENABLE_7SEG) begin : gen_7seg
            
            // Select what to display
            always_comb begin
                case (sw[3:2])
                    2'b00: display_value = perf_cycle_count;
                    2'b01: display_value = perf_instr_count;
                    2'b10: display_value = {16'b0, cmd_pc[15:0]};
                    2'b11: display_value = {24'b0, 4'b0, ctrl_state, gpu_done, gpu_busy};
                endcase
            end
            
            // Refresh counter for multiplexing
            always_ff @(posedge core_clk or negedge core_rst_n) begin
                if (~core_rst_n) begin
                    refresh_cnt <= '0;
                end else begin
                    refresh_cnt <= refresh_cnt + 1;
                end
            end
            
            assign digit_sel = refresh_cnt[19:17];
            
            // Digit selection (active-low anodes)
            always_comb begin
                seg_an = 8'hFF;  // All off
                seg_an[digit_sel] = 1'b0;  // Enable selected digit
            end
            
            // Hex to 7-segment decoder
            logic [3:0] hex_digit;
            
            always_comb begin
                case (digit_sel)
                    3'd0: hex_digit = display_value[3:0];
                    3'd1: hex_digit = display_value[7:4];
                    3'd2: hex_digit = display_value[11:8];
                    3'd3: hex_digit = display_value[15:12];
                    3'd4: hex_digit = display_value[19:16];
                    3'd5: hex_digit = display_value[23:20];
                    3'd6: hex_digit = display_value[27:24];
                    3'd7: hex_digit = display_value[31:28];
                endcase
            end
            
            // 7-segment encoding (active-low: gfedcba, dp)
            always_comb begin
                case (hex_digit)
                    4'h0: seg_ca = 8'b11000000;
                    4'h1: seg_ca = 8'b11111001;
                    4'h2: seg_ca = 8'b10100100;
                    4'h3: seg_ca = 8'b10110000;
                    4'h4: seg_ca = 8'b10011001;
                    4'h5: seg_ca = 8'b10010010;
                    4'h6: seg_ca = 8'b10000010;
                    4'h7: seg_ca = 8'b11111000;
                    4'h8: seg_ca = 8'b10000000;
                    4'h9: seg_ca = 8'b10010000;
                    4'hA: seg_ca = 8'b10001000;
                    4'hB: seg_ca = 8'b10000011;
                    4'hC: seg_ca = 8'b11000110;
                    4'hD: seg_ca = 8'b10100001;
                    4'hE: seg_ca = 8'b10000110;
                    4'hF: seg_ca = 8'b10001110;
                endcase
            end
            
        end else begin : no_7seg
            assign seg_an = 8'hFF;
            assign seg_ca = 8'hFF;
        end
    endgenerate
    
    //=========================================================================
    // UART Interface (Simple TX for debug output)
    //=========================================================================
    
    generate
        if (ENABLE_UART) begin : gen_uart
            // Simple UART TX for status output
            // Baud rate: 115200, 50 MHz clock
            localparam BAUD_DIV = 50_000_000 / 115200;
            
            logic [15:0] uart_div_cnt;
            logic [3:0]  uart_bit_cnt;
            logic [9:0]  uart_shift_reg;
            logic        uart_busy;
            
            always_ff @(posedge core_clk or negedge core_rst_n) begin
                if (~core_rst_n) begin
                    uart_div_cnt   <= '0;
                    uart_bit_cnt   <= '0;
                    uart_shift_reg <= 10'h3FF;
                    uart_busy      <= 1'b0;
                    uart_tx        <= 1'b1;
                end else begin
                    if (~uart_busy && uart_tx_valid) begin
                        // Start transmission
                        uart_shift_reg <= {1'b1, uart_tx_data, 1'b0};  // Stop, data, start
                        uart_bit_cnt   <= 4'd10;
                        uart_busy      <= 1'b1;
                        uart_div_cnt   <= '0;
                    end else if (uart_busy) begin
                        if (uart_div_cnt == BAUD_DIV - 1) begin
                            uart_div_cnt   <= '0;
                            uart_tx        <= uart_shift_reg[0];
                            uart_shift_reg <= {1'b1, uart_shift_reg[9:1]};
                            uart_bit_cnt   <= uart_bit_cnt - 1;
                            if (uart_bit_cnt == 1)
                                uart_busy <= 1'b0;
                        end else begin
                            uart_div_cnt <= uart_div_cnt + 1;
                        end
                    end
                end
            end
            
            assign uart_tx_ready = ~uart_busy;
            
            // Auto-send status on completion
            logic [3:0] tx_state;
            logic [7:0] tx_msg [0:15];
            logic [3:0] tx_idx;
            
            initial begin
                // "DONE\r\n"
                tx_msg[0] = "D";
                tx_msg[1] = "O";
                tx_msg[2] = "N";
                tx_msg[3] = "E";
                tx_msg[4] = 8'h0D;
                tx_msg[5] = 8'h0A;
            end
            
            always_ff @(posedge core_clk or negedge core_rst_n) begin
                if (~core_rst_n) begin
                    tx_state      <= '0;
                    tx_idx        <= '0;
                    uart_tx_valid <= 1'b0;
                    uart_tx_data  <= '0;
                end else begin
                    case (tx_state)
                        0: begin
                            uart_tx_valid <= 1'b0;
                            if (gpu_done && ~led_done_latch) begin
                                tx_state <= 1;
                                tx_idx   <= 0;
                            end
                        end
                        1: begin
                            if (uart_tx_ready) begin
                                uart_tx_data  <= tx_msg[tx_idx];
                                uart_tx_valid <= 1'b1;
                                tx_state      <= 2;
                            end
                        end
                        2: begin
                            uart_tx_valid <= 1'b0;
                            if (tx_idx == 5) begin
                                tx_state <= 0;
                            end else begin
                                tx_idx   <= tx_idx + 1;
                                tx_state <= 1;
                            end
                        end
                        default: tx_state <= 0;
                    endcase
                end
            end
            
        end else begin : no_uart
            assign uart_tx = 1'b1;
        end
    endgenerate

endmodule
