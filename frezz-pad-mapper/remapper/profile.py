"""Profils : chargement, sauvegarde, valeurs par défaut et validation."""

import copy
import json
import os
import re

from .constants import PHYS_BUTTONS, MACRO_MODES, STEP_TYPES, is_input

PROFILE_VERSION = 1


def default_stick(target):
    return {
        "target": target,
        "deadzone": 0.08,        # zone morte intérieure (0..0.9)
        "outer": 0.98,           # zone morte extérieure : au-delà = 100 %
        "anti_deadzone": 0.0,    # compense la zone morte du jeu (0..0.5)
        "sensitivity": 1.0,      # multiplicateur (0.1..3)
        "curve": 1.0,            # 1 = linéaire, >1 = plus précis au centre
        "invert_x": False,
        "invert_y": False,
        "mouse_speed": 1400.0,   # pixels / seconde à fond (cible "mouse")
        "digital_threshold": 0.5,  # seuil pour wasd / flèches
    }


def default_trigger():
    return {"deadzone": 0.02, "outer": 0.98, "threshold": 0.35}


def default_profile(name="Défaut"):
    return {
        "version": PROFILE_VERSION,
        "name": name,
        "virtual_pad": "x360",   # "x360" ou "ds4"
        "buttons": {b: ("none" if b == "MUTE" else f"pad:{b}") for b in PHYS_BUTTONS},
        "sticks": {"LEFT": default_stick("pad:LS"), "RIGHT": default_stick("pad:RS")},
        "triggers": {"L2": default_trigger(), "R2": default_trigger()},
        "turbo": {},
        "macros": [],
        "hotkeys": {
            "next_profile": ["PS", "R1"],
            "prev_profile": ["PS", "L1"],
            "toggle_pause": ["PS", "OPTIONS"],
            "stop_macros": ["PS", "CREATE"],
        },
    }


def default_macro(name="Nouvelle macro"):
    return {
        "name": name,
        "enabled": True,
        "trigger": [],          # liste de boutons physiques (combo = plusieurs)
        "mode": "press",
        "repeat": 1,            # nombre de répétitions (0 = infini pour hold/toggle)
        "speed": 1.0,           # multiplicateur de vitesse des délais
        "jitter_ms": 0,         # aléa +/- sur les délais (humanisation)
        "block_trigger": True,  # n'envoie pas les boutons déclencheurs au jeu
        "hold_ms": 400,         # durée pour le mode "long"
        "double_ms": 300,       # fenêtre pour le mode "double"
        "steps": [],
    }


def _num(v, default, lo=None, hi=None):
    try:
        v = float(v)
    except (TypeError, ValueError):
        return default
    if lo is not None:
        v = max(lo, v)
    if hi is not None:
        v = min(hi, v)
    return v


def _targets(step):
    t = step.get("targets")
    if t is None:
        t = step.get("target")
    if isinstance(t, str):
        t = [t] if t else []
    return [x for x in (t or []) if isinstance(x, str) and x and x != "none"]


def normalize_step(step):
    typ = step.get("type", "wait")
    if typ not in STEP_TYPES:
        raise ValueError(f"type de pas inconnu : {typ}")
    out = {"type": typ}
    if typ in ("tap", "press", "release"):
        out["targets"] = _targets(step)
        if typ == "tap":
            out["ms"] = int(_num(step.get("ms"), 50, 1, 600000))
    elif typ == "wait":
        out["ms"] = int(_num(step.get("ms"), 100, 0, 600000))
    elif typ == "axis":
        out["axis"] = str(step.get("axis", "LX"))
        lo = 0.0 if out["axis"] in ("L2", "R2") else -1.0
        out["value"] = round(_num(step.get("value"), 0.0, lo, 1.0), 3)
    elif typ == "mouse_move":
        out["dx"] = int(_num(step.get("dx"), 0, -10000, 10000))
        out["dy"] = int(_num(step.get("dy"), 0, -10000, 10000))
        out["ms"] = int(_num(step.get("ms"), 0, 0, 60000))   # 0 = instantané, sinon glissé
    return out


def normalize_macro(m):
    base = default_macro()
    base.update({k: v for k, v in m.items() if k in base})
    base["name"] = str(base["name"]).strip() or "Macro"
    base["enabled"] = bool(base["enabled"])
    base["trigger"] = list(dict.fromkeys(b for b in base["trigger"] if isinstance(b, str) and is_input(b)))
    if base["mode"] not in MACRO_MODES:
        base["mode"] = "press"
    base["repeat"] = int(_num(base["repeat"], 1, 0, 100000))
    base["speed"] = _num(base["speed"], 1.0, 0.05, 20.0)
    base["jitter_ms"] = int(_num(base["jitter_ms"], 0, 0, 5000))
    base["block_trigger"] = bool(base["block_trigger"])
    base["hold_ms"] = int(_num(base["hold_ms"], 400, 50, 10000))
    base["double_ms"] = int(_num(base["double_ms"], 300, 80, 2000))
    base["steps"] = [normalize_step(s) for s in base["steps"] if isinstance(s, dict)]
    return base


def normalize_profile(p):
    """Complète un profil (éventuellement ancien ou incomplet) avec les valeurs par défaut."""
    out = default_profile(p.get("name", "Défaut"))
    if p.get("virtual_pad") in ("x360", "ds4"):
        out["virtual_pad"] = p["virtual_pad"]
    for b, t in (p.get("buttons") or {}).items():
        if b in out["buttons"] and isinstance(t, str):
            out["buttons"][b] = t or "none"
    for side, cfg in (p.get("sticks") or {}).items():
        if side in out["sticks"] and isinstance(cfg, dict):
            out["sticks"][side].update(cfg)
    for side, cfg in (p.get("triggers") or {}).items():
        if side in out["triggers"] and isinstance(cfg, dict):
            out["triggers"][side].update(cfg)
    for b, cfg in (p.get("turbo") or {}).items():
        if b in PHYS_BUTTONS and isinstance(cfg, dict):
            out["turbo"][b] = {
                "enabled": bool(cfg.get("enabled", True)),
                "rate": _num(cfg.get("rate"), 12.0, 1.0, 60.0),
                "mode": cfg.get("mode") if cfg.get("mode") in ("hold", "toggle") else "hold",
            }
    names = set()
    for m in p.get("macros") or []:
        if not isinstance(m, dict):
            continue
        m = normalize_macro(m)
        base, i = m["name"], 2
        while m["name"] in names:
            m["name"] = f"{base} ({i})"
            i += 1
        names.add(m["name"])
        out["macros"].append(m)
    if isinstance(p.get("hotkeys"), dict):
        for k, v in p["hotkeys"].items():
            if k in out["hotkeys"] and isinstance(v, list):
                out["hotkeys"][k] = [b for b in v if isinstance(b, str) and is_input(b)]
    return out


def safe_filename(name):
    s = re.sub(r"[^\w\- ]+", "_", name, flags=re.UNICODE).strip()
    return (s or "profil") + ".json"


class ProfileStore:
    """Dossier de profils JSON."""

    def __init__(self, folder):
        self.folder = folder
        os.makedirs(folder, exist_ok=True)

    def path_for(self, name):
        return os.path.join(self.folder, safe_filename(name))

    def list(self):
        names = []
        for f in sorted(os.listdir(self.folder)):
            if f.lower().endswith(".json"):
                try:
                    with open(os.path.join(self.folder, f), encoding="utf-8") as fh:
                        names.append(json.load(fh).get("name") or f[:-5])
                except (OSError, ValueError):
                    continue
        return names

    def load(self, name):
        with open(self.path_for(name), encoding="utf-8") as fh:
            return normalize_profile(json.load(fh))

    def save(self, profile):
        profile = normalize_profile(copy.deepcopy(profile))
        path = self.path_for(profile["name"])
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(profile, fh, indent=2, ensure_ascii=False)
        os.replace(tmp, path)
        return path

    def delete(self, name):
        path = self.path_for(name)
        if os.path.exists(path):
            os.remove(path)


def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return copy.deepcopy(default)


def save_json(path, data):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
    os.replace(tmp, path)
