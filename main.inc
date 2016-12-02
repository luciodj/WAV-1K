#include "p16f18855.inc"

; PIC16F18855 XPRESS Evaluation board pin assignments
#define LED_MOUNT       LATA,0   ; Successfull mount
#define LED_WAV         LATA,1   ; Found WAV file
#define LED_PLAY        LATA,2   ; Playing NOW!
#define LED_ERROR       LATA,3   ; if on the previous 3 indicate the FERROR code
#define SW              PORTA,5  ; user button
#define	SD_CS           LATB,2   ; SD Click


;---------------------------------------------------------
wait_until MACRO reg,bit
    btfss reg,bit
    goto  $-1
    ENDM

wait_while MACRO reg,bit
    btfsc reg,bit
    goto  $-1
    ENDM

set_sfr  MACRO  sfr,value
    movlw   value
    movwf   sfr
    ENDM

LFSR0 MACRO addr
    movlw	LOW(addr)
    movwf	FSR0L
    movlw	HIGH(addr)
    movwf	FSR0H
    ENDM

LFSR1 MACRO addr
    movlw	LOW(addr)
    movwf	FSR1L
    movlw	HIGH(addr)
    movwf	FSR1H
    ENDM

LLBA MACRO addr
    movlw       LOW(addr)
    movwf	LBA
    movlw	HIGH(addr)
    movwf	LBA+1
    clrf	LBA+2
    ENDM

CPLBA	MACRO	src
    banksel	src
    movf	src,W
    movwf	LBA
    movf	src+1,W
    movwf	LBA+1
    clrf	LBA+2	    ; assume src is a Word
;    movf	src+2,W
;    movwf	LBA+2
    ENDM

