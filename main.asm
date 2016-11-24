; PIC16F18855 Configuration Bit Settings

#include "main.inc"

#include "config.inc"
#include "delay.inc"
#include "serial.inc"
#include "pwm.inc"
#include "sdmmc.inc"

;-------------------------------------------------------------
; Master Boot Record key fields offsets
#define FO_MBR             0    ; master boot record sector LBA
#define FO_FIRST_P      0x1BE   ; offset of first partition table
#define FO_FIRST_TYPE   0x1C2   ; offset of first partition type
#define FO_FIRST_SECT   0x1C6   ; first sector of first partition
#define FO_FIRST_SIZE   0x1CA   ; number of sectors in partition
#define FO_SIGN         0x1FE   ; MBR signature location (55,AA)

#define FAT_EOF        0xffff   ; last cluster in a file
#define FAT_MCLST      0xfff8   ; max cluster value in a fat

; Partition Boot Record key fields offsets
#define BR_SXC            0xd   ; (byte) sector per cluster
#define BR_RES            0xe   ; (word) res sectors boot record
#define BR_FAT_SIZE      0x16   ; (word) FAT size sectors
#define BR_FAT_CPY       0x10   ; (byte) number of FAT copies
#define BR_MAX_ROOT      0x11   ; (odd word) max entries root dir

; directory entry management
#define DIR_ESIZE         .32   ; size of a directory entry(bytes)
#define DIR_NAME            0   ; offset file name
#define DIR_EXT             8   ; offset file extension
#define DIR_ATTRIB        .11   ; offset attribute( 00ARSHDV)
#define DIR_CTIME         .14   ; creation time
#define DIR_CDATE         .16   ; creation date
#define DIR_ADATE         .18   ; last access date
#define DIR_TIME          .22   ; offset last use time  (word)
#define DIR_DATE          .24   ; offset last use date  (word)
#define DIR_CLST          .26   ; offset first cluster FAT (word)
#define DIR_SIZE          .28   ; offset of file size (dword)
#define DIR_DEL          0xE5   ; marker deleted entry
#define DIR_EMPTY           0   ; marker last entry in directory

#define buffer	0x2100

.main	udata 0x20
temp	    res	    1
firstSec    res     3
partSize    res     3
root        res     3
fat         res     3
sdata       res     3
fatSize     res     2
rootMax     res     2
fatCopy     res     1
sxc         res     1
curBuf      res     1
FError      res     1



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
mount
    ; 1-2. try to init media (detect presence)
    call    SD_MEDIAinit
    bz      MediaInitialized
    movlw   FE_NOT_PRESENT
    goto    MountError

MediaInitialized
    ; 3-4. take the first buffer
    clrf    curBuf
    LFSR0   buffer

    ; 5. get the Master Boot Record
    LLBA    FO_MBR
    movf    LBA,W
    call    SD_SECTORread
    bnz     MBRError

    ; 6. check signature
    LFSR0   buffer+FO_SIGN
    moviw   FSR0++
    xorlw   0x55
    bnz     MBRError
    moviw   FSR0++
    xorlw   0xAA
    bz      ValidMBR
MBRError
    movlw   FE_INVALID_MBR

MountError
    banksel FError
    movwf   FError
    LFSR1   szError
    movf    FError,W
    call    printf
    goto    mainL
    iorlw   1
    return  ; FAIL NZ

ValidMBR
    ; read number of sectors in partition?

    ; 8. check for compatible partition type
    LFSR0   buffer+FO_FIRST_TYPE
    moviw   FSR0++
    banksel temp
    movwf   temp
    movlw   0x04
    xorwf   temp,W
    bz      ValidPartition
    movlw   0x06
    xorwf   temp,W
    bz      ValidPartition
    movlw   0x0E
    xorwf   temp,W
    bz      ValidPartition
PartitionError
    movlw   FE_PARTITION_TYPE
    goto    MountError

ValidPartition
    ; 9. get the first sector (boot record) of the first partition
    LFSR0   buffer+FO_FIRST_SECT
    moviw   FSR0++
    banksel firstSec
    movwf   LBA
    movwf    firstSec
    moviw   FSR0++
    movwf   LBA+1
    movwf    firstSec+1
    moviw   FSR0++
    movwf   LBA+2
    movwf   firstSec+2

    ; 10. load the (Partition) Boot Record
    LFSR0   buffer
    movf    LBA,W
    call    SD_SECTORread
    bnz     BRError

    ; 11. check for the signature again
    LFSR0   buffer+FO_SIGN
    moviw   FSR0++
    xorlw   0x55
    bnz     BRError
    moviw   FSR0++
    xorlw   0xAA
    bz      ValidBR
BRError
    movlw   FE_INVALID_BR
    goto    MountError

ValidBR
    ; 12. determine the cluster size
    banksel sxc
    LFSR0   buffer+BR_SXC
    moviw   FSR0++
    movwf   sxc

    ; 13. get FAT info (offset, size, num. copies)
    LFSR0   buffer+BR_RES
    moviw   FSR0++
    movwf   fat         ; fat offset
    moviw   FSR0++
    movwf   fat+1
    clrf    fat+2
    ; add the first sector LBA
    movf    firstSec,W
    addwf   fat
    movf    firstSec+1,W
    addwfc  fat+1
    movf    firstSec+2,W
    addwfc  fat+2

    LFSR0   buffer+BR_FAT_SIZE
    moviw   FSR0++
    movwf   fatSize
    moviw   FSR0++
    movwf   fatSize+1

    LFSR0   buffer+BR_FAT_CPY
    moviw   FSR0++
    movwf   fatCopy

    ; 14. compute root LBA
    ; root = fat + fatSize * fatCopy (assuming fatCopy 1 or 2)
    movf    fat,W       ; root = fat+fatSize
    addwf   fatSize,W
    movwf   root
    movf    fat+1,W
    addwfc  fatSize+1,W
    movwf   root+1
    movlw   0
    addwfc  fat+2,W
    movwf   root+2

    btfss   fatCopy,1   ; if there is a single copy
    goto    SingleFat

AddFat
    movf    fatSize,W       ; add again fatSize
    addwf   root
    movf    fatSize+1,W
    addwfc  root+1
    movlw   0
    addwfc  root+2

SingleFat
    ; 15. get max root
    LFSR0   buffer+BR_MAX_ROOT
    moviw   FSR0++
    movwf   rootMax
    moviw   FSR0++
    movwf   rootMax+1

    ; 16. compute sdata LBA
    ; sdata = root + rootMax (* 32 / 512) = root + rootMax >> 4
    asrf    rootMax+1   ; rootMax >>= 4
    rrf     rootMax
    asrf    rootMax+1
    rrf     rootMax
    asrf    rootMax+1
    rrf     rootMax
    asrf    rootMax+1
    rrf     rootMax

    movf    root,W     ; sdata = root + (rootMax >> 4)
    addwf   rootMax,W
    movwf   sdata
    movf    root+1,W
    addwfc  rootMax+1,W
    movf    sdata+1
    movlw   0
    addwfc  root+2,W
    movwf   sdata+2

    ; 17. get max cluster in partition (size)
    andlw   0
    return          ; success return Z

;---------------------------------------------------------------
szError     dt  "Error: ",0

main
	call SYSTEM_init
	; enable interrupts

mainL
	movlw   .50	    ; 500 ms delay
	call    delay_10ms

    LFSR1   szError
    call    mount
    bz      success
    call    printf

success
; dump  fat
    LFSR0   buffer
    CPLBA   fat
    call    SD_SECTORread
    LFSR0   buffer
    movlw   .8
    call    dump
    call    putNL

    ; dump root
    LFSR0   buffer
    CPLBA   root
    call    SD_SECTORread
    LFSR0   buffer
    movlw   .8
    call    dump
    call    putNL

    ; dump sdata
    LFSR0   buffer
    CPLBA   sdata
    call    SD_SECTORread
    LFSR0   buffer
    movlw   .8
    call    dump
    call    putNL

stop
	goto    stop

    END