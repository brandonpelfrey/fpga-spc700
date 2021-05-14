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

.PHONY: all all-verilate all-test
all: all-verilate all-test

################################################################################
# Generic Build Rules
################################################################################

build/libverilated.a : $(VERILATOR_INC)/verilated.cpp
	g++ -c $< $(CXXFLAGS) -o build/libverilated.o
	ar cr $@ build/libverilated.o

define GEN_verilator
build/build-$(1)/V$(1).cpp: src/$(1).v
	mkdir -p build/build-$(1)
	verilator -Wall -cc -Mdir build/build-$(1) --exe src/SimulatorTop.v

build/lib$(1).a: build/build-$(1)/V$(1).cpp
	for i in build/build-$(1)/*.cpp; do \
		g++ $(CXXFLAGS) -c $$$${i} -o build/build-$(1)/`basename -s .cpp $$$${i}`.o; \
	done
	ar cr $$@ build/build-$(1)/*.o

all-verilate: build/build-$(1)/V$(1).cpp
endef

define GEN_test
build/$(1).o : src/$(1).cpp build/build-$(1)/V$(1).cpp
	$(CXX) -c $(CXXFLAGS) -Ibuild/build-$(1) $$< -o $$@

build/$(1) : build/$(1).o build/lib$(1).a build/libverilated.a
	$(CXX) build/$(1).o -Lbuild -lverilated -l$(1) $(LDFLAGS) -o $$@

all-test: build/$(1)
endef

$(foreach what,$(MODULES),$(eval $(call GEN_verilator,$(what))))
$(foreach what,$(BENCHES),$(eval $(call GEN_test,$(what))))
