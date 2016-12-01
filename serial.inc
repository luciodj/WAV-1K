    ;
    ;	serial port
    ;
    ifdef DEBUG_PRINT

      extern serial_init, putch, putsz, puts
      extern putHex, printf, printLBA, dump, putNL

	#define SERIAL_INIT	    call serial_init
	#define PUTCH	    call putch
	#define PUTSZ	    call putsz
	#define PUTS	    call puts
	#define PUTHEX	    call putHex
	#define PRINTF	    call printf
	#define PRINTLBA    call printLBA
	#define DUMP	    call dump
	#define PUTNL	    call putNL

    else
	#define SERIAL_INIT
	#define PUTCH
	#define PUTZ
	#define PUTS
	#define PUTHEX
	#define PRINTF
	#define PRINTLBA
	#define DUMP
	#define PUTNL
    endif
