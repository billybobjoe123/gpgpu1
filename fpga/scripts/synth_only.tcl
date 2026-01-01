#=============================================================================
# GPGPU-1 Vivado Synthesis-Only Script
#=============================================================================
# File:        synth_only.tcl
# Description: Quick synthesis-only script for resource estimation
# Usage:       vivado -mode batch -source synth_only.tcl
# Date:        January 1, 2026
#=============================================================================

#-----------------------------------------------------------------------------
# Configuration
#-----------------------------------------------------------------------------

# Target FPGA - Modify for your target
set PART "xczu7ev-ffvc1156-2-e"

# Alternative common parts (uncomment one):
# set PART "xc7a100tcsg324-1"     ;# Artix-7 100T
# set PART "xc7k325tffg900-2"     ;# Kintex-7 325T
# set PART "xcku040-ffva1156-2-e" ;# Kintex Ultrascale

# Design configuration
set NUM_CORES 2
set WARPS_PER_CORE 4

set DESIGN_NAME "gpgpu_top"
set OUTPUT_DIR "synth_output"

#-----------------------------------------------------------------------------
# Directory Setup
#-----------------------------------------------------------------------------

set SCRIPT_DIR [file dirname [info script]]
set ROOT_DIR [file normalize "$SCRIPT_DIR/.."]
set RTL_DIR "$ROOT_DIR/rtl"

file mkdir $OUTPUT_DIR

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

#-----------------------------------------------------------------------------
# Run Synthesis
#-----------------------------------------------------------------------------

puts "=============================================="
puts "GPGPU-1 Synthesis-Only (Resource Estimation)"
puts "=============================================="
puts "Part:        $PART"
puts "Cores:       $NUM_CORES"
puts "Warps/Core:  $WARPS_PER_CORE"
puts "=============================================="

# Read sources
puts "\n[INFO] Reading RTL sources..."
foreach f $RTL_FILES {
    if {[file exists $f]} {
        read_verilog -sv $f
    } else {
        puts "[WARNING] File not found: $f"
    }
}

# Set generic parameters
set_property generic "NUM_CORES=$NUM_CORES WARPS_PER_CORE=$WARPS_PER_CORE" [current_fileset]

# Synthesize
puts "\n[INFO] Running synthesis..."
synth_design \
    -top gpu_top \
    -part $PART \
    -flatten_hierarchy rebuilt \
    -directive AreaOptimized_high \
    -retiming

# Generate reports
puts "\n[INFO] Generating reports..."

report_utilization -file "$OUTPUT_DIR/utilization.rpt"
report_utilization -hierarchical -file "$OUTPUT_DIR/utilization_hier.rpt"
report_timing_summary -file "$OUTPUT_DIR/timing_summary.rpt"
report_design_analysis -file "$OUTPUT_DIR/design_analysis.rpt"

# Print summary to console
puts "\n=============================================="
puts "Resource Utilization Summary"
puts "=============================================="
report_utilization -hierarchical -hierarchical_depth 2

# Extract key metrics
set util_report [report_utilization -return_string]
puts "\n$util_report"

puts "\n=============================================="
puts "Synthesis Complete!"
puts "=============================================="
puts "Reports saved to: $OUTPUT_DIR/"
puts "=============================================="

#=============================================================================
# End of Synthesis-Only Script
#=============================================================================
