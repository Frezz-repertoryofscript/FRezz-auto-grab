# TAIL CHASE

Jeu Roblox de course-poursuite : chaque participant porte une queue (chasuble) dans le dos, les chasseurs (outline rouge visible à travers les murs, étiquette « HUNTER ») l'arrachent au contact, et le participant capturé devient chasseur à son tour.

Projet **Rojo**. L'UI est entièrement construite avec le kit **Stud UI Clean Roblox** (`StudUI`, `StudMotion`, `CheckUIIcons`, installés dans `ReplicatedStorage`).

## Installer dans ta place

1. Installe Rojo (plugin Studio + CLI) : https://rojo.space
2. `cd TailChase && rojo serve`, puis dans Studio : plugin Rojo → **Connect**.
   (ou `rojo build -o TailChase.rbxlx` et ouvre le fichier)
3. **Game Settings → Avatar → R15** (les animations procédurales visent le R15 ; en R6 les animations par défaut restent actives).
4. Pour tester la sauvegarde : **Game Settings → Security → Enable Studio Access to API Services**.

La map, le lobby, l'éclairage et les groupes de collision sont générés au démarrage par `MapBuilder`. Si tu sauvegardes un modèle `Workspace.Map` / `Workspace.Lobby` (par ex. après l'avoir retouché à la main), il est réutilisé tel quel.

## Tester

| Test | Comment |
|---|---|
| Solo (mouvement, map, UI, boucle complète sans chasseur) | Play → clique **JOUER** → intermission 20 s → manche |
| Vraie manche | Test → Clients and Servers → **Local Server, 2 à 4 joueurs**, chacun clique JOUER |
| Shop | Bouton Shop du menu gauche, ou le stand rouge du lobby (ProximityPrompt) |
| Tests hors Studio | `tests/run.sh` (binaire `luau`) : mocks de l'API Roblox, exécute map, lobby, une manche complète avec captures, shop, toute l'UI et les contrôleurs |

Commandes : **Dash** Q / Shift / manette X / bouton tactile · **Slide** C / Ctrl / manette Y / bouton tactile. Les tunnels de slide sont signalés par un néon cyan et un panneau « SLIDE [C] ».

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
  RoleService, TailService, CoinService, DataService, ShopService, MovementService, MapBuilder
StarterPlayerScripts
  MovementController                   dash, slide, jump pads
  AnimationController                  walk/run/idle/air/dash/slide/arrachage procéduraux (Motor6D.Transform)
  EffectsController                    balancement des queues, traînées, poussière, FOV, shake, queue qui vole, musique
  UIController (+ Hud, LobbyMenu, Collection, Results, Screens)
```

## Valeurs à ajuster (`Shared/Config`)

- Manche : `MinPlayers` (4), `StudioMinPlayers` (1), `IntermissionTime` 20, `CountdownTime` 5, `HunterReleaseDelay` 3, `RoundTime` 180, `ResultsTime` 10, `ExtraHunterThreshold` 10
- Capture : `CaptureDistance` 5.5, `CaptureVerticalMax` 6, `HunterCaptureCooldown` 0.6, `NewHunterImmunity` 2
- Mouvement : `RunnerWalkSpeed` 20, `HunterWalkSpeed` 21.5, `DashSpeed` 78, `DashDuration` 0.18, `DashCooldown` 4, `DashFovBoost` 14, `SlideBoost` 1.55, `SlideDuration` 0.85, `SlideCooldown` 1.1, `JumpPadPower`, `KillPlaneY` -40
- Économie : `Coins.SurvivalSecondsPerCoin` 5, `PerTail` 10, `Participation` 25, `LastSurvivor` 50, `StartingCoins` 100
- Prix et raretés : `Shared/Cosmetics`

## Reste à faire / à renseigner

- **Musiques** : `Config.Sounds.MusicLobby` et `MusicRound` sont des `PLACEHOLDER_…` (ignorés sans erreur). Mets des IDs de la Creator Store.
- Les effets sonores utilisent des sons intégrés (`rbxasset://sounds/...`) et ceux du kit ; remplace-les dans `Config.Sounds` si tu veux.
- Monétisation : `Config.Monetization` + `ShopService.GrantProduct` / `HasGamepass` sont des points d'extension non branchés.
- Pas d'IDs d'animation : tout est procédural. Pour des animations faites dans l'Animation Editor, remplace les poses de `AnimationController`.
