"""Fenêtres : édition d'un pas, capture de combo, calibration."""

import time
import tkinter as tk
from tkinter import ttk

from ..constants import STEP_TYPES, PAD_AXES, LABELS, step_targets, target_label, PHYS_BUTTONS
from .widgets import BG, listbox


class StepDialog(tk.Toplevel):
    """Création / édition d'un pas de macro."""

    def __init__(self, parent, step=None, on_ok=None):
        super().__init__(parent)
        self.title("Pas de macro")
        self.configure(bg=BG)
        self.resizable(False, False)
        self.transient(parent)
        self.on_ok = on_ok
        step = dict(step or {"type": "tap", "targets": ["pad:CROSS"], "ms": 50})
        types = list(STEP_TYPES)
        self.type_var = tk.StringVar(value=STEP_TYPES[step["type"]])
        pad = {"padx": 10, "pady": 4}

        ttk.Label(self, text="Type").grid(row=0, column=0, sticky="w", **pad)
        cb = ttk.Combobox(self, values=[STEP_TYPES[t] for t in types], textvariable=self.type_var,
                          state="readonly", width=30)
        cb.grid(row=0, column=1, columnspan=2, sticky="we", **pad)
        cb.bind("<<ComboboxSelected>>", lambda e: self._refresh())

        # Cibles
        self.tf = ttk.LabelFrame(self, text="Boutons / touches (plusieurs = simultané)")
        self.tf.grid(row=1, column=0, columnspan=3, sticky="we", **pad)
        self.targets = list(step.get("targets", []))
        self.lb = listbox(self.tf, height=4, width=34)
        self.lb.grid(row=0, column=0, rowspan=3, padx=6, pady=6)
        self.add_var = tk.StringVar(value="pad:CROSS")
        ttk.Combobox(self.tf, values=step_targets(), textvariable=self.add_var, width=18).grid(
            row=0, column=1, padx=6, pady=4)
        ttk.Button(self.tf, text="Ajouter", command=self._add).grid(row=1, column=1, sticky="we", padx=6)
        ttk.Button(self.tf, text="Retirer", command=self._remove).grid(row=2, column=1, sticky="we", padx=6)

        # Durée
        self.ms_var = tk.IntVar(value=int(step.get("ms", 50)))
        self.ms_lbl = ttk.Label(self, text="Durée (ms)")
        self.ms_lbl.grid(row=2, column=0, sticky="w", **pad)
        self.ms_spin = ttk.Spinbox(self, from_=0, to=600000, increment=5, textvariable=self.ms_var, width=10)
        self.ms_spin.grid(row=2, column=1, sticky="w", **pad)

        # Axe
        self.axis_var = tk.StringVar(value=step.get("axis", "LX"))
        self.val_var = tk.DoubleVar(value=float(step.get("value", 0.0)))
        self.ax_lbl = ttk.Label(self, text="Axe / valeur")
        self.ax_lbl.grid(row=3, column=0, sticky="w", **pad)
        self.ax_cb = ttk.Combobox(self, values=PAD_AXES, textvariable=self.axis_var, state="readonly", width=6)
        self.ax_cb.grid(row=3, column=1, sticky="w", **pad)
        self.val_scale = ttk.Scale(self, from_=-1, to=1, variable=self.val_var, length=160,
                                   command=lambda _=None: self.val_lbl.configure(text=f"{self.val_var.get():+.2f}"))
        self.val_scale.grid(row=3, column=2, sticky="w", **pad)
        self.val_lbl = ttk.Label(self, text=f"{self.val_var.get():+.2f}", style="Muted.TLabel")
        self.val_lbl.grid(row=4, column=2, sticky="w", padx=10)
        self.hint = ttk.Label(self, text="Sticks : -1 = gauche/haut, +1 = droite/bas. Gâchettes : 0 à 1.",
                              style="Muted.TLabel")
        self.hint.grid(row=5, column=0, columnspan=3, sticky="w", **pad)

        bf = ttk.Frame(self)
        bf.grid(row=6, column=0, columnspan=3, sticky="e", **pad)
        ttk.Button(bf, text="Annuler", command=self.destroy).pack(side="right", padx=4)
        ttk.Button(bf, text="OK", style="Accent.TButton", command=self._ok).pack(side="right")
        self._fill()
        self._refresh()
        self.bind("<Return>", lambda e: self._ok())
        self.bind("<Escape>", lambda e: self.destroy())
        self.grab_set()

    def _type(self):
        for k, v in STEP_TYPES.items():
            if v == self.type_var.get():
                return k
        return "wait"

    def _fill(self):
        self.lb.delete(0, "end")
        for t in self.targets:
            self.lb.insert("end", f"{t}   ({target_label(t)})")

    def _add(self):
        t = self.add_var.get().strip()
        if t and t not in self.targets:
            self.targets.append(t)
            self._fill()

    def _remove(self):
        sel = self.lb.curselection()
        if sel:
            del self.targets[sel[0]]
            self._fill()

    def _refresh(self):
        t = self._type()
        show_t = t in ("tap", "press", "release")
        show_ms = t in ("tap", "wait")
        show_ax = t == "axis"
        for w in (self.tf,):
            w.grid() if show_t else w.grid_remove()
        for w in (self.ms_lbl, self.ms_spin):
            w.grid() if show_ms else w.grid_remove()
        for w in (self.ax_lbl, self.ax_cb, self.val_scale, self.val_lbl, self.hint):
            w.grid() if show_ax else w.grid_remove()

    def _ok(self):
        t = self._type()
        step = {"type": t}
        if t in ("tap", "press", "release"):
            if self.add_var.get().strip() and not self.targets:
                self._add()
            step["targets"] = list(self.targets)
        if t in ("tap", "wait"):
            try:
                step["ms"] = max(0, int(float(self.ms_var.get())))
            except (tk.TclError, ValueError):
                step["ms"] = 50
        if t == "axis":
            step["axis"] = self.axis_var.get()
            v = round(self.val_var.get(), 2)
            step["value"] = max(0.0, v) if step["axis"] in ("L2", "R2") else v
        if self.on_ok:
            self.on_ok(step)
        self.destroy()


class CaptureDialog(tk.Toplevel):
    """Capture un combo : appuie sur les boutons voulus puis relâche tout."""

    def __init__(self, parent, engine, on_done, title="Capture du combo"):
        super().__init__(parent)
        self.title(title)
        self.configure(bg=BG)
        self.transient(parent)
        self.engine, self.on_done = engine, on_done
        self.best = []
        self.started = False
        self.deadline = time.time() + 15
        ttk.Label(self, text="Appuie sur le bouton ou le combo sur la manette,\npuis relâche tout.",
                  style="H.TLabel", justify="center").pack(padx=20, pady=(16, 8))
        self.lbl = ttk.Label(self, text="…", style="Muted.TLabel")
        self.lbl.pack(padx=20, pady=6)
        ttk.Button(self, text="Annuler", command=self.destroy).pack(pady=(4, 14))
        self.grab_set()
        self.after(30, self._poll)

    def _poll(self):
        if not self.winfo_exists():
            return
        snap = self.engine.snapshot()
        held = [b for b in PHYS_BUTTONS if snap.get("buttons", {}).get(b)]
        if held:
            self.started = True
            if len(held) >= len(self.best):
                self.best = held
            self.lbl.configure(text=" + ".join(LABELS.get(b, b) for b in held))
        elif self.started:
            self.on_done(self.best)
            self.destroy()
            return
        if time.time() > self.deadline:
            self.destroy()
            return
        self.after(20, self._poll)


class CalibrationDialog(tk.Toplevel):
    """Assistant : associe chaque bouton/axe physique à son index brut SDL."""

    AXIS_STEPS = [
        ("LX", "Pousse le stick GAUCHE vers la DROITE", 1),
        ("LY", "Pousse le stick GAUCHE vers le BAS", 1),
        ("RX", "Pousse le stick DROIT vers la DROITE", 1),
        ("RY", "Pousse le stick DROIT vers le BAS", 1),
        ("L2", "Enfonce L2 à fond", 1),
        ("R2", "Enfonce R2 à fond", 1),
    ]

    def __init__(self, parent, engine, on_done):
        super().__init__(parent)
        self.title("Calibration de la manette")
        self.configure(bg=BG)
        self.transient(parent)
        self.engine, self.on_done = engine, on_done
        self.result = {"buttons": {}, "axes": {}, "use_hat": False}
        self.queue = [("btn", b, f"Appuie sur {LABELS[b]}") for b in PHYS_BUTTONS if b not in ("L2", "R2")]
        self.queue += [("axis", a, txt) for a, txt, _ in self.AXIS_STEPS]
        self.i = 0
        self.base = None
        self.trigger_min = None
        self.prompt = ttk.Label(self, text="", style="H.TLabel")
        self.prompt.pack(padx=24, pady=(18, 6))
        self.info = ttk.Label(self, text="", style="Muted.TLabel")
        self.info.pack(padx=24, pady=4)
        self.bar = ttk.Progressbar(self, length=320, maximum=len(self.queue))
        self.bar.pack(padx=24, pady=8)
        bf = ttk.Frame(self)
        bf.pack(pady=(4, 16))
        ttk.Button(bf, text="Passer", command=self._skip).pack(side="left", padx=4)
        ttk.Button(bf, text="Annuler", command=self.destroy).pack(side="left", padx=4)
        self.grab_set()
        self._next()
        self.after(30, self._poll)

    def _raw(self):
        return self.engine.snapshot().get("raw")

    def _next(self):
        if self.i >= len(self.queue):
            if self.trigger_min is not None:
                self.result["trigger_min"] = self.trigger_min
            self.on_done(self.result)
            self.destroy()
            return
        kind, name, txt = self.queue[self.i]
        self.prompt.configure(text=txt)
        self.info.configure(text="puis relâche" if kind == "btn" else "maintiens 1 seconde puis relâche")
        self.bar.configure(value=self.i)
        self.base = None
        self.wait_release = False

    def _skip(self):
        self.i += 1
        self._next()

    def _poll(self):
        if not self.winfo_exists():
            return
        raw = self._raw()
        if raw is None:
            self.info.configure(text="Aucune manette détectée…")
        elif self.i < len(self.queue):
            kind, name, _ = self.queue[self.i]
            if self.base is None:
                if not any(raw["buttons"]) and all(h == (0, 0) for h in raw["hats"]):
                    self.base = {"axes": list(raw["axes"])}
            elif kind == "btn":
                self._poll_button(name, raw)
            else:
                self._poll_axis(name, raw)
        self.after(20, self._poll)

    def _poll_button(self, name, raw):
        if self.wait_release:
            if not any(raw["buttons"]) and all(h == (0, 0) for h in raw["hats"]):
                self.i += 1
                self._next()
            return
        pressed = [i for i, v in enumerate(raw["buttons"]) if v]
        if pressed:
            self.result["buttons"][name] = pressed[0]
            self.info.configure(text=f"→ bouton #{pressed[0]}")
            self.wait_release = True
        elif raw["hats"] and raw["hats"][0] != (0, 0) and name.startswith("DPAD"):
            self.result["use_hat"] = True
            self.result["buttons"][name] = None
            self.info.configure(text="→ croix directionnelle (hat)")
            self.wait_release = True

    def _poll_axis(self, name, raw):
        base = self.base["axes"]
        if self.wait_release:
            idx = self.result["axes"].get(name)
            if idx is None or abs(raw["axes"][idx] - base[idx]) < 0.2:
                self.i += 1
                self._next()
            return
        best, delta = None, 0.0
        for i, v in enumerate(raw["axes"]):
            d = abs(v - base[i]) if i < len(base) else 0
            if d > delta and i not in [x for k, x in self.result["axes"].items() if k != name]:
                best, delta = i, d
        if best is not None and delta > 0.7:
            self.result["axes"][name] = best
            if name in ("L2", "R2"):
                self.trigger_min = round(base[best], 2)
            self.info.configure(text=f"→ axe #{best}")
            self.wait_release = True
