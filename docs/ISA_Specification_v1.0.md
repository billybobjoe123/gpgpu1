# GPGPU-1 Instruction Set Architecture Specification

**Version:** 1.0  
**Date:** December 20, 2025  
**Status:** Draft  

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architectural Parameters](#2-architectural-parameters)
3. [Register File](#3-register-file)
4. [Instruction Formats](#4-instruction-formats)
5. [Opcode Map](#5-opcode-map)
6. [Instruction Reference](#6-instruction-reference)
7. [Memory Model](#7-memory-model)
8. [Divergence Handling](#8-divergence-handling)
9. [Synchronization](#9-synchronization)
10. [Assembly Syntax](#10-assembly-syntax)
11. [Binary Encoding Examples](#11-binary-encoding-examples)
12. [Revision History](#12-revision-history)

---

## 1. Overview

GPGPU-1 is a synthesizable general-purpose GPU architecture designed for FPGA and ASIC implementation. It implements a SIMT (Single Instruction, Multiple Threads) execution model optimized for data-parallel workloads.

### 1.1 Key Features

- Fixed 32-bit instruction encoding
- 64-bit data path and registers
- SIMT execution with 8-thread warps
- Mask-based divergence handling with stack
- Predicated execution
- AXI4 memory interface
- Multi-core scalable design
- Hybrid instruction memory (shared L2 + per-core I-cache)

### 1.2 Design Goals

| Goal | Description |
|------|-------------|
| Synthesizability | All RTL must synthesize on modern FPGAs and ASIC flows |
| Simplicity | Minimal instruction set with orthogonal design |
| Scalability | Architecture scales from 1 to N cores |
| Efficiency | High throughput for parallel workloads |

---

## 2. Architectural Parameters

### 2.1 Fixed Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| INST_WIDTH | 32 | Instruction width in bits |
| DATA_WIDTH | 64 | Data path width in bits |
| REG_WIDTH | 64 | Register width in bits |
| WARP_SIZE | 8 | Number of threads per warp |
| NUM_REGS | 32 | General-purpose registers per thread |
| NUM_PRED | 8 | Predicate registers per thread |
| ADDR_WIDTH | 64 | Address bus width |

### 2.2 Configurable Parameters

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| NUM_CORES | 4 | 1-64 | Number of GPU cores |
| WARPS_PER_CORE | 4 | 1-16 | Warps per core |
| SHARED_MEM_SIZE | 16KB | 4KB-64KB | Shared memory per core |
| ICACHE_SIZE | 4KB | 1KB-16KB | Instruction cache per core |
| MASK_STACK_DEPTH | 8 | 4-16 | Divergence mask stack depth |

### 2.3 Memory Map (Example Configuration)

| Region | Start Address | End Address | Size | Description |
|--------|---------------|-------------|------|-------------|
| Global Memory | 0x0000_0000_0000_0000 | 0x0000_0000_FFFF_FFFF | 4GB | External DDR |
| Shared Memory | 0x0000_0001_0000_0000 | 0x0000_0001_0000_3FFF | 16KB | Per-core scratchpad |
| I/O Space | 0x0000_0002_0000_0000 | 0x0000_0002_0000_FFFF | 64KB | Control registers |

---

## 3. Register File

### 3.1 General Purpose Registers

Each thread has 32 general-purpose 64-bit registers.

| Register | Encoding | Access | Description |
|----------|----------|--------|-------------|
| R0 | 5'b00000 | Read-only | Hardwired to zero |
| R1 | 5'b00001 | Read/Write | General purpose |
| R2 | 5'b00010 | Read/Write | General purpose |
| ... | ... | ... | ... |
| R31 | 5'b11111 | Read/Write | General purpose |

**Note:** Writes to R0 are silently ignored.

### 3.2 Predicate Registers

Each thread has 8 predicate registers (1-bit each).

| Register | Encoding | Access | Description |
|----------|----------|--------|-------------|
| P0 | 3'b000 | Read-only | Hardwired to true (1) |
| P1 | 3'b001 | Read/Write | General purpose |
| P2 | 3'b010 | Read/Write | General purpose |
| P3 | 3'b011 | Read/Write | General purpose |
| P4 | 3'b100 | Read/Write | General purpose |
| P5 | 3'b101 | Read/Write | General purpose |
| P6 | 3'b110 | Read/Write | General purpose |
| P7 | 3'b111 | Read/Write | General purpose |

### 3.3 Special Registers

Read-only registers accessible via MOVSR instruction.

| Register | Encoding | Description |
|----------|----------|-------------|
| SR_TID | 4'b0000 | Thread ID within warp (0 to WARP_SIZE-1) |
| SR_WID | 4'b0001 | Warp ID within core |
| SR_CID | 4'b0010 | Core ID (0 to NUM_CORES-1) |
| SR_BID_X | 4'b0011 | Block ID, X dimension |
| SR_BID_Y | 4'b0100 | Block ID, Y dimension |
| SR_BID_Z | 4'b0101 | Block ID, Z dimension |
| SR_NTID | 4'b0110 | Number of threads per block |
| SR_NCTAID_X | 4'b0111 | Number of blocks, X dimension |
| SR_NCTAID_Y | 4'b1000 | Number of blocks, Y dimension |
| SR_NCTAID_Z | 4'b1001 | Number of blocks, Z dimension |
| SR_CLOCK | 4'b1010 | Clock cycle counter (lower 64 bits) |
| SR_CLOCK_HI | 4'b1011 | Clock cycle counter (upper 64 bits) |

### 3.4 Per-Warp State Registers

These are not directly accessible but maintained by hardware:

| State | Width | Description |
|-------|-------|-------------|
| PC | 64-bit | Program counter |
| ACTIVE_MASK | 8-bit | Current thread active mask |
| MASK_STACK | 8×8-bit | Divergence mask stack |
| MASK_SP | 4-bit | Mask stack pointer |

---

## 4. Instruction Formats

All instructions are 32 bits. Six instruction formats are defined:

### 4.1 Format R: Register-Register

Used for ALU operations with three register operands.

```
  31    26 25   21 20   16 15   11 10    8 7         0
 ┌────────┬───────┬───────┬───────┬───────┬───────────┐
 │ OPCODE │  RD   │  RS1  │  RS2  │ PRED  │   FUNC    │
 │ 6 bits │5 bits │5 bits │5 bits │3 bits │  8 bits   │
 └────────┴───────┴───────┴───────┴───────┴───────────┘
```

| Field | Bits | Description |
|-------|------|-------------|
| OPCODE | [31:26] | Primary opcode |
| RD | [25:21] | Destination register |
| RS1 | [20:16] | Source register 1 |
| RS2 | [15:11] | Source register 2 |
| PRED | [10:8] | Predicate register for conditional execution |
| FUNC | [7:0] | Function code (operation selector) |

### 4.2 Format I: Immediate

Used for ALU operations with immediate operand.

```
  31    26 25   21 20   16 15                        0
 ┌────────┬───────┬───────┬───────────────────────────┐
 │ OPCODE │  RD   │  RS1  │          IMM16            │
 │ 6 bits │5 bits │5 bits │         16 bits           │
 └────────┴───────┴───────┴───────────────────────────┘
```

| Field | Bits | Description |
|-------|------|-------------|
| OPCODE | [31:26] | Primary opcode |
| RD | [25:21] | Destination register |
| RS1 | [20:16] | Source register 1 |
| IMM16 | [15:0] | 16-bit signed immediate |

### 4.3 Format L: Load/Store

Used for memory operations.

```
  31    26 25   21 20   16 15   13 12                0
 ┌────────┬───────┬───────┬───────┬──────────────────┐
 │ OPCODE │ RD/RS │ RBASE │ PRED  │     OFFSET       │
 │ 6 bits │5 bits │5 bits │3 bits │    13 bits       │
 └────────┴───────┴───────┴───────┴──────────────────┘
```

| Field | Bits | Description |
|-------|------|-------------|
| OPCODE | [31:26] | Primary opcode |
| RD/RS | [25:21] | Destination (load) or source (store) register |
| RBASE | [20:16] | Base address register |
| PRED | [15:13] | Predicate register for conditional execution |
| OFFSET | [12:0] | 13-bit signed offset (byte addressed) |

### 4.4 Format B: Branch

Used for control flow operations.

```
  31    26 25   23 22   20 19                        0
 ┌────────┬───────┬───────┬───────────────────────────┐
 │ OPCODE │ PRED  │ COND  │         OFFSET20          │
 │ 6 bits │3 bits │3 bits │  20 bits (signed, ×4)     │
 └────────┴───────┴───────┴───────────────────────────┘
```

| Field | Bits | Description |
|-------|------|-------------|
| OPCODE | [31:26] | Primary opcode |
| PRED | [25:23] | Predicate register to test |
| COND | [22:20] | Branch condition code |
| OFFSET20 | [19:0] | 20-bit signed offset (word aligned, ×4) |

### 4.5 Format S: Special/System

Used for special register access and system operations.

```
  31    26 25   21 20   16 15                        0
 ┌────────┬───────┬───────┬───────────────────────────┐
 │ OPCODE │  RD   │  SR   │         RESERVED          │
 │ 6 bits │5 bits │5 bits │         16 bits           │
 └────────┴───────┴───────┴───────────────────────────┘
```

| Field | Bits | Description |
|-------|------|-------------|
| OPCODE | [31:26] | Primary opcode |
| RD | [25:21] | Destination register |
| SR | [20:16] | Special register selector |
| RESERVED | [15:0] | Reserved for future use |

### 4.6 Format M: Mask/Divergence

Used for divergence control and warp-level operations.

```
  31    26 25   21 20   16 15   13 12                0
 ┌────────┬───────┬───────┬───────┬──────────────────┐
 │ OPCODE │  RD   │  RS1  │ PRED  │      FUNC13      │
 │ 6 bits │5 bits │5 bits │3 bits │     13 bits      │
 └────────┴───────┴───────┴───────┴──────────────────┘
```

| Field | Bits | Description |
|-------|------|-------------|
| OPCODE | [31:26] | Primary opcode |
| RD | [25:21] | Destination register (if applicable) |
| RS1 | [20:16] | Source register (if applicable) |
| PRED | [15:13] | Predicate register |
| FUNC13 | [12:0] | Function code and additional data |

---

## 5. Opcode Map

### 5.1 Primary Opcode Table

| Opcode | Binary | Hex | Mnemonic | Format | Description |
|--------|--------|-----|----------|--------|-------------|
| 0 | 000000 | 0x00 | ALU | R | Integer ALU operations |
| 1 | 000001 | 0x01 | ALUI | I | Integer ALU with immediate |
| 2 | 000010 | 0x02 | MUL | R | Integer multiply operations |
| 3 | 000011 | 0x03 | MULI | I | Integer multiply with immediate |
| 4 | 000100 | 0x04 | SHIFT | R | Shift/rotate operations |
| 5 | 000101 | 0x05 | SHIFTI | I | Shift/rotate with immediate |
| 6 | 000110 | 0x06 | CMP | R | Compare (set predicate) |
| 7 | 000111 | 0x07 | CMPI | I | Compare with immediate |
| 8 | 001000 | 0x08 | LD | L | Load 64-bit from global memory |
| 9 | 001001 | 0x09 | LD32 | L | Load 32-bit unsigned from global |
| 10 | 001010 | 0x0A | LD32S | L | Load 32-bit signed from global |
| 11 | 001011 | 0x0B | LDS | L | Load 64-bit from shared memory |
| 12 | 001100 | 0x0C | ST | L | Store 64-bit to global memory |
| 13 | 001101 | 0x0D | ST32 | L | Store 32-bit to global memory |
| 14 | 001110 | 0x0E | STS | L | Store 64-bit to shared memory |
| 15 | 001111 | 0x0F | LDS32 | L | Load 32-bit from shared memory |
| 16 | 010000 | 0x10 | BRA | B | Unconditional branch |
| 17 | 010001 | 0x11 | BRC | B | Conditional branch |
| 18 | 010010 | 0x12 | CALL | B | Call subroutine |
| 19 | 010011 | 0x13 | RET | S | Return from subroutine |
| 20 | 010100 | 0x14 | EXIT | S | Thread/warp exit |
| 21 | 010101 | 0x15 | BAR | M | Barrier synchronization |
| 22 | 010110 | 0x16 | PUSH | M | Push mask, begin divergence |
| 23 | 010111 | 0x17 | POP | M | Pop mask, reconverge |
| 24 | 011000 | 0x18 | ELSE | M | Switch to else path |
| 25 | 011001 | 0x19 | VOTE | M | Warp voting operations |
| 26 | 011010 | 0x1A | MOV | I | Move register or immediate |
| 27 | 011011 | 0x1B | MOVSR | S | Move from special register |
| 28 | 011100 | 0x1C | SEL | R | Select based on predicate |
| 29 | 011101 | 0x1D | LUI | I | Load upper immediate |
| 30 | 011110 | 0x1E | AUIPC | I | Add upper immediate to PC |
| 31 | 011111 | 0x1F | STS32 | L | Store 32-bit to shared memory |
| 32-47 | 10xxxx | 0x20-0x2F | *reserved* | - | Reserved for floating-point |
| 48-63 | 11xxxx | 0x30-0x3F | *reserved* | - | Reserved for future extensions |

### 5.2 ALU Function Codes (Opcode 0x00)

| FUNC | Binary | Hex | Mnemonic | Operation |
|------|--------|-----|----------|-----------|
| 0 | 00000000 | 0x00 | ADD | RD ← RS1 + RS2 |
| 1 | 00000001 | 0x01 | SUB | RD ← RS1 - RS2 |
| 2 | 00000010 | 0x02 | AND | RD ← RS1 & RS2 |
| 3 | 00000011 | 0x03 | OR | RD ← RS1 \| RS2 |
| 4 | 00000100 | 0x04 | XOR | RD ← RS1 ^ RS2 |
| 5 | 00000101 | 0x05 | NOR | RD ← ~(RS1 \| RS2) |
| 6 | 00000110 | 0x06 | MIN | RD ← min(RS1, RS2) signed |
| 7 | 00000111 | 0x07 | MAX | RD ← max(RS1, RS2) signed |
| 8 | 00001000 | 0x08 | MINU | RD ← min(RS1, RS2) unsigned |
| 9 | 00001001 | 0x09 | MAXU | RD ← max(RS1, RS2) unsigned |
| 10 | 00001010 | 0x0A | ABS | RD ← \|RS1\| |
| 11 | 00001011 | 0x0B | NEG | RD ← -RS1 |
| 12 | 00001100 | 0x0C | NOT | RD ← ~RS1 |
| 13 | 00001101 | 0x0D | CLZ | RD ← count_leading_zeros(RS1) |
| 14 | 00001110 | 0x0E | CTZ | RD ← count_trailing_zeros(RS1) |
| 15 | 00001111 | 0x0F | POPC | RD ← population_count(RS1) |

### 5.3 ALU Immediate Function Encoding (Opcode 0x01)

For immediate operations, the function is encoded in bits [15:14] of IMM16:

| IMM[15:14] | Mnemonic | Operation |
|------------|----------|-----------|
| 00 | ADDI | RD ← RS1 + sign_ext(IMM[13:0]) |
| 01 | ANDI | RD ← RS1 & zero_ext(IMM[13:0]) |
| 10 | ORI | RD ← RS1 \| zero_ext(IMM[13:0]) |
| 11 | XORI | RD ← RS1 ^ zero_ext(IMM[13:0]) |

**Note:** SUBI can be achieved with ADDI using negative immediate.

### 5.4 Multiply Function Codes (Opcode 0x02)

| FUNC | Binary | Hex | Mnemonic | Operation |
|------|--------|-----|----------|-----------|
| 0 | 00000000 | 0x00 | MUL | RD ← (RS1 × RS2)[63:0] |
| 1 | 00000001 | 0x01 | MULH | RD ← (RS1 × RS2)[127:64] signed |
| 2 | 00000010 | 0x02 | MULHU | RD ← (RS1 × RS2)[127:64] unsigned |
| 3 | 00000011 | 0x03 | MULHSU | RD ← (RS1 × RS2)[127:64] signed×unsigned |
| 4 | 00000100 | 0x04 | DIV | RD ← RS1 / RS2 signed |
| 5 | 00000101 | 0x05 | DIVU | RD ← RS1 / RS2 unsigned |
| 6 | 00000110 | 0x06 | REM | RD ← RS1 % RS2 signed |
| 7 | 00000111 | 0x07 | REMU | RD ← RS1 % RS2 unsigned |

### 5.5 Shift Function Codes (Opcode 0x04)

| FUNC | Binary | Hex | Mnemonic | Operation |
|------|--------|-----|----------|-----------|
| 0 | 00000000 | 0x00 | SLL | RD ← RS1 << RS2[5:0] |
| 1 | 00000001 | 0x01 | SRL | RD ← RS1 >> RS2[5:0] logical |
| 2 | 00000010 | 0x02 | SRA | RD ← RS1 >> RS2[5:0] arithmetic |
| 3 | 00000011 | 0x03 | ROL | RD ← rotate_left(RS1, RS2[5:0]) |
| 4 | 00000100 | 0x04 | ROR | RD ← rotate_right(RS1, RS2[5:0]) |

### 5.6 Shift Immediate Encoding (Opcode 0x05)

```
  31    26 25   21 20   16 15   14 13    8 7    6 5        0
 ┌────────┬───────┬───────┬───────┬───────┬──────┬──────────┐
 │ OPCODE │  RD   │  RS1  │ FUNC2 │ SHAMT │ RES  │   RES    │
 │ 6 bits │5 bits │5 bits │2 bits │6 bits │2 bits│  6 bits  │
 └────────┴───────┴───────┴───────┴───────┴──────┴──────────┘
```

| FUNC2 | Mnemonic | Operation |
|-------|----------|-----------|
| 00 | SLLI | RD ← RS1 << SHAMT |
| 01 | SRLI | RD ← RS1 >> SHAMT logical |
| 10 | SRAI | RD ← RS1 >> SHAMT arithmetic |
| 11 | *reserved* | - |

### 5.7 Compare Function Codes (Opcode 0x06)

| FUNC | Binary | Hex | Mnemonic | Operation |
|------|--------|-----|----------|-----------|
| 0 | 00000000 | 0x00 | SEQ | P[RD[2:0]] ← (RS1 == RS2) |
| 1 | 00000001 | 0x01 | SNE | P[RD[2:0]] ← (RS1 ≠ RS2) |
| 2 | 00000010 | 0x02 | SLT | P[RD[2:0]] ← (RS1 < RS2) signed |
| 3 | 00000011 | 0x03 | SLE | P[RD[2:0]] ← (RS1 ≤ RS2) signed |
| 4 | 00000100 | 0x04 | SGT | P[RD[2:0]] ← (RS1 > RS2) signed |
| 5 | 00000101 | 0x05 | SGE | P[RD[2:0]] ← (RS1 ≥ RS2) signed |
| 6 | 00000110 | 0x06 | SLTU | P[RD[2:0]] ← (RS1 < RS2) unsigned |
| 7 | 00000111 | 0x07 | SLEU | P[RD[2:0]] ← (RS1 ≤ RS2) unsigned |
| 8 | 00001000 | 0x08 | SGTU | P[RD[2:0]] ← (RS1 > RS2) unsigned |
| 9 | 00001001 | 0x09 | SGEU | P[RD[2:0]] ← (RS1 ≥ RS2) unsigned |
| 10 | 00001010 | 0x0A | PAND | P[RD[2:0]] ← P[RS1[2:0]] & P[RS2[2:0]] |
| 11 | 00001011 | 0x0B | POR | P[RD[2:0]] ← P[RS1[2:0]] \| P[RS2[2:0]] |
| 12 | 00001100 | 0x0C | PXOR | P[RD[2:0]] ← P[RS1[2:0]] ^ P[RS2[2:0]] |
| 13 | 00001101 | 0x0D | PNOT | P[RD[2:0]] ← ~P[RS1[2:0]] |

### 5.8 Branch Condition Codes (Format B)

| COND | Binary | Mnemonic | Condition |
|------|--------|----------|-----------|
| 0 | 000 | ALWAYS | Always branch (unconditional) |
| 1 | 001 | TRUE | Branch if P[PRED] == 1 |
| 2 | 010 | FALSE | Branch if P[PRED] == 0 |
| 3 | 011 | ANY | Branch if any active thread has P[PRED]==1 |
| 4 | 100 | ALL | Branch if all active threads have P[PRED]==1 |
| 5 | 101 | NONE | Branch if no active thread has P[PRED]==1 |
| 6 | 110 | *reserved* | - |
| 7 | 111 | *reserved* | - |

### 5.9 Vote Function Codes (Opcode 0x19)

| FUNC13[3:0] | Mnemonic | Operation |
|-------------|----------|-----------|
| 0000 | VOTE_ANY | P[RD] ← any active thread has P[PRED]==1 |
| 0001 | VOTE_ALL | P[RD] ← all active threads have P[PRED]==1 |
| 0010 | VOTE_NONE | P[RD] ← no active thread has P[PRED]==1 |
| 0011 | VOTE_BALLOT | RD ← ballot of P[PRED] across all threads |
| 0100 | POPC_BALLOT | RD ← popcount(ballot of P[PRED]) |

---

## 6. Instruction Reference

### 6.1 Integer Arithmetic Instructions

#### ADD - Add

**Format:** R  
**Encoding:** `000000 | RD | RS1 | RS2 | PRED | 00000000`  
**Syntax:** `ADD RD, RS1, RS2`  
**Operation:**
```
for each thread t where active_mask[t] && P[t][PRED]:
    R[t][RD] ← R[t][RS1] + R[t][RS2]
```
**Flags:** None  
**Exceptions:** None

#### ADDI - Add Immediate

**Format:** I  
**Encoding:** `000001 | RD | RS1 | 00 | IMM14`  
**Syntax:** `ADDI RD, RS1, IMM`  
**Operation:**
```
for each thread t where active_mask[t]:
    R[t][RD] ← R[t][RS1] + sign_extend(IMM14)
```

#### SUB - Subtract

**Format:** R  
**Encoding:** `000000 | RD | RS1 | RS2 | PRED | 00000001`  
**Syntax:** `SUB RD, RS1, RS2`  
**Operation:**
```
for each thread t where active_mask[t] && P[t][PRED]:
    R[t][RD] ← R[t][RS1] - R[t][RS2]
```

#### MUL - Multiply (Low 64 bits)

**Format:** R  
**Encoding:** `000010 | RD | RS1 | RS2 | PRED | 00000000`  
**Syntax:** `MUL RD, RS1, RS2`  
**Operation:**
```
for each thread t where active_mask[t] && P[t][PRED]:
    R[t][RD] ← (R[t][RS1] × R[t][RS2])[63:0]
```

#### DIV - Signed Divide

**Format:** R  
**Encoding:** `000010 | RD | RS1 | RS2 | PRED | 00000100`  
**Syntax:** `DIV RD, RS1, RS2`  
**Operation:**
```
for each thread t where active_mask[t] && P[t][PRED]:
    if R[t][RS2] == 0:
        R[t][RD] ← -1  // Division by zero returns -1
    else:
        R[t][RD] ← R[t][RS1] / R[t][RS2]  // Signed division
```

### 6.2 Logical Instructions

#### AND - Bitwise AND

**Format:** R  
**Encoding:** `000000 | RD | RS1 | RS2 | PRED | 00000010`  
**Syntax:** `AND RD, RS1, RS2`  
**Operation:**
```
for each thread t where active_mask[t] && P[t][PRED]:
    R[t][RD] ← R[t][RS1] & R[t][RS2]
```

#### OR - Bitwise OR

**Format:** R  
**Encoding:** `000000 | RD | RS1 | RS2 | PRED | 00000011`  
**Syntax:** `OR RD, RS1, RS2`  

#### XOR - Bitwise XOR

**Format:** R  
**Encoding:** `000000 | RD | RS1 | RS2 | PRED | 00000100`  
**Syntax:** `XOR RD, RS1, RS2`  

#### NOT - Bitwise NOT

**Format:** R  
**Encoding:** `000000 | RD | RS1 | 00000 | PRED | 00001100`  
**Syntax:** `NOT RD, RS1`  
**Operation:**
```
for each thread t where active_mask[t] && P[t][PRED]:
    R[t][RD] ← ~R[t][RS1]
```

### 6.3 Shift Instructions

#### SLL - Shift Left Logical

**Format:** R  
**Encoding:** `000100 | RD | RS1 | RS2 | PRED | 00000000`  
**Syntax:** `SLL RD, RS1, RS2`  
**Operation:**
```
for each thread t where active_mask[t] && P[t][PRED]:
    shamt ← R[t][RS2][5:0]
    R[t][RD] ← R[t][RS1] << shamt
```

#### SLLI - Shift Left Logical Immediate

**Format:** I (special encoding)  
**Encoding:** `000101 | RD | RS1 | 00 | SHAMT6 | 00000000`  
**Syntax:** `SLLI RD, RS1, SHAMT`  
**Operation:**
```
for each thread t where active_mask[t]:
    R[t][RD] ← R[t][RS1] << SHAMT
```

### 6.4 Memory Instructions

#### LD - Load 64-bit

**Format:** L  
**Encoding:** `001000 | RD | RBASE | PRED | OFFSET13`  
**Syntax:** `LD RD, OFFSET(RBASE)`  
**Operation:**
```
for each thread t where active_mask[t] && P[t][PRED]:
    addr ← R[t][RBASE] + sign_extend(OFFSET13)
    R[t][RD] ← memory[addr]  // 64-bit load
```
**Alignment:** Address must be 8-byte aligned  
**Memory Space:** Global memory

#### LD32 - Load 32-bit Unsigned

**Format:** L  
**Encoding:** `001001 | RD | RBASE | PRED | OFFSET13`  
**Syntax:** `LD32 RD, OFFSET(RBASE)`  
**Operation:**
```
for each thread t where active_mask[t] && P[t][PRED]:
    addr ← R[t][RBASE] + sign_extend(OFFSET13)
    R[t][RD] ← zero_extend(memory[addr][31:0])
```
**Alignment:** Address must be 4-byte aligned

#### LD32S - Load 32-bit Signed

**Format:** L  
**Encoding:** `001010 | RD | RBASE | PRED | OFFSET13`  
**Syntax:** `LD32S RD, OFFSET(RBASE)`  
**Operation:**
```
for each thread t where active_mask[t] && P[t][PRED]:
    addr ← R[t][RBASE] + sign_extend(OFFSET13)
    R[t][RD] ← sign_extend(memory[addr][31:0])
```

#### LDS - Load from Shared Memory

**Format:** L  
**Encoding:** `001011 | RD | RBASE | PRED | OFFSET13`  
**Syntax:** `LDS RD, OFFSET(RBASE)`  
**Operation:**
```
for each thread t where active_mask[t] && P[t][PRED]:
    addr ← R[t][RBASE] + sign_extend(OFFSET13)
    R[t][RD] ← shared_memory[addr]
```
**Memory Space:** Shared memory (per-core scratchpad)

#### ST - Store 64-bit

**Format:** L  
**Encoding:** `001100 | RS | RBASE | PRED | OFFSET13`  
**Syntax:** `ST RS, OFFSET(RBASE)`  
**Operation:**
```
for each thread t where active_mask[t] && P[t][PRED]:
    addr ← R[t][RBASE] + sign_extend(OFFSET13)
    memory[addr] ← R[t][RS]
```

#### ST32 - Store 32-bit

**Format:** L  
**Encoding:** `001101 | RS | RBASE | PRED | OFFSET13`  
**Syntax:** `ST32 RS, OFFSET(RBASE)`  
**Operation:**
```
for each thread t where active_mask[t] && P[t][PRED]:
    addr ← R[t][RBASE] + sign_extend(OFFSET13)
    memory[addr][31:0] ← R[t][RS][31:0]
```

#### STS - Store to Shared Memory

**Format:** L  
**Encoding:** `001110 | RS | RBASE | PRED | OFFSET13`  
**Syntax:** `STS RS, OFFSET(RBASE)`  

### 6.5 Control Flow Instructions

#### BRA - Branch Always

**Format:** B  
**Encoding:** `010000 | 000 | 000 | OFFSET20`  
**Syntax:** `BRA LABEL`  
**Operation:**
```
PC ← PC + sign_extend(OFFSET20 << 2)
```
**Note:** All active threads branch together.

#### BRC - Branch Conditional

**Format:** B  
**Encoding:** `010001 | PRED | COND | OFFSET20`  
**Syntax:** `BRC.cond PRED, LABEL`  
**Operation:**
```
condition_met ← evaluate_condition(COND, PRED, active_mask)
if condition_met:
    PC ← PC + sign_extend(OFFSET20 << 2)
else:
    PC ← PC + 4
```

#### CALL - Call Subroutine

**Format:** B  
**Encoding:** `010010 | 000 | 000 | OFFSET20`  
**Syntax:** `CALL LABEL`  
**Operation:**
```
// Push return address (implementation-defined mechanism)
return_stack.push(PC + 4)
PC ← PC + sign_extend(OFFSET20 << 2)
```

#### RET - Return from Subroutine

**Format:** S  
**Encoding:** `010011 | 00000 | 00000 | 0000000000000000`  
**Syntax:** `RET`  
**Operation:**
```
PC ← return_stack.pop()
```

#### EXIT - Thread/Warp Exit

**Format:** S  
**Encoding:** `010100 | 00000 | 00000 | 0000000000000000`  
**Syntax:** `EXIT`  
**Operation:**
```
for each thread t where active_mask[t]:
    thread_active[t] ← 0
if all threads inactive:
    warp_terminated ← 1
```

### 6.6 Divergence Control Instructions

#### PUSH - Push Mask (Begin Divergent Section)

**Format:** M  
**Encoding:** `010110 | 00000 | 00000 | PRED | 0000000000000`  
**Syntax:** `PUSH PRED`  
**Operation:**
```
mask_stack.push(active_mask)
new_mask ← 0
for each thread t where active_mask[t]:
    new_mask[t] ← P[t][PRED]
active_mask ← new_mask
```
**Note:** Must be followed by ELSE and POP instructions.

#### ELSE - Switch to Else Path

**Format:** M  
**Encoding:** `011000 | 00000 | 00000 | 000 | 0000000000000`  
**Syntax:** `ELSE`  
**Operation:**
```
// Flip to threads that were inactive in THEN path
active_mask ← mask_stack.top() & ~active_mask
```
**Note:** Must appear between PUSH and POP.

#### POP - Pop Mask (Reconverge)

**Format:** M  
**Encoding:** `010111 | 00000 | 00000 | 000 | 0000000000000`  
**Syntax:** `POP`  
**Operation:**
```
active_mask ← mask_stack.pop()
```
**Note:** Restores mask from before PUSH.

### 6.7 Synchronization Instructions

#### BAR - Barrier Synchronization

**Format:** M  
**Encoding:** `010101 | 00000 | 00000 | 000 | BARRIER_ID`  
**Syntax:** `BAR BARRIER_ID`  
**Operation:**
```
// All warps in thread block must reach barrier before any proceed
barrier_wait(BARRIER_ID)
// Memory fence: all prior memory operations complete
memory_fence()
```
**BARRIER_ID Range:** 0-15 (4 bits used from FUNC13)

### 6.8 Data Movement Instructions

#### MOV - Move Register/Immediate

**Format:** I  
**Encoding:** `011010 | RD | RS1 | IMM16`  
**Syntax:** `MOV RD, RS1` or `MOVI RD, IMM16`  
**Operation:**
```
if RS1 == 0:
    // Immediate move
    for each thread t where active_mask[t]:
        R[t][RD] ← sign_extend(IMM16)
else:
    // Register move
    for each thread t where active_mask[t]:
        R[t][RD] ← R[t][RS1]
```

#### MOVSR - Move from Special Register

**Format:** S  
**Encoding:** `011011 | RD | SR | 0000000000000000`  
**Syntax:** `MOVSR RD, SR`  
**Operation:**
```
for each thread t where active_mask[t]:
    R[t][RD] ← special_register[SR]
```
**Note:** Some special registers return per-thread values (e.g., TID), others return per-warp/block values.

#### LUI - Load Upper Immediate

**Format:** I  
**Encoding:** `011101 | RD | 00000 | IMM16`  
**Syntax:** `LUI RD, IMM16`  
**Operation:**
```
for each thread t where active_mask[t]:
    R[t][RD] ← {IMM16, 48'b0}  // IMM16 in bits [63:48]
```
**Note:** Used with ORI to construct 64-bit constants.

#### SEL - Select Based on Predicate

**Format:** R  
**Encoding:** `011100 | RD | RS1 | RS2 | PRED | 00000000`  
**Syntax:** `SEL RD, RS1, RS2, PRED`  
**Operation:**
```
for each thread t where active_mask[t]:
    if P[t][PRED]:
        R[t][RD] ← R[t][RS1]
    else:
        R[t][RD] ← R[t][RS2]
```

### 6.9 Comparison Instructions

#### SEQ - Set Predicate if Equal

**Format:** R  
**Encoding:** `000110 | PD | RS1 | RS2 | 000 | 00000000`  
**Syntax:** `SEQ PD, RS1, RS2`  
**Operation:**
```
for each thread t where active_mask[t]:
    P[t][PD] ← (R[t][RS1] == R[t][RS2])
```
**Note:** PD is encoded in RD[2:0], RD[4:3] ignored.

#### SLT - Set Predicate if Less Than (Signed)

**Format:** R  
**Encoding:** `000110 | PD | RS1 | RS2 | 000 | 00000010`  
**Syntax:** `SLT PD, RS1, RS2`  
**Operation:**
```
for each thread t where active_mask[t]:
    P[t][PD] ← (signed(R[t][RS1]) < signed(R[t][RS2]))
```

### 6.10 Warp Voting Instructions

#### VOTE_ANY - Vote Any

**Format:** M  
**Encoding:** `011001 | PD | 00000 | PRED | 0000000000000`  
**Syntax:** `VOTE.ANY PD, PRED`  
**Operation:**
```
result ← 0
for each thread t where active_mask[t]:
    result ← result | P[t][PRED]
for each thread t where active_mask[t]:
    P[t][PD] ← result
```

#### VOTE_ALL - Vote All

**Format:** M  
**Encoding:** `011001 | PD | 00000 | PRED | 0000000000001`  
**Syntax:** `VOTE.ALL PD, PRED`  
**Operation:**
```
result ← 1
for each thread t where active_mask[t]:
    result ← result & P[t][PRED]
for each thread t where active_mask[t]:
    P[t][PD] ← result
```

#### BALLOT - Ballot

**Format:** M  
**Encoding:** `011001 | RD | 00000 | PRED | 0000000000011`  
**Syntax:** `BALLOT RD, PRED`  
**Operation:**
```
ballot ← 0
for each thread t where active_mask[t]:
    ballot[t] ← P[t][PRED]
for each thread t where active_mask[t]:
    R[t][RD] ← ballot
```

---

## 7. Memory Model

### 7.1 Memory Spaces

| Space | Scope | Latency | Size | Access |
|-------|-------|---------|------|--------|
| Global | All cores | High (~100+ cycles) | GBs | R/W |
| Shared | Per-core (block) | Low (~4-8 cycles) | 16-64KB | R/W |
| Registers | Per-thread | 0 cycles | 32×64b | R/W |

### 7.2 Memory Coalescing

When threads in a warp access consecutive memory addresses, the hardware coalesces these into wider memory transactions:

**Coalesced Access (Optimal):**
```
Thread 0: addr = base + 0
Thread 1: addr = base + 8
Thread 2: addr = base + 16
...
→ Single 512-bit (64B) transaction
```

**Strided Access (Suboptimal):**
```
Thread 0: addr = base + 0
Thread 1: addr = base + 256
Thread 2: addr = base + 512
...
→ Multiple transactions
```

### 7.3 Memory Ordering

Within a warp:
- All memory operations appear to execute in program order
- Loads return values from most recent store to same address

Between warps:
- No ordering guarantees without explicit synchronization
- BAR instruction provides memory fence

### 7.4 Atomics (Future Extension)

Reserved opcodes 0x20-0x2F will include:
- ATOM.ADD, ATOM.MIN, ATOM.MAX
- ATOM.AND, ATOM.OR, ATOM.XOR
- ATOM.EXCH, ATOM.CAS

---

## 8. Divergence Handling

### 8.1 SIMT Execution Model

All threads in a warp execute the same instruction. When threads need different control paths, divergence handling is used.

### 8.2 Mask Stack

Each warp maintains:
- **active_mask[7:0]**: Currently active threads
- **mask_stack[DEPTH][7:0]**: Stack of saved masks
- **mask_sp[3:0]**: Stack pointer

### 8.3 Divergence Example

Source code:
```c
if (x > 0) {
    a = 1;
} else {
    a = -1;
}
b = a + 1;
```

Assembly:
```asm
    CMPI    P1, R5, 0       ; P1 = (x > 0) for each thread
    PUSH    P1              ; Save mask, then-mask = threads where P1=1
    
    ; THEN path (only threads with x > 0)
    MOVI    R6, 1           ; a = 1
    
    ELSE                    ; Switch to else-mask
    
    ; ELSE path (only threads with x <= 0)
    MOVI    R6, -1          ; a = -1
    
    POP                     ; Reconverge, restore original mask
    
    ADDI    R7, R6, 1       ; b = a + 1 (all threads)
```

### 8.4 Nested Divergence

Maximum nesting depth = MASK_STACK_DEPTH (default 8).

```asm
    PUSH    P1          ; Level 1
    ...
    PUSH    P2          ; Level 2
    ...
    POP                 ; Back to level 1
    ELSE                ; Level 1 else
    PUSH    P3          ; Level 2 in else branch
    ...
    POP                 ; Back to level 1
    POP                 ; Back to level 0
```

### 8.5 Stack Overflow

If PUSH is executed when stack is full:
- Hardware exception raised
- Warp is terminated
- Implementation should set error status register

---

## 9. Synchronization

### 9.1 Barrier Synchronization

BAR instruction synchronizes all warps in a thread block:

1. All warps must reach the barrier
2. Memory fence is applied
3. All warps proceed together

```asm
    ; All threads in block write to shared memory
    STS     R1, 0(R10)
    
    BAR     0               ; Barrier 0, wait for all warps
    
    ; Now safe to read values written by other threads
    LDS     R2, 0(R11)
```

### 9.2 Memory Fences

BAR includes implicit memory fence. Explicit fence reserved for future:
- MEMBAR.CTA: Thread block scope
- MEMBAR.GPU: Device scope
- MEMBAR.SYS: System scope

---

## 10. Assembly Syntax

### 10.1 General Syntax

```asm
[LABEL:]    MNEMONIC[.MOD]    OPERANDS    [; COMMENT]
```

### 10.2 Register Notation

| Notation | Meaning |
|----------|---------|
| R0-R31 | General purpose registers |
| P0-P7 | Predicate registers |
| SR_TID, etc. | Special registers |

### 10.3 Immediate Values

| Format | Example | Meaning |
|--------|---------|---------|
| Decimal | 42 | Decimal number |
| Hex | 0x2A | Hexadecimal |
| Binary | 0b101010 | Binary |
| Negative | -5 | Negative decimal |

### 10.4 Memory Operands

```asm
LD      RD, OFFSET(RBASE)   ; Load from RBASE + OFFSET
ST      RS, OFFSET(RBASE)   ; Store to RBASE + OFFSET
```

### 10.5 Predicated Execution

```asm
@P1     ADD     R1, R2, R3  ; Execute only if P1 is true
@!P2    SUB     R4, R5, R6  ; Execute only if P2 is false
```

### 10.6 Labels

```asm
loop:
        ADDI    R1, R1, 1
        SLT     P1, R1, R10
        BRC.TRUE P1, loop
```

---

## 11. Binary Encoding Examples

### 11.1 ADD R3, R1, R2

```
Opcode: 000000 (ALU)
RD:     00011 (R3)
RS1:    00001 (R1)
RS2:    00010 (R2)
PRED:   000 (P0 = always)
FUNC:   00000000 (ADD)

Binary: 0000 0000 0110 0001 0001 0000 0000 0000
Hex:    0x00610000
```

### 11.2 LD R5, 16(R10)

```
Opcode: 001000 (LD)
RD:     00101 (R5)
RBASE:  01010 (R10)
PRED:   000 (P0)
OFFSET: 0000000010000 (16)

Binary: 0010 0000 1010 1010 0000 0000 0001 0000
Hex:    0x20AA0010
```

### 11.3 BRC.TRUE P1, -8 (branch back 2 instructions)

```
Opcode: 010001 (BRC)
PRED:   001 (P1)
COND:   001 (TRUE)
OFFSET: 11111111111111111110 (-2 in words = -8 bytes)

Binary: 0100 0100 1001 1111 1111 1111 1111 1110
Hex:    0x449FFFFE
```

### 11.4 PUSH P2

```
Opcode: 010110 (PUSH)
RD:     00000 (unused)
RS1:    00000 (unused)
PRED:   010 (P2)
FUNC13: 0000000000000

Binary: 0101 1000 0000 0000 0100 0000 0000 0000
Hex:    0x58004000
```

---

## 12. Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-20 | - | Initial specification |

---

## Appendix A: Instruction Encoding Quick Reference

```
Format R:  OOOOOO DDDDD SSSSS sssss PPP FFFFFFFF
Format I:  OOOOOO DDDDD SSSSS IIIIIIIIIIIIIIII
Format L:  OOOOOO DDDDD BBBBB PPP OOOOOOOOOOOOO
Format B:  OOOOOO PPP CCC OOOOOOOOOOOOOOOOOOOO
Format S:  OOOOOO DDDDD RRRRR RRRRRRRRRRRRRRRR
Format M:  OOOOOO DDDDD SSSSS PPP FFFFFFFFFFFFF

O = Opcode
D = Destination register
S = Source register
s = Source register 2
P = Predicate register
F = Function code
I = Immediate
B = Base register
C = Condition code
R = Reserved/Special register
```

---

## Appendix B: Complete Opcode Encoding Table

| Opcode[5:0] | Hex | Instruction | Format |
|-------------|-----|-------------|--------|
| 000000 | 0x00 | ALU | R |
| 000001 | 0x01 | ALUI | I |
| 000010 | 0x02 | MUL | R |
| 000011 | 0x03 | MULI | I |
| 000100 | 0x04 | SHIFT | R |
| 000101 | 0x05 | SHIFTI | I |
| 000110 | 0x06 | CMP | R |
| 000111 | 0x07 | CMPI | I |
| 001000 | 0x08 | LD | L |
| 001001 | 0x09 | LD32 | L |
| 001010 | 0x0A | LD32S | L |
| 001011 | 0x0B | LDS | L |
| 001100 | 0x0C | ST | L |
| 001101 | 0x0D | ST32 | L |
| 001110 | 0x0E | STS | L |
| 001111 | 0x0F | LDS32 | L |
| 010000 | 0x10 | BRA | B |
| 010001 | 0x11 | BRC | B |
| 010010 | 0x12 | CALL | B |
| 010011 | 0x13 | RET | S |
| 010100 | 0x14 | EXIT | S |
| 010101 | 0x15 | BAR | M |
| 010110 | 0x16 | PUSH | M |
| 010111 | 0x17 | POP | M |
| 011000 | 0x18 | ELSE | M |
| 011001 | 0x19 | VOTE | M |
| 011010 | 0x1A | MOV | I |
| 011011 | 0x1B | MOVSR | S |
| 011100 | 0x1C | SEL | R |
| 011101 | 0x1D | LUI | I |
| 011110 | 0x1E | AUIPC | I |
| 011111 | 0x1F | STS32 | L |
| 100000-101111 | 0x20-0x2F | *Reserved (FP)* | - |
| 110000-111111 | 0x30-0x3F | *Reserved* | - |

---

**End of Specification**
