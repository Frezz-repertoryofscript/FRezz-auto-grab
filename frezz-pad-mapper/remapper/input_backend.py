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
        # On lit l'état directement : inutile de remplir la file avec chaque mouvement d'axe
        pygame.event.set_blocked(None)
        pygame.event.set_allowed([pygame.JOYDEVICEADDED, pygame.JOYDEVICEREMOVED])
        self.want_raw = False
        self.joy = None
        self.set_map(controller_map or {})
        self.wanted = device_index
        self.joy = None
        self.batt_tick = 0
        self.battery = ""
        self.name = ""
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
        self._compile()

    def _compile(self):
        """Précalcule les index à lire pour que poll() soit minimal."""
        j = getattr(self, "joy", None)
        nb = j.get_numbuttons() if j else 64
        na = j.get_numaxes() if j else 16
        self.nh = j.get_numhats() if j else 0
        self.btn_idx = [(n, i) for n, i in self.map["buttons"].items() if i is not None and 0 <= i < nb]
        self.ax_idx = [(n, i) for n, i in self.map["axes"].items()
                       if i is not None and 0 <= i < na and n not in ("L2", "R2")]
        self.trig_idx = [(n, i) for n, i in self.map["axes"].items()
                         if i is not None and 0 <= i < na and n in ("L2", "R2")]
        tmin = float(self.map["trigger_min"])
        self.t_off, self.t_scale = tmin, (1.0 / (1.0 - tmin) if tmin < 1.0 else 1.0)
        self.use_hat = bool(self.map["use_hat"]) and self.nh > 0

    def list_devices(self):
        js = self.pg.joystick
        return [(i, js.Joystick(i).get_name()) for i in range(js.get_count())]

    def select(self, index):
        self.wanted = int(index)
        self._open()

    def _open(self):
        js = self.pg.joystick
        self.joy = None
        self.batt_tick = 0
        n = js.get_count()
        if n == 0:
            self._compile()
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
        self._compile()

    def rumble(self, low=0.6, high=0.6, ms=300):
        if self.joy is not None:
            try:
                self.joy.rumble(low, high, int(ms))
            except Exception:  # noqa: BLE001
                pass

    def poll(self):
        pg = self.pg
        events = []
        for ev in pg.event.get():   # met aussi à jour l'état de la manette (SDL_PumpEvents)
            if ev.type == pg.JOYDEVICEADDED:
                events.append("Manette branchée")
                if self.joy is None:
                    self._open()
            elif ev.type == pg.JOYDEVICEREMOVED:
                events.append("Manette débranchée")
                if pg.joystick.get_count():
                    self._open()
                else:
                    self.joy = None
        j = self.joy
        if j is None:
            st = _empty_state()
            st["events"] = events
            return st
        try:
            gb, ga = j.get_button, j.get_axis
            buttons = {n: gb(i) == 1 for n, i in self.btn_idx}
            axes = {n: ga(i) for n, i in self.ax_idx}
            off, scale = self.t_off, self.t_scale
            for n, i in self.trig_idx:
                v = (ga(i) - off) * scale
                axes[n] = 0.0 if v < 0.0 else 1.0 if v > 1.0 else v
            if self.use_hat:
                hx, hy = j.get_hat(0)
                if hx or hy:
                    if hx < 0:
                        buttons["DPAD_LEFT"] = True
                    elif hx > 0:
                        buttons["DPAD_RIGHT"] = True
                    if hy > 0:
                        buttons["DPAD_UP"] = True
                    elif hy < 0:
                        buttons["DPAD_DOWN"] = True
            raw = None
            if self.want_raw:
                raw = {"buttons": [bool(gb(i)) for i in range(j.get_numbuttons())],
                       "axes": [ga(i) for i in range(j.get_numaxes())],
                       "hats": [j.get_hat(i) for i in range(self.nh)]}
        except pg.error:
            self.joy = None
            st = _empty_state()
            st["events"] = events
            return st
        self.batt_tick -= 1
        if self.batt_tick <= 0:
            self.batt_tick = 5000
            try:
                self.battery = j.get_power_level()
            except Exception:  # noqa: BLE001
                self.battery = ""
            self.name = j.get_name()
        for a in ("LX", "LY", "RX", "RY", "L2", "R2"):
            axes.setdefault(a, 0.0)
        return {"connected": True, "name": self.name, "buttons": buttons, "axes": axes,
                "raw": raw, "events": events, "battery": self.battery}

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

    want_raw = False

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
