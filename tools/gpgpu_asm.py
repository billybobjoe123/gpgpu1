#!/usr/bin/env python3
"""
GPGPU-1 Assembler
=================
Assembles GPGPU-1 assembly language into binary machine code.

Usage:
    python gpgpu_asm.py input.asm -o output.bin
    python gpgpu_asm.py input.asm -o output.hex --format hex
    python gpgpu_asm.py input.asm -o output.mem --format mem

Author: GPGPU-1 Project
Version: 1.0
"""

import argparse
import sys
import re
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple, Union
from enum import Enum, auto

#=============================================================================
# Constants - Opcodes
#=============================================================================

OPCODES = {
    # ALU operations (Format R)
    'ALU':    0x00,
    'ALUI':   0x01,
    'MUL':    0x02,
    'MULI':   0x03,
    'SHIFT':  0x04,
    'SHIFTI': 0x05,
    'CMP':    0x06,
    'CMPI':   0x07,
    
    # Memory operations (Format L)
    'LD':     0x08,
    'LD32':   0x09,
    'LD32S':  0x0A,
    'LDS':    0x0B,
    'ST':     0x0C,
    'ST32':   0x0D,
    'STS':    0x0E,
    'LDS32':  0x0F,
    'STS32':  0x1F,
    
    # Control flow (Format B)
    'BRA':    0x10,
    'BRC':    0x11,
    'CALL':   0x12,
    
    # System (Format S)
    'RET':    0x13,
    'EXIT':   0x14,
    
    # Divergence/Mask (Format M)
    'BAR':    0x15,
    'PUSH':   0x16,
    'POP':    0x17,
    'ELSE':   0x18,
    'VOTE':   0x19,
      # Data movement (Format I/S)
    'MOV':    0x1A,
    'MOVSR':  0x1B,
    'SEL':    0x1C,
    'LUI':    0x1D,
    'AUIPC':  0x1E,
    
    # Floating-Point Operations (Format R)
    'FADD':   0x20,
    'FSUB':   0x21,
    'FMUL':   0x22,
    'FDIV':   0x23,
    'FMIN':   0x24,
    'FMAX':   0x25,
    'FSQRT':  0x26,
    'FABS':   0x27,
    'FNEG':   0x28,
    'FMADD':  0x29,
    'FCMP':   0x2A,
    'FCVT':   0x2B,
    'FRCP':   0x2C,
    'FRSQRT': 0x2D,
}

# ALU function codes (opcode 0x00)
ALU_FUNCS = {
    'ADD':  0x00,
    'SUB':  0x01,
    'AND':  0x02,
    'OR':   0x03,
    'XOR':  0x04,
    'NOR':  0x05,
    'MIN':  0x06,
    'MAX':  0x07,
    'MINU': 0x08,
    'MAXU': 0x09,
    'ABS':  0x0A,
    'NEG':  0x0B,
    'NOT':  0x0C,
    'CLZ':  0x0D,
    'CTZ':  0x0E,
    'POPC': 0x0F,
}

# Multiply/Divide function codes (opcode 0x02)
MUL_FUNCS = {
    'MUL':    0x00,
    'MULH':   0x01,
    'MULHU':  0x02,
    'MULHSU': 0x03,
    'DIV':    0x04,
    'DIVU':   0x05,
    'REM':    0x06,
    'REMU':   0x07,
}

# Shift function codes (opcode 0x04)
SHIFT_FUNCS = {
    'SLL': 0x00,
    'SRL': 0x01,
    'SRA': 0x02,
    'ROL': 0x03,
    'ROR': 0x04,
}

# Shift immediate function codes (opcode 0x05, bits [15:14])
SHIFTI_FUNCS = {
    'SLLI': 0b00,
    'SRLI': 0b01,
    'SRAI': 0b10,
}

# Compare function codes (opcode 0x06)
CMP_FUNCS = {
    'SEQ':  0x00,
    'SNE':  0x01,
    'SLT':  0x02,
    'SLE':  0x03,
    'SGT':  0x04,
    'SGE':  0x05,
    'SLTU': 0x06,
    'SLEU': 0x07,
    'SGTU': 0x08,
    'SGEU': 0x09,
    'PAND': 0x0A,
    'POR':  0x0B,
    'PXOR': 0x0C,
    'PNOT': 0x0D,
}

# Branch condition codes
BRANCH_CONDS = {
    'ALWAYS': 0b000,
    'TRUE':   0b001,
    'FALSE':  0b010,
    'ANY':    0b011,
    'ALL':    0b100,
    'NONE':   0b101,
}

# Vote function codes
VOTE_FUNCS = {
    'ANY':    0x0,
    'ALL':    0x1,
    'NONE':   0x2,
    'BALLOT': 0x3,
    'POPC':   0x4,
}

# Special registers
SPECIAL_REGS = {
    'SR_TID':      0,
    'SR_WID':      1,
    'SR_CID':      2,
    'SR_BID_X':    3,
    'SR_BID_Y':    4,
    'SR_BID_Z':    5,
    'SR_NTID':     6,
    'SR_NCTAID_X': 7,
    'SR_NCTAID_Y': 8,
    'SR_NCTAID_Z': 9,
    'SR_CLOCK':    10,
    'SR_CLOCK_HI': 11,
    # Aliases
    'TID':         0,
    'WID':         1,
    'CID':         2,
    'LANEID':      0,  # Alias for thread ID
}

#=============================================================================
# FPU Function Codes
#=============================================================================

# FP Compare function codes (for FCMP)
FCMP_FUNCS = {
    'EQ':  0x0,   # a == b
    'NE':  0x1,   # a != b
    'LT':  0x2,   # a < b
    'LE':  0x3,   # a <= b
    'GT':  0x4,   # a > b
    'GE':  0x5,   # a >= b
    'ORD': 0x6,   # ordered (neither is NaN)
    'UNO': 0x7,   # unordered (either is NaN)
}

# FP Convert function codes (for FCVT)
FCVT_FUNCS = {
    'S2D':   0x00,  # Single to Double
    'D2S':   0x01,  # Double to Single
    'S2I':   0x02,  # Single to Int64 (signed)
    'S2U':   0x03,  # Single to Int64 (unsigned)
    'I2S':   0x04,  # Int64 to Single (signed)
    'U2S':   0x05,  # Int64 to Single (unsigned)
    'D2I':   0x06,  # Double to Int64 (signed)
    'D2U':   0x07,  # Double to Int64 (unsigned)
    'I2D':   0x08,  # Int64 to Double (signed)
    'U2D':   0x09,  # Int64 to Double (unsigned)
    'S2I32': 0x0A,  # Single to Int32 (signed)
    'S2U32': 0x0B,  # Single to Int32 (unsigned)
    'I322S': 0x0C,  # Int32 to Single (signed)
    'U322S': 0x0D,  # Int32 to Single (unsigned)
}

# FP Rounding modes (encoded in func[1:0])
FP_ROUND_MODES = {
    'RNE': 0b00,  # Round to Nearest, ties to Even (default)
    'RTZ': 0b01,  # Round Toward Zero
    'RDN': 0b10,  # Round Down (toward -infinity)
    'RUP': 0b11,  # Round Up (toward +infinity)
}

#=============================================================================
# Data Structures
#=============================================================================

@dataclass
class Token:
    type: str
    value: str
    line: int
    col: int

@dataclass
class Instruction:
    mnemonic: str
    operands: List[str]
    predicate: Optional[str]
    negate_pred: bool
    line: int
    address: int

@dataclass 
class Label:
    name: str
    address: int

class AssemblerError(Exception):
    def __init__(self, message: str, line: int = 0):
        self.message = message
        self.line = line
        super().__init__(f"Line {line}: {message}")

#=============================================================================
# Lexer
#=============================================================================

class Lexer:
    def __init__(self, source: str):
        self.source = source
        self.lines = source.split('\n')
        
    def tokenize_line(self, line_num: int, line: str) -> List[Token]:
        """Tokenize a single line of assembly."""
        tokens = []
        
        # Remove comments
        if ';' in line:
            line = line[:line.index(';')]
        
        # Skip empty lines
        line = line.strip()
        if not line:
            return tokens
        
        # Pattern for tokens
        # Matches: labels (word:), registers (R0-R31, P0-P7), 
        # immediates (decimal, hex, binary), mnemonics, etc.
        pattern = r'''
            (\w+:)           |  # Label
            (@!?\w+)         |  # Predicate (@P1 or @!P1)
            ([RP]\d+)        |  # Register (R0-R31, P0-P7)
            (SR_\w+|\w+)     |  # Mnemonic or special reg
            (-?0x[0-9A-Fa-f]+) |  # Hex immediate
            (-?0b[01]+)      |  # Binary immediate
            (-?\d+)          |  # Decimal immediate
            (\()             |  # Open paren
            (\))             |  # Close paren
            (,)              |  # Comma
            (\.)             |  # Dot (modifier separator)
        '''
        
        col = 0
        for match in re.finditer(pattern, line, re.VERBOSE):
            value = match.group(0)
            if value:
                # Determine token type
                if value.endswith(':'):
                    tok_type = 'LABEL'
                    value = value[:-1]  # Remove colon
                elif value.startswith('@'):
                    tok_type = 'PREDICATE'
                elif value.upper().startswith('R') and value[1:].isdigit():
                    tok_type = 'REG'
                elif value.upper().startswith('P') and value[1:].isdigit():
                    tok_type = 'PRED_REG'
                elif value.upper().startswith('SR_') or value.upper() in SPECIAL_REGS:
                    tok_type = 'SPECIAL_REG'
                elif value == '(':
                    tok_type = 'LPAREN'
                elif value == ')':
                    tok_type = 'RPAREN'
                elif value == ',':
                    tok_type = 'COMMA'
                elif value == '.':
                    tok_type = 'DOT'
                elif value.startswith('0x') or value.startswith('-0x'):
                    tok_type = 'IMM_HEX'
                elif value.startswith('0b') or value.startswith('-0b'):
                    tok_type = 'IMM_BIN'
                elif value.lstrip('-').isdigit():
                    tok_type = 'IMM_DEC'
                else:
                    tok_type = 'IDENT'
                
                tokens.append(Token(tok_type, value, line_num, col))
            col = match.end()
        
        return tokens

#=============================================================================
# Parser
#=============================================================================

class Parser:
    def __init__(self):
        self.labels: Dict[str, int] = {}
        self.instructions: List[Instruction] = []
        self.current_address = 0
        
    def parse(self, source: str) -> Tuple[Dict[str, int], List[Instruction]]:
        """Two-pass assembly: first collect labels, then parse instructions."""
        lexer = Lexer(source)
        
        # First pass: collect labels and calculate addresses
        self.current_address = 0
        for line_num, line in enumerate(lexer.lines, 1):
            tokens = lexer.tokenize_line(line_num, line)
            if not tokens:
                continue
            
            # Check for label
            if tokens[0].type == 'LABEL':
                label_name = tokens[0].value
                if label_name in self.labels:
                    raise AssemblerError(f"Duplicate label: {label_name}", line_num)
                self.labels[label_name] = self.current_address
                tokens = tokens[1:]  # Remove label from tokens
            
            # If there are remaining tokens, it's an instruction
            if tokens:
                self.current_address += 4  # Each instruction is 4 bytes
        
        # Second pass: parse instructions
        self.current_address = 0
        for line_num, line in enumerate(lexer.lines, 1):
            tokens = lexer.tokenize_line(line_num, line)
            if not tokens:
                continue
            
            # Skip label token
            if tokens[0].type == 'LABEL':
                tokens = tokens[1:]
            
            if tokens:
                instr = self._parse_instruction(tokens, line_num)
                if instr:
                    self.instructions.append(instr)
                    self.current_address += 4
        
        return self.labels, self.instructions
    
    def _parse_instruction(self, tokens: List[Token], line_num: int) -> Optional[Instruction]:
        """Parse a single instruction from tokens."""
        idx = 0
        predicate = None
        negate_pred = False
        
        # Check for predicate
        if tokens[idx].type == 'PREDICATE':
            pred_str = tokens[idx].value
            if pred_str.startswith('@!'):
                negate_pred = True
                predicate = pred_str[2:]
            else:
                predicate = pred_str[1:]
            idx += 1
        
        if idx >= len(tokens):
            return None
        
        # Get mnemonic (might have modifier after dot)
        mnemonic_parts = []
        mnemonic_parts.append(tokens[idx].value.upper())
        idx += 1
        
        # Check for modifiers (e.g., BRC.TRUE)
        while idx < len(tokens) and tokens[idx].type == 'DOT':
            idx += 1
            if idx < len(tokens):
                mnemonic_parts.append(tokens[idx].value.upper())
                idx += 1
        
        mnemonic = '.'.join(mnemonic_parts)
        
        # Parse operands
        operands = []
        while idx < len(tokens):
            tok = tokens[idx]
            if tok.type == 'COMMA':
                idx += 1
                continue
            elif tok.type in ('REG', 'PRED_REG', 'SPECIAL_REG', 'IDENT', 
                             'IMM_DEC', 'IMM_HEX', 'IMM_BIN'):
                # Check for memory operand: OFFSET(BASE)
                if idx + 1 < len(tokens) and tokens[idx + 1].type == 'LPAREN':
                    # This is an offset
                    offset = tok.value
                    idx += 2  # Skip offset and LPAREN
                    if idx < len(tokens):
                        base = tokens[idx].value
                        idx += 1
                        if idx < len(tokens) and tokens[idx].type == 'RPAREN':
                            idx += 1
                        operands.append(f"{offset}({base})")
                    continue
                else:
                    operands.append(tok.value)
            elif tok.type == 'LPAREN':
                # Standalone (BASE) means offset 0
                idx += 1
                if idx < len(tokens):
                    base = tokens[idx].value
                    idx += 1
                    if idx < len(tokens) and tokens[idx].type == 'RPAREN':
                        idx += 1
                    operands.append(f"0({base})")
                continue
            idx += 1
        
        return Instruction(
            mnemonic=mnemonic,
            operands=operands,
            predicate=predicate,
            negate_pred=negate_pred,
            line=line_num,
            address=self.current_address
        )

#=============================================================================
# Code Generator
#=============================================================================

class CodeGenerator:
    def __init__(self, labels: Dict[str, int]):
        self.labels = labels
        
    def generate(self, instructions: List[Instruction]) -> List[int]:
        """Generate machine code for all instructions."""
        machine_code = []
        for instr in instructions:
            try:
                code = self._encode_instruction(instr)
                machine_code.append(code)
            except Exception as e:
                raise AssemblerError(str(e), instr.line)
        return machine_code
    
    def _parse_register(self, reg_str: str) -> int:
        """Parse register string (R0-R31 or P0-P7) to number."""
        reg_str = reg_str.upper()
        if reg_str.startswith('R'):
            num = int(reg_str[1:])
            if 0 <= num <= 31:
                return num
            raise ValueError(f"Invalid register: {reg_str}")
        elif reg_str.startswith('P'):
            num = int(reg_str[1:])
            if 0 <= num <= 7:
                return num
            raise ValueError(f"Invalid predicate register: {reg_str}")
        raise ValueError(f"Unknown register: {reg_str}")
    
    def _parse_immediate(self, imm_str: str, bits: int, signed: bool = True) -> int:
        """Parse immediate value and check range."""
        if imm_str.startswith('0x') or imm_str.startswith('-0x'):
            value = int(imm_str, 16)
        elif imm_str.startswith('0b') or imm_str.startswith('-0b'):
            value = int(imm_str, 2)
        else:
            value = int(imm_str)
        
        # Check range
        if signed:
            min_val = -(1 << (bits - 1))
            max_val = (1 << (bits - 1)) - 1
        else:
            min_val = 0
            max_val = (1 << bits) - 1
        
        if not (min_val <= value <= max_val):
            raise ValueError(f"Immediate {value} out of range [{min_val}, {max_val}]")
        
        # Return as unsigned for encoding
        if value < 0:
            value = value + (1 << bits)
        return value
    
    def _parse_memory_operand(self, operand: str) -> Tuple[int, int]:
        """Parse memory operand like '16(R10)' into (offset, base_reg)."""
        match = re.match(r'(-?\w+)\((\w+)\)', operand)
        if not match:
            raise ValueError(f"Invalid memory operand: {operand}")
        offset_str = match.group(1)
        base_str = match.group(2)
        
        offset = self._parse_immediate(offset_str, 13, signed=True)
        base = self._parse_register(base_str)
        return offset, base
    
    def _get_predicate(self, instr: Instruction) -> int:
        """Get predicate register number (default P0 = always)."""
        if instr.predicate:
            return self._parse_register(instr.predicate)
        return 0  # P0 is always true
    
    def _encode_instruction(self, instr: Instruction) -> int:
        """Encode a single instruction to 32-bit machine code."""
        mnemonic = instr.mnemonic
        ops = instr.operands
        
        # Determine instruction type and encode
        
        #---------------------------------------------------------------------
        # ALU R-type: ADD, SUB, AND, OR, XOR, etc.
        #---------------------------------------------------------------------
        if mnemonic in ALU_FUNCS:
            return self._encode_alu_r(instr, ALU_FUNCS[mnemonic])
        
        #---------------------------------------------------------------------
        # ALU I-type: ADDI, ANDI, ORI, XORI
        #---------------------------------------------------------------------
        if mnemonic == 'ADDI':
            return self._encode_alui(instr, 0b00)
        if mnemonic == 'ANDI':
            return self._encode_alui(instr, 0b01)
        if mnemonic == 'ORI':
            return self._encode_alui(instr, 0b10)
        if mnemonic == 'XORI':
            return self._encode_alui(instr, 0b11)
        
        #---------------------------------------------------------------------
        # Multiply/Divide R-type
        #---------------------------------------------------------------------
        if mnemonic in MUL_FUNCS:
            return self._encode_mul_r(instr, MUL_FUNCS[mnemonic])
        
        #---------------------------------------------------------------------
        # Shift R-type: SLL, SRL, SRA, ROL, ROR
        #---------------------------------------------------------------------
        if mnemonic in SHIFT_FUNCS:
            return self._encode_shift_r(instr, SHIFT_FUNCS[mnemonic])
        
        #---------------------------------------------------------------------
        # Shift I-type: SLLI, SRLI, SRAI
        #---------------------------------------------------------------------
        if mnemonic in SHIFTI_FUNCS:
            return self._encode_shifti(instr, SHIFTI_FUNCS[mnemonic])
        
        #---------------------------------------------------------------------
        # Compare: SEQ, SNE, SLT, etc.
        #---------------------------------------------------------------------
        if mnemonic in CMP_FUNCS:
            return self._encode_cmp(instr, CMP_FUNCS[mnemonic])
        
        #---------------------------------------------------------------------
        # Load/Store
        #---------------------------------------------------------------------
        if mnemonic in ('LD', 'LD32', 'LD32S', 'LDS', 'LDS32'):
            return self._encode_load(instr, OPCODES[mnemonic])
        if mnemonic in ('ST', 'ST32', 'STS', 'STS32'):
            return self._encode_store(instr, OPCODES[mnemonic])
        
        #---------------------------------------------------------------------
        # Branch
        #---------------------------------------------------------------------
        if mnemonic == 'BRA':
            return self._encode_branch(instr, BRANCH_CONDS['ALWAYS'])
        if mnemonic.startswith('BRC'):
            return self._encode_brc(instr)
        if mnemonic == 'CALL':
            return self._encode_call(instr)
        
        #---------------------------------------------------------------------
        # System
        #---------------------------------------------------------------------
        if mnemonic == 'RET':
            return self._encode_simple(OPCODES['RET'])
        if mnemonic == 'EXIT':
            return self._encode_simple(OPCODES['EXIT'])
        
        #---------------------------------------------------------------------
        # Divergence
        #---------------------------------------------------------------------
        if mnemonic == 'PUSH':
            return self._encode_push(instr)
        if mnemonic == 'POP':
            return self._encode_simple(OPCODES['POP'])
        if mnemonic == 'ELSE':
            return self._encode_simple(OPCODES['ELSE'])
        if mnemonic == 'BAR':
            return self._encode_bar(instr)
        
        #---------------------------------------------------------------------
        # Vote
        #---------------------------------------------------------------------
        if mnemonic.startswith('VOTE'):
            return self._encode_vote(instr)
        if mnemonic == 'BALLOT':
            return self._encode_ballot(instr)
        
        #---------------------------------------------------------------------
        # Data movement
        #---------------------------------------------------------------------
        if mnemonic == 'MOV':
            return self._encode_mov(instr)
        if mnemonic == 'MOVI':
            return self._encode_movi(instr)
        if mnemonic == 'MOVSR':
            return self._encode_movsr(instr)
        if mnemonic == 'LUI':
            return self._encode_lui(instr)
        if mnemonic == 'AUIPC':
            return self._encode_auipc(instr)
        if mnemonic == 'SEL':
            return self._encode_sel(instr)
        
        #---------------------------------------------------------------------
        # Floating-Point Operations
        #---------------------------------------------------------------------
        # Binary FP ops: FADD, FSUB, FMUL, FDIV, FMIN, FMAX
        if mnemonic in ('FADD', 'FSUB', 'FMUL', 'FDIV', 'FMIN', 'FMAX'):
            return self._encode_fp_binary(instr, OPCODES[mnemonic])
        
        # Unary FP ops: FSQRT, FABS, FNEG, FRCP, FRSQRT
        if mnemonic in ('FSQRT', 'FABS', 'FNEG', 'FRCP', 'FRSQRT'):
            return self._encode_fp_unary(instr, OPCODES[mnemonic])
        
        # FP Compare: FCMP.cond (e.g., FCMP.EQ, FCMP.LT)
        if mnemonic.startswith('FCMP'):
            return self._encode_fcmp(instr)
        
        # FP Convert: FCVT.func (e.g., FCVT.I2S, FCVT.S2I)
        if mnemonic.startswith('FCVT'):
            return self._encode_fcvt(instr)
        
        # FP Fused Multiply-Add
        if mnemonic == 'FMADD':
            return self._encode_fmadd(instr)
        
        #---------------------------------------------------------------------
        # NOP (pseudo-instruction)
        #---------------------------------------------------------------------
        if mnemonic == 'NOP':
            # NOP is ADD R0, R0, R0
            return 0x00000000
        
        raise ValueError(f"Unknown instruction: {mnemonic}")
    
    #=========================================================================
    # Encoding helpers
    #=========================================================================
    
    def _encode_alu_r(self, instr: Instruction, func: int) -> int:
        """Encode ALU R-type: opcode(6) | rd(5) | rs1(5) | rs2(5) | pred(3) | func(8)"""
        ops = instr.operands
        if len(ops) < 2:
            raise ValueError(f"ALU instruction requires at least 2 operands")
        
        rd = self._parse_register(ops[0])
        rs1 = self._parse_register(ops[1])
        rs2 = self._parse_register(ops[2]) if len(ops) > 2 else 0
        pred = self._get_predicate(instr)
        
        return (OPCODES['ALU'] << 26) | (rd << 21) | (rs1 << 16) | (rs2 << 11) | (pred << 8) | func
    
    def _encode_alui(self, instr: Instruction, func2: int) -> int:
        """Encode ALU I-type: opcode(6) | rd(5) | rs1(5) | func2(2) | imm14(14)"""
        ops = instr.operands
        if len(ops) != 3:
            raise ValueError("ALUI instruction requires 3 operands: rd, rs1, imm")
        
        rd = self._parse_register(ops[0])
        rs1 = self._parse_register(ops[1])
        imm = self._parse_immediate(ops[2], 14, signed=True)
        
        imm16 = (func2 << 14) | (imm & 0x3FFF)
        return (OPCODES['ALUI'] << 26) | (rd << 21) | (rs1 << 16) | imm16
    
    def _encode_mul_r(self, instr: Instruction, func: int) -> int:
        """Encode MUL R-type"""
        ops = instr.operands
        rd = self._parse_register(ops[0])
        rs1 = self._parse_register(ops[1])
        rs2 = self._parse_register(ops[2])
        pred = self._get_predicate(instr)
        
        return (OPCODES['MUL'] << 26) | (rd << 21) | (rs1 << 16) | (rs2 << 11) | (pred << 8) | func
    
    def _encode_shift_r(self, instr: Instruction, func: int) -> int:
        """Encode SHIFT R-type"""
        ops = instr.operands
        rd = self._parse_register(ops[0])
        rs1 = self._parse_register(ops[1])
        rs2 = self._parse_register(ops[2])
        pred = self._get_predicate(instr)
        
        return (OPCODES['SHIFT'] << 26) | (rd << 21) | (rs1 << 16) | (rs2 << 11) | (pred << 8) | func
    
    def _encode_shifti(self, instr: Instruction, func2: int) -> int:
        """Encode SHIFT I-type: opcode(6) | rd(5) | rs1(5) | func2(2) | shamt(6) | reserved(8)"""
        ops = instr.operands
        rd = self._parse_register(ops[0])
        rs1 = self._parse_register(ops[1])
        shamt = self._parse_immediate(ops[2], 6, signed=False)
        
        imm16 = (func2 << 14) | (shamt << 8)
        return (OPCODES['SHIFTI'] << 26) | (rd << 21) | (rs1 << 16) | imm16
    
    def _encode_cmp(self, instr: Instruction, func: int) -> int:
        """Encode CMP R-type (sets predicate register)"""
        ops = instr.operands
        pd = self._parse_register(ops[0])  # Predicate destination
        rs1 = self._parse_register(ops[1])
        rs2 = self._parse_register(ops[2]) if len(ops) > 2 else 0
        
        # PD goes in RD field (only bits [2:0] used)
        return (OPCODES['CMP'] << 26) | (pd << 21) | (rs1 << 16) | (rs2 << 11) | (0 << 8) | func
    
    def _encode_load(self, instr: Instruction, opcode: int) -> int:
        """Encode Load: opcode(6) | rd(5) | rbase(5) | pred(3) | offset(13)"""
        ops = instr.operands
        rd = self._parse_register(ops[0])
        offset, base = self._parse_memory_operand(ops[1])
        pred = self._get_predicate(instr)
        
        return (opcode << 26) | (rd << 21) | (base << 16) | (pred << 13) | (offset & 0x1FFF)
    
    def _encode_store(self, instr: Instruction, opcode: int) -> int:
        """Encode Store: opcode(6) | rs(5) | rbase(5) | pred(3) | offset(13)"""
        ops = instr.operands
        rs = self._parse_register(ops[0])
        offset, base = self._parse_memory_operand(ops[1])
        pred = self._get_predicate(instr)
        
        return (opcode << 26) | (rs << 21) | (base << 16) | (pred << 13) | (offset & 0x1FFF)
    
    def _encode_branch(self, instr: Instruction, cond: int) -> int:
        """Encode BRA: opcode(6) | pred(3) | cond(3) | offset20(20)"""
        ops = instr.operands
        
        # Calculate offset from label
        if ops[0] in self.labels:
            target = self.labels[ops[0]]
            offset = (target - instr.address) >> 2  # Word offset
        else:
            offset = self._parse_immediate(ops[0], 20, signed=True)
        
        offset20 = offset & 0xFFFFF
        return (OPCODES['BRA'] << 26) | (0 << 23) | (cond << 20) | offset20
    
    def _encode_brc(self, instr: Instruction) -> int:
        """Encode BRC.cond: opcode(6) | pred(3) | cond(3) | offset20(20)"""
        # Parse condition from mnemonic (BRC.TRUE, BRC.FALSE, etc.)
        parts = instr.mnemonic.split('.')
        if len(parts) < 2:
            cond = BRANCH_CONDS['TRUE']  # Default to TRUE
        else:
            cond_name = parts[1].upper()
            if cond_name not in BRANCH_CONDS:
                raise ValueError(f"Unknown branch condition: {cond_name}")
            cond = BRANCH_CONDS[cond_name]
        
        ops = instr.operands
        pred = self._parse_register(ops[0])
        
        # Calculate offset from label
        if ops[1] in self.labels:
            target = self.labels[ops[1]]
            offset = (target - instr.address) >> 2  # Word offset
        else:
            offset = self._parse_immediate(ops[1], 20, signed=True)
        
        offset20 = offset & 0xFFFFF
        return (OPCODES['BRC'] << 26) | (pred << 23) | (cond << 20) | offset20
    
    def _encode_call(self, instr: Instruction) -> int:
        """Encode CALL"""
        ops = instr.operands
        
        if ops[0] in self.labels:
            target = self.labels[ops[0]]
            offset = (target - instr.address) >> 2
        else:
            offset = self._parse_immediate(ops[0], 20, signed=True)
        
        offset20 = offset & 0xFFFFF
        return (OPCODES['CALL'] << 26) | offset20
    
    def _encode_simple(self, opcode: int) -> int:
        """Encode simple instruction with no operands"""
        return opcode << 26
    
    def _encode_push(self, instr: Instruction) -> int:
        """Encode PUSH"""
        ops = instr.operands
        pred = self._parse_register(ops[0]) if ops else 0
        
        return (OPCODES['PUSH'] << 26) | (pred << 13)
    
    def _encode_bar(self, instr: Instruction) -> int:
        """Encode BAR"""
        ops = instr.operands
        barrier_id = self._parse_immediate(ops[0], 4, signed=False) if ops else 0
        
        return (OPCODES['BAR'] << 26) | barrier_id
    
    def _encode_vote(self, instr: Instruction) -> int:
        """Encode VOTE.ANY, VOTE.ALL, VOTE.NONE"""
        parts = instr.mnemonic.split('.')
        vote_type = parts[1].upper() if len(parts) > 1 else 'ANY'
        func = VOTE_FUNCS.get(vote_type, 0)
        
        ops = instr.operands
        pd = self._parse_register(ops[0])
        pred = self._parse_register(ops[1]) if len(ops) > 1 else 0
        
        return (OPCODES['VOTE'] << 26) | (pd << 21) | (pred << 13) | func
    
    def _encode_ballot(self, instr: Instruction) -> int:
        """Encode BALLOT"""
        ops = instr.operands
        rd = self._parse_register(ops[0])
        pred = self._parse_register(ops[1]) if len(ops) > 1 else 0
        
        return (OPCODES['VOTE'] << 26) | (rd << 21) | (pred << 13) | VOTE_FUNCS['BALLOT']
    
    def _encode_mov(self, instr: Instruction) -> int:
        """Encode MOV (register to register)"""
        ops = instr.operands
        rd = self._parse_register(ops[0])
        rs1 = self._parse_register(ops[1])
        
        return (OPCODES['MOV'] << 26) | (rd << 21) | (rs1 << 16)
    
    def _encode_movi(self, instr: Instruction) -> int:
        """Encode MOVI (immediate to register)"""
        ops = instr.operands
        rd = self._parse_register(ops[0])
        imm = self._parse_immediate(ops[1], 16, signed=True)
        
        return (OPCODES['MOV'] << 26) | (rd << 21) | (0 << 16) | imm
    
    def _encode_movsr(self, instr: Instruction) -> int:
        """Encode MOVSR (special register to register)"""
        ops = instr.operands
        rd = self._parse_register(ops[0])
        
        sr_name = ops[1].upper()
        if sr_name not in SPECIAL_REGS:
            raise ValueError(f"Unknown special register: {sr_name}")
        sr = SPECIAL_REGS[sr_name]
        
        return (OPCODES['MOVSR'] << 26) | (rd << 21) | (sr << 16)
    
    def _encode_lui(self, instr: Instruction) -> int:
        """Encode LUI"""
        ops = instr.operands
        rd = self._parse_register(ops[0])
        imm = self._parse_immediate(ops[1], 16, signed=False)
        
        return (OPCODES['LUI'] << 26) | (rd << 21) | imm
    
    def _encode_auipc(self, instr: Instruction) -> int:
        """Encode AUIPC"""
        ops = instr.operands
        rd = self._parse_register(ops[0])
        imm = self._parse_immediate(ops[1], 16, signed=False)
        
        return (OPCODES['AUIPC'] << 26) | (rd << 21) | imm
    
    def _encode_sel(self, instr: Instruction) -> int:
        """Encode SEL"""
        ops = instr.operands
        rd = self._parse_register(ops[0])
        rs1 = self._parse_register(ops[1])
        rs2 = self._parse_register(ops[2])
        pred = self._parse_register(ops[3]) if len(ops) > 3 else self._get_predicate(instr)
        
        return (OPCODES['SEL'] << 26) | (rd << 21) | (rs1 << 16) | (rs2 << 11) | (pred << 8)
    
    #=========================================================================
    # Floating-Point Encoding Helpers
    #=========================================================================
    
    def _encode_fp_binary(self, instr: Instruction, opcode: int) -> int:
        """Encode FP binary operation: FADD, FSUB, FMUL, FDIV, FMIN, FMAX
        Format: opcode(6) | rd(5) | rs1(5) | rs2(5) | pred(3) | func(8)
        func[7] = precision (0=single, 1=double)
        func[1:0] = rounding mode
        """
        ops = instr.operands
        if len(ops) < 3:
            raise ValueError(f"FP binary instruction requires 3 operands: rd, rs1, rs2")
        
        rd = self._parse_register(ops[0])
        rs1 = self._parse_register(ops[1])
        rs2 = self._parse_register(ops[2])
        pred = self._get_predicate(instr)
        
        # Extract rounding mode from mnemonic modifier (e.g., FADD.RTZ)
        parts = instr.mnemonic.split('.')
        rnd = 0b00  # Default: RNE
        if len(parts) > 1 and parts[1].upper() in FP_ROUND_MODES:
            rnd = FP_ROUND_MODES[parts[1].upper()]
        
        func = rnd  # func[1:0] = rounding mode
        
        return (opcode << 26) | (rd << 21) | (rs1 << 16) | (rs2 << 11) | (pred << 8) | func
    
    def _encode_fp_unary(self, instr: Instruction, opcode: int) -> int:
        """Encode FP unary operation: FSQRT, FABS, FNEG, FRCP, FRSQRT
        Format: opcode(6) | rd(5) | rs1(5) | 0(5) | pred(3) | func(8)
        """
        ops = instr.operands
        if len(ops) < 2:
            raise ValueError(f"FP unary instruction requires 2 operands: rd, rs1")
        
        rd = self._parse_register(ops[0])
        rs1 = self._parse_register(ops[1])
        pred = self._get_predicate(instr)
        
        # Extract rounding mode from mnemonic modifier
        parts = instr.mnemonic.split('.')
        rnd = 0b00  # Default: RNE
        for part in parts[1:]:
            if part.upper() in FP_ROUND_MODES:
                rnd = FP_ROUND_MODES[part.upper()]
                break
        
        func = rnd
        
        return (opcode << 26) | (rd << 21) | (rs1 << 16) | (0 << 11) | (pred << 8) | func
    
    def _encode_fcmp(self, instr: Instruction) -> int:
        """Encode FCMP.cond: Compare and set predicate
        Format: opcode(6) | pd(5) | rs1(5) | rs2(5) | pred(3) | func(8)
        func[3:0] = compare function
        """
        parts = instr.mnemonic.split('.')
        if len(parts) < 2:
            raise ValueError("FCMP requires compare function, e.g., FCMP.EQ")
        
        cmp_name = parts[1].upper()
        if cmp_name not in FCMP_FUNCS:
            raise ValueError(f"Unknown FCMP function: {cmp_name}")
        
        ops = instr.operands
        if len(ops) < 3:
            raise ValueError("FCMP requires 3 operands: pd, rs1, rs2")
        
        pd = self._parse_register(ops[0])
        rs1 = self._parse_register(ops[1])
        rs2 = self._parse_register(ops[2])
        pred = self._get_predicate(instr)
        
        func = FCMP_FUNCS[cmp_name]
        
        return (OPCODES['FCMP'] << 26) | (pd << 21) | (rs1 << 16) | (rs2 << 11) | (pred << 8) | func
    
    def _encode_fcvt(self, instr: Instruction) -> int:
        """Encode FCVT.func: Convert between int/float
        Format: opcode(6) | rd(5) | rs1(5) | 0(5) | pred(3) | func(8)
        func[4:0] = convert function
        """
        parts = instr.mnemonic.split('.')
        if len(parts) < 2:
            raise ValueError("FCVT requires convert function, e.g., FCVT.I2S")
        
        cvt_name = parts[1].upper()
        if cvt_name not in FCVT_FUNCS:
            raise ValueError(f"Unknown FCVT function: {cvt_name}")
        
        ops = instr.operands
        if len(ops) < 2:
            raise ValueError("FCVT requires 2 operands: rd, rs1")
        
        rd = self._parse_register(ops[0])
        rs1 = self._parse_register(ops[1])
        pred = self._get_predicate(instr)
        
        # Extract rounding mode if present
        rnd = 0b00
        for part in parts[2:]:
            if part.upper() in FP_ROUND_MODES:
                rnd = FP_ROUND_MODES[part.upper()]
                break
        
        func = (FCVT_FUNCS[cvt_name] << 2) | rnd
        
        return (OPCODES['FCVT'] << 26) | (rd << 21) | (rs1 << 16) | (0 << 11) | (pred << 8) | func
    
    def _encode_fmadd(self, instr: Instruction) -> int:
        """Encode FMADD: Fused multiply-add (rd = rs1 * rs2 + rs3)
        Format: opcode(6) | rd(5) | rs1(5) | rs2(5) | pred(3) | rs3(5) | rnd(3)
        Note: Using func field for rs3 and rounding mode
        """
        ops = instr.operands
        if len(ops) < 4:
            raise ValueError("FMADD requires 4 operands: rd, rs1, rs2, rs3")
        
        rd = self._parse_register(ops[0])
        rs1 = self._parse_register(ops[1])
        rs2 = self._parse_register(ops[2])
        rs3 = self._parse_register(ops[3])
        pred = self._get_predicate(instr)
        
        # Extract rounding mode from mnemonic modifier
        parts = instr.mnemonic.split('.')
        rnd = 0b00  # Default: RNE
        for part in parts[1:]:
            if part.upper() in FP_ROUND_MODES:
                rnd = FP_ROUND_MODES[part.upper()]
                break
        
        func = (rs3 << 3) | rnd
        
        return (OPCODES['FMADD'] << 26) | (rd << 21) | (rs1 << 16) | (rs2 << 11) | (pred << 8) | func

#=============================================================================
# Output Formatters
#=============================================================================

def output_binary(machine_code: List[int], filename: str):
    """Write raw binary output."""
    with open(filename, 'wb') as f:
        for code in machine_code:
            f.write(code.to_bytes(4, byteorder='little'))

def output_hex(machine_code: List[int], filename: str):
    """Write hex output (one instruction per line)."""
    with open(filename, 'w') as f:
        for code in machine_code:
            f.write(f"{code:08x}\n")

def output_mem(machine_code: List[int], filename: str):
    """Write Verilog $readmemh format."""
    with open(filename, 'w') as f:
        f.write("// GPGPU-1 Machine Code\n")
        f.write("// Format: @address instruction\n")
        for i, code in enumerate(machine_code):
            f.write(f"@{i:04x} {code:08x}\n")

def output_coe(machine_code: List[int], filename: str):
    """Write Xilinx COE format."""
    with open(filename, 'w') as f:
        f.write("; GPGPU-1 Machine Code\n")
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        for i, code in enumerate(machine_code):
            sep = ";" if i == len(machine_code) - 1 else ","
            f.write(f"{code:08x}{sep}\n")

def output_sv(machine_code: List[int], filename: str):
    """Write SystemVerilog array initialization."""
    with open(filename, 'w') as f:
        f.write("// GPGPU-1 Machine Code - SystemVerilog Array\n")
        f.write(f"localparam int PROGRAM_SIZE = {len(machine_code)};\n")
        f.write("logic [31:0] program_mem [PROGRAM_SIZE] = '{\n")
        for i, code in enumerate(machine_code):
            sep = "" if i == len(machine_code) - 1 else ","
            f.write(f"    32'h{code:08x}{sep}  // {i:04x}\n")
        f.write("};\n")

#=============================================================================
# Main
#=============================================================================

def main():
    parser = argparse.ArgumentParser(
        description='GPGPU-1 Assembler',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  %(prog)s program.asm -o program.bin
  %(prog)s program.asm -o program.hex --format hex
  %(prog)s program.asm -o program.mem --format mem
  %(prog)s program.asm -o program.sv --format sv
        '''
    )
    
    parser.add_argument('input', help='Input assembly file')
    parser.add_argument('-o', '--output', required=True, help='Output file')
    parser.add_argument('-f', '--format', 
                        choices=['bin', 'hex', 'mem', 'coe', 'sv'],
                        default='bin',
                        help='Output format (default: bin)')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Verbose output')
    parser.add_argument('--dump', action='store_true',
                        help='Dump parsed instructions')
    
    args = parser.parse_args()
    
    # Read input file
    try:
        with open(args.input, 'r') as f:
            source = f.read()
    except FileNotFoundError:
        print(f"Error: File not found: {args.input}", file=sys.stderr)
        sys.exit(1)
    
    # Parse
    try:
        asm_parser = Parser()
        labels, instructions = asm_parser.parse(source)
        
        if args.verbose:
            print(f"Labels: {labels}")
            print(f"Instructions: {len(instructions)}")
        
        if args.dump:
            print("\nParsed Instructions:")
            for instr in instructions:
                print(f"  {instr.address:04x}: {instr.mnemonic} {instr.operands}")
        
        # Generate code
        codegen = CodeGenerator(labels)
        machine_code = codegen.generate(instructions)
        
        if args.verbose:
            print(f"\nGenerated {len(machine_code)} instructions")
            for i, code in enumerate(machine_code):
                print(f"  {i*4:04x}: {code:08x}")
        
        # Output
        if args.format == 'bin':
            output_binary(machine_code, args.output)
        elif args.format == 'hex':
            output_hex(machine_code, args.output)
        elif args.format == 'mem':
            output_mem(machine_code, args.output)
        elif args.format == 'coe':
            output_coe(machine_code, args.output)
        elif args.format == 'sv':
            output_sv(machine_code, args.output)
        
        print(f"Successfully assembled {len(machine_code)} instructions to {args.output}")
        
    except AssemblerError as e:
        print(f"Assembly error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
