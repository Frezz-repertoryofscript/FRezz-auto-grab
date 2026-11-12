"""Thème sombre et petits widgets réutilisables."""

import tkinter as tk
from tkinter import ttk

BG = "#14161c"
PANEL = "#1d2029"
FIELD = "#262a36"
FG = "#e6e8ef"
MUTED = "#8a90a2"
ACCENT = "#2f7cff"
ACCENT2 = "#00c2ff"
OK = "#2ecc71"
WARN = "#f5a623"
BAD = "#ff4d5e"


def apply_theme(root):
    root.configure(bg=BG)
    s = ttk.Style(root)
    s.theme_use("clam")
    s.configure(".", background=BG, foreground=FG, fieldbackground=FIELD, bordercolor="#2c3140",
                lightcolor=PANEL, darkcolor=PANEL, troughcolor=FIELD, font=("Segoe UI", 10))
    s.configure("TFrame", background=BG)
    s.configure("Panel.TFrame", background=PANEL)
    s.configure("TLabel", background=BG, foreground=FG)
    s.configure("Panel.TLabel", background=PANEL)
    s.configure("Muted.TLabel", foreground=MUTED)
    s.configure("Title.TLabel", font=("Segoe UI Semibold", 15), foreground=ACCENT2)
    s.configure("H.TLabel", font=("Segoe UI Semibold", 11))
    s.configure("TLabelframe", background=BG, bordercolor="#2c3140")
    s.configure("TLabelframe.Label", background=BG, foreground=ACCENT2, font=("Segoe UI Semibold", 10))
    s.configure("TButton", background=FIELD, foreground=FG, padding=(10, 4), borderwidth=0)
    s.map("TButton", background=[("active", "#323849"), ("pressed", ACCENT)])
    s.configure("Accent.TButton", background=ACCENT, foreground="white")
    s.map("Accent.TButton", background=[("active", "#4a8fff")])
    s.configure("Danger.TButton", background="#4a1f27")
    s.map("Danger.TButton", background=[("active", BAD)])
    s.configure("TCheckbutton", background=BG, foreground=FG)
    s.map("TCheckbutton", background=[("active", BG)])
    s.configure("TRadiobutton", background=BG, foreground=FG)
    s.map("TRadiobutton", background=[("active", BG)])
    s.configure("TNotebook", background=BG, borderwidth=0)
    s.configure("TNotebook.Tab", background=PANEL, foreground=MUTED, padding=(14, 6))
    s.map("TNotebook.Tab", background=[("selected", FIELD)], foreground=[("selected", FG)])
    s.configure("TCombobox", fieldbackground=FIELD, background=FIELD, foreground=FG, arrowcolor=FG)
    s.map("TCombobox", fieldbackground=[("readonly", FIELD)], foreground=[("readonly", FG)])
    s.configure("TEntry", fieldbackground=FIELD, foreground=FG, insertcolor=FG)
    s.configure("TSpinbox", fieldbackground=FIELD, foreground=FG, arrowcolor=FG, insertcolor=FG)
    s.configure("Treeview", background=FIELD, fieldbackground=FIELD, foreground=FG, rowheight=24,
                borderwidth=0)
    s.map("Treeview", background=[("selected", ACCENT)])
    s.configure("Treeview.Heading", background=PANEL, foreground=MUTED)
    s.configure("Horizontal.TScale", background=BG, troughcolor=FIELD)
    s.configure("Horizontal.TProgressbar", background=ACCENT, troughcolor=FIELD)
    root.option_add("*TCombobox*Listbox.background", FIELD)
    root.option_add("*TCombobox*Listbox.foreground", FG)
    root.option_add("*TCombobox*Listbox.selectBackground", ACCENT)


def listbox(parent, **kw):
    return tk.Listbox(parent, bg=FIELD, fg=FG, selectbackground=ACCENT, selectforeground="white",
                      highlightthickness=0, borderwidth=0, activestyle="none", font=("Segoe UI", 10), **kw)


class ScrollFrame(ttk.Frame):
    """Cadre vertical scrollable (molette supportée)."""

    def __init__(self, parent, **kw):
        super().__init__(parent, **kw)
        self.canvas = tk.Canvas(self, bg=BG, highlightthickness=0, borderwidth=0)
        self.vsb = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        self.inner = ttk.Frame(self.canvas)
        self.inner.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.win = self.canvas.create_window((0, 0), window=self.inner, anchor="nw")
        self.canvas.bind("<Configure>", lambda e: self.canvas.itemconfigure(self.win, width=e.width))
        self.canvas.configure(yscrollcommand=self.vsb.set)
        self.canvas.pack(side="left", fill="both", expand=True)
        self.vsb.pack(side="right", fill="y")
        self.inner.bind("<Enter>", lambda e: self.canvas.bind_all("<MouseWheel>", self._wheel))
        self.inner.bind("<Leave>", lambda e: self.canvas.unbind_all("<MouseWheel>"))

    def _wheel(self, e):
        self.canvas.yview_scroll(int(-e.delta / 120) or (-1 if e.delta > 0 else 1), "units")


class LabeledScale(ttk.Frame):
    """Libellé + curseur + valeur ; appelle on_change(valeur)."""

    def __init__(self, parent, text, frm, to, value, on_change, digits=2, width=220):
        super().__init__(parent)
        self.digits = digits
        self.on_change = on_change
        self.var = tk.DoubleVar(value=value)
        ttk.Label(self, text=text, width=22).pack(side="left")
        self.scale = ttk.Scale(self, from_=frm, to=to, variable=self.var, length=width,
                               command=lambda _=None: self._changed())
        self.scale.pack(side="left", padx=6)
        self.val = ttk.Label(self, width=7, style="Muted.TLabel")
        self.val.pack(side="left")
        self._show()

    def _show(self):
        v = self.var.get()
        self.val.configure(text=f"{v:.{self.digits}f}" if self.digits else f"{int(round(v))}")

    def _changed(self):
        self._show()
        v = round(self.var.get(), self.digits) if self.digits else int(round(self.var.get()))
        self.on_change(v)

    def set(self, v):
        self.var.set(v)
        self._show()


def chord_text(chord):
    from ..constants import LABELS
    return " + ".join(LABELS.get(b, b) for b in chord) if chord else "— aucun —"
