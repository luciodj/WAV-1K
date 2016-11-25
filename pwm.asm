    ;
    ;
    ;
#include "main.inc"

    GLOBAL  PWM_init
PWM	CODE

PWM_init
TMR2_init
    banksel T2CON
    set_sfr T2CON,0x00
    set_sfr T2CLKCON,0x01
    set_sfr T2HLT,0x01
    clrf    T2RST
    set_sfr T2PR,0xb0
    clrf    T2TMR
    banksel PIR4
    bcf	    PIR4,TMR2IF
    banksel PIE4
    bsf	    PIE4,TMR2IE
    banksel T2CON
    bsf	    T2CON,TMR2ON
    bsf     INTCON,PEIE

PWM7_init
    banksel PWM7CON
    set_sfr PWM7CON,0x80
    set_sfr PWM7DCH,0x58
    set_sfr PWM7DCL,0x40
    banksel CCPTMRS1
    bsf	    CCPTMRS1,P7TSEL0

    retlw 1

    END
