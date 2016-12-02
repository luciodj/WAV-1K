;
; fileio.inc
;

#define buffer      0x2000  ; -20ff
#define buffer1     0x2100  ; -21ff
#define buffer2     0x2200  ; -22ff


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



