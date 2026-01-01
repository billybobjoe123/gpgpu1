; GPGPU-1 Test Program: FPU Integration Test
; ============================================
; Tests floating-point operations including:
; - Single precision: FADD, FSUB, FMUL, FDIV
; - FMA (Fused Multiply-Add)
; - Min/Max/Abs/Neg
; - Double precision operations (func[7]=1)
;
; Memory Layout:
;   0x100-0x13F: Input A (8 floats, 32-bit each at 8-byte aligned)
;   0x200-0x23F: Input B (8 floats)
;   0x300-0x33F: Input C (8 floats, for FMA)
;   0x400-0x43F: Output results
;   0x500-0x53F: Expected results (for verification)
;
; Register usage:
;   R1  = thread ID
;   R2  = base address of A
;   R3  = base address of B
;   R4  = base address of C
;   R5  = base address of output
;   R10 = offset = tid * 8
;   R11 = A[tid]
;   R12 = B[tid]
;   R13 = C[tid]
;   R14-R20 = computation results

start:
    ; Get thread ID
    MOVSR   R1, SR_TID          ; R1 = tid (0-7)
    
    ; Setup base addresses
    MOVI    R2, 0x100           ; A base
    MOVI    R3, 0x200           ; B base
    MOVI    R4, 0x300           ; C base
    MOVI    R5, 0x400           ; Output base
    
    ; Calculate offset = tid * 8
    MOVI    R6, 8
    MUL     R10, R1, R6         ; R10 = tid * 8
    
    ; Calculate addresses
    ADD     R2, R2, R10         ; &A[tid]
    ADD     R3, R3, R10         ; &B[tid]
    ADD     R4, R4, R10         ; &C[tid]
    
    ; Load input values (as 64-bit containing 32-bit floats in lower bits)
    LD      R11, 0(R2)          ; R11 = A[tid]
    LD      R12, 0(R3)          ; R12 = B[tid]
    LD      R13, 0(R4)          ; R13 = C[tid]
    
    ;=========================================================================
    ; Test 1: FADD - Floating Point Addition
    ;=========================================================================
    FADD    R14, R11, R12       ; R14 = A + B
    
    ;=========================================================================
    ; Test 2: FSUB - Floating Point Subtraction
    ;=========================================================================
    FSUB    R15, R11, R12       ; R15 = A - B
    
    ;=========================================================================
    ; Test 3: FMUL - Floating Point Multiplication
    ;=========================================================================
    FMUL    R16, R11, R12       ; R16 = A * B
    
    ;=========================================================================
    ; Test 4: FDIV - Floating Point Division
    ;=========================================================================
    FDIV    R17, R11, R12       ; R17 = A / B
    
    ;=========================================================================
    ; Test 5: FMADD - Fused Multiply-Add
    ;=========================================================================
    ; FMA: R18 = A * B + C (single rounding)
    FMADD   R18, R11, R12, R13
    
    ;=========================================================================
    ; Test 6: FMIN/FMAX
    ;=========================================================================
    FMIN    R19, R11, R12       ; R19 = min(A, B)
    FMAX    R20, R11, R12       ; R20 = max(A, B)
    
    ;=========================================================================
    ; Test 7: FABS/FNEG
    ;=========================================================================
    FABS    R21, R11            ; R21 = |A|
    FNEG    R22, R11            ; R22 = -A
    
    ;=========================================================================
    ; Store Results
    ;=========================================================================
    ; Calculate output addresses (offset per test result)
    ADD     R5, R5, R10         ; Base output + thread offset
    
    ; Store FADD result
    ST      R14, 0(R5)
    
    ; Store other results with offsets
    ADDI    R5, R5, 64          ; Next result block
    ST      R15, 0(R5)          ; FSUB
    
    ADDI    R5, R5, 64
    ST      R16, 0(R5)          ; FMUL
    
    ADDI    R5, R5, 64
    ST      R17, 0(R5)          ; FDIV
    
    ADDI    R5, R5, 64
    ST      R18, 0(R5)          ; FMADD
    
    ADDI    R5, R5, 64
    ST      R19, 0(R5)          ; FMIN
    
    ADDI    R5, R5, 64
    ST      R20, 0(R5)          ; FMAX
    
    ADDI    R5, R5, 64
    ST      R21, 0(R5)          ; FABS
    
    ADDI    R5, R5, 64
    ST      R22, 0(R5)          ; FNEG
    
    ; Done
    EXIT
