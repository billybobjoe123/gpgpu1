; GPGPU-1 Test Program: Simple Loop
; ==================================
; Counts from 0 to N in a loop
;
; Register usage:
;   R1 = counter
;   R2 = limit (10)
;   P1 = loop condition

start:
    MOVI    R1, 0               ; counter = 0
    MOVI    R2, 10              ; limit = 10
    
loop:
    ADDI    R1, R1, 1           ; counter++
    SLT     P1, R1, R2          ; P1 = (counter < limit)
    BRC.TRUE P1, loop           ; if P1, goto loop
    
done:
    EXIT
