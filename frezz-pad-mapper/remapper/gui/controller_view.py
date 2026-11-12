"""Visualisation en direct de la DualSense."""

import tkinter as tk

from .widgets import BG, PANEL, FIELD, FG, MUTED, ACCENT, ACCENT2

W, H = 560, 330

# position (x, y), forme, libellé
LAYOUT = {
    "L2": ((110, 22), "trig", "L2"), "R2": ((450, 22), "trig", "R2"),
    "L1": ((110, 62), "bump", "L1"), "R1": ((450, 62), "bump", "R1"),
    "DPAD_UP": ((110, 118), "sq", "↑"), "DPAD_DOWN": ((110, 178), "sq", "↓"),
    "DPAD_LEFT": ((80, 148), "sq", "←"), "DPAD_RIGHT": ((140, 148), "sq", "→"),
    "TRIANGLE": ((450, 112), "ci", "△"), "CROSS": ((450, 184), "ci", "✕"),
    "SQUARE": ((414, 148), "ci", "□"), "CIRCLE": ((486, 148), "ci", "○"),
    "CREATE": ((190, 100), "pill", "Cr"), "OPTIONS": ((370, 100), "pill", "Op"),
    "TOUCHPAD": ((280, 112), "pad", ""), "PS": ((280, 196), "ci", "PS"), "MUTE": ((280, 226), "pill", "mic"),
    "L3": ((200, 230), "stick", "L3"), "R3": ((360, 230), "stick", "R3"),
}


class ControllerView(tk.Canvas):
    def __init__(self, parent):
        super().__init__(parent, width=W, height=H, bg=BG, highlightthickness=0)
        self.items = {}
        self._draw_body()
        for name, ((x, y), shape, label) in LAYOUT.items():
            self.items[name] = self._shape(x, y, shape)
            if label:
                self.create_text(x, y if shape != "trig" else y, text=label, fill=FG,
                                 font=("Segoe UI Semibold", 9))
        self.trig_fill = {}
        for side in ("L2", "R2"):
            x, y = LAYOUT[side][0]
            self.trig_fill[side] = self.create_rectangle(x - 40, y + 9, x - 40, y + 13, fill=ACCENT2, width=0)
        self.dots = {}
        for side, name in (("LEFT", "L3"), ("RIGHT", "R3")):
            x, y = LAYOUT[name][0]
            self.dots[side] = self.create_oval(x - 6, y - 6, x + 6, y + 6, fill=ACCENT2, outline="")
        self.out_text = self.create_text(10, H - 10, anchor="sw", fill=MUTED, font=("Consolas", 9), text="")

    def _draw_body(self):
        pts = [60, 80, 500, 80, 545, 230, 520, 300, 450, 290, 400, 250, 160, 250, 110, 290, 40, 300, 15, 230]
        self.create_polygon(pts, smooth=True, fill=PANEL, outline="#2c3140", width=2)

    def _shape(self, x, y, shape):
        if shape == "ci":
            return self.create_oval(x - 16, y - 16, x + 16, y + 16, fill=FIELD, outline="#3a4052")
        if shape == "sq":
            return self.create_rectangle(x - 13, y - 13, x + 13, y + 13, fill=FIELD, outline="#3a4052")
        if shape == "pill":
            return self.create_rectangle(x - 16, y - 9, x + 16, y + 9, fill=FIELD, outline="#3a4052")
        if shape == "pad":
            return self.create_rectangle(x - 70, y - 32, x + 70, y + 32, fill=FIELD, outline="#3a4052")
        if shape == "stick":
            return self.create_oval(x - 30, y - 30, x + 30, y + 30, fill=FIELD, outline="#3a4052")
        if shape == "bump":
            return self.create_rectangle(x - 42, y - 10, x + 42, y + 10, fill=FIELD, outline="#3a4052")
        if shape == "trig":
            return self.create_rectangle(x - 42, y - 14, x + 42, y + 14, fill=FIELD, outline="#3a4052")
        return None

    def update_state(self, snap):
        buttons = snap.get("buttons", {})
        axes = snap.get("axes", {})
        for name, item in self.items.items():
            self.itemconfigure(item, fill=ACCENT if buttons.get(name) else FIELD)
        for side in ("L2", "R2"):
            x, y = LAYOUT[side][0]
            v = max(0.0, min(1.0, axes.get(side, 0.0)))
            self.coords(self.trig_fill[side], x - 40, y + 9, x - 40 + 80 * v, y + 13)
        for side, name, ax, ay in (("LEFT", "L3", "LX", "LY"), ("RIGHT", "R3", "RX", "RY")):
            x, y = LAYOUT[name][0]
            dx, dy = axes.get(ax, 0.0) * 24, axes.get(ay, 0.0) * 24
            self.coords(self.dots[side], x + dx - 6, y + dy - 6, x + dx + 6, y + dy + 6)
        outs = sorted(snap.get("out_targets", []))
        txt = "Sortie : " + (", ".join(outs) if outs else "—")
        self.itemconfigure(self.out_text, text=txt[:95])
