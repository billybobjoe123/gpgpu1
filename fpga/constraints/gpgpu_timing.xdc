#=============================================================================
# GPGPU-1 Timing Constraints (Xilinx XDC)
#=============================================================================
# File:        gpgpu_timing.xdc
# Description: Timing constraints for FPGA synthesis
# Target:      Xilinx Ultrascale+ (configurable)
# Date:        January 1, 2026
#=============================================================================

#-----------------------------------------------------------------------------
# Clock Definition
#-----------------------------------------------------------------------------

# Primary system clock - adjust period based on target FPGA
# 100 MHz = 10ns period (default, conservative)
# 200 MHz = 5ns period  (aggressive)
create_clock -period 10.000 -name sys_clk [get_ports clk]

# Memory clock (if using external DDR - typically 2x or 4x sys_clk)
# create_clock -period 2.500 -name mem_clk [get_ports mem_clk]

#-----------------------------------------------------------------------------
# Clock Uncertainty
#-----------------------------------------------------------------------------

# Account for jitter, skew, and PVT variations
set_clock_uncertainty -setup 0.200 [get_clocks sys_clk]
set_clock_uncertainty -hold  0.050 [get_clocks sys_clk]

#-----------------------------------------------------------------------------
# Input Delay Constraints
#-----------------------------------------------------------------------------

# Command interface from host (assume synchronous to sys_clk)
set_input_delay -clock sys_clk -max 2.0 [get_ports {cmd_valid cmd_opcode[*] cmd_pc[*]}]
set_input_delay -clock sys_clk -min 0.5 [get_ports {cmd_valid cmd_opcode[*] cmd_pc[*]}]

set_input_delay -clock sys_clk -max 2.0 [get_ports {cmd_grid_dim_*[*] cmd_block_dim_*[*]}]
set_input_delay -clock sys_clk -min 0.5 [get_ports {cmd_grid_dim_*[*] cmd_block_dim_*[*]}]

# AXI read data channel
set_input_delay -clock sys_clk -max 3.0 [get_ports {axi_rvalid axi_rdata[*] axi_rresp[*] axi_rlast axi_rid[*]}]
set_input_delay -clock sys_clk -min 0.5 [get_ports {axi_rvalid axi_rdata[*] axi_rresp[*] axi_rlast axi_rid[*]}]

# AXI write response channel
set_input_delay -clock sys_clk -max 3.0 [get_ports {axi_bvalid axi_bresp[*] axi_bid[*]}]
set_input_delay -clock sys_clk -min 0.5 [get_ports {axi_bvalid axi_bresp[*] axi_bid[*]}]

# AXI ready signals
set_input_delay -clock sys_clk -max 3.0 [get_ports {axi_arready axi_awready axi_wready}]
set_input_delay -clock sys_clk -min 0.5 [get_ports {axi_arready axi_awready axi_wready}]

#-----------------------------------------------------------------------------
# Output Delay Constraints
#-----------------------------------------------------------------------------

# Command interface
set_output_delay -clock sys_clk -max 2.0 [get_ports cmd_ready]
set_output_delay -clock sys_clk -min 0.5 [get_ports cmd_ready]

# Status outputs
set_output_delay -clock sys_clk -max 2.0 [get_ports {gpu_busy gpu_done cores_active[*]}]
set_output_delay -clock sys_clk -min 0.5 [get_ports {gpu_busy gpu_done cores_active[*]}]

set_output_delay -clock sys_clk -max 2.0 [get_ports {perf_cycle_count[*] perf_instr_count[*]}]
set_output_delay -clock sys_clk -min 0.5 [get_ports {perf_cycle_count[*] perf_instr_count[*]}]

# AXI read address channel
set_output_delay -clock sys_clk -max 3.0 [get_ports {axi_arvalid axi_araddr[*] axi_arlen[*] axi_arsize[*] axi_arburst[*] axi_arid[*]}]
set_output_delay -clock sys_clk -min 0.5 [get_ports {axi_arvalid axi_araddr[*] axi_arlen[*] axi_arsize[*] axi_arburst[*] axi_arid[*]}]

# AXI write address channel
set_output_delay -clock sys_clk -max 3.0 [get_ports {axi_awvalid axi_awaddr[*] axi_awlen[*] axi_awsize[*] axi_awburst[*] axi_awid[*]}]
set_output_delay -clock sys_clk -min 0.5 [get_ports {axi_awvalid axi_awaddr[*] axi_awlen[*] axi_awsize[*] axi_awburst[*] axi_awid[*]}]

# AXI write data channel
set_output_delay -clock sys_clk -max 3.0 [get_ports {axi_wvalid axi_wdata[*] axi_wstrb[*] axi_wlast}]
set_output_delay -clock sys_clk -min 0.5 [get_ports {axi_wvalid axi_wdata[*] axi_wstrb[*] axi_wlast}]

# AXI ready outputs
set_output_delay -clock sys_clk -max 3.0 [get_ports {axi_rready axi_bready}]
set_output_delay -clock sys_clk -min 0.5 [get_ports {axi_rready axi_bready}]

#-----------------------------------------------------------------------------
# False Paths
#-----------------------------------------------------------------------------

# Reset is async, but synchronized internally
set_false_path -from [get_ports rst_n]

# Configuration registers that don't change during operation
# (uncomment if needed)
# set_false_path -from [get_cells -hierarchical *config_reg*]

#-----------------------------------------------------------------------------
# Multicycle Paths
#-----------------------------------------------------------------------------

# FPU division/sqrt operations take multiple cycles
# The pipeline handles this, but we can relax timing if needed
# set_multicycle_path 2 -setup -from [get_cells -hierarchical *fpu*div*]
# set_multicycle_path 1 -hold  -from [get_cells -hierarchical *fpu*div*]

#-----------------------------------------------------------------------------
# Max Delay Constraints
#-----------------------------------------------------------------------------

# Cross-module critical paths (if identified during timing analysis)
# set_max_delay 8.0 -from [get_cells ...] -to [get_cells ...]

#-----------------------------------------------------------------------------
# Clock Groups (for multiple clock domains)
#-----------------------------------------------------------------------------

# If using separate memory clock:
# set_clock_groups -asynchronous -group [get_clocks sys_clk] -group [get_clocks mem_clk]

#-----------------------------------------------------------------------------
# Physical Constraints (Pblocks for large designs)
#-----------------------------------------------------------------------------

# Example: Constrain cores to specific regions
# create_pblock pblock_core0
# add_cells_to_pblock [get_pblocks pblock_core0] [get_cells -hierarchical gen_cores[0].*]
# resize_pblock [get_pblocks pblock_core0] -add {SLICE_X0Y0:SLICE_X50Y100}

#-----------------------------------------------------------------------------
# Debug Hub (if using ILA)
#-----------------------------------------------------------------------------

# set_property C_CLK_INPUT_FREQ_HZ 100000000 [get_debug_cores dbg_hub]
# set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]

#=============================================================================
# End of Timing Constraints
#=============================================================================
