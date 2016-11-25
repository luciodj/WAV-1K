
DIRread
;input  entry, root
    banksel entry
    movf    entry,W
    movwf   LBA         ; use LBA as working space
    movf    entry+1,W
    movwf   LBA+1
    clrf    LBA+2
    asrf    LBA+1       ; lba = entry >> 1
    rrf     LBA
    asrf    LBA+1       ; lba = entry >> 2
    rrf     LBA
    asrf    LBA+1       ; lba = entry >> 3
    rrf     LBA
    asrf    LBA+1       ; lba = entry >> 4
    rrf     LBA
    movf    root,W
    addwf   LBA         ; lba = root + (entry >> 4)
    movf    root+1,W
    addwfc  LBA+1
    movf    root+2,W
    addwfc  LBA+2
    ; fpage = -1
    bcf     fpage,0
    call    getBuffer   ; find a buffer
    goto    SD_SECTORread

getByteAtEntryPointerOffset
; input W    : offset [0-31]
; input ePointer: &B[CurBuf]
; output  W = ePointer[W]
    addwf   ePointer,W
    movwf   FSR0L
    movlw   0
    addwfc  ePointer+1,W
    movwf   FSR0H
    moviw   FSR0++
    return

getWordAtEntryPointerOffset
; input FSR0    : offset
; input ePointer: &B[CurBuf]
; output  W/WH = FSR0[ePointer]
    call    getByteAtEntryPointerOffset   ; discard the first byte
    moviw   FSR0--      ; then go backward
    movwf   WH          ; get the high
    moviw   FSR0--      ; get the low
    return


;---------------------------------------------------------------
ffind
; input entry: entry counter
; input FSR1:  pointer to extension
; 1-2. check if mounted
; 3. allocate file structure
; 4. set pointers to entry buffers
    call    initEntryPointer    ; get ePointer
; 5. start from given entry
    call    getBuffer
    call    DIRread     ; load sector for given entry
    bz      DIRloop
    movlw   FE_NOT_PRESENT
    goto    FileError
; 6.1 loop until you reach the end of the root directory

DIRloop
    movf    rootMax,W
    subwf   entry,W     ; entry - rootMax
    movf    rootMax+1,W
    subwfb  entry+1,W   ;
    bc      DIRLoopExit ; entry >= rootMax

    ; 6.0 get the offset in sector
    movf    entry,W
    andlw   0xf         ; find offset for entry (in sector)
    movwf   FSR0L
    movlw   0
    movwf   FSR0H
    aslf    FSR0L
    rlf     FSR0H
    aslf    FSR0L
    rlf     FSR0H
    aslf    FSR0L
    rlf     FSR0H
    aslf    FSR0L
    rlf     FSR0H
    aslf    FSR0L
    rlf     FSR0H       ; FSR0 = (entry & 0xF) *32
    movf    ePointer,W
    addwf   FSR0L,W
    movwf   ePointer
    movf    ePointer+1,W
    addwfc  FSR0H,W
    movwf   ePointer+1


    call    DIRread     ; to be loaded
    bz      DIRfound
    movlw   FE_NOT_PRESENT
    goto    FileError
DIRfound
    ; 6.1 read the first char of the file name
    movlw   DIR_NAME
    call    getByteAtEntryPointerOffset
    ; 6.2 terminate if reached end of dir or empty
    xorlw   DIR_EMPTY
    bz      DIRLoopExit
    ; 6.3 if deleted entry (ignore it)
    xorlw   DIR_EMPTY
    xorlw   DIR_DEL
    bz      DIRdeleted
    ; 6.4 check attributes
    movlw   DIR_ATTRIB
    call    getByteAtEntryPointerOffset
    andlw   ATT_HIDE | ATT_DIR
    bnz     DIRhidden
    ; 6.5 compare extension
    movlw   DIR_EXT
    call    getByteAtEntryPointerOffset
    movwf   temp
    moviw   FSR1++
    xorwf   temp,W
    bnz     DIRnomatch
    movlw   DIR_EXT+1
    call    getByteAtEntryPointerOffset
    movwf   temp
    moviw   FSR1++
    xorwf   temp,W
    bnz     DIRnomatch
    movlw   DIR_EXT+2
    call    getByteAtEntryPointerOffset
    movwf   temp
    moviw   FSR1++
    xorwf   temp,W
    bnz     DIRnomatch
FoundIt
    ; 8-9. entry found init file structure
    clrf    seek    ; first byte in file
    clrf    seek+1
    clrf    seek+2
    clrf    seek+3
    clrf    sec     ; first sector in the cluster
    clrf    pos     ; first byte in sector
    clrf    pos+1
    ; 10. set current cluster pointer
    movlw   DIR_CLST
    call    getWordAtEntryPointerOffset
    movwf   cluster ; first cluster in fat chain
    movf    WH,W
    movwf   cluster+1
    ; 12. determine how much data is really inside the sector
    movlw   DIR_SIZE
    call    getWordAtEntryPointerOffset
    movwf   size ; first cluster in fat chain
    movf    WH,W
    movwf   size+1
    movlw   DIR_SIZE+2
    call    getWordAtEntryPointerOffset
    movwf   size+2 ; first cluster in fat chain
    movf    WH,W
    movwf   size+3
    ; 13. increment entry
    movlw   1
    addwf   entry
    movlw   0
    addwfc  entry+1

    ; 11. read the first sector of data
    call    DATAread    ; get the sector of data
    bz      ffindSuccess
    movlw   FE_FIND_ERROR
    goto    FileError

ffindSuccess
    andlw   0
    return          ; Z success

DIRhidden
DIRnomatch
DIRdeleted
    movlw   1
    addwf   entry
    movlw   0
    addwfc  entry+1
    goto    DIRloop

DIRLoopExit
    movlw   FE_FILE_NOT_FOUND
    movwf   FError
    iorlw    1
    return      ; NZ failure