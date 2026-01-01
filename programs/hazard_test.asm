; hazard_test.asm
; Tests RAW (Read After Write) hazard detection and handling
; Without proper scoreboard stalling, this program would produce wrong results

    .text
    .global _start

_start:
    ;==========================================================================
    ; Test 1: Simple RAW hazard
    ; R1 = 10, R2 = 20, R3 = R1 + R2 = 30
    ;==========================================================================
    MOVI    R1, 10          ; R1 = 10
    MOVI    R2, 20          ; R2 = 20
    ADD     R3, R1, R2      ; R3 = R1 + R2 (RAW on R1, R2 from MOVI)
    
    ;==========================================================================
    ; Test 2: Back-to-back dependent operations
    ; R4 = 5, R5 = R4 * 3 = 15, R6 = R5 + 1 = 16
    ;==========================================================================
    MOVI    R4, 5           ; R4 = 5
    MULI    R5, R4, 3       ; R5 = R4 * 3 = 15 (RAW on R4)
    ADDI    R6, R5, 1       ; R6 = R5 + 1 = 16 (RAW on R5)
    
    ;==========================================================================
    ; Test 3: Chain of dependent instructions
    ; R7 = 2, R8 = R7 * 2 = 4, R9 = R8 * 2 = 8, R10 = R9 * 2 = 16
    ;==========================================================================
    MOVI    R7, 2           ; R7 = 2
    MULI    R8, R7, 2       ; R8 = R7 * 2 = 4 (RAW on R7)
    MULI    R9, R8, 2       ; R9 = R8 * 2 = 8 (RAW on R8)
    MULI    R10, R9, 2      ; R10 = R9 * 2 = 16 (RAW on R9)
    
    ;==========================================================================
    ; Test 4: Independent instructions between dependent ones
    ; R11 = 100, R12 = 200, R13 = R11 + R12 = 300
    ; R14 should be able to be computed in parallel
    ;==========================================================================
    MOVI    R11, 100        ; R11 = 100
    MOVI    R12, 200        ; R12 = 200
    MOVI    R14, 400        ; R14 = 400 (independent)
    ADD     R13, R11, R12   ; R13 = R11 + R12 = 300 (RAW on R11, R12)
    
    ;==========================================================================
    ; Test 5: Load-use hazard
    ; Load from memory, then use result immediately
    ;==========================================================================
    MOVI    R15, 0x1000     ; R15 = address
    LD      R16, R15, 0     ; Load R16 from memory
    ADDI    R17, R16, 1     ; R17 = R16 + 1 (RAW on R16 from load)
    
    ;==========================================================================
    ; Test 6: Store then load to same address
    ;==========================================================================
    MOVI    R18, 0x1008     ; R18 = address
    MOVI    R19, 999        ; R19 = value to store
    ST      R19, R18, 0     ; Store R19 to memory
    LD      R20, R18, 0     ; Load R20 from same address
    
    ;==========================================================================
    ; Verify results
    ;==========================================================================
    ; Expected values:
    ; R3 = 30, R6 = 16, R10 = 16
    ; R13 = 300, R14 = 400
    
    EXIT

