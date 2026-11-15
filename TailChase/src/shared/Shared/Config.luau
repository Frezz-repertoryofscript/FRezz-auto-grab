--!strict
--[[
	Config - TOUTES les valeurs ajustables de TAIL CHASE.
	Modifie ici les durées, vitesses, cooldowns, récompenses et prix : aucun autre script ne contient de "nombre magique" de gameplay.
]]

local Config = {}

-- =====================================================================
-- BOUCLE DE MANCHE
-- =====================================================================
Config.MinPlayers = 4            -- joueurs "prêts" minimum pour lancer l'intermission
Config.StudioMinPlayers = 1      -- en Studio : 1 = manche solo sans chasseur (test du mouvement), 2+ = Test > Local Server
Config.IntermissionTime = 20     -- secondes
Config.CountdownTime = 5         -- décompte avant le départ (tout le monde figé)
Config.HunterReleaseDelay = 3    -- avance des participants : les chasseurs partent X s après le GO
Config.RoundTime = 180           -- 3 minutes
Config.ResultsTime = 10
Config.ExtraHunterThreshold = 10 -- au-delà de ce nombre de joueurs : 2 chasseurs

-- =====================================================================
-- CAPTURE (validée côté serveur)
-- =====================================================================
Config.CaptureDistance = 5.5       -- distance max (studs) entre les HumanoidRootPart
Config.CaptureVerticalMax = 6      -- écart vertical max (évite les captures à travers un toit)
Config.HunterCaptureCooldown = 0.6 -- délai entre deux captures d'un même chasseur
Config.NewHunterImmunity = 2       -- anti-chaîne : un nouveau chasseur ne peut pas capturer pendant X s
Config.CaptureCheckRate = 1 / 20   -- fréquence du test de capture (s)

-- =====================================================================
-- MOUVEMENT
-- =====================================================================
Config.RunnerWalkSpeed = 20
Config.HunterWalkSpeed = 21.5
Config.LobbyWalkSpeed = 18
Config.JumpPower = 50

Config.DashSpeed = 78           -- vitesse horizontale pendant le dash
Config.DashDuration = 0.18
Config.DashCooldown = 4
Config.DashFovBoost = 14        -- élargissement bref du FOV
Config.DashServerTolerance = 0.35 -- marge latence pour la validation serveur du cooldown

Config.SlideBoost = 1.55        -- multiplicateur de vitesse au début du slide (conserve l'élan)
Config.SlideMinSpeed = 30
Config.SlideMaxSpeed = 60
Config.SlideDuration = 0.85
Config.SlideFriction = 1.6      -- décroissance de la vitesse par seconde (fraction)
Config.SlideCooldown = 1.1
Config.SlideCrouchSpeed = 13    -- vitesse quand on reste accroupi sous un plafond de tunnel
Config.SlideCameraOffset = -1.8

Config.JumpPadPower = 105       -- vitesse verticale donnée par un jump pad
Config.JumpPadCooldown = 0.6

Config.KillPlaneY = -40         -- sous cette hauteur, le joueur est replacé

-- =====================================================================
-- ÉCONOMIE
-- =====================================================================
Config.Coins = {
	SurvivalSecondsPerCoin = 5, -- 1 pièce / 5 s de survie
	PerTail = 10,               -- 10 pièces par queue prise
	Participation = 25,
	LastSurvivor = 50,
	StartingCoins = 100,
}

-- =====================================================================
-- DONNÉES
-- =====================================================================
Config.Data = {
	StoreName = "TailChase_Profiles_v1",
	LeaderboardStore = "TailChase_TailsTaken_v1",
	AutoSaveInterval = 120,
	Retries = 4,
	RetryDelay = 1.5,
	LeaderboardRefresh = 60,
}

-- =====================================================================
-- MONÉTISATION (points d'extension, NON implémentés)
-- Renseigne ici les IDs quand tu les crées sur le dashboard ; ShopService.GrantProduct est le point d'entrée prévu.
-- =====================================================================
Config.Monetization = {
	DeveloperProducts = {
		-- [123456789] = { Kind = "Coins", Amount = 500 },
	},
	Gamepasses = {
		-- [987654321] = { Kind = "Cosmetic", Item = "tail_rainbow" },
	},
}

-- =====================================================================
-- AUDIO (sons libres Roblox / fichiers intégrés ; remplace les PLACEHOLDER_ par tes IDs)
-- =====================================================================
Config.Sounds = {
	RoundStart = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8, Pitch = 0.8 },
	Countdown = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.7, Pitch = 1 },
	Go = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.9, Pitch = 1.3 },
	Capture = { Id = "rbxasset://sounds/snap.wav", Volume = 1, Pitch = 0.9 },
	CaptureWhoosh = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.8, Pitch = 1.2 },
	Dash = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.7, Pitch = 1.5 },
	Slide = { Id = "rbxasset://sounds/action_swim.mp3", Volume = 0.6, Pitch = 1.6 },
	JumpPad = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.9, Pitch = 0.8 },
	Purchase = { Id = "rbxassetid://1319346243", Volume = 0.55, Pitch = 1 },
	Victory = { Id = "rbxasset://sounds/victory.wav", Volume = 0.8, Pitch = 1 },
	Notify = { Id = "rbxassetid://109359226723492", Volume = 0.35, Pitch = 1.3 },
	CoinTick = { Id = "rbxassetid://6895079853", Volume = 0.35, Pitch = 1.4 },
	-- Musiques : PLACEHOLDER. Mets ici l'ID d'une musique libre de la Creator Store (ex : "rbxassetid://XXXX").
	MusicLobby = { Id = "PLACEHOLDER_MusicLobby", Volume = 0.3, Pitch = 1 },
	MusicRound = { Id = "PLACEHOLDER_MusicRound", Volume = 0.3, Pitch = 1 },
}

-- =====================================================================
-- VISUEL
-- =====================================================================
Config.StudTexture = "rbxassetid://140544932962041" -- motif de studs tileable (même texture que le kit StudUI)
Config.HunterColor = Color3.fromRGB(255, 30, 50)
Config.RunnerColor = Color3.fromRGB(60, 170, 255)
Config.TailSegments = 6
Config.TailSegmentLength = 0.75

Config.States = {
	Lobby = "Lobby",
	Intermission = "Intermission",
	Countdown = "Countdown",
	Round = "Round",
	Results = "Results",
}

return Config
