CC ?= cc
CFLAGS ?= -O2 -std=gnu11 -Wall -Wextra

all: out/vban-pipewire

out/vban-pipewire: src/vban-pipewire.c
	mkdir -p out
	$(CC) $(CFLAGS) $< -o $@ $$(pkg-config --cflags --libs libpipewire-0.3) -pthread

clean:
	rm -rf out
