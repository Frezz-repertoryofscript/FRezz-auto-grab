--[[
	AnimationController - animations procédurales (R15) pour TOUS les personnages, calculées localement.
	Aucun ID d'animation n'est nécessaire : on écrit Motor6D.Transform à chaque frame (après l'Animator).

	Le script "Animate" par défaut du joueur local est désactivé, donc aucun track n'est répliqué : chaque client
	anime tous les personnages à partir de leur vitesse (répliquée) et de leurs Attributes (Dashing / Sliding).

	Poses :
		Idle  : respiration (torse + épaules), léger balancement de la tête
		Walk / Run : balancement du torse, bras expressifs, rebond au run, inclinaison avant selon la vitesse
		Air   : bras écartés, jambes décalées
		Dash  : corps penché, bras en arrière, jambes tendues
		Slide : corps renversé en arrière et abaissé, jambes devant, un bras levé
		Rip   : (chasseur qui capture) bras qui attrape puis tire en arrière + rotation du torse
		Flinch: (participant capturé) sursaut bras levés
	Rig R6 : non géré procéduralement -> l'Animate par défaut reste actif (règle le jeu en R15 dans Game Settings > Avatar).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local JOINTS = {
	Root = { "LowerTorso", "Root" },
	Waist = { "UpperTorso", "Waist" },
	Neck = { "Head", "Neck" },
	RShoulder = { "RightUpperArm", "RightShoulder" },
	LShoulder = { "LeftUpperArm", "LeftShoulder" },
	RElbow = { "RightLowerArm", "RightElbow" },
	LElbow = { "LeftLowerArm", "LeftElbow" },
	RHip = { "RightUpperLeg", "RightHip" },
	LHip = { "LeftUpperLeg", "LeftHip" },
	RKnee = { "RightLowerLeg", "RightKnee" },
	LKnee = { "LeftLowerLeg", "LeftKnee" },
}

type Rig = {
	Char: Model, Hum: Humanoid, RootPart: BasePart,
	Motors: { [string]: Motor6D }, Current: { [string]: CFrame },
	Phase: number, Action: string?, ActionStart: number, ActionLen: number, Conns: { RBXScriptConnection },
}

local rigs: { [Model]: Rig } = {}

local function A(x: number, y: number, z: number): CFrame
	return CFrame.Angles(x, y, z)
end

local function buildRig(char: Model): Rig?
	local hum = char:FindFirstChildOfClass("Humanoid")
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not rootPart or hum.RigType ~= Enum.HumanoidRigType.R15 then return nil end
	local motors = {}
	for key, path in JOINTS do
		local part = char:FindFirstChild(path[1])
		local m = part and part:FindFirstChild(path[2])
		if m and m:IsA("Motor6D") then motors[key] = m end
	end
	if not motors.Root then return nil end
	local cur = {}
	for k in motors do cur[k] = CFrame.identity end
	return { Char = char, Hum = hum, RootPart = rootPart, Motors = motors, Current = cur, Phase = 0,
		Action = nil, ActionStart = 0, ActionLen = 0, Conns = {} }
end

local function removeRig(char: Model)
	local r = rigs[char]
	if not r then return end
	for _, c in r.Conns do c:Disconnect() end
	for _, m in r.Motors do if m.Parent then m.Transform = CFrame.identity end end
	rigs[char] = nil
end

local function trackCharacter(char: Model)
	task.spawn(function()
		char:WaitForChild("HumanoidRootPart", 10)
		char:WaitForChild("Humanoid", 10)
		char:WaitForChild("LowerTorso", 10)
		if not char.Parent then return end
		local r = buildRig(char)
		if not r then return end
		removeRig(char)
		rigs[char] = r
		if char == player.Character then
			-- coupe l'Animate par défaut (walk/run/idle remplacés par les versions procédurales)
			local anim = char:FindFirstChild("Animate")
			if anim and anim:IsA("LocalScript") then anim.Enabled = false end
			local animator = r.Hum:FindFirstChildOfClass("Animator")
			if animator then
				for _, t in animator:GetPlayingAnimationTracks() do t:Stop(0) end
				table.insert(r.Conns, animator.AnimationPlayed:Connect(function(track)
					-- sécurité : un track joué malgré tout (outil, émote) n'écrase pas nos poses de base
					if track.Priority == Enum.AnimationPriority.Core then track:Stop(0) end
				end))
			end
		end
		table.insert(r.Conns, char.AncestryChanged:Connect(function()
			if not char.Parent then removeRig(char) end
		end))
		-- les parties peuvent être remplacées au chargement de l'apparence
		table.insert(r.Conns, char.ChildAdded:Connect(function(c)
			if c:IsA("BasePart") then
				task.defer(function()
					if rigs[char] == r then
						local nr = buildRig(char)
						if nr then
							nr.Conns = r.Conns
							rigs[char] = nr
						end
					end
				end)
			end
		end))
	end)
end

local function playAction(char: Model?, name: string, length: number)
	local r = char and rigs[char]
	if not r then return end
	r.Action = name
	r.ActionStart = os.clock()
	r.ActionLen = length
end

-- =====================================================================
-- POSES
-- =====================================================================
local function computePose(r: Rig, dt: number, t: number): { [string]: CFrame }
	local pose: { [string]: CFrame } = {}
	local vel = r.RootPart.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local state = r.Hum:GetState()
	local inAir = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
	local sliding = r.Char:GetAttribute("Sliding") == true
	local dashing = r.Char:GetAttribute("Dashing") == true

	if sliding then
		pose.Root = CFrame.new(0, -1.35, 0.2) * A(1.05, 0, 0)
		pose.Waist = A(-0.35, 0.15, 0)
		pose.Neck = A(-0.55, 0, 0)
		pose.RHip = A(1.25, 0, 0.05)
		pose.LHip = A(0.75, 0, -0.08)
		pose.RKnee = A(-0.1, 0, 0)
		pose.LKnee = A(-1.1, 0, 0)
		pose.RShoulder = A(0.5, 0, 1.25)
		pose.LShoulder = A(-0.6, 0, -0.45)
		pose.RElbow = A(0.4, 0, 0)
		pose.LElbow = A(0.6, 0, 0)
	elseif dashing then
		pose.Root = A(-0.45, 0, 0)
		pose.Waist = A(-0.2, 0, 0)
		pose.Neck = A(0.35, 0, 0)
		pose.RShoulder = A(-1.25, 0, 0.35)
		pose.LShoulder = A(-1.25, 0, -0.35)
		pose.RElbow = A(0.2, 0, 0)
		pose.LElbow = A(0.2, 0, 0)
		pose.RHip = A(0.7, 0, 0)
		pose.LHip = A(-0.6, 0, 0)
		pose.RKnee = A(-0.6, 0, 0)
		pose.LKnee = A(-0.2, 0, 0)
	elseif inAir then
		local up = math.clamp(vel.Y / 40, -1, 1)
		pose.Root = A(-0.08, 0, 0)
		pose.Waist = A(0.05 * up, 0, 0)
		pose.Neck = A(0.15 * up, 0, 0)
		pose.RShoulder = A(0.3 + 0.4 * up, 0, 0.9)
		pose.LShoulder = A(0.3 + 0.4 * up, 0, -0.9)
		pose.RElbow = A(0.6, 0, 0)
		pose.LElbow = A(0.6, 0, 0)
		pose.RHip = A(0.55, 0, 0.05)
		pose.LHip = A(-0.25, 0, -0.05)
		pose.RKnee = A(-0.9, 0, 0)
		pose.LKnee = A(-0.35, 0, 0)
	elseif speed > 1.2 then
		-- cycle de course : fréquence liée à la vitesse
		local k = math.clamp(speed / 22, 0, 1.35) -- 0..1 = walk -> run
		r.Phase += dt * (5 + speed * 0.42)
		local p = r.Phase
		local s = math.sin(p)
		local legAmp = 0.45 + 0.55 * k
		local armAmp = 0.5 + 0.7 * k
		local bounce = math.abs(math.cos(p)) * 0.28 * k
		pose.Root = CFrame.new(0, bounce - 0.08 * k, 0) * A(-0.12 * k, s * 0.1, 0)
		pose.Waist = A(-0.08 * k, -s * 0.22 * (0.5 + k), s * 0.04)
		pose.Neck = A(0.1 * k, s * 0.15, 0)
		pose.RHip = A(s * legAmp, 0, 0)
		pose.LHip = A(-s * legAmp, 0, 0)
		pose.RKnee = A(-0.15 - legAmp * 1.1 * math.max(0, math.sin(p + 1.4)), 0, 0)
		pose.LKnee = A(-0.15 - legAmp * 1.1 * math.max(0, math.sin(p + 1.4 + math.pi)), 0, 0)
		pose.RShoulder = A(-s * armAmp, 0, 0.12 + 0.1 * k)
		pose.LShoulder = A(s * armAmp, 0, -0.12 - 0.1 * k)
		pose.RElbow = A(0.35 + 0.6 * k + math.max(0, -s) * 0.4, 0, 0)
		pose.LElbow = A(0.35 + 0.6 * k + math.max(0, s) * 0.4, 0, 0)
	else
		-- idle : respiration
		local b = math.sin(t * 2.1)
		pose.Root = CFrame.new(0, b * 0.035, 0)
		pose.Waist = A(b * 0.035, math.sin(t * 0.7) * 0.05, 0)
		pose.Neck = A(-b * 0.04, math.sin(t * 0.9) * 0.12, 0)
		pose.RShoulder = A(0.05, 0, 0.1 + b * 0.04)
		pose.LShoulder = A(0.05, 0, -0.1 - b * 0.04)
		pose.RElbow = A(0.18, 0, 0)
		pose.LElbow = A(0.18, 0, 0)
		pose.RHip = A(0, 0, 0.03)
		pose.LHip = A(0, 0, -0.03)
		pose.RKnee = A(-0.04, 0, 0)
		pose.LKnee = A(-0.04, 0, 0)
	end

	-- actions ponctuelles superposées
	if r.Action then
		local a = (os.clock() - r.ActionStart) / r.ActionLen
		if a >= 1 then
			r.Action = nil
		elseif r.Action == "Rip" then
			-- 0 -> 0.35 : bras qui attrape devant ; 0.35 -> 1 : tire en arrière en tournant le torse
			local grab = math.clamp(a / 0.35, 0, 1)
			local pull = math.clamp((a - 0.35) / 0.65, 0, 1)
			local arm = 1.7 * grab - 2.4 * pull
			pose.RShoulder = A(arm, 0, 0.2)
			pose.RElbow = A(0.2 + 0.9 * pull, 0, 0)
			pose.Waist = (pose.Waist or CFrame.identity) * A(0, -0.6 * grab + 1.0 * pull, 0)
		elseif r.Action == "Flinch" then
			local f = math.sin(a * math.pi)
			pose.RShoulder = A(0.4 * f, 0, 1.6 * f)
			pose.LShoulder = A(0.4 * f, 0, -1.6 * f)
			pose.Waist = (pose.Waist or CFrame.identity) * A(0.35 * f, 0, 0)
			pose.Neck = A(0.4 * f, 0, 0)
		end
	end
	return pose
end

RunService.Stepped:Connect(function(_, dt)
	local t = os.clock()
	local alpha = 1 - math.exp(-dt * 14)
	for char, r in rigs do
		if r.Hum.Health > 0 and r.RootPart.Parent then
			local pose = computePose(r, dt, t)
			for key, motor in r.Motors do
				local target = pose[key] or CFrame.identity
				local cur = r.Current[key] or CFrame.identity
				cur = cur:Lerp(target, alpha)
				r.Current[key] = cur
				if motor.Parent then motor.Transform = cur end
			end
		end
		_ = char
	end
end)

-- =====================================================================
-- SUIVI DES PERSONNAGES
-- =====================================================================
local function onPlayer(p: Player)
	p.CharacterAdded:Connect(trackCharacter)
	if p.Character then trackCharacter(p.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do onPlayer(p) end
Players.PlayerRemoving:Connect(function(p)
	if p.Character then removeRig(p.Character) end
end)

-- animation d'arrachage de queue (chasseur) + sursaut (participant capturé)
Remotes.Captured.OnClientEvent:Connect(function(hunter: Player, runner: Player)
	if hunter and hunter.Character then playAction(hunter.Character, "Rip", 0.55) end
	if runner and runner.Character then playAction(runner.Character, "Flinch", 0.45) end
end)
