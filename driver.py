import sys
import serial

class FPGAController:
  def __init__(self, device_or_port) -> None:
    self.ser = serial.Serial(
      device_or_port,
      baudrate=460800,
      bytesize=serial.EIGHTBITS,
      parity=serial.PARITY_NONE,
      stopbits=serial.STOPBITS_ONE,
      timeout=None
    )

  def reset(self):
    '''Reset the system DSP / CPU'''
    self.ser.write([0])
    print("Sent APU reset")


if __name__ == '__main__':
  controller = FPGAController("/dev/ttyUSB0")
  if '--reset-dsp' in sys.argv:
    controller.reset()

