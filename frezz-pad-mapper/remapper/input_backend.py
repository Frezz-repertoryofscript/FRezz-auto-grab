"""Lecture de la DualSense via pygame (SDL2, pilote HIDAPI PS5)."""

import os

from .constants import PHYS_BUTTONS, PHYS_AXES

# Disposition SDL2 / pygame pour une DualSense (USB ou Bluetooth) sous Windows.
# Modifiable via l'assistant de calibration si ta config est différente.
DEFAULT_MAP = {
    "buttons": {
        "CROSS": 0, "CIRCLE": 1, "SQUARE": 2, "TRIANGLE": 3,
        "CREATE": 4, "PS": 5, "OPTIONS": 6, "L3": 7, "R3": 8,
        "L1": 9, "R1": 10,
        "DPAD_UP": 11, "DPAD_DOWN": 12, "DPAD_LEFT": 13, "DPAD_RIGHT": 14,
        "TOUCHPAD": 15, "MUTE": 16,
    },
    "axes": {"LX": 0, "LY": 1, "RX": 2, "RY": 3, "L2": 4, "R2": 5},
    # Les gâchettes SDL vont de -1 (relâchée) à 1 (enfoncée)
    "trigger_min": -1.0,
    "use_hat": True,   # certaines configs donnent la croix directionnelle en "hat"
}


def _empty_state():
    return {
        "connected": False,
        "name": "",
        "buttons": {b: False for b in PHYS_BUTTONS},
        "axes": {a: 0.0 for a in PHYS_AXES},
        "raw": None,
        "events": [],
    }


class PygameInput:
    def __init__(self, controller_map=None, device_index=0):
        os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")
        # Indispensable : continuer à lire la manette quand le jeu a le focus
        os.environ["SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"] = "1"
        os.environ.setdefault("SDL_JOYSTICK_HIDAPI_PS5", "1")
        os.environ.setdefault("SDL_JOYSTICK_HIDAPI_PS5_RUMBLE", "1")
        import pygame
        self.pg = pygame
        pygame.display.init()   # requis pour la pompe à événements (aucune fenêtre créée)
        pygame.joystick.init()
        self.map = dict(DEFAULT_MAP)
        if controller_map:
            self.set_map(controller_map)
        self.wanted = device_index
        self.joy = None
        self.batt_tick = 0
        self.battery = ""
        self._open()

    def set_map(self, m):
        new = {
            "buttons": dict(DEFAULT_MAP["buttons"]),
            "axes": dict(DEFAULT_MAP["axes"]),
            "trigger_min": DEFAULT_MAP["trigger_min"],
            "use_hat": DEFAULT_MAP["use_hat"],
        }
        new["buttons"].update(m.get("buttons", {}))
        new["axes"].update(m.get("axes", {}))
        for k in ("trigger_min", "use_hat"):
            if k in m:
                new[k] = m[k]
        self.map = new

    def list_devices(self):
        js = self.pg.joystick
        return [(i, js.Joystick(i).get_name()) for i in range(js.get_count())]

    def select(self, index):
        self.wanted = int(index)
        self._open()

    def _open(self):
        js = self.pg.joystick
        self.joy = None
        n = js.get_count()
        if n == 0:
            return
        idx = self.wanted if 0 <= self.wanted < n else 0
        # Préférer une manette Sony si l'index demandé n'est pas valide
        if idx != self.wanted:
            for i in range(n):
                name = js.Joystick(i).get_name().lower()
                if "dualsense" in name or "ps5" in name or "wireless controller" in name:
                    idx = i
                    break
        self.joy = js.Joystick(idx)
        self.joy.init()

    def rumble(self, low=0.6, high=0.6, ms=300):
        if self.joy is not None:
            try:
                self.joy.rumble(low, high, int(ms))
            except Exception:  # noqa: BLE001
                pass

    def poll(self):
        pg = self.pg
        events = []
        for ev in pg.event.get():
            if ev.type == pg.JOYDEVICEADDED:
                events.append("Manette branchée")
                if self.joy is None:
                    self._open()
            elif ev.type == pg.JOYDEVICEREMOVED:
                events.append("Manette débranchée")
                self._open() if pg.joystick.get_count() else setattr(self, "joy", None)
        st = _empty_state()
        st["events"] = events
        j = self.joy
        if j is None:
            return st
        try:
            nb, na, nh = j.get_numbuttons(), j.get_numaxes(), j.get_numhats()
            raw_b = [bool(j.get_button(i)) for i in range(nb)]
            raw_a = [j.get_axis(i) for i in range(na)]
            raw_h = [j.get_hat(i) for i in range(nh)]
        except pg.error:
            self.joy = None
            return st
        st["connected"] = True
        st["name"] = j.get_name()
        st["raw"] = {"buttons": raw_b, "axes": raw_a, "hats": raw_h}
        for name, idx in self.map["buttons"].items():
            if idx is not None and 0 <= idx < nb:
                st["buttons"][name] = raw_b[idx]
        tmin = float(self.map["trigger_min"])
        for name, idx in self.map["axes"].items():
            if idx is None or not 0 <= idx < na:
                continue
            v = raw_a[idx]
            if name in ("L2", "R2"):
                v = (v - tmin) / (1.0 - tmin) if tmin < 1.0 else v
                v = min(max(v, 0.0), 1.0)
            st["axes"][name] = v
        if self.map["use_hat"] and nh:
            hx, hy = raw_h[0]
            b = st["buttons"]
            b["DPAD_LEFT"] |= hx < 0
            b["DPAD_RIGHT"] |= hx > 0
            b["DPAD_UP"] |= hy > 0
            b["DPAD_DOWN"] |= hy < 0
        self.batt_tick -= 1
        if self.batt_tick <= 0:
            self.batt_tick = 2000
            try:
                self.battery = j.get_power_level()
            except Exception:  # noqa: BLE001
                self.battery = ""
        st["battery"] = self.battery
        return st

    def close(self):
        try:
            self.pg.joystick.quit()
            self.pg.display.quit()
        except Exception:  # noqa: BLE001
            pass


class NullInput:
    """Aucune manette (mode démo / tests)."""

    def __init__(self, *_, **__):
        pass

    def poll(self):
        return _empty_state()

    def set_map(self, m):
        pass

    def select(self, i):
        pass

    def list_devices(self):
        return []

    def rumble(self, *a):
        pass

    def close(self):
        pass
