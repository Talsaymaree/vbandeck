import {
  ButtonItem,
  PanelSection,
  PanelSectionRow,
  TextField,
  staticClasses,
} from "@decky/ui";
import { callable, definePlugin, toaster } from "@decky/api";
import { useEffect, useRef, useState } from "react";
import { FaBroadcastTower } from "react-icons/fa";

type Settings = {
  ip: string;
  port: number;
  stream: string;
  target: string;
};

type Status = {
  running: boolean;
  pid: number | null;
  settings: Settings;
  error: string;
};

const getStatus = callable<[], Status>("get_status");
const startStream = callable<[ip: string, port: number, stream: string, target: string], Status>("start_stream");
const stopStream = callable<[], Status>("stop_stream");

function Content() {
  const [settings, setSettings] = useState<Settings>({ ip: "", port: 6980, stream: "SteamDeck", target: "" });
  const settingsInitialized = useRef(false);
  const [running, setRunning] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("Stopped");

  const refresh = async () => {
    try {
      const s = await getStatus();
      setRunning(s.running);
      // Poll status without replacing the form's in-progress edits.
      if (!settingsInitialized.current) {
        settingsInitialized.current = true;
        setSettings(s.settings);
      }
      setMessage(s.running ? `Streaming to ${s.settings.ip}:${s.settings.port}` : (s.error || "Stopped"));
    } catch (e) {
      setMessage(String(e));
    }
  };

  useEffect(() => {
    refresh();
    const timer = window.setInterval(refresh, 2000);
    return () => window.clearInterval(timer);
  }, []);

  const update = <K extends keyof Settings>(key: K, value: Settings[K]) => {
    // Also protect edits made before the initial status request returns.
    settingsInitialized.current = true;
    setSettings((old) => ({ ...old, [key]: value }));
  };

  const start = async () => {
    setBusy(true);
    try {
      const s = await startStream(settings.ip.trim(), Number(settings.port), settings.stream.trim(), settings.target.trim());
      setRunning(s.running);
      setMessage(s.running ? `Streaming to ${s.settings.ip}:${s.settings.port}` : (s.error || "Failed to start"));
      if (!s.running) toaster.toast({ title: "VBAN Deck", body: s.error || "Could not start stream" });
    } catch (e) {
      setMessage(String(e));
      toaster.toast({ title: "VBAN Deck", body: String(e) });
    } finally {
      setBusy(false);
    }
  };

  const stop = async () => {
    setBusy(true);
    try {
      const s = await stopStream();
      setRunning(s.running);
      setMessage("Stopped");
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <PanelSection title="VBAN destination">
        <PanelSectionRow>
          <TextField
            label="PC IP"
            value={settings.ip}
            disabled={running}
            onChange={(e: any) => update("ip", e.target.value)}
          />
        </PanelSectionRow>
        <PanelSectionRow>
          <TextField
            label="Port"
            value={String(settings.port)}
            disabled={running}
            onChange={(e: any) => update("port", Number(e.target.value || 6980))}
          />
        </PanelSectionRow>
        <PanelSectionRow>
          <TextField
            label="Stream name"
            value={settings.stream}
            disabled={running}
            onChange={(e: any) => update("stream", e.target.value.slice(0, 15))}
          />
        </PanelSectionRow>
      </PanelSection>

      <PanelSection title="Audio">
        <PanelSectionRow>
          <div style={{ fontSize: "12px", opacity: 0.8, paddingBottom: "8px" }}>
            Captures the current default Steam Deck output through native PipeWire. Leave Advanced target blank unless you need a specific sink node.
          </div>
        </PanelSectionRow>
        <PanelSectionRow>
          <TextField
            label="Advanced target (optional)"
            value={settings.target}
            disabled={running}
            onChange={(e: any) => update("target", e.target.value)}
          />
        </PanelSectionRow>
      </PanelSection>

      <PanelSection title="Status">
        <PanelSectionRow>
          <div style={{ padding: "8px 0", fontWeight: 600 }}>{running ? "● Streaming" : "○ Stopped"}</div>
          <div style={{ fontSize: "12px", opacity: 0.8, paddingBottom: "8px" }}>{message}</div>
        </PanelSectionRow>
        <PanelSectionRow>
          <ButtonItem layout="below" disabled={busy} onClick={running ? stop : start}>
            {busy ? "Working…" : running ? "Stop Streaming" : "Start Streaming"}
          </ButtonItem>
        </PanelSectionRow>
      </PanelSection>
    </>
  );
}

export default definePlugin(() => ({
  name: "VBAN Deck",
  titleView: <div className={staticClasses.Title}>VBAN Deck</div>,
  content: <Content />,
  icon: <FaBroadcastTower />,
  onDismount() {
    // The Python backend deliberately keeps a stream alive if only the UI panel
    // is closed. Decky calls backend _unload when the plugin itself unloads,
    // and that stops the sender cleanly.
  },
}));
