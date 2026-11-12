"""Modèles de macros prêts à l'emploi (modifiables ensuite)."""

from .profile import default_macro


def _m(name, mode, steps, trigger=(), repeat=1, **kw):
    m = default_macro(name)
    m.update(mode=mode, steps=steps, trigger=list(trigger), repeat=repeat, **kw)
    return m


def tap(t, ms=40):
    return {"type": "tap", "targets": [t] if isinstance(t, str) else list(t), "ms": ms}


def press(*t):
    return {"type": "press", "targets": list(t)}


def release(*t):
    return {"type": "release", "targets": list(t)}


def wait(ms):
    return {"type": "wait", "ms": ms}


def axis(a, v):
    return {"type": "axis", "axis": a, "value": v}


RELEASE_ALL = {"type": "release_all"}

TEMPLATES = {
    "Tir rapide ✕ (toggle)": lambda: _m(
        "Tir rapide ✕", "toggle", [tap("pad:CROSS", 30), wait(30)], repeat=0),
    "Spam saut (maintien)": lambda: _m(
        "Spam saut", "hold", [tap("pad:CROSS", 40), wait(60)], repeat=0),
    "Mitraillette clic gauche": lambda: _m(
        "Mitraillette clic", "hold", [tap("mouse:left", 20), wait(40)], repeat=0),
    "Quart de cercle avant + □ (↓ ↘ → □)": lambda: _m(
        "Quart de cercle + □", "press", [
            press("pad:DPAD_DOWN"), wait(33),
            press("pad:DPAD_RIGHT"), wait(33),
            release("pad:DPAD_DOWN"), wait(33),
            tap("pad:SQUARE", 50), RELEASE_ALL]),
    "Dragon punch + △ (→ ↓ ↘ △)": lambda: _m(
        "Dragon punch + △", "press", [
            tap("pad:DPAD_RIGHT", 33),
            press("pad:DPAD_DOWN"), wait(33),
            press("pad:DPAD_RIGHT"), wait(33),
            tap("pad:TRIANGLE", 50), RELEASE_ALL]),
    "Combo chaîne □ □ △ ○": lambda: _m(
        "Combo □□△○", "press", [
            tap("pad:SQUARE", 40), wait(120), tap("pad:SQUARE", 40), wait(120),
            tap("pad:TRIANGLE", 40), wait(180), tap("pad:CIRCLE", 60)]),
    "Drop shot (R2 tenu + ○)": lambda: _m(
        "Drop shot", "press", [press("pad:R2"), wait(20), tap("pad:CIRCLE", 60), wait(400),
                               RELEASE_ALL]),
    "Glissade (○ en courant)": lambda: _m(
        "Glissade", "press", [press("pad:L3"), wait(50), tap("pad:CIRCLE", 60), release("pad:L3")]),
    "Rechargement rapide (□ puis switch △△)": lambda: _m(
        "Reload cancel", "press", [tap("pad:SQUARE", 40), wait(350), tap("pad:TRIANGLE", 30),
                                   wait(60), tap("pad:TRIANGLE", 30)]),
    "Anti-AFK (toggle)": lambda: _m(
        "Anti-AFK", "toggle", [axis("LX", 1.0), wait(400), axis("LX", -1.0), wait(400),
                               axis("LX", 0.0), tap("pad:CROSS", 60), wait(20000)], repeat=0),
    "Tourner caméra 180°": lambda: _m(
        "Demi-tour", "press", [axis("RX", 1.0), wait(250), axis("RX", 0.0)]),
    "Texte « gg » au clavier": lambda: _m(
        "gg", "press", [tap("key:enter", 30), wait(80), tap("key:g", 30), wait(30),
                        tap("key:g", 30), wait(30), tap("key:enter", 30)]),
}
