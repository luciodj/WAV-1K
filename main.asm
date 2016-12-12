;
; Project: WAV-1k
;
; File:  main.asm
;
; Description:
;   A simple WAV file player for the XPRESS evaluation board + SD Click in 1KB of code!
;   Reads 8-bit Mono, uncompressed, 44kHz WAV files from a FAT16 formatted (<2GB) SD card.
;
; Copyright: Lucio Di Jasio - December 2016
;
; License: Apache 2, see license file included
;

;
;    SOFTWARE AND DOCUMENTATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND,
;    EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION, ANY WARRANTY OF
;    MERCHANTABILITY, TITLE, NON-INFRINGEMENT AND FITNESS FOR A PARTICULAR PURPOSE.
;    IN NO EVENT SHALL THE AUTHOR OR ITS LICENSORS BE LIABLE OR OBLIGATED UNDER
;    CONTRACT, NEGLIGENCE, STRICT LIABILITY, CONTRIBUTION, BREACH OF WARRANTY, OR
;    OTHER LEGAL EQUITABLE THEORY ANY DIRECT OR INDIRECT DAMAGES OR EXPENSES
;    INCLUDING BUT NOT LIMITED TO ANY INCIDENTAL, SPECIAL, INDIRECT, PUNITIVE OR
;    CONSEQUENTIAL DAMAGES, LOST PROFITS OR LOST DATA, COST OF PROCUREMENT OF
;    SUBSTITUTE GOODS, TECHNOLOGY, SERVICES, OR ANY CLAIMS BY THIRD PARTIES
;    (INCLUDING BUT NOT LIMITED TO ANY DEFENSE THEREOF), OR OTHER SIMILAR COSTS.

#include "main.inc"

#include "config.inc"
#include "delay.inc"
#include "pwm.inc"
#include "sdmmc.inc"
#include "fileio.inc"
#include "serial.inc"


.audio_shr    UDATA_SHR
curBuf      res     1   ; current buffer playing
BCount      res     1   ; 256 bytes buffers
EmptyFlag   res     1   ; 1 = need refilling
count       res     1   ;


;-------------------------------------------------------------
.reset    CODE 0
reset_vector
    goto    main

;-------------------------------------------------------------
.interrupt    CODE 4
interrupt_vector
    banksel PIR4
    bcf     PIR4,TMR2IF
    ; 1.,2. load the new sample
    moviw   FSR1++
    banksel PWM7DCH
    movwf   PWM7DCH

    banksel FSR1L_SHAD  ; ISR context saving has saved a copy of FSR1
    incf    FSR1L_SHAD  ; must update the saved copy too!

    ; 3. check if buffer emptied
    decfsz  BCount
    goto    ISRexit

    ; 3.1 swap buffers
    movlw   1
    xorwf   curBuf  ; toggle
    clrf    FSR1L_SHAD
    movlw   HIGH(buffer)
    btfsc   curBuf,0
    movlw   HIGH(buffer2)
    movwf   FSR1H_SHAD

    ; 3.2 buffer refilled
;    clrf    BCount

    ; 3.3 flag a new buffer needs to be prepared
    bsf     EmptyFlag,0

ISRexit
    retfie

;-------------------------------------------------------------
        CODE
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

    SERIAL_INIT
    goto    PWM_init

;---------------------------------------------------------------
main
	call SYSTEM_init

mainL
	movlw   .50	    ; 500 ms delay
	call    delay_10ms

    call    mount
    bz      success

 ifdef  DEBUG_PRINT
    LFSR1   szError
    movf    FError,W
    call    printf
 endif

    goto    mainL

success
    banksel PORTA
    bsf     LED_MOUNT

;    ; dump root
;    LFSR0   buffer
;    CPLBA   root
;    call    SD_SECTORread
;    LFSR0   buffer
;    movlw   .8
;    call    dump
;    call    putNL

    clrf    curBuf      ; init the working buffer
    LFSR0   buffer
    call    find

    banksel LATA
    bsf     LED_WAV

; show what was loaded
;    LFSR0   buffer     ; a RIFF WAV file!
;    movlw   .8
;    DUMP
;    PUTNL

play
;AUDIO_init
    bsf     curBuf,0    ; start with buffer 1 active first
    LFSR1   buffer      ; put the audio pointer on its first byte
    clrf    BCount      ; init the counter to 256 samples
    bsf     EmptyFlag,0 ; immediately signal need a new buffer
    bsf     INTCON,GIE
    banksel LATA
    bsf     LED_PLAY

playLoop
    ; check if file exhausted
    banksel size
    movlw   2           ; subtract 512
    subwf   size+1
    movlw   0
    subwfb  size+2
    subwfb  size+3
    bnc     AUDIO_stop  ; borrow (NC)

 ifdef DEBUG_PRINT
    ; check if button pressed
    banksel PORTA
    btfss   SW
    goto    AUDIO_stop
 endif

    ; check if buffer needs refilling
    btfss   EmptyFlag,0
    goto    $-1
;
    bcf     EmptyFlag,0
    ; refill buffer
    btfss   curBuf,0
    goto    cpyBuffer
;
    ; load a new buffer, advance to next sector in cluster
    banksel sec
    incf    sec
    movf    sxc,W       ; compare to sectors per cluster
    xorwf   sec,W
    bnz     DATAnext
    clrf    sec         ; get the next cluster
    call    next
DATAnext
    call    read
    bnz     AUDIO_stop
    goto    playLoop
;
;    ; copy buffer
cpyBuffer
    banksel  count
    clrf    count       ; cpy 256 bytes
    LFSR0   buffer1     ; source buffer 1

cpyLoop
    moviw   0[FSR0]
    incf    FSR0H           ; destination buffer 2
    movwi   FSR0++
    decf    FSR0H           ; back to source
    decfsz  count
    goto    cpyLoop

    goto    playLoop

AUDIO_stop
    banksel LATA
    bcf     LED_PLAY
    bcf     INTCON,GIE

stop
	goto    stop

    END