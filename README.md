WAV-1k
======

A simple audio player  in less than 1K of code.

Reads WAV files from an SD card formatted in FAT16 (\<2GB).

Audio files must be 8-bit mono, uncompressed PCM, 44.100Hz (.WAV) files.

Designed as a demonstration for the XPRESS evaluation board using an
SD-Click(tm) board.

Target microcontroller is PIC16F18855, although any similar PIC16F1 device will
work provided the presence of 1KB of Flash, 1K of RAM, PWM and SPI modules.

Output is provided on pin RC7 (PWM). Connect any audio amplifier between RC7 and
GND.

Serial output can be enabled choosing the “debugging" configuration.

Select the “final" configuration for minimal code size \<1KB!

In the final configuration only the four LEDs are used to provide user feedback:

LED0: Successful mount of FAT16 File System

LED1: .WAV file found

LED2: Ready for playback (off during playback)

LED3: ERROR: card not present (or incompatible)

 

NOTE: Only the first .WAV file found in the root directory will be played
repeatedly when the USER button is pressed.

 
