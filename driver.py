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

  def set_dsp_reg(self, addr, val):
    self.ser.write([0x20, addr & 0xFF, val & 0xFF])
    resp = self.get_response()
    print(f"DSP reg [0x{addr:02X}] <- 0x{val:02X}, resp {resp}")

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

  def set_pitch(self, channel, pitch_value):
    assert channel >= 0 and channel <= 7
    assert pitch_value < 4096*4
    reg_lo = (channel << 4) | 0x02
    val_lo = pitch_value & 0xFF
    self.set_dsp_reg(reg_lo, val_lo)

    reg_hi = (channel << 4) | 0x03
    val_hi = (pitch_value >> 8) & 0x3F
    self.set_dsp_reg(reg_hi, val_hi)    

  def load_ram(self, path):
    with open(path, 'rb') as f:
      data = list(f.read())
      addr = 0
      transfer_size = 256
      while len(data) > 0:
        if len(data) >= transfer_size:
          self.set_ram(addr, transfer_size, data[:transfer_size])  
        else:
          self.set_ram(addr, len(data), data)

        # Transfer succeeded?
        resp = list(self.get_response())
        print(f"Set RAM :: addr {addr:8} n_bytes {transfer_size:3} -> response {resp}")
        if len(resp) == 0:
          continue
        if list(resp)[0] > 0:
          continue

        data = data[transfer_size:]
        addr += transfer_size

def load_and_play(controller, path):
  controller.load_ram(path)
  controller.reset_apu()

def all(controller, path):
  from os import listdir
  from os.path import isfile, join
  files = [f"{path}/{f}" for f in listdir(path) if isfile(join(path, f)) and '.brr' in f]

  for f in files:
    print(f)
    load_and_play(controller, f)
    time.sleep(1)

def loopy(controller):
  t = 0.0
  while True:
    min_pitch = 512
    max_pitch = 2048
    s = (math.sin(t * .1) + 1.0 ) / 2.0
    pitch = int( min_pitch + (max_pitch - min_pitch) * s)

    controller.set_pitch(0, pitch)
    time.sleep(0.1)
    t += 1

if __name__ == '__main__':
  controller = FPGAController("/dev/ttyUSB0")

  for i in range(len(sys.argv)):
    if '--reset-apu' == sys.argv[i]:
      controller.reset_apu()
    if '--reset-audio' == sys.argv[i]:
      controller.reset_audio()
    if '--load-sample' == sys.argv[i]:
      controller.load_ram(sys.argv[i+1])

    if '--set-dsp-reg' == sys.argv[i]:
      controller.set_dsp_reg(int(sys.argv[i+1]), int(sys.argv[i+2]))

    if '--set-pitch' == sys.argv[i]:
      controller.set_pitch( int(sys.argv[i+1]), int(sys.argv[i+2]) )

    if '--loopy' == sys.argv[i]:
      loopy(controller)

    if '--all' == sys.argv[i]:
      all(controller, sys.argv[i+1])
