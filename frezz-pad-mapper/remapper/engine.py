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
from .realtime import MODES, DEFAULT_MODE, Sleeper, boost_thread

STICK_AXES = {"pad:LS": ("LX", "LY"), "pad:RS": ("RX", "RY")}
DIGITAL_STICK_KEYS = {
    "wasd": ("key:w", "key:s", "key:a", "key:d"),
    "zqsd": ("key:z", "key:s", "key:q", "key:d"),
    "arrows": ("key:up", "key:down", "key:left", "key:right"),
}
TRIGGER_TARGETS = {"pad:L2": "L2", "pad:R2": "R2"}
_NO_BUTTONS = {b: False for b in PHYS_BUTTONS}
_ZERO_AXES = {a: 0.0 for a in PHYS_AXES}


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
        self.targets = set(targets) if targets else set()
        self.axes = dict(axes) if axes else dict(_ZERO_AXES)
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
        self.profile = p = normalize_profile(profile)
        self.macros = {m["name"]: m for m in p["macros"]}
        # combos les plus longs d'abord : ils ont la priorité sur leurs sous-ensembles
        self.triggered = sorted(
            (m for m in p["macros"] if m["enabled"] and m["trigger"]),
            key=lambda m: -len(m["trigger"]),
        )
        self.chords = [tuple(m["trigger"]) for m in self.triggered]
        self.chords += [tuple(c) for c in p["hotkeys"].values() if c]
        # --- tables précalculées pour que le tick fasse le moins de travail possible
        multi = [frozenset(c) for c in self.chords if len(c) > 1]
        # pour chaque combo : les combos plus longs qui le contiennent (priorité)
        self._supers = {}
        for c in self.chords:
            fc = frozenset(c)
            self._supers[tuple(c)] = [tuple(x) for x in set(multi) if len(x) > len(fc) and fc < x]
        self._hotkeys = [(a, tuple(c)) for a, c in p["hotkeys"].items() if c]
        self._macro_trigs = [(m, tuple(m["trigger"]), ("trig", m["name"]), m["mode"] == "long")
                             for m in self.triggered]
        rows = []
        for b in PHYS_BUTTONS:
            target = p["buttons"].get(b, "none")
            turbo = p["turbo"].get(b)
            turbo = turbo if turbo and turbo["enabled"] else None
            kind, _, name = target.partition(":")
            analog = b in ("L2", "R2") and target in TRIGGER_TARGETS and turbo is None
            if target == "none" and turbo is None:
                continue
            rows.append((b, target, kind, name, turbo, analog))
        self._rows = rows
        self._analog = [(side, TRIGGER_TARGETS[p["buttons"][side]], p["triggers"][side])
                        for side in ("L2", "R2")
                        if p["buttons"].get(side) in TRIGGER_TARGETS and not
                        (p["turbo"].get(side) or {}).get("enabled")]
        self._thr = ((p["triggers"]["L2"]["threshold"]), (p["triggers"]["R2"]["threshold"]))
        self._sticks = [(ax, ay, p["sticks"][side], p["sticks"][side].get("target", "none"))
                        for side, (ax, ay) in STICKS.items()
                        if p["sticks"][side].get("target", "none") != "none"]
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
    def _shadowed(self, chord, cur):
        for c in self._supers.get(chord, ()):
            if all(cur[b] for b in c):
                return True
        return False

    def process(self, buttons, axes, now):
        dt = 0.0 if self.last_now is None else clamp(now - self.last_now, 0.0, 0.1)
        self.last_now = now
        cur = dict(_NO_BUTTONS)
        for b, v in buttons.items():
            if v:
                cur[b] = True
        ax = dict(_ZERO_AXES)
        ax.update(axes)
        if ax["L2"] > self._thr[0]:
            cur["L2"] = True
        if ax["R2"] > self._thr[1]:
            cur["R2"] = True
        prev = self.prev
        press_time = self.press_time
        for b, v in cur.items():
            if v and not prev.get(b):
                press_time[b] = now

        out = OutputState()
        actions = []
        blocked = set()

        # Raccourcis globaux (fonctionnent même en pause)
        chord_prev = self.chord_prev
        for action, chord in self._hotkeys:
            held = all(cur[b] for b in chord) and not self._shadowed(chord, cur)
            key = ("hotkey", action)
            if held and not chord_prev.get(key):
                actions.append(action)
            chord_prev[key] = held
            if held:
                blocked.update(chord)
        if actions:
            if "toggle_pause" in actions:
                self.paused = not self.paused
                self.stop_all_macros()
            if "stop_macros" in actions:
                self.stop_all_macros()

        if self.paused:
            self.prev = cur
            return out, actions

        # Macros déclenchées par bouton / combo
        trig = self.trig
        for m, chord, key, is_long in self._macro_trigs:
            held = all(cur[b] for b in chord) and not self._shadowed(chord, cur)
            st = trig.get(key)
            # rien n'a changé : on saute (sauf appui long qui dépend du temps)
            if st is None or st["prev"] != held or (is_long and held):
                self._handle_trigger(m, key, held, now)
            if held and m["block_trigger"]:
                blocked.update(chord)

        # Remappage bouton par bouton (seulement les boutons utiles)
        rec_targets = set()
        for b, target, kind, name, turbo, analog in self._rows:
            pressed = cur[b] and b not in blocked
            if turbo is not None:
                pressed = self._turbo(b, turbo, pressed, now)
            if kind == "macro":
                m = self.macros.get(name)
                if m:
                    self._handle_trigger(m, ("btn", b, name), pressed, now)
                continue
            if not pressed or analog:
                continue
            if kind == "action":
                if not prev.get(b):
                    actions.append(name)
                continue
            if target != "none":
                rec_targets.add(target)

        # Gâchettes analogiques
        oax = out.axes
        for side, a, cfg in self._analog:
            if side not in blocked:
                v = process_trigger(ax[side], cfg)
                if v > oax[a]:
                    oax[a] = v

        # Sticks
        mx = my = 0.0
        for sx, sy, cfg, tgt in self._sticks:
            x, y = process_stick(ax[sx], ax[sy], cfg)
            if x == 0.0 and y == 0.0:
                continue
            if tgt in STICK_AXES:
                ox, oy = STICK_AXES[tgt]
                oax[ox] = clamp(oax[ox] + x)
                oax[oy] = clamp(oax[oy] + y)
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
            self._record(rec_targets, oax, now)
        out.targets = rec_targets

        # Macros en cours : leurs boutons/axes s'ajoutent (et priment pour les axes)
        if self.running:
            for name in list(self.running):
                inst = self.running[name]
                if not inst.update(now):
                    del self.running[name]
                    continue
                out.targets |= inst.held
                oax.update(inst.axes)
        if self.manual:
            alive = []
            for inst in self.manual:
                if inst.update(now):
                    out.targets |= inst.held
                    oax.update(inst.axes)
                    alive.append(inst)
            self.manual = alive

        self.prev = cur
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

    SNAPSHOT_EVERY = 0.008   # l'interface n'a pas besoin de plus de ~120 images/s

    def __init__(self, input_factory, output_factory, mode=DEFAULT_MODE, log=print, tick_hz=None):
        self.input_factory = input_factory
        self.output_factory = output_factory
        self.mode = mode if mode in MODES else DEFAULT_MODE
        hz = tick_hz or MODES[self.mode]["hz"]
        self.tick = 1.0 / max(int(hz), 60)
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
        self.snap_queue = None     # utilisé quand le moteur tourne dans un processus séparé
        self.stats = {"hz": 0.0, "proc_us": 0.0, "late_ms": 0.0, "max_us": 0.0}

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
        self.log(f"Mode : {MODES[self.mode]['label']}")
        undo_thread = boost_thread(self.log)
        sleeper = Sleeper(MODES[self.mode]["spin_us"])
        perf = time.perf_counter
        tick = self.tick
        core, inp, outp, cmds = self.core, self.input, self.output, self.commands
        next_t = perf()
        snap_t = 0.0
        count, count_t, proc_sum, proc_max, late_max = 0, next_t, 0.0, 0.0, 0.0
        state = None
        out = OutputState()
        try:
            while self.alive:
                t0 = perf()
                late = t0 - next_t
                if late > late_max:
                    late_max = late
                if not cmds.empty():
                    self._commands(t0)
                state = inp.poll()
                if state["events"]:
                    for ev in state["events"]:
                        self.log(ev)
                        self.events.put(("device", ev))
                out, actions = core.process(state["buttons"], state["axes"], t0)
                if not state["connected"]:
                    out = OutputState()
                outp.apply(out, core.profile["virtual_pad"])
                for a in actions:
                    self.events.put(("action", a))
                t1 = perf()
                d = t1 - t0
                proc_sum += d
                if d > proc_max:
                    proc_max = d
                count += 1
                if t1 - count_t >= 1.0:
                    self.stats = {"hz": count / (t1 - count_t), "proc_us": proc_sum / count * 1e6,
                                  "max_us": proc_max * 1e6, "late_ms": max(late_max, 0.0) * 1e3}
                    count, count_t, proc_sum, proc_max, late_max = 0, t1, 0.0, 0.0, 0.0
                if t1 - snap_t >= self.SNAPSHOT_EVERY:
                    snap_t = t1
                    self._publish(state, out)
                next_t += tick
                if next_t < t1 - 0.05:   # gros retard (mise en veille…) : on se recale
                    next_t = t1
                sleeper.until(next_t)
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
            sleeper.close()
            undo_thread()

    def _publish(self, state, out):
        snap = {
            "connected": state["connected"],
            "device": state.get("name", ""),
            "battery": state.get("battery", ""),
            "buttons": self.core.prev,          # remplacé (pas modifié) à chaque tick
            "axes": state["axes"],
            "raw": state.get("raw"),
            "out_targets": out.targets,
            "out_axes": out.axes,
            "running": self.core.running_info(),
            "paused": self.core.paused,
            "recording": self.core.recording is not None,
            "profile": self.core.profile["name"],
            "hz": self.stats["hz"],
            "stats": self.stats,
            "mode": self.mode,
        }
        if self.snap_queue is not None:
            try:
                self.snap_queue.put_nowait(snap)
            except Exception:  # noqa: BLE001  (file pleine : l'interface lira la suivante)
                pass
            return
        with self.lock:
            self._snap = snap

    def _commands(self, now):
        while True:
            try:
                cmd, args = self.commands.get_nowait()
            except queue.Empty:
                return
            if cmd == "quit":
                self.alive = False
            elif cmd == "profile":
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
            elif cmd == "raw":
                self.input.want_raw = bool(args[0])
            elif cmd == "list_devices":
                self.events.put(("devices", self.input.list_devices()))
