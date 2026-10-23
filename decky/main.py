import asyncio
import json
import os
import signal
import subprocess
from pathlib import Path

import decky

DEFAULTS = {
    "ip": "",
    "port": 6980,
    "stream": "SteamDeck",
    "target": "",
}


class Plugin:
    def __init__(self):
        self.proc = None
        self.last_error = ""
        self.settings = dict(DEFAULTS)
        self.settings_file = None

    def _binary(self) -> str:
        return os.path.join(decky.DECKY_PLUGIN_DIR, "bin", "vban-pipewire")

    def _runtime_env(self):
        env = os.environ.copy()
        # Decky's backend may run as root. Point PipeWire explicitly at the
        # logged-in Steam Deck user's session socket.
        env["XDG_RUNTIME_DIR"] = "/run/user/1000"
        env["PIPEWIRE_RUNTIME_DIR"] = "/run/user/1000"
        return env

    def _load_settings_sync(self):
        self.settings_file = Path(decky.DECKY_PLUGIN_SETTINGS_DIR) / "settings.json"
        try:
            loaded = json.loads(self.settings_file.read_text())
            self.settings.update({k: loaded[k] for k in DEFAULTS if k in loaded})
        except Exception:
            pass
        self.settings["port"] = int(self.settings.get("port", 6980))

    def _save_settings_sync(self):
        self.settings_file.parent.mkdir(parents=True, exist_ok=True)
        self.settings_file.write_text(json.dumps(self.settings, indent=2))

    def _is_running(self):
        if self.proc is None:
            return False
        if self.proc.poll() is None:
            return True
        try:
            err = self.proc.stderr.read().strip() if self.proc.stderr else ""
            if err:
                self.last_error = err[-600:]
        except Exception:
            pass
        self.proc = None
        return False

    def _status(self):
        return {
            "running": self._is_running(),
            "pid": self.proc.pid if self.proc and self.proc.poll() is None else None,
            "settings": dict(self.settings),
            "error": self.last_error,
        }

    async def get_status(self):
        return self._status()

    async def save_settings(self, settings: dict):
        ip = str(settings.get("ip", "")).strip()
        stream = str(settings.get("stream", "SteamDeck")).strip()
        target = str(settings.get("target", "")).strip()
        try:
            port = int(settings.get("port", 6980))
        except Exception:
            raise ValueError("Port must be a number")
        if not ip:
            raise ValueError("Destination IP is required")
        if not (1 <= port <= 65535):
            raise ValueError("Port must be 1-65535")
        if not stream or len(stream.encode("utf-8")) > 15:
            raise ValueError("VBAN stream name must be 1-15 bytes")
        self.settings = {"ip": ip, "port": port, "stream": stream, "target": target}
        self._save_settings_sync()
        return dict(self.settings)

    async def start_stream(self, ip: str, port: int, stream: str, target: str = ""):
        try:
            await self.save_settings({"ip": ip, "port": port, "stream": stream, "target": target})
        except (ValueError, TypeError, OSError) as e:
            self.last_error = str(e)
            return self._status()
        if self._is_running():
            return self._status()

        binary = self._binary()
        if not os.path.isfile(binary):
            self.last_error = f"Missing native sender: {binary}"
            return self._status()

        cmd = [binary, "--ip", self.settings["ip"], "--port", str(self.settings["port"]), "--stream", self.settings["stream"]]
        if self.settings["target"]:
            cmd += ["--target", self.settings["target"]]

        self.last_error = ""
        try:
            self.proc = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
                env=self._runtime_env(),
            )
            await asyncio.sleep(0.35)
            if self.proc.poll() is not None:
                err = self.proc.stderr.read().strip() if self.proc.stderr else ""
                self.last_error = err[-600:] or f"Sender exited with code {self.proc.returncode}"
                self.proc = None
        except Exception as e:
            self.last_error = str(e)
            self.proc = None
        return self._status()

    async def stop_stream(self):
        if self.proc is not None:
            proc = self.proc
            self.proc = None
            try:
                proc.send_signal(signal.SIGTERM)
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=1)
            except Exception as e:
                self.last_error = str(e)
        return self._status()

    async def _main(self):
        self._load_settings_sync()
        decky.logger.info("VBAN Deck loaded")

    async def _unload(self):
        await self.stop_stream()
        decky.logger.info("VBAN Deck unloaded; sender stopped")

    async def _uninstall(self):
        await self.stop_stream()
