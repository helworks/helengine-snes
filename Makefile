.DEFAULT_GOAL := all
.DELETE_ON_ERROR:

TARGET := helengine_snes
BUILD_DIR := build
OBJECT_ROOT ?= $(BUILD_DIR)/obj
ROM_TITLE := HELENGINE SNES

CXX := mos-snes-clang++
CXXFLAGS := -std=c++20 -fno-exceptions -fno-rtti -Os -Wall -Wextra -Werror -Isrc -MMD -MP

SOURCES := $(wildcard src/*.cpp) $(wildcard src/platform/snes/*.cpp)
OBJECTS := $(patsubst src/%.cpp,$(OBJECT_ROOT)/%.o,$(SOURCES))
RAW_ROM := $(BUILD_DIR)/$(TARGET).raw.sfc
ELF := $(BUILD_DIR)/$(TARGET).elf
MAP := $(BUILD_DIR)/$(TARGET).map
ROM := $(TARGET).sfc

.PHONY: all clean FORCE

all: $(ROM)

$(OBJECT_ROOT)/%.o: src/%.cpp
	@mkdir -p $(dir $@)
	@echo "    [CXX] $<"
	$(CXX) $(CXXFLAGS) -c -o $@ $<

# The SDK link script emits the raw 32 KiB image directly and drops an ELF
# sidecar next to it as <output>.elf; move the sidecar to the documented name.
$(RAW_ROM): $(OBJECTS)
	@echo "    [LD]  $@"
	$(CXX) $(CXXFLAGS) -Wl,-Map,$(MAP) -o $@ $(OBJECTS)
	mv $@.elf $(ELF)

$(ROM): FORCE $(RAW_ROM) tools/finalize_rom.py tools/validate_rom.py
	python3 tools/finalize_rom.py --title "$(ROM_TITLE)" $(RAW_ROM) $@
	python3 tools/validate_rom.py --title "$(ROM_TITLE)" $@

clean:
	rm -rf "$(BUILD_DIR)" "$(OBJECT_ROOT)" "$(ROM)"

FORCE:

-include $(OBJECTS:.o=.d)
