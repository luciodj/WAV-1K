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
#define DIR_ESIZE          .32  ; size of a directory entry(bytes)
#define DIR_NAME          -.16  ;  0   ; offset file name
#define DIR_EXT            -.8  ;  8   ; offset file extension
#define DIR_ATTRIB         -.5  ; .11   ; offset attribute( 00ARSHDV)
#define DIR_CTIME          -.2  ; .14   ; creation time
#define DIR_CDATE            0  ; .16   ; creation date
#define DIR_ADATE           .2  ; .18   ; last access date
#define DIR_TIME            .6  ; .22   ; offset last use time  (word)
#define DIR_DATE            .8  ; .24   ; offset last use date  (word)
#define DIR_CLST           .10  ; .26   ; offset first cluster FAT (word)
#define DIR_SIZE           .12  ; .28   ; offset of file size (dword)

#define DIR_DEL          0xE5   ; marker deleted entry
#define DIR_EMPTY           0   ; marker last entry in directory

#define buffer	0x2100

.main	udata 0x20
temp	    res	    4
count       res     1
;WH          res     1
firstSec    res     2   ; assume always < 16 bit
;partSize    res     3
root        res     2   ; assume always < 16 bit
fat         res     2   ; assume allways < 16 bit
sdata       res     3
fatSize     res     2
;rootMax     res     2
;fatCopy     res     1
sxc         res     1   ; cluster size
curBuf      res     1
FError      res     1
cluster     res     2   ; cluster in fat
size        res     4   ; total file size
sec         res     1   ; sector in cluster
;ePointer    res     2   ; pointer to entry in buffer
;entry       res     2   ; entry in root [0-rootMax]
;seek        res     4   ; byte in file
;pos         res     2   ; position in sector
;fpage       res     1   ; flag of page caching

BCount      res     1   ; 256 bytes buffers
EmptyFlag   res     1   ; 1 = need refilling


.reset    CODE 0
reset_vector
    goto    main

.interrupt    CODE 4
interrupt_vector
    banksel PIR4
    bcf     PIR4,TMR2IF
    ; 1. handle skip via T2 postscaler
    ; 2. load the new sample
    ; handle only 8-bit mono!
    moviw   FSR1++
    banksel PWM7DCH
    movwf   PWM7DCH

    ; 3. check if buffer emptied
    banksel BCount
    decfsz  BCount
    retfie

    ; 3.1 swap buffers
    movlw   1
    xorwf   curBuf  ; toggle
    ; 3.2 buffer refilled
;    clrf    BCount
    ; 3.3 flag a new buffer needs to be prepared
    bsf     EmptyFlag,0
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

    call    serial_init
    goto    PWM_init

;---------------------------------------------------------------
AUDIO_init MACRO
    bcf     curBuf,0    ; start with buffer 0 active first
    LFSR1   buffer+25   ; put the audio pointer on its last byte
    bcf     EmptyFlag,0 ;
    ENDM

AUDIO_start MACRO
    bsf     INTCON,GIE
    ENDM
AUDIO_stop  MACRO
    bcf     INTCON,GIE
    ENDM
;---------------------------------------------------------------
MountError
FileError
    banksel FError
    movwf   FError
    iorlw   1
    return  ; FAIL NZ

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
 ifndef  __SKIP
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
    goto    MountError
 endif
ValidMBR
    ; read number of sectors in partition?
 ifndef __SKIP
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
 endif

ValidPartition
    ; 9. get the first sector (boot record) of the first partition
    LFSR0   buffer+FO_FIRST_SECT
    moviw   FSR0++
    banksel firstSec
    movwf   LBA
    movwf    firstSec
;    moviw   FSR0++
;    movwf   LBA+1
;    movwf    firstSec+1
;    moviw   FSR0++
;    movwf   LBA+2
;    movwf   firstSec+2

    ; 10. load the (Partition) Boot Record
    LFSR0   buffer
    call    SD_SECTORread
 ifndef  __SKIP
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
 endif

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
;    clrf    fat+2
    ; add the first sector LBA
    movf    firstSec,W
    addwf   fat
    movf    firstSec+1,W
    addwfc  fat+1
;    movf    firstSec+2,W
;    addwfc  fat+2

    LFSR0   buffer+BR_FAT_SIZE
    moviw   FSR0++
    movwf   fatSize
    moviw   FSR0++
    movwf   fatSize+1

; assume always fatCopy = 2
;    LFSR0   buffer+BR_FAT_CPY
;    moviw   FSR0++
;    movwf   fatCopy

;    btfss   fatCopy,1   ; if there is a single copy
;    goto    SingleFat
    aslf    fatSize     ; assuming double
    rlf     fatSize

AddFat
    ; 14. compute root LBA
    ; root = fat + fatSize * fatCopy (assuming fatCopy 1 or 2)
    movf    fat,W       ; root = fat+fatSize
    addwf   fatSize,W
    movwf   root
    movf    fat+1,W
    addwfc  fatSize+1,W
    movwf   root+1
; assume always root2 = 0
;    movlw   0
;    addwfc  fat+2,W
;    movwf   root+2

SingleFat
    ; 15. get max root
;    LFSR0   buffer+BR_MAX_ROOT
;    moviw   FSR0++
;    movwf   rootMax
;    moviw   FSR0++
;    movwf   rootMax+1

    ; 16. compute sdata LBA
    ; assume always rootMax = 512
    ; sdata = root + rootMax (* 32 / 512) = root + rootMax >> 4
;    asrf    rootMax+1   ; rootMax >>= 4
;    rrf     rootMax
;    asrf    rootMax+1
;    rrf     rootMax
;    asrf    rootMax+1
;    rrf     rootMax
;    asrf    rootMax+1
;    rrf     rootMax

    movf    root,W     ; sdata = root + (rootMax >> 4)
    addlw   0x10        ; 512 >> 4
;    addwf   rootMax,W
    movwf   sdata
    movlw   0
    addwfc  root+1,W
;    addlw   0
;    addwfc  rootMax+1,W
    movf    sdata+1
;    movlw   0
;    addwfc  root+2,W
;    movwf   sdata+2

    ; 17. get max cluster in partition (size)
    andlw   0
    return          ; success return Z

;---------------------------------------------------------------
DATAread
; input cluster, sxc, sec, sdata
    banksel cluster
    movlw   2           ; use LBA = cluster-2 as multiplicand
    subwf   cluster,W
    movwf   LBA
    movlw   0
    subwfb  cluster+1,W
    movwf   LBA+1
    clrf    LBA+2

    movf    sxc,W
    movwf   temp        ;
MultLoop
    rrf     temp        ; assume sxc is always a power of 2 (single byte)
    bc      MultLoopB   ; i.e. 0x10, 0x20, 0x40
    aslf    LBA         ; 24-bit shit left of LBA
    rlf     LBA+1
    rlf     LBA+2
    goto    MultLoop

MultLoopB
    ; add the sector within the cluster
    movf    sec,W
    addwf   LBA
    movlw   0
    addwfc  LBA+1
    addwfc  LBA+2

    ; add sdata
    movf    sdata,W
    addwf   LBA
    movf    sdata+1,W
    addwfc  LBA+1
    movf    sdata+2,W
    addwfc  LBA+2
    ; invalidate cahce
;    bcf     fpage,0
    call    getBuffer   ; find a buffer
    goto    SD_SECTORread

getBuffer
; input CurBuffer
; output FSR0 = &B[CurBuf]
    LFSR0   buffer
    banksel curBuf
    btfsc   curBuf,0
    incf    FSR0H
    return

;initPointer
;    movlw   LOW(buffer)     ; ePointer = &B[CurBuf*0x100]
;    banksel ePointer
;    movwf   ePointer
;    movlw   HIGH(buffer)
;    btfsc   curBuf,0
;    incf    WREG
;    movwf   ePointer+1
;    return
;
;getByteAt
;; input W    : offset [0-31]
;; input ePointer: &B[CurBuf]
;; output  W = ePointer[W]
;    addwf   ePointer,W
;    movwf   FSR0L
;    movlw   0
;    addwfc  ePointer+1,W
;    movwf   FSR0H
;    moviw   FSR0++
;    return


;---------------------------------------------------------------
ffind
; input FSR1:  pointer to extension
; 1-2. check if mounted
; 3. allocate file structure
; 4. set pointers to entry buffers
; 5. start from beginning of root
    LFSR0   buffer
    CPLBA   root
    call    SD_SECTORread

; 6. loop until you reach the end of the root directory (sector)
    movlw   .16         ; there are 16 entries in first sector of root
    banksel count
    movwf   count
;    call    initPointer
    LFSR0   buffer+.16  ; init pointer to middle of the first DIR entry
DIRloop
    ; 6.1 read the first char of the file name
;    movlw   DIR_NAME
;    call    getByteAt
    moviw   DIR_NAME[FSR0]
    ; 6.2 terminate if reached end of dir or empty
;    xorlw   DIR_EMPTY
    bz      DIRLoopExit
    ; 6.3 if deleted entry (ignore it)
;    xorlw   DIR_EMPTY
    xorlw   DIR_DEL
    bz      DIRdeleted
    ; 6.4 check attributes
    moviw   DIR_ATTRIB[FSR0]
;    call    getByteAt
    andlw   ATT_HIDE | ATT_DIR
    bnz     DIRhidden
    ; 6.5 compare extension
    moviw   DIR_EXT[FSR0]
;    call    getByteAt
    movwf   temp
    moviw   FSR1++
    xorwf   temp,W
    bnz     DIRnomatch
    moviw   DIR_EXT+1[FSR0]
;    call    getByteAt
    movwf   temp
    moviw   FSR1++
    xorwf   temp,W
    bnz     DIRnomatch
    moviw   DIR_EXT+1[FSR0]
;    call    getByteAt
    movwf   temp
    moviw   FSR1++
    xorwf   temp,W
    bnz     DIRnomatch
FoundIt
    ; 8-9. entry found init file structure
    clrf    sec         ; first sector in the cluster
    ; 10. set current cluster pointer
    moviw   DIR_CLST[FSR0]
;    call    getByteAt
    movwf   cluster     ; first cluster in fat chain
    moviw   DIR_CLST+1[FSR0]
    movwf   cluster+1
    ; 12. determine how much data is really inside the sector
    moviw   DIR_SIZE+1[FSR0]
;    call    getByteAt
;    movwf   size        ; file size
;    moviw   FSR0++
    movwf   size+1
    moviw   DIR_SIZE+2[FSR0]
    movwf   size+2
    moviw   DIR_SIZE+3[FSR0]
    movwf   size+3

    ; 11. read the first sector of data
    goto    DATAread    ; get the sector of data
;    bz      ffindSuccess
;    movlw   FE_FIND_ERROR
;    goto    FileError

;ffindSuccess
;    andlw   0
;    return          ; Z success

DIRhidden
DIRnomatch
DIRdeleted
;    movlw   .32
;    addwf   ePointer
;    movlw   0
;    addwfc  ePointer+1
;    decfsz   count
    addfsr  FSR0,.16
    addfsr  FSR0,.16
    decfsz   count
    goto    DIRloop

DIRLoopExit
    movlw   FE_FILE_NOT_FOUND
    movwf   FError
    iorlw    1
    return      ; NZ failure
;---------------------------------------------------------------
FATread
FATnext
;input cluster
;ouput cluster->next
;    movf    cluster+1,W     ; check if already in cache
;    xorwf   fpage,W
;    bz      FATreadB
    ; need to load a new page
    movf    cluster+1,W     ; LBA = cluster >> 8 (256 cluster/sec)
    addwf   fat,W
    movwf   LBA
    movlw   0
    addwfc  fat+1,W
    movwf   LBA+1
    movlw   0
    addwfc  WREG
    movwf   LBA+2           ; LBA = fat + (cluster >> 8)
    call    getBuffer
    call    SD_SECTORread
;    bz      FATreadB
;    movlw   FE_FAT_EOF
;    goto    FileError
FATreadB
;    movf    cluster+1,W
;    movwf   fpage           ; page is loaded
    ; read the next cluster
    call    getBuffer
    movf    cluster,W       ; W = (cluster &0xff)*2
    addwf   FSR0L
    movf    cluster+1,W
    addwfc  FSR0H
    movf    cluster,W       ; W = (cluster &0xff)*2
    addwf   FSR0L
    movf    cluster+1,W
    addwfc  FSR0H
; get the new cluster
    moviw   FSR0++
    movwf   cluster
    moviw   FSR0++
    movwf   cluster+1
    andlw   0
    return                  ; Z success

;---------------------------------------------------------------

;---------------------------------------------------------------
szError     dt  "Error: ",0
sWAV       dt  "WAV"

main
	call SYSTEM_init
	; enable interrupts

mainL
	movlw   .50	    ; 500 ms delay
	call    delay_10ms

;    LFSR1   szError
    call    mount
    bz      success
;    call    printf
    goto    mainL

success
    LFSR1   sWAV
    LFSR0   buffer
    call    ffind

;    LFSR0   buffer
;    movlw   .8
;    call    dump
;    call    putNL

; dump  fat
;    LFSR0   buffer
;    CPLBA   fat
;    call    SD_SECTORread
;    LFSR0   buffer
;    movlw   .8
;    call    dump
;    call    putNL
;
;    ; dump root
;    LFSR0   buffer
;    CPLBA   root
;    call    SD_SECTORread
;    LFSR0   buffer
;    movlw   .8
;    call    dump
;    call    putNL
;
;    ; dump sdata
;    LFSR0   buffer
;    CPLBA   sdata
;    call    SD_SECTORread
;    LFSR0   buffer
;    movlw   .8
;    call    dump
;    call    putNL

play
    bcf     curBuf,0    ; set audio to buffer 0
    AUDIO_start

playLoop
    ; check if file exhausted
    movlw   2           ; subtract 512
    subwf   size
    movlw   0
    subwfb  size+1
    subwfb  size+2
    bnc     stop        ; borrow (NC)

    ; check if button pressed
    ; check if buffer needs refilling
    btfsc   EmptyFlag,0
    goto    playLoop

    bcf     EmptyFlag,0
    ; refill buffer
    btfss   curBuf,0
    goto    cpyBuffer

    ; load a new buffer
    call    FATnext
    call    DATAread
    goto    playLoop

    ; copy buffer
cpyBuffer
;    clrf    count          ; cpy 256 bytes
    LFSR0   buffer+0x100    ; source buffer 1

cpyLoop
    moviw   FSR0++
    incf    FSR0H           ; destination buffer 2
    decf    FSR0L
    movwi   FSR0++
    decf    FSR0H           ; back to source
    decfsz  count
    goto    cpyLoop

    goto    playLoop

stop
    AUDIO_stop
	goto    stop

    END