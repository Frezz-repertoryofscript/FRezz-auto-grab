# TAIL CHASE

Jeu Roblox de course-poursuite : chaque participant porte une queue (chasuble) dans le dos, les chasseurs (outline rouge visible à travers les murs, étiquette « HUNTER ») l'arrachent au contact, et le participant capturé devient chasseur à son tour.

Projet **Rojo**. L'UI est entièrement construite avec le kit **Stud UI Clean Roblox** (`StudUI`, `StudMotion`, `CheckUIIcons`, installés dans `ReplicatedStorage`).

## Installer dans ta place

1. Installe Rojo (plugin Studio + CLI) : https://rojo.space
2. `cd TailChase && rojo serve`, puis dans Studio : plugin Rojo → **Connect**.
   (le plus simple : ouvre directement `TailChase.rbxlx`, régénéré par `python3 tools/build_rbxlx.py`)
   (ou `rojo build -o TailChase.rbxlx` et ouvre le fichier)
3. **Game Settings → Avatar → R15** (les animations procédurales visent le R15 ; en R6 les animations par défaut restent actives).
4. Pour tester la sauvegarde : **Game Settings → Security → Enable Studio Access to API Services**.

La map, le lobby, l'éclairage et les groupes de collision sont générés au démarrage par `MapBuilder`. Si tu sauvegardes un modèle `Workspace.Map` / `Workspace.Lobby` (par ex. après l'avoir retouché à la main), il est réutilisé tel quel.

## Tester

| Test | Comment |
|---|---|
| Solo (test) | Play → tuile **Admin** (violette) → **LANCER** : manche immédiate, sans chasseur |
| Vraie manche (minimum **2 joueurs** prêts) | Test → Clients and Servers → **Local Server, 2 à 4 joueurs**, chacun clique JOUER (ou Admin → TOUS PRÊTS → LANCER) |
| Shop | Bouton Shop du menu gauche, ou le stand rouge du lobby (ProximityPrompt) |
| Tests hors Studio | `tests/run.sh` (binaire `luau`) : mocks de l'API Roblox, exécute map, lobby, une manche complète avec captures, shop, toute l'UI et les contrôleurs |

Commandes : **Dash** Q / Shift / manette X / bouton tactile · **Slide** C / Ctrl / manette Y / bouton tactile. Les tunnels de slide sont signalés par un néon cyan et un panneau « SLIDE [C] ».

## Maps et vote

6 maps générées par code (`server/MapBuilder` + `server/MapBuilder/Maps/*.luau`) : **Ville**, **Plage**, **Château**, **Néon City** (de nuit), **Village alpin** (lac gelé glissant), **Fête foraine**.
Pendant l'intermission, 3 maps tirées au hasard sont proposées au vote (fenêtre automatique pour les joueurs prêts, bouton **VOTE** sous le chrono). La gagnante (égalité : tirage) est construite juste avant la manche ; l'ancienne est détruite.
Ajouter une map : copier un module de `Maps/`, changer `Id`/`Name`/`Order` et la fonction `Build(H, map, spawns)` (briques dans `MapBuilder.H`). `tests/run.sh` vérifie chaque map (construction, spawns, **z-fighting**).

## Animations

Idle, marche, course, saut, chute, réception, slide, dash, arrachage de queue : animations custom procédurales (`AnimationController`), sans asset à uploader.
Pour utiliser tes propres animations Roblox, mets leurs IDs dans `Config.Animations` (l'état correspondant les joue, répliquées à tous).

## Panel admin

Tuile violette « Admin » du menu de gauche (visible en Studio pour tous ; en ligne pour le créateur du jeu, le rang ≥ `Config.AdminGroupRank` du groupe propriétaire et les UserIds de `Config.Admins`). Toutes les commandes sont vérifiées par le serveur (`AdminService`).

| Bouton | Effet |
|---|---|
| LANCER | tout le monde prêt + intermission sautée → manche tout de suite (seul : sans chasseur) |
| TERMINER | fin de la manche en cours (résultats et pièces normaux) |
| TOUS PRÊTS | met tous les joueurs « prêts » |
| +1000 | pièces pour tester le shop |
| MANCHE 60s | bascule la durée des manches 180 s ↔ 60 s |
| TUTO | réaffiche le tutoriel |

## Tutoriel

4 pages (queue, chasseurs, mouvements, pièces), s'ouvre tout seul au premier passage (sauvegardé dans le profil) et via la tuile jaune « Tuto ».

## Architecture

```
ReplicatedStorage
  StudUI, StudMotion, CheckUIIcons     kit UI (skill stud-ui-clean-roblox)
  Shared/Config                        TOUTES les valeurs ajustables
  Shared/Cosmetics                     catalogue du shop (queues, traînées, effets de capture)
  Shared/TailBuilder                   construction de la queue (serveur + client)
  Shared/Audio, Shared/ClientSignals   sons / bus d'événements client
  Remotes/                             RemoteEvents et RemoteFunctions (déclarés dans default.project.json)
ServerScriptService
  GameManager (Script)                 boucle Lobby → Intermission → Countdown → Round → Results, captures validées
  RoleService, TailService, CoinService, DataService, ShopService, MovementService, AdminService
  MapBuilder (+ Maps/Plage, Chateau, Neon, Neige, Fete)
StarterPlayerScripts
  MovementController                   dash, slide, jump pads
  AnimationController                  walk/run/idle/air/dash/slide/arrachage procéduraux (Motor6D.Transform)
  EffectsController                    balancement des queues, traînées, poussière, FOV, shake, queue qui vole, musique
  UIController (+ Hud, LobbyMenu, Collection, Results, Screens, AdminPanel, Tutorial, MapVote)
```

## Valeurs à ajuster (`Shared/Config`)

- Manche : `MinPlayers` (2), `StudioMinPlayers` (2), `IntermissionTime` 20, `CountdownTime` 5, `HunterReleaseDelay` 3, `RoundTime` 180, `ResultsTime` 10, `ExtraHunterThreshold` 10
- Capture : `CaptureDistance` 5.5, `CaptureVerticalMax` 6, `HunterCaptureCooldown` 0.6, `NewHunterImmunity` 2
- Mouvement : `RunnerWalkSpeed` 20, `HunterWalkSpeed` 21.5, `DashSpeed` 78, `DashDuration` 0.18, `DashCooldown` 4, `DashFovBoost` 14, `SlideBoost` 1.55, `SlideDuration` 0.85, `SlideCooldown` 1.1, `JumpPadPower`, `KillPlaneY` -40
- Économie : `Coins.SurvivalSecondsPerCoin` 5, `PerTail` 10, `Participation` 25, `LastSurvivor` 50, `StartingCoins` 100
- Prix et raretés : `Shared/Cosmetics`

## Images

Le shop utilise un en-tête stud généré par le kit (plus de texture externe).

## Reste à faire / à renseigner

- **Musiques** : `Config.Sounds.MusicLobby` et `MusicRound` sont des `PLACEHOLDER_…` (ignorés sans erreur). Mets des IDs de la Creator Store.
- Les effets sonores utilisent des sons intégrés (`rbxasset://sounds/...`) et ceux du kit ; remplace-les dans `Config.Sounds` si tu veux.
- Monétisation : `Config.Monetization` + `ShopService.GrantProduct` / `HasGamepass` sont des points d'extension non branchés.
- Pas d'IDs d'animation : tout est procédural. Pour des animations faites dans l'Animation Editor, remplace les poses de `AnimationController`.
