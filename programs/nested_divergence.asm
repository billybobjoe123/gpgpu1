; GPGPU-1 Test Program: Nested Divergence Test
; ==============================================
; Tests nested control flow and divergence stack behavior
;
; Tests:
;   1. Nested if statements (2 levels deep)
;   2. Nested if-else (divergence within divergence)
;   3. Stack push/pop on entry/exit
;   4. Mask reconstruction on reconvergence
;
; Expected behavior:
;   - Threads diverge at outer if
;   - Subset diverges again at inner if
;   - Masks properly restored at each reconvergence point
;   - All threads write correct results based on their path
;
; Memory Layout:
;   0x100-0x13F: Output array (8 elements, 8 bytes each)
;     result[tid] = computed value based on control flow path

start:
    ; Get thread ID
    MOVSR   R1, SR_TID          ; R1 = tid
    
    ; Initialize result to 0
    MOVI    R2, 0               ; R2 = result = 0
    
    ;=========================================================================
    ; Outer if: tid < 4
    ;=========================================================================
    
    MOVI    R3, 4
    SLT     P1, R1, R3          ; P1 = (tid < 4)
    BRC.FALSE P1, outer_else
    
outer_then:
    ; Threads 0-3: add 10
    ADDI    R2, R2, 10          ; result += 10
    
    ;-------------------------------------------------------------------------
    ; Inner if: tid < 2 (threads 0-1)
    ;-------------------------------------------------------------------------
    MOVI    R3, 2
    SLT     P1, R1, R3          ; P1 = (tid < 2)
    BRC.FALSE P1, inner_else
    
inner_then:
    ; Threads 0-1: add 100
    ADDI    R2, R2, 100         ; result += 100
    ; Fall through to inner_end
    
inner_else:
    ; Threads 2-3: add 200
    ADDI    R2, R2, 200         ; result += 200
    
inner_end:
    ; Reconverge threads 0-3
    ; At this point:
    ;   Thread 0-1: result = 0 + 10 + 100 = 110
    ;   Thread 2-3: result = 0 + 10 + 200 = 210
    ; Fall through skips outer_else
    
    ; Skip outer_else block
    MOVI    R6, 1
    SEQ     P2, R6, R6          ; P2 = true
    BRC.TRUE P2, outer_end
    
outer_else:
    ; Threads 4-7: add 20
    ADDI    R2, R2, 20          ; result += 20
    
    ;-------------------------------------------------------------------------
    ; Inner if: tid < 6 (threads 4-5)
    ;-------------------------------------------------------------------------
    MOVI    R3, 6
    SLT     P1, R1, R3          ; P1 = (tid < 6)
    BRC.FALSE P1, inner_else2
    
inner_then2:
    ; Threads 4-5: add 300
    ADDI    R2, R2, 300         ; result += 300
    ; Fall through
    
inner_else2:
    ; Threads 6-7: add 400
    ADDI    R2, R2, 400         ; result += 400
    
inner_end2:
    ; Reconverge threads 4-7
    ; At this point:
    ;   Thread 4-5: result = 0 + 20 + 300 = 320
    ;   Thread 6-7: result = 0 + 20 + 400 = 420

outer_end:
    ; All threads reconverge here
    ; Expected results:
    ;   Thread 0: 110
    ;   Thread 1: 110
    ;   Thread 2: 210
    ;   Thread 3: 210
    ;   Thread 4: 320
    ;   Thread 5: 320
    ;   Thread 6: 420
    ;   Thread 7: 420
    
    ;=========================================================================
    ; Store result
    ;=========================================================================
    
    MOVI    R3, 0x100           ; Base address
    MOVI    R4, 8               ; Element size
    MUL     R5, R1, R4          ; Offset = tid * 8
    ADD     R3, R3, R5          ; Address = base + offset
    ST      R2, 0(R3)           ; Store result[tid]
    
    EXIT

;=============================================================================
; Expected Memory Contents at 0x100-0x13F:
;   0x100: 110 (0x000000000000006E)
;   0x108: 110 (0x000000000000006E)
;   0x110: 210 (0x00000000000000D2)
;   0x118: 210 (0x00000000000000D2)
;   0x120: 320 (0x0000000000000140)
;   0x128: 320 (0x0000000000000140)
;   0x130: 420 (0x00000000000001A4)
;   0x138: 420 (0x00000000000001A4)
;=============================================================================
