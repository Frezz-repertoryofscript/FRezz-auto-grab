--[[
	UIController - construit TOUTE l'interface avec le kit StudUI (une seule fois, ScreenGuis ResetOnSpawn = false)
	et la branche aux Remotes / Attributes. Animations et sons via StudMotion.

	Pourquoi au runtime et pas en Edit dans StarterGui : le projet est livré en fichiers (Rojo, sans MCP Studio).
	Les builders sont des fonctions pures (comme les exemples du kit) : tu peux les exécuter depuis la barre de
	commande Studio pour figer l'UI dans StarterGui si tu préfères, sans rien changer d'autre.

	Modules : Hud, LobbyMenu, Collection (Shop + Inventaire), Results, Screens (notifications + écran de rôle)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UI = require(ReplicatedStorage:WaitForChild("StudUI"))
local Motion = require(ReplicatedStorage:WaitForChild("StudMotion"))
local Icons = require(ReplicatedStorage:WaitForChild("CheckUIIcons"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared.Cosmetics)
local Signals = require(Shared.ClientSignals)
local Audio = require(Shared.Audio)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Hud = require(script.Hud)
local LobbyMenu = require(script.LobbyMenu)
local Collection = require(script.Collection)
local Results = require(script.Results)
local Screens = require(script.Screens)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local S = Config.States

-- dossier de sons partagé par les éléments HUD (les fenêtres ont leur propre dossier "Sons")
local sons = Instance.new("Folder")
sons.Name = "SonsUI"
sons.Parent = playerGui
Motion.CreateSounds(sons)

local profile = nil
local ctx = {
	UI = UI, Motion = Motion, Icons = Icons, Config = Config, Cosmetics = Cosmetics, Signals = Signals, Audio = Audio,
	PlayerGui = playerGui, Sons = sons, Player = player,
	Abbreviate = function(n: number) return Motion.Abbreviate(n, "") end,
	Duration = Motion.Duration,
}

-- =====================================================================
-- PROFIL (défini avant les builders : les fenêtres l'utilisent dès leur construction)
-- =====================================================================
local hud, shop, inventory
function ctx.GetProfile() return profile end
function ctx.SetProfile(p)
	if not p then return end
	profile = p
	if hud then hud.SetCoins(p.Coins) end
	if shop then shop.Refresh(p) end
	if inventory then inventory.Refresh(p) end
end

hud = Hud.Build(ctx)
local notifs = Screens.BuildNotifications(ctx)
local roleScreen = Screens.BuildRoleScreen(ctx)
shop = Collection.Build(ctx, "Shop")
inventory = Collection.Build(ctx, "Inventory")
local results = Results.Build(ctx)

ctx.OpenShop = function() shop.Open() end
ctx.OpenInventory = function() inventory.Open() end
local lobbyMenu = LobbyMenu.Build(ctx)
Remotes.DataUpdated.OnClientEvent:Connect(ctx.SetProfile)
task.spawn(function()
	local ok, p = pcall(Remotes.GetProfile.InvokeServer, Remotes.GetProfile)
	if ok and p then ctx.SetProfile(p) end
end)

-- =====================================================================
-- RÔLE / STATS
-- =====================================================================
local function refreshRole()
	hud.SetRole(player:GetAttribute("Role") or "Lobby")
end
player:GetAttributeChangedSignal("Role"):Connect(refreshRole)
refreshRole()

player:GetAttributeChangedSignal("TailsTaken"):Connect(function()
	hud.SetTails(player:GetAttribute("TailsTaken") or 0)
end)
hud.SetTails(0)

-- =====================================================================
-- ÉTAT DE PARTIE
-- =====================================================================
local STATE_LABEL = {
	[S.Lobby] = "EN ATTENTE",
	[S.Intermission] = "INTERMISSION",
	[S.Countdown] = "PRÉPAREZ-VOUS",
	[S.Round] = "MANCHE",
	[S.Results] = "RÉSULTATS",
}

local function inRoundForMe(): boolean
	local st = ReplicatedStorage:GetAttribute("GameState")
	local role = player:GetAttribute("Role")
	return (st == S.Round or st == S.Countdown) and role ~= "Lobby" and role ~= nil
end

local function onState()
	local st = ReplicatedStorage:GetAttribute("GameState") or S.Lobby
	hud.SetState(STATE_LABEL[st] or st)
	local playing = inRoundForMe()
	lobbyMenu.SetVisible(not playing)
	if playing then
		shop.Close()
		inventory.Close()
		task.delay(0.35, function() lobbyMenu.SetVisible(not inRoundForMe()) end)
	end
	if st == S.Lobby or st == S.Results then roleScreen.Hide() end
end
ReplicatedStorage:GetAttributeChangedSignal("GameState"):Connect(onState)
player:GetAttributeChangedSignal("Role"):Connect(onState)
onState()

-- minuteur / sous-titre / restants / cooldown du dash
RunService.RenderStepped:Connect(function()
	local st = ReplicatedStorage:GetAttribute("GameState") or S.Lobby
	local endsAt = ReplicatedStorage:GetAttribute("EndsAt") or 0
	local now = workspace:GetServerTimeNow()
	local left = math.max(0, endsAt - now)
	if st == S.Lobby then
		local ready = ReplicatedStorage:GetAttribute("ReadyCount") or 0
		local min = ReplicatedStorage:GetAttribute("MinPlayers") or Config.MinPlayers
		hud.SetTimer(("%d/%d"):format(ready, min))
		hud.SetSub(if player:GetAttribute("Ready") then "Joueurs prêts" else 'Clique sur <font color="#B4FF3C">JOUER</font> pour participer')
	else
		hud.SetTimer(Motion.Duration(math.ceil(left)), st == S.Round and left <= 15)
		local release = ReplicatedStorage:GetAttribute("HuntersReleaseAt") or 0
		if st == S.Round and now < release then
			hud.SetSub(('Chasseurs lâchés dans <font color="#FF5A6A">%d</font>'):format(math.ceil(release - now)))
		elseif st == S.Intermission then
			hud.SetSub(if player:GetAttribute("Ready") then "La manche commence bientôt !" else 'Clique sur <font color="#B4FF3C">JOUER</font> pour participer')
		else
			hud.SetSub("")
		end
	end
	if st == S.Round or st == S.Countdown then
		local r = ReplicatedStorage:GetAttribute("RunnersLeft") or 0
		hud.SetRemaining(("%d participant%s"):format(r, if r > 1 then "s" else ""))
	else
		hud.SetRemaining("")
	end
	hud.UpdateDash(Signals.State.DashReadyAt, Signals.State.DashCooldown)
end)

-- =====================================================================
-- REMOTES
-- =====================================================================
Remotes.Notify.OnClientEvent:Connect(function(text: string, kind: string?)
	notifs.Push(text, kind)
	if kind == "success" then Signals.Fire("Shake", 0.5, 0.2) end
end)

Remotes.RoleAssigned.OnClientEvent:Connect(function(role: string, countdown: number)
	roleScreen.Show(role, countdown)
end)

Remotes.Results.OnClientEvent:Connect(function(data)
	roleScreen.Hide()
	results.Show(data)
end)

Remotes.OpenMenu.OnClientEvent:Connect(function(which: string)
	if inRoundForMe() then return end
	if which == "Shop" then shop.Open() elseif which == "Inventory" then inventory.Open() end
end)

Remotes.Captured.OnClientEvent:Connect(function(hunter: Player)
	if hunter == player then
		hud.SetTails(player:GetAttribute("TailsTaken") or 0)
	end
end)
