;
;  fileio.asm
;
#include "main.inc"

#include sdmmc.inc
#include fileio.inc

; from fileio
    global  mount, find, read, next, size, sec, sxc

.fileio     udata 0x520     ; 0x2320 in linear memory
temp	    res	    1
count       res     1
boot        res     2   ; assume always < 16 bit
root        res     2   ; assume always < 16 bit
fat         res     2   ; assume always < 16
sdata       res     2   ; assume always < 16
fatSize     res     2
sxc         res     1   ; cluster size
FError      res     1
cluster     res     2   ; cluster in fat
size        res     4   ; total file size
sec         res     1   ; sector in cluster
;fatCopy     res     1  ; assume always two copies

    CODE
;---------------------------------------------------------------
MountError
FileError
    banksel FError
    movwf   FError
    banksel PORTA
;    movwf   PORTA      ; DBG
    bsf     LED_ERROR
    iorlw   0
    return  ; FAIL NZ

;---------------------------------------------------------------
 ifdef DEBUG_PRINT
szError     dt  "Error: ",0
szFAT       dt  "FAT: ",0
szRoot      dt  "Root:",0
szBoot      dt  "Boot:",0
szData      dt  "Data:",0
szSize      dt  "Size:",0
szCluster   dt  "Cluster:",0
szSector    dt  "Sector:",0
 endif

;---------------------------------------------------------------
mount
    ; 1-2. try to init media (detect presence)
    call    SD_MEDIAinit
    bz      MediaInitialized
    movlw   FE_NOT_PRESENT
    goto    MountError

MediaInitialized
    ; 3-4. take the first buffer
    LFSR0   buffer

    ; 5. get the Master Boot Record
    LLBA    FO_MBR
    call    SD_SECTORread

 ifdef  DEBUG_PRINT
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
 ifdef DEBUG_PRINT
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
;    movlw   FE_PARTITION_TYPE
    movf   temp,W
    goto    MountError
 endif

ValidPartition
    ; 9. get the first sector (boot record) of the first partition
    LFSR0   buffer+FO_FIRST_SECT
    moviw   FSR0++
    banksel boot
    movwf   LBA
    movwf    boot
    moviw   FSR0++
    movwf   LBA+1
    movwf    boot+1
    clrf    LBA+2

;  ifdef DEBUG_PRINT
;    LFSR1   szBoot
;    call    printLBA
;  endif
;
    ; 10. load the (Partition) Boot Record
    LFSR0   buffer
    call    SD_SECTORread
 ifdef  DEBUG_PRINT
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
    LFSR0   buffer
    moviw   BR_SXC[FSR0]
    movwf   sxc

    ; 13. get FAT info (offset, size, num. copies)
;    LFSR0   buffer+BR_RES
    moviw   BR_RES[FSR0]
    movwf   fat         ; fat offset(word)
    moviw   (BR_RES+1)[FSR0]
    movwf   fat+1

    ; add the first sector LBA
    movf    boot,W
    addwf   fat
    movf    boot+1,W
    addwfc  fat+1

; ifdef DEBUG_PRINT
;    LFSR1   szFAT
;    CPLBA   fat
;    call    printLBA
; endif

;    LFSR0   buffer+BR_FAT_SIZE
    moviw   BR_FAT_SIZE[FSR0]
    movwf   fatSize
    moviw   (BR_FAT_SIZE+1)[FSR0]
    movwf   fatSize+1

; assume always fatCopy = 2
;    LFSR0   buffer+BR_FAT_CPY
;    moviw   FSR0++
;    movwf   fatCopy

;    btfss   fatCopy,1   ; if there is a single copy
;    goto    SingleFat
    aslf    fatSize     ; assuming double
    rlf     fatSize+1   ; *= 2

    ; 14. compute root LBA
    ; root = fat + fatSize * fatCopy (assuming fatCopy == 2)
    movf    fat,W       ; root = fat+fatSize*2
    addwf   fatSize,W
    movwf   root
    movf    fat+1,W
    addwfc  fatSize+1,W
    movwf   root+1

; ifdef DEBUG_PRINT
;    LFSR1   szRoot
;    CPLBA   root
;    call    printLBA
; endif

;SingleFat
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

    banksel root
    movf    root,W     ; sdata = root + (rootMax >> 4)
    addlw   0x20        ; 512 >> 4
    movwf   sdata
    movlw   0
    addwfc  root+1,W
    movwf   sdata+1

; ifdef DEBUG_PRINT
;    LFSR1   szData
;    CPLBA   sdata
;    call    printLBA
; endif

    ; 17. get max cluster in partition (size)
    andlw   0
    return          ; success return Z


;---------------------------------------------------------------
find
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
    moviw   DIR_NAME[FSR0]
    ; 6.2 terminate if reached end of dir or empty
    bz      DIRLoopExit
    ; 6.3 if deleted entry (ignore it)
    xorlw   DIR_DEL
    bz      DIRdeleted
    ; 6.4 check attributes
    moviw   DIR_ATTRIB[FSR0]
    andlw   ATT_HIDE | ATT_DIR
    bnz     DIRhidden
    ; 6.5 compare extension
    moviw   DIR_EXT[FSR0]
    xorlw   'W'
    bnz     DIRnomatch
    moviw   DIR_EXT+1[FSR0]
    xorlw   'A'
    bnz     DIRnomatch
    moviw   DIR_EXT+2[FSR0]
    xorlw   'V'
    bnz     DIRnomatch
FoundIt
    ; 8-9. entry found init file structure
    clrf    sec         ; first sector in the cluster
    ; 10. set current cluster pointer
    moviw   DIR_CLST[FSR0]
    movwf   cluster     ; first cluster in fat chain
    moviw   DIR_CLST+1[FSR0]
    movwf   cluster+1

;    LFSR1   szCluster
;    CPLBA   cluster
;    clrf    LBA+2
;    call    printLBA
;    banksel size

    ; 12. determine how much data is really inside the file
    clrf    size        ; ignore the LSB
    moviw   DIR_SIZE+1[FSR0]
    movwf   size+1
    moviw   DIR_SIZE+2[FSR0]
    movwf   size+2
    moviw   DIR_SIZE+3[FSR0]
    movwf   size+3

;    LFSR1   szSize
;    CPLBA   size
;    goto    printLBA

    ; 11. read the first sector of data
    goto    read    ; get the sector of data

DIRhidden
DIRnomatch
DIRdeleted
    addfsr  FSR0,.16
    addfsr  FSR0,.16
    decfsz  count
    goto    DIRloop

DIRLoopExit
    movlw   FE_FILE_NOT_FOUND
    movwf   FError
    iorlw   0
    return      ; NZ failure

;---------------------------------------------------------------
next
;input cluster
;ouput cluster->next
    movf    cluster+1,W     ; LBA = cluster >> 8 (256 cluster/sec)
    addwf   fat,W
    movwf   LBA
    movlw   0
    addwfc  fat+1,W
    movwf   LBA+1
    movlw   0
    addwfc  WREG
    movwf   LBA+2           ; LBA = fat + (cluster >> 8)
    LFSR0   buffer
    call    SD_SECTORread
;    bz      FATreadB
;    movlw   FE_FAT_EOF
;    goto    FileError

FATreadB
    banksel cluster
    LFSR0   buffer
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
read
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
    movlw   0
    addwfc  LBA+2

    LFSR0   buffer          ; load the first sector
    goto    SD_SECTORread

    END