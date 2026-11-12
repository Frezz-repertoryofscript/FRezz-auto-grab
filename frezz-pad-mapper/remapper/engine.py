"""Moteur de remappage : lit la manette, applique profil / turbo / macros, envoie la sortie."""

import copy
import math
import queue
import threading
import time
import traceback

from .constants import PHYS_BUTTONS, PHYS_AXES, STICKS
from .macro import MacroInstance
from .profile import normalize_profile, default_profile

STICK_AXES = {"pad:LS": ("LX", "LY"), "pad:RS": ("RX", "RY")}
DIGITAL_STICK_KEYS = {
    "wasd": ("key:w", "key:s", "key:a", "key:d"),
    "zqsd": ("key:z", "key:s", "key:q", "key:d"),
    "arrows": ("key:up", "key:down", "key:left", "key:right"),
}
TRIGGER_TARGETS = {"pad:L2": "L2", "pad:R2": "R2"}


def clamp(v, lo=-1.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def process_stick(x, y, cfg):
    """Zone morte radiale, courbe, sensibilité, anti-zone morte, inversion."""
    if cfg.get("invert_x"):
        x = -x
    if cfg.get("invert_y"):
        y = -y
    mag = math.hypot(x, y)
    dz = clamp(float(cfg.get("deadzone", 0.08)), 0.0, 0.9)
    outer = clamp(float(cfg.get("outer", 0.98)), dz + 0.01, 1.0)
    if mag <= dz or mag == 0.0:
        return 0.0, 0.0
    norm = clamp((mag - dz) / (outer - dz), 0.0, 1.0)
    norm = norm ** max(float(cfg.get("curve", 1.0)), 0.1)
    anti = clamp(float(cfg.get("anti_deadzone", 0.0)), 0.0, 0.9)
    norm = anti + (1.0 - anti) * norm
    norm = clamp(norm * float(cfg.get("sensitivity", 1.0)), 0.0, 1.0)
    scale = norm / mag
    return clamp(x * scale), clamp(y * scale)


def process_trigger(v, cfg):
    dz = clamp(float(cfg.get("deadzone", 0.02)), 0.0, 0.9)
    outer = clamp(float(cfg.get("outer", 0.98)), dz + 0.01, 1.0)
    if v <= dz:
        return 0.0
    return clamp((v - dz) / (outer - dz), 0.0, 1.0)


class OutputState:
    __slots__ = ("targets", "axes", "mouse")

    def __init__(self, targets=None, axes=None, mouse=(0.0, 0.0)):
        self.targets = set(targets or ())
        self.axes = dict(axes or {a: 0.0 for a in PHYS_AXES})
        self.mouse = mouse


class EngineCore:
    """Logique pure (sans matériel) : entrée physique -> état de sortie désiré."""

    def __init__(self, profile=None, rng=None):
        self.rng = rng
        self.profile = None
        self.paused = False
        self.prev = {b: False for b in PHYS_BUTTONS}
        self.press_time = {}
        self.turbo_on = {}
        self.turbo_since = {}
        self.chord_prev = {}
        self.trig = {}          # état des déclencheurs de macros
        self.running = {}       # nom -> MacroInstance
        self.manual = []        # macros lancées depuis l'interface
        self.recording = None
        self.last_now = None
        self.set_profile(profile or default_profile())

    # ------------------------------------------------------------------ profil
    def set_profile(self, profile):
        self.profile = normalize_profile(profile)
        self.macros = {m["name"]: m for m in self.profile["macros"]}
        # combos les plus longs d'abord : ils ont la priorité sur leurs sous-ensembles
        self.triggered = sorted(
            (m for m in self.profile["macros"] if m["enabled"] and m["trigger"]),
            key=lambda m: -len(m["trigger"]),
        )
        self.chords = [tuple(m["trigger"]) for m in self.triggered]
        self.chords += [tuple(c) for c in self.profile["hotkeys"].values() if c]
        self.stop_all_macros()
        self.trig.clear()
        self.turbo_on.clear()

    def stop_all_macros(self):
        for inst in list(self.running.values()) + self.manual:
            inst.stop()
        self.running.clear()
        self.manual = []

    # ----------------------------------------------------------------- macros
    def start_macro(self, macro, now, loop=False):
        inst = MacroInstance(macro, now, loop=loop, rng=self.rng)
        inst.update(now)
        self.running[macro["name"]] = inst
        return inst

    def run_manual(self, macro, now):
        """Lance une macro depuis l'interface (bouton « Tester »)."""
        inst = MacroInstance(normalize_profile({"macros": [macro]})["macros"][0], now, rng=self.rng)
        self.manual.append(inst)

    def _is_running(self, name):
        inst = self.running.get(name)
        return inst is not None and not inst.finished

    def _handle_trigger(self, m, key, held, now):
        st = self.trig.setdefault(key, {"prev": False, "rise": 0.0, "last_rise": -1e9, "fired": False})
        was = st["prev"]
        st["prev"] = held
        name, mode = m["name"], m["mode"]
        rising, falling = held and not was, was and not held
        if rising:
            st["rise"] = now
        if mode == "press":
            if rising and not self._is_running(name):
                self.start_macro(m, now)
        elif mode == "hold":
            if rising:
                self.start_macro(m, now, loop=True)
            elif falling and self._is_running(name):
                self.running.pop(name).stop()
        elif mode == "toggle":
            if rising:
                if self._is_running(name):
                    self.running.pop(name).stop()
                else:
                    self.start_macro(m, now, loop=True)
        elif mode == "release":
            if falling and not self._is_running(name):
                self.start_macro(m, now)
        elif mode == "double":
            if rising:
                if now - st["last_rise"] <= m["double_ms"] / 1000.0:
                    st["last_rise"] = -1e9
                    if not self._is_running(name):
                        self.start_macro(m, now)
                else:
                    st["last_rise"] = now
        elif mode == "long":
            if held and not st["fired"] and now - st["rise"] >= m["hold_ms"] / 1000.0:
                st["fired"] = True
                if not self._is_running(name):
                    self.start_macro(m, now)
            if not held:
                st["fired"] = False

    # -------------------------------------------------------------- recording
    def start_recording(self, now):
        self.recording = {"start": now, "last": now, "steps": [], "targets": set(),
                          "axes": {a: 0.0 for a in PHYS_AXES}, "axis_time": {}}

    def stop_recording(self, now):
        rec, self.recording = self.recording, None
        if not rec:
            return []
        steps = rec["steps"]
        if rec["targets"]:
            self._rec_wait(rec, now)
            steps.append({"type": "release", "targets": sorted(rec["targets"])})
        if any(rec["axes"].values()):
            steps.append({"type": "release_all"})
        return compact_steps(steps)

    def _rec_wait(self, rec, now):
        ms = int(round((now - rec["last"]) * 1000))
        if ms >= 1:
            rec["steps"].append({"type": "wait", "ms": ms})
            rec["last"] = now

    def _record(self, targets, axes, now):
        rec = self.recording
        added, removed = targets - rec["targets"], rec["targets"] - targets
        if added or removed:
            self._rec_wait(rec, now)
            if removed:
                rec["steps"].append({"type": "release", "targets": sorted(removed)})
            if added:
                rec["steps"].append({"type": "press", "targets": sorted(added)})
            rec["targets"] = set(targets)
        for a in PHYS_AXES:
            v, last = round(axes.get(a, 0.0), 2), rec["axes"][a]
            if v == last:
                continue
            big = abs(v - last) >= 0.2 or (v == 0.0) != (last == 0.0)
            if big and now - rec["axis_time"].get(a, -1) >= 0.03:
                self._rec_wait(rec, now)
                rec["steps"].append({"type": "axis", "axis": a, "value": v})
                rec["axes"][a] = v
                rec["axis_time"][a] = now

    # ------------------------------------------------------------------- tick
    def process(self, buttons, axes, now):
        p = self.profile
        dt = 0.0 if self.last_now is None else clamp(now - self.last_now, 0.0, 0.1)
        self.last_now = now
        buttons = {b: bool(buttons.get(b, False)) for b in PHYS_BUTTONS}
        axes = {a: float(axes.get(a, 0.0)) for a in PHYS_AXES}
        for side in ("L2", "R2"):
            if axes[side] > p["triggers"][side]["threshold"]:
                buttons[side] = True
        for b in PHYS_BUTTONS:
            if buttons[b] and not self.prev[b]:
                self.press_time[b] = now

        out = OutputState()
        actions = []
        blocked = set()

        # Combos actuellement tenus (pour la priorité des combos longs)
        held_chords = [c for c in self.chords if len(c) > 1 and all(buttons[b] for b in c)]

        def shadowed(chord):
            s = set(chord)
            return any(len(c) > len(chord) and s < set(c) for c in held_chords)

        # Raccourcis globaux (fonctionnent même en pause)
        for action, chord in p["hotkeys"].items():
            if not chord:
                continue
            key = ("hotkey", action)
            held = all(buttons[b] for b in chord) and not shadowed(chord)
            if held and not self.chord_prev.get(key):
                actions.append(action)
            self.chord_prev[key] = held
            if held:
                blocked.update(chord)
        if "toggle_pause" in actions:
            self.paused = not self.paused
            self.stop_all_macros()
        if "stop_macros" in actions:
            self.stop_all_macros()

        if self.paused:
            self.prev = buttons
            return out, actions

        # Macros déclenchées par bouton / combo
        for m in self.triggered:
            held = all(buttons[b] for b in m["trigger"]) and not shadowed(m["trigger"])
            self._handle_trigger(m, ("trig", m["name"]), held, now)
            if m["block_trigger"] and held:
                blocked.update(m["trigger"])

        # Remappage bouton par bouton
        bmap = p["buttons"]
        rec_targets = set()
        for b in PHYS_BUTTONS:
            target = bmap.get(b, "none")
            pressed = buttons[b] and b not in blocked
            turbo = p["turbo"].get(b)
            if turbo and turbo["enabled"]:
                pressed = self._turbo(b, turbo, pressed, now)
            kind, _, name = target.partition(":")
            if kind == "macro":
                m = self.macros.get(name)
                if m:
                    self._handle_trigger(m, ("btn", b, name), pressed, now)
                continue
            if kind == "action":
                if pressed and not self.prev[b]:
                    actions.append(name)
                continue
            if target == "none" or not pressed:
                continue
            # Gâchette analogique -> gâchette virtuelle analogique (sauf turbo)
            if b in ("L2", "R2") and target in TRIGGER_TARGETS and not (turbo and turbo["enabled"]):
                continue
            rec_targets.add(target)

        # Gâchettes analogiques
        for side in ("L2", "R2"):
            target = bmap.get(side)
            turbo = p["turbo"].get(side)
            if target in TRIGGER_TARGETS and side not in blocked and not (turbo and turbo["enabled"]):
                v = process_trigger(axes[side], p["triggers"][side])
                a = TRIGGER_TARGETS[target]
                out.axes[a] = max(out.axes[a], v)

        # Sticks
        mx = my = 0.0
        for side, (ax, ay) in STICKS.items():
            cfg = p["sticks"][side]
            x, y = process_stick(axes[ax], axes[ay], cfg)
            tgt = cfg.get("target", "none")
            if tgt in STICK_AXES:
                ox, oy = STICK_AXES[tgt]
                out.axes[ox] = clamp(out.axes[ox] + x)
                out.axes[oy] = clamp(out.axes[oy] + y)
            elif tgt == "mouse":
                speed = float(cfg.get("mouse_speed", 1400.0))
                mx += x * speed * dt
                my += y * speed * dt
            elif tgt in DIGITAL_STICK_KEYS:
                up, down, left, right = DIGITAL_STICK_KEYS[tgt]
                thr = float(cfg.get("digital_threshold", 0.5))
                if y < -thr:
                    rec_targets.add(up)
                if y > thr:
                    rec_targets.add(down)
                if x < -thr:
                    rec_targets.add(left)
                if x > thr:
                    rec_targets.add(right)
        out.mouse = (mx, my)

        if self.recording is not None:
            self._record(rec_targets, out.axes, now)
        out.targets |= rec_targets

        # Macros en cours : leurs boutons/axes s'ajoutent (et priment pour les axes)
        for name in list(self.running):
            inst = self.running[name]
            if not inst.update(now):
                del self.running[name]
                continue
            out.targets |= inst.held
            out.axes.update(inst.axes)
        alive = []
        for inst in self.manual:
            if inst.update(now):
                out.targets |= inst.held
                out.axes.update(inst.axes)
                alive.append(inst)
        self.manual = alive

        self.prev = buttons
        return out, actions

    def _turbo(self, b, cfg, pressed, now):
        period = 1.0 / max(cfg["rate"], 0.5)
        if cfg["mode"] == "toggle":
            if pressed and not self.prev[b]:
                self.turbo_on[b] = not self.turbo_on.get(b, False)
                self.turbo_since[b] = now
            if not self.turbo_on.get(b):
                return False
            start = self.turbo_since[b]
        else:
            if not pressed:
                return False
            start = self.press_time.get(b, now)
        return ((now - start) % period) < period / 2

    def running_info(self):
        info = [(i.name, i.progress) for i in self.running.values() if not i.finished]
        info += [(i.name + " (test)", i.progress) for i in self.manual if not i.finished]
        return info


def compact_steps(steps):
    """Fusionne press X / wait / release X en tap X, et les attentes consécutives."""
    out = []
    i = 0
    while i < len(steps):
        s = steps[i]
        if (
            s["type"] == "press" and i + 2 < len(steps)
            and steps[i + 1]["type"] == "wait"
            and steps[i + 2]["type"] == "release"
            and steps[i + 2]["targets"] == s["targets"]
        ):
            out.append({"type": "tap", "targets": s["targets"], "ms": steps[i + 1]["ms"]})
            i += 3
            continue
        if s["type"] == "wait" and out and out[-1]["type"] == "wait":
            out[-1]["ms"] += s["ms"]
        else:
            out.append(dict(s))
        i += 1
    return out


class Engine:
    """Boucle temps réel dans un thread : entrée -> EngineCore -> sortie."""

    def __init__(self, input_factory, output_factory, tick_hz=1000, log=print):
        self.input_factory = input_factory
        self.output_factory = output_factory
        self.tick = 1.0 / max(int(tick_hz), 60)
        self.log = log
        self.core = EngineCore()
        self.lock = threading.Lock()
        self.commands = queue.Queue()
        self.events = queue.Queue()   # (type, data) pour l'interface
        self.thread = None
        self.alive = False
        self.input = None
        self.output = None
        self._snap = {}
        self.loop_hz = 0.0

    # ----------------------------------------------- API (thread interface)
    def start(self):
        if self.thread and self.thread.is_alive():
            return
        self.alive = True
        self.thread = threading.Thread(target=self._run, name="engine", daemon=True)
        self.thread.start()

    def stop(self):
        self.alive = False
        if self.thread:
            self.thread.join(timeout=2)

    def send(self, cmd, *args):
        self.commands.put((cmd, args))

    def set_profile(self, profile):
        self.send("profile", copy.deepcopy(profile))

    def snapshot(self):
        with self.lock:
            return dict(self._snap)

    # ------------------------------------------------------- thread moteur
    def _run(self):
        try:
            self.input = self.input_factory()
            self.output = self.output_factory()
        except Exception as e:  # noqa: BLE001
            self.log(f"Erreur d'initialisation : {e}")
            self.events.put(("error", str(e)))
            return
        self.log(f"Sortie : {self.output.describe()}")
        hi_res = _enable_hires_timer()
        next_t = time.perf_counter()
        count, count_t = 0, next_t
        try:
            while self.alive:
                now = time.perf_counter()
                self._commands(now)
                state = self.input.poll()
                for ev in state.get("events", []):
                    self.log(ev)
                    self.events.put(("device", ev))
                out, actions = self.core.process(state["buttons"], state["axes"], now)
                if not state["connected"]:
                    out = OutputState()
                self.output.apply(out, self.core.profile["virtual_pad"])
                for a in actions:
                    self.events.put(("action", a))
                count += 1
                if now - count_t >= 1.0:
                    self.loop_hz = count / (now - count_t)
                    count, count_t = 0, now
                with self.lock:
                    self._snap = {
                        "connected": state["connected"],
                        "device": state.get("name", ""),
                        "battery": state.get("battery", ""),
                        "buttons": dict(self.core.prev),
                        "axes": dict(state["axes"]),
                        "raw": state.get("raw"),
                        "out_targets": set(out.targets),
                        "out_axes": dict(out.axes),
                        "running": self.core.running_info(),
                        "paused": self.core.paused,
                        "recording": self.core.recording is not None,
                        "profile": self.core.profile["name"],
                        "hz": self.loop_hz,
                    }
                next_t += self.tick
                delay = next_t - time.perf_counter()
                if delay > 0:
                    time.sleep(delay)
                else:
                    next_t = time.perf_counter()
        except Exception:  # noqa: BLE001
            err = traceback.format_exc()
            self.log(err)
            self.events.put(("error", err))
        finally:
            try:
                self.output.apply(OutputState(), self.core.profile["virtual_pad"])
                self.output.close()
            except Exception:  # noqa: BLE001
                pass
            try:
                self.input.close()
            except Exception:  # noqa: BLE001
                pass
            if hi_res:
                hi_res()

    def _commands(self, now):
        while True:
            try:
                cmd, args = self.commands.get_nowait()
            except queue.Empty:
                return
            if cmd == "profile":
                self.core.set_profile(args[0])
            elif cmd == "run_macro":
                self.core.run_manual(args[0], now)
            elif cmd == "stop_macros":
                self.core.stop_all_macros()
            elif cmd == "pause":
                self.core.paused = bool(args[0])
                self.core.stop_all_macros()
            elif cmd == "record_start":
                self.core.start_recording(now)
            elif cmd == "record_stop":
                self.events.put(("recorded", self.core.stop_recording(now)))
            elif cmd == "select_device":
                self.input.select(args[0])
            elif cmd == "controller_map":
                self.input.set_map(args[0])
            elif cmd == "rumble":
                self.input.rumble(*args)
            elif cmd == "list_devices":
                self.events.put(("devices", self.input.list_devices()))


def _enable_hires_timer():
    """Sous Windows, passe le timer système à 1 ms (sinon sleep ≈ 15 ms)."""
    try:
        import ctypes
        winmm = ctypes.WinDLL("winmm")
        winmm.timeBeginPeriod(1)
        return lambda: winmm.timeEndPeriod(1)
    except Exception:  # noqa: BLE001
        return None
