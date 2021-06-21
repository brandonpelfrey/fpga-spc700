
# UART Setup (Linux)
```sudo stty -F /dev/ttyUSB0 cs8 -parenb -cstopb -clocal -ixon -inpck 460800```

# UART Commands

### Command Protocol
1. Host sends Command byte and N (>=0) parameter bytes.
2. Device processes command.
3. Device sends response byte. 
   - All bits are 1 if success.
   - All bits are 0 if parity or command error occurred.
4. (Optional) If Command has response bytes, these are sent.

### Function List
```
# General Functions
0x00 : Get Status -> ??
0x01 : Reset Audio Codec

# RAM Functions
0x10 : Set RAM, 1 Byte         (+2 address, + 1 value) -> 0
0x11 : Set RAM, Variable Bytes (+2 address, +1 N bytes, +N data bytes)

# DSP Functions
0x20 : Set DSP Register   (+1 byte address, +1 byte value)
0x21 : Get DSP Registers  -> 128 byte response
0x22 : DSP Reset

# Audio Functions
0x30 : Set DAC Volume (+1 byte volume: 0 mute, 0xFF max)
```