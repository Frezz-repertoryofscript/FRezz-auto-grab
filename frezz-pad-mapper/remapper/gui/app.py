"""Fenêtre principale de FRezz Pad Mapper."""

import copy
import json
import os
import queue
import time
import tkinter as tk
from tkinter import ttk, filedialog, messagebox, simpledialog

from .. import __version__
from ..constants import (PHYS_BUTTONS, LABELS, STICK_TARGETS, ACTIONS, ACTION_LABELS,
                         all_targets, target_label)
from ..engine_process import EngineProcess
from ..realtime import MODES, DEFAULT_MODE
from ..profile import ProfileStore, default_profile, normalize_profile, load_json, save_json
from .controller_view import ControllerView
from .dialogs import CaptureDialog, CalibrationDialog
from .macro_tab import MacroTab
from .widgets import (apply_theme, ScrollFrame, LabeledScale, chord_text,
                      BG, FG, MUTED, OK, WARN, BAD, ACCENT2)

STICK_LABELS = {
    "pad:LS": "Stick gauche virtuel", "pad:RS": "Stick droit virtuel", "mouse": "Souris",
    "zqsd": "Touches ZQSD", "wasd": "Touches WASD", "arrows": "Flèches", "none": "Désactivé",
}

DEFAULT_CONFIG = {
    "last_profile": "Défaut",
    "device_name": "",      # "" = choix automatique (DualSense en priorité)
    "perf_mode": DEFAULT_MODE,
    "virtual_pad": True,
    "keyboard_mouse": True,
}


class App(tk.Tk):
    def __init__(self, base_dir, demo=False):
        super().__init__()
        self.base_dir = base_dir
        self.cfg_path = os.path.join(base_dir, "config", "config.json")
        self.map_path = os.path.join(base_dir, "config", "controller_map.json")
        self.cfg = {**DEFAULT_CONFIG, **load_json(self.cfg_path, {})}
        self.store = ProfileStore(os.path.join(base_dir, "profiles"))
        self.demo = demo
        self.log_queue = queue.Queue()
        self._save_job = None
        self._push_job = None

        self.title(f"FRezz Pad Mapper {__version__} — remappage & macros PS5")
        self.geometry("1180x760")
        self.minsize(1000, 660)
        apply_theme(self)
        self.protocol("WM_DELETE_WINDOW", self.on_close)

        self.profile = self._load_initial_profile()
        self.engine = self._make_engine()
        self._build()
        self.engine.set_profile(self.profile)
        self.engine.start()
        self.engine_dead_shown = False
        self.after(33, self._tick)

    # ---------------------------------------------------------------- moteur
    def _make_engine(self):
        mode = self.cfg.get("perf_mode", DEFAULT_MODE)
        return EngineProcess({
            "demo": self.demo,
            "controller_map": load_json(self.map_path, {}),
            "device_name": self.cfg.get("device_name", ""),
            "virtual_pad": bool(self.cfg.get("virtual_pad", True)),
            "keyboard_mouse": bool(self.cfg.get("keyboard_mouse", True)),
            "mode": mode if mode in MODES else DEFAULT_MODE,
            "profile": self.profile,
        })

    def restart_engine(self):
        self.engine.stop()
        self.engine = self._make_engine()
        self.engine.set_profile(self.profile)
        self.engine.start()
        self.log("Moteur redémarré")

    def log(self, msg):
        self.log_queue.put(f"[{time.strftime('%H:%M:%S')}] {msg}")

    # --------------------------------------------------------------- profils
    def _load_initial_profile(self):
        names = self.store.list()
        if not names:
            self.store.save(default_profile("Défaut"))
            names = ["Défaut"]
        name = self.cfg.get("last_profile")
        try:
            return self.store.load(name if name in names else names[0])
        except (OSError, ValueError):
            return default_profile()

    def profile_changed(self):
        """À appeler après toute modification : envoi au moteur + sauvegarde auto."""
        if self._push_job:
            self.after_cancel(self._push_job)
        self._push_job = self.after(120, self._push)
        if self._save_job:
            self.after_cancel(self._save_job)
        self._save_job = self.after(600, self._autosave)
        self.save_lbl.configure(text="modifié…", foreground=WARN)

    def _push(self):
        self._push_job = None
        self.engine.set_profile(self.profile)

    def _autosave(self):
        self._save_job = None
        try:
            self.store.save(self.profile)
            self.save_lbl.configure(text="✔ sauvegardé", foreground=OK)
        except OSError as e:
            self.save_lbl.configure(text="erreur de sauvegarde", foreground=BAD)
            self.log(f"Sauvegarde impossible : {e}")

    def switch_profile(self, name):
        if self._save_job:
            self.after_cancel(self._save_job)
            self._autosave()
        try:
            self.profile = self.store.load(name)
        except (OSError, ValueError) as e:
            messagebox.showerror("Profil", f"Impossible de charger « {name} » : {e}")
            return
        self.cfg["last_profile"] = name
        save_json(self.cfg_path, self.cfg)
        self.engine.set_profile(self.profile)
        self.reload_all()
        self.log(f"Profil actif : {name}")

    def cycle_profile(self, d):
        names = self.store.list()
        if len(names) < 2:
            return
        i = names.index(self.profile["name"]) if self.profile["name"] in names else 0
        self.switch_profile(names[(i + d) % len(names)])
        self.engine.send("rumble", 0.3, 0.3, 120)

    def new_profile(self, copy_current=False):
        name = simpledialog.askstring("Nouveau profil", "Nom du profil :", parent=self)
        if not name:
            return
        name = name.strip()
        if name in self.store.list():
            messagebox.showwarning("Profil", "Ce nom existe déjà.")
            return
        p = copy.deepcopy(self.profile) if copy_current else default_profile(name)
        p["name"] = name
        self.store.save(p)
        self.switch_profile(name)

    def rename_profile(self):
        old = self.profile["name"]
        name = simpledialog.askstring("Renommer", "Nouveau nom :", initialvalue=old, parent=self)
        if not name or name.strip() == old:
            return
        name = name.strip()
        if name in self.store.list():
            messagebox.showwarning("Profil", "Ce nom existe déjà.")
            return
        self.profile["name"] = name
        self.store.save(self.profile)
        self.store.delete(old)
        self.switch_profile(name)

    def delete_profile(self):
        names = self.store.list()
        if len(names) <= 1:
            messagebox.showinfo("Profil", "Impossible de supprimer le dernier profil.")
            return
        name = self.profile["name"]
        if not messagebox.askyesno("Supprimer", f"Supprimer le profil « {name} » ?"):
            return
        if self._save_job:
            self.after_cancel(self._save_job)
            self._save_job = None
        self.store.delete(name)
        self.switch_profile([n for n in names if n != name][0])

    def import_profile(self):
        path = filedialog.askopenfilename(filetypes=[("Profil JSON", "*.json")])
        if not path:
            return
        try:
            with open(path, encoding="utf-8") as fh:
                p = normalize_profile(json.load(fh))
        except (OSError, ValueError) as e:
            messagebox.showerror("Import", f"Fichier invalide : {e}")
            return
        base, i = p["name"], 2
        while p["name"] in self.store.list():
            p["name"] = f"{base} ({i})"
            i += 1
        self.store.save(p)
        self.switch_profile(p["name"])

    def export_profile(self):
        path = filedialog.asksaveasfilename(defaultextension=".json",
                                            initialfile=self.profile["name"] + ".json",
                                            filetypes=[("Profil JSON", "*.json")])
        if path:
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(self.profile, fh, indent=2, ensure_ascii=False)

    # ----------------------------------------------------------- interface
    def _build(self):
        top = ttk.Frame(self)
        top.pack(fill="x", padx=12, pady=(10, 4))
        ttk.Label(top, text="🎮 FRezz Pad Mapper", style="Title.TLabel").pack(side="left")
        ttk.Label(top, text="  Profil :").pack(side="left", padx=(20, 4))
        self.profile_var = tk.StringVar()
        self.profile_cb = ttk.Combobox(top, textvariable=self.profile_var, state="readonly", width=24)
        self.profile_cb.pack(side="left")
        self.profile_cb.bind("<<ComboboxSelected>>", lambda e: self.switch_profile(self.profile_var.get()))
        self.save_lbl = ttk.Label(top, text="", style="Muted.TLabel")
        self.save_lbl.pack(side="left", padx=10)

        self.pause_btn = ttk.Button(top, text="⏸ Pause", command=self.toggle_pause)
        self.pause_btn.pack(side="right", padx=2)
        ttk.Button(top, text="■ Stop macros", command=lambda: self.engine.send("stop_macros")).pack(
            side="right", padx=2)
        self.status_lbl = ttk.Label(top, text="", style="Muted.TLabel")
        self.status_lbl.pack(side="right", padx=12)

        self.nb = ttk.Notebook(self)
        self.nb.pack(fill="both", expand=True, padx=10, pady=(4, 10))
        self.tab_pad = ttk.Frame(self.nb)
        self.tab_remap = ttk.Frame(self.nb)
        self.tab_sticks = ttk.Frame(self.nb)
        self.tab_macros = MacroTab(self.nb, self)
        self.tab_turbo = ttk.Frame(self.nb)
        self.tab_hotkeys = ttk.Frame(self.nb)
        self.tab_settings = ttk.Frame(self.nb)
        self.tab_log = ttk.Frame(self.nb)
        for frame, text in [(self.tab_pad, "🎮 Manette"), (self.tab_remap, "🔁 Remapping"),
                            (self.tab_sticks, "🕹 Sticks & gâchettes"), (self.tab_macros, "⚡ Macros & combos"),
                            (self.tab_turbo, "🔥 Turbo"), (self.tab_hotkeys, "⌨ Raccourcis"),
                            (self.tab_settings, "⚙ Paramètres"), (self.tab_log, "📜 Journal")]:
            self.nb.add(frame, text=text)
        self._build_pad_tab()
        self._build_log_tab()
        self._build_settings_tab()
        self.reload_all()

    def reload_all(self):
        """Reconstruit les onglets dépendant du profil."""
        self.profile_cb.configure(values=self.store.list())
        self.profile_var.set(self.profile["name"])
        for tab, builder in [(self.tab_remap, self._build_remap_tab), (self.tab_sticks, self._build_sticks_tab),
                             (self.tab_turbo, self._build_turbo_tab), (self.tab_hotkeys, self._build_hotkeys_tab)]:
            for c in tab.winfo_children():
                c.destroy()
            builder()
        self.tab_macros.cur = 0 if self.profile["macros"] else None
        self.tab_macros.refresh()
        self.save_lbl.configure(text="")

    def refresh_remap(self):
        values = all_targets(m["name"] for m in self.profile["macros"])
        for b, (var, cb, lbl) in getattr(self, "remap_widgets", {}).items():
            cb.configure(values=values)
            var.set(self.profile["buttons"][b])
            lbl.configure(text=target_label(var.get()))

    # ---- Manette
    def _build_pad_tab(self):
        f = self.tab_pad
        left = ttk.Frame(f)
        left.pack(side="left", fill="both", padx=14, pady=14)
        self.view = ControllerView(left)
        self.view.pack()
        self.conn_lbl = ttk.Label(left, text="", style="H.TLabel")
        self.conn_lbl.pack(anchor="w", pady=(10, 2))
        self.batt_lbl = ttk.Label(left, text="", style="Muted.TLabel")
        self.batt_lbl.pack(anchor="w")
        row = ttk.Frame(left)
        row.pack(anchor="w", pady=8)
        ttk.Label(row, text="Périphérique :").pack(side="left")
        self.dev_var = tk.StringVar()
        self.dev_cb = ttk.Combobox(row, textvariable=self.dev_var, state="readonly", width=34)
        self.dev_cb.pack(side="left", padx=6)
        self.dev_cb.bind("<<ComboboxSelected>>", lambda e: self._select_device())
        ttk.Button(row, text="↻", width=3, command=lambda: self.engine.send("list_devices")).pack(side="left")
        row2 = ttk.Frame(left)
        row2.pack(anchor="w")
        ttk.Button(row2, text="📳 Test vibration", command=lambda: self.engine.send("rumble", 0.8, 0.8, 400)).pack(
            side="left", padx=(0, 6))
        ttk.Button(row2, text="🎯 Calibrer la manette", command=self.calibrate).pack(side="left")

        right = ttk.Frame(f)
        right.pack(side="left", fill="both", expand=True, padx=10, pady=14)
        ttk.Label(right, text="Macros en cours", style="H.TLabel").pack(anchor="w")
        self.running_lb = tk.Listbox(right, height=8, bg="#262a36", fg=FG, borderwidth=0,
                                     highlightthickness=0, font=("Segoe UI", 10))
        self.running_lb.pack(fill="x", pady=(4, 12))
        ttk.Label(right, text="Axes (entrée → sortie)", style="H.TLabel").pack(anchor="w")
        self.axes_lbl = ttk.Label(right, text="", font=("Consolas", 10), justify="left")
        self.axes_lbl.pack(anchor="w", pady=4)
        ttk.Label(right, text="Rappel", style="H.TLabel").pack(anchor="w", pady=(14, 2))
        ttk.Label(right, style="Muted.TLabel", justify="left", wraplength=420, text=(
            "• Le jeu doit voir la manette VIRTUELLE (Xbox 360 / DS4) créée par l'appli.\n"
            "• Cache ta DualSense au jeu avec HidHide sinon les appuis sont doublés.\n"
            "• Désactive le support PlayStation de Steam Input pour ce jeu.\n"
            "• PS + Options = pause, PS + R1 / L1 = profil suivant / précédent,\n"
            "  PS + Create = stopper toutes les macros (modifiable dans Raccourcis).")).pack(anchor="w")

    def _select_device(self):
        txt = self.dev_var.get()
        if not txt:
            return
        name = "" if txt.startswith("Auto") else txt.split(": ", 1)[1]
        self.cfg["device_name"] = name
        save_json(self.cfg_path, self.cfg)
        self.engine.send("select_device", name)

    def calibrate(self):
        def done(result):
            save_json(self.map_path, result)
            self.engine.send("controller_map", result)
            self.log("Calibration enregistrée")
            messagebox.showinfo("Calibration", "Calibration enregistrée ✔")
        self._with_raw(CalibrationDialog(self, self.engine, done))

    def _with_raw(self, win):
        """Active la lecture brute de la manette tant que la fenêtre est ouverte."""
        self.engine.send("raw", True)
        win.bind("<Destroy>", lambda e: e.widget is win and self.engine.send("raw", False), add="+")
        return win

    # ---- Remapping
    def _build_remap_tab(self):
        f = self.tab_remap
        head = ttk.Frame(f)
        head.pack(fill="x", padx=14, pady=(12, 4))
        ttk.Label(head, text="Bouton physique → action envoyée", style="H.TLabel").pack(side="left")
        ttk.Button(head, text="Tout réinitialiser", command=self._reset_remap).pack(side="right")
        ttk.Button(head, text="Échanger ✕ / ○", command=lambda: self._swap("CROSS", "CIRCLE")).pack(
            side="right", padx=4)
        ttk.Label(f, style="Muted.TLabel", wraplength=1000, justify="left", text=(
            "Cibles : pad:… = bouton manette virtuelle, key:… = touche clavier, mouse:… = clic souris, "
            "wheel:… = molette, macro:… = lance une macro, action:… = profil / pause. "
            "Tu peux taper une valeur directement (ex. key:f).")).pack(anchor="w", padx=14)
        sf = ScrollFrame(f)
        sf.pack(fill="both", expand=True, padx=10, pady=8)
        values = all_targets(m["name"] for m in self.profile["macros"])
        self.remap_widgets = {}
        for i, b in enumerate(PHYS_BUTTONS):
            r = i
            ttk.Label(sf.inner, text=LABELS[b], width=20).grid(row=r, column=0, sticky="w", padx=8, pady=3)
            var = tk.StringVar(value=self.profile["buttons"][b])
            cb = ttk.Combobox(sf.inner, textvariable=var, values=values, width=28)
            cb.grid(row=r, column=1, padx=6)
            lbl = ttk.Label(sf.inner, text=target_label(var.get()), style="Muted.TLabel", width=34)
            lbl.grid(row=r, column=2, sticky="w", padx=6)

            def commit(_e=None, b=b, var=var, lbl=lbl):
                t = var.get().strip() or "none"
                if t != "none" and ":" not in t:
                    t = "key:" + t.lower()
                    var.set(t)
                if self.profile["buttons"][b] != t:
                    self.profile["buttons"][b] = t
                    self.profile_changed()
                lbl.configure(text=target_label(t))
            cb.bind("<<ComboboxSelected>>", commit)
            cb.bind("<Return>", commit)
            cb.bind("<FocusOut>", commit)
            ttk.Button(sf.inner, text="Défaut", width=7,
                       command=lambda b=b: self._set_button(b, "none" if b == "MUTE" else f"pad:{b}")).grid(
                row=r, column=3, padx=2)
            ttk.Button(sf.inner, text="Aucun", width=7, command=lambda b=b: self._set_button(b, "none")).grid(
                row=r, column=4, padx=2)
            self.remap_widgets[b] = (var, cb, lbl)

    def _set_button(self, b, t):
        self.profile["buttons"][b] = t
        self.refresh_remap()
        self.profile_changed()

    def _swap(self, a, b):
        bt = self.profile["buttons"]
        bt[a], bt[b] = bt[b], bt[a]
        self.refresh_remap()
        self.profile_changed()

    def _reset_remap(self):
        if messagebox.askyesno("Réinitialiser", "Remettre tous les boutons par défaut ?"):
            self.profile["buttons"] = default_profile()["buttons"]
            self.refresh_remap()
            self.profile_changed()

    # ---- Sticks & gâchettes
    def _build_sticks_tab(self):
        f = ScrollFrame(self.tab_sticks)
        f.pack(fill="both", expand=True)
        inner = f.inner
        vp = ttk.LabelFrame(inner, text="Manette virtuelle")
        vp.pack(fill="x", padx=12, pady=8)
        self.vpad_var = tk.StringVar(value=self.profile["virtual_pad"])
        for val, txt in [("x360", "Xbox 360 (compatibilité maximale)"), ("ds4", "DualShock 4 (icônes PlayStation)")]:
            ttk.Radiobutton(vp, text=txt, value=val, variable=self.vpad_var,
                            command=lambda: self._set(self.profile, "virtual_pad", self.vpad_var.get())).pack(
                side="left", padx=10, pady=6)

        row = ttk.Frame(inner)
        row.pack(fill="x")
        for side, title in (("LEFT", "Stick gauche"), ("RIGHT", "Stick droit")):
            cfg = self.profile["sticks"][side]
            lf = ttk.LabelFrame(row, text=title)
            lf.pack(side="left", fill="both", expand=True, padx=12, pady=6)
            tr = ttk.Frame(lf)
            tr.pack(anchor="w", padx=6, pady=4)
            ttk.Label(tr, text="Envoyer vers", width=22).pack(side="left")
            var = tk.StringVar(value=STICK_LABELS[cfg["target"]] if cfg["target"] in STICK_LABELS else cfg["target"])
            cb = ttk.Combobox(tr, values=[STICK_LABELS[t] for t in STICK_TARGETS], textvariable=var,
                              state="readonly", width=22)
            cb.pack(side="left")

            def set_target(_e=None, cfg=cfg, var=var):
                for k, v in STICK_LABELS.items():
                    if v == var.get():
                        self._set(cfg, "target", k)
            cb.bind("<<ComboboxSelected>>", set_target)
            for key, text, frm, to, digits in [
                ("deadzone", "Zone morte", 0, 0.5, 2), ("outer", "Zone morte extérieure", 0.5, 1, 2),
                ("anti_deadzone", "Anti-zone morte", 0, 0.5, 2), ("sensitivity", "Sensibilité", 0.1, 3, 2),
                ("curve", "Courbe (1 = linéaire)", 0.3, 3, 2), ("mouse_speed", "Vitesse souris (px/s)", 100, 5000, 0),
                ("digital_threshold", "Seuil touches", 0.1, 0.95, 2)]:
                LabeledScale(lf, text, frm, to, cfg[key], lambda v, cfg=cfg, key=key: self._set(cfg, key, v),
                             digits=digits).pack(anchor="w", padx=6, pady=1)
            cr = ttk.Frame(lf)
            cr.pack(anchor="w", padx=6, pady=6)
            for key, text in (("invert_x", "Inverser X"), ("invert_y", "Inverser Y")):
                v = tk.BooleanVar(value=cfg[key])
                ttk.Checkbutton(cr, text=text, variable=v,
                                command=lambda cfg=cfg, key=key, v=v: self._set(cfg, key, v.get())).pack(
                    side="left", padx=(0, 14))
            ttk.Button(cr, text="Échanger les sticks", command=self._swap_sticks).pack(side="left")

        row = ttk.Frame(inner)
        row.pack(fill="x")
        for side in ("L2", "R2"):
            cfg = self.profile["triggers"][side]
            lf = ttk.LabelFrame(row, text=f"Gâchette {side}")
            lf.pack(side="left", fill="both", expand=True, padx=12, pady=6)
            for key, text, frm, to in [("deadzone", "Zone morte", 0, 0.5), ("outer", "Zone morte extérieure", 0.5, 1),
                                       ("threshold", "Seuil appui digital", 0.05, 0.95)]:
                LabeledScale(lf, text, frm, to, cfg[key],
                             lambda v, cfg=cfg, key=key: self._set(cfg, key, v)).pack(anchor="w", padx=6, pady=1)
            ttk.Label(lf, style="Muted.TLabel", text=(
                "Le seuil sert pour les macros, le turbo et quand la gâchette\n"
                "est remappée vers une touche / un bouton.")).pack(anchor="w", padx=6, pady=4)

    def _set(self, d, k, v):
        d[k] = v
        self.profile_changed()

    def _swap_sticks(self):
        s = self.profile["sticks"]
        s["LEFT"]["target"], s["RIGHT"]["target"] = s["RIGHT"]["target"], s["LEFT"]["target"]
        self.profile_changed()
        for c in self.tab_sticks.winfo_children():
            c.destroy()
        self._build_sticks_tab()

    # ---- Turbo
    def _build_turbo_tab(self):
        f = self.tab_turbo
        ttk.Label(f, text="Turbo / tir automatique", style="H.TLabel").pack(anchor="w", padx=14, pady=(12, 0))
        ttk.Label(f, style="Muted.TLabel", text=(
            "Maintien : le bouton est répété tant qu'il est tenu.  "
            "Toggle : un appui lance le tir auto, un autre l'arrête.")).pack(anchor="w", padx=14)
        sf = ScrollFrame(f)
        sf.pack(fill="both", expand=True, padx=10, pady=8)
        turbo = self.profile["turbo"]
        for i, b in enumerate(PHYS_BUTTONS):
            cfg = turbo.get(b, {"enabled": False, "rate": 12.0, "mode": "hold"})
            en = tk.BooleanVar(value=cfg["enabled"])
            mode = tk.StringVar(value="Maintien" if cfg["mode"] == "hold" else "Toggle")
            ttk.Label(sf.inner, text=LABELS[b], width=20).grid(row=i, column=0, sticky="w", padx=8, pady=2)

            def update(_e=None, b=b, en=en, mode=mode):
                cur = turbo.get(b, {"enabled": False, "rate": 12.0, "mode": "hold"})
                cur["enabled"] = en.get()
                cur["mode"] = "hold" if mode.get() == "Maintien" else "toggle"
                turbo[b] = cur
                self.profile_changed()
            ttk.Checkbutton(sf.inner, text="Actif", variable=en, command=update).grid(row=i, column=1, padx=6)
            cb = ttk.Combobox(sf.inner, values=["Maintien", "Toggle"], textvariable=mode, state="readonly", width=10)
            cb.grid(row=i, column=2, padx=6)
            cb.bind("<<ComboboxSelected>>", update)

            def set_rate(v, b=b, en=en, mode=mode):
                turbo.setdefault(b, {"enabled": en.get(), "rate": 12.0,
                                     "mode": "hold" if mode.get() == "Maintien" else "toggle"})["rate"] = v
                self.profile_changed()
            LabeledScale(sf.inner, "Cadence (appuis/s)", 1, 30, cfg["rate"], set_rate, digits=0).grid(
                row=i, column=3, padx=6, sticky="w")

    # ---- Raccourcis
    def _build_hotkeys_tab(self):
        f = self.tab_hotkeys
        ttk.Label(f, text="Raccourcis globaux (combos sur la manette)", style="H.TLabel").pack(
            anchor="w", padx=14, pady=(12, 0))
        ttk.Label(f, style="Muted.TLabel", text="Ils fonctionnent même quand le remappage est en pause.").pack(
            anchor="w", padx=14)
        g = ttk.Frame(f)
        g.pack(anchor="w", padx=14, pady=10)
        for i, action in enumerate(ACTIONS):
            ttk.Label(g, text=ACTION_LABELS[action], width=32).grid(row=i, column=0, sticky="w", pady=4)
            lbl = ttk.Label(g, text=chord_text(self.profile["hotkeys"].get(action, [])), foreground=ACCENT2, width=30)
            lbl.grid(row=i, column=1, sticky="w")

            def setc(chord, action=action, lbl=lbl):
                self.profile["hotkeys"][action] = list(chord)
                lbl.configure(text=chord_text(chord))
                self.profile_changed()
            ttk.Button(g, text="🎮 Capturer", command=lambda s=setc: CaptureDialog(self, self.engine, s)).grid(
                row=i, column=2, padx=4)
            ttk.Button(g, text="Effacer", command=lambda s=setc: s([])).grid(row=i, column=3, padx=4)

    # ---- Paramètres
    def _build_settings_tab(self):
        f = self.tab_settings
        pf = ttk.LabelFrame(f, text="Profils")
        pf.pack(fill="x", padx=12, pady=10)
        for txt, cmd in [("Nouveau", self.new_profile), ("Dupliquer", lambda: self.new_profile(True)),
                         ("Renommer", self.rename_profile), ("Supprimer", self.delete_profile),
                         ("Importer…", self.import_profile), ("Exporter…", self.export_profile),
                         ("Ouvrir le dossier", self._open_folder)]:
            ttk.Button(pf, text=txt, command=cmd).pack(side="left", padx=4, pady=8)

        ef = ttk.LabelFrame(f, text="Moteur (redémarrage automatique)")
        ef.pack(fill="x", padx=12, pady=6)
        self.vp_var = tk.BooleanVar(value=self.cfg["virtual_pad"])
        self.km_var = tk.BooleanVar(value=self.cfg["keyboard_mouse"])
        mode = self.cfg.get("perf_mode") if self.cfg.get("perf_mode") in MODES else DEFAULT_MODE
        self.mode_var = tk.StringVar(value=MODES[mode]["label"])
        ttk.Checkbutton(ef, text="Manette virtuelle (ViGEmBus)", variable=self.vp_var,
                        command=self._apply_engine_settings).grid(row=0, column=0, sticky="w", padx=8, pady=4)
        ttk.Checkbutton(ef, text="Sortie clavier / souris", variable=self.km_var,
                        command=self._apply_engine_settings).grid(row=0, column=1, sticky="w", padx=8)
        ttk.Label(ef, text="Mode de performance").grid(row=1, column=0, sticky="w", padx=8, pady=4)
        cb = ttk.Combobox(ef, values=[m["label"] for m in MODES.values()], textvariable=self.mode_var,
                          state="readonly", width=40)
        cb.grid(row=1, column=1, sticky="w", padx=8)
        cb.bind("<<ComboboxSelected>>", lambda e: self._apply_engine_settings())
        self.perf_lbl = ttk.Label(ef, text="", style="Muted.TLabel", font=("Consolas", 10))
        self.perf_lbl.grid(row=2, column=0, columnspan=2, sticky="w", padx=8, pady=(2, 8))

        ttk.Button(ef, text="Installer le pilote ViGEmBus", command=self.install_vigembus).grid(
            row=0, column=2, sticky="w", padx=8)

        cf = ttk.LabelFrame(f, text="Manette physique")
        cf.pack(fill="x", padx=12, pady=6)
        ttk.Button(cf, text="🎯 Assistant de calibration", command=self.calibrate).pack(side="left", padx=6, pady=8)
        ttk.Button(cf, text="Réinitialiser la calibration", command=self._reset_calibration).pack(side="left", padx=6)
        ttk.Button(cf, text="Voir les valeurs brutes", command=self._raw_window).pack(side="left", padx=6)

        hf = ttk.LabelFrame(f, text="Aide")
        hf.pack(fill="both", expand=True, padx=12, pady=6)
        ttk.Label(hf, justify="left", style="Muted.TLabel", wraplength=1050, text=(
            "1. Installe ViGEmBus (installé automatiquement avec « pip install vgamepad »).\n"
            "2. Branche la DualSense en USB ou Bluetooth. Elle s'affiche dans l'onglet Manette.\n"
            "3. Installe HidHide et cache la DualSense aux jeux (ajoute python.exe / FRezzPadMapper.exe dans "
            "la liste des applis autorisées), sinon le jeu reçoit les appuis en double.\n"
            "4. Remappe, crée tes macros/combos : tout est sauvegardé automatiquement dans le dossier profiles/.\n\n"
            "Macros : un « Tap » = appui + relâche après la durée. « Appuyer » garde le bouton enfoncé jusqu'au "
            "« Relâcher ». Plusieurs cibles dans un pas = appui simultané. Le déclencheur peut être un combo "
            "(ex. L1 + R1). Le combo le plus long est prioritaire sur ses sous-combos.\n"
            "Clavier / souris : un déclencheur peut aussi être une touche, un bouton de souris (X1, X2, "
            "molette…) ou un mélange (ex. L1 + Shift). L'écoute du clavier ne s'active que si le profil "
            "en a besoin ; la touche déclencheuse est bloquée pour le jeu si « Bloquer » est coché. "
            "Le pas « Souris : déplacer » bouge la souris (instantané ou glissé sur une durée).\n"
            "Modes : Appui (N fois), Maintien (boucle tant que tenu), Toggle (start/stop), Relâchement, "
            "Double appui, Appui long. Vitesse × accélère/ralentit tous les délais ; Aléa ± humanise le timing.\n\n"
            "⚠ Respecte les règles des jeux en ligne : les macros/turbo peuvent être interdits en compétitif."
        )).pack(anchor="w", padx=8, pady=8)

    def _apply_engine_settings(self):
        self.cfg["virtual_pad"] = self.vp_var.get()
        self.cfg["keyboard_mouse"] = self.km_var.get()
        for k, m in MODES.items():
            if m["label"] == self.mode_var.get():
                self.cfg["perf_mode"] = k
        save_json(self.cfg_path, self.cfg)
        self.restart_engine()

    def install_vigembus(self):
        from ..output_backend import vigembus_installer
        msi = vigembus_installer()
        if not msi:
            messagebox.showinfo("ViGEmBus", "Installeur introuvable. Télécharge ViGEmBus sur :\n"
                                "https://github.com/nefarius/ViGEmBus/releases")
            return
        try:
            os.startfile(msi)  # type: ignore[attr-defined]
        except AttributeError:
            messagebox.showinfo("ViGEmBus", msi)
            return
        messagebox.showinfo("ViGEmBus", "Termine l'installation du pilote, puis clique OK :\n"
                            "le moteur va redémarrer.")
        self.restart_engine()

    def _reset_calibration(self):
        if os.path.exists(self.map_path):
            os.remove(self.map_path)
        from ..input_backend import DEFAULT_MAP
        self.engine.send("controller_map", DEFAULT_MAP)
        self.log("Calibration réinitialisée (DualSense par défaut)")

    def _open_folder(self):
        path = self.store.folder
        try:
            os.startfile(path)  # type: ignore[attr-defined]
        except AttributeError:
            messagebox.showinfo("Dossier des profils", path)

    def _raw_window(self):
        win = tk.Toplevel(self)
        win.title("Valeurs brutes SDL")
        self._with_raw(win)
        win.configure(bg=BG)
        lbl = ttk.Label(win, font=("Consolas", 10), justify="left")
        lbl.pack(padx=14, pady=14)

        def upd():
            if not win.winfo_exists():
                return
            raw = self.engine.snapshot().get("raw")
            if raw:
                b = " ".join(f"{i}:{'■' if v else '·'}" for i, v in enumerate(raw["buttons"]))
                a = "\n".join(f"axe {i}: {v:+.3f}" for i, v in enumerate(raw["axes"]))
                lbl.configure(text=f"Boutons\n{b}\n\nAxes\n{a}\n\nHats : {raw['hats']}")
            else:
                lbl.configure(text="Aucune manette")
            win.after(50, upd)
        upd()

    # ---- Journal
    def _build_log_tab(self):
        self.log_text = tk.Text(self.tab_log, bg="#262a36", fg=FG, borderwidth=0, font=("Consolas", 10),
                                state="disabled")
        self.log_text.pack(fill="both", expand=True, padx=10, pady=10)

    # --------------------------------------------------------------- boucle UI
    def toggle_pause(self):
        snap = self.engine.snapshot()
        self.engine.send("pause", not snap.get("paused", False))

    def _tick(self):
        hidden = self.state() == "iconic"
        snap = self.engine.snapshot() if not hidden else None
        if snap:
            st = snap.get("stats", {})
            on_pad_tab = self.nb.select() == str(self.tab_pad)
            if on_pad_tab:
                self._update_pad_tab(snap)
            state = "⏸ EN PAUSE" if snap["paused"] else "▶ actif"
            rec = "  ● REC" if snap["recording"] else ""
            self.status_lbl.configure(
                text=f"{state}{rec}   {st.get('hz', 0):.0f} Hz · {st.get('proc_us', 0):.0f} µs",
                foreground=WARN if snap["paused"] else MUTED)
            self.pause_btn.configure(text="▶ Reprendre" if snap["paused"] else "⏸ Pause")
            if self.nb.select() == str(self.tab_settings):
                self.perf_lbl.configure(text=(
                    f"Boucle : {st.get('hz', 0):.0f} Hz   traitement moyen : {st.get('proc_us', 0):.1f} µs   "
                    f"pire : {st.get('max_us', 0):.0f} µs   retard max du réveil : {st.get('late_ms', 0):.2f} ms"))
        while True:
            try:
                kind, data = self.engine.events.get_nowait()
            except queue.Empty:
                break
            if kind == "action":
                if data == "next_profile":
                    self.cycle_profile(1)
                elif data == "prev_profile":
                    self.cycle_profile(-1)
                elif data == "toggle_pause":
                    self.log("Pause" if self.engine.snapshot().get("paused") else "Reprise")
            elif kind == "recorded":
                self.tab_macros.on_recorded(data)
            elif kind == "device":
                self.engine.send("list_devices")
            elif kind == "devices":
                self.dev_cb.configure(values=["Auto (DualSense en priorité)"] + [f"{i}: {n}" for i, n in data])
                if not self.dev_var.get():
                    want = self.cfg.get("device_name", "")
                    self.dev_var.set(next((f"{i}: {n}" for i, n in data if n == want),
                                          "Auto (DualSense en priorité)"))
            elif kind == "log":
                self.log(data)
                if "manette virtuelle indisponible" in data and not self.demo and not getattr(self, "_asked_vigem", 0):
                    self._asked_vigem = True
                    if messagebox.askyesno("Pilote manquant",
                                           "Le pilote ViGEmBus (manette virtuelle) n'est pas installé.\n"
                                           "L'installer maintenant ?"):
                        self.install_vigembus()
            elif kind == "error":
                messagebox.showerror("Erreur du moteur", data[-1500:])
        while True:
            try:
                line = self.log_queue.get_nowait()
            except queue.Empty:
                break
            self.log_text.configure(state="normal")
            self.log_text.insert("end", line + "\n")
            self.log_text.see("end")
            self.log_text.configure(state="disabled")
        if not getattr(self, "_listed", False):
            self._listed = True
            self.after(800, lambda: self.engine.send("list_devices"))
        if not self.engine.alive() and not self.engine_dead_shown:
            self.engine_dead_shown = True
            self.status_lbl.configure(text="✖ moteur arrêté", foreground=BAD)
            if messagebox.askyesno("Moteur", "Le moteur s'est arrêté (voir Journal). Le relancer ?"):
                self.restart_engine()
                self.engine_dead_shown = False
        # fenêtre réduite : l'interface se met en veille pour laisser tout le CPU au moteur
        self.after(500 if hidden else 33, self._tick)

    def _update_pad_tab(self, snap):
        self.view.update_state(snap)
        if snap["connected"]:
            self.conn_lbl.configure(text=f"✔ {snap['device']}", foreground=OK)
        else:
            self.conn_lbl.configure(text="✖ Aucune manette détectée — branche ta DualSense", foreground=BAD)
        batt = snap.get("battery")
        self.batt_lbl.configure(text=f"Batterie : {batt}" if batt and batt != "unknown" else "")
        items = [f"▶ {n}  {int(p * 100)}%" for n, p in snap["running"]] or ["—"]
        if list(self.running_lb.get(0, "end")) != items:
            self.running_lb.delete(0, "end")
            for it in items:
                self.running_lb.insert("end", it)
        ia, oa = snap["axes"], snap["out_axes"]
        txt = "\n".join(f"{a:>3}  {ia.get(a, 0):+.2f}  →  {oa.get(a, 0):+.2f}"
                        for a in ("LX", "LY", "RX", "RY", "L2", "R2"))
        if self.axes_lbl.cget("text") != txt:
            self.axes_lbl.configure(text=txt)

    def on_close(self):
        if self._save_job:
            self.after_cancel(self._save_job)
            self._autosave()
        save_json(self.cfg_path, self.cfg)
        self.engine.stop()
        self.destroy()
