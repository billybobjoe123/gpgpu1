#=============================================================================
# GPGPU-1 Pin Constraints (Xilinx XDC)
#=============================================================================
# File:        gpgpu_pins_zcu104.xdc
# Description: Pin assignments for Xilinx ZCU104 development board
# Target:      Zynq Ultrascale+ XCZU7EV-2FFVC1156
# Date:        January 1, 2026
#=============================================================================
#
# This file provides example pin constraints for the ZCU104 board.
# Modify for your specific target board.
#
#-----------------------------------------------------------------------------
# I/O Standards
#-----------------------------------------------------------------------------

set_property IOSTANDARD LVCMOS18 [get_ports clk]
set_property IOSTANDARD LVCMOS18 [get_ports rst_n]

#-----------------------------------------------------------------------------
# Clock Input (125 MHz on-board clock)
#-----------------------------------------------------------------------------

set_property PACKAGE_PIN F23 [get_ports clk]

#-----------------------------------------------------------------------------
# Reset Button (directly active-low)
#-----------------------------------------------------------------------------

set_property PACKAGE_PIN G13 [get_ports rst_n]

#-----------------------------------------------------------------------------
# Status LEDs
#-----------------------------------------------------------------------------

# GPU busy indicator
set_property PACKAGE_PIN D5 [get_ports gpu_busy]
set_property IOSTANDARD LVCMOS33 [get_ports gpu_busy]

# GPU done indicator  
set_property PACKAGE_PIN D6 [get_ports gpu_done]
set_property IOSTANDARD LVCMOS33 [get_ports gpu_done]

# Core active indicators (directly to LEDs if available)
# set_property PACKAGE_PIN A5 [get_ports {cores_active[0]}]
# set_property PACKAGE_PIN B5 [get_ports {cores_active[1]}]
# set_property PACKAGE_PIN B6 [get_ports {cores_active[2]}]
# set_property PACKAGE_PIN C6 [get_ports {cores_active[3]}]

#-----------------------------------------------------------------------------
# AXI Interface to PS (when using Zynq)
#-----------------------------------------------------------------------------
# Note: When connecting to Zynq PS via AXI, the pins are internal.
# These constraints are only needed for standalone FPGA implementations
# with external memory controllers.

#-----------------------------------------------------------------------------
# High-Speed I/O Banks for DDR (if using MIG)
#-----------------------------------------------------------------------------
# DDR4 interface pins would go here for standalone implementations.
# For Zynq designs, DDR is typically handled by the PS.

#-----------------------------------------------------------------------------
# Debug UART (optional, directly to PL)
#-----------------------------------------------------------------------------

# set_property PACKAGE_PIN F12 [get_ports uart_tx]
# set_property PACKAGE_PIN E12 [get_ports uart_rx]
# set_property IOSTANDARD LVCMOS18 [get_ports uart_*]

#-----------------------------------------------------------------------------
# PMOD Headers (for debug/test signals)
#-----------------------------------------------------------------------------

# PMOD0 - Performance counters output (directly accessible)
# set_property PACKAGE_PIN Y12 [get_ports {pmod0[0]}]
# set_property PACKAGE_PIN AA12 [get_ports {pmod0[1]}]
# ... etc

#-----------------------------------------------------------------------------
# Configuration
#-----------------------------------------------------------------------------

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLDOWN [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

#=============================================================================
# End of Pin Constraints (ZCU104)
#=============================================================================
