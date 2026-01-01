; GPGPU-1 Test Program: Parallel Dot Product with Shuffle Reduction
; ==================================================================
; Computes dot product of two vectors using warp shuffle reduction
;
; Each thread loads one element from A and B, computes A[i] * B[i]
; Then uses shuffle butterfly reduction to sum across the warp
;
; This test combines:
;   - FPU operations (FMUL, FADD)
;   - Warp shuffle (SHFL.BFLY for butterfly reduction)
;   - Memory operations
;
; Memory Layout:
;   0x100-0x13F: Vector A (8 floats)
;   0x200-0x23F: Vector B (8 floats)
;   0x300:       Result (single float - dot product)
;
; Algorithm:
;   1. Each thread computes partial = A[tid] * B[tid]
;   2. Butterfly reduction using SHFL.BFLY with XOR lanes 4, 2, 1
;   3. Thread 0 writes final result
;
; Expected result with A = [1,2,3,4,5,6,7,8], B = [8,7,6,5,4,3,2,1]:
;   = 1*8 + 2*7 + 3*6 + 4*5 + 5*4 + 6*3 + 7*2 + 8*1
;   = 8 + 14 + 18 + 20 + 20 + 18 + 14 + 8 = 120

start:
    ; Get thread ID
    MOVSR   R1, SR_TID          ; R1 = tid
    
    ; Calculate addresses
    MOVI    R3, 0x100           ; A base
    MOVI    R4, 0x200           ; B base
    MOVI    R5, 8               ; Element size (8 bytes for double)
    MUL     R6, R1, R5          ; offset = tid * 8
    ADD     R3, R3, R6          ; &A[tid]
    ADD     R4, R4, R6          ; &B[tid]
    
    ; Load elements
    LD      R10, 0(R3)          ; R10 = A[tid]
    LD      R11, 0(R4)          ; R11 = B[tid]
    
    ; Compute partial product
    FMUL    R12, R10, R11       ; R12 = A[tid] * B[tid]
    
    ; ============================================
    ; Butterfly reduction using shuffle
    ; ============================================
    ; After each step, threads with lower indices accumulate sums
    ;
    ; Step 1: XOR with lane 4
    ;   Thread 0 gets from 4, adds: sum[0] = p0 + p4
    ;   Thread 1 gets from 5, adds: sum[1] = p1 + p5
    ;   Thread 2 gets from 6, adds: sum[2] = p2 + p6
    ;   Thread 3 gets from 7, adds: sum[3] = p3 + p7
    ;   etc.
    
    ; R13 = source lane index for SHFL
    MOVI    R13, 4              ; XOR distance
    SHFL.BFLY R14, R12, R13     ; R14 = value from lane (tid ^ 4)
    FADD    R12, R12, R14       ; R12 = partial sum
    
    ; Step 2: XOR with lane 2
    MOVI    R13, 2
    SHFL.BFLY R14, R12, R13     ; R14 = value from lane (tid ^ 2)
    FADD    R12, R12, R14
    
    ; Step 3: XOR with lane 1
    MOVI    R13, 1
    SHFL.BFLY R14, R12, R13     ; R14 = value from lane (tid ^ 1)
    FADD    R12, R12, R14
    
    ; ============================================
    ; Now thread 0 has the complete dot product in R12
    ; ============================================
    
    ; Only thread 0 writes result
    MOVI    R2, 0               ; R2 = 0 for comparison
    SEQ     P1, R1, R2          ; P1 = (tid == 0)
    BRC.FALSE P1, done
    
    ; Store result
    MOVI    R3, 0x300
    ST      R12, 0(R3)          ; Store dot product
    
done:
    EXIT
