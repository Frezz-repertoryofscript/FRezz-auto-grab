"""Onglet Macros : liste, éditeur, pas, enregistrement, test, modèles."""

import copy
import json
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

from ..constants import MACRO_MODES, STEP_TYPES, PHYS_BUTTONS, LABELS, SHORT, target_label, kbm_inputs, input_label
from ..macro import macro_duration_ms
from ..profile import default_macro, normalize_macro
from ..templates import TEMPLATES
from .dialogs import StepDialog, CaptureDialog
from .widgets import listbox, chord_text, OK, BAD


def step_text(s):
    t = s["type"]
    if t in ("tap", "press", "release"):
        what = " + ".join(target_label(x) for x in s["targets"]) or "—"
        return STEP_TYPES[t], what, f"{s['ms']} ms" if t == "tap" else ""
    if t == "wait":
        return STEP_TYPES[t], "", f"{s['ms']} ms"
    if t == "axis":
        return STEP_TYPES[t], s["axis"], f"{s['value']:+.2f}"
    if t == "mouse_move":
        return STEP_TYPES[t], f"X {s['dx']:+d}   Y {s['dy']:+d}", f"{s['ms']} ms" if s["ms"] else "instantané"
    return STEP_TYPES[t], "", ""


class MacroTab(ttk.Frame):
    def __init__(self, parent, app):
        super().__init__(parent)
        self.app = app
        self.cur = None          # index de la macro éditée
        self.loading = False
        self.recording = False
        self._snapshot = None
        self._build()

    @property
    def macros(self):
        return self.app.profile["macros"]

    # ------------------------------------------------------------- construction
    def _build(self):
        left = ttk.Frame(self)
        left.pack(side="left", fill="y", padx=(10, 6), pady=10)
        ttk.Label(left, text="Liste des macros", style="H.TLabel").pack(anchor="w")
        self.lb = listbox(left, width=34, height=22, exportselection=False)
        self.lb.pack(fill="y", expand=True, pady=6)
        self.lb.bind("<<ListboxSelect>>", lambda e: self._select())
        g = ttk.Frame(left)
        g.pack(fill="x")
        btns = [("Nouvelle", self.new), ("Dupliquer", self.duplicate), ("Supprimer", self.delete),
                ("▲", lambda: self.move(-1)), ("▼", lambda: self.move(1)), ("Modèles…", self.templates_menu),
                ("Importer", self.import_), ("Exporter", self.export)]
        for i, (txt, cmd) in enumerate(btns):
            ttk.Button(g, text=txt, command=cmd, width=10).grid(row=i // 2, column=i % 2, padx=2, pady=2,
                                                               sticky="we")
        self.tpl_menu = tk.Menu(self, tearoff=0)
        for name in TEMPLATES:
            self.tpl_menu.add_command(label=name, command=lambda n=name: self.add_template(n))

        self.right = right = ttk.Frame(self)
        right.pack(side="left", fill="both", expand=True, padx=(6, 10), pady=10)

        # --- Paramètres de la macro
        pf = ttk.LabelFrame(right, text="Paramètres")
        pf.pack(fill="x")
        self.v = {
            "name": tk.StringVar(), "enabled": tk.BooleanVar(), "mode": tk.StringVar(),
            "repeat": tk.StringVar(), "speed": tk.StringVar(), "jitter_ms": tk.StringVar(),
            "block_trigger": tk.BooleanVar(), "hold_ms": tk.StringVar(), "double_ms": tk.StringVar(),
        }
        ttk.Label(pf, text="Nom").grid(row=0, column=0, sticky="w", padx=6, pady=3)
        e = ttk.Entry(pf, textvariable=self.v["name"], width=30)
        e.grid(row=0, column=1, sticky="w", padx=6)
        e.bind("<FocusOut>", lambda ev: self._rename())
        e.bind("<Return>", lambda ev: self._rename())
        chk = ttk.Frame(pf)
        chk.grid(row=0, column=2, sticky="w", padx=6)
        ttk.Checkbutton(chk, text="Activée", variable=self.v["enabled"], command=self._save_fields).pack(
            side="left", padx=(0, 12))
        ttk.Checkbutton(chk, text="Bloquer les boutons déclencheurs", variable=self.v["block_trigger"],
                        command=self._save_fields).pack(side="left")

        ttk.Label(pf, text="Déclencheur").grid(row=1, column=0, sticky="w", padx=6, pady=3)
        self.trig_lbl = ttk.Label(pf, text="", foreground="#00c2ff")
        self.trig_lbl.grid(row=1, column=1, sticky="w", padx=6)
        tb = ttk.Frame(pf)
        tb.grid(row=1, column=2, sticky="w", padx=6)
        ttk.Button(tb, text="🎮 Capturer", command=self.capture_trigger).pack(side="left", padx=(0, 2))
        ttk.Button(tb, text="Choisir…", command=self.choose_trigger).pack(side="left", padx=2)
        ttk.Button(tb, text="Effacer", command=lambda: self._set_trigger([])).pack(side="left", padx=2)

        ttk.Label(pf, text="Mode").grid(row=2, column=0, sticky="w", padx=6, pady=3)
        cb = ttk.Combobox(pf, values=list(MACRO_MODES.values()), state="readonly", width=32,
                          textvariable=self.v["mode"])
        cb.grid(row=2, column=1, sticky="w", padx=6)
        cb.bind("<<ComboboxSelected>>", lambda e: self._save_fields())

        specs = [[("repeat", "Répétitions (0=∞)", 0, 100000, 1), ("speed", "Vitesse ×", 0.05, 20, 0.05),
                  ("jitter_ms", "Aléa ± ms", 0, 5000, 1)],
                 [("hold_ms", "Appui long (ms)", 50, 10000, 50), ("double_ms", "Double appui (ms)", 80, 2000, 10)]]
        for r, line in enumerate(specs):
            row = ttk.Frame(pf)
            row.grid(row=3 + r, column=0, columnspan=3, sticky="w", padx=6, pady=(3, 6 if r else 0))
            for key, label, frm, to, inc in line:
                ttk.Label(row, text=label).pack(side="left", padx=(0, 4))
                sp = ttk.Spinbox(row, from_=frm, to=to, increment=inc, textvariable=self.v[key], width=7,
                                 command=self._save_fields)
                sp.pack(side="left", padx=(0, 16))
                sp.bind("<FocusOut>", lambda e: self._save_fields())
                sp.bind("<Return>", lambda e: self._save_fields())

        run = ttk.Frame(right)
        run.pack(side="bottom", fill="x", pady=(8, 0))
        self.rec_btn = ttk.Button(run, text="● Enregistrer (manette / clavier / souris)", command=self.toggle_record)
        self.rec_btn.pack(side="left", padx=2)
        ttk.Button(run, text="▶ Tester", style="Accent.TButton", command=self.test).pack(side="left", padx=2)
        ttk.Button(run, text="■ Stopper les macros", command=lambda: self.app.engine.send("stop_macros")).pack(
            side="left", padx=2)
        self.rec_lbl = ttk.Label(run, text="", foreground=BAD)
        self.rec_lbl.pack(side="left", padx=10)


        # --- Pas
        sf = ttk.LabelFrame(right, text="Séquence (combo) — double-clic pour modifier")
        sf.pack(fill="both", expand=True, pady=(8, 0))
        bar = ttk.Frame(sf)
        bar.pack(fill="x", padx=4, pady=4)
        for txt, typ in [("+ Tap", "tap"), ("+ Appuyer", "press"), ("+ Relâcher", "release"),
                         ("+ Attendre", "wait"), ("+ Axe", "axis"), ("+ Souris", "mouse_move"),
                         ("+ Tout relâcher", "release_all")]:
            ttk.Button(bar, text=txt, style="Small.TButton", width=len(txt),
                       command=lambda t=typ: self.add_step(t)).pack(side="left", padx=2)
        quick = ttk.Frame(sf)
        quick.pack(fill="x", padx=4)
        ttk.Label(quick, text="Tap rapide :", style="Muted.TLabel").pack(side="left", padx=(2, 4))
        for b in ["CROSS", "CIRCLE", "SQUARE", "TRIANGLE", "L1", "R1", "L2", "R2",
                  "DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT"]:
            ttk.Button(quick, text=SHORT.get(b, b), width=3,
                       command=lambda x=b: self.quick_tap(x)).pack(side="left", padx=1)

        cols = ("n", "type", "what", "val")
        self.tree = ttk.Treeview(sf, columns=cols, show="headings", height=9, selectmode="extended")
        for c, txt, w in [("n", "#", 40), ("type", "Action", 160), ("what", "Cible", 320), ("val", "Durée / valeur", 120)]:
            self.tree.heading(c, text=txt)
            self.tree.column(c, width=w, anchor="w", stretch=c == "what")
        self.tree.pack(fill="both", expand=True, padx=4, pady=4)
        self.tree.bind("<Double-1>", lambda e: self.edit_step())
        self.tree.bind("<Delete>", lambda e: self.delete_steps())

        bar2 = ttk.Frame(sf)
        bar2.pack(fill="x", padx=4, pady=(0, 6))
        for txt, cmd in [("Modifier", self.edit_step), ("Dupliquer", self.dup_steps),
                         ("Supprimer", self.delete_steps), ("▲", lambda: self.move_step(-1)),
                         ("▼", lambda: self.move_step(1)), ("Tout effacer", self.clear_steps)]:
            ttk.Button(bar2, text=txt, command=cmd).pack(side="left", padx=2)
        self.dur_lbl = ttk.Label(bar2, text="", style="Muted.TLabel")
        self.dur_lbl.pack(side="right", padx=6)

        self.refresh()

    # ----------------------------------------------------------------- liste
    def refresh(self, keep=True):
        sel = self.cur if keep else None
        self.lb.delete(0, "end")
        for m in self.macros:
            flag = "●" if m["enabled"] else "○"
            trig = chord_text(m["trigger"]) if m["trigger"] else "(bouton remappé / test)"
            self.lb.insert("end", f"{flag} {m['name']}  —  {trig}")
            self.lb.itemconfigure("end", foreground=OK if m["enabled"] else "#8a90a2")
        if sel is not None and sel < len(self.macros):
            self.lb.selection_set(sel)
            self.cur = sel
        elif self.macros:
            self.lb.selection_set(0)
            self.cur = 0
        else:
            self.cur = None
        self._load()

    def _select(self):
        sel = self.lb.curselection()
        if sel and sel[0] != self.cur:
            new = sel[0]
            self._rename()
            self._save_fields()
            self.cur = new
            self.lb.selection_clear(0, "end")
            self.lb.selection_set(new)
            self._load()

    def macro(self):
        if self.cur is None or self.cur >= len(self.macros):
            return None
        return self.macros[self.cur]

    def _load(self):
        m = self.macro()
        self.loading = True
        state = "normal" if m else "disabled"
        for child in self.right.winfo_children():
            _set_state(child, state)
        if m:
            for k in ("name", "enabled", "block_trigger"):
                self.v[k].set(m[k])
            self.v["mode"].set(MACRO_MODES[m["mode"]])
            for k in ("repeat", "jitter_ms", "hold_ms", "double_ms"):
                self.v[k].set(str(m[k]))
            self.v["speed"].set(f"{m['speed']:g}")
            self.trig_lbl.configure(text=chord_text(m["trigger"]))
        self._snapshot = copy.deepcopy(m) if m else None
        self._fill_steps()
        self.loading = False

    def _fill_steps(self, select=()):
        self.tree.delete(*self.tree.get_children())
        m = self.macro()
        if not m:
            self.dur_lbl.configure(text="")
            return
        for i, s in enumerate(m["steps"]):
            self.tree.insert("", "end", iid=str(i), values=(i + 1, *step_text(s)))
        for i in select:
            if 0 <= i < len(m["steps"]):
                self.tree.selection_add(str(i))
                self.tree.see(str(i))
        self.dur_lbl.configure(text=self._dur_text(m))

    def changed(self):
        self.refresh()
        self.app.profile_changed()

    # -------------------------------------------------------------- champs
    def _save_fields(self):
        m = self.macro()
        if not m or self.loading:
            return
        m["enabled"] = bool(self.v["enabled"].get())
        m["block_trigger"] = bool(self.v["block_trigger"].get())
        for k, v in MACRO_MODES.items():
            if v == self.v["mode"].get():
                m["mode"] = k
        for k in ("repeat", "jitter_ms", "hold_ms", "double_ms", "speed"):
            m[k] = self.v[k].get()
        new = normalize_macro(m)
        if new == self._snapshot:
            self.macros[self.cur] = new
            return
        self.macros[self.cur] = new
        self._snapshot = copy.deepcopy(new)
        self._update_list_line()
        self.dur_lbl.configure(text=self._dur_text(new))
        self.app.profile_changed()

    @staticmethod
    def _dur_text(m):
        return f"{len(m['steps'])} pas · cycle ≈ {macro_duration_ms(m):.0f} ms"

    def _update_list_line(self):
        m = self.macro()
        flag = "●" if m["enabled"] else "○"
        trig = chord_text(m["trigger"]) if m["trigger"] else "(bouton remappé / test)"
        self.lb.delete(self.cur)
        self.lb.insert(self.cur, f"{flag} {m['name']}  —  {trig}")
        self.lb.itemconfigure(self.cur, foreground=OK if m["enabled"] else "#8a90a2")
        self.lb.selection_set(self.cur)

    def _rename(self):
        m = self.macro()
        if not m or self.loading:
            return
        new = self.v["name"].get().strip()
        if not new or new == m["name"]:
            self.v["name"].set(m["name"])
            return
        if any(x["name"] == new for x in self.macros):
            messagebox.showwarning("Nom déjà pris", f"Une macro « {new} » existe déjà.")
            self.v["name"].set(m["name"])
            return
        old = m["name"]
        m["name"] = new
        # met à jour les boutons qui pointaient vers cette macro
        for b, t in self.app.profile["buttons"].items():
            if t == f"macro:{old}":
                self.app.profile["buttons"][b] = f"macro:{new}"
        self.app.refresh_remap()
        self.changed()

    def _set_trigger(self, chord):
        m = self.macro()
        if not m:
            return
        m["trigger"] = list(chord)
        self._snapshot = copy.deepcopy(m)
        self.trig_lbl.configure(text=chord_text(m["trigger"]))
        self._update_list_line()
        self.app.profile_changed()

    def capture_trigger(self):
        if self.macro():
            CaptureDialog(self, self.app.engine, self._set_trigger)

    def choose_trigger(self):
        m = self.macro()
        if not m:
            return
        win = tk.Toplevel(self)
        win.title("Déclencheur (combo)")
        win.transient(self)
        win.configure(bg="#14161c")
        ttk.Label(win, text="Coche un ou plusieurs boutons (plusieurs = combo simultané)").grid(
            row=0, column=0, columnspan=4, padx=10, pady=8, sticky="w")
        vars_ = {}
        for i, b in enumerate(PHYS_BUTTONS):
            vars_[b] = tk.BooleanVar(value=b in m["trigger"])
            ttk.Checkbutton(win, text=LABELS[b], variable=vars_[b]).grid(
                row=1 + i // 4, column=i % 4, sticky="w", padx=10, pady=2)

        kf = ttk.LabelFrame(win, text="Clavier / souris (peut se combiner avec la manette)")
        kf.grid(row=10, column=0, columnspan=4, sticky="we", padx=10, pady=8)
        kbm = [b for b in m["trigger"] if ":" in b]
        lb = listbox(kf, height=4, width=30)
        lb.grid(row=0, column=0, rowspan=3, padx=6, pady=6)

        def fill():
            lb.delete(0, "end")
            for k in kbm:
                lb.insert("end", f"{input_label(k)}   ({k})")
        fill()
        names = {f"{input_label(k)}  ({k})": k for k in kbm_inputs()}
        add_var = tk.StringVar()
        ttk.Combobox(kf, values=list(names), textvariable=add_var, width=26, state="readonly").grid(
            row=0, column=1, padx=6, pady=4)

        def add():
            k = names.get(add_var.get())
            if k and k not in kbm:
                kbm.append(k)
                fill()

        def remove():
            sel = lb.curselection()
            if sel:
                del kbm[sel[0]]
                fill()
        ttk.Button(kf, text="Ajouter", command=add).grid(row=1, column=1, sticky="we", padx=6)
        ttk.Button(kf, text="Retirer", command=remove).grid(row=2, column=1, sticky="we", padx=6)

        def ok():
            self._set_trigger([b for b in PHYS_BUTTONS if vars_[b].get()] + kbm)
            win.destroy()
        ttk.Button(win, text="OK", style="Accent.TButton", command=ok).grid(
            row=20, column=3, sticky="e", padx=10, pady=10)
        win.grab_set()

    # ------------------------------------------------------ gestion liste
    def _unique(self, name):
        names = {m["name"] for m in self.macros}
        base, i, out = name, 2, name
        while out in names:
            out = f"{base} ({i})"
            i += 1
        return out

    def _append(self, m):
        self._save_fields()
        m["name"] = self._unique(m["name"])
        self.macros.append(normalize_macro(m))
        self.cur = len(self.macros) - 1
        self.changed()
        self.app.refresh_remap()

    def new(self):
        self._append(default_macro("Nouvelle macro"))

    def duplicate(self):
        m = self.macro()
        if m:
            c = copy.deepcopy(m)
            c["trigger"] = []
            self._append(c)

    def delete(self):
        m = self.macro()
        if not m or not messagebox.askyesno("Supprimer", f"Supprimer la macro « {m['name']} » ?"):
            return
        del self.macros[self.cur]
        for b, t in self.app.profile["buttons"].items():
            if t == f"macro:{m['name']}":
                self.app.profile["buttons"][b] = "none"
        self.cur = min(self.cur, len(self.macros) - 1) if self.macros else None
        self.changed()
        self.app.refresh_remap()

    def move(self, d):
        i = self.cur
        if i is None or not 0 <= i + d < len(self.macros):
            return
        self.macros[i], self.macros[i + d] = self.macros[i + d], self.macros[i]
        self.cur = i + d
        self.changed()

    def templates_menu(self):
        x, y = self.winfo_pointerx(), self.winfo_pointery()
        self.tpl_menu.tk_popup(x, y)

    def add_template(self, name):
        self._append(TEMPLATES[name]())

    def import_(self):
        path = filedialog.askopenfilename(filetypes=[("Macros JSON", "*.json")])
        if not path:
            return
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
            items = data.get("macros", [data]) if isinstance(data, dict) else data
            for m in items:
                self._append(normalize_macro(m))
        except (OSError, ValueError) as e:
            messagebox.showerror("Import", f"Fichier invalide : {e}")

    def export(self):
        m = self.macro()
        if not m:
            return
        path = filedialog.asksaveasfilename(defaultextension=".json", initialfile=m["name"] + ".json",
                                            filetypes=[("Macros JSON", "*.json")])
        if path:
            with open(path, "w", encoding="utf-8") as fh:
                json.dump({"macros": [m]}, fh, indent=2, ensure_ascii=False)

    # ---------------------------------------------------------------- pas
    def _sel(self):
        return sorted(int(i) for i in self.tree.selection())

    def _steps_changed(self, select=()):
        m = self.macro()
        self.macros[self.cur] = normalize_macro(m)
        self._snapshot = copy.deepcopy(self.macros[self.cur])
        self._fill_steps(select)
        self.app.profile_changed()

    def add_step(self, typ):
        m = self.macro()
        if not m:
            return
        sel = self._sel()
        pos = (sel[-1] + 1) if sel else len(m["steps"])
        defaults = {"tap": {"type": "tap", "targets": [], "ms": 50},
                    "press": {"type": "press", "targets": []},
                    "release": {"type": "release", "targets": []},
                    "wait": {"type": "wait", "ms": 100},
                    "axis": {"type": "axis", "axis": "LX", "value": 1.0},
                    "mouse_move": {"type": "mouse_move", "dx": 0, "dy": 20, "ms": 50}}
        if typ == "release_all":
            m["steps"].insert(pos, {"type": "release_all"})
            self._steps_changed([pos])
            return

        def ok(step):
            m["steps"].insert(pos, step)
            self._steps_changed([pos])
        StepDialog(self, defaults[typ], ok)

    def quick_tap(self, button):
        m = self.macro()
        if not m:
            return
        sel = self._sel()
        pos = (sel[-1] + 1) if sel else len(m["steps"])
        new = [{"type": "tap", "targets": [f"pad:{button}"], "ms": 50}]
        if pos > 0:
            new.insert(0, {"type": "wait", "ms": 50})
        m["steps"][pos:pos] = new
        self._steps_changed([pos + len(new) - 1])

    def edit_step(self):
        m, sel = self.macro(), self._sel()
        if not m or not sel:
            return
        i = sel[0]

        def ok(step):
            m["steps"][i] = step
            self._steps_changed([i])
        StepDialog(self, m["steps"][i], ok)

    def dup_steps(self):
        m, sel = self.macro(), self._sel()
        if not m or not sel:
            return
        block = [copy.deepcopy(m["steps"][i]) for i in sel]
        pos = sel[-1] + 1
        m["steps"][pos:pos] = block
        self._steps_changed(range(pos, pos + len(block)))

    def delete_steps(self):
        m, sel = self.macro(), self._sel()
        if not m or not sel:
            return
        for i in reversed(sel):
            del m["steps"][i]
        self._steps_changed([min(sel[0], len(m["steps"]) - 1)])

    def move_step(self, d):
        m, sel = self.macro(), self._sel()
        if not m or not sel:
            return
        if (d < 0 and sel[0] == 0) or (d > 0 and sel[-1] == len(m["steps"]) - 1):
            return
        steps = m["steps"]
        order = sel if d < 0 else list(reversed(sel))
        for i in order:
            steps[i], steps[i + d] = steps[i + d], steps[i]
        self._steps_changed([i + d for i in sel])

    def clear_steps(self):
        m = self.macro()
        if m and m["steps"] and messagebox.askyesno("Effacer", "Effacer tous les pas de cette macro ?"):
            m["steps"] = []
            self._steps_changed()

    # ------------------------------------------------- enregistrement / test
    def toggle_record(self):
        if not self.macro():
            return
        if not self.recording:
            self.recording = True
            self.rec_btn.configure(text="■ Arrêter l'enregistrement")
            self.rec_lbl.configure(text="● REC — joue ton combo (manette, clavier, souris)")
            self.app.engine.send("record_start")
        else:
            self.recording = False
            self.rec_btn.configure(text="● Enregistrer (manette / clavier / souris)")
            self.rec_lbl.configure(text="")
            self.app.engine.send("record_stop")

    def on_recorded(self, steps):
        m = self.macro()
        if not m:
            return
        if not steps:
            messagebox.showinfo("Enregistrement", "Rien n'a été enregistré.")
            return
        if m["steps"] and not messagebox.askyesno(
                "Enregistrement", f"{len(steps)} pas enregistrés.\nOui = remplacer la séquence, Non = ajouter à la fin"):
            m["steps"].extend(steps)
        else:
            m["steps"] = steps
        self._steps_changed()

    def test(self):
        m = self.macro()
        if m:
            self._save_fields()
            self.app.engine.send("run_macro", copy.deepcopy(self.macros[self.cur]))


def _set_state(widget, state):
    try:
        if isinstance(widget, (ttk.Button, ttk.Entry, ttk.Checkbutton, ttk.Spinbox)):
            widget.state(["!disabled"] if state == "normal" else ["disabled"])
        elif isinstance(widget, ttk.Combobox):
            widget.state(["!disabled", "readonly"] if state == "normal" else ["disabled"])
    except tk.TclError:
        pass
    for c in widget.winfo_children():
        _set_state(c, state)
