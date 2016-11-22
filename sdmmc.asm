    ;
    ; SDMMC.asm
    ;
#include "main.inc"
    
    GLOBAL  SD_MEDIAinit, SD_SECTORread, LBAHH, LBAHL, LBAH, LBA
    
; SD card commands
#define CMD_RESET		0 ; a.k.a. GO_IDLE (CMD0)
#define CMD_INIT                .1 ; a.k.a. SEND_OP_COND (CMD1)
#define CMD_SEND_CSD            .9
#define CMD_SEND_CID           .10
#define CMD_SET_BLEN           .16
#define CMD_READ_SINGLE        .17 ; read a single sector of data
#define CMD_WRITE_SINGLE       .24
#define CMD_APP_CMD            .55
#define CMD_SEND_APP_OP        .41

; SD card responses
#define DATA_START	    0xFE
#define DATA_ACCEPT	    0x05
    
    UDATA_SHR 0x70 
LBA	res 1
LBAH	res 1
LBAHL	res 1
LBAHH	res 1
count	res 1
countH	res 1
	

;---------------------------------------------------------------
SDMMC	CODE

SD_Enable MACRO 
    banksel LATB
    bcf	    SD_CS
    ENDM
    
SD_Disable  MACRO
    banksel LATB
    bsf	    SD_CS
    ENDM
    
SPI_read MACRO 
    movlw   0xFF
    call    SPI_write
    ENDM

SPI_init_slow
    banksel SSP1STAT
    set_sfr SSP1STAT,0x40
    set_sfr SSP1CON1,0x2A
    set_sfr SSP1ADD, .79
    retlw   1
    
SPI_init_fast
    banksel SSP1STAT
    set_sfr SSP1STAT,0x40
    set_sfr SSP1CON1,0x20
    clrf    SSP1ADD
    retlw   1
    
SPI_write
; input W value to write    
; output W read value
; output bank0
    banksel SSP1CON1
    bcf	    SSP1CON1,WCOL
    movwf   SSP1BUF
    wait_until	SSP1STAT,BF
    movf    SSP1BUF,W
    return    
    
    
;----------------------------------------------------------------    
SD_CMDsend
; input LBA desired LBA
; input W   desired CMD
; output W : status, SD still enabled!
    SD_Enable
    ; 1. send the command : W
    iorlw   0x40    ; add frame bit
    call    SPI_write
    ; 2. send the address : LBA * 512 (LBA << 9)
    rlf	    LBAH,W	
    rlf	    LBAHL,W 
    call    SPI_write
    rlf	    LBA,W
    rlf	    LBAH,W
    call    SPI_write
    CLRC
    rlf	    LBA,W
    call    SPI_write
    movlw   0
    call    SPI_write
    ; 3. send CMD0 CRC
    movlw   0x95	
    call    SPI_write
    
    ; 4. wait for a response (allow up to 8 bytes delay)
    movlw   .9
    movwf   count
SD_CMDsendL
    SPI_read	; check if ready
    xorlw   0xFF
    bnz	    SD_CMDsendB
    decfsz  count
    goto    SD_CMDsendL
    
SD_CMDsendB
    xorlw   0xFF
    return	

    ; left SD enabled!
; return responses
;    FF - timeout 
;    00 - command accepted
;    01 - command received, card in idle state after RESET

;other codes:
;    bit 0 = Idle state
;    bit 1 = Erase Reset
;    bit 2 = Illegal command
;    bit 3 = Communication CRC error
;    bit 4 = Erase sequence error
;    bit 5 = Address error
;    bit 6 = Parameter error
;    bit 7 = Always 0
    
;-----------------------------------------------        
SD_MEDIAinit
    call SPI_init_slow
    ; 1. with the card not selected
    SD_Disable

    ; 2. send 80 clock cycles to start up
    movlw   .10
    movwf   count
SD_MEDIAinitL1    
    movlw   0xFF
    call    SPI_write
    decfsz  count
    goto    SD_MEDIAinitL1
    ; 3. now select the card
    SD_Enable    
    ; 4. send a Reset command to enter SPI mode
    clrf    LBAHH
    clrf    LBAHL
    clrf    LBAH
    clrf    LBA
    movlw   CMD_RESET
    call    SD_CMDsend
    SD_Disable
    xorlw   0x01
    bz	    SD_MEDIA5
    retlw   0x84    ; reset command not accepted
    
    ; 5. send repeatedly INIT
SD_MEDIA5
    movlw   HIGH(10000)+1
    movwf   countH
    movlw   LOW(10000)
    movwf   count

SD_MEDIAinitL2
    movlw   CMD_INIT
    call    SD_CMDsend
    SD_Disable
    andlw   1
    bz	    SD_MEDIAinitB
    decfsz  count
    goto    SD_MEDIAinitL2
    decfsz  countH
    goto    SD_MEDIAinitL2
    iorlw   1
    retlw   0x85	 ; init failure
    
SD_MEDIAinitB
;    call    SPI_init_fast
    andlw   0		; Z success
    return
	
;-------------------------------------------------------
SD_SECTORread
; input LBA selected lba
; input FSR0 :	data buffer
; output W success if 00, failure otherwise

    ; 1. send read command
    movlw   CMD_READ_SINGLE
    call    SD_CMDsend
    andlw   1
    bnz	    SD_SECTORreadE
    ; 2. wait for DATA_START
SD_SECTORwait
    movlw   HIGH(10000)+1
    movwf   countH
    movlw   LOW(10000)
    movwf   count    
SD_SECTORwaitL
    SPI_read
    xorlw   DATA_START
    bz	    SD_SECTORwaitB
    decfsz  count
    goto    SD_SECTORwaitL
    decfsz  countH
    goto    SD_SECTORwaitL
SD_SECTORwaitB
    bnz	    SD_SECTORreadE  ; NZ failure
    ; 3. read data
    clrf    count	; two blocks of 256
read_loop
    movlw   0xff
    movwf   SSP1BUF
    nop
    nop
    nop
    nop
    movf    SSP1BUF,W
    movwi   FSR0++
    decfsz  count
    goto    read_loop
read_loop2
    movlw   0xff
    movwf   SSP1BUF
    nop
    nop
    nop
    nop
    movf    SSP1BUF,W
    movwi   FSR0++
    decfsz  count
    goto    read_loop
    
    ; 5. ignore CRC
    SPI_read
    SPI_read
    andlw   0	    ; set Z
    
SD_SECTORreadE
    SD_Disable
    return	    ; Z success    
    
    END
