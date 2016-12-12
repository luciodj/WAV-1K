;
; serial.h
;
  ifdef DEBUG_PRINT

    extern serial_init, putch, putsz, puts
    extern putHex, printf, printLBA, dump, putNL

    #define SERIAL_INIT	    call serial_init

  else
	#define SERIAL_INIT
  endif
