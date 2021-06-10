MODULES := $(patsubst src/%.v,%,$(wildcard src/*.v))
BENCHES := $(patsubst src/%.cpp,%,$(wildcard src/*.cpp))

ifeq ($(shell uname -s),Linux)
VERILATOR_INC := /usr/share/verilator/include
else
VERILATOR_INC := /opt/homebrew/Cellar/verilator/4.200/share/verilator/include
endif

CXXFLAGS := -Ibuild/
CXXFLAGS += -std=c++17
CXXFLAGS += -I$(VERILATOR_INC)
VERILATOR_FLAGS := -cc -Wall -Wno-UNUSED

.PHONY: all all-verilate all-test clean
all: all-verilate all-test

clean:
	rm -rf build

################################################################################
# Generic Build Rules (verilator)
################################################################################

build/libverilated.a : $(VERILATOR_INC)/verilated.cpp
	g++ -c $< $(CXXFLAGS) -o build/libverilated.o
	ar cr $@ build/libverilated.o

define GEN_verilator
build/build-$(1)/V$(1).cpp: $(wildcard src/*.v)
	mkdir -p build/build-$(1)
	verilator $(VERILATOR_FLAGS) -Isrc -Mdir build/build-$(1) --top-module $(1) --exe src/$(1).v
	touch $$@

build/lib$(1).a: build/build-$(1)/V$(1).cpp
	for i in build/build-$(1)/*.cpp; do \
		g++ $(CXXFLAGS) -c $$$${i} -o build/build-$(1)/`basename -s .cpp $$$${i}`.o; \
	done
	ar cr $$@ build/build-$(1)/*.o

all-verilate: build/build-$(1)/V$(1).cpp
endef

define GEN_test
build/$(1).o : src/$(1).cpp build/build-$(1)/V$(1).cpp $(wildcard src/*.h)
	$(CXX) -c $(CXXFLAGS) -Ibuild/build-$(1) $$< -o $$@

build/$(1) : build/$(1).o build/lib$(1).a build/libverilated.a
	mkdir -p build/test
	$(CXX) build/$(1).o -Lbuild -lverilated -l$(1) $(LDFLAGS) -o $$@

all-test: build/$(1)
endef

$(foreach what,$(BENCHES),$(eval $(call GEN_verilator,$(what))))
$(foreach what,$(BENCHES),$(eval $(call GEN_test,$(what))))

################################################################################
# Build Rules (Ice40)
################################################################################

.PHONY: ice40
ice40:
	yosys -p "read_verilog -sv src/Ice40_CPUBench.v; synth_ice40 -json build/Ice40_CPUBench.json"
	nextpnr-ice40 --hx8k --package ct256 --json build/Ice40_CPUBench.json --pcf src/ice40.pcf --asc build/Ice40_CPUBench.asc

.PHONY: ice40-dsp
ice40-dsp:
	yosys -p "read_verilog -sv src/DSP.v; synth_ice40 -json build/Ice40_TestDSP.json"

.PHONY: ice40-dsp-decoder
ice40-dsp-decoder:
	yosys -p "read_verilog -sv src/DSPVoiceDecoder.v; synth_ice40 -json build/Ice40_DSPVoiceDecoder.json"

################################################################################
# Build Rules (ECP5)
################################################################################

.PHONY: ecp5
ecp5:
	yosys -p "read_verilog -sv src/ECP5_CPUBench.v; synth_ecp5 -json build/ECP5_CPUBench.json"
	nextpnr-ecp5 --um-85k --package CABGA381 --json build/ECP5_CPUBench.json --lpf src/ecp5.lpf

.PHONY: ecp5-dsp-decoder
ecp5-dsp-decoder:
	yosys -p "read_verilog -sv src/DSPVoiceDecoder.v; synth_ecp5 -json build/ECP5_DSPVoiceDecoder.json"
