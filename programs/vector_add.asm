; GPGPU-1 Test Program: Vector Addition
; =====================================
; Computes C[i] = A[i] + B[i] for each thread
;
; Register usage:
;   R1  = thread ID (global index)
;   R2  = base address of A
;   R3  = base address of B  
;   R4  = base address of C
;   R5  = element size (8 bytes for 64-bit)
;   R10 = offset = tid * 8
;   R11 = A[i]
;   R12 = B[i]
;   R13 = C[i] = A[i] + B[i]

start:
    ; Get thread ID
    MOVSR   R1, SR_TID          ; R1 = thread ID within warp (0-7)
    
    ; Load base addresses (would be passed as kernel args)
    ; For test: A=0x100, B=0x200, C=0x300 (small offsets for testing)
    MOVI    R2, 0x100           ; R2 = 0x100 (base of A)
    MOVI    R3, 0x200           ; R3 = 0x200 (base of B)
    MOVI    R4, 0x300           ; R4 = 0x300 (base of C)
    
    ; Calculate offset = tid * 8
    MOVI    R5, 8               ; Element size
    MUL     R10, R1, R5         ; R10 = tid * 8
    
    ; Calculate addresses
    ADD     R2, R2, R10         ; R2 = &A[tid]
    ADD     R3, R3, R10         ; R3 = &B[tid]
    ADD     R4, R4, R10         ; R4 = &C[tid]
    
    ; Load A[i] and B[i]
    LD      R11, 0(R2)          ; R11 = A[tid]
    LD      R12, 0(R3)          ; R12 = B[tid]
    
    ; Compute sum
    ADD     R13, R11, R12       ; R13 = A[tid] + B[tid]
    
    ; Store result
    ST      R13, 0(R4)          ; C[tid] = R13
    
    ; Exit
    EXIT
