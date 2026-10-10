package com.tee215.vbandeck;

import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioPlaybackCaptureConfiguration;
import android.media.AudioRecord;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjectionManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.IBinder;
import android.os.Parcelable;

import java.util.concurrent.atomic.AtomicBoolean;

public class AudioCaptureService extends Service {
    public static final String ACTION_STOP = "com.tee215.vbandeck.STOP";
    public static final String ACTION_STATUS = "com.tee215.vbandeck.STATUS";
    public static final String EXTRA_RESULT_CODE = "result_code";
    public static final String EXTRA_PROJECTION_DATA = "projection_data";
    public static final String EXTRA_IP = "ip";
    public static final String EXTRA_PORT = "port";
    public static final String EXTRA_STREAM = "stream";
    public static final String EXTRA_RUNNING = "running";
    public static final String EXTRA_MESSAGE = "message";

    private static final String CHANNEL_ID = "vban_stream";
    private static final int NOTIFICATION_ID = 215;

    private final AtomicBoolean running = new AtomicBoolean(false);
    private Thread worker;
    private MediaProjection projection;
    private MediaProjection.Callback projectionCallback;
    private AudioRecord recorder;

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_NOT_STICKY;

        if (ACTION_STOP.equals(intent.getAction())) {
            stopCapture("Stopped");
            return START_NOT_STICKY;
        }

        startInForeground();
        if (running.get()) return START_NOT_STICKY;

        int resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED);
        Intent projectionData = getProjectionData(intent);
        String ip = intent.getStringExtra(EXTRA_IP);
        int port = intent.getIntExtra(EXTRA_PORT, 6980);
        String stream = intent.getStringExtra(EXTRA_STREAM);

        if (resultCode != Activity.RESULT_OK || projectionData == null || ip == null || stream == null) {
            stopCapture("Missing capture permission or VBAN settings");
            return START_NOT_STICKY;
        }

        try {
            MediaProjectionManager mpm = (MediaProjectionManager) getSystemService(MEDIA_PROJECTION_SERVICE);
            projection = mpm.getMediaProjection(resultCode, projectionData);
            if (projection == null) throw new IllegalStateException("Could not obtain MediaProjection");
            // Required for MediaProjection sessions on Android 14+ and also makes
            // system-initiated capture stops (lock screen, user action, etc.) safe.
            projectionCallback = new MediaProjection.Callback() {
                @Override
                public void onStop() {
                    stopCapture("Capture stopped by Android");
                }
            };
            projection.registerCallback(projectionCallback, new Handler(Looper.getMainLooper()));

            AudioPlaybackCaptureConfiguration captureConfig =
                    new AudioPlaybackCaptureConfiguration.Builder(projection)
                            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                            .addMatchingUsage(AudioAttributes.USAGE_GAME)
                            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                            .build();

            AudioFormat format = new AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(VbanSender.SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
                    .build();

            int min = AudioRecord.getMinBufferSize(
                    VbanSender.SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_STEREO,
                    AudioFormat.ENCODING_PCM_16BIT);
            int bufferSize = Math.max(min, VbanSender.PCM_BYTES_PER_PACKET * 8);

            recorder = new AudioRecord.Builder()
                    .setAudioFormat(format)
                    .setBufferSizeInBytes(bufferSize)
                    .setAudioPlaybackCaptureConfig(captureConfig)
                    .build();

            if (recorder.getState() != AudioRecord.STATE_INITIALIZED) {
                throw new IllegalStateException("AudioRecord failed to initialize");
            }

            running.set(true);
            recorder.startRecording();
            sendStatus(true, "Streaming to " + ip + ":" + port);

            worker = new Thread(() -> streamLoop(ip, port, stream), "VBAN-Audio-Sender");
            worker.start();
        } catch (Exception e) {
            stopCapture("Start failed: " + safeMessage(e));
        }

        return START_NOT_STICKY;
    }

    private void streamLoop(String ip, int port, String stream) {
        byte[] packetAudio = new byte[VbanSender.PCM_BYTES_PER_PACKET];
        int filled = 0;

        try (VbanSender sender = new VbanSender(ip, port, stream)) {
            while (running.get()) {
                int read = recorder.read(
                        packetAudio,
                        filled,
                        packetAudio.length - filled,
                        AudioRecord.READ_BLOCKING);

                if (read < 0) throw new IllegalStateException("AudioRecord read error " + read);
                if (read == 0) continue;
                filled += read;

                if (filled == packetAudio.length) {
                    sender.sendPcm16Stereo(packetAudio, 0, filled);
                    filled = 0;
                }
            }
        } catch (Exception e) {
            if (running.get()) {
                stopCapture("Streaming error: " + safeMessage(e));
            }
        }
    }

    private void startInForeground() {
        Intent openApp = new Intent(this, MainActivity.class);
        PendingIntent pending = PendingIntent.getActivity(
                this, 0, openApp,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification notification = new Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .setContentTitle("VBAN Deck")
                .setContentText("Capturing Android audio for VBAN")
                .setContentIntent(pending)
                .setOngoing(true)
                .build();

        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
    }

    private Intent getProjectionData(Intent source) {
        if (Build.VERSION.SDK_INT >= 33) {
            return source.getParcelableExtra(EXTRA_PROJECTION_DATA, Intent.class);
        }
        Parcelable value = source.getParcelableExtra(EXTRA_PROJECTION_DATA);
        return value instanceof Intent ? (Intent) value : null;
    }

    private void stopCapture(String message) {
        if (!running.getAndSet(false)) {
            sendStatus(false, message);
            stopForeground(STOP_FOREGROUND_REMOVE);
            stopSelf();
            return;
        }

        try {
            if (recorder != null) recorder.stop();
        } catch (Exception ignored) {}
        try {
            if (recorder != null) recorder.release();
        } catch (Exception ignored) {}
        recorder = null;

        MediaProjection activeProjection = projection;
        projection = null;
        if (activeProjection != null) {
            try {
                if (projectionCallback != null) activeProjection.unregisterCallback(projectionCallback);
            } catch (Exception ignored) {}
            try { activeProjection.stop(); } catch (Exception ignored) {}
        }
        projectionCallback = null;

        sendStatus(false, message);
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    private void sendStatus(boolean isRunning, String message) {
        Intent status = new Intent(ACTION_STATUS);
        status.setPackage(getPackageName());
        status.putExtra(EXTRA_RUNNING, isRunning);
        status.putExtra(EXTRA_MESSAGE, message);
        sendBroadcast(status);
    }

    private void createNotificationChannel() {
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "VBAN streaming",
                NotificationManager.IMPORTANCE_LOW);
        nm.createNotificationChannel(channel);
    }

    private static String safeMessage(Throwable t) {
        String m = t.getMessage();
        return m == null || m.trim().isEmpty() ? t.getClass().getSimpleName() : m;
    }

    @Override
    public void onDestroy() {
        if (running.get()) stopCapture("Stopped");
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
