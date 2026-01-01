#!/bin/bash
# GPGPU-1 Linux/WSL Setup Script
# Run this script to install all necessary dependencies on Linux/WSL

set -e

echo "=========================================="
echo "GPGPU-1 Linux Development Setup"
echo "=========================================="

# Detect package manager
if command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt"
    INSTALL_CMD="sudo apt-get install -y"
    UPDATE_CMD="sudo apt-get update"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
    INSTALL_CMD="sudo dnf install -y"
    UPDATE_CMD="sudo dnf check-update || true"
elif command -v pacman &> /dev/null; then
    PKG_MANAGER="pacman"
    INSTALL_CMD="sudo pacman -S --noconfirm"
    UPDATE_CMD="sudo pacman -Sy"
else
    echo "[ERROR] No supported package manager found (apt, dnf, pacman)"
    exit 1
fi

echo "[OK] Using package manager: $PKG_MANAGER"

# Update package lists
echo "[UPDATE] Updating package lists..."
$UPDATE_CMD

# Install Verilator
echo "[INSTALL] Checking Verilator..."
if ! command -v verilator &> /dev/null; then
    echo "[INSTALL] Installing Verilator..."
    if [ "$PKG_MANAGER" = "apt" ]; then
        $INSTALL_CMD verilator
    elif [ "$PKG_MANAGER" = "dnf" ]; then
        $INSTALL_CMD verilator
    elif [ "$PKG_MANAGER" = "pacman" ]; then
        $INSTALL_CMD verilator
    fi
else
    echo "[OK] Verilator already installed: $(verilator --version | head -1)"
fi

# Install GTKWave (optional)
echo "[INSTALL] Checking GTKWave..."
if ! command -v gtkwave &> /dev/null; then
    echo "[INSTALL] Installing GTKWave (optional)..."
    if [ "$PKG_MANAGER" = "apt" ]; then
        $INSTALL_CMD gtkwave
    elif [ "$PKG_MANAGER" = "dnf" ]; then
        $INSTALL_CMD gtkwave
    elif [ "$PKG_MANAGER" = "pacman" ]; then
        $INSTALL_CMD gtkwave
    fi
else
    echo "[OK] GTKWave already installed"
fi

# Install Python 3
echo "[CHECK] Checking Python 3..."
if ! command -v python3 &> /dev/null; then
    echo "[INSTALL] Installing Python 3..."
    if [ "$PKG_MANAGER" = "apt" ]; then
        $INSTALL_CMD python3
    elif [ "$PKG_MANAGER" = "dnf" ]; then
        $INSTALL_CMD python3
    elif [ "$PKG_MANAGER" = "pacman" ]; then
        $INSTALL_CMD python
    fi
else
    echo "[OK] Python 3 found: $(python3 --version)"
fi

# Install build essentials
echo "[CHECK] Checking build tools..."
if [ "$PKG_MANAGER" = "apt" ]; then
    $INSTALL_CMD build-essential
elif [ "$PKG_MANAGER" = "dnf" ]; then
    $INSTALL_CMD gcc gcc-c++ make
elif [ "$PKG_MANAGER" = "pacman" ]; then
    $INSTALL_CMD base-devel
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
