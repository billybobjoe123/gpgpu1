; GPGPU-1 Test Program: Divergence Test
; ======================================
; Tests if-else divergence handling
;
; if (tid < 4) {
;     R5 = 100;
; } else {
;     R5 = 200;
; }
; R6 = R5 + tid;

start:
    ; Get thread ID
    MOVSR   R1, SR_TID          ; R1 = tid (0-7)
    
    ; Compare tid < 4
    MOVI    R2, 4
    SLT     P1, R1, R2          ; P1 = (tid < 4)
    
    ; Begin divergent section
    PUSH    P1                  ; Save mask, activate threads where P1=1
    
    ; THEN path: threads 0-3
    MOVI    R5, 100             ; R5 = 100
    
    ELSE                        ; Switch to threads where P1=0
    
    ; ELSE path: threads 4-7
    MOVI    R5, 200             ; R5 = 200
    
    POP                         ; Reconverge all threads
    
    ; All threads execute this
    ADD     R6, R5, R1          ; R6 = R5 + tid
      ; Store results to memory
    MOVI    R10, 8
    MUL     R10, R1, R10        ; offset = tid * 8
    MOVI    R11, 0x400          ; base = 0x400 (smaller address)
    ADD     R11, R11, R10       ; addr = base + offset
    ST      R6, 0(R11)          ; mem[addr] = R6
    
    EXIT
