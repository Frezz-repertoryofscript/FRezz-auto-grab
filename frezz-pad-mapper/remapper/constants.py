"""Noms des entrées/sorties et libellés affichés dans l'interface."""

# Boutons physiques de la DualSense (L2/R2 = version "digitale" de la gâchette)
PHYS_BUTTONS = [
    "CROSS", "CIRCLE", "SQUARE", "TRIANGLE",
    "L1", "R1", "L2", "R2", "L3", "R3",
    "DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT",
    "CREATE", "OPTIONS", "PS", "TOUCHPAD", "MUTE",
]

# Axes physiques : sticks dans [-1, 1] (Y vers le bas = positif), gâchettes dans [0, 1]
PHYS_AXES = ["LX", "LY", "RX", "RY", "L2", "R2"]

STICKS = {"LEFT": ("LX", "LY"), "RIGHT": ("RX", "RY")}

LABELS = {
    "CROSS": "✕ Croix", "CIRCLE": "○ Rond", "SQUARE": "□ Carré", "TRIANGLE": "△ Triangle",
    "L1": "L1", "R1": "R1", "L2": "L2", "R2": "R2", "L3": "L3 (clic stick G)", "R3": "R3 (clic stick D)",
    "DPAD_UP": "Croix ↑", "DPAD_DOWN": "Croix ↓", "DPAD_LEFT": "Croix ←", "DPAD_RIGHT": "Croix →",
    "CREATE": "Create", "OPTIONS": "Options", "PS": "PS", "TOUCHPAD": "Pavé tactile", "MUTE": "Micro",
}

SHORT = {
    "CROSS": "✕", "CIRCLE": "○", "SQUARE": "□", "TRIANGLE": "△",
    "DPAD_UP": "↑", "DPAD_DOWN": "↓", "DPAD_LEFT": "←", "DPAD_RIGHT": "→",
}

# Boutons de la manette virtuelle (MUTE n'existe pas sur la manette virtuelle)
PAD_BUTTONS = [b for b in PHYS_BUTTONS if b != "MUTE"]
# Axes de la manette virtuelle utilisables dans les macros
PAD_AXES = ["LX", "LY", "RX", "RY", "L2", "R2"]

STICK_TARGETS = ["pad:LS", "pad:RS", "mouse", "zqsd", "wasd", "arrows", "none"]

MOUSE_BUTTONS = ["left", "right", "middle", "x1", "x2"]
WHEEL = ["up", "down"]

KEYS = (
    [chr(c) for c in range(ord("a"), ord("z") + 1)]
    + [str(d) for d in range(10)]
    + [f"f{i}" for i in range(1, 13)]
    + [
        "space", "enter", "esc", "tab", "backspace", "capslock",
        "shift", "rshift", "ctrl", "rctrl", "alt", "ralt",
        "up", "down", "left", "right",
        "insert", "delete", "home", "end", "pageup", "pagedown",
        "minus", "equal", "lbracket", "rbracket", "semicolon", "quote",
        "backquote", "backslash", "comma", "period", "slash",
        "num0", "num1", "num2", "num3", "num4", "num5", "num6", "num7", "num8", "num9",
        "numenter", "numplus", "numminus", "nummul", "numdiv", "numdot",
    ]
)

ACTIONS = ["next_profile", "prev_profile", "toggle_pause", "stop_macros"]

ACTION_LABELS = {
    "next_profile": "Profil suivant",
    "prev_profile": "Profil précédent",
    "toggle_pause": "Pause / reprise du remappage",
    "stop_macros": "Stopper toutes les macros",
}

MACRO_MODES = {
    "press": "Appui (joue N fois)",
    "hold": "Maintien (boucle tant que tenu)",
    "toggle": "Toggle (appui = start / stop)",
    "release": "Relâchement (joue N fois)",
    "double": "Double appui",
    "long": "Appui long",
}

STEP_TYPES = {
    "tap": "Tap (appui + relâche)",
    "press": "Appuyer",
    "release": "Relâcher",
    "wait": "Attendre",
    "axis": "Axe / stick",
    "mouse_move": "Souris : déplacer",
    "release_all": "Tout relâcher",
}


def all_targets(macro_names=()):
    """Liste de toutes les cibles possibles pour un bouton."""
    out = ["none"]
    out += [f"pad:{b}" for b in PAD_BUTTONS]
    out += [f"key:{k}" for k in KEYS]
    out += [f"mouse:{m}" for m in MOUSE_BUTTONS]
    out += [f"wheel:{w}" for w in WHEEL]
    out += [f"macro:{n}" for n in macro_names]
    out += [f"action:{a}" for a in ACTIONS]
    return out


def kbm_inputs():
    """Touches / boutons souris utilisables comme DÉCLENCHEURS (entrée)."""
    return ([f"key:{k}" for k in KEYS] + [f"mouse:{m}" for m in MOUSE_BUTTONS]
            + [f"wheel:{w}" for w in WHEEL])


def is_input(name):
    """Entrée valide pour un déclencheur : bouton manette, touche, bouton souris ou molette."""
    if name in PHYS_BUTTONS:
        return True
    kind, _, n = name.partition(":")
    return (kind == "key" and n in KEYS) or (kind == "mouse" and n in MOUSE_BUTTONS) or \
        (kind == "wheel" and n in WHEEL)


def input_label(name):
    if name in LABELS:
        return LABELS[name]
    kind, _, n = name.partition(":")
    if kind == "key":
        return n.upper() if len(n) == 1 else n.capitalize()
    if kind == "mouse":
        return {"left": "Clic gauche", "right": "Clic droit", "middle": "Clic molette",
                "x1": "Souris X1", "x2": "Souris X2"}.get(n, n)
    if kind == "wheel":
        return "Molette ↑" if n == "up" else "Molette ↓"
    return name


def step_targets():
    """Cibles utilisables dans un pas de macro (pas de macro:/action:)."""
    return (
        [f"pad:{b}" for b in PAD_BUTTONS]
        + [f"key:{k}" for k in KEYS]
        + [f"mouse:{m}" for m in MOUSE_BUTTONS]
        + [f"wheel:{w}" for w in WHEEL]
    )


def target_label(target):
    if not target or target == "none":
        return "— aucun —"
    kind, _, name = target.partition(":")
    if kind == "pad":
        return "Manette " + LABELS.get(name, name)
    if kind == "key":
        return "Touche " + name.upper()
    if kind == "mouse":
        return "Souris " + name
    if kind == "wheel":
        return "Molette " + name
    if kind == "macro":
        return "Macro « " + name + " »"
    if kind == "action":
        return ACTION_LABELS.get(name, name)
    return target
