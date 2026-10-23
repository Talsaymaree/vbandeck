#!/usr/bin/env python3
import gi, json, subprocess
from pathlib import Path

gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, GLib

APP_ID = 'com.tee215.VBANDeck'
CFG = Path(GLib.get_user_config_dir()) / 'vbandeck' / 'settings.json'

class Window(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title='VBAN Deck')
        self.set_default_size(520, 500)
        self.proc = None
        self.poll_id = None

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        toolbar.add_top_bar(header)
        page = Adw.PreferencesPage()
        toolbar.set_content(page)
        self.set_content(toolbar)

        conn = Adw.PreferencesGroup(title='VBAN destination', description='Voicemeeter / VBAN receiver on your PC')
        page.add(conn)
        self.ip = Adw.EntryRow(title='Destination IP')
        self.port = Adw.EntryRow(title='Port')
        self.stream = Adw.EntryRow(title='Stream name')
        conn.add(self.ip); conn.add(self.port); conn.add(self.stream)

        audio = Adw.PreferencesGroup(title='Audio capture')
        page.add(audio)
        self.follow = Adw.SwitchRow(title='Follow default output', subtitle='Capture the current Steam Deck speaker/headphone/Bluetooth sink monitor')
        self.follow.set_active(True)
        audio.add(self.follow)
        self.target = Adw.EntryRow(title='Advanced: PipeWire sink node')
        audio.add(self.target)

        statusg = Adw.PreferencesGroup(title='Status')
        page.add(statusg)
        self.status = Adw.ActionRow(title='Stopped', subtitle='Native PipeWire capture → paced VBAN PCM')
        statusg.add(self.status)
        self.stats = Adw.ActionRow(title='48 kHz • stereo • 16-bit PCM', subtitle='256 frames/packet • ~5.33 ms packet cadence')
        statusg.add(self.stats)

        controls = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        controls.set_margin_top(18); controls.set_margin_bottom(18)
        controls.set_margin_start(18); controls.set_margin_end(18)
        self.start_btn = Gtk.Button(label='Start Streaming')
        self.start_btn.add_css_class('suggested-action')
        self.start_btn.set_hexpand(True)
        self.stop_btn = Gtk.Button(label='Stop')
        self.stop_btn.set_sensitive(False)
        controls.append(self.start_btn); controls.append(self.stop_btn)
        page.add(Adw.PreferencesGroup())
        toolbar.set_content(Gtk.Box())

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.append(page); outer.append(controls)
        toolbar.set_content(outer)

        self.start_btn.connect('clicked', self.start_stream)
        self.stop_btn.connect('clicked', self.stop_stream)
        self.connect('close-request', self.on_close)
        self.load()

    def load(self):
        vals = {'ip':'','port':'6980','stream':'SteamDeck','target':''}
        try: vals.update(json.loads(CFG.read_text()))
        except Exception: pass
        self.ip.set_text(vals['ip']); self.port.set_text(str(vals['port']))
        self.stream.set_text(vals['stream']); self.target.set_text(vals.get('target',''))

    def save(self):
        CFG.parent.mkdir(parents=True, exist_ok=True)
        CFG.write_text(json.dumps({'ip':self.ip.get_text().strip(),'port':self.port.get_text().strip(),
                                   'stream':self.stream.get_text().strip(),'target':self.target.get_text().strip()}, indent=2))

    def set_running(self, yes):
        self.start_btn.set_sensitive(not yes); self.stop_btn.set_sensitive(yes)
        self.status.set_title('Streaming' if yes else 'Stopped')
        self.status.set_subtitle('Sending native PipeWire audio to your PC' if yes else 'Native PipeWire capture → paced VBAN PCM')

    def start_stream(self, *_):
        if self.proc: return
        ip = self.ip.get_text().strip(); stream = self.stream.get_text().strip()
        try: port = int(self.port.get_text().strip())
        except ValueError:
            self.status.set_title('Invalid port'); return
        if not ip or not stream or len(stream) > 15:
            self.status.set_title('Check IP / stream name'); return
        self.save()
        cmd = ['/app/bin/vban-pipewire','--ip',ip,'--port',str(port),'--stream',stream]
        target = self.target.get_text().strip()
        if target and not self.follow.get_active(): cmd += ['--target',target]
        try:
            self.proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            self.set_running(True)
            self.poll_id = GLib.timeout_add(500, self.poll_proc)
        except Exception as e:
            self.proc = None; self.status.set_title('Failed to start'); self.status.set_subtitle(str(e))

    def poll_proc(self):
        if not self.proc: return False
        rc = self.proc.poll()
        if rc is None: return True
        tail = ''
        try: tail = self.proc.stderr.read()[-300:].strip()
        except Exception: pass
        self.proc = None; self.set_running(False)
        if rc != 0:
            self.status.set_title(f'Stopped with error ({rc})'); self.status.set_subtitle(tail or 'Run from Konsole for details')
        return False

    def stop_stream(self, *_):
        if not self.proc:
            return

        proc = self.proc
        self.proc = None

        try:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=1)
        except Exception:
            pass

        self.set_running(False)

        if self.poll_id:
            GLib.source_remove(self.poll_id)
            self.poll_id = None

    def on_close(self, *_):
        self.stop_stream(); self.save(); return False

class App(Adw.Application):
    def __init__(self): super().__init__(application_id=APP_ID)
    def do_activate(self): Window(self).present()

Adw.init(); App().run(None)
