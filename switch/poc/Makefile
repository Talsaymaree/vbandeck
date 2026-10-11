APP_TITLE := VBAN Deck Switch Test
APP_AUTHOR := Tee215
APP_VERSION := 0.1.0

TARGET := VBANDeckSwitchTest
BUILD := build
SOURCES := source
INCLUDES := include

ARCH := -march=armv8-a+crc+crypto -mtune=cortex-a57 -mtp=soft -fPIE
CFLAGS := -g -Wall -Wextra -Wpedantic -O2 -ffunction-sections -fdata-sections $(ARCH)
CFLAGS += $(INCLUDE) -D__SWITCH__
CXXFLAGS := $(CFLAGS) -fno-rtti -fno-exceptions
ASFLAGS := -g $(ARCH)
LDFLAGS := -specs=$(DEVKITPRO)/libnx/switch.specs -g $(ARCH) -Wl,-Map,$(notdir $*.map) -Wl,--gc-sections
LIBS := -lnx -lm

NROFLAGS := --nacp=$(TARGET).nacp

include $(DEVKITPRO)/libnx/switch_rules
