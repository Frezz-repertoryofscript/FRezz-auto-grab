--[[
	AdminService - commandes du panel admin (RemoteFunction Remotes.AdminCommand), vérifiées côté serveur.
	Qui est admin : tout le monde en Studio ; en ligne, le créateur du jeu (ou rang >= Config.AdminGroupRank si le jeu
	appartient à un groupe) + Config.Admins. Player Attribute "IsAdmin" -> le client affiche la tuile Admin.

	Commandes :
		"Start"      lance la manche tout de suite (tout le monde devient prêt, intermission sautée)
		"End"        termine la manche en cours (résultats normaux)
		"AllReady"   met tous les joueurs « prêts »
		"Coins"      +Config.AdminCoinsGift pièces pour l'admin
		"ShortRound" bascule la durée de manche : Config.RoundTime <-> Config.AdminShortRoundTime
		"ResetTuto"  rejoue le tutoriel au prochain affichage
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local AdminService = {}

-- état lu par GameManager
AdminService.Control = {
	ForceStart = false,
	ForceEnd = false,
	ShortRound = false,
}

function AdminService.IsAdmin(player: Player): boolean
	if RunService:IsStudio() then return true end
	if table.find(Config.Admins, player.UserId) then return true end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
	return ok and rank >= Config.AdminGroupRank
end

function AdminService.RoundTime(): number
	return if AdminService.Control.ShortRound then Config.AdminShortRoundTime else Config.RoundTime
end

local function reply(ok: boolean, msg: string)
	return { Ok = ok, Message = msg, ShortRound = AdminService.Control.ShortRound }
end

local function run(player: Player, cmd: any)
	if not AdminService.IsAdmin(player) then return reply(false, "Accès refusé") end
	if typeof(cmd) ~= "string" then return reply(false, "Commande invalide") end
	local state = ReplicatedStorage:GetAttribute("GameState")
	local S = Config.States
	if cmd == "Start" then
		if state == S.Round or state == S.Countdown then return reply(false, "Une manche est déjà en cours") end
		for _, p in Players:GetPlayers() do p:SetAttribute("Ready", true) end
		AdminService.Control.ForceStart = true
		return reply(true, "Lancement de la manche !")
	elseif cmd == "End" then
		if state ~= S.Round and state ~= S.Countdown then return reply(false, "Aucune manche en cours") end
		AdminService.Control.ForceEnd = true
		return reply(true, "Fin de manche demandée")
	elseif cmd == "AllReady" then
		for _, p in Players:GetPlayers() do p:SetAttribute("Ready", true) end
		return reply(true, "Tout le monde est prêt")
	elseif cmd == "Coins" then
		DataService.AddCoins(player, Config.AdminCoinsGift)
		return reply(true, "+" .. Config.AdminCoinsGift .. " pièces")
	elseif cmd == "ShortRound" then
		AdminService.Control.ShortRound = not AdminService.Control.ShortRound
		return reply(true, if AdminService.Control.ShortRound then ("Manches de %d s"):format(Config.AdminShortRoundTime) else ("Manches de %d s"):format(Config.RoundTime))
	elseif cmd == "ResetTuto" then
		local d = DataService.Get(player)
		if d then
			d.TutorialDone = false
			DataService.Push(player)
		end
		return reply(true, "Tutoriel réinitialisé")
	end
	return reply(false, "Commande inconnue")
end

function AdminService.Init()
	Remotes.AdminCommand.OnServerInvoke = run
	local function tag(p: Player)
		task.spawn(function() p:SetAttribute("IsAdmin", AdminService.IsAdmin(p)) end)
	end
	Players.PlayerAdded:Connect(tag)
	for _, p in Players:GetPlayers() do tag(p) end
end

return AdminService
