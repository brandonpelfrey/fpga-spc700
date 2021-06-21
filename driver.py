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

  def reset_audio(self):
    '''Reset the audio codec'''
    self.ser.write([0x01])
    print("Sent audio codec reset")

  def reset_apu(self):
    '''Reset the system DSP / CPU'''
    self.ser.write([0x22])
    print("Sent APU reset")


if __name__ == '__main__':
  controller = FPGAController("/dev/ttyUSB0")
  if '--reset-apu' in sys.argv:
    controller.reset_apu()
  if '--reset-audio' in sys.argv:
    controller.reset_audio()

