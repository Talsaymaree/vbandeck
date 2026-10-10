#define _GNU_SOURCE
#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/utils/result.h>
#include <arpa/inet.h>
#include <errno.h>
#include <getopt.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define RATE 48000u
#define CHANNELS 2u
#define SAMPLE_BYTES 2u
#define PACKET_FRAMES 256u
#define RING_FRAMES (RATE) /* 1 second */
#define VBAN_STREAM_NAME_SIZE 16
#define VBAN_HEADER_SIZE 28

/* VBAN SR table index 3 = 48000 Hz. 16-bit signed integer format = 1. */
#define VBAN_SR_48000 3u
#define VBAN_FMT_16I 1u

struct __attribute__((packed)) vban_header {
    char magic[4];
    uint8_t format_sr;
    uint8_t format_nbs;
    uint8_t format_nbc;
    uint8_t format_bit;
    char stream_name[VBAN_STREAM_NAME_SIZE];
    uint32_t frame_counter;
};

struct app {
    struct pw_main_loop *loop;
    struct pw_stream *stream;
    struct spa_hook listener;

    int sock;
    struct sockaddr_in dest;
    char stream_name[VBAN_STREAM_NAME_SIZE];
    char target[256];

    int16_t *ring;
    atomic_uint_fast64_t write_frame;
    atomic_uint_fast64_t read_frame;
    atomic_uint_fast64_t overflows;
    atomic_uint_fast64_t underruns;
    atomic_uint_fast64_t packets;
    atomic_bool running;

    pthread_t sender_thread;
    pthread_mutex_t wake_mutex;
    pthread_cond_t wake_cond;
};

static struct app *g_app = NULL;

static inline uint64_t ring_available(struct app *a) {
    uint64_t w = atomic_load_explicit(&a->write_frame, memory_order_acquire);
    uint64_t r = atomic_load_explicit(&a->read_frame, memory_order_acquire);
    return w - r;
}

static void ring_write(struct app *a, const int16_t *samples, uint32_t frames) {
    uint64_t w = atomic_load_explicit(&a->write_frame, memory_order_relaxed);
    uint64_t r = atomic_load_explicit(&a->read_frame, memory_order_acquire);
    uint64_t used = w - r;

    if (frames > RING_FRAMES) {
        samples += (frames - RING_FRAMES) * CHANNELS;
        frames = RING_FRAMES;
    }

    if (used + frames > RING_FRAMES) {
        uint64_t drop = used + frames - RING_FRAMES;
        atomic_fetch_add_explicit(&a->read_frame, drop, memory_order_release);
        atomic_fetch_add(&a->overflows, 1);
    }

    for (uint32_t f = 0; f < frames; ++f) {
        uint64_t idx = (w + f) % RING_FRAMES;
        a->ring[idx * CHANNELS] = samples[f * CHANNELS];
        a->ring[idx * CHANNELS + 1] = samples[f * CHANNELS + 1];
    }
    atomic_store_explicit(&a->write_frame, w + frames, memory_order_release);

    pthread_mutex_lock(&a->wake_mutex);
    pthread_cond_signal(&a->wake_cond);
    pthread_mutex_unlock(&a->wake_mutex);
}

static uint32_t ring_read(struct app *a, int16_t *dst, uint32_t frames) {
    uint64_t r = atomic_load_explicit(&a->read_frame, memory_order_relaxed);
    uint64_t w = atomic_load_explicit(&a->write_frame, memory_order_acquire);
    uint64_t avail = w - r;
    if (avail < frames) return 0;

    for (uint32_t f = 0; f < frames; ++f) {
        uint64_t idx = (r + f) % RING_FRAMES;
        dst[f * CHANNELS] = a->ring[idx * CHANNELS];
        dst[f * CHANNELS + 1] = a->ring[idx * CHANNELS + 1];
    }
    atomic_store_explicit(&a->read_frame, r + frames, memory_order_release);
    return frames;
}

static void add_ns(struct timespec *t, uint64_t ns) {
    t->tv_nsec += (long)(ns % 1000000000ULL);
    t->tv_sec += (time_t)(ns / 1000000000ULL);
    if (t->tv_nsec >= 1000000000L) {
        t->tv_nsec -= 1000000000L;
        t->tv_sec++;
    }
}

static void *sender_main(void *userdata) {
    struct app *a = userdata;
    const uint64_t packet_ns = (1000000000ULL * PACKET_FRAMES) / RATE;
    const uint32_t payload_bytes = PACKET_FRAMES * CHANNELS * SAMPLE_BYTES;
    uint8_t packet[VBAN_HEADER_SIZE + PACKET_FRAMES * CHANNELS * SAMPLE_BYTES];
    struct vban_header *h = (struct vban_header *)packet;
    int16_t *pcm = (int16_t *)(packet + VBAN_HEADER_SIZE);

    memset(packet, 0, sizeof(packet));
    memcpy(h->magic, "VBAN", 4);
    h->format_sr = VBAN_SR_48000;
    h->format_nbs = PACKET_FRAMES - 1;
    h->format_nbc = CHANNELS - 1;
    h->format_bit = VBAN_FMT_16I;
    strncpy(h->stream_name, a->stream_name, VBAN_STREAM_NAME_SIZE - 1);

    /* Prime ~32 ms to absorb PipeWire quantum/batch variation. */
    while (atomic_load(&a->running) && ring_available(a) < 1536) {
        pthread_mutex_lock(&a->wake_mutex);
        struct timespec until;
        clock_gettime(CLOCK_REALTIME, &until);
        add_ns(&until, 10000000ULL);
        pthread_cond_timedwait(&a->wake_cond, &a->wake_mutex, &until);
        pthread_mutex_unlock(&a->wake_mutex);
    }

    struct timespec next;
    clock_gettime(CLOCK_MONOTONIC, &next);

    while (atomic_load(&a->running)) {
        if (!ring_read(a, pcm, PACKET_FRAMES)) {
            memset(pcm, 0, payload_bytes);
            atomic_fetch_add(&a->underruns, 1);
        }

        /* frame counter is little-endian on the wire on x86, matching VBAN reference implementations. */
        h->frame_counter++;
        ssize_t n = sendto(a->sock, packet, sizeof(packet), 0,
                           (struct sockaddr *)&a->dest, sizeof(a->dest));
        if (n < 0 && errno != EINTR) perror("sendto");
        atomic_fetch_add(&a->packets, 1);

        add_ns(&next, packet_ns);
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next, NULL);

        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        if ((now.tv_sec > next.tv_sec) ||
            (now.tv_sec == next.tv_sec && now.tv_nsec > next.tv_nsec + 50000000L)) {
            next = now;
        }
    }
    return NULL;
}

static void on_process(void *userdata) {
    struct app *a = userdata;
    struct pw_buffer *pb = pw_stream_dequeue_buffer(a->stream);
    if (!pb) return;

    struct spa_buffer *buf = pb->buffer;
    if (buf->n_datas < 1) {
        pw_stream_queue_buffer(a->stream, pb);
        return;
    }

    struct spa_data *d = &buf->datas[0];
    if (d->data && d->chunk && d->chunk->size > 0) {
        uint8_t *base = d->data;
        uint32_t offset = d->chunk->offset;
        uint32_t size = d->chunk->size;
        uint32_t stride = d->chunk->stride ? d->chunk->stride : (CHANNELS * SAMPLE_BYTES);
        if (stride == CHANNELS * SAMPLE_BYTES) {
            uint32_t frames = size / stride;
            ring_write(a, (const int16_t *)(base + offset), frames);
        }
    }
    pw_stream_queue_buffer(a->stream, pb);
}

static void on_state_changed(void *userdata, enum pw_stream_state old,
                             enum pw_stream_state state, const char *error) {
    (void)old;
    struct app *a = userdata;
    fprintf(stderr, "PipeWire: %s%s%s\n", pw_stream_state_as_string(state),
            error ? " - " : "", error ? error : "");
    if (state == PW_STREAM_STATE_ERROR) {
        atomic_store(&a->running, false);
        pw_main_loop_quit(a->loop);
    }
}

static const struct pw_stream_events stream_events = {
    PW_VERSION_STREAM_EVENTS,
    .state_changed = on_state_changed,
    .process = on_process,
};

static void handle_signal(int sig) {
    (void)sig;
    if (!g_app) return;
    atomic_store(&g_app->running, false);
    if (g_app->loop) pw_main_loop_quit(g_app->loop);
}

static void usage(const char *argv0) {
    fprintf(stderr,
        "Usage: %s --ip IP [--port 6980] [--stream SteamDeck] [--target NODE]\n"
        "Native PipeWire sink-monitor capture -> paced VBAN PCM sender.\n"
        "If --target is omitted, WirePlumber selects/follows the default sink.\n",
        argv0);
}

int main(int argc, char **argv) {
    const char *ip = NULL;
    int port = 6980;
    const char *stream = "SteamDeck";
    const char *target = NULL;

    static const struct option opts[] = {
        {"ip", required_argument, 0, 'i'},
        {"port", required_argument, 0, 'p'},
        {"stream", required_argument, 0, 's'},
        {"target", required_argument, 0, 't'},
        {"help", no_argument, 0, 'h'},
        {0, 0, 0, 0}
    };
    int c;
    while ((c = getopt_long(argc, argv, "i:p:s:t:h", opts, NULL)) != -1) {
        switch (c) {
            case 'i': ip = optarg; break;
            case 'p': port = atoi(optarg); break;
            case 's': stream = optarg; break;
            case 't': target = optarg; break;
            default: usage(argv[0]); return c == 'h' ? 0 : 2;
        }
    }
    if (!ip || port < 1 || port > 65535 || strlen(stream) > 15) {
        usage(argv[0]);
        return 2;
    }

    struct app a;
    memset(&a, 0, sizeof(a));
    a.sock = -1;
    a.ring = calloc(RING_FRAMES * CHANNELS, sizeof(int16_t));
    if (!a.ring) return 1;
    strncpy(a.stream_name, stream, sizeof(a.stream_name) - 1);
    if (target) strncpy(a.target, target, sizeof(a.target) - 1);
    pthread_mutex_init(&a.wake_mutex, NULL);
    pthread_cond_init(&a.wake_cond, NULL);
    atomic_store(&a.running, true);

    a.sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (a.sock < 0) { perror("socket"); return 1; }
    memset(&a.dest, 0, sizeof(a.dest));
    a.dest.sin_family = AF_INET;
    a.dest.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, ip, &a.dest.sin_addr) != 1) {
        fprintf(stderr, "Invalid destination IP: %s\n", ip);
        return 2;
    }

    pw_init(&argc, &argv);
    a.loop = pw_main_loop_new(NULL);
    if (!a.loop) return 1;

    struct pw_properties *props = pw_properties_new(
        PW_KEY_MEDIA_TYPE, "Audio",
        PW_KEY_MEDIA_CATEGORY, "Capture",
        PW_KEY_MEDIA_ROLE, "Music",
        PW_KEY_APP_NAME, "VBAN Deck",
        PW_KEY_NODE_NAME, "com.tee215.VBANDeck.capture",
        PW_KEY_STREAM_CAPTURE_SINK, "true",
        PW_KEY_STREAM_DONT_REMIX, "true",
        PW_KEY_NODE_AUTOCONNECT, "true",
        NULL);
    if (target && *target)
        pw_properties_set(props, PW_KEY_TARGET_OBJECT, target);

    a.stream = pw_stream_new_simple(pw_main_loop_get_loop(a.loop),
                                    "VBAN Deck Capture", props,
                                    &stream_events, &a);
    if (!a.stream) return 1;

    uint8_t buffer[1024];
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
    const struct spa_pod *params[1];
    struct spa_audio_info_raw info = SPA_AUDIO_INFO_RAW_INIT(
        .format = SPA_AUDIO_FORMAT_S16_LE,
        .rate = RATE,
        .channels = CHANNELS,
        .position = { SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR }
    );
    params[0] = spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &info);

    int res = pw_stream_connect(a.stream, PW_DIRECTION_INPUT, PW_ID_ANY,
        PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS,
        params, 1);
    if (res < 0) {
        fprintf(stderr, "pw_stream_connect: %s\n", spa_strerror(res));
        return 1;
    }

    g_app = &a;
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    if (pthread_create(&a.sender_thread, NULL, sender_main, &a) != 0) {
        perror("pthread_create"); return 1;
    }

    fprintf(stderr, "VBAN Deck: %s:%d stream=%s, 48kHz stereo S16, %u frames/packet\n",
            ip, port, stream, PACKET_FRAMES);
    fprintf(stderr, "Capture: %s sink monitor\n", target ? target : "default");

    pw_main_loop_run(a.loop);

    atomic_store(&a.running, false);
    pthread_mutex_lock(&a.wake_mutex);
    pthread_cond_broadcast(&a.wake_cond);
    pthread_mutex_unlock(&a.wake_mutex);
    pthread_join(a.sender_thread, NULL);

    fprintf(stderr, "Stopped. packets=%llu underruns=%llu overflows=%llu\n",
            (unsigned long long)atomic_load(&a.packets),
            (unsigned long long)atomic_load(&a.underruns),
            (unsigned long long)atomic_load(&a.overflows));

    pw_stream_destroy(a.stream);
    pw_main_loop_destroy(a.loop);
    pw_deinit();
    close(a.sock);
    free(a.ring);
    pthread_cond_destroy(&a.wake_cond);
    pthread_mutex_destroy(&a.wake_mutex);
    return 0;
}
