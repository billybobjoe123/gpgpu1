# GPGPU-1 Simulation Makefile
# Uses Verilator as the primary simulator

#=============================================================================
# Configuration
#=============================================================================

# Simulator selection: verilator (default), vcs, questa, xsim
SIM ?= verilator

# Directories
RTL_DIR    := rtl
TB_DIR     := tb
BUILD_DIR  := build
LOG_DIR    := logs

# Source files
PKG_FILES  := $(RTL_DIR)/common/gpgpu_pkg.sv
INTF_FILES := $(RTL_DIR)/common/gpgpu_interfaces.sv
RTL_FILES  := $(RTL_DIR)/core/decoder.sv \
              $(RTL_DIR)/core/register_file.sv \
              $(RTL_DIR)/core/alu.sv \
              $(RTL_DIR)/core/fpu.sv \
              $(RTL_DIR)/core/fpu_dp.sv \
              $(RTL_DIR)/core/warp_scheduler.sv \
              $(RTL_DIR)/core/warp_shuffle.sv \
              $(RTL_DIR)/core/warp_vote.sv \
              $(RTL_DIR)/core/forwarding_network.sv \
              $(RTL_DIR)/core/performance_counters.sv \
              $(RTL_DIR)/core/lsu.sv \
              $(RTL_DIR)/core/fetch_unit.sv \
              $(RTL_DIR)/core/gpu_core.sv \
              $(RTL_DIR)/memory/l2_cache.sv \
              $(RTL_DIR)/memory/memory_controller.sv \
              $(RTL_DIR)/top/gpu_top.sv \
              $(RTL_DIR)/top/gpu_system.sv

# Include directories
INC_DIRS   := +incdir+$(RTL_DIR)/common

#=============================================================================
# Common flags
#=============================================================================

DEFINES := +define+SIMULATION +define+DEBUG +define+ENABLE_ASSERTIONS

#=============================================================================
# Simulator-specific settings
#=============================================================================

ifeq ($(SIM),verilator)
    # Verilator (default)
    COMPILE  := verilator
    CFLAGS   := --sv --binary --timing -Wall -Wno-fatal -I$(RTL_DIR)/common \
                -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
                -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT -Wno-BLKANDNBLK
    OUT_EXT  :=
else ifeq ($(SIM),vcs)
    # Synopsys VCS
    COMPILE  := vcs
    CFLAGS   := -full64 -sverilog +v2k $(INC_DIRS) $(DEFINES) -debug_access+all
    OUT_EXT  := 
else ifeq ($(SIM),questa)
    # Mentor Questa/ModelSim
    COMPILE  := vlog
    CFLAGS   := -sv $(INC_DIRS) $(DEFINES)
    OUT_EXT  := 
else ifeq ($(SIM),xsim)
    # Xilinx XSim
    COMPILE  := xvlog
    CFLAGS   := --sv $(INC_DIRS) $(DEFINES)
    OUT_EXT  := 
else
    $(error Unknown simulator: $(SIM). Supported: verilator, vcs, questa, xsim)
endif

#=============================================================================
# Targets
#=============================================================================

.PHONY: all clean compile test_decoder test_regfile test_alu test_scheduler test_lsu test_fetch test_core test_top test_memory test_system test_asm test_atomic test_fpu test_perf test_scoreboard test_forwarding synth synth_full synth_gui synth_clean synth_nexys_a7 synth_arty_a7 synth_zcu104 help

all:
	@echo "=============================================="
	@echo "GPGPU-1 Full Test Suite"
	@echo "=============================================="
	@$(MAKE) test_asm
	@$(MAKE) test_decoder
	@$(MAKE) test_regfile
	@$(MAKE) test_alu
	@$(MAKE) test_scheduler
	@$(MAKE) test_scoreboard
	@$(MAKE) test_forwarding
	@$(MAKE) test_lsu
	@$(MAKE) test_atomic
	@$(MAKE) test_fpu
	@$(MAKE) test_fpu_dp
	@$(MAKE) test_warp_vote
	@$(MAKE) test_perf
	@$(MAKE) test_fetch
	@$(MAKE) test_core
	@$(MAKE) test_memory
	@$(MAKE) test_top
	@$(MAKE) test_system
	@$(MAKE) test_multi_core
	@echo "=============================================="
	@echo "ALL TESTS COMPLETED"
	@echo "=============================================="

# Test assembler
test_asm:
	@echo "=============================================="
	@echo "[0/10] ASSEMBLER TEST"
	@echo "=============================================="
	@python3 tools/test_assembler.py

# Assemble a program
# Usage: make assemble PROG=programs/vector_add.asm FMT=hex
PROG ?= programs/vector_add.asm
FMT ?= hex
assemble: $(BUILD_DIR)
	@echo "Assembling $(PROG) -> $(BUILD_DIR)/$(notdir $(basename $(PROG))).$(FMT)"
	@python3 tools/gpgpu_asm.py $(PROG) -o $(BUILD_DIR)/$(notdir $(basename $(PROG))).$(FMT) -f $(FMT) -v

# Create build directories
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(LOG_DIR):
	mkdir -p $(LOG_DIR)

#-----------------------------------------------------------------------------
# Decoder Test
#-----------------------------------------------------------------------------

test_decoder: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[1/8] DECODER TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling decoder testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_decoder \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_decoder.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_decoder
	@echo "[RUN] Running decoder tests..."
	./$(BUILD_DIR)/tb_decoder | tee $(LOG_DIR)/tb_decoder.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_decoder \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_decoder.sv)
	./$(BUILD_DIR)/tb_decoder | tee $(LOG_DIR)/tb_decoder.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# Register File Test
#-----------------------------------------------------------------------------

test_regfile: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[2/8] REGISTER FILE TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling register file testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_register_file \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_register_file.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_register_file
	@echo "[RUN] Running register file tests..."
	./$(BUILD_DIR)/tb_register_file | tee $(LOG_DIR)/tb_register_file.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_register_file \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_register_file.sv)
	./$(BUILD_DIR)/tb_register_file | tee $(LOG_DIR)/tb_register_file.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# FPU Test (Single-Precision, Pipelined)
#-----------------------------------------------------------------------------

test_fpu: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[FPU] FPU AND FMA TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling FPU testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_fpu_sp \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_fpu_sp.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_fpu_sp
	@echo "[RUN] Running FPU and FMA tests..."
	./$(BUILD_DIR)/tb_fpu_sp | tee $(LOG_DIR)/tb_fpu_sp.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_fpu_sp \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_fpu_sp.sv)
	./$(BUILD_DIR)/tb_fpu_sp | tee $(LOG_DIR)/tb_fpu_sp.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# Double-Precision FPU Test
#-----------------------------------------------------------------------------

test_fpu_dp: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[FPU-DP] DOUBLE-PRECISION FPU TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling DP FPU testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_fpu_dp \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_fpu_dp.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_fpu_dp
	@echo "[RUN] Running DP FPU tests..."
	./$(BUILD_DIR)/tb_fpu_dp | tee $(LOG_DIR)/tb_fpu_dp.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_fpu_dp \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_fpu_dp.sv)
	./$(BUILD_DIR)/tb_fpu_dp | tee $(LOG_DIR)/tb_fpu_dp.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# FPU Pipeline Test
#-----------------------------------------------------------------------------

test_fpu_pipeline: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[FPU-PIPE] FPU PIPELINE LATENCY TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling FPU pipeline testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_fpu_pipeline \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_fpu_pipeline.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_fpu_pipeline
	@echo "[RUN] Running FPU pipeline tests..."
	./$(BUILD_DIR)/tb_fpu_pipeline | tee $(LOG_DIR)/tb_fpu_pipeline.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_fpu_pipeline \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_fpu_pipeline.sv)
	./$(BUILD_DIR)/tb_fpu_pipeline | tee $(LOG_DIR)/tb_fpu_pipeline.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# Warp Shuffle Test
#-----------------------------------------------------------------------------

test_warp_shuffle: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[SHFL] WARP SHUFFLE TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling warp shuffle testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_warp_shuffle \
		$(PKG_FILES) $(RTL_DIR)/core/warp_shuffle.sv $(TB_DIR)/tb_warp_shuffle.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_warp_shuffle
	@echo "[RUN] Running warp shuffle tests..."
	./$(BUILD_DIR)/tb_warp_shuffle | tee $(LOG_DIR)/tb_warp_shuffle.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_warp_shuffle \
		$(addprefix ../,$(PKG_FILES) $(RTL_DIR)/core/warp_shuffle.sv $(TB_DIR)/tb_warp_shuffle.sv)
	./$(BUILD_DIR)/tb_warp_shuffle | tee $(LOG_DIR)/tb_warp_shuffle.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# Warp Vote Test
#-----------------------------------------------------------------------------

test_warp_vote: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[VOTE] WARP VOTE TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling warp vote testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_warp_vote \
		$(PKG_FILES) $(RTL_DIR)/core/warp_vote.sv $(TB_DIR)/tb_warp_vote.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_warp_vote
	@echo "[RUN] Running warp vote tests..."
	./$(BUILD_DIR)/tb_warp_vote | tee $(LOG_DIR)/tb_warp_vote.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_warp_vote \
		$(addprefix ../,$(PKG_FILES) $(RTL_DIR)/core/warp_vote.sv $(TB_DIR)/tb_warp_vote.sv)
	./$(BUILD_DIR)/tb_warp_vote | tee $(LOG_DIR)/tb_warp_vote.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# Performance Counters Test
#-----------------------------------------------------------------------------

test_perf: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[PERF] PERFORMANCE COUNTERS TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling performance counters testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_performance_counters \
		$(PKG_FILES) $(RTL_DIR)/core/performance_counters.sv $(TB_DIR)/tb_performance_counters.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_performance_counters
	@echo "[RUN] Running performance counters tests..."
	./$(BUILD_DIR)/tb_performance_counters | tee $(LOG_DIR)/tb_performance_counters.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_performance_counters \
		$(addprefix ../,$(PKG_FILES) $(RTL_DIR)/core/performance_counters.sv $(TB_DIR)/tb_performance_counters.sv)
	./$(BUILD_DIR)/tb_performance_counters | tee $(LOG_DIR)/tb_performance_counters.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# Scoreboard Test (Data Hazard Detection)
#-----------------------------------------------------------------------------

test_scoreboard: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[SCOREBOARD] DATA HAZARD DETECTION TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling scoreboard testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_scoreboard \
		$(PKG_FILES) $(RTL_DIR)/core/warp_scheduler.sv $(TB_DIR)/tb_scoreboard.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_scoreboard
	@echo "[RUN] Running scoreboard tests..."
	./$(BUILD_DIR)/tb_scoreboard | tee $(LOG_DIR)/tb_scoreboard.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_scoreboard \
		$(addprefix ../,$(PKG_FILES) $(RTL_DIR)/core/warp_scheduler.sv $(TB_DIR)/tb_scoreboard.sv)
	./$(BUILD_DIR)/tb_scoreboard | tee $(LOG_DIR)/tb_scoreboard.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# Forwarding Network Test
#-----------------------------------------------------------------------------

test_forwarding: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[FORWARDING] DATA FORWARDING NETWORK TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling forwarding network testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_forwarding_network \
		$(PKG_FILES) $(RTL_DIR)/core/forwarding_network.sv $(TB_DIR)/tb_forwarding_network.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_forwarding_network
	@echo "[RUN] Running forwarding network tests..."
	./$(BUILD_DIR)/tb_forwarding_network | tee $(LOG_DIR)/tb_forwarding_network.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_forwarding_network \
		$(addprefix ../,$(PKG_FILES) $(RTL_DIR)/core/forwarding_network.sv $(TB_DIR)/tb_forwarding_network.sv)
	./$(BUILD_DIR)/tb_forwarding_network | tee $(LOG_DIR)/tb_forwarding_network.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# ALU Test
#-----------------------------------------------------------------------------

test_alu: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[3/8] ALU TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling ALU testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_alu \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_alu.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_alu
	@echo "[RUN] Running ALU tests..."
	./$(BUILD_DIR)/tb_alu | tee $(LOG_DIR)/tb_alu.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_alu \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_alu.sv)
	./$(BUILD_DIR)/tb_alu | tee $(LOG_DIR)/tb_alu.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# Warp Scheduler Test
#-----------------------------------------------------------------------------

test_scheduler: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[4/8] WARP SCHEDULER TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling warp scheduler testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_warp_scheduler \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_warp_scheduler.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_warp_scheduler
	@echo "[RUN] Running warp scheduler tests..."
	./$(BUILD_DIR)/tb_warp_scheduler | tee $(LOG_DIR)/tb_warp_scheduler.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_warp_scheduler \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_warp_scheduler.sv)
	./$(BUILD_DIR)/tb_warp_scheduler | tee $(LOG_DIR)/tb_warp_scheduler.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# LSU Test
#-----------------------------------------------------------------------------

test_lsu: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[5/8] LSU TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling LSU testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_lsu \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_lsu.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_lsu
	@echo "[RUN] Running LSU tests..."
	./$(BUILD_DIR)/tb_lsu | tee $(LOG_DIR)/tb_lsu.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_lsu \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_lsu.sv)
	./$(BUILD_DIR)/tb_lsu | tee $(LOG_DIR)/tb_lsu.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# Atomic Operations Test
#-----------------------------------------------------------------------------

test_atomic: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[ATOMIC] ATOMIC OPERATIONS TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling atomic testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_atomic \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_atomic.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_atomic
	@echo "[RUN] Running atomic operations tests..."
	./$(BUILD_DIR)/tb_atomic | tee $(LOG_DIR)/tb_atomic.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_atomic \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_atomic.sv)
	./$(BUILD_DIR)/tb_atomic | tee $(LOG_DIR)/tb_atomic.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# Fetch Unit Test
#-----------------------------------------------------------------------------

test_fetch: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[6/8] FETCH UNIT TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling fetch unit testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_fetch_unit \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_fetch_unit.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_fetch_unit
	@echo "[RUN] Running fetch unit tests..."
	./$(BUILD_DIR)/tb_fetch_unit | tee $(LOG_DIR)/tb_fetch_unit.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_fetch_unit \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_fetch_unit.sv)
	./$(BUILD_DIR)/tb_fetch_unit | tee $(LOG_DIR)/tb_fetch_unit.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# GPU Core Test
#-----------------------------------------------------------------------------

test_core: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[7/8] GPU CORE TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling GPU core testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_gpu_core \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_gpu_core.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_gpu_core
	@echo "[RUN] Running GPU core tests..."
	./$(BUILD_DIR)/tb_gpu_core | tee $(LOG_DIR)/tb_gpu_core.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_gpu_core \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_gpu_core.sv)
	./$(BUILD_DIR)/tb_gpu_core | tee $(LOG_DIR)/tb_gpu_core.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# GPU Top (Multi-Core) Test
#-----------------------------------------------------------------------------

test_top: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[9/9] GPU TOP (MULTI-CORE) TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling GPU top testbench..."
	@echo "[COMPILE] This may take a while for multi-core design..."
	$(COMPILE) $(CFLAGS) --top-module tb_gpu_top \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_gpu_top.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_gpu_top
	@echo "[COMPILE] Compilation complete!"
	@echo "[RUN] Running GPU top tests..."
	./$(BUILD_DIR)/tb_gpu_top | tee $(LOG_DIR)/tb_gpu_top.log
	@echo "[DONE] GPU top test finished!"
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_gpu_top \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_gpu_top.sv)
	./$(BUILD_DIR)/tb_gpu_top | tee $(LOG_DIR)/tb_gpu_top.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# Memory Subsystem Test
#-----------------------------------------------------------------------------

test_memory: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[8/10] MEMORY SUBSYSTEM TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling memory subsystem testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_memory_subsystem \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_memory_subsystem.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_memory_subsystem
	@echo "[RUN] Running memory subsystem tests..."
	./$(BUILD_DIR)/tb_memory_subsystem | tee $(LOG_DIR)/tb_memory_subsystem.log
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_memory_subsystem \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_memory_subsystem.sv)
	./$(BUILD_DIR)/tb_memory_subsystem | tee $(LOG_DIR)/tb_memory_subsystem.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# GPU System Test (Full Memory Hierarchy)
#-----------------------------------------------------------------------------

test_system: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[10/10] GPU SYSTEM (FULL MEMORY HIERARCHY) TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling GPU system testbench..."
	@echo "[COMPILE] This includes L2 cache and memory controller..."
	$(COMPILE) $(CFLAGS) --top-module tb_gpu_system \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_gpu_system.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_gpu_system
	@echo "[COMPILE] Compilation complete!"
	@echo "[RUN] Running GPU system tests..."
	./$(BUILD_DIR)/tb_gpu_system | tee $(LOG_DIR)/tb_gpu_system.log
	@echo "[DONE] GPU system test finished!"
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_gpu_system \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_gpu_system.sv)
	./$(BUILD_DIR)/tb_gpu_system | tee $(LOG_DIR)/tb_gpu_system.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# Multi-Core Integration Test
#-----------------------------------------------------------------------------

test_multi_core: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[MULTI] MULTI-CORE INTEGRATION TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling multi-core testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_multi_core \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_multi_core.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_multi_core
	@echo "[RUN] Running multi-core tests..."
	./$(BUILD_DIR)/tb_multi_core | tee $(LOG_DIR)/tb_multi_core.log
	@echo "[DONE] Multi-core test finished!"
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_multi_core \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_multi_core.sv)
	./$(BUILD_DIR)/tb_multi_core | tee $(LOG_DIR)/tb_multi_core.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# Divergence Test (End-to-End Control Flow)
#-----------------------------------------------------------------------------

test_divergence: $(BUILD_DIR) $(LOG_DIR)
	@echo "=============================================="
	@echo "[DIV] DIVERGENCE (END-TO-END CONTROL FLOW) TEST"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[COMPILE] Compiling divergence testbench..."
	$(COMPILE) $(CFLAGS) --top-module tb_divergence \
		-DDEBUG_SCHEDULER -DDEBUG_FETCH -DDEBUG_PIPELINE -DDEBUG_GMEM \
		$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_divergence.sv \
		-o $(CURDIR)/$(BUILD_DIR)/tb_divergence
	@echo "[RUN] Running divergence tests..."
	./$(BUILD_DIR)/tb_divergence | tee $(LOG_DIR)/tb_divergence.log
	@echo "[DONE] Divergence test finished!"
else ifeq ($(SIM),vcs)
	cd $(BUILD_DIR) && $(COMPILE) $(CFLAGS) -o tb_divergence \
		$(addprefix ../,$(PKG_FILES) $(RTL_FILES) $(TB_DIR)/tb_divergence.sv)
	./$(BUILD_DIR)/tb_divergence | tee $(LOG_DIR)/tb_divergence.log
else
	@echo "Simulator $(SIM) not fully configured. Add support as needed."
endif

#-----------------------------------------------------------------------------
# Compile only (syntax check)
#-----------------------------------------------------------------------------

compile: $(BUILD_DIR)
	@echo "=============================================="
	@echo "SYNTAX/LINT CHECK"
	@echo "=============================================="
ifeq ($(SIM),verilator)
	@echo "[LINT] Running Verilator lint check..."
	$(COMPILE) $(CFLAGS) --lint-only \
		$(PKG_FILES) $(INTF_FILES) $(RTL_FILES)
	@echo "[LINT] Lint check passed!"
else
	@echo "Use simulator-specific compile check"
endif

#-----------------------------------------------------------------------------
# FPGA Synthesis (Vivado)
#-----------------------------------------------------------------------------

FPGA_DIR       := fpga
FPGA_BUILD_DIR := $(FPGA_DIR)/vivado_output
FPGA_PART      ?= xczu7ev-ffvc1156-2-e
NUM_CORES_FPGA ?= 2

# Board-specific configurations
# ZCU104:   xczu7ev-ffvc1156-2-e, 4 cores, 4 warps
# Nexys A7: xc7a100tcsg324-1, 1 core, 2 warps
# Arty A7:  xc7a100tcsg324-1, 1 core, 2 warps

# Quick synthesis for resource estimation
synth:
	@echo "=============================================="
	@echo "[SYNTH] FPGA Synthesis (Resource Estimation)"
	@echo "=============================================="
	@echo "Target Part: $(FPGA_PART)"
	@echo "Cores: $(NUM_CORES_FPGA)"
	@if command -v vivado >/dev/null 2>&1; then \
		cd $(FPGA_DIR) && vivado -mode batch -source scripts/synth_only.tcl -tclargs $(FPGA_PART) $(NUM_CORES_FPGA); \
	else \
		echo "[ERROR] Vivado not found in PATH. Please source Vivado settings."; \
		echo "  e.g., source /tools/Xilinx/Vivado/2023.2/settings64.sh"; \
		exit 1; \
	fi

# Synthesis for Nexys A7-100T student board
synth_nexys_a7:
	@echo "=============================================="
	@echo "[SYNTH] Nexys A7-100T Synthesis"
	@echo "=============================================="
	$(MAKE) synth FPGA_PART=xc7a100tcsg324-1 NUM_CORES_FPGA=1

# Synthesis for Arty A7-100T
synth_arty_a7:
	@echo "=============================================="
	@echo "[SYNTH] Arty A7-100T Synthesis"
	@echo "=============================================="
	$(MAKE) synth FPGA_PART=xc7a100tcsg324-1 NUM_CORES_FPGA=1

# Synthesis for ZCU104 (full config)
synth_zcu104:
	@echo "=============================================="
	@echo "[SYNTH] ZCU104 Synthesis"
	@echo "=============================================="
	$(MAKE) synth FPGA_PART=xczu7ev-ffvc1156-2-e NUM_CORES_FPGA=2

# Full synthesis, place and route
synth_full:
	@echo "=============================================="
	@echo "[SYNTH] FPGA Full Build (Synthesis + P&R)"
	@echo "=============================================="
	@echo "Target Part: $(FPGA_PART)"
	@if command -v vivado >/dev/null 2>&1; then \
		cd $(FPGA_DIR) && vivado -mode batch -source scripts/build_vivado.tcl; \
	else \
		echo "[ERROR] Vivado not found in PATH. Please source Vivado settings."; \
		exit 1; \
	fi
	@echo "[DONE] Bitstream: $(FPGA_DIR)/vivado_output/gpgpu_top.bit"

# Open Vivado GUI with checkpoint
synth_gui:
	@echo "[SYNTH] Opening Vivado GUI..."
	@if [ -f $(FPGA_DIR)/vivado_output/checkpoints/post_route.dcp ]; then \
		vivado $(FPGA_DIR)/vivado_output/checkpoints/post_route.dcp &; \
	elif [ -f $(FPGA_DIR)/vivado_output/checkpoints/post_synth.dcp ]; then \
		vivado $(FPGA_DIR)/vivado_output/checkpoints/post_synth.dcp &; \
	else \
		echo "[INFO] No checkpoint found. Run 'make synth' first."; \
		vivado &; \
	fi

# Clean FPGA build artifacts
synth_clean:
	@echo "[CLEAN] Removing FPGA build artifacts..."
	rm -rf $(FPGA_DIR)/vivado_output
	rm -rf $(FPGA_DIR)/synth_output
	rm -rf $(FPGA_DIR)/*.jou $(FPGA_DIR)/*.log
	rm -rf $(FPGA_DIR)/.Xil
	@echo "[CLEAN] Done!"

#-----------------------------------------------------------------------------
# Clean
#-----------------------------------------------------------------------------

clean:
	@echo "[CLEAN] Removing build artifacts..."
	rm -rf $(BUILD_DIR) $(LOG_DIR)
	rm -rf obj_dir
	rm -rf simv* csrc* *.log *.vpd *.fsdb DVEfiles
	rm -rf work transcript vsim.wlf
	rm -rf xsim.dir .Xil *.jou *.pb
	@echo "[CLEAN] Done!"

#-----------------------------------------------------------------------------
# Help
#-----------------------------------------------------------------------------

help:
	@echo "GPGPU-1 Simulation Makefile"
	@echo ""
	@echo "Usage: make [target] [SIM=simulator]"
	@echo ""
	@echo "Targets:"
	@echo "  all           - Run all tests (default)"
	@echo "  test_asm      - Run assembler tests"
	@echo "  test_decoder  - Run decoder testbench"
	@echo "  test_regfile  - Run register file testbench"
	@echo "  test_alu      - Run ALU and execution unit testbench"
	@echo "  test_scheduler- Run warp scheduler testbench"
	@echo "  test_lsu      - Run load/store unit testbench"
	@echo "  test_fetch    - Run fetch unit testbench"
	@echo "  test_core     - Run GPU core testbench"
	@echo "  test_memory   - Run memory subsystem testbench"
	@echo "  test_top      - Run GPU top (multi-core) testbench"
	@echo "  test_system   - Run GPU system (full memory hierarchy) testbench"
	@echo "  assemble      - Assemble a program (PROG=filename)"
	@echo "  compile       - Compile only (syntax/lint check)"
	@echo "  clean         - Clean build artifacts"
	@echo "  help          - Show this help"
	@echo ""
	@echo "Assembler:"
	@echo "  make assemble PROG=programs/vector_add.asm"
	@echo "  make assemble PROG=programs/reduction.asm FMT=sv"
	@echo ""
	@echo "Simulators (SIM=):"
	@echo "  verilator    - Verilator (default)"
	@echo "  vcs          - Synopsys VCS"
	@echo "  questa       - Mentor Questa/ModelSim"
	@echo "  xsim         - Xilinx XSim"
	@echo ""
	@echo "FPGA Synthesis:"
	@echo "  synth          - Quick synthesis (resource estimation)"
	@echo "  synth_full     - Full synthesis, place & route, bitstream"
	@echo "  synth_nexys_a7 - Synthesis for Digilent Nexys A7-100T"
	@echo "  synth_arty_a7  - Synthesis for Digilent Arty A7-100T"
	@echo "  synth_zcu104   - Synthesis for Xilinx ZCU104"
	@echo "  synth_gui      - Open Vivado GUI with checkpoint"
	@echo "  synth_clean    - Clean FPGA build artifacts"
	@echo ""
	@echo "Examples:"
	@echo "  make test_decoder"
	@echo "  make all"
	@echo "  make compile"
	@echo "  make synth_nexys_a7   # For student boards"
