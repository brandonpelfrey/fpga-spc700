# https://wiki.superfamicom.org/spc700-reference#dsp-register-map-985
# This is a helper to generate the DSP register data for X Macros in the source code.

class Register:
  def __init__(self, index, has_voice, name, description):
    self.index = index
    self.has_voice = has_voice
    self.name = name
    self.description = description

regs = []
regs.append(Register(0x0, True, 'VOLL', "Left Channel Volume"))
regs.append(Register(0x1, True, 'VOLR', "Right Channel Volume"))
regs.append(Register(0x2, True, 'PL', "Pitch (Low 8 bits)"))
regs.append(Register(0x3, True, 'PH', "Pitch (High 4 bits)"))
regs.append(Register(0x4, True, 'SRCN', "Source Number"))
regs.append(Register(0x5, True, 'ADSR1', "ADSR Config 1"))
regs.append(Register(0x6, True, 'ADSR2', "ADSR Config 2"))
regs.append(Register(0x7, True, 'GAIN', "Envelope Gain"))
regs.append(Register(0x8, True, 'ENVX', "Current Envelope Value"))
regs.append(Register(0x9, True, 'OUTX', "Current waveform, after envelope, pre-volume"))
regs.append(Register(0xF, True, 'COEF', "FIR Filter Coefficient"))

regs.append(Register(0x0C, False, 'MVOLL', "Main Volume (left output)"))
regs.append(Register(0x1C, False, 'MVOLR', "Main Volume (right output)"))
regs.append(Register(0x2C, False, 'EVOLL', "Echo Volume (left output)"))
regs.append(Register(0x3C, False, 'EVOLR', "Echo Volume (right output)"))
regs.append(Register(0x4C, False, 'KON', "Key On (1 bit per voice)"))
regs.append(Register(0x5C, False, 'KOF', "Key Off (1 bit per voice)"))
regs.append(Register(0x6C, False, 'FLG', "DSP Flags"))
regs.append(Register(0x7C, False, 'ENDX', "End of Sample (1 bit per voice)"))
regs.append(Register(0x0D, False, 'EFB', "Echo Feedback"))
regs.append(Register(0x2D, False, 'PMON', "Pitch Modulation (1 bit per voice)"))
regs.append(Register(0x3D, False, 'NON', "Noise enable"))
regs.append(Register(0x4D, False, 'EON', "Echo enable"))
regs.append(Register(0x5D, False, 'DIR', "Source Directory Address (DIR * 0x100"))
regs.append(Register(0x6D, False, 'ESA', "Echo Buffer Address (ESA * 0x100)"))
regs.append(Register(0x7D, False, 'EDL', "Echo Delay, 4 bits, higher values require more memory"))

def voice_register_index(index, voice_num):
  return index | (voice_num << 4)

# For everything which isn't a register, add an 'invalid' register 
valid_register_indexes = set([])
for reg in regs:
  if reg.has_voice:
    for voice in range(8):
      valid_register_indexes.add(voice_register_index(reg.index, voice))
  else:
    valid_register_indexes.add(reg.index)

for i in range(128):
  if i not in valid_register_indexes:
    regs.append(Register(i, False, None, None))

# Output functions
def print_c_macros(regs):
  lines = [] # [ (index, text), ... ]
  for reg in regs:
    index = reg.index
    if reg.has_voice: # Append voice number to registers encoding 
      for voice in range(8):
        name = f'{reg.name}{voice}' if reg.name else f'__invalid{voice}{index}'
        description = f'"{reg.description} (Voice {voice})"' if reg.description else 'nullptr'
        index = voice_register_index(reg.index, voice)
        line_entry = (index, f'DSP_REGISTER({index}, {voice}, {name}, {description})')
        lines.append(line_entry)
    else:
      name = f'{reg.name}' if reg.name else f'__invalid{index}'
      description = f'"{reg.description}"' if reg.description else 'nullptr'
      line_entry = (index, f'DSP_REGISTER({index}, 0xFF, {name}, {description})')
      lines.append(line_entry)

  for _, line in sorted(lines, key=lambda e: e[0]):
    print(line)

def print_verilog_defs(regs):
  lines = [] # [ (index, text), ... ]
  for reg in regs:
    index = reg.index
    if reg.has_voice: # Append voice number to registers encoding 
      index_array = '\'{' + ','.join([f"7'h{voice_register_index(index, i):02x}" for i in range(8)]) + '}'
      reg_name_string = f'REG_{reg.name}'
      line_entry = (index, f'localparam [6:0] {reg_name_string:10s} [7:0] = {index_array};')
      lines.append(line_entry)
    elif reg.name:
      reg_name_string = f'REG_{reg.name}'
      line_entry = (index, f"localparam [6:0] {reg_name_string:10s} = 7'h{index:02x};")
      lines.append(line_entry)

  for _, line in sorted(lines, key=lambda e: e[0]):
    print(line)
  

# 
print_c_macros(regs)
# print_verilog_defs(regs)
