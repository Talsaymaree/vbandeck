package com.tee215.vbandeck;

import android.Manifest;
import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.media.projection.MediaProjectionManager;
import android.os.Build;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.nio.charset.StandardCharsets;

public class MainActivity extends Activity {
    private static final int REQ_AUDIO = 1001;
    private static final int REQ_CAPTURE = 1002;

    private EditText ipField;
    private EditText portField;
    private EditText streamField;
    private TextView status;
    private Button startButton;
    private Button stopButton;
    private SharedPreferences prefs;

    private String pendingIp;
    private int pendingPort;
    private String pendingStream;

    private final BroadcastReceiver statusReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            boolean isRunning = intent.getBooleanExtra(AudioCaptureService.EXTRA_RUNNING, false);
            String message = intent.getStringExtra(AudioCaptureService.EXTRA_MESSAGE);
            updateStatus(isRunning, message == null ? "" : message);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        prefs = getSharedPreferences("vban", MODE_PRIVATE);
        buildUi();
        loadSettings();

        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1003);
        }
    }

    @Override
    protected void onStart() {
        super.onStart();
        IntentFilter filter = new IntentFilter(AudioCaptureService.ACTION_STATUS);
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(statusReceiver, filter, RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(statusReceiver, filter);
        }
    }

    @Override
    protected void onStop() {
        try { unregisterReceiver(statusReceiver); } catch (Exception ignored) {}
        super.onStop();
    }

    private void buildUi() {
        int pad = dp(20);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, pad, pad, pad);
        root.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView title = new TextView(this);
        title.setText("VBAN Deck");
        title.setTextSize(28);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title, matchWrap());

        TextView subtitle = new TextView(this);
        subtitle.setText("Android system-audio → VBAN\n48 kHz • Stereo • PCM 16-bit • 256 frames/packet");
        subtitle.setTextSize(14);
        subtitle.setPadding(0, dp(6), 0, dp(20));
        root.addView(subtitle, matchWrap());

        ipField = field("Destination IP", InputType.TYPE_CLASS_PHONE);
        root.addView(ipField, matchWrap());

        portField = field("Port", InputType.TYPE_CLASS_NUMBER);
        root.addView(portField, matchWrap());

        streamField = field("VBAN stream name", InputType.TYPE_CLASS_TEXT);
        root.addView(streamField, matchWrap());

        startButton = new Button(this);
        startButton.setText("START STREAMING");
        startButton.setOnClickListener(v -> beginStart());
        root.addView(startButton, matchWrap());

        stopButton = new Button(this);
        stopButton.setText("STOP");
        stopButton.setEnabled(false);
        stopButton.setOnClickListener(v -> stopStreaming());
        root.addView(stopButton, matchWrap());

        status = new TextView(this);
        status.setText("Stopped");
        status.setTextSize(16);
        status.setPadding(0, dp(18), 0, 0);
        root.addView(status, matchWrap());

        TextView note = new TextView(this);
        note.setText("Android will show a system capture prompt each time you start. Some apps can block playback capture; those apps may send silence.");
        note.setTextSize(13);
        note.setPadding(0, dp(20), 0, 0);
        root.addView(note, matchWrap());

        ScrollView scroll = new ScrollView(this);
        scroll.addView(root);
        setContentView(scroll);
    }

    private EditText field(String hint, int inputType) {
        EditText e = new EditText(this);
        e.setHint(hint);
        e.setSingleLine(true);
        e.setInputType(inputType);
        e.setTextSize(18);
        e.setPadding(dp(12), dp(12), dp(12), dp(12));
        return e;
    }

    private LinearLayout.LayoutParams matchWrap() {
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        p.setMargins(0, dp(5), 0, dp(5));
        return p;
    }

    private void loadSettings() {
        ipField.setText(prefs.getString("ip", ""));
        portField.setText(String.valueOf(prefs.getInt("port", 6980)));
        streamField.setText(prefs.getString("stream", "Android"));
    }

    private void beginStart() {
        pendingIp = ipField.getText().toString().trim();
        pendingStream = streamField.getText().toString().trim();

        try {
            pendingPort = Integer.parseInt(portField.getText().toString().trim());
        } catch (Exception e) {
            toast("Port must be a number");
            return;
        }

        if (pendingIp.isEmpty()) {
            toast("Destination IP is required");
            return;
        }
        if (pendingPort < 1 || pendingPort > 65535) {
            toast("Port must be 1-65535");
            return;
        }
        int streamBytes = pendingStream.getBytes(StandardCharsets.US_ASCII).length;
        if (pendingStream.isEmpty() || streamBytes > 16) {
            toast("VBAN stream name must be 1-16 ASCII characters");
            return;
        }

        prefs.edit()
                .putString("ip", pendingIp)
                .putInt("port", pendingPort)
                .putString("stream", pendingStream)
                .apply();

        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, REQ_AUDIO);
            return;
        }
        requestProjection();
    }

    private void requestProjection() {
        MediaProjectionManager mpm = (MediaProjectionManager) getSystemService(MEDIA_PROJECTION_SERVICE);
        startActivityForResult(mpm.createScreenCaptureIntent(), REQ_CAPTURE);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQ_AUDIO) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                requestProjection();
            } else {
                toast("Audio permission is required for playback capture");
            }
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQ_CAPTURE) return;
        if (resultCode != RESULT_OK || data == null) {
            updateStatus(false, "Capture permission denied");
            return;
        }

        Intent service = new Intent(this, AudioCaptureService.class);
        service.putExtra(AudioCaptureService.EXTRA_RESULT_CODE, resultCode);
        service.putExtra(AudioCaptureService.EXTRA_PROJECTION_DATA, data);
        service.putExtra(AudioCaptureService.EXTRA_IP, pendingIp);
        service.putExtra(AudioCaptureService.EXTRA_PORT, pendingPort);
        service.putExtra(AudioCaptureService.EXTRA_STREAM, pendingStream);
        startForegroundService(service);
        updateStatus(true, "Starting…");
    }

    private void stopStreaming() {
        Intent stop = new Intent(this, AudioCaptureService.class);
        stop.setAction(AudioCaptureService.ACTION_STOP);
        startService(stop);
        updateStatus(false, "Stopping…");
    }

    private void updateStatus(boolean isRunning, String message) {
        status.setText(message);
        startButton.setEnabled(!isRunning);
        stopButton.setEnabled(isRunning);
    }

    private void toast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }
}
