#!/bin/bash
# GPGPU-1 macOS Setup Script
# Run this script to install all necessary dependencies on macOS

set -e

echo "=========================================="
echo "GPGPU-1 macOS Development Setup"
echo "=========================================="

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo "[ERROR] Homebrew not found. Install from https://brew.sh"
    exit 1
fi

echo "[OK] Homebrew found"

# Install Verilator
echo "[INSTALL] Checking Verilator..."
if ! command -v verilator &> /dev/null; then
    echo "[INSTALL] Installing Verilator..."
    brew install verilator
else
    echo "[OK] Verilator already installed: $(verilator --version | head -1)"
fi

# Install GTKWave (optional, for waveform viewing)
echo "[INSTALL] Checking GTKWave..."
if ! command -v gtkwave &> /dev/null; then
    echo "[INSTALL] Installing GTKWave (optional)..."
    brew install --cask gtkwave || echo "[WARN] GTKWave installation failed (deprecated but still functional)"
else
    echo "[OK] GTKWave already installed"
fi

# Check Python
echo "[CHECK] Checking Python 3..."
if ! command -v python3 &> /dev/null; then
    echo "[INSTALL] Installing Python 3..."
    brew install python3
else
    echo "[OK] Python 3 found: $(python3 --version)"
fi

# Verify Python dependencies
echo "[CHECK] Verifying Python modules..."
python3 -c "from dataclasses import dataclass; from typing import Dict, List, Optional; from enum import Enum, auto" && \
    echo "[OK] Python dependencies satisfied" || \
    echo "[WARN] Python may be missing required modules"

# Check Make
echo "[CHECK] Checking Make..."
if command -v make &> /dev/null; then
    echo "[OK] Make found: $(make --version | head -1)"
else
    echo "[INSTALL] Installing build tools..."
    xcode-select --install
fi

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Run tests with:"
echo "  make test_asm      # Test assembler"
echo "  make test_decoder  # Test decoder"
echo "  make all           # Run all tests"
echo ""
echo "Assemble a program with:"
echo "  make assemble PROG=programs/vector_add.asm"
echo ""
