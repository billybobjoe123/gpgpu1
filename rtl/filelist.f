// GPGPU-1 RTL File List
// This file lists all RTL source files in compilation order

// Common files (must be compiled first)
rtl/common/gpgpu_defines.svh
rtl/common/gpgpu_pkg.sv
rtl/common/gpgpu_interfaces.sv

// Core components
rtl/core/decoder.sv
rtl/core/register_file.sv
rtl/core/alu.sv
rtl/core/fpu.sv
rtl/core/fpu_dp.sv
rtl/core/warp_scheduler.sv
rtl/core/warp_shuffle.sv
rtl/core/lsu.sv
rtl/core/fetch_unit.sv
rtl/core/gpu_core.sv

// Top level
rtl/top/gpu_top.sv
