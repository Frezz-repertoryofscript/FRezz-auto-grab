--[[
	RoleService - rôle de chaque joueur et visuels associés.
	Rôles (Player Attribute "Role") :
		"Lobby"   dans le lobby (queue cosmétique visible pour montrer son skin)
		"Runner"  participant : queue dans le dos
		"Hunter"  chasseur : Highlight ROUGE visible à travers les murs + BillboardGui "HUNTER", pas de queue
	Attributes complémentaires : "Frozen" (décompte), "ImmuneUntil" (anti-chaîne, temps serveur).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local UI = require(ReplicatedStorage.StudUI)
local Icons = require(ReplicatedStorage.CheckUIIcons)
local TailService = require(script.Parent.TailService)

local RoleService = {}

local function clearVisuals(char: Model)
	for _, n in { "HunterHighlight", "HunterTag" } do
		local o = char:FindFirstChild(n, true)
		if o then o:Destroy() end
	end
end

local function hunterVisuals(char: Model)
	local hl = Instance.new("Highlight")
	hl.Name = "HunterHighlight"
	hl.FillColor = Config.HunterColor
	hl.FillTransparency = 0.72
	hl.OutlineColor = Color3.fromRGB(255, 20, 40)
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = char
	hl.Parent = char

	local head = char:FindFirstChild("Head")
	if head then
		local bb = Instance.new("BillboardGui")
		bb.Name = "HunterTag"
		bb.Size = UDim2.fromOffset(190, 56)
		bb.StudsOffset = Vector3.new(0, 2.6, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 250
		bb.LightInfluence = 0
		bb.Adornee = head
		bb.Parent = head
		local icon = UI.Image(bb, Icons.Get("Player/Skull/Skull 1st Outline"), { Size = UDim2.fromOffset(46, 46),
			Position = UDim2.new(0, 22, 0.5, 0), Rotation = -10, ZIndex = 8 })
		_ = icon
		UI.ShadowText(bb, "HUNTER", { Font = "Gotham", Size = UDim2.new(1, -46, 1, 0), Position = UDim2.new(0.5, 23, 0.5, 0),
			Max = 40, Stroke = Color3.fromRGB(60, 0, 8), Thickness = 3.4, Gradient = UI.seq(Color3.fromRGB(255, 120, 120), Color3.fromRGB(255, 20, 40)) })
	end
end

function RoleService.Get(player: Player): string
	return player:GetAttribute("Role") or "Lobby"
end

--- Applique les visuels + la vitesse du rôle courant au personnage actuel.
function RoleService.ApplyVisuals(player: Player)
	local char = player.Character
	if not char then return end
	local role = RoleService.Get(player)
	clearVisuals(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if role == "Hunter" then
		TailService.Remove(player)
		hunterVisuals(char)
		if hum then hum.WalkSpeed = Config.HunterWalkSpeed end
	elseif role == "Runner" then
		TailService.Give(player)
		if hum then hum.WalkSpeed = Config.RunnerWalkSpeed end
	else
		TailService.Give(player)
		if hum then hum.WalkSpeed = Config.LobbyWalkSpeed end
	end
	if hum then
		hum.UseJumpPower = true
		hum.JumpPower = Config.JumpPower
	end
	RoleService.ApplyFreeze(player)
end

function RoleService.Set(player: Player, role: string)
	player:SetAttribute("Role", role)
	RoleService.ApplyVisuals(player)
end

--- Gèle / dégèle (décompte de début de manche, départ retardé des chasseurs).
function RoleService.SetFrozen(player: Player, frozen: boolean)
	player:SetAttribute("Frozen", frozen)
	RoleService.ApplyFreeze(player)
end

function RoleService.ApplyFreeze(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local role = RoleService.Get(player)
	if player:GetAttribute("Frozen") then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
	else
		hum.WalkSpeed = if role == "Hunter" then Config.HunterWalkSpeed elseif role == "Runner" then Config.RunnerWalkSpeed else Config.LobbyWalkSpeed
		hum.JumpPower = Config.JumpPower
	end
end

return RoleService
