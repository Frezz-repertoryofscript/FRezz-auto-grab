"""Optimisations temps réel : timer haute résolution, priorités, anti-bridage Windows.

Modes de performance de la boucle :
    eco      500 Hz   sleep classique                    CPU minimal
    rapide  1000 Hz   timer haute résolution              recommandé
    ultra   2000 Hz   timer HR + attente active finale    ~1 ms de CPU en plus
    extreme 8000 Hz   attente active pure                 1 cœur à 100 %
"""

import gc
import sys
import time

MODES = {
    "eco": {"hz": 500, "spin_us": 0, "label": "Éco — 500 Hz (CPU minimal)"},
    "rapide": {"hz": 1000, "spin_us": 0, "label": "Rapide — 1000 Hz (recommandé)"},
    "ultra": {"hz": 2000, "spin_us": 150, "label": "Ultra — 2000 Hz (faible latence)"},
    "extreme": {"hz": 8000, "spin_us": 10 ** 6, "label": "Extrême — 8000 Hz (1 cœur à 100 %)"},
}
DEFAULT_MODE = "ultra"


class Sleeper:
    """Attente précise jusqu'à une échéance perf_counter."""

    def __init__(self, spin_us=0):
        self.spin = spin_us / 1e6
        self.timer = None
        self._kernel32 = None
        if sys.platform == "win32":
            self._init_win_timer()

    def _init_win_timer(self):
        try:
            import ctypes
            k32 = ctypes.WinDLL("kernel32", use_last_error=True)
            k32.CreateWaitableTimerExW.restype = ctypes.c_void_p
            # CREATE_WAITABLE_TIMER_HIGH_RESOLUTION (Windows 10 1803+) : précision ~0,5 ms
            h = k32.CreateWaitableTimerExW(None, None, 0x00000002, 0x1F0003)
            if h:
                self.timer = h
                self._kernel32 = k32
                self._ct = ctypes
                k32.SetWaitableTimer.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_longlong),
                                                 ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p,
                                                 ctypes.c_int]
                k32.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
                k32.CloseHandle.argtypes = [ctypes.c_void_p]
        except Exception:  # noqa: BLE001
            self.timer = None

    def _os_sleep(self, seconds):
        if self.timer is not None:
            due = self._ct.c_longlong(-int(seconds * 1e7))  # relatif, en 100 ns
            if self._kernel32.SetWaitableTimer(self.timer, self._ct.byref(due), 0, None, None, 0):
                self._kernel32.WaitForSingleObject(self.timer, 0xFFFFFFFF)
                return
        time.sleep(seconds)

    def until(self, deadline):
        now = time.perf_counter
        remaining = deadline - now()
        if remaining <= 0:
            return
        coarse = remaining - self.spin
        if coarse > 0.0002:
            self._os_sleep(coarse)
        # attente active pour la fin (relâche le GIL à chaque tour)
        while now() < deadline:
            if self.spin >= 1.0:
                continue
            time.sleep(0)

    def close(self):
        if self.timer is not None:
            try:
                self._kernel32.CloseHandle(self.timer)
            except Exception:  # noqa: BLE001
                pass
            self.timer = None


def boost_process(log=print):
    """Priorité haute, timer 1 ms, pas de bridage énergie (Windows 11). Renvoie une fonction d'annulation."""
    undo = []
    # Le thread interface ne doit pas garder le GIL longtemps (5 ms par défaut)
    old = sys.getswitchinterval()
    sys.setswitchinterval(0.0002)
    undo.append(lambda: sys.setswitchinterval(old))
    # Moins de pauses du ramasse-miettes pendant le jeu
    gc.collect()
    if hasattr(gc, "freeze"):
        gc.freeze()
    gc.set_threshold(50000, 50, 100)
    if sys.platform != "win32":
        return lambda: [f() for f in undo]
    done = []
    try:
        import ctypes
        from ctypes import wintypes
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        winmm = ctypes.WinDLL("winmm")
        k32.GetCurrentProcess.restype = wintypes.HANDLE
        k32.GetCurrentThread.restype = wintypes.HANDLE
        if winmm.timeBeginPeriod(1) == 0:
            undo.append(lambda: winmm.timeEndPeriod(1))
            done.append("timer 1 ms")
        if k32.SetPriorityClass(k32.GetCurrentProcess(), 0x00000080):  # HIGH_PRIORITY_CLASS
            done.append("priorité haute")

        # Windows 11 : désactive EcoQoS et le bridage du timer quand la fenêtre est cachée
        class PPTS(ctypes.Structure):
            _fields_ = [("Version", wintypes.ULONG), ("ControlMask", wintypes.ULONG),
                        ("StateMask", wintypes.ULONG)]
        st = PPTS(1, 0x1 | 0x4, 0)
        if hasattr(k32, "SetProcessInformation") and k32.SetProcessInformation(
                k32.GetCurrentProcess(), 4, ctypes.byref(st), ctypes.sizeof(st)):
            done.append("anti-bridage Windows 11")
    except Exception as e:  # noqa: BLE001
        log(f"Optimisations système partielles : {e}")
    if done:
        log("Optimisations : " + ", ".join(done))
    return lambda: [f() for f in reversed(undo)]


def boost_thread(log=print):
    """Thread moteur en priorité temps critique + MMCSS « Games »."""
    if sys.platform != "win32":
        return lambda: None
    undo = []
    try:
        import ctypes
        from ctypes import wintypes
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        k32.GetCurrentThread.restype = wintypes.HANDLE
        k32.SetThreadPriority(k32.GetCurrentThread(), 15)  # THREAD_PRIORITY_TIME_CRITICAL
        try:
            avrt = ctypes.WinDLL("avrt")
            avrt.AvSetMmThreadCharacteristicsW.restype = wintypes.HANDLE
            task = wintypes.DWORD(0)
            h = avrt.AvSetMmThreadCharacteristicsW("Games", ctypes.byref(task))
            if h:
                avrt.AvSetMmThreadPriority(h, 2)  # AVRT_PRIORITY_HIGH
                undo.append(lambda: avrt.AvRevertMmThreadCharacteristics(h))
        except OSError:
            pass
    except Exception as e:  # noqa: BLE001
        log(f"Priorité du thread non modifiée : {e}")
    return lambda: [f() for f in undo]
