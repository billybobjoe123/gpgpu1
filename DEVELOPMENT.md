# GPGPU-1 Development Guide

## Supported Platforms

This project supports development on:
- **macOS** (Apple Silicon & Intel)
- **Linux** (Ubuntu, Fedora, Arch)
- **Windows Subsystem for Linux (WSL2)**

## Quick Setup

### macOS
```bash
./scripts/setup_macos.sh
```

Or manually:
```bash
brew install verilator
brew install --cask gtkwave  # Optional, for waveform viewing
```

### Linux / WSL
```bash
./scripts/setup_linux.sh
```

Or manually (Ubuntu/Debian):
```bash
sudo apt update
sudo apt install verilator gtkwave python3 build-essential
```

## Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Verilator | 5.0+ | SystemVerilog simulation |
| Python 3 | 3.8+ | Assembler toolchain |
| GNU Make | 3.81+ | Build system |
| GTKWave | Any | Waveform viewing (optional) |

## Building & Testing

```bash
# Run all tests
make all

# Individual test targets
make test_asm        # Test the assembler
make test_decoder    # Test instruction decoder
make test_regfile    # Test register file
make test_alu        # Test ALU
make test_scheduler  # Test warp scheduler
make test_lsu        # Test load/store unit
make test_fetch      # Test fetch unit
make test_core       # Test GPU core
make test_memory     # Test memory subsystem
make test_top        # Test top module
make test_system     # Test full system

# Assemble a program
make assemble PROG=programs/vector_add.asm FMT=hex

# Clean build artifacts
make clean
```

## Simulator Selection

The project defaults to Verilator but supports other simulators:

```bash
# Use Verilator (default, open-source)
make test_decoder SIM=verilator

# Use Synopsys VCS (commercial)
make test_decoder SIM=vcs

# Use Mentor Questa/ModelSim (commercial)
make test_decoder SIM=questa

# Use Xilinx XSim (with Vivado)
make test_decoder SIM=xsim
```

## Project Structure

```
gpgpu1/
├── rtl/                    # RTL source files
│   ├── common/             # Shared packages and interfaces
│   │   ├── gpgpu_defines.svh
│   │   ├── gpgpu_pkg.sv
│   │   └── gpgpu_interfaces.sv
│   ├── core/               # GPU core components
│   │   ├── decoder.sv
│   │   ├── register_file.sv
│   │   ├── alu.sv
│   │   ├── fpu.sv
│   │   ├── warp_scheduler.sv
│   │   ├── lsu.sv
│   │   ├── fetch_unit.sv
│   │   └── gpu_core.sv
│   ├── memory/             # Memory subsystem
│   │   ├── l2_cache.sv
│   │   └── memory_controller.sv
│   └── top/                # Top-level modules
│       ├── gpu_top.sv
│       └── gpu_system.sv
├── tb/                     # Testbenches
├── programs/               # Assembly test programs
├── tools/                  # Assembler and utilities
│   ├── gpgpu_asm.py        # GPGPU-1 assembler
│   └── test_assembler.py   # Assembler unit tests
├── scripts/                # Setup and utility scripts
│   ├── setup_macos.sh
│   └── setup_linux.sh
├── build/                  # Build output (generated)
├── logs/                   # Test logs (generated)
└── docs/                   # Documentation
```

## Platform-Specific Notes

### macOS (Apple Silicon)
- Verilator from Homebrew works natively on ARM64
- GTKWave is deprecated upstream but still functional via Homebrew Cask

### Linux
- Most distributions have Verilator in their package repositories
- For the latest Verilator, consider building from source

### WSL
- Use WSL2 for best performance
- GTKWave requires an X server (like VcXsrv or WSLg on Windows 11)
- Files should be stored in the Linux filesystem (not /mnt/c/) for performance

## Troubleshooting

### Verilator Warnings
The Makefile suppresses common warnings. If you see new warnings, you can add them to `CFLAGS` in the Makefile:
```makefile
CFLAGS := ... -Wno-NEWWARNING
```

### "Command not found" errors
Ensure the tools are in your PATH:
```bash
which verilator
which python3
which make
```

### Python module errors
The assembler uses only standard library modules (dataclasses, typing, enum). No pip packages required.
