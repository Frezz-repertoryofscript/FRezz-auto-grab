--[[
	MovementService - validation serveur du dash et du slide.
	Le client applique la physique tout de suite (réactivité) et prévient le serveur via Remotes.MoveAction :
		"Dash"        -> cooldown vérifié (Config.DashCooldown - tolérance). Refusé => Attribute "DashRejected" (le client se corrige).
		"SlideStart"  -> cooldown vérifié, personnage passé dans le CollisionGroup "Sliders" (traverse les plafonds de tunnel)
		"SlideEnd"    -> retour au groupe par défaut
	Les Attributes "Dashing" / "Sliding" du personnage servent aux effets et animations de TOUS les clients.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local MovementService = {}

local lastDash: { [Player]: number } = {}
local lastSlide: { [Player]: number } = {}

local function setGroup(char: Model, group: string)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") and d.Parent and d.Parent.Name ~= "Tail" then
			d.CollisionGroup = group
		end
	end
end

local function canMove(player: Player): boolean
	if player:GetAttribute("Frozen") then return false end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

function MovementService.EndSlide(player: Player)
	local char = player.Character
	if char then
		char:SetAttribute("Sliding", false)
		setGroup(char, "Default")
	end
end

local function onAction(player: Player, action: any)
	if typeof(action) ~= "string" then return end
	local now = os.clock()
	local char = player.Character
	if not char then return end
	if action == "Dash" then
		local last = lastDash[player] or 0
		if not canMove(player) or now - last < Config.DashCooldown - Config.DashServerTolerance then
			player:SetAttribute("DashRejected", now)
			return
		end
		lastDash[player] = now
		char:SetAttribute("Dashing", true)
		task.delay(Config.DashDuration + 0.1, function()
			if char.Parent then char:SetAttribute("Dashing", false) end
		end)
	elseif action == "SlideStart" then
		local last = lastSlide[player] or 0
		if not canMove(player) or now - last < Config.SlideCooldown - Config.DashServerTolerance then return end
		lastSlide[player] = now
		char:SetAttribute("Sliding", true)
		setGroup(char, "Sliders")
	elseif action == "SlideEnd" then
		MovementService.EndSlide(player)
	end
end

function MovementService.Init()
	Remotes.MoveAction.OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(p)
		lastDash[p] = nil
		lastSlide[p] = nil
	end)
end

return MovementService
