;
; serial port
;
#include "main.inc"
    
    GLOBAL serial_init, getch, putch, putsz, puts, putHex

serial_data    IDATA
_HexTemp    res	    1
_HexTemp2   res	    1
	
  
serial    CODE
    
serial_init
; init 9600 baud @32MHz
    banksel BAUD1CON
    set_sfr BAUD1CON, 0x08
    set_sfr RC1STA, 0x90
    set_sfr TX1STA, 0x24
    set_sfr SP1BRGL, 0x40
    set_sfr SP1BRGH, 0x03
    retlw   1
    
getch
; output W = received data
    banksel PIR3
    wait_until PIR3,RCIF

    banksel RC1REG
    if_flag RC1STA,OERR, otherwise, +3
	bcf RC1STA,SPEN
	bsf RC1STA,SPEN
   
    movf    RC1REG,W
    banksel 0
    return

putch    
; input W = data to transmit
    banksel PIR3
    wait_until PIR3,TXIF
    
    banksel TX1REG
    movwf   TX1REG
    banksel 0
    retlw   0
    
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
    movlw   0x0D
    call    putch
    movlw   0x0A
    goto    putch
    
putHex
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
    banksel _HexTemp
    movf    _HexTemp,W
    andlw   0xf
    addlw   0x30
    movwf   _HexTemp2
    movlw   0x3A
    subwf   _HexTemp2,W
    movf    _HexTemp2,W
    bnc	    $+2
    addlw   7
    goto    putch
    
    
    END

