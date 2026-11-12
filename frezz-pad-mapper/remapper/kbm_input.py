"""Clavier / souris en ENTRÉE : déclencheurs de macros, raccourcis, enregistrement.

Sous Windows : hooks globaux bas niveau (WH_KEYBOARD_LL / WH_MOUSE_LL) dans un thread
dédié. Les événements injectés (dont ceux envoyés par l'appli elle-même) sont ignorés,
une macro ne peut donc jamais se redéclencher toute seule.

Les entrées portent les mêmes noms que les sorties : "key:f", "key:shift",
"mouse:left", "mouse:x1", "wheel:up"...
"""

import sys
import threading
import time

WHEEL_PULSE = 0.05   # durée pendant laquelle un cran de molette compte comme « appuyé »


def kbm_parts(chord):
    return [b for b in chord if ":" in b]


def pad_parts(chord):
    return [b for b in chord if ":" not in b]


class NullKbm:
    available = False

    def pressed(self, now):
        return ()

    def configure(self, need, chords, block):
        pass

    def set_pad(self, pad_pressed):
        pass

    def close(self):
        pass


class WinKbmHook:
    """Hooks bas niveau Windows, lancés seulement quand le profil en a besoin."""

    available = True

    def __init__(self, log=print):
        self.log = log
        self.lock = threading.Lock()
        self.down = set()           # entrées physiques actuellement enfoncées
        self.pulses = {}            # molette : nom -> fin du pulse
        self.blocked_down = set()   # appuis bloqués (on bloquera aussi leur relâchement)
        self.chords = []            # [(kbm frozenset, pad frozenset)] dont il faut bloquer l'entrée
        self.pad_pressed = frozenset()
        self.thread = None
        self.thread_id = None
        self.need = False
        self._names = self._build_names()

    # ------------------------------------------------------------------ API
    def configure(self, need, chords, block):
        """need : installer les hooks ; chords : combos à bloquer (kbm, pad)."""
        with self.lock:
            self.chords = [(frozenset(kbm_parts(c)), frozenset(pad_parts(c))) for c in block]
        if need and not self.thread:
            self._start()
        elif not need and self.thread:
            self._stop()

    def set_pad(self, pad_pressed):
        self.pad_pressed = pad_pressed

    def pressed(self, now):
        with self.lock:
            if self.pulses:
                for k in [k for k, t in self.pulses.items() if t < now]:
                    del self.pulses[k]
                return self.down | set(self.pulses)
            return set(self.down) if self.down else ()

    def close(self):
        self._stop()

    # -------------------------------------------------------------- interne
    @staticmethod
    def _build_names():
        from .output_backend import SCANCODES
        rev = {v: k for k, v in SCANCODES.items() if len(k) > 1 or k.isdigit()}
        return rev

    def _key_name(self, vk, scan, ext):
        if 0x41 <= vk <= 0x5A:
            return "key:" + chr(vk).lower()      # lettres : selon la disposition (AZERTY…)
        if 0x30 <= vk <= 0x39:
            return "key:" + chr(vk)
        name = self._names.get((scan, ext))
        if name is None and vk in (0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5):
            name = {0xA0: "shift", 0xA1: "rshift", 0xA2: "ctrl", 0xA3: "rctrl",
                    0xA4: "alt", 0xA5: "ralt"}[vk]
        return "key:" + name if name else None

    def _should_block(self, name):
        for kbm, pad in self.chords:
            if name in kbm and pad <= self.pad_pressed and all(k == name or k in self.down for k in kbm):
                return True
        return False

    def _event(self, name, is_down):
        """Retourne True si l'événement doit être bloqué (pas transmis au jeu)."""
        with self.lock:
            if is_down:
                self.down.add(name)
                if name in self.blocked_down or self._should_block(name):
                    self.blocked_down.add(name)
                    return True
                return False
            self.down.discard(name)
            if name in self.blocked_down:
                self.blocked_down.discard(name)
                return True
            return False

    def _start(self):
        ready = threading.Event()
        self.thread = threading.Thread(target=self._run, args=(ready,), name="kbm-hook", daemon=True)
        self.thread.start()
        ready.wait(2)

    def _stop(self):
        if self.thread and self.thread_id:
            import ctypes
            ctypes.WinDLL("user32").PostThreadMessageW(self.thread_id, 0x0012, 0, 0)  # WM_QUIT
            self.thread.join(timeout=2)
        self.thread = None
        self.thread_id = None
        with self.lock:
            self.down.clear()
            self.pulses.clear()
            self.blocked_down.clear()

    def _run(self, ready):
        import ctypes
        from ctypes import wintypes
        user32 = ctypes.WinDLL("user32", use_last_error=True)
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        LRESULT = ctypes.c_ssize_t
        HOOKPROC = ctypes.WINFUNCTYPE(LRESULT, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM)

        class KBDLL(ctypes.Structure):
            _fields_ = [("vkCode", wintypes.DWORD), ("scanCode", wintypes.DWORD), ("flags", wintypes.DWORD),
                        ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t)]

        class MSLL(ctypes.Structure):
            _fields_ = [("pt", wintypes.POINT), ("mouseData", wintypes.DWORD), ("flags", wintypes.DWORD),
                        ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t)]

        user32.SetWindowsHookExW.argtypes = [ctypes.c_int, HOOKPROC, wintypes.HINSTANCE, wintypes.DWORD]
        user32.SetWindowsHookExW.restype = wintypes.HHOOK
        user32.CallNextHookEx.argtypes = [wintypes.HHOOK, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM]
        user32.CallNextHookEx.restype = LRESULT
        user32.UnhookWindowsHookEx.argtypes = [wintypes.HHOOK]
        user32.GetMessageW.argtypes = [ctypes.POINTER(wintypes.MSG), wintypes.HWND, wintypes.UINT, wintypes.UINT]
        k32.GetModuleHandleW.restype = wintypes.HMODULE
        k32.GetModuleHandleW.argtypes = [wintypes.LPCWSTR]

        KEY_DOWN = (0x0100, 0x0104)   # WM_KEYDOWN, WM_SYSKEYDOWN
        KEY_UP = (0x0101, 0x0105)
        MOUSE = {0x0201: ("mouse:left", True), 0x0202: ("mouse:left", False),
                 0x0204: ("mouse:right", True), 0x0205: ("mouse:right", False),
                 0x0207: ("mouse:middle", True), 0x0208: ("mouse:middle", False)}

        def kb_proc(n, wparam, lparam):
            if n == 0:
                info = ctypes.cast(lparam, ctypes.POINTER(KBDLL)).contents
                if not info.flags & 0x10:   # LLKHF_INJECTED : on ignore nos propres envois
                    name = self._key_name(info.vkCode, info.scanCode, bool(info.flags & 0x01))
                    if name and (wparam in KEY_DOWN or wparam in KEY_UP):
                        if self._event(name, wparam in KEY_DOWN):
                            return 1
            return user32.CallNextHookEx(None, n, wparam, lparam)

        def ms_proc(n, wparam, lparam):
            if n == 0 and wparam != 0x0200:   # WM_MOUSEMOVE : on laisse passer tout de suite
                info = ctypes.cast(lparam, ctypes.POINTER(MSLL)).contents
                if not info.flags & 0x01:      # LLMHF_INJECTED
                    if wparam in MOUSE:
                        name, down = MOUSE[wparam]
                        if self._event(name, down):
                            return 1
                    elif wparam in (0x020B, 0x020C):   # WM_XBUTTONDOWN / UP
                        name = "mouse:x1" if (info.mouseData >> 16) == 1 else "mouse:x2"
                        if self._event(name, wparam == 0x020B):
                            return 1
                    elif wparam == 0x020A:              # WM_MOUSEWHEEL
                        delta = ctypes.c_short(info.mouseData >> 16).value
                        name = "wheel:up" if delta > 0 else "wheel:down"
                        with self.lock:
                            self.pulses[name] = time.perf_counter() + WHEEL_PULSE
                            block = self._should_block(name)
                        if block:
                            return 1
            return user32.CallNextHookEx(None, n, wparam, lparam)

        self._kb_cb, self._ms_cb = HOOKPROC(kb_proc), HOOKPROC(ms_proc)   # garder les références
        hmod = k32.GetModuleHandleW(None)
        hk = user32.SetWindowsHookExW(13, self._kb_cb, hmod, 0)   # WH_KEYBOARD_LL
        hm = user32.SetWindowsHookExW(14, self._ms_cb, hmod, 0)   # WH_MOUSE_LL
        self.thread_id = k32.GetCurrentThreadId()
        if hk and hm:
            self.log("Clavier / souris : écoute activée")
        else:
            self.log(f"Clavier / souris : hooks refusés (erreur {ctypes.get_last_error()})")
        ready.set()
        msg = wintypes.MSG()
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))
        for h in (hk, hm):
            if h:
                user32.UnhookWindowsHookEx(h)


def make_kbm(log=print):
    if sys.platform == "win32":
        try:
            return WinKbmHook(log)
        except Exception as e:  # noqa: BLE001
            log(f"Clavier / souris en entrée indisponible : {e}")
    return NullKbm()
