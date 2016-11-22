; PIC16F18855 Configuration Bit Settings

#include "main.inc"

#include "config.inc"
#include "delay.inc"
#include "serial.inc"
#include "pwm.inc"
#include "SDMMC.inc"

buffer	equ 0x2050

.main	udata 0x20
temp	    res	    1

    CODE 0
reset_vector
    goto    main

;-------------------------------------------------------------
SYSTEM_init

OSC_init
    banksel OSCCON1
    set_sfr OSCCON1,0x60
    clrf    OSCCON3
    clrf    OSCEN
    set_sfr OSCFRQ,0x06
    clrf    OSCTUNE

IO_init
    banksel LATA
    set_sfr LATA,0x00
    set_sfr LATB,0x04
    set_sfr LATC,0x01
    banksel TRISA
    set_sfr TRISA,0xF0
    set_sfr TRISB,0xD3
    set_sfr TRISC,0x5E
    banksel ANSELA
    set_sfr ANSELA,0x00
    banksel ANSELB
    set_sfr ANSELB,0x00
    set_sfr ANSELC,0x00

    banksel PPSLOCK
    set_sfr PPSLOCK,0x55
    set_sfr PPSLOCK,0xAA
    bcf	    PPSLOCK,PPSLOCKED
    banksel SSP1DATPPS
    set_sfr SSP1DATPPS,0x0c; SDI <- RB4
    set_sfr SSP1CLKPPS,0x0b; SCK <- RB3 ???
    set_sfr RXPPS,0x11	    ; RX
    banksel RB3PPS
    set_sfr RB3PPS,0x14	    ; SCK
    set_sfr RB5PPS,0x15	    ; SDO
    set_sfr RC0PPS,0x10	    ; TX
    set_sfr RC7PPS,0x0f	    ; PWM7OUT
    banksel PPSLOCK
    set_sfr PPSLOCK,0x55
    set_sfr PPSLOCK,0xAA
    bsf	    PPSLOCK,PPSLOCKED

    call    serial_init
    goto    PWM_init

;---------------------------------------------------------------
szInit	dt  " Init SD-MEDIA",0
szRead	dt  " Read",0

main
	call SYSTEM_init
	; enable interrupts

mainL
	movlw   .50	    ; 500 ms delay
	call    delay_10ms

    call    SD_MEDIAinit
    banksel temp
    movwf   temp
    call    putHex
    LFSR1   szInit
    call    puts

    banksel temp
    movf    temp,W
    bnz     mainL

init_success
    LFSR0   buffer
    LLBA    0x0
    call    SD_SECTORread
    banksel temp
    movwf   temp
    call    putHex
    LFSR1   szRead
    call    puts

    banksel temp
    movf    temp,W
    bnz     mainL

stop
	goto    stop

    END