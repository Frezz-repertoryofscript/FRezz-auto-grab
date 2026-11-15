#!/usr/bin/env bash
# Tests de non-régression hors Studio : exécute map, lobby, boucle de manche, shop et toute l'UI sur un mock de l'API Roblox.
# Prérequis : binaire `luau` (https://github.com/luau-lang/luau/releases) dans le PATH ou via LUAU=/chemin/luau
set -euo pipefail
cd "$(dirname "$0")"
LUAU="${LUAU:-luau}"
python3 gen.py
echo "== serveur ==" && "$LUAU" server.luau
echo "== client ==" && "$LUAU" client.luau
