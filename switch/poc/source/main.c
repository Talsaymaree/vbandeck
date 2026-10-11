#include <switch.h>

#include <arpa/inet.h>
#include <errno.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define VBAN_PORT_DEFAULT 6980
#define VBAN_STREAM_NAME_SIZE 16
#define VBAN_HEADER_SIZE 28
#define SAMPLE_RATE 48000u
#define CHANNELS 2u
#define PACKET_FRAMES 256u
#define TWO_PI 6.28318530717958647692

/* VBAN: sample-rate table index 3 = 48 kHz; data format 1 = signed 16-bit. */
#define VBAN_SR_48000 3u
#define VBAN_FMT_16I 1u

typedef struct __attribute__((packed)) {
    char magic[4];
    uint8_t format_sr;
    uint8_t format_nbs;
    uint8_t format_nbc;
    uint8_t format_bit;
    char stream_name[VBAN_STREAM_NAME_SIZE];
    uint32_t frame_counter;
} VbanHeader;

_Static_assert(sizeof(VbanHeader) == VBAN_HEADER_SIZE, "VBAN header must be 28 bytes");

typedef struct {
    char host[16];
    uint16_t port;
    char stream[VBAN_STREAM_NAME_SIZE];
} Config;

static void config_defaults(Config *config) {
    strncpy(config->host, "192.168.1.2", sizeof(config->host) - 1);
    config->port = VBAN_PORT_DEFAULT;
    strncpy(config->stream, "SwitchTest", sizeof(config->stream) - 1);
}

static char *trim(char *text) {
    char *end;
    while (*text == ' ' || *text == '\t' || *text == '\r' || *text == '\n') text++;
    end = text + strlen(text);
    while (end > text && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r' || end[-1] == '\n')) *--end = '\0';
    return text;
}

static void load_config(Config *config) {
    FILE *file = fopen("sdmc:/switch/vbandeck-switch/config.ini", "r");
    char line[96];
    if (!file) return;

    while (fgets(line, sizeof(line), file)) {
        char *equals = strchr(line, '=');
        if (!equals || line[0] == '#') continue;
        *equals = '\0';
        char *key = trim(line);
        char *value = trim(equals + 1);
        if (strcmp(key, "host") == 0) {
            strncpy(config->host, value, sizeof(config->host) - 1);
            config->host[sizeof(config->host) - 1] = '\0';
        } else if (strcmp(key, "port") == 0) {
            long port = strtol(value, NULL, 10);
            if (port > 0 && port <= 65535) config->port = (uint16_t)port;
        } else if (strcmp(key, "stream") == 0 && strlen(value) < VBAN_STREAM_NAME_SIZE) {
            strncpy(config->stream, value, sizeof(config->stream) - 1);
            config->stream[sizeof(config->stream) - 1] = '\0';
        }
    }
    fclose(file);
}

static void generate_tone(int16_t *pcm, double *phase) {
    const double phase_step = TWO_PI * 440.0 / SAMPLE_RATE;
    for (uint32_t frame = 0; frame < PACKET_FRAMES; ++frame) {
        int16_t sample = (int16_t)(sin(*phase) * 6000.0);
        pcm[frame * CHANNELS] = sample;
        pcm[frame * CHANNELS + 1] = sample;
        *phase += phase_step;
        if (*phase >= TWO_PI) *phase -= TWO_PI;
    }
}

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;
    consoleInit(NULL);
    fsdevMountSdmc();

    Config config = {0};
    config_defaults(&config);
    load_config(&config);

    Result rc = socketInitializeDefault();
    bool socket_ready = R_SUCCEEDED(rc);
    bool nifm_ready = false;
    if (socket_ready) {
        rc = nifmInitialize(NifmServiceType_User);
        nifm_ready = R_SUCCEEDED(rc);
    }
    if (R_FAILED(rc)) {
        printf("Network initialization failed.\nPress PLUS to exit.\n");
        while (appletMainLoop()) {
            hidScanInput();
            if (hidKeysDown(CONTROLLER_P1_AUTO) & KEY_PLUS) break;
            consoleUpdate(NULL);
        }
        if (nifm_ready) nifmExit();
        if (socket_ready) socketExit();
        consoleExit(NULL);
        return 1;
    }

    int socket_fd = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in destination = {0};
    destination.sin_family = AF_INET;
    destination.sin_port = htons(config.port);
    if (socket_fd < 0 || inet_pton(AF_INET, config.host, &destination.sin_addr) != 1) {
        printf("Invalid host: %s\nPress PLUS to exit.\n", config.host);
        if (socket_fd >= 0) close(socket_fd);
        nifmExit();
        socketExit();
        consoleExit(NULL);
        return 1;
    }

    uint8_t packet[VBAN_HEADER_SIZE + PACKET_FRAMES * CHANNELS * sizeof(int16_t)] = {0};
    VbanHeader *header = (VbanHeader *)packet;
    int16_t *pcm = (int16_t *)(packet + VBAN_HEADER_SIZE);
    memcpy(header->magic, "VBAN", 4);
    header->format_sr = VBAN_SR_48000;
    header->format_nbs = PACKET_FRAMES - 1;
    header->format_nbc = CHANNELS - 1;
    header->format_bit = VBAN_FMT_16I;
    strncpy(header->stream_name, config.stream, VBAN_STREAM_NAME_SIZE - 1);

    printf("VBAN Deck Switch Test\n\nSending 440 Hz test tone\n%s:%u  stream=%s\n\nPress PLUS to exit.\n", config.host, config.port, config.stream);

    double phase = 0.0;
    uint64_t packets = 0;
    const int64_t packet_ns = (1000000000LL * PACKET_FRAMES) / SAMPLE_RATE;
    while (appletMainLoop()) {
        hidScanInput();
        if (hidKeysDown(CONTROLLER_P1_AUTO) & KEY_PLUS) break;

        generate_tone(pcm, &phase);
        header->frame_counter++;
        ssize_t sent = sendto(socket_fd, packet, sizeof(packet), 0,
                              (struct sockaddr *)&destination, sizeof(destination));
        if (sent == (ssize_t)sizeof(packet)) packets++;
        svcSleepThread(packet_ns);
    }

    printf("\nStopped. Packets sent: %llu\n", (unsigned long long)packets);
    close(socket_fd);
    nifmExit();
    socketExit();
    fsdevUnmountDevice("sdmc");
    consoleExit(NULL);
    return 0;
}
