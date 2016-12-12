;
; delay.asm
;
#include "p16f18855.inc"

    GLOBAL delay_10ms

_delay    IDATA
_delay10ms	res 1
_delayms_inner	res 1
_delayms_outer	res 1

delay    CODE
;---------------------------------------------------------------
delay_10ms
; input W : x10 ms delay
	banksel	_delay10ms
	movwf	_delay10ms
tenms_loop
	movlw	.40	    ; 40 x250us = 10ms
	movwf	_delayms_outer
delayms_outerL
	movlw	.250	    ; 250us
	movwf	_delayms_inner

delayms_innerL
	nop			; 1
	nop			; 2
	nop			; 3
	nop			; 4
	nop			; 5
	decfsz	_delayms_inner	; 6
	goto	delayms_innerL	; 7-8   = 1us

	decfsz	_delayms_outer
	goto	delayms_outerL

	decfsz  _delay10ms
	goto	tenms_loop
	return

    END

