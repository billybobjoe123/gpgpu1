; GPGPU-1 Test Program: Matrix-Vector Multiply
; ==============================================
; Computes y = A * x where:
;   A is an 8x8 matrix (row-major)
;   x is an 8-element vector
;   y is an 8-element result vector
;
; Each thread computes one element of y:
;   y[tid] = sum(A[tid][j] * x[j] for j in 0..7)
;
; Uses:
;   - Floating-point FMUL and FADD (or FMA)
;   - Memory loads
;   - Loop constructs
;
; Memory Layout:
;   0x000-0x1FF: Matrix A (8x8 = 64 elements, 8 bytes each)
;   0x200-0x23F: Vector x (8 elements)
;   0x300-0x33F: Vector y (output, 8 elements)
;
; Register usage:
;   R1  = thread ID (row index i)
;   R2  = loop counter j (column index)
;   R3  = A base address
;   R4  = x base address
;   R5  = y base address
;   R6  = current A[i][j] address
;   R7  = current x[j] address
;   R10 = row offset = tid * 8 * 8 = tid * 64 bytes
;   R11 = A[i][j] value
;   R12 = x[j] value
;   R13 = product = A[i][j] * x[j]
;   R14 = accumulator (sum)
;   R15 = loop limit

start:
    ; Get thread ID (each thread computes one row of result)
    MOVSR   R1, SR_TID          ; R1 = tid = row index i
    
    ; Setup base addresses
    MOVI    R3, 0x000           ; A base (matrix)
    MOVI    R4, 0x200           ; x base (input vector)
    MOVI    R5, 0x300           ; y base (output vector)
    
    ; Calculate row offset for matrix A
    ; Row i starts at A + i * 8 * 8 = A + i * 64
    MOVI    R6, 64
    MUL     R10, R1, R6         ; R10 = tid * 64 (row offset in bytes)
    ADD     R3, R3, R10         ; R3 = &A[tid][0]
    
    ; Initialize accumulator to 0.0
    ; In IEEE 754, 0.0 = 0x00000000
    MOVI    R14, 0              ; R14 = 0.0 (accumulator)
    
    ; Initialize loop counter
    MOVI    R2, 0               ; j = 0
    MOVI    R15, 8              ; loop limit
    
loop:
    ; Calculate A[i][j] address = A_row_base + j * 8
    MOVI    R6, 8
    MUL     R7, R2, R6          ; R7 = j * 8
    ADD     R6, R3, R7          ; R6 = &A[i][j]
    
    ; Calculate x[j] address = x_base + j * 8
    ADD     R7, R4, R7          ; R7 = &x[j] (reuse R7)
    
    ; Load A[i][j] and x[j]
    LD      R11, 0(R6)          ; R11 = A[i][j]
    LD      R12, 0(R7)          ; R12 = x[j]
    
    ; Compute product and accumulate
    ; Using FMA would be better: R14 = R11 * R12 + R14
    FMUL    R13, R11, R12       ; R13 = A[i][j] * x[j]
    FADD    R14, R14, R13       ; R14 += product
    
    ; Increment loop counter
    ADDI    R2, R2, 1           ; j++
    
    ; Check loop condition
    SLT     P1, R2, R15         ; P1 = (j < 8)
    BRC.TRUE P1, loop           ; Branch if P1 is true
    
    ; Store result y[tid]
    MOVI    R6, 8
    MUL     R7, R1, R6          ; R7 = tid * 8
    ADD     R5, R5, R7          ; R5 = &y[tid]
    ST      R14, 0(R5)          ; y[tid] = accumulator
    
    ; Done
    EXIT
