; GPGPU-1 Test Program: Atomic Operations Integration Test
; =========================================================
; Tests atomic memory operations:
; - ATOM.ADD  - Atomic add
; - ATOM.MIN  - Atomic minimum (signed)
; - ATOM.MAX  - Atomic maximum (signed)
; - ATOM.AND  - Atomic bitwise AND
; - ATOM.OR   - Atomic bitwise OR
; - ATOM.XOR  - Atomic bitwise XOR
; - ATOM.EXCH - Atomic exchange
;
; Memory Layout:
;   0x100: Atomic counter (initialized to 0) - for ADD test
;   0x108: Min value (initialized to MAX_INT64)
;   0x110: Max value (initialized to MIN_INT64)
;   0x118: AND accumulator (initialized to 0xFFFFFFFFFFFFFFFF)
;   0x120: OR accumulator (initialized to 0)
;   0x128: XOR accumulator (initialized to 0)
;   0x130: Exchange target
;   0x200-0x23F: Per-thread old values from atomic ADD
;   0x300-0x33F: Per-thread old values from atomic MIN
;
; Each thread contributes its tid+1 to the atomic operations
;
; Register usage:
;   R1  = thread ID
;   R2  = value to contribute (tid + 1)
;   R3  = atomic address
;   R4  = old value returned from atomic
;   R10 = offset for storing results

start:
    ; Get thread ID
    MOVSR   R1, SR_TID          ; R1 = tid (0-7)
    
    ; Calculate contribution value = tid + 1
    ADDI    R2, R1, 1           ; R2 = tid + 1 (so values are 1,2,3,4,5,6,7,8)
    
    ; Calculate per-thread output offset
    MOVI    R6, 8
    MUL     R10, R1, R6         ; R10 = tid * 8
    
    ;=========================================================================
    ; Test 1: ATOM.ADD - All threads atomically add to counter
    ;=========================================================================
    ; After all threads: counter = 1+2+3+4+5+6+7+8 = 36
    MOVI    R3, 0x100           ; Atomic counter address
    ATOM.ADD R4, 0(R3), R2      ; old = *R3; *R3 += R2; R4 = old
    
    ; Store old value for this thread
    MOVI    R5, 0x200
    ADD     R5, R5, R10
    ST      R4, 0(R5)           ; old_add[tid] = R4
    
    ;=========================================================================
    ; Test 2: ATOM.MIN - Find minimum (each thread contributes tid+1)
    ;=========================================================================
    ; Result should be 1 (from thread 0)
    MOVI    R3, 0x108
    ATOM.MIN R4, 0(R3), R2      ; old = *R3; *R3 = min(*R3, R2); R4 = old
    
    ; Store old value
    MOVI    R5, 0x300
    ADD     R5, R5, R10
    ST      R4, 0(R5)           ; old_min[tid] = R4
    
    ;=========================================================================
    ; Test 3: ATOM.MAX - Find maximum
    ;=========================================================================
    ; Result should be 8 (from thread 7)
    MOVI    R3, 0x110
    ATOM.MAX R4, 0(R3), R2      ; old = *R3; *R3 = max(*R3, R2); R4 = old
    
    ; Store old value
    MOVI    R5, 0x400
    ADD     R5, R5, R10
    ST      R4, 0(R5)           ; old_max[tid] = R4
    
    ;=========================================================================
    ; Test 4: ATOM.AND - Bitwise AND all contributions
    ;=========================================================================
    ; Each thread ANDs its (tid+1) value
    ; 1 & 2 & 3 & 4 & 5 & 6 & 7 & 8 = 0 (no bit is set in all values)
    MOVI    R3, 0x118
    ATOM.AND R4, 0(R3), R2
    
    MOVI    R5, 0x500
    ADD     R5, R5, R10
    ST      R4, 0(R5)           ; old_and[tid] = R4
    
    ;=========================================================================
    ; Test 5: ATOM.OR - Bitwise OR all contributions
    ;=========================================================================
    ; 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 = 15 (0xF)
    MOVI    R3, 0x120
    ATOM.OR R4, 0(R3), R2
    
    MOVI    R5, 0x600
    ADD     R5, R5, R10
    ST      R4, 0(R5)           ; old_or[tid] = R4
    
    ;=========================================================================
    ; Test 6: ATOM.XOR - Bitwise XOR all contributions
    ;=========================================================================
    ; 1 ^ 2 ^ 3 ^ 4 ^ 5 ^ 6 ^ 7 ^ 8 = 8 (interesting pattern)
    MOVI    R3, 0x128
    ATOM.XOR R4, 0(R3), R2
    
    MOVI    R5, 0x700
    ADD     R5, R5, R10
    ST      R4, 0(R5)           ; old_xor[tid] = R4
    
    ;=========================================================================
    ; Test 7: ATOM.EXCH - Exchange (last writer wins)
    ;=========================================================================
    ; Final value will be one of the tid+1 values (race)
    MOVI    R3, 0x130
    ATOM.EXCH R4, 0(R3), R2
    
    MOVI    R5, 0x800
    ADD     R5, R5, R10
    ST      R4, 0(R5)           ; old_exch[tid] = R4
    
    ;=========================================================================
    ; Barrier to ensure all atomics complete
    ;=========================================================================
    BAR     0
    
    ;=========================================================================
    ; Thread 0 reads and stores final atomic values
    ;=========================================================================
    ; Only thread 0 stores final results
    SEQ     P1, R1, R0          ; P1 = (tid == 0)
    PUSH    P1
    
    ; Read and store final values
    MOVI    R3, 0x100
    LD      R4, 0(R3)           ; Final ADD result
    MOVI    R5, 0x900
    ST      R4, 0(R5)           ; final_add = 36 (expected)
    
    MOVI    R3, 0x108
    LD      R4, 0(R3)           ; Final MIN result
    MOVI    R5, 0x908
    ST      R4, 0(R5)           ; final_min = 1 (expected)
    
    MOVI    R3, 0x110
    LD      R4, 0(R3)           ; Final MAX result
    MOVI    R5, 0x910
    ST      R4, 0(R5)           ; final_max = 8 (expected)
    
    MOVI    R3, 0x120
    LD      R4, 0(R3)           ; Final OR result
    MOVI    R5, 0x918
    ST      R4, 0(R5)           ; final_or = 15 (expected)
    
    POP
    
    ; Done
    EXIT
