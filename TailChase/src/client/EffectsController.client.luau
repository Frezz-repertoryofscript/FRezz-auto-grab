--[[
	EffectsController - "juice" côté client (aucune logique de jeu ici).
		* balancement procédural des queues de tous les personnages (C0 des Joints)
		* traînée de dash (skin équipé, Attribute "TrailSkin") + élargissement bref du FOV pour le joueur local
		* poussière + son pendant le slide
		* capture : la queue vole vers le chasseur (arc + rotation), effet de capture du chasseur, sons, screen shake
		* jump pads : burst de particules
		* musique lobby / manche selon l'état
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local TailBuilder = require(ReplicatedStorage.Shared.TailBuilder)
local Signals = require(ReplicatedStorage.Shared.ClientSignals)
local Audio = require(ReplicatedStorage.Shared.Audio)
local Icons = require(ReplicatedStorage:WaitForChild("CheckUIIcons"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- =====================================================================
-- QUEUES : balancement procédural
-- =====================================================================
type TailData = { Joints: { Weld }, Root: BasePart?, Seed: number }
local tails: { [Model]: TailData } = {}

local function registerTail(char: Model, tail: Instance)
	local joints = {}
	for _, d in tail:GetDescendants() do
		if d:IsA("Weld") and d.Name == "Joint" then table.insert(joints, d) end
	end
	table.sort(joints, function(a, b) return (a:GetAttribute("Index") or 0) < (b:GetAttribute("Index") or 0) end)
	tails[char] = { Joints = joints, Root = char:FindFirstChild("HumanoidRootPart") :: BasePart?, Seed = math.random() * 10 }
end

local function watchCharacter(char: Model)
	local t = char:FindFirstChild("Tail")
	if t then registerTail(char, t) end
	char.ChildAdded:Connect(function(c)
		if c.Name == "Tail" then task.defer(registerTail, char, c) end
	end)
	char.ChildRemoved:Connect(function(c)
		if c.Name == "Tail" then tails[char] = nil end
	end)
end

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for char, d in tails do
		if not char.Parent then
			tails[char] = nil
			continue
		end
		local root = d.Root
		local vel = if root then root.AssemblyLinearVelocity else Vector3.zero
		local localVel = if root then root.CFrame:VectorToObjectSpace(vel) else Vector3.zero
		local fwd = math.clamp(-localVel.Z / 24, -0.5, 1.6)   -- vitesse vers l'avant -> la queue se soulève en arrière
		local side = math.clamp(localVel.X / 24, -1, 1)
		local fall = math.clamp(vel.Y / 40, -1, 1)
		for i, j in d.Joints do
			local base = j:GetAttribute("BaseC0")
			if typeof(base) == "CFrame" and j.Parent then
				local w = i / #d.Joints
				local wave = math.sin(t * (5 + fwd * 5) - i * 0.7 + d.Seed) * (0.12 + 0.18 * fwd) * (0.4 + w)
				local sway = math.sin(t * 1.9 + i * 0.5 + d.Seed) * 0.12 * (0.5 + w)
				local lift = -(0.28 * fwd + 0.15 * fall) * (if i == 1 then 1.4 else 0.55)
				j.C0 = base * CFrame.Angles(lift + wave, 0, sway - side * 0.25 * w)
			end
		end
	end
end)

-- =====================================================================
-- TRAÎNÉE DE DASH / POUSSIÈRE DE SLIDE (tous les personnages)
-- =====================================================================
local function trailItemFor(p: Player?)
	local id = p and p:GetAttribute("TrailSkin")
	return Cosmetics.Get(id) or Cosmetics.Get(Cosmetics.DefaultFor("Trail"))
end

local function ensureTrail(char: Model): Trail?
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end
	local tr = root:FindFirstChild("TC_DashTrail") :: Trail?
	local p = Players:GetPlayerFromCharacter(char)
	local item = trailItemFor(p)
	if not tr then
		local a0 = Instance.new("Attachment"); a0.Name = "TC_TrailTop"; a0.Position = Vector3.new(0, 1.2, 0.3); a0.Parent = root
		local a1 = Instance.new("Attachment"); a1.Name = "TC_TrailBottom"; a1.Position = Vector3.new(0, -1.6, 0.3); a1.Parent = root
		local newTr = Instance.new("Trail")
		newTr.Name = "TC_DashTrail"
		newTr.Attachment0 = a0
		newTr.Attachment1 = a1
		newTr.Lifetime = 0.35
		newTr.MinLength = 0.05
		newTr.LightEmission = 0.8
		newTr.FaceCamera = true
		newTr.Transparency = NumberSequence.new(0.1, 1)
		newTr.WidthScale = NumberSequence.new(1, 0.2)
		newTr.Enabled = false
		newTr.Parent = root
		tr = newTr
	end
	if item and item.Colors and tr then
		local cs = item.Colors
		tr.Color = if #cs >= 2 then ColorSequence.new(cs[1], cs[#cs]) else ColorSequence.new(cs[1])
	end
	return tr
end

local function ensureDust(char: Model): ParticleEmitter?
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end
	local pe = root:FindFirstChild("TC_SlideDust") :: ParticleEmitter?
	if pe then return pe end
	local att = Instance.new("Attachment"); att.Name = "TC_Feet"; att.Position = Vector3.new(0, -2.6, 0); att.Parent = root
	local e = Instance.new("ParticleEmitter")
	e.Name = "TC_SlideDust"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(235, 220, 200))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.4) })
	e.Transparency = NumberSequence.new(0.35, 1)
	e.Lifetime = NumberRange.new(0.4, 0.7)
	e.Rate = 45
	e.Speed = NumberRange.new(2, 5)
	e.SpreadAngle = Vector2.new(70, 20)
	e.Acceleration = Vector3.new(0, 3, 0)
	e.Enabled = false
	e.Parent = att
	return e
end

local function watchMovementFx(char: Model)
	char:GetAttributeChangedSignal("Dashing"):Connect(function()
		local on = char:GetAttribute("Dashing") == true
		local tr = ensureTrail(char)
		if not tr then return end
		if on then
			tr.Enabled = true
			if char ~= player.Character then
				Audio.Play("Dash", char:FindFirstChild("HumanoidRootPart"), 0.05)
			end
		else
			task.delay(0.2, function() if tr.Parent then tr.Enabled = false end end)
		end
	end)
	char:GetAttributeChangedSignal("Sliding"):Connect(function()
		local on = char:GetAttribute("Sliding") == true
		local dust = ensureDust(char)
		if dust then dust.Enabled = on end
		if on and char ~= player.Character then
			Audio.Play("Slide", char:FindFirstChild("HumanoidRootPart"), 0.05)
		end
	end)
end

local function onCharacter(char: Model)
	char:WaitForChild("HumanoidRootPart", 10)
	watchCharacter(char)
	watchMovementFx(char)
end

local function onPlayer(p: Player)
	p.CharacterAdded:Connect(onCharacter)
	if p.Character then task.spawn(onCharacter, p.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do onPlayer(p) end

-- dash local : traînée immédiate (sans attendre le serveur) + FOV
local baseFov = camera.FieldOfView
Signals.Connect("Dash", function()
	local char = player.Character
	if char then
		local tr = ensureTrail(char)
		if tr then
			tr.Enabled = true
			task.delay(Config.DashDuration + 0.25, function() if tr.Parent and char:GetAttribute("Dashing") ~= true then tr.Enabled = false end end)
		end
	end
	baseFov = if camera.FieldOfView > 60 and camera.FieldOfView < 90 then camera.FieldOfView else 70
	local up = TweenService:Create(camera, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = baseFov + Config.DashFovBoost })
	up:Play()
	task.delay(0.12, function()
		TweenService:Create(camera, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = baseFov }):Play()
	end)
	Signals.Fire("Shake", 0.25, 0.12)
end)

Signals.Connect("Slide", function(on: boolean)
	local char = player.Character
	local dust = char and ensureDust(char)
	if dust then dust.Enabled = on end
end)

-- =====================================================================
-- SCREEN SHAKE
-- =====================================================================
local shakeUntil, shakeAmp = 0, 0
Signals.Connect("Shake", function(amp: number, duration: number)
	shakeAmp = math.max(shakeAmp, amp)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end)
RunService:BindToRenderStep("TC_Shake", Enum.RenderPriority.Camera.Value + 1, function()
	local t = os.clock()
	if t < shakeUntil then
		local a = shakeAmp * math.clamp((shakeUntil - t) * 4, 0, 1)
		camera.CFrame = camera.CFrame * CFrame.Angles(math.rad((math.random() - 0.5) * a * 6), math.rad((math.random() - 0.5) * a * 6), 0)
	else
		shakeAmp = 0
	end
end)

-- =====================================================================
-- CAPTURE : la queue vole vers le chasseur
-- =====================================================================
local FX_TEXTURE = {
	Puff = "rbxasset://textures/particles/smoke_main.dds",
	Stars = Icons.Get("Main/Star/Golden Star 1st Outline"),
	Hearts = Icons.Get("Main/Heart/Heart 1st Outline"),
	Skull = Icons.Get("Player/Skull/Skull 1st Outline"),
	Coins = Icons.Get("Currency/Coin/Golden Coin 1st Outline"),
}

local function burst(pos: Vector3, fxId: string?)
	local item = Cosmetics.Get(fxId) or Cosmetics.Get(Cosmetics.DefaultFor("Capture"))
	local kind = item and item.Fx or "Puff"
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	local e = Instance.new("ParticleEmitter")
	e.Texture = FX_TEXTURE[kind] or FX_TEXTURE.Puff
	e.Color = ColorSequence.new(if kind == "Puff" then Color3.new(1, 1, 1) else Color3.new(1, 1, 1))
	e.Size = if kind == "Puff" then NumberSequence.new(1.5, 3.5) else NumberSequence.new(1.4, 0.4)
	e.Transparency = NumberSequence.new(0, 1)
	e.Lifetime = NumberRange.new(0.6, 1)
	e.Speed = NumberRange.new(12, 22)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(-30, 30)
	e.RotSpeed = NumberRange.new(-120, 120)
	e.Acceleration = Vector3.new(0, if kind == "Puff" then 4 else -30, 0)
	e.Drag = 3
	e.Rate = 0
	e.Parent = p
	e:Emit(if kind == "Puff" then 18 else 24)
	-- anneau de choc
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = item and item.Color or Color3.new(1, 1, 1)
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.2
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, 14, 14), Transparency = 1 }):Play()
	Debris:AddItem(p, 2)
	Debris:AddItem(ring, 0.5)
end

Remotes.Captured.OnClientEvent:Connect(function(hunter: Player, runner: Player, skin: string?, fxId: string?, tailCF: CFrame?)
	local hChar = hunter and hunter.Character
	local rChar = runner and runner.Character
	local hRoot = hChar and hChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local rRoot = rChar and rChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local startCF = tailCF or (rRoot and rRoot.CFrame * CFrame.new(0, 0, 0.8))
	if rRoot then Audio.Play("CaptureWhoosh", rRoot, 0.05) end

	-- secousse : forte pour les 2 joueurs concernés, légère pour les proches
	local me = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if player == hunter or player == runner then
		Signals.Fire("Shake", 1, 0.35)
	elseif me and rRoot and (me.Position - rRoot.Position).Magnitude < 40 then
		Signals.Fire("Shake", 0.35, 0.2)
	end

	if not startCF or not hRoot then
		if hRoot then burst(hRoot.Position, fxId) end
		return
	end
	-- queue volante (copie locale, purement visuelle)
	local tail = TailBuilder.Build(skin, nil)
	local seg1 = tail:FindFirstChild("Seg1") :: BasePart
	for _, d in tail:GetDescendants() do
		if d:IsA("BasePart") then d.Anchored = false end
	end
	seg1.Anchored = true
	seg1.CFrame = startCF
	tail.Parent = workspace
	local t0 = os.clock()
	local DUR = 0.45
	local from = startCF.Position
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / DUR, 0, 1)
		local target = if hRoot.Parent then hRoot.Position + Vector3.new(0, 0.5, 0) else from
		local e = 1 - (1 - a) ^ 3
		local pos = from:Lerp(target, e) + Vector3.new(0, math.sin(a * math.pi) * 5, 0)
		local scale = 1 - 0.6 * a
		_ = scale
		seg1.CFrame = CFrame.new(pos) * CFrame.Angles(a * 9, a * 6, 0)
		if a >= 1 then
			conn:Disconnect()
			tail:Destroy()
			burst(target, fxId)
			Audio.Play("Capture", hRoot)
		end
	end)
end)

-- =====================================================================
-- JUMP PADS
-- =====================================================================
Signals.Connect("JumpPad", function(pad: BasePart)
	local att = pad:FindFirstChildOfClass("Attachment")
	local pe = att and att:FindFirstChildOfClass("ParticleEmitter")
	if pe then pe:Emit(25) end
	Signals.Fire("Shake", 0.2, 0.1)
end)

-- =====================================================================
-- MUSIQUE
-- =====================================================================
local function updateMusic()
	local state = ReplicatedStorage:GetAttribute("GameState")
	local role = player:GetAttribute("Role")
	if (state == Config.States.Round or state == Config.States.Countdown) and role ~= "Lobby" then
		Audio.Music("MusicRound")
	else
		Audio.Music("MusicLobby")
	end
end
ReplicatedStorage:GetAttributeChangedSignal("GameState"):Connect(updateMusic)
player:GetAttributeChangedSignal("Role"):Connect(updateMusic)
updateMusic()
