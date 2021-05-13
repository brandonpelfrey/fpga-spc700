.PHONY: all
ifeq ($(shell uname -s),Linux)
all: all-linux

CXXFLAGS := -I/usr/share/verilator/include
CXXFLAGS += -Ibuild/
else
all: all-mac
endif

CXXFLAGS += -std=c++17

MODULES := $(patsubst src/%.v,%,$(wildcard src/*.v))
BENCHES := $(patsubst src/%.cpp,%,$(wildcard src/*.cpp))

################################################################################
# Linux Build Rules
################################################################################

.PHONY: all-linux

build/libverilated.a : /usr/share/verilator/include/verilated.cpp
	g++ -c $< $(CXXFLAGS) -o build/libverilated.o
	ar cr $@ build/libverilated.o

define GEN_verilator
build/build-$(1)/V$(1).cpp: src/$(1).v
	mkdir -p build/build-$(1)
	verilator -Wall -cc -Mdir build/build-$(1) --exe src/SimulatorTop.v

build/lib$(1).a: build/build-$(1)/V$(1).cpp
	g++ $(CXXFLAGS) -c build/build-$(1)/V$(1).cpp -o build/build-$(1)/V$(1).o
	g++ $(CXXFLAGS) -c build/build-$(1)/V$(1)__Syms.cpp -o build/build-$(1)/V$(1)__Syms.o
	ar cr $$@ build/build-$(1)/V$(1).o build/build-$(1)/V$(1)__Syms.o
endef

define GEN_test
build/$(1).o : src/$(1).cpp build/build-$(1)/V$(1).cpp
	$(CXX) -c $(CXXFLAGS) -Ibuild/build-$(1) $$< -o $$@

build/$(1) : build/$(1).o build/lib$(1).a build/libverilated.a
	$(CXX) build/$(1).o -Lbuild -lverilated -l$(1) $(LDFLAGS) -o $$@

all-linux: build/$(1)
endef

$(foreach what,$(MODULES),$(eval $(call GEN_verilator,$(what))))
$(foreach what,$(BENCHES),$(eval $(call GEN_test,$(what))))

################################################################################
# Mac Build Rules
################################################################################

all-mac:
	verilator -Wall -cc --exe --build src/SimulatorTop.cpp src/SimulatorTop.v
