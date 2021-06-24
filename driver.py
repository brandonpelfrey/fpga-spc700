import math
import sys
import serial
import time


class FPGAController:
  def __init__(self, device_or_port) -> None:
    self.ser = serial.Serial(
      device_or_port,
      baudrate=460800,
      bytesize=serial.EIGHTBITS,
      parity=serial.PARITY_NONE,
      stopbits=serial.STOPBITS_TWO,
      timeout=0.1
    )

  def get_response(self):
    return self.ser.read()

  def reset_audio(self):
    '''Reset the audio codec'''
    self.ser.write([0x01])
    resp = self.get_response()
    print(f"Sent audio codec reset. response {resp}")

  def reset_apu(self):
    '''Reset the system DSP / CPU'''
    self.ser.write([0x22])
    resp = self.get_response()
    print(f"Sent APU reset. response {resp}")

  def set_ram(self, address, nbytes, data):
    ''' Set APU RAM bytes) '''
    assert address >=0 and address+nbytes <= 0xFFFF
    assert nbytes >=1 and nbytes <= 256
    assert len(data) == nbytes
    self.ser.write([0x10, (address >> 8) & 0xFF, address & 0xFF, nbytes-1] + data)


if __name__ == '__main__':
  controller = FPGAController("/dev/ttyUSB0")
  if '--reset-apu' in sys.argv:
    controller.reset_apu()
  if '--reset-audio' in sys.argv:
    controller.reset_audio()

  if '--load-sample' in sys.argv:
    with open(sys.argv[-1], 'rb') as f:
      data = list(f.read())
      addr = 0
      transfer_size = 256
      while len(data) > 0:
        if len(data) >= transfer_size:
          controller.set_ram(addr, transfer_size, data[:transfer_size])  
        else:
          controller.set_ram(addr, len(data), data)

        # Transfer succeeded?
        resp = list(controller.get_response())
        print(f"Set RAM :: addr {addr:8} n_bytes {transfer_size:3} -> response {resp}")
        if len(resp) == 0:
          continue
        if list(resp)[0] > 0:
          continue

        data = data[transfer_size:]
        addr += transfer_size

  if '--test' in sys.argv:
      controller.set_ram(0x1234, 4, [5,6,7,8])
