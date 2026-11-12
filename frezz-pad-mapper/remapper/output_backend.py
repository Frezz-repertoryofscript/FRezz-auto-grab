"""Sorties : manette virtuelle (ViGEmBus via vgamepad) + clavier/souris (SendInput)."""

import sys

from .constants import PHYS_AXES


# ============================================================ manette virtuelle
class VirtualPad:
    """Xbox 360 ou DualShock 4 virtuelle via ViGEmBus."""

    def __init__(self):
        import vgamepad as vg
        self.vg = vg
        self.kind = None
        self.pad = None
        self.last = None

    def _ensure(self, kind):
        if kind == self.kind and self.pad is not None:
            return
        vg = self.vg
        self.close()
        self.pad = vg.VDS4Gamepad() if kind == "ds4" else vg.VX360Gamepad()
        self.kind = kind
        self.last = None
        if kind == "ds4":
            B, S = vg.DS4_BUTTONS, vg.DS4_SPECIAL_BUTTONS
            self.bmap = {
                "CROSS": B.DS4_BUTTON_CROSS, "CIRCLE": B.DS4_BUTTON_CIRCLE,
                "SQUARE": B.DS4_BUTTON_SQUARE, "TRIANGLE": B.DS4_BUTTON_TRIANGLE,
                "L1": B.DS4_BUTTON_SHOULDER_LEFT, "R1": B.DS4_BUTTON_SHOULDER_RIGHT,
                "L3": B.DS4_BUTTON_THUMB_LEFT, "R3": B.DS4_BUTTON_THUMB_RIGHT,
                "CREATE": B.DS4_BUTTON_SHARE, "OPTIONS": B.DS4_BUTTON_OPTIONS,
            }
            self.smap = {"PS": S.DS4_SPECIAL_BUTTON_PS, "TOUCHPAD": S.DS4_SPECIAL_BUTTON_TOUCHPAD}
        else:
            X = vg.XUSB_BUTTON
            self.bmap = {
                "CROSS": X.XUSB_GAMEPAD_A, "CIRCLE": X.XUSB_GAMEPAD_B,
                "SQUARE": X.XUSB_GAMEPAD_X, "TRIANGLE": X.XUSB_GAMEPAD_Y,
                "L1": X.XUSB_GAMEPAD_LEFT_SHOULDER, "R1": X.XUSB_GAMEPAD_RIGHT_SHOULDER,
                "L3": X.XUSB_GAMEPAD_LEFT_THUMB, "R3": X.XUSB_GAMEPAD_RIGHT_THUMB,
                "CREATE": X.XUSB_GAMEPAD_BACK, "OPTIONS": X.XUSB_GAMEPAD_START,
                "PS": X.XUSB_GAMEPAD_GUIDE, "TOUCHPAD": X.XUSB_GAMEPAD_BACK,
                "DPAD_UP": X.XUSB_GAMEPAD_DPAD_UP, "DPAD_DOWN": X.XUSB_GAMEPAD_DPAD_DOWN,
                "DPAD_LEFT": X.XUSB_GAMEPAD_DPAD_LEFT, "DPAD_RIGHT": X.XUSB_GAMEPAD_DPAD_RIGHT,
            }
            self.smap = {}

    def apply(self, buttons, axes, kind):
        self._ensure(kind)
        l2 = max(axes.get("L2", 0.0), 1.0 if "L2" in buttons else 0.0)
        r2 = max(axes.get("R2", 0.0), 1.0 if "R2" in buttons else 0.0)
        key = (frozenset(buttons), round(axes["LX"], 3), round(axes["LY"], 3),
               round(axes["RX"], 3), round(axes["RY"], 3), round(l2, 3), round(r2, 3))
        if key == self.last:
            return
        self.last = key
        pad = self.pad
        pad.reset()
        for b in buttons:
            if b in self.bmap:
                pad.press_button(button=self.bmap[b])
            elif b in self.smap:
                pad.press_special_button(special_button=self.smap[b])
        if self.kind == "ds4":
            self._ds4_dpad(buttons)
            if l2 > 0.05:
                pad.press_button(button=self.vg.DS4_BUTTONS.DS4_BUTTON_TRIGGER_LEFT)
            if r2 > 0.05:
                pad.press_button(button=self.vg.DS4_BUTTONS.DS4_BUTTON_TRIGGER_RIGHT)
            # DS4 : axe Y vers le bas positif, comme la DualSense
            pad.left_joystick_float(x_value_float=axes["LX"], y_value_float=axes["LY"])
            pad.right_joystick_float(x_value_float=axes["RX"], y_value_float=axes["RY"])
        else:
            # XInput : axe Y vers le haut positif -> on inverse
            pad.left_joystick_float(x_value_float=axes["LX"], y_value_float=-axes["LY"])
            pad.right_joystick_float(x_value_float=axes["RX"], y_value_float=-axes["RY"])
        pad.left_trigger_float(value_float=l2)
        pad.right_trigger_float(value_float=r2)
        pad.update()

    def _ds4_dpad(self, b):
        D = self.vg.DS4_DPAD_DIRECTIONS
        u, d, l, r = ("DPAD_UP" in b, "DPAD_DOWN" in b, "DPAD_LEFT" in b, "DPAD_RIGHT" in b)
        if u and r:
            v = D.DS4_BUTTON_DPAD_NORTHEAST
        elif u and l:
            v = D.DS4_BUTTON_DPAD_NORTHWEST
        elif d and r:
            v = D.DS4_BUTTON_DPAD_SOUTHEAST
        elif d and l:
            v = D.DS4_BUTTON_DPAD_SOUTHWEST
        elif u:
            v = D.DS4_BUTTON_DPAD_NORTH
        elif d:
            v = D.DS4_BUTTON_DPAD_SOUTH
        elif l:
            v = D.DS4_BUTTON_DPAD_WEST
        elif r:
            v = D.DS4_BUTTON_DPAD_EAST
        else:
            v = D.DS4_BUTTON_DPAD_NONE
        self.pad.directional_pad(direction=v)

    def close(self):
        if self.pad is not None:
            try:
                self.pad.reset()
                self.pad.update()
            except Exception:  # noqa: BLE001
                pass
            self.pad = None
            self.kind = None


# ================================================== clavier / souris Windows
# Scancodes "set 1" ; (code, étendu)
SCANCODES = {
    **{c: (code, False) for c, code in zip("1234567890", range(0x02, 0x0C))},
    **{c: (code, False) for c, code in zip("qwertyuiop", range(0x10, 0x1A))},
    **{c: (code, False) for c, code in zip("asdfghjkl", range(0x1E, 0x27))},
    **{c: (code, False) for c, code in zip("zxcvbnm", range(0x2C, 0x33))},
    **{f"f{i}": (0x3A + i, False) for i in range(1, 11)},
    "f11": (0x57, False), "f12": (0x58, False),
    "esc": (0x01, False), "minus": (0x0C, False), "equal": (0x0D, False),
    "backspace": (0x0E, False), "tab": (0x0F, False), "lbracket": (0x1A, False),
    "rbracket": (0x1B, False), "enter": (0x1C, False), "ctrl": (0x1D, False),
    "semicolon": (0x27, False), "quote": (0x28, False), "backquote": (0x29, False),
    "shift": (0x2A, False), "backslash": (0x2B, False), "comma": (0x33, False),
    "period": (0x34, False), "slash": (0x35, False), "rshift": (0x36, False),
    "nummul": (0x37, False), "alt": (0x38, False), "space": (0x39, False),
    "capslock": (0x3A, False),
    "num7": (0x47, False), "num8": (0x48, False), "num9": (0x49, False), "numminus": (0x4A, False),
    "num4": (0x4B, False), "num5": (0x4C, False), "num6": (0x4D, False), "numplus": (0x4E, False),
    "num1": (0x4F, False), "num2": (0x50, False), "num3": (0x51, False), "num0": (0x52, False),
    "numdot": (0x53, False),
    "numenter": (0x1C, True), "rctrl": (0x1D, True), "numdiv": (0x35, True), "ralt": (0x38, True),
    "home": (0x47, True), "up": (0x48, True), "pageup": (0x49, True), "left": (0x4B, True),
    "right": (0x4D, True), "end": (0x4F, True), "down": (0x50, True), "pagedown": (0x51, True),
    "insert": (0x52, True), "delete": (0x53, True),
}


class WinSendInput:
    """Clavier en scancodes (compatible DirectInput / RawInput) et souris relative."""

    def __init__(self):
        import ctypes
        from ctypes import wintypes
        self.ct = ctypes
        ULONG_PTR = ctypes.c_size_t

        class KEYBDINPUT(ctypes.Structure):
            _fields_ = [("wVk", wintypes.WORD), ("wScan", wintypes.WORD), ("dwFlags", wintypes.DWORD),
                        ("time", wintypes.DWORD), ("dwExtraInfo", ULONG_PTR)]

        class MOUSEINPUT(ctypes.Structure):
            _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG), ("mouseData", wintypes.DWORD),
                        ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD), ("dwExtraInfo", ULONG_PTR)]

        class HARDWAREINPUT(ctypes.Structure):
            _fields_ = [("uMsg", wintypes.DWORD), ("wParamL", wintypes.WORD), ("wParamH", wintypes.WORD)]

        class _U(ctypes.Union):
            _fields_ = [("ki", KEYBDINPUT), ("mi", MOUSEINPUT), ("hi", HARDWAREINPUT)]

        class INPUT(ctypes.Structure):
            _fields_ = [("type", wintypes.DWORD), ("u", _U)]

        self.INPUT, self.KEYBDINPUT, self.MOUSEINPUT = INPUT, KEYBDINPUT, MOUSEINPUT
        self.user32 = ctypes.WinDLL("user32", use_last_error=True)

    def _send(self, inp):
        self.user32.SendInput(1, self.ct.byref(inp), self.ct.sizeof(inp))

    def key(self, name, down):
        if len(name) == 1 and name.isalpha():
            # Lettres : on respecte la disposition du clavier (AZERTY, QWERTY...)
            code, ext = self.user32.MapVirtualKeyW(ord(name.upper()), 0), False
            if not code:
                return
        elif name in SCANCODES:
            code, ext = SCANCODES[name]
        else:
            return
        flags = 0x0008 | (0 if down else 0x0002) | (0x0001 if ext else 0)
        inp = self.INPUT(type=1)
        inp.u.ki = self.KEYBDINPUT(0, code, flags, 0, 0)
        self._send(inp)

    MOUSE_FLAGS = {
        "left": (0x0002, 0x0004, 0), "right": (0x0008, 0x0010, 0), "middle": (0x0020, 0x0040, 0),
        "x1": (0x0080, 0x0100, 1), "x2": (0x0080, 0x0100, 2),
    }

    def mouse_button(self, name, down):
        if name not in self.MOUSE_FLAGS:
            return
        d, u, data = self.MOUSE_FLAGS[name]
        inp = self.INPUT(type=0)
        inp.u.mi = self.MOUSEINPUT(0, 0, data, d if down else u, 0, 0)
        self._send(inp)

    def mouse_move(self, dx, dy):
        inp = self.INPUT(type=0)
        inp.u.mi = self.MOUSEINPUT(int(dx), int(dy), 0, 0x0001, 0, 0)
        self._send(inp)

    def wheel(self, up):
        inp = self.INPUT(type=0)
        inp.u.mi = self.MOUSEINPUT(0, 0, 120 if up else (-120 & 0xFFFFFFFF), 0x0800, 0, 0)
        self._send(inp)


class PynputKM:
    """Repli multi-plateforme (Linux / macOS)."""

    def __init__(self):
        from pynput import keyboard, mouse
        self.kb, self.ms = keyboard.Controller(), mouse.Controller()
        K = keyboard.Key
        self.special = {
            "space": K.space, "enter": K.enter, "esc": K.esc, "tab": K.tab, "backspace": K.backspace,
            "shift": K.shift, "rshift": K.shift_r, "ctrl": K.ctrl, "rctrl": K.ctrl_r,
            "alt": K.alt, "ralt": K.alt_r, "up": K.up, "down": K.down, "left": K.left, "right": K.right,
            "capslock": K.caps_lock, "delete": K.delete, "home": K.home, "end": K.end,
            "pageup": K.page_up, "pagedown": K.page_down, "insert": K.insert,
            **{f"f{i}": getattr(K, f"f{i}") for i in range(1, 13)},
        }
        self.chars = {"minus": "-", "equal": "=", "lbracket": "[", "rbracket": "]", "semicolon": ";",
                      "quote": "'", "backquote": "`", "backslash": "\\", "comma": ",", "period": ".",
                      "slash": "/"}
        B = mouse.Button
        self.buttons = {"left": B.left, "right": B.right, "middle": B.middle}

    def key(self, name, down):
        k = self.special.get(name) or self.chars.get(name)
        if k is None:
            if name.startswith("num") and name[3:].isdigit():
                k = name[3:]
            elif len(name) == 1:
                k = name
            else:
                return
        (self.kb.press if down else self.kb.release)(k)

    def mouse_button(self, name, down):
        b = self.buttons.get(name)
        if b is not None:
            (self.ms.press if down else self.ms.release)(b)

    def mouse_move(self, dx, dy):
        self.ms.move(int(dx), int(dy))

    def wheel(self, up):
        self.ms.scroll(0, 1 if up else -1)


# ==================================================================== gestion
class OutputManager:
    """Applique un OutputState : ne transmet que les changements."""

    def __init__(self, enable_pad=True, enable_km=True, log=print):
        self.log = log
        self.pad = None
        self.km = None
        self.notes = []
        if enable_pad:
            try:
                self.pad = VirtualPad()
            except Exception as e:  # noqa: BLE001
                self.notes.append(f"manette virtuelle indisponible ({e}) — installe vgamepad + ViGEmBus")
        if enable_km:
            try:
                self.km = WinSendInput() if sys.platform == "win32" else PynputKM()
            except Exception as e:  # noqa: BLE001
                self.notes.append(f"clavier/souris indisponible ({e})")
        self.prev = set()
        self.rem = [0.0, 0.0]

    def describe(self):
        parts = []
        parts.append("manette virtuelle OK" if self.pad else "pas de manette virtuelle")
        parts.append("clavier/souris OK" if self.km else "pas de clavier/souris")
        return ", ".join(parts + self.notes)

    def apply(self, out, pad_kind):
        targets = out.targets
        if self.km:
            for t in self.prev - targets:
                self._km(t, False)
            for t in targets - self.prev:
                self._km(t, True)
            dx, dy = out.mouse
            self.rem[0] += dx
            self.rem[1] += dy
            ix, iy = int(self.rem[0]), int(self.rem[1])
            if ix or iy:
                self.rem[0] -= ix
                self.rem[1] -= iy
                self.km.mouse_move(ix, iy)
        self.prev = set(targets)
        if self.pad:
            buttons = {t[4:] for t in targets if t.startswith("pad:")}
            axes = {a: out.axes.get(a, 0.0) for a in PHYS_AXES}
            self.pad.apply(buttons, axes, pad_kind)

    def _km(self, target, down):
        kind, _, name = target.partition(":")
        if kind == "key":
            self.km.key(name, down)
        elif kind == "mouse":
            self.km.mouse_button(name, down)
        elif kind == "wheel" and down:
            self.km.wheel(name == "up")

    def close(self):
        if self.km:
            for t in self.prev:
                self._km(t, False)
        self.prev = set()
        if self.pad:
            self.pad.close()


class NullOutput:
    def describe(self):
        return "sortie désactivée (mode test)"

    def apply(self, out, kind):
        pass

    def close(self):
        pass
