# fpga-spc700

### Build and Simulate DSP Voice
```
make -j && ./build/DSPVoiceDecoder ./test_data/13_piano.brr && play ./build/dsp_voice_test_wave_out.wav
```

### Build and Simulate Full DSP
```
make && time ./build/TestDSP ./test_data/13_piano.brr && play ./build/dsp_test_wave_out.wav
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
