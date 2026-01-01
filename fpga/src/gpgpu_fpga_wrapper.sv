//=============================================================================
// GPGPU-1 FPGA Wrapper
//=============================================================================
// File:        gpgpu_fpga_wrapper.sv
// Description: Top-level FPGA wrapper for the GPGPU-1 design
//              - Clock management (MMCM/PLL)
//              - Reset synchronization
//              - AXI4 interface for Zynq PS connection
//              - Debug LED outputs
//              - Optional ILA debug core instantiation
// Target:      Xilinx Zynq Ultrascale+ (ZCU104)
// Version:     1.0
//=============================================================================

`include "gpgpu_defines.svh"

module gpgpu_fpga_wrapper
    import gpgpu_pkg::*;
#(
    // Core configuration (reduced for FPGA)
    parameter int NUM_CORES       = 2,
    parameter int WARPS_PER_CORE  = 4,
    parameter int ICACHE_SIZE     = 4096,
    parameter int SHARED_MEM_SIZE = 8192,
    
    // Clock configuration
    parameter int INPUT_CLK_FREQ  = 100,  // Input clock frequency (MHz)
    parameter int CORE_CLK_FREQ   = 100,  // GPU core clock frequency (MHz)
    
    // Debug features
    parameter bit ENABLE_ILA      = 0,    // Enable Integrated Logic Analyzer
    parameter bit ENABLE_VIO      = 0     // Enable Virtual I/O
)(
    //=========================================================================
    // Board-Level Clocks and Reset
    //=========================================================================
    
    input  logic        sys_clk_p,        // Differential clock positive
    input  logic        sys_clk_n,        // Differential clock negative
    // Alternative single-ended clock input
    input  logic        sys_clk,          // Single-ended clock (active if diff not used)
    input  logic        sys_rst_n,        // Active-low system reset
    
    //=========================================================================
    // AXI4 Master Interface (to DDR via Zynq PS or MIG)
    //=========================================================================
    
    // Read Address Channel
    output logic                    m_axi_arvalid,
    input  logic                    m_axi_arready,
    output logic [39:0]             m_axi_araddr,     // 40-bit for Zynq
    output logic [7:0]              m_axi_arlen,
    output logic [2:0]              m_axi_arsize,
    output logic [1:0]              m_axi_arburst,
    output logic [3:0]              m_axi_arid,
    output logic [3:0]              m_axi_arcache,
    output logic [2:0]              m_axi_arprot,
    output logic                    m_axi_arlock,
    output logic [3:0]              m_axi_arqos,
    
    // Read Data Channel
    input  logic                    m_axi_rvalid,
    output logic                    m_axi_rready,
    input  logic [511:0]            m_axi_rdata,
    input  logic [1:0]              m_axi_rresp,
    input  logic                    m_axi_rlast,
    input  logic [3:0]              m_axi_rid,
    
    // Write Address Channel
    output logic                    m_axi_awvalid,
    input  logic                    m_axi_awready,
    output logic [39:0]             m_axi_awaddr,
    output logic [7:0]              m_axi_awlen,
    output logic [2:0]              m_axi_awsize,
    output logic [1:0]              m_axi_awburst,
    output logic [3:0]              m_axi_awid,
    output logic [3:0]              m_axi_awcache,
    output logic [2:0]              m_axi_awprot,
    output logic                    m_axi_awlock,
    output logic [3:0]              m_axi_awqos,
    
    // Write Data Channel
    output logic                    m_axi_wvalid,
    input  logic                    m_axi_wready,
    output logic [511:0]            m_axi_wdata,
    output logic [63:0]             m_axi_wstrb,
    output logic                    m_axi_wlast,
    
    // Write Response Channel
    input  logic                    m_axi_bvalid,
    output logic                    m_axi_bready,
    input  logic [1:0]              m_axi_bresp,
    input  logic [3:0]              m_axi_bid,
    
    //=========================================================================
    // AXI4-Lite Slave Interface (Control Registers from Host)
    //=========================================================================
    
    // Write Address Channel
    input  logic                    s_axi_awvalid,
    output logic                    s_axi_awready,
    input  logic [11:0]             s_axi_awaddr,
    input  logic [2:0]              s_axi_awprot,
    
    // Write Data Channel
    input  logic                    s_axi_wvalid,
    output logic                    s_axi_wready,
    input  logic [31:0]             s_axi_wdata,
    input  logic [3:0]              s_axi_wstrb,
    
    // Write Response Channel
    output logic                    s_axi_bvalid,
    input  logic                    s_axi_bready,
    output logic [1:0]              s_axi_bresp,
    
    // Read Address Channel
    input  logic                    s_axi_arvalid,
    output logic                    s_axi_arready,
    input  logic [11:0]             s_axi_araddr,
    input  logic [2:0]              s_axi_arprot,
    
    // Read Data Channel
    output logic                    s_axi_rvalid,
    input  logic                    s_axi_rready,
    output logic [31:0]             s_axi_rdata,
    output logic [1:0]              s_axi_rresp,
    
    //=========================================================================
    // Interrupt Output
    //=========================================================================
    
    output logic                    irq_done,         // Kernel completion interrupt
    
    //=========================================================================
    // Debug LEDs
    //=========================================================================
    
    output logic [3:0]              led               // Status LEDs
);

    //=========================================================================
    // Local Signals
    //=========================================================================
    
    // Clock and reset
    logic core_clk;
    logic core_rst_n;
    logic clk_locked;
    logic rst_sync_n;
    
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
    
    // Internal AXI signals (32-bit address from gpu_top)
    logic [ADDR_WIDTH-1:0]   int_axi_araddr;
    logic [ADDR_WIDTH-1:0]   int_axi_awaddr;
    
    //=========================================================================
    // Clock Management (MMCM)
    //=========================================================================
    
    // For synthesis: use Xilinx MMCM primitive
    // For simulation: bypass clock management
    
    `ifdef SYNTHESIS
    
    // Differential clock buffer
    logic sys_clk_buf;
    
    IBUFDS #(
        .DIFF_TERM    ("FALSE"),
        .IBUF_LOW_PWR ("FALSE"),
        .IOSTANDARD   ("LVDS")
    ) u_ibufds_clk (
        .O  (sys_clk_buf),
        .I  (sys_clk_p),
        .IB (sys_clk_n)
    );
    
    // MMCM for clock generation
    logic mmcm_clk_fb;
    logic mmcm_clk_out0;
    
    MMCME4_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKFBOUT_MULT_F      (10.0),         // VCO = 1000 MHz
        .CLKFBOUT_PHASE       (0.0),
        .CLKIN1_PERIOD        (10.0),         // 100 MHz input
        .CLKOUT0_DIVIDE_F     (10.0),         // 100 MHz output
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
        .CLKIN1       (sys_clk_buf),
        .CLKIN2       (1'b0),
        .CLKINSEL     (1'b1),
        .DADDR        (7'h0),
        .DCLK         (1'b0),
        .DEN          (1'b0),
        .DI           (16'h0),
        .DO           (),
        .DRDY         (),
        .DWE          (1'b0),
        .CDDCDONE     (),
        .CDDCREQ      (1'b0),
        .PSCLK        (1'b0),
        .PSDONE       (),
        .PSEN         (1'b0),
        .PSINCDEC     (1'b0),
        .PWRDWN       (1'b0),
        .RST          (~sys_rst_n)
    );
    
    // Output clock buffer
    BUFG u_bufg_core_clk (
        .O (core_clk),
        .I (mmcm_clk_out0)
    );
    
    `else
    
    // Simulation: use single-ended clock directly
    assign core_clk   = sys_clk;
    assign clk_locked = 1'b1;
    
    `endif
    
    //=========================================================================
    // Reset Synchronization
    //=========================================================================
    
    // Synchronize external reset to core clock domain
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
    // AXI4-Lite Control Register Interface
    //=========================================================================
    
    // Register map:
    // 0x000: Control register (RW)
    //        [0]   : Start kernel
    //        [1]   : Soft reset
    //        [31:8]: Reserved
    // 0x004: Status register (RO)
    //        [0]   : GPU busy
    //        [1]   : GPU done
    //        [7:2] : Active cores
    //        [31:8]: Reserved
    // 0x008: PC start address low (RW)
    // 0x00C: PC start address high (RW)
    // 0x010: Grid dimension X (RW)
    // 0x014: Grid dimension Y (RW)
    // 0x018: Grid dimension Z (RW)
    // 0x01C: Block dimension X (RW) [15:0]
    // 0x020: Block dimension Y (RW) [15:0]
    // 0x024: Block dimension Z (RW) [15:0]
    // 0x028: Performance counter - cycles (RO)
    // 0x02C: Performance counter - instructions (RO)
    // 0x030: Command opcode (RW) [3:0]
    
    // Control registers
    logic [31:0] ctrl_reg;
    logic [31:0] pc_low_reg;
    logic [31:0] pc_high_reg;
    logic [31:0] grid_x_reg;
    logic [31:0] grid_y_reg;
    logic [31:0] grid_z_reg;
    logic [31:0] block_x_reg;
    logic [31:0] block_y_reg;
    logic [31:0] block_z_reg;
    logic [31:0] cmd_opcode_reg;
    
    // AXI-Lite state machine
    typedef enum logic [1:0] {
        AXI_IDLE,
        AXI_WRITE,
        AXI_READ
    } axi_state_e;
    
    axi_state_e axi_wr_state, axi_rd_state;
    logic [11:0] axi_wr_addr, axi_rd_addr;
    
    // Write channel state machine
    always_ff @(posedge core_clk or negedge core_rst_n) begin
        if (~core_rst_n) begin
            axi_wr_state   <= AXI_IDLE;
            axi_wr_addr    <= '0;
            s_axi_awready  <= 1'b0;
            s_axi_wready   <= 1'b0;
            s_axi_bvalid   <= 1'b0;
            s_axi_bresp    <= 2'b00;
            ctrl_reg       <= '0;
            pc_low_reg     <= '0;
            pc_high_reg    <= '0;
            grid_x_reg     <= 32'd1;
            grid_y_reg     <= 32'd1;
            grid_z_reg     <= 32'd1;
            block_x_reg    <= 32'd32;
            block_y_reg    <= 32'd1;
            block_z_reg    <= 32'd1;
            cmd_opcode_reg <= '0;
        end else begin
            // Default: deassert ready signals
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            
            // Clear start bit after one cycle
            if (ctrl_reg[0] && cmd_ready) begin
                ctrl_reg[0] <= 1'b0;
            end
            
            case (axi_wr_state)
                AXI_IDLE: begin
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        // Both address and data valid
                        s_axi_awready <= 1'b1;
                        s_axi_wready  <= 1'b1;
                        axi_wr_addr   <= s_axi_awaddr;
                        axi_wr_state  <= AXI_WRITE;
                    end else if (s_axi_awvalid) begin
                        s_axi_awready <= 1'b1;
                        axi_wr_addr   <= s_axi_awaddr;
                    end else if (s_axi_wvalid && axi_wr_addr != '0) begin
                        s_axi_wready <= 1'b1;
                        axi_wr_state <= AXI_WRITE;
                    end
                end
                
                AXI_WRITE: begin
                    // Write data to register
                    case (axi_wr_addr[7:0])
                        8'h00: ctrl_reg       <= s_axi_wdata;
                        8'h08: pc_low_reg     <= s_axi_wdata;
                        8'h0C: pc_high_reg    <= s_axi_wdata;
                        8'h10: grid_x_reg     <= s_axi_wdata;
                        8'h14: grid_y_reg     <= s_axi_wdata;
                        8'h18: grid_z_reg     <= s_axi_wdata;
                        8'h1C: block_x_reg    <= s_axi_wdata;
                        8'h20: block_y_reg    <= s_axi_wdata;
                        8'h24: block_z_reg    <= s_axi_wdata;
                        8'h30: cmd_opcode_reg <= s_axi_wdata;
                        default: ; // Ignore writes to other addresses
                    endcase
                    
                    s_axi_bvalid <= 1'b1;
                    s_axi_bresp  <= 2'b00;  // OKAY
                    axi_wr_state <= AXI_IDLE;
                    axi_wr_addr  <= '0;
                end
                
                default: axi_wr_state <= AXI_IDLE;
            endcase
            
            // Handle write response handshake
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end
    
    // Read channel state machine
    always_ff @(posedge core_clk or negedge core_rst_n) begin
        if (~core_rst_n) begin
            axi_rd_state  <= AXI_IDLE;
            axi_rd_addr   <= '0;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= '0;
            s_axi_rresp   <= 2'b00;
        end else begin
            s_axi_arready <= 1'b0;
            
            case (axi_rd_state)
                AXI_IDLE: begin
                    if (s_axi_arvalid) begin
                        s_axi_arready <= 1'b1;
                        axi_rd_addr   <= s_axi_araddr;
                        axi_rd_state  <= AXI_READ;
                    end
                end
                
                AXI_READ: begin
                    s_axi_rvalid <= 1'b1;
                    s_axi_rresp  <= 2'b00;
                    
                    case (axi_rd_addr[7:0])
                        8'h00: s_axi_rdata <= ctrl_reg;
                        8'h04: s_axi_rdata <= {24'b0, cores_active, 4'b0, gpu_done, gpu_busy};
                        8'h08: s_axi_rdata <= pc_low_reg;
                        8'h0C: s_axi_rdata <= pc_high_reg;
                        8'h10: s_axi_rdata <= grid_x_reg;
                        8'h14: s_axi_rdata <= grid_y_reg;
                        8'h18: s_axi_rdata <= grid_z_reg;
                        8'h1C: s_axi_rdata <= block_x_reg;
                        8'h20: s_axi_rdata <= block_y_reg;
                        8'h24: s_axi_rdata <= block_z_reg;
                        8'h28: s_axi_rdata <= perf_cycle_count;
                        8'h2C: s_axi_rdata <= perf_instr_count;
                        8'h30: s_axi_rdata <= cmd_opcode_reg;
                        default: s_axi_rdata <= 32'hDEADBEEF;
                    endcase
                    
                    axi_rd_state <= AXI_IDLE;
                end
                
                default: axi_rd_state <= AXI_IDLE;
            endcase
            
            // Handle read response handshake
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end
    
    // Generate command interface signals
    assign cmd_valid      = ctrl_reg[0];
    assign cmd_opcode     = cmd_opcode_reg[3:0];
    assign cmd_pc         = pc_low_reg[ADDR_WIDTH-1:0];
    assign cmd_grid_dim_x = grid_x_reg;
    assign cmd_grid_dim_y = grid_y_reg;
    assign cmd_grid_dim_z = grid_z_reg;
    assign cmd_block_dim_x = block_x_reg[15:0];
    assign cmd_block_dim_y = block_y_reg[15:0];
    assign cmd_block_dim_z = block_z_reg[15:0];
    
    //=========================================================================
    // GPU Top Instance
    //=========================================================================
    
    gpu_top #(
        .NUM_CORES       (NUM_CORES),
        .WARPS_PER_CORE  (WARPS_PER_CORE),
        .ICACHE_SIZE     (ICACHE_SIZE),
        .SHARED_MEM_SIZE (SHARED_MEM_SIZE)
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
        
        // AXI4 Memory interface
        .axi_arvalid     (m_axi_arvalid),
        .axi_arready     (m_axi_arready),
        .axi_araddr      (int_axi_araddr),
        .axi_arlen       (m_axi_arlen),
        .axi_arsize      (m_axi_arsize),
        .axi_arburst     (m_axi_arburst),
        .axi_arid        (m_axi_arid),
        
        .axi_rvalid      (m_axi_rvalid),
        .axi_rready      (m_axi_rready),
        .axi_rdata       (m_axi_rdata),
        .axi_rresp       (m_axi_rresp),
        .axi_rlast       (m_axi_rlast),
        .axi_rid         (m_axi_rid),
        
        .axi_awvalid     (m_axi_awvalid),
        .axi_awready     (m_axi_awready),
        .axi_awaddr      (int_axi_awaddr),
        .axi_awlen       (m_axi_awlen),
        .axi_awsize      (m_axi_awsize),
        .axi_awburst     (m_axi_awburst),
        .axi_awid        (m_axi_awid),
        
        .axi_wvalid      (m_axi_wvalid),
        .axi_wready      (m_axi_wready),
        .axi_wdata       (m_axi_wdata),
        .axi_wstrb       (m_axi_wstrb),
        .axi_wlast       (m_axi_wlast),
        
        .axi_bvalid      (m_axi_bvalid),
        .axi_bready      (m_axi_bready),
        .axi_bresp       (m_axi_bresp),
        .axi_bid         (m_axi_bid),
        
        // Status
        .gpu_busy        (gpu_busy),
        .gpu_done        (gpu_done),
        .cores_active    (cores_active),
        .perf_cycle_count(perf_cycle_count),
        .perf_instr_count(perf_instr_count)
    );
    
    //=========================================================================
    // Address Extension (32-bit to 40-bit for Zynq)
    //=========================================================================
    
    // Zero-extend 32-bit addresses to 40-bit
    // Could add a base address offset register for accessing different memory regions
    assign m_axi_araddr = {8'h00, int_axi_araddr};
    assign m_axi_awaddr = {8'h00, int_axi_awaddr};
    
    // Additional AXI signals
    assign m_axi_arcache = 4'b0011;  // Normal, non-cacheable, bufferable
    assign m_axi_arprot  = 3'b000;   // Unprivileged, secure, data access
    assign m_axi_arlock  = 1'b0;     // Normal access
    assign m_axi_arqos   = 4'b0000;  // No QoS
    
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awqos   = 4'b0000;
    
    //=========================================================================
    // Interrupt Generation
    //=========================================================================
    
    // Generate interrupt pulse on kernel completion
    logic gpu_done_r;
    
    always_ff @(posedge core_clk or negedge core_rst_n) begin
        if (~core_rst_n) begin
            gpu_done_r <= 1'b0;
            irq_done   <= 1'b0;
        end else begin
            gpu_done_r <= gpu_done;
            irq_done   <= gpu_done && ~gpu_done_r;  // Rising edge detect
        end
    end
    
    //=========================================================================
    // Status LEDs
    //=========================================================================
    
    // LED[0]: Clock locked
    // LED[1]: GPU busy
    // LED[2]: GPU done (latched)
    // LED[3]: Heartbeat
    
    logic [26:0] heartbeat_cnt;
    logic        led_done_latch;
    
    always_ff @(posedge core_clk or negedge core_rst_n) begin
        if (~core_rst_n) begin
            heartbeat_cnt  <= '0;
            led_done_latch <= 1'b0;
        end else begin
            heartbeat_cnt <= heartbeat_cnt + 1;
            
            // Latch done until next start
            if (gpu_done) begin
                led_done_latch <= 1'b1;
            end else if (cmd_valid && cmd_ready) begin
                led_done_latch <= 1'b0;
            end
        end
    end
    
    assign led[0] = clk_locked;
    assign led[1] = gpu_busy;
    assign led[2] = led_done_latch;
    assign led[3] = heartbeat_cnt[26];  // ~0.67 Hz at 100 MHz
    
    //=========================================================================
    // Optional Debug: ILA Core
    //=========================================================================
    
    generate
        if (ENABLE_ILA) begin : gen_ila
            // ILA instantiation would go here
            // This is typically done via IP catalog in Vivado
            // Example placeholder:
            /*
            ila_0 u_ila (
                .clk    (core_clk),
                .probe0 (cmd_valid),
                .probe1 (cmd_ready),
                .probe2 (gpu_busy),
                .probe3 (gpu_done),
                .probe4 (cores_active),
                .probe5 (m_axi_arvalid),
                .probe6 (m_axi_arready),
                .probe7 (m_axi_awvalid),
                .probe8 (m_axi_awready),
                .probe9 (perf_cycle_count),
                .probe10(perf_instr_count)
            );
            */
        end
    endgenerate

endmodule
