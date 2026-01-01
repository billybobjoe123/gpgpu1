#=============================================================================
# GPGPU-1 Pin Constraints for Digilent Nexys A7-100T
#=============================================================================
# File:        gpgpu_pins_nexys_a7.xdc
# Target:      Xilinx Artix-7 XC7A100TCSG324-1
# Board:       Digilent Nexys A7-100T
# Date:        January 1, 2026
#=============================================================================

#-----------------------------------------------------------------------------
# Clock Input (100 MHz oscillator)
#-----------------------------------------------------------------------------

# Single-ended 100 MHz clock (active-low active)
set_property PACKAGE_PIN E3 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]

# Create 100 MHz clock
create_clock -period 10.000 -name sys_clk [get_ports sys_clk]

#-----------------------------------------------------------------------------
# Reset Button (Active-Low CPU_RESETN)
#-----------------------------------------------------------------------------

set_property PACKAGE_PIN C12 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]

#-----------------------------------------------------------------------------
# User LEDs (accent active-high)
#-----------------------------------------------------------------------------

# LED[0] - Clock locked
set_property PACKAGE_PIN H17 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]

# LED[1] - GPU busy
set_property PACKAGE_PIN K15 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]

# LED[2] - GPU done (latched)
set_property PACKAGE_PIN J13 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]

# LED[3] - Heartbeat
set_property PACKAGE_PIN N14 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

# Additional status LEDs
set_property PACKAGE_PIN R18 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[4]}]

set_property PACKAGE_PIN V17 [get_ports {led[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[5]}]

set_property PACKAGE_PIN U17 [get_ports {led[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[6]}]

set_property PACKAGE_PIN U16 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[7]}]

#-----------------------------------------------------------------------------
# User Push Buttons
#-----------------------------------------------------------------------------

# BTNC - Center button (optional kernel trigger)
set_property PACKAGE_PIN N17 [get_ports btn_start]
set_property IOSTANDARD LVCMOS33 [get_ports btn_start]

# BTNU - Up button (optional)  
set_property PACKAGE_PIN M18 [get_ports btn_up]
set_property IOSTANDARD LVCMOS33 [get_ports btn_up]

# BTND - Down button (optional)
set_property PACKAGE_PIN P18 [get_ports btn_down]
set_property IOSTANDARD LVCMOS33 [get_ports btn_down]

#-----------------------------------------------------------------------------
# Switches (for mode selection)
#-----------------------------------------------------------------------------

set_property PACKAGE_PIN J15 [get_ports {sw[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[0]}]

set_property PACKAGE_PIN L16 [get_ports {sw[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[1]}]

set_property PACKAGE_PIN M13 [get_ports {sw[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[2]}]

set_property PACKAGE_PIN R15 [get_ports {sw[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[3]}]

#-----------------------------------------------------------------------------
# 7-Segment Display (Active-Low anodes and cathodes)
#-----------------------------------------------------------------------------

# Anodes
set_property PACKAGE_PIN J17 [get_ports {seg_an[0]}]
set_property PACKAGE_PIN J18 [get_ports {seg_an[1]}]
set_property PACKAGE_PIN T9  [get_ports {seg_an[2]}]
set_property PACKAGE_PIN J14 [get_ports {seg_an[3]}]
set_property PACKAGE_PIN P14 [get_ports {seg_an[4]}]
set_property PACKAGE_PIN T14 [get_ports {seg_an[5]}]
set_property PACKAGE_PIN K2  [get_ports {seg_an[6]}]
set_property PACKAGE_PIN U13 [get_ports {seg_an[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg_an[*]}]

# Cathodes (active-low: CA, CB, CC, CD, CE, CF, CG, DP)
set_property PACKAGE_PIN T10 [get_ports {seg_ca[0]}]
set_property PACKAGE_PIN R10 [get_ports {seg_ca[1]}]
set_property PACKAGE_PIN K16 [get_ports {seg_ca[2]}]
set_property PACKAGE_PIN K13 [get_ports {seg_ca[3]}]
set_property PACKAGE_PIN P15 [get_ports {seg_ca[4]}]
set_property PACKAGE_PIN T11 [get_ports {seg_ca[5]}]
set_property PACKAGE_PIN L18 [get_ports {seg_ca[6]}]
set_property PACKAGE_PIN H15 [get_ports {seg_ca[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg_ca[*]}]

#-----------------------------------------------------------------------------
# USB-UART Bridge
#-----------------------------------------------------------------------------

set_property PACKAGE_PIN C4  [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

set_property PACKAGE_PIN D4  [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

#-----------------------------------------------------------------------------
# Cellular RAM / PSRAM (16-bit, 8MB) - Alternative to DDR2
#-----------------------------------------------------------------------------

# Address bus [22:0]
set_property PACKAGE_PIN J18 [get_ports {cram_a[0]}]
set_property PACKAGE_PIN H17 [get_ports {cram_a[1]}]
# ... (full address mapping would continue)

# Data bus [15:0]
set_property PACKAGE_PIN R12 [get_ports {cram_dq[0]}]
set_property PACKAGE_PIN T11 [get_ports {cram_dq[1]}]
# ... (full data mapping would continue)

# Control signals
# set_property PACKAGE_PIN T15 [get_ports cram_ce_n]
# set_property PACKAGE_PIN L13 [get_ports cram_oe_n]
# set_property PACKAGE_PIN M16 [get_ports cram_we_n]

#-----------------------------------------------------------------------------
# DDR2 Memory Interface (optional - requires MIG IP)
#-----------------------------------------------------------------------------

# DDR2 pins are typically auto-generated by MIG IP Core
# Reference: Nexys A7 Reference Manual, DDR2 section

#-----------------------------------------------------------------------------
# Configuration Settings
#-----------------------------------------------------------------------------

# Configuration voltage
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# Bitstream options
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

#-----------------------------------------------------------------------------
# I/O Constraints
#-----------------------------------------------------------------------------

# Default LVCMOS33 for all I/Os on 3.3V banks
set_property IOSTANDARD LVCMOS33 [get_ports -filter {IOSTANDARD == ""}]
