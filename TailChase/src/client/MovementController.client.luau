--[[
	MovementController - dash, slide et jump pads du joueur local.
		Dash  : Q / Shift / bouton mobile / manette X  -> impulsion horizontale, cooldown Config.DashCooldown
		Slide : C / Ctrl  / bouton mobile / manette Y  -> glissade qui conserve l'élan ; le personnage passe dans le
		        CollisionGroup "Sliders" (hitbox réduite) et traverse les plafonds des mini-tunnels.
		        Si le slide se termine sous un plafond, on reste accroupi (vitesse réduite) jusqu'à la sortie.
	La physique est appliquée localement (réactivité), le serveur valide les cooldowns (MovementService).
	Toutes les connexions liées au personnage sont déconnectées à sa mort / respawn.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Signals = require(ReplicatedStorage.Shared.ClientSignals)
local Audio = require(ReplicatedStorage.Shared.Audio)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local State = Signals.State

local char: Model?, hum: Humanoid?, root: BasePart?
local charConns: { RBXScriptConnection } = {}

local sliding = false
local crouchLocked = false
local slideReadyAt = 0
local lastPad = 0
local baseWalkSpeed: number? = nil

local function disconnectAll()
	for _, c in charConns do c:Disconnect() end
	table.clear(charConns)
end

local function frozen(): boolean
	return player:GetAttribute("Frozen") == true
end

local function alive(): boolean
	return hum ~= nil and root ~= nil and hum.Health > 0 and root.Parent ~= nil
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function setGroup(group: string)
	if not char then return end
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") and d.Parent and d.Parent.Name ~= "Tail" then
			d.CollisionGroup = group
		end
	end
end

--- Contrainte de vitesse horizontale (Y libre) attachée au RootAttachment.
local function makeMover(name: string): LinearVelocity?
	if not root then return nil end
	local att = root:FindFirstChild("RootAttachment") or root:FindFirstChildOfClass("Attachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "RootAttachment"
		att.Parent = root
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = name
	lv.Attachment0 = att :: Attachment
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(1e5, 0, 1e5)
	lv.Parent = root
	return lv
end

local function moveDir(): Vector3
	if not hum or not root then return Vector3.new(0, 0, -1) end
	local md = flat(hum.MoveDirection)
	if md.Magnitude > 0.1 then return md.Unit end
	local look = flat(root.CFrame.LookVector)
	return if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
end

-- =====================================================================
-- DASH
-- =====================================================================
local function dash()
	if not alive() or frozen() or crouchLocked then return end
	local t = os.clock()
	if t < State.DashReadyAt then return end
	State.DashReadyAt = t + Config.DashCooldown
	State.DashCooldown = Config.DashCooldown
	Remotes.MoveAction:FireServer("Dash")
	Signals.Fire("Dash", Config.DashCooldown)
	Audio.Play("Dash", root, 0.05)

	local dir = moveDir()
	local lv = makeMover("DashVelocity")
	if not lv then return end
	lv.VectorVelocity = dir * Config.DashSpeed
	local r = root :: BasePart
	task.delay(Config.DashDuration, function()
		lv:Destroy()
		-- on garde un peu d'élan à la sortie
		if r.Parent then
			local v = r.AssemblyLinearVelocity
			r.AssemblyLinearVelocity = Vector3.new(dir.X * Config.RunnerWalkSpeed * 1.4, v.Y, dir.Z * Config.RunnerWalkSpeed * 1.4)
		end
	end)
end

-- =====================================================================
-- SLIDE
-- =====================================================================
local ceilingParams = RaycastParams.new()
ceilingParams.FilterType = Enum.RaycastFilterType.Include

local function underCeiling(): boolean
	if not root then return false end
	ceilingParams.FilterDescendantsInstances = CollectionService:GetTagged("SlideCeiling")
	local origin = root.Position - Vector3.new(0, 1.5, 0)
	-- plusieurs rayons : centre + devant / derrière
	for _, off in { Vector3.zero, root.CFrame.LookVector * 1.2, -root.CFrame.LookVector * 1.2 } do
		if workspace:Raycast(origin + off, Vector3.new(0, 5, 0), ceilingParams) then return true end
	end
	return false
end

local function standUp()
	if not hum then return end
	sliding = false
	crouchLocked = false
	State.Sliding = false
	setGroup("Default")
	if baseWalkSpeed and not frozen() then
		-- vitesse du rôle courant (le rôle a pu changer pendant le slide)
		local role = player:GetAttribute("Role")
		hum.WalkSpeed = if role == "Hunter" then Config.HunterWalkSpeed elseif role == "Runner" then Config.RunnerWalkSpeed else Config.LobbyWalkSpeed
	end
	baseWalkSpeed = nil
	TweenService:Create(hum, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { CameraOffset = Vector3.zero }):Play()
	Remotes.MoveAction:FireServer("SlideEnd")
	Signals.Fire("Slide", false)
end

local function slide()
	if not alive() or frozen() or sliding then return end
	local h = hum :: Humanoid
	local r = root :: BasePart
	if h.FloorMaterial == Enum.Material.Air then return end
	local t0 = os.clock()
	if t0 < slideReadyAt then return end
	slideReadyAt = t0 + Config.SlideCooldown + Config.SlideDuration

	sliding = true
	State.Sliding = true
	setGroup("Sliders")
	Remotes.MoveAction:FireServer("SlideStart")
	Signals.Fire("Slide", true)
	Audio.Play("Slide", r, 0.05)
	TweenService:Create(h, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { CameraOffset = Vector3.new(0, Config.SlideCameraOffset, 0) }):Play()

	local v = flat(r.AssemblyLinearVelocity)
	local dir = if v.Magnitude > 2 then v.Unit else moveDir()
	local speed = math.clamp(math.max(v.Magnitude, h.WalkSpeed) * Config.SlideBoost, Config.SlideMinSpeed, Config.SlideMaxSpeed)
	local lv = makeMover("SlideVelocity")
	baseWalkSpeed = h.WalkSpeed

	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		if not alive() or not sliding or frozen() then
			conn:Disconnect()
			if lv then lv:Destroy() end
			if sliding then standUp() end
			return
		end
		local elapsed = os.clock() - t0
		local jumped = h:GetState() == Enum.HumanoidStateType.Jumping
		if lv and (elapsed < Config.SlideDuration and not jumped) then
			-- léger contrôle de direction + friction
			local md = flat(h.MoveDirection)
			if md.Magnitude > 0.1 then dir = (dir + md.Unit * dt * 2.2).Unit end
			speed = math.max(Config.SlideCrouchSpeed, speed * (1 - Config.SlideFriction * dt * 0.5))
			lv.VectorVelocity = dir * speed
			return
		end
		if lv then
			lv:Destroy()
			lv = nil
			-- conserve l'élan à la sortie (et sur un saut)
			local cur = r.AssemblyLinearVelocity
			r.AssemblyLinearVelocity = Vector3.new(dir.X * speed, cur.Y, dir.Z * speed)
		end
		if underCeiling() then
			-- encore sous un tunnel : on reste accroupi
			crouchLocked = true
			h.WalkSpeed = Config.SlideCrouchSpeed
			return
		end
		conn:Disconnect()
		standUp()
	end)
	table.insert(charConns, conn)
end

-- =====================================================================
-- JUMP PADS
-- =====================================================================
local padParams = RaycastParams.new()
padParams.FilterType = Enum.RaycastFilterType.Include

local function checkPads()
	if not alive() or frozen() then return end
	local r = root :: BasePart
	local h = hum :: Humanoid
	if os.clock() - lastPad < Config.JumpPadCooldown then return end
	padParams.FilterDescendantsInstances = CollectionService:GetTagged("JumpPad")
	local hit = workspace:Raycast(r.Position, Vector3.new(0, -(h.HipHeight + 2.2), 0), padParams)
	if hit and hit.Instance then
		lastPad = os.clock()
		local pad = hit.Instance
		local power = pad:GetAttribute("Power") or Config.JumpPadPower
		local push = pad:GetAttribute("Push") or Vector3.zero
		h:ChangeState(Enum.HumanoidStateType.Jumping)
		local cur = flat(r.AssemblyLinearVelocity)
		r.AssemblyLinearVelocity = Vector3.new(push.X + cur.X * 0.3, power, push.Z + cur.Z * 0.3)
		Audio.Play("JumpPad", r, 0.05)
		Signals.Fire("JumpPad", pad)
	end
end

-- =====================================================================
-- PERSONNAGE
-- =====================================================================
local function onCharacter(c: Model)
	disconnectAll()
	sliding, crouchLocked, baseWalkSpeed = false, false, nil
	State.Sliding = false
	char = c
	hum = c:WaitForChild("Humanoid", 10) :: Humanoid
	root = c:WaitForChild("HumanoidRootPart", 10) :: BasePart
	if not hum or not root then return end
	table.insert(charConns, RunService.Heartbeat:Connect(checkPads))
	table.insert(charConns, hum.Died:Connect(function()
		sliding = false
		State.Sliding = false
		disconnectAll()
	end))
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then task.spawn(onCharacter, player.Character) end

player:GetAttributeChangedSignal("Frozen"):Connect(function()
	if frozen() and sliding then standUp() end
end)

-- refus serveur du dash (cooldown) : on resynchronise le cooldown local
player:GetAttributeChangedSignal("DashRejected"):Connect(function()
	State.DashReadyAt = math.max(State.DashReadyAt, os.clock() + 0.5)
end)

-- =====================================================================
-- ENTRÉES
-- =====================================================================
local function onAction(name: string, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	if name == "TC_Dash" then dash() elseif name == "TC_Slide" then slide() end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindActionAtPriority("TC_Dash", onAction, false, Enum.ContextActionPriority.High.Value,
	Enum.KeyCode.Q, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonX)
ContextActionService:BindActionAtPriority("TC_Slide", onAction, false, Enum.ContextActionPriority.High.Value,
	Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonY)

-- boutons tactiles (créés par UIController)
Signals.Connect("MobileAction", function(name: string)
	if name == "Dash" then dash() elseif name == "Slide" then slide() end
end)
