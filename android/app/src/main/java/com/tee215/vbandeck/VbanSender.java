package com.tee215.vbandeck;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;

final class VbanSender implements AutoCloseable {
    static final int SAMPLE_RATE = 48000;
    static final int CHANNELS = 2;
    static final int BYTES_PER_SAMPLE = 2;
    static final int FRAMES_PER_PACKET = 256;
    static final int PCM_BYTES_PER_PACKET = FRAMES_PER_PACKET * CHANNELS * BYTES_PER_SAMPLE;
    private static final int HEADER_SIZE = 28;

    private final DatagramSocket socket;
    private final InetAddress address;
    private final int port;
    private final byte[] streamName = new byte[16];
    private int frameCounter = 0;

    VbanSender(String host, int port, String stream) throws IOException {
        this.address = InetAddress.getByName(host);
        this.port = port;
        this.socket = new DatagramSocket();

        byte[] raw = stream.getBytes(StandardCharsets.US_ASCII);
        System.arraycopy(raw, 0, streamName, 0, Math.min(raw.length, streamName.length));
    }

    void sendPcm16Stereo(byte[] pcm, int offset, int byteCount) throws IOException {
        if (byteCount <= 0 || byteCount % (CHANNELS * BYTES_PER_SAMPLE) != 0) return;

        int frames = byteCount / (CHANNELS * BYTES_PER_SAMPLE);
        if (frames < 1 || frames > 256) {
            throw new IllegalArgumentException("VBAN packet must contain 1-256 audio frames");
        }

        byte[] packet = new byte[HEADER_SIZE + byteCount];
        ByteBuffer h = ByteBuffer.wrap(packet).order(ByteOrder.LITTLE_ENDIAN);
        h.put((byte) 'V');
        h.put((byte) 'B');
        h.put((byte) 'A');
        h.put((byte) 'N');
        h.put((byte) 3);              // 48 kHz sample-rate index, audio sub-protocol
        h.put((byte) (frames - 1));   // VBAN stores sample count minus 1
        h.put((byte) (CHANNELS - 1)); // VBAN stores channel count minus 1
        h.put((byte) 1);              // signed 16-bit PCM
        h.put(streamName);
        h.putInt(frameCounter++);      // little-endian growing frame number

        System.arraycopy(pcm, offset, packet, HEADER_SIZE, byteCount);
        DatagramPacket datagram = new DatagramPacket(packet, packet.length, address, port);
        socket.send(datagram);
    }

    @Override
    public void close() {
        socket.close();
    }
}
