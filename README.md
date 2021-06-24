# fpga-spc700

### Build and Simulate DSP Voice
```
make -j && ./build/DSPVoiceDecoder ./test_data/13_piano.brr && play ./build/dsp_voice_test_wave_out.wav
```

### Build and Simulate Full DSP
```
make && time ./build/TestDSP ./test_data/13_piano.brr && play ./build/dsp_test_wave_out.wav
```

### Utilizing driver.py
```
# Make sure we have: 460800 baud, 1 stop bit, no parity bit
sudo stty -F /dev/ttyUSB0 cs8 -parenb -cstopb -clocal -ixon -inpck 460800

# You can reset Audio Codec I2C regs
python3 driver.py --reset-audio

# Reset APU (e.g. replay a sound at RAM 0x0000 for now)
python3 driver.py --reset-apu

# Send data to RAM
python driver.py --load-sample [sample_path]
```

### DSP TODO
- Noise Generator
- Master Volume
- ADSR Envelope Generator
- Gaussian Sample Filtering
- Pitch Modulation
- Echo Buffer

### Reference Info
- http://vspcplay.raphnet.net/spc_file_format.txt
- https://wiki.superfamicom.org/spc700-reference
