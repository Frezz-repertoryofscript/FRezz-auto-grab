"""FRezz Pad Mapper — point d'entrée.

    python main.py              interface graphique
    python main.py --demo       interface sans matériel (aucune entrée / sortie)
    python main.py --headless --profile "Mon profil" --mode extreme   sans interface
"""

import argparse
import os
import sys
import time


def base_dir():
    if getattr(sys, "frozen", False):  # exécutable PyInstaller
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))


def seed_profiles(root):
    """Exe autonome : copie les profils fournis à côté de l'exe au premier lancement."""
    bundled = os.path.join(getattr(sys, "_MEIPASS", ""), "profiles")
    target = os.path.join(root, "profiles")
    if not getattr(sys, "frozen", False) or not os.path.isdir(bundled):
        return
    os.makedirs(target, exist_ok=True)
    if any(f.endswith(".json") for f in os.listdir(target)):
        return
    import shutil
    for f in os.listdir(bundled):
        if f.endswith(".json"):
            shutil.copy2(os.path.join(bundled, f), os.path.join(target, f))


def headless(profile_name, mode):
    from remapper.engine import Engine
    from remapper.realtime import boost_process
    from remapper.input_backend import PygameInput
    from remapper.output_backend import OutputManager
    from remapper.profile import ProfileStore, load_json

    root = base_dir()
    store = ProfileStore(os.path.join(root, "profiles"))
    names = store.list()
    if not names:
        print("Aucun profil. Lance d'abord l'interface.")
        return 1
    name = profile_name if profile_name in names else names[0]
    cmap = load_json(os.path.join(root, "config", "controller_map.json"), {})
    engine = Engine(lambda: PygameInput(cmap), lambda: OutputManager(), mode=mode)
    engine.set_profile(store.load(name))
    engine.start()
    undo = boost_process()
    print(f"Profil « {name} » actif. Ctrl+C pour quitter.")
    try:
        while engine.thread.is_alive():
            time.sleep(0.5)
            while not engine.events.empty():
                kind, data = engine.events.get()
                if kind == "action" and data in ("next_profile", "prev_profile"):
                    i = (names.index(name) + (1 if data == "next_profile" else -1)) % len(names)
                    name = names[i]
                    engine.set_profile(store.load(name))
                    print(f"Profil « {name} »")
                elif kind == "action":
                    print(f"Action : {data}")
    except KeyboardInterrupt:
        pass
    engine.stop()
    undo()
    return 0


def main():
    ap = argparse.ArgumentParser(description="FRezz Pad Mapper — remappage et macros pour manette PS5")
    ap.add_argument("--demo", action="store_true", help="interface sans manette ni sortie")
    ap.add_argument("--headless", action="store_true", help="sans interface graphique")
    ap.add_argument("--profile", default="", help="profil à charger en mode headless")
    ap.add_argument("--mode", default="ultra", choices=["eco", "rapide", "ultra", "extreme"],
                    help="mode de performance en mode headless")
    args = ap.parse_args()
    seed_profiles(base_dir())
    if args.headless:
        return headless(args.profile, args.mode)
    from remapper.gui.app import App
    App(base_dir(), demo=args.demo).mainloop()
    return 0


if __name__ == "__main__":
    import multiprocessing
    multiprocessing.freeze_support()   # requis pour l'exécutable PyInstaller
    sys.exit(main())
