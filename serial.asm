;
; serial.asm
;
#include "main.inc"
#include "sdmmc.inc"

    GLOBAL serial_init, getch, putch, putsz, puts,
    GLOBAL putHex, printf, printLBA, putNL, dump

serial_data    IDATA
_HexTemp    res	    1
_HexTemp2   res	    1
_HexCount   res     1
_HexRows    res     1
_BSRsave    res     1


serial    CODE

serial_init
; init 9600 baud @32MHz
 ifndef __SKIP
    banksel BAUD1CON
    set_sfr BAUD1CON, 0x08
    set_sfr RC1STA, 0x90
    set_sfr TX1STA, 0x24
    set_sfr SP1BRGL, 0x40
    set_sfr SP1BRGH, 0x03
 endif
    retlw   1

getch
; output W = received data
    banksel PIR3
    btfss   PIR3,RCIF
    bra     $-1

    banksel RC1REG
    btfss   RC1STA,OERR
    bra     no_err
	bcf     RC1STA,SPEN
	bsf     RC1STA,SPEN
no_err
    movf    RC1REG,W
    return

putch
; input W = data to transmit
 ifndef __SKIP
    banksel PIR3
    wait_until PIR3,TXIF

    banksel TX1REG
    movwf   TX1REG
    banksel _HexTemp
 endif
   return

putsz
; input FSR1 = points to zero terminated ascii string
;
    moviw   FSR1++
    btfsc   STATUS,Z
    return
    call    putch
    goto    putsz


puts
    call    putsz
putNL
    movlw   0x0D
    call    putch
    movlw   0x0A
    goto    putch

putHex
 ifndef __SKIP
    banksel _HexTemp
    movwf    _HexTemp
    swapf   _HexTemp,W
    andlw   0xf
    addlw   0x30
    movwf   _HexTemp2
    movlw   0x3A
    subwf   _HexTemp2,W
    movf    _HexTemp2,W
    bnc	    $+2
    addlw   7
    call    putch
    movf    _HexTemp,W
    andlw   0xf
    addlw   0x30
    movwf   _HexTemp2
    movlw   0x3A
    subwf   _HexTemp2,W
    movf    _HexTemp2,W
    bnc	    $+2
    addlw   7
 endif
    goto    putch

printf
    banksel _HexTemp    ; save W
    movwf   _HexTemp
    call    putsz       ; print string
    movf    _HexTemp,W
    call    putHex      ; followed by the hex value of W
    goto    putNL

printLBA
    movf    BSR,W       ; save the bank
    banksel _BSRsave
    movwf   _BSRsave
    call    putsz       ; print the string
    movf    LBA+2,W     ; print hex LBA
    call    putHex
    movf    LBA+1,W
    call    putHex
    movf    LBA,W
    call    putHex      ; CRLF
    call    putNL
    movf    _BSRsave,W
    movwf   BSR
    return

dump
; input W: number of rows to print
; input FSR0 : buffer pointer
 ifndef __SKIP
    banksel _HexCount
    movwf   _HexRows

dumpRowL
    movf    FSR0L,W
    call    putHex
    movlw   ':'
    call    putch
    movlw   .16
    movwf   _HexCount

dumpByteL
    moviw   FSR0++
    call    putHex
    movlw   ' '
    call    putch
    decfsz  _HexCount
    goto    dumpByteL

    call    putNL
    decfsz  _HexRows
    goto    dumpRowL
 endif
    retlw   0
    END

