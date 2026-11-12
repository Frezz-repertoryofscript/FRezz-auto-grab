"""FRezz Pad Mapper — point d'entrée.

    python main.py              interface graphique
    python main.py --demo       interface sans matériel (aucune entrée / sortie)
    python main.py --headless --profile "Mon profil"   sans interface
"""

import argparse
import os
import sys
import time


def base_dir():
    if getattr(sys, "frozen", False):  # exécutable PyInstaller
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))


def headless(profile_name):
    from remapper.engine import Engine
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
    engine = Engine(lambda: PygameInput(cmap), lambda: OutputManager(), tick_hz=1000)
    engine.set_profile(store.load(name))
    engine.start()
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
    return 0


def main():
    ap = argparse.ArgumentParser(description="FRezz Pad Mapper — remappage et macros pour manette PS5")
    ap.add_argument("--demo", action="store_true", help="interface sans manette ni sortie")
    ap.add_argument("--headless", action="store_true", help="sans interface graphique")
    ap.add_argument("--profile", default="", help="profil à charger en mode headless")
    args = ap.parse_args()
    if args.headless:
        return headless(args.profile)
    from remapper.gui.app import App
    App(base_dir(), demo=args.demo).mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
