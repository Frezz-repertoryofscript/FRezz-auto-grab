"""Moteur dans un processus séparé.

L'interface (tkinter) et le moteur ne partagent plus le GIL de Python : quoi que
fasse l'interface, la boucle du moteur n'est jamais retardée. Le processus moteur
tourne en priorité haute, l'interface en priorité normale.
"""

import copy
import multiprocessing as mp
import queue


def _child(cfg, cmd_q, evt_q, snap_q):
    from .engine import Engine
    from .input_backend import PygameInput, NullInput
    from .output_backend import OutputManager, NullOutput
    from .realtime import boost_process

    def log(msg):
        evt_q.put(("log", msg))

    def make_input():
        if cfg["demo"]:
            return NullInput()
        try:
            return PygameInput(cfg["controller_map"], cfg.get("device_name", ""))
        except ImportError:
            log("pygame n'est pas installé : pip install pygame")
            return NullInput()

    def make_output():
        if cfg["demo"]:
            return NullOutput()
        return OutputManager(cfg["virtual_pad"], cfg["keyboard_mouse"], log=log)

    engine = Engine(make_input, make_output, mode=cfg["mode"], log=log)
    engine.commands = cmd_q          # mp.Queue : get_nowait / empty comme queue.Queue
    engine.events = evt_q
    engine.snap_queue = snap_q
    engine.SNAPSHOT_EVERY = 0.016
    engine.core.set_profile(cfg["profile"])
    undo = boost_process(log)
    engine.alive = True
    try:
        engine._run()                # boucle dans le thread principal du processus
    finally:
        undo()


class EngineProcess:
    """Même interface que Engine, mais le moteur vit dans un autre processus."""

    def __init__(self, cfg):
        self.ctx = mp.get_context("spawn")
        self.cfg = cfg
        self.commands = self.ctx.Queue()
        self.events = self.ctx.Queue()
        self.snaps = self.ctx.Queue(maxsize=4)
        self.proc = None
        self._snap = {}
        self.profile = cfg.get("profile")

    def start(self):
        cfg = dict(self.cfg, profile=self.profile)
        self.proc = self.ctx.Process(target=_child, args=(cfg, self.commands, self.events, self.snaps),
                                     name="FRezzEngine", daemon=True)
        self.proc.start()

    def alive(self):
        return self.proc is not None and self.proc.is_alive()

    def stop(self):
        if not self.proc:
            return
        self.send("quit")
        self.proc.join(timeout=2)
        if self.proc.is_alive():
            self.proc.terminate()
            self.proc.join(timeout=1)
        self.proc = None

    def send(self, cmd, *args):
        self.commands.put((cmd, args))

    def set_profile(self, profile):
        self.profile = copy.deepcopy(profile)
        self.send("profile", self.profile)

    def snapshot(self):
        while True:
            try:
                self._snap = self.snaps.get_nowait()
            except (queue.Empty, OSError, EOFError):
                break
        return dict(self._snap)
