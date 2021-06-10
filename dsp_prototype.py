import struct
from sys import argv
import wave
import enum

def gen_header(_range, filter, loop, end):
  return ((int(_range) & 0b1111) << 4) \
    | ((int(filter) & 0b11) << 2)      \
    | ((int(loop) & 0b1) << 1)         \
    | (int(end) & 0b1)

def twos_comp(val, bits):
  """compute the 2's complement of int value val"""
  # https://stackoverflow.com/a/9147327
  if (val & (1 << (bits - 1))) != 0: # if sign bit is set e.g., 8bit: 128-255
      val = val - (1 << bits)        # compute negative value
  return val                         # return positive value as is

####################################################

class Memory:
  def __init__(self):
    self.data = {}

  def put(self, addr, bytes):
    for i, dat in enumerate(bytes):
      self.data[addr + i] = dat
  
  def get(self, addr):
    if addr in self.data:
      return self.data[addr]
    return 0xFF

class States(enum.Enum):
  INIT = 0
  READ_HEADER = 1
  READ_DATA = 2
  PROCESS = 3
  OUTPUT_AND_WAIT = 4
  END = 5

# class VoiceData:
#   def __init__(self):
#     self.cursor_i = 0

class Decoder:
  READ_BUFFER_LENGTH = 8

  def __init__(self, start_addr, loop_addr = 0xFFFF):
    self.reset()
    self._start_addr = start_addr
    self._loop_addr = loop_addr

  def reset(self):
    self.cursor_i = 0
    self.cursor   = 0
    self.state = States.INIT

    self.read_buffer   = [0] * 8
    self.filter_buffer = [0] * 8
    self.read_buffer_index = 0
    self.block_index   = 0

    self.previous_samples = [0, 0]
    self.output = 0

    self.unused_samples = 0
    self.advance_trigger = 0

    self.ram_addr = 0
    self.ram_data = 0xFF

  def settle_ram(self, memory):
    self.ram_data = memory.get(self.ram_addr)

  def log(self, string):
    print(f" - {string}")

  def step(self):
    if self.state == States.INIT:
      self.ram_addr = self._start_addr
      self.state = States.READ_HEADER

    elif self.state == States.READ_HEADER:
      self.header = self.ram_data
      self.range  = (self.ram_data >> 4) & 0b1111
      self.filter = (self.ram_data >> 2) & 0b11
      self.loop   = (self.ram_data >> 1) & 0b1
      self.end    = (self.ram_data >> 0) & 0b1

      self.log(f"Read header: 0x{self.header:X} (Range {self.range}, Filter {self.filter})")
      self.state = States.READ_DATA
      self.ram_addr = self.ram_addr + 1
      self.block_index = 0

    elif self.state == States.READ_DATA:
      nibble0 = (self.ram_data >> 4) & 0b1111
      nibble1 = (self.ram_data >> 0) & 0b1111

      index0 = self.read_buffer_index
      index1 = (self.read_buffer_index + 1) % Decoder.READ_BUFFER_LENGTH

      self.read_buffer  [index0] = twos_comp(nibble0 << self.range, self.range+4)
      self.filter_buffer[index0] = self.filter
      self.read_buffer  [index1] = twos_comp(nibble1 << self.range, self.range+4)
      self.filter_buffer[index1] = self.filter
      if self.unused_samples >= 2:
        # We have four now, go to process
        self.state = States.PROCESS
      else:
        if self.block_index == 8:
          self.state = States.END if self.end and not self.loop else States.READ_HEADER
          if self.end and self.loop:
            self.ram_addr = self._loop_addr
        else:
          self.state = States.READ_DATA

      self.log(f"Read0, New byte is 0x{self.ram_data:02X}, n0 0x{nibble0:X}, n1 0x{nibble1:X}, wrote to [{index0}, {index1}], unused_samples now {self.unused_samples+2}")
      self.read_buffer_index = (self.read_buffer_index + 2) % Decoder.READ_BUFFER_LENGTH
      self.unused_samples += 2
      self.ram_addr = self.ram_addr + 1  # TODO: Handle looping case
      self.block_index += 1
        
    elif self.state == States.PROCESS:
      self.log(f"Entering PROCESS, cursor {self.cursor}")
      if self.cursor >= 4096:
        
        # Select from the correct combinatorial logic
        new_sample = int(self.filter_out)
        self.previous_samples = [new_sample, self.previous_samples[0]]

        # self.log(f"New Sample [filter {filter}] = {new_sample} ({new_sample:04X}h) cursor_i {self.cursor_i} cursor {self.cursor}")
        # self.log(f"Previous samples now {self.previous_samples}")
        # self.log(f"                                                                 {new_sample}")

        self.cursor -= 4096
        self.cursor_i = (self.cursor_i + 1) % Decoder.READ_BUFFER_LENGTH
        self.unused_samples -= 1
      
      else:
        self.log(f"No more samples to decode, output is {self.output}, transitioning to OUTPUT_AND_WAIT")
        self.state = States.OUTPUT_AND_WAIT

    elif self.state == States.OUTPUT_AND_WAIT:
      if self.advance_trigger:
        self.advance_trigger = 0
        if self.unused_samples < 4:

          if self.block_index == 8:
            self.state = States.END if self.end and not self.loop else States.READ_HEADER
            if self.end and self.loop:
              self.ram_addr = self._loop_addr
          else:
            self.state = States.READ_DATA

        else:
          self.state = States.PROCESS

    elif self.state == States.END:
      pass
  
  def settle_comb(self):
    A = [0, .9375, 1.90625, 1.796875]
    B = [0, 0, -0.9375, -.8125]

    a = A[self.filter_buffer[self.cursor_i]]
    b = B[self.filter_buffer[self.cursor_i]]
    self.filter_out = self.read_buffer[self.cursor_i] + a * self.previous_samples[0] + b * self.previous_samples[1]

    t = (int(self.cursor) % 4096) / 4096.0
    self.output = self.previous_samples[0] * t + self.previous_samples[1] * (1 - t)

#####################################################

def test(brr_data, loop_offset):
  mem = Memory()
  mem.put(0, brr_data)

  start_addr = 0
  loop_addr = start_addr + loop_offset
  decoder = Decoder(start_addr, loop_addr)

  # Modify the pitch/playback speed if desired
  pitch = 4096 * 2**0  

  # It's important to start at pitch + 4096 to consume the starting sample in the waveform
  decoder.cursor = pitch + 4096

  with wave.open("test.wav", "wb") as wave_file:
    wave_file.setnchannels(1)
    wave_file.setsampwidth(2)
    wave_file.setframerate(32000)

    output_samples = 0
    total_steps = 0
    while output_samples < 32000 and total_steps < 200000:
      total_steps += 1
      
      print(f"[{total_steps:05}] State {States(decoder.state).name}")
      decoder.step()
      decoder.settle_ram(mem)
      decoder.settle_comb()

      if decoder.state == States.OUTPUT_AND_WAIT:
        print("--------------------------------------------")
        print(f"@@ Reachout output state. Advancing pitch")
        
        wave_file.writeframesraw(struct.pack('<h', int(decoder.output)))
        output_samples += 1

        decoder.cursor += pitch
        decoder.advance_trigger = 1

      elif decoder.state == States.END:
        break

  wave_file.close()


if __name__ == '__main__':
  import sys

  if '--help' in sys.argv:
    print(f"{sys.argv[0]} [--help] [brr_file_path loop_offset_in_hex]")
    exit()

  if len(sys.argv) >= 2:
    # BRR data at : https://www.ff6hacking.com/forums/thread-3640-post-35824.html
    # Download the "nolength" files. Loop setting of "AABB" signifies a loop offset of 0xBBAA
    with open(sys.argv[1], 'rb') as brr:
      brr_data = [byte for byte in brr.read()]
      loop_offset = int(sys.argv[2].replace('0x', ''), 16) if len(sys.argv) >= 3 else 0
  else:
    brr_data = [
      gen_header(_range=0xC, filter=0, loop=0, end=0), 0x03, 0x56, 0x75, 0x31, 0xEB, 0x9A, 0xBD, 0xEF,
      gen_header(_range=0xB, filter=0, loop=0, end=0), 0x03, 0x56, 0x75, 0x31, 0xEB, 0x9A, 0xBD, 0xEF,
      gen_header(_range=0xA, filter=0, loop=1, end=1), 0x03, 0x56, 0x75, 0x31, 0xEB, 0x9A, 0xBD, 0xEF,
    ]
    loop_offset = 9 # start in the second block

  test(brr_data, loop_offset)