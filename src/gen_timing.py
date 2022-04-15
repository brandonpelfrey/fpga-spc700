# 92 clock cycles per samples, 32khz audio rate
#           |       |       |       |       |       |       |       |       |       |       |       |       
# Timing    000000000000000011111111111111112222222222222222333333333333333344444444444444445555555555555555
#           0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF
DSP_MEM  = '00.00.0..11.11.12.22.22.33.33.3..44.44.45.55.55.66.66.6..77.77.7................................'
DSP_PROC = '........0000000011111111222222223333333344444444555555556666666677777777........................'
CPU_READ = '..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D..D'

CLOCKS_PER_SAMPLE = 96
N_VOICES = 8

for clock in range(CLOCKS_PER_SAMPLE):
  dsp_access = DSP_MEM[clock] != '.'
  cpu_access = CPU_READ[clock] != '.'
  assert not (dsp_access and cpu_access), f"Simultaneous CPU/DSP memory access at cycle {clock}"

print("localparam DSP_VOICE_MEM_CLOCKS [7:0] = '{")
for v in range(N_VOICES):
  print(f"  {CLOCKS_PER_SAMPLE}'b", end='')
  for clock in range(CLOCKS_PER_SAMPLE):
    print('1' if DSP_MEM[clock] == str(v) else '0', end='')
  print(',')
print("};")

print("localparam VOICE_PROCESSING [7:0] = '{")
for v in range(N_VOICES):
  print(f"  {CLOCKS_PER_SAMPLE}'b", end='')
  for clock in range(CLOCKS_PER_SAMPLE):
    print('1' if DSP_PROC[clock] == str(v) else '0', end='')
  print(',')
print("};")

print("localparam CPU_MEM_CLOCKS = ")
print(f"  {CLOCKS_PER_SAMPLE}'b", end='')
for clock in range(CLOCKS_PER_SAMPLE):
  print('1' if CPU_READ[clock] == 'D' else '0', end='')
print(";")
