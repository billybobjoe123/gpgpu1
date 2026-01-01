#=============================================================================
# GPGPU-1 Vivado Synthesis Script
#=============================================================================
# File:        build_vivado.tcl
# Description: Non-project mode TCL script for Vivado synthesis
# Usage:       vivado -mode batch -source build_vivado.tcl
# Date:        January 1, 2026
#=============================================================================

#-----------------------------------------------------------------------------
# Configuration Parameters
#-----------------------------------------------------------------------------

# Target FPGA part (modify as needed)
# Zynq Ultrascale+ on ZCU104:
set PART "xczu7ev-ffvc1156-2-e"

# Alternative parts:
# Artix-7 on Arty:     set PART "xc7a35ticsg324-1L"
# Kintex Ultrascale:   set PART "xcku040-ffva1156-2-e"
# Alveo U50:           set PART "xcu50-fsvh2104-2-e"

# Design name
set DESIGN_NAME "gpgpu_top"

# Number of parallel jobs
set JOBS 8

# Output directory
set OUTPUT_DIR "vivado_output"

#-----------------------------------------------------------------------------
# Directory Setup
#-----------------------------------------------------------------------------

set SCRIPT_DIR [file dirname [info script]]
set ROOT_DIR [file normalize "$SCRIPT_DIR/.."]
set RTL_DIR "$ROOT_DIR/rtl"
set FPGA_DIR "$ROOT_DIR/fpga"
set CONSTRAINT_DIR "$FPGA_DIR/constraints"

file mkdir $OUTPUT_DIR
file mkdir "$OUTPUT_DIR/reports"
file mkdir "$OUTPUT_DIR/checkpoints"

#-----------------------------------------------------------------------------
# RTL Source Files
#-----------------------------------------------------------------------------

set RTL_FILES [list \
    "$RTL_DIR/common/gpgpu_defines.svh" \
    "$RTL_DIR/common/gpgpu_pkg.sv" \
    "$RTL_DIR/common/gpgpu_interfaces.sv" \
    "$RTL_DIR/core/alu.sv" \
    "$RTL_DIR/core/decoder.sv" \
    "$RTL_DIR/core/execution_unit.sv" \
    "$RTL_DIR/core/fetch_unit.sv" \
    "$RTL_DIR/core/fpu.sv" \
    "$RTL_DIR/core/fpu_dp.sv" \
    "$RTL_DIR/core/fpu_lane.sv" \
    "$RTL_DIR/core/forwarding_network.sv" \
    "$RTL_DIR/core/gpu_core.sv" \
    "$RTL_DIR/core/lsu.sv" \
    "$RTL_DIR/core/performance_counters.sv" \
    "$RTL_DIR/core/register_file.sv" \
    "$RTL_DIR/core/warp_scheduler.sv" \
    "$RTL_DIR/core/warp_shuffle.sv" \
    "$RTL_DIR/core/warp_vote.sv" \
    "$RTL_DIR/memory/l2_cache.sv" \
    "$RTL_DIR/memory/memory_controller.sv" \
    "$RTL_DIR/top/gpu_top.sv" \
    "$RTL_DIR/top/gpu_system.sv" \
]

# Optional: Add FPGA wrapper if it exists
if {[file exists "$FPGA_DIR/src/gpgpu_fpga_wrapper.sv"]} {
    lappend RTL_FILES "$FPGA_DIR/src/gpgpu_fpga_wrapper.sv"
    set TOP_MODULE "gpgpu_fpga_wrapper"
} else {
    set TOP_MODULE "gpu_top"
}

#-----------------------------------------------------------------------------
# Constraint Files
#-----------------------------------------------------------------------------

set XDC_FILES [list \
    "$CONSTRAINT_DIR/gpgpu_timing.xdc" \
]

# Add board-specific pin constraints if targeting a specific board
# Uncomment and modify as needed:
# lappend XDC_FILES "$CONSTRAINT_DIR/gpgpu_pins_zcu104.xdc"

#-----------------------------------------------------------------------------
# Synthesis Settings
#-----------------------------------------------------------------------------

puts "=============================================="
puts "GPGPU-1 Vivado Synthesis"
puts "=============================================="
puts "Part:        $PART"
puts "Top Module:  $TOP_MODULE"
puts "Output Dir:  $OUTPUT_DIR"
puts "=============================================="

# Read design sources
puts "\n[INFO] Reading RTL sources..."
foreach f $RTL_FILES {
    if {[file exists $f]} {
        puts "  Reading: $f"
        if {[string match "*.svh" $f]} {
            # Header files - just read for defines
            read_verilog -sv $f
        } else {
            read_verilog -sv $f
        }
    } else {
        puts "  [WARNING] File not found: $f"
    }
}

# Read constraints
puts "\n[INFO] Reading constraints..."
foreach f $XDC_FILES {
    if {[file exists $f]} {
        puts "  Reading: $f"
        read_xdc $f
    } else {
        puts "  [WARNING] Constraint file not found: $f"
    }
}

#-----------------------------------------------------------------------------
# Run Synthesis
#-----------------------------------------------------------------------------

puts "\n[INFO] Running synthesis..."
synth_design \
    -top $TOP_MODULE \
    -part $PART \
    -flatten_hierarchy rebuilt \
    -directive Default \
    -fsm_extraction auto \
    -resource_sharing auto \
    -no_lc

# Write checkpoint
write_checkpoint -force "$OUTPUT_DIR/checkpoints/post_synth.dcp"

# Generate synthesis reports
puts "\n[INFO] Generating synthesis reports..."
report_timing_summary -file "$OUTPUT_DIR/reports/synth_timing_summary.rpt"
report_utilization -file "$OUTPUT_DIR/reports/synth_utilization.rpt"
report_design_analysis -file "$OUTPUT_DIR/reports/synth_design_analysis.rpt"
report_clock_networks -file "$OUTPUT_DIR/reports/synth_clocks.rpt"
report_high_fanout_nets -file "$OUTPUT_DIR/reports/synth_fanout.rpt" -fanout_greater_than 200

#-----------------------------------------------------------------------------
# Optimization (opt_design)
#-----------------------------------------------------------------------------

puts "\n[INFO] Running optimization..."
opt_design -directive Explore

write_checkpoint -force "$OUTPUT_DIR/checkpoints/post_opt.dcp"

#-----------------------------------------------------------------------------
# Placement
#-----------------------------------------------------------------------------

puts "\n[INFO] Running placement..."
place_design -directive Explore

write_checkpoint -force "$OUTPUT_DIR/checkpoints/post_place.dcp"

# Post-placement reports
report_timing_summary -file "$OUTPUT_DIR/reports/place_timing_summary.rpt"
report_utilization -file "$OUTPUT_DIR/reports/place_utilization.rpt"
report_clock_utilization -file "$OUTPUT_DIR/reports/place_clock_util.rpt"

#-----------------------------------------------------------------------------
# Physical Optimization
#-----------------------------------------------------------------------------

puts "\n[INFO] Running physical optimization..."
phys_opt_design -directive AggressiveExplore

write_checkpoint -force "$OUTPUT_DIR/checkpoints/post_phys_opt.dcp"

#-----------------------------------------------------------------------------
# Routing
#-----------------------------------------------------------------------------

puts "\n[INFO] Running routing..."
route_design -directive Explore

write_checkpoint -force "$OUTPUT_DIR/checkpoints/post_route.dcp"

# Post-route reports
report_timing_summary -file "$OUTPUT_DIR/reports/route_timing_summary.rpt"
report_timing -max_paths 100 -file "$OUTPUT_DIR/reports/route_timing_detailed.rpt"
report_route_status -file "$OUTPUT_DIR/reports/route_status.rpt"
report_drc -file "$OUTPUT_DIR/reports/route_drc.rpt"
report_methodology -file "$OUTPUT_DIR/reports/route_methodology.rpt"
report_power -file "$OUTPUT_DIR/reports/route_power.rpt"

# Check for timing violations
set WNS [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set WHS [get_property SLACK [get_timing_paths -max_paths 1 -hold]]

puts "\n=============================================="
puts "Timing Summary"
puts "=============================================="
puts "Worst Negative Slack (Setup): $WNS ns"
puts "Worst Hold Slack:             $WHS ns"

if {$WNS < 0} {
    puts "[WARNING] Design has setup timing violations!"
}
if {$WHS < 0} {
    puts "[WARNING] Design has hold timing violations!"
}

#-----------------------------------------------------------------------------
# Generate Bitstream
#-----------------------------------------------------------------------------

puts "\n[INFO] Generating bitstream..."
write_bitstream -force "$OUTPUT_DIR/${DESIGN_NAME}.bit"

# Generate debug probes file if ILAs are present
# write_debug_probes -force "$OUTPUT_DIR/${DESIGN_NAME}.ltx"

#-----------------------------------------------------------------------------
# Generate Hardware Handoff (for Zynq designs)
#-----------------------------------------------------------------------------

# Uncomment for Zynq designs:
# write_hw_platform -fixed -include_bit -force "$OUTPUT_DIR/${DESIGN_NAME}.xsa"

#-----------------------------------------------------------------------------
# Summary
#-----------------------------------------------------------------------------

puts "\n=============================================="
puts "Build Complete!"
puts "=============================================="
puts "Bitstream:   $OUTPUT_DIR/${DESIGN_NAME}.bit"
puts "Checkpoint:  $OUTPUT_DIR/checkpoints/post_route.dcp"
puts "Reports:     $OUTPUT_DIR/reports/"
puts "=============================================="

# Final utilization summary
report_utilization -hierarchical -file "$OUTPUT_DIR/reports/final_utilization_hier.rpt"

puts "\n[INFO] All done!"

#=============================================================================
# End of Vivado Build Script
#=============================================================================
