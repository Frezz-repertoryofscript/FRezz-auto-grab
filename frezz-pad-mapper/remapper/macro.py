"""Exécution des macros sous forme de machine à états avancée à chaque tick.

Pas de threads : chaque tick du moteur (~1 ms) fait avancer les macros en cours,
ce qui donne un timing précis et déterministe (et testable).
"""

import random


def compile_steps(steps):
    """Transforme les pas éditables en opérations primitives."""
    ops = []
    for s in steps:
        t = s["type"]
        if t == "tap":
            if s["targets"]:
                ops.append(("press", tuple(s["targets"])))
                ops.append(("wait", s["ms"]))
                ops.append(("release", tuple(s["targets"])))
            else:
                ops.append(("wait", s["ms"]))
        elif t in ("press", "release"):
            ops.append((t, tuple(s["targets"])))
        elif t == "wait":
            ops.append(("wait", s["ms"]))
        elif t == "axis":
            ops.append(("axis", s["axis"], s["value"]))
        elif t == "release_all":
            ops.append(("release_all",))
    return ops


def macro_duration_ms(macro):
    """Durée d'un cycle (sans aléa), pour l'affichage."""
    total = 0.0
    for op in compile_steps(macro["steps"]):
        if op[0] == "wait":
            total += op[1]
    return total / max(macro.get("speed", 1.0), 0.05)


class MacroInstance:
    """Une exécution en cours d'une macro."""

    # Si le moteur prend plus de ce retard, on se recale sur l'heure actuelle
    MAX_LAG = 0.05

    def __init__(self, macro, now, loop=False, rng=None):
        self.macro = macro
        self.name = macro["name"]
        self.ops = compile_steps(macro["steps"])
        self.speed = max(float(macro.get("speed", 1.0)), 0.05)
        self.jitter = float(macro.get("jitter_ms", 0))
        repeat = int(macro.get("repeat", 1))
        # loop=True (hold/toggle) : repeat 0 => infini, sinon N cycles max
        if loop:
            self.cycles = repeat if repeat > 0 else None
        else:
            self.cycles = max(repeat, 1)
        self.cycle = 0
        self.pc = 0
        self.next_time = now
        self.held = set()
        self.axes = {}
        self.finished = not self.ops
        self.rng = rng or random.Random()
        self.started_at = now

    def _wait(self, ms):
        delay = ms / 1000.0 / self.speed
        if self.jitter:
            delay += self.rng.uniform(-self.jitter, self.jitter) / 1000.0
        return max(delay, 0.0)

    def update(self, now):
        """Avance la macro ; renvoie False quand elle est terminée."""
        if self.finished:
            return False
        if now - self.next_time > self.MAX_LAG:
            self.next_time = now
        guard = 0
        while not self.finished and now >= self.next_time:
            guard += 1
            if guard > 10000:  # macro sans attente qui boucle : on rend la main
                break
            if self.pc >= len(self.ops):
                self.cycle += 1
                if self.cycles is not None and self.cycle >= self.cycles:
                    self.stop()
                    break
                self.pc = 0
                # Une macro en boucle sans aucune attente bloquerait le tick
                if not any(op[0] == "wait" for op in self.ops):
                    self.next_time = now + 0.001
                    break
                continue
            op = self.ops[self.pc]
            self.pc += 1
            kind = op[0]
            if kind == "press":
                self.held.update(op[1])
            elif kind == "release":
                self.held.difference_update(op[1])
            elif kind == "wait":
                self.next_time += self._wait(op[1])
            elif kind == "axis":
                self.axes[op[1]] = op[2]
            elif kind == "release_all":
                self.held.clear()
                self.axes.clear()
        return not self.finished

    def stop(self):
        self.finished = True
        self.held.clear()
        self.axes.clear()

    @property
    def progress(self):
        if not self.ops:
            return 1.0
        return min(self.pc / len(self.ops), 1.0)
