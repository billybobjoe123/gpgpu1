; GPGPU-1 Test Program: Warp Shuffle Integration Test
; ====================================================
; Tests warp shuffle operations:
; - SHFL.IDX  - Direct index (broadcast/gather)
; - SHFL.UP   - Shift up (from lower lanes)
; - SHFL.DOWN - Shift down (from higher lanes)
; - SHFL.BFLY - Butterfly (XOR) for reductions
;
; Memory Layout:
;   0x100-0x13F: Input data (8 values, one per lane)
;   0x200-0x23F: Output for IDX test
;   0x300-0x33F: Output for UP test
;   0x400-0x43F: Output for DOWN test
;   0x500-0x53F: Output for BFLY test (reduction)
;
; Register usage:
;   R1  = thread ID (lane ID)
;   R2  = input base
;   R3  = my value from input
;   R4-R7 = shuffle results
;   R10 = offset calculation
;   R20 = reduction accumulator

start:
    ; Get thread ID (lane ID 0-7)
    MOVSR   R1, SR_TID          ; R1 = tid
    
    ;=========================================================================
    ; Load input data
    ;=========================================================================
    MOVI    R2, 0x100           ; Input base
    MOVI    R6, 8
    MUL     R10, R1, R6         ; offset = tid * 8
    ADD     R2, R2, R10         ; &input[tid]
    LD      R3, 0(R2)           ; R3 = input[tid] = my value
    
    ;=========================================================================
    ; Test 1: SHFL.IDX - Broadcast lane 0 to all lanes
    ;=========================================================================
    ; All lanes get value from lane 0
    MOVI    R8, 0               ; Lane index = 0
    SHFL.IDX R4, R3, R8         ; R4 = value from lane 0
    
    ; Store result
    MOVI    R9, 0x200
    ADD     R9, R9, R10
    ST      R4, 0(R9)           ; output_idx[tid] = broadcast value
    
    ;=========================================================================
    ; Test 2: SHFL.UP - Each lane gets value from lane-1
    ;=========================================================================
    ; Lane 0 gets nothing valid, lanes 1-7 get from lane-1
    MOVI    R8, 1               ; Delta = 1
    SHFL.UP R5, R3, R8          ; R5 = value from (lane - 1)
    
    ; Store result
    MOVI    R9, 0x300
    ADD     R9, R9, R10
    ST      R5, 0(R9)           ; output_up[tid]
    
    ;=========================================================================
    ; Test 3: SHFL.DOWN - Each lane gets value from lane+1
    ;=========================================================================
    ; Lanes 0-6 get from lane+1, lane 7 gets nothing valid
    MOVI    R8, 1               ; Delta = 1
    SHFL.DOWN R6, R3, R8        ; R6 = value from (lane + 1)
    
    ; Store result
    MOVI    R9, 0x400
    ADD     R9, R9, R10
    ST      R6, 0(R9)           ; output_down[tid]
    
    ;=========================================================================
    ; Test 4: SHFL.BFLY - Butterfly reduction (sum all values)
    ;=========================================================================
    ; Classic tree reduction using XOR shuffle
    ; Step 1: XOR with 4 (swap halves: 0<->4, 1<->5, 2<->6, 3<->7)
    ; Step 2: XOR with 2 (swap pairs: 0<->2, 1<->3, 4<->6, 5<->7)
    ; Step 3: XOR with 1 (swap adjacent: 0<->1, 2<->3, 4<->5, 6<->7)
    
    ; Start with my value
    ADD     R20, R3, R0         ; R20 = my value (copy)
    
    ; Step 1: XOR with 4
    MOVI    R8, 4
    SHFL.BFLY R7, R20, R8       ; R7 = value from (lane ^ 4)
    ADD     R20, R20, R7        ; R20 += partner value
    
    BAR     0                   ; Sync (ensure all threads have computed)
    
    ; Step 2: XOR with 2
    MOVI    R8, 2
    SHFL.BFLY R7, R20, R8       ; R7 = value from (lane ^ 2)
    ADD     R20, R20, R7        ; R20 += partner value
    
    BAR     0
    
    ; Step 3: XOR with 1
    MOVI    R8, 1
    SHFL.BFLY R7, R20, R8       ; R7 = value from (lane ^ 1)
    ADD     R20, R20, R7        ; R20 += partner value
    
    ; Now all lanes have the sum of all 8 input values!
    
    ; Store reduction result
    MOVI    R9, 0x500
    ADD     R9, R9, R10
    ST      R20, 0(R9)          ; output_bfly[tid] = sum (all lanes have same value)
    
    ;=========================================================================
    ; Test 5: SHFL.IDX with varying indices - gather pattern
    ;=========================================================================
    ; Each lane gathers from lane (7 - tid) - reverse order
    MOVI    R8, 7
    SUB     R8, R8, R1          ; R8 = 7 - tid
    SHFL.IDX R4, R3, R8         ; R4 = value from lane (7-tid)
    
    ; Store result
    MOVI    R9, 0x600
    ADD     R9, R9, R10
    ST      R4, 0(R9)           ; output_reverse[tid]
    
    ; Done
    EXIT
