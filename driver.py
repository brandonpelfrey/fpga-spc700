import serial

ser = serial.Serial("/dev/ttyUSB0", baudrate=460800, bytesize=serial.EIGHTBITS, parity=serial.PARITY_NONE, stopbits=serial.STOPBITS_ONE, timeout=None)
#ser.open()
ser.write(b'hello')
