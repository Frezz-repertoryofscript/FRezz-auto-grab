"""Génère FRezzPadMapper.py : toute l'appli dans un seul fichier.

    python tools/make_single_file.py
"""

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "FRezzPadMapper.py")

HEADER = '''#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""FRezz Pad Mapper — remappage et macros pour manette PS5 (DualSense) sur PC.

Version UN SEUL FICHIER (générée par tools/make_single_file.py, ne pas modifier à la main).

Lancement :  python FRezzPadMapper.py
Au premier lancement, les dépendances (pygame, vgamepad) sont installées automatiquement
et l'installeur du pilote ViGEmBus s'ouvre : accepte-le.
"""

import importlib.abc
import importlib.util
import os
import subprocess
import sys

_SOURCES = {SOURCES}

_DATA = {DATA}


class _EmbeddedImporter(importlib.abc.MetaPathFinder, importlib.abc.Loader):
    """Charge les modules « remapper.* » embarqués dans ce fichier."""

    def find_spec(self, name, path=None, target=None):
        if name in _SOURCES:
            return importlib.util.spec_from_loader(name, self, is_package=_SOURCES[name][0])
        return None

    def create_module(self, spec):
        return None

    def exec_module(self, module):
        is_pkg, src = _SOURCES[module.__name__]
        if is_pkg:
            module.__path__ = []
        module.__file__ = os.path.abspath(__file__)
        exec(compile(src, "<" + module.__name__ + ">", "exec"), module.__dict__)


if not any(isinstance(f, _EmbeddedImporter) for f in sys.meta_path):
    sys.meta_path.insert(0, _EmbeddedImporter())


def _ensure_dependencies():
    """Installe pygame (+ vgamepad sous Windows) si absents."""
    missing = []
    for mod, pkg in (("pygame", "pygame"), ("vgamepad", "vgamepad")):
        if mod == "vgamepad" and sys.platform != "win32":
            continue
        if importlib.util.find_spec(mod) is None:
            missing.append(pkg)
    if sys.platform != "win32" and importlib.util.find_spec("pynput") is None:
        missing.append("pynput")
    if not missing:
        return
    print("Installation des dépendances : " + ", ".join(missing) + " ...")
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", *missing])
    except Exception as e:  # noqa: BLE001
        print("Échec de l'installation automatique (" + str(e) + ").")
        print("Lance à la main :  " + sys.executable + " -m pip install " + " ".join(missing))
    importlib.invalidate_caches()


def _seed_files(root):
    target = os.path.join(root, "profiles")
    os.makedirs(target, exist_ok=True)
    if any(f.endswith(".json") for f in os.listdir(target)):
        return
    for rel, content in _DATA.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(content)


# ============================================================ main.py
'''

FOOTER = '''

if __name__ == "__main__":
    import multiprocessing
    multiprocessing.freeze_support()
    _ensure_dependencies()
    _seed_files(base_dir())
    sys.exit(main())
'''


def main():
    sources = {}
    pkg_dir = os.path.join(ROOT, "remapper")
    for dirpath, _dirs, files in os.walk(pkg_dir):
        for f in sorted(files):
            if not f.endswith(".py"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, f), ROOT)[:-3].replace(os.sep, ".")
            is_pkg = rel.endswith(".__init__")
            name = rel[: -len(".__init__")] if is_pkg else rel
            with open(os.path.join(dirpath, f), encoding="utf-8") as fh:
                sources[name] = (is_pkg, fh.read())
    data = {}
    for f in sorted(os.listdir(os.path.join(ROOT, "profiles"))):
        if f.endswith(".json"):
            with open(os.path.join(ROOT, "profiles", f), encoding="utf-8") as fh:
                data["profiles/" + f] = fh.read()

    def fmt(d):
        lines = ["{"]
        for k in sorted(d):
            lines.append("    %r: %r," % (k, d[k]))
        lines.append("}")
        return "\n".join(lines)

    with open(os.path.join(ROOT, "main.py"), encoding="utf-8") as fh:
        main_src = fh.read()
    # on retire la docstring et le bloc __main__ de main.py (remplacés par FOOTER)
    main_src = main_src.split('if __name__ == "__main__":')[0].rstrip()
    if main_src.startswith('"""'):
        main_src = main_src.split('"""', 2)[2].lstrip()

    out = HEADER.replace("{SOURCES}", fmt(sources)).replace("{DATA}", fmt(data)) + main_src + FOOTER
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(out)
    print(f"{OUT} : {len(sources)} modules, {len(out) // 1024} Ko")


if __name__ == "__main__":
    main()
