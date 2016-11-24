#include "p16f18855.inc"

#define	    SD_CS	   LATB,2


wait_until MACRO reg,bit
    btfss reg,bit
    goto  $-1
    ENDM

wait_while MACRO reg,bit
    btfsc reg,bit
    goto  $-1
    ENDM

otherwise   equ	    0

if_flag  MACRO  reg,bit,otherwise,offs
    btfss   reg,bit
    goto    $+offs
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
    movf	src+2,W
    movwf	LBA+2
    ENDM

