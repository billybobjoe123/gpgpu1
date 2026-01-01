; GPGPU-1 Test Program: Reduction (Sum)
; ======================================
; Computes sum of array elements using shared memory
; Each warp loads 8 elements, then reduces to single value
;
; Register usage:
;   R1 = tid
;   R2 = input array base
;   R3 = value
;   R4 = stride for reduction
;   R5 = partner tid
;   R6 = partner value
;   R10 = shared memory base (per-warp offset)

start:
    ; Get thread ID
    MOVSR   R1, SR_TID          ; R1 = tid (0-7)
      ; Setup input array address (0x100)
    MOVI    R2, 0x100           ; input base address
    
    ; Calculate offset and load input
    MOVI    R7, 8
    MUL     R8, R1, R7          ; offset = tid * 8
    ADD     R2, R2, R8          ; addr = base + offset
    LD      R3, 0(R2)           ; R3 = input[tid]
    
    ; Store to shared memory for reduction
    ; Shared mem base at 0x1_0000_0000 (simplified to offset 0)
    MOVI    R10, 0              ; shared base offset
    MUL     R8, R1, R7          ; offset = tid * 8
    ADD     R10, R10, R8
    STS     R3, 0(R10)          ; shared[tid] = R3
    
    ; Synchronize - all threads must write before reduction
    BAR     0
    
    ; Tree reduction: stride = 4, 2, 1
    ; Stride 4: threads 0-3 add values from threads 4-7
    MOVI    R4, 4               ; stride = 4
    SLT     P1, R1, R4          ; P1 = (tid < 4)
    PUSH    P1
    
    ; Only threads 0-3 participate
    ADD     R5, R1, R4          ; partner = tid + stride
    MUL     R8, R5, R7          ; partner offset
    LDS     R6, 0(R8)           ; R6 = shared[partner]
    ADD     R3, R3, R6          ; R3 += partner value
    STS     R3, 0(R10)          ; Update shared[tid]
    
    POP
    BAR     0
    
    ; Stride 2: threads 0-1 add values from threads 2-3
    MOVI    R4, 2
    SLT     P1, R1, R4
    PUSH    P1
    
    ADD     R5, R1, R4
    MUL     R8, R5, R7
    LDS     R6, 0(R8)
    ADD     R3, R3, R6
    STS     R3, 0(R10)
    
    POP
    BAR     0
    
    ; Stride 1: thread 0 adds value from thread 1
    MOVI    R4, 1
    SLT     P1, R1, R4
    PUSH    P1
    
    ADD     R5, R1, R4
    MUL     R8, R5, R7
    LDS     R6, 0(R8)
    ADD     R3, R3, R6
      ; Thread 0 writes final result to output
    MOVI    R9, 0x200           ; output address
    ST      R3, 0(R9)
    
    POP
    
    EXIT
