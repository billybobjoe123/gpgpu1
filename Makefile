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
              $(RTL_DIR)/core/warp_scheduler.sv \
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

.PHONY: all clean compile test_decoder test_regfile test_alu test_scheduler test_lsu test_fetch test_core test_top test_memory test_system test_asm help

all:
	@echo "=============================================="
	@echo "GPGPU-1 Full Test Suite"
	@echo "=============================================="
	@$(MAKE) test_asm
	@$(MAKE) test_decoder
	@$(MAKE) test_regfile
	@$(MAKE) test_alu
	@$(MAKE) test_scheduler
	@$(MAKE) test_lsu
	@$(MAKE) test_fetch
	@$(MAKE) test_core
	@$(MAKE) test_memory
	@$(MAKE) test_top
	@$(MAKE) test_system
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
		-o tb_gpu_system
	@mkdir -p obj_dir/tb_gpu_system
	cd obj_dir && make -f Vtb_gpu_system.mk
	cp obj_dir/tb_gpu_system $(BUILD_DIR)/tb_gpu_system
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
	@echo "Examples:"
	@echo "  make test_decoder"
	@echo "  make all"
	@echo "  make compile"
