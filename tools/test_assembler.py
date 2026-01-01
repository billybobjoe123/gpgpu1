#!/usr/bin/env python3
"""GPGPU-1 Assembler Unit Tests - Validates encoding against ISA spec"""

import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

from gpgpu_asm import Parser, CodeGenerator

def encode_r_type(opcode, rd, rs1, rs2, pred, func):
    """Manually encode R-type instruction for verification."""
    return (opcode << 26) | (rd << 21) | (rs1 << 16) | (rs2 << 11) | (pred << 8) | func

def encode_i_type(opcode, rd, rs1, imm16):
    """Manually encode I-type instruction for verification."""
    return (opcode << 26) | (rd << 21) | (rs1 << 16) | (imm16 & 0xFFFF)

def encode_l_type(opcode, rd_rs, rbase, pred, offset):
    """Manually encode L-type instruction for verification."""
    return (opcode << 26) | (rd_rs << 21) | (rbase << 16) | (pred << 13) | (offset & 0x1FFF)

def test_encoding(name, asm, expected_hex):
    parser = Parser()
    labels, instructions = parser.parse(asm)
    codegen = CodeGenerator(labels)
    machine_code = codegen.generate(instructions)
    
    if len(machine_code) != 1:
        print(f"[FAIL] {name}: Expected 1 instruction, got {len(machine_code)}")
        return False
    
    if machine_code[0] != expected_hex:
        print(f"[FAIL] {name}: Expected 0x{expected_hex:08x}, got 0x{machine_code[0]:08x}")
        return False
    
    print(f"[PASS] {name}")
    return True

def main():
    print("=" * 50)
    print("GPGPU-1 Assembler Unit Tests")
    print("=" * 50)
    
    passed = 0
    failed = 0
    
    # Build tests with correct expected values
    # Format R: opcode(6) | rd(5) | rs1(5) | rs2(5) | pred(3) | func(8)
    tests = [
        # ALU R-type: ADD R3, R1, R2 -> rd=3, rs1=1, rs2=2, pred=0, func=0
        ("ADD R3, R1, R2", "ADD R3, R1, R2", encode_r_type(0x00, 3, 1, 2, 0, 0x00)),
        ("SUB R5, R10, R15", "SUB R5, R10, R15", encode_r_type(0x00, 5, 10, 15, 0, 0x01)),
        ("AND R1, R2, R3", "AND R1, R2, R3", encode_r_type(0x00, 1, 2, 3, 0, 0x02)),
        ("OR R1, R2, R3", "OR R1, R2, R3", encode_r_type(0x00, 1, 2, 3, 0, 0x03)),
        ("XOR R1, R2, R3", "XOR R1, R2, R3", encode_r_type(0x00, 1, 2, 3, 0, 0x04)),
        ("NOT R1, R2", "NOT R1, R2", encode_r_type(0x00, 1, 2, 0, 0, 0x0C)),
        
        # ALU I-type: ADDI uses bits [15:14]=00 for ADDI, [13:0] for imm
        ("ADDI R1, R2, 10", "ADDI R1, R2, 10", encode_i_type(0x01, 1, 2, 10)),
        ("ADDI R1, R2, -1", "ADDI R1, R2, -1", encode_i_type(0x01, 1, 2, 0x3FFF)),
        
        # Shift R-type (opcode 0x04)
        ("SLL R1, R2, R3", "SLL R1, R2, R3", encode_r_type(0x04, 1, 2, 3, 0, 0x00)),
        ("SRL R1, R2, R3", "SRL R1, R2, R3", encode_r_type(0x04, 1, 2, 3, 0, 0x01)),
        
        # Shift I-type: SLLI uses bits [15:14] for func, [13:8] for shamt
        ("SLLI R1, R2, 5", "SLLI R1, R2, 5", encode_i_type(0x05, 1, 2, (0b00 << 14) | (5 << 8))),
        
        # Compare (opcode 0x06)
        ("SEQ P1, R2, R3", "SEQ P1, R2, R3", encode_r_type(0x06, 1, 2, 3, 0, 0x00)),
        ("SLT P1, R5, R10", "SLT P1, R5, R10", encode_r_type(0x06, 1, 5, 10, 0, 0x02)),
        
        # Load (opcode 0x08): L-format
        ("LD R5, 0(R10)", "LD R5, 0(R10)", encode_l_type(0x08, 5, 10, 0, 0)),
        ("LD R5, 16(R10)", "LD R5, 16(R10)", encode_l_type(0x08, 5, 10, 0, 16)),
        
        # Store (opcode 0x0C): L-format
        ("ST R3, 0(R4)", "ST R3, 0(R4)", encode_l_type(0x0C, 3, 4, 0, 0)),
        
        # LDS (opcode 0x0B) and STS (opcode 0x0E)
        ("LDS R1, 8(R2)", "LDS R1, 8(R2)", encode_l_type(0x0B, 1, 2, 0, 8)),
        ("STS R1, 8(R2)", "STS R1, 8(R2)", encode_l_type(0x0E, 1, 2, 0, 8)),
        
        # System
        ("EXIT", "EXIT", 0x14 << 26),  # opcode 0x14 = EXIT
        ("RET", "RET", 0x13 << 26),    # opcode 0x13 = RET
        
        # Divergence
        ("PUSH P1", "PUSH P1", (0x16 << 26) | (1 << 13)),
        ("PUSH P2", "PUSH P2", (0x16 << 26) | (2 << 13)),
        ("POP", "POP", 0x17 << 26),
        ("ELSE", "ELSE", 0x18 << 26),
        
        # Barrier
        ("BAR 0", "BAR 0", 0x15 << 26),
        ("BAR 5", "BAR 5", (0x15 << 26) | 5),
        
        # Data movement
        ("MOVI R1, 100", "MOVI R1, 100", encode_i_type(0x1A, 1, 0, 100)),
        ("MOVSR R1, SR_TID", "MOVSR R1, SR_TID", (0x1B << 26) | (1 << 21) | (0 << 16)),
        ("LUI R1, 0x1234", "LUI R1, 0x1234", encode_i_type(0x1D, 1, 0, 0x1234)),
        
        # MUL/DIV (opcode 0x02)
        ("MUL R1, R2, R3", "MUL R1, R2, R3", encode_r_type(0x02, 1, 2, 3, 0, 0x00)),
        ("DIV R1, R2, R3", "DIV R1, R2, R3", encode_r_type(0x02, 1, 2, 3, 0, 0x04)),
        
        # NOP (ADD R0, R0, R0)
        ("NOP", "NOP", 0x00000000),
    ]
    
    for name, asm, expected in tests:
        try:
            if test_encoding(name, asm, expected):
                passed += 1
            else:
                failed += 1
        except Exception as e:
            print(f"[FAIL] {name}: {e}")
            failed += 1
    
    # Test branch/label handling
    print("\n--- Branch and Label Tests ---")
    try:
        parser = Parser()
        labels, instructions = parser.parse("""
start:
    MOVI R1, 0
loop:
    ADDI R1, R1, 1
    BRA loop
end:
    EXIT
""")
        if labels == {'start': 0, 'loop': 4, 'end': 12}:
            print("[PASS] Label addresses")
            passed += 1
        else:
            print(f"[FAIL] Label addresses: {labels}")
            failed += 1
            
        codegen = CodeGenerator(labels)
        machine_code = codegen.generate(instructions)
        
        # BRA at addr 8 to loop at addr 4: offset = (4-8)/4 = -1
        bra_instr = machine_code[2]
        offset = bra_instr & 0xFFFFF
        if offset == 0xFFFFF:  # -1 in 20-bit twos complement
            print("[PASS] Backward branch offset")
            passed += 1
        else:
            print(f"[FAIL] Backward branch: expected 0xFFFFF, got 0x{offset:05x}")
            failed += 1
    except Exception as e:
        print(f"[FAIL] Branch test: {e}")
        failed += 2
    
    print("\n" + "=" * 50)
    print(f"Passed: {passed}, Failed: {failed}")
    print("=" * 50)
    
    if failed > 0:
        print("*** SOME TESTS FAILED ***")
        sys.exit(1)
    else:
        print("*** ALL TESTS PASSED ***")

if __name__ == '__main__':
    main()
