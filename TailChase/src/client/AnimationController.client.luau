--[[
	AnimationController - animations custom de TOUS les personnages (R15), calculées localement à chaque frame.

	États (déduits de la vitesse répliquée, de l'état Humanoid et des Attributes Sliding / Dashing) :
		Idle  : respiration, transfert de poids, coup d'œil à gauche / droite toutes les ~4 s
		Walk  : petite foulée souple, bras bas, tête qui suit le pas
		Run   : penché en avant, bras pliés à 90° qui pompent, genoux hauts, rebond, rotation du torse
		Jump  : impulsion (jambes repliées, bras qui montent)
		Fall  : bras écartés qui moulinent, jambes qui cherchent le sol
		Land  : réception amortie 0.22 s (squash : bassin bas, genoux pliés, bras devant)
		Slide : corps renversé et abaissé, jambe avant tendue, bras d'équilibre, tête qui regarde devant
		Dash  : gainé, bras en arrière, jambes en ciseau
		Rip / Flinch : arrachage de queue (chasseur) / sursaut (capturé), superposés à l'état courant

	Procédural = on écrit Motor6D.Transform après l'Animator (RunService.Stepped). Le script "Animate" par défaut du
	joueur local est coupé. Si un ID est renseigné dans Config.Animations[état], cet état joue ta vraie animation
	(Animator, répliquée) et le procédural laisse la main pour cet état.
	Rig R6 : non géré (règle le jeu en R15 dans Game Settings > Avatar).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
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
	RWrist = { "RightHand", "RightWrist" },
	LWrist = { "LeftHand", "LeftWrist" },
	RHip = { "RightUpperLeg", "RightHip" },
	LHip = { "LeftUpperLeg", "LeftHip" },
	RKnee = { "RightLowerLeg", "RightKnee" },
	LKnee = { "LeftLowerLeg", "LeftKnee" },
	RAnkle = { "RightFoot", "RightAnkle" },
	LAnkle = { "LeftFoot", "LeftAnkle" },
}

type Rig = {
	Char: Model, Hum: Humanoid, RootPart: BasePart,
	Motors: { [string]: Motor6D }, Current: { [string]: CFrame },
	Phase: number, Action: string?, ActionStart: number, ActionLen: number, Conns: { RBXScriptConnection },
	WasAir: boolean, LandAt: number, AirTime: number, Seed: number, State: string,
	Tracks: { [string]: AnimationTrack }, Playing: string?,
}

local rigs: { [Model]: Rig } = {}
local CUSTOM = {} -- états qui ont un vrai ID d'animation
for state, id in Config.Animations do
	if type(id) == "string" and id ~= "" then CUSTOM[state] = id end
end

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
		Action = nil, ActionStart = 0, ActionLen = 0, Conns = {}, WasAir = false, LandAt = -10, AirTime = 0,
		Seed = math.random() * 100, State = "Idle", Tracks = {}, Playing = nil }
end

local function removeRig(char: Model)
	local r = rigs[char]
	if not r then return end
	for _, c in r.Conns do c:Disconnect() end
	for _, m in r.Motors do if m.Parent then m.Transform = CFrame.identity end end
	rigs[char] = nil
end

--- Vraies animations (si IDs fournis) : uniquement pour le personnage local, l'Animator les réplique.
local function playCustom(r: Rig, state: string)
	if r.Char ~= player.Character then return end
	local want = if CUSTOM[state] then state else nil
	if r.Playing == want then return end
	if r.Playing and r.Tracks[r.Playing] then r.Tracks[r.Playing]:Stop(0.15) end
	r.Playing = want
	if not want then return end
	local track = r.Tracks[want]
	if not track then
		local animator = r.Hum:FindFirstChildOfClass("Animator")
		if not animator then return end
		local anim = Instance.new("Animation")
		anim.AnimationId = CUSTOM[want]
		local ok, t = pcall(animator.LoadAnimation, animator, anim)
		if not ok then warn("[AnimationController] animation invalide pour " .. want .. " : " .. CUSTOM[want]); CUSTOM[want] = nil; return end
		t.Priority = if want == "Slide" or want == "Dash" then Enum.AnimationPriority.Action else Enum.AnimationPriority.Movement
		t.Looped = want ~= "Jump"
		r.Tracks[want] = t
		track = t
	end
	track:Play(0.15)
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
			-- coupe l'Animate par défaut : walk / run / idle / jump sont remplacés
			local anim = char:FindFirstChild("Animate")
			if anim and anim:IsA("LocalScript") then anim.Enabled = false end
			local animator = r.Hum:FindFirstChildOfClass("Animator")
			if animator then
				for _, t in animator:GetPlayingAnimationTracks() do t:Stop(0) end
			end
		end
		table.insert(r.Conns, char.AncestryChanged:Connect(function()
			if not char.Parent then removeRig(char) end
		end))
		-- les parties du corps peuvent être remplacées au chargement de l'apparence
		table.insert(r.Conns, char.ChildAdded:Connect(function(c)
			if c:IsA("BasePart") then
				task.defer(function()
					local cur = rigs[char]
					if cur then
						local nr = buildRig(char)
						if nr then
							nr.Conns = cur.Conns
							nr.Tracks = cur.Tracks
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
local function stateOf(r: Rig, dt: number): (string, number, Vector3)
	local vel = r.RootPart.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local hs = r.Hum:GetState()
	local air = hs == Enum.HumanoidStateType.Freefall or hs == Enum.HumanoidStateType.Jumping
	local now = os.clock()
	if air then
		r.AirTime += dt
	elseif r.WasAir then
		if r.AirTime > 0.25 then r.LandAt = now end
		r.AirTime = 0
	end
	r.WasAir = air
	if r.Char:GetAttribute("Sliding") == true then return "Slide", speed, vel end
	if r.Char:GetAttribute("Dashing") == true then return "Dash", speed, vel end
	if air then return (if vel.Y > 2 then "Jump" else "Fall"), speed, vel end
	if now - r.LandAt < 0.22 then return "Land", speed, vel end
	if speed > Config.WalkRunThreshold then return "Run", speed, vel end
	if speed > 1.2 then return "Walk", speed, vel end
	return "Idle", speed, vel
end

local function computePose(r: Rig, state: string, speed: number, vel: Vector3, dt: number, t: number): { [string]: CFrame }
	local pose: { [string]: CFrame } = {}
	if state == "Slide" then
		local w = math.sin(t * 9) * 0.06
		pose.Root = CFrame.new(0, -1.15, 0.25) * A(1.05, 0, 0.05) -- abaissé juste assez pour l'ouverture des tunnels (3 studs) sans traverser le sol
		pose.Waist = A(-0.4, 0.18, 0)
		pose.Neck = A(-0.6, 0, 0)
		pose.RHip = A(1.3, 0, 0.06)
		pose.LHip = A(0.7, 0, -0.1)
		pose.RKnee = A(-0.08, 0, 0)
		pose.LKnee = A(-1.15, 0, 0)
		pose.RAnkle = A(0.4, 0, 0)
		pose.RShoulder = A(0.55 + w, 0, 1.3)
		pose.LShoulder = A(-0.7 - w, 0, -0.5)
		pose.RElbow = A(0.35, 0, 0)
		pose.LElbow = A(0.7, 0, 0)
	elseif state == "Dash" then
		pose.Root = CFrame.new(0, -0.15, 0) * A(-0.5, 0, 0)
		pose.Waist = A(-0.22, 0, 0)
		pose.Neck = A(0.4, 0, 0)
		pose.RShoulder = A(-1.35, 0, 0.3)
		pose.LShoulder = A(-1.35, 0, -0.3)
		pose.RElbow = A(0.15, 0, 0)
		pose.LElbow = A(0.15, 0, 0)
		pose.RHip = A(0.8, 0, 0)
		pose.LHip = A(-0.7, 0, 0)
		pose.RKnee = A(-0.7, 0, 0)
		pose.LKnee = A(-0.25, 0, 0)
	elseif state == "Jump" then
		local up = math.clamp(vel.Y / 50, 0, 1)
		pose.Root = A(-0.1, 0, 0)
		pose.Waist = A(0.08, 0, 0)
		pose.Neck = A(0.2 * up, 0, 0)
		pose.RShoulder = A(0.4 + 1.6 * up, 0, 0.35)
		pose.LShoulder = A(0.4 + 1.6 * up, 0, -0.35)
		pose.RElbow = A(0.4, 0, 0)
		pose.LElbow = A(0.4, 0, 0)
		pose.RHip = A(0.9, 0, 0.05)
		pose.LHip = A(0.25, 0, -0.05)
		pose.RKnee = A(-1.4, 0, 0)
		pose.LKnee = A(-0.5, 0, 0)
		pose.RAnkle = A(-0.3, 0, 0)
	elseif state == "Fall" then
		local m = math.sin(t * 11 + r.Seed)
		local fall = math.clamp(-vel.Y / 60, 0, 1)
		pose.Root = A(0.05, 0, 0)
		pose.Waist = A(-0.05, 0, m * 0.04)
		pose.Neck = A(-0.25 * fall, 0, 0)
		pose.RShoulder = A(0.5 + m * 0.35, 0, 1.4 + fall * 0.4)
		pose.LShoulder = A(0.5 - m * 0.35, 0, -1.4 - fall * 0.4)
		pose.RElbow = A(0.5, 0, 0)
		pose.LElbow = A(0.5, 0, 0)
		pose.RHip = A(0.35 + m * 0.15, 0, 0.08)
		pose.LHip = A(-0.15 - m * 0.15, 0, -0.08)
		pose.RKnee = A(-0.6, 0, 0)
		pose.LKnee = A(-0.3, 0, 0)
	elseif state == "Land" then
		local k = 1 - (os.clock() - r.LandAt) / 0.22
		pose.Root = CFrame.new(0, -0.65 * k, 0) * A(-0.25 * k, 0, 0)
		pose.Waist = A(-0.2 * k, 0, 0)
		pose.RHip = A(0.8 * k, 0, 0.06)
		pose.LHip = A(0.8 * k, 0, -0.06)
		pose.RKnee = A(-1.3 * k, 0, 0)
		pose.LKnee = A(-1.3 * k, 0, 0)
		pose.RAnkle = A(0.5 * k, 0, 0)
		pose.LAnkle = A(0.5 * k, 0, 0)
		pose.RShoulder = A(0.7 * k, 0, 0.5 * k)
		pose.LShoulder = A(0.7 * k, 0, -0.5 * k)
		pose.RElbow = A(0.4, 0, 0)
		pose.LElbow = A(0.4, 0, 0)
	elseif state == "Run" then
		local k = math.clamp(speed / 22, 0.6, 1.4)
		r.Phase += dt * (6.5 + speed * 0.38)
		local p = r.Phase
		local s, c = math.sin(p), math.cos(p)
		local leg = 0.75 * k
		pose.Root = CFrame.new(0, math.abs(c) * 0.3 * k - 0.12, 0) * A(-0.2 * k, s * 0.12, 0)
		pose.Waist = A(-0.12, -s * 0.32, s * 0.04)
		pose.Neck = A(0.22, s * 0.2, 0)
		pose.RHip = A(s * leg + 0.1, 0, 0)
		pose.LHip = A(-s * leg + 0.1, 0, 0)
		pose.RKnee = A(-0.2 - 1.5 * k * math.max(0, math.sin(p + 1.3)), 0, 0)
		pose.LKnee = A(-0.2 - 1.5 * k * math.max(0, math.sin(p + 1.3 + math.pi)), 0, 0)
		pose.RAnkle = A(0.3 * math.max(0, -s), 0, 0)
		pose.LAnkle = A(0.3 * math.max(0, s), 0, 0)
		pose.RShoulder = A(-s * 1.1 * k, 0, 0.18)
		pose.LShoulder = A(s * 1.1 * k, 0, -0.18)
		pose.RElbow = A(1.35, 0, 0)
		pose.LElbow = A(1.35, 0, 0)
		pose.RWrist = A(0.2, 0, 0)
		pose.LWrist = A(0.2, 0, 0)
	elseif state == "Walk" then
		r.Phase += dt * (4.5 + speed * 0.45)
		local p = r.Phase
		local s, c = math.sin(p), math.cos(p)
		pose.Root = CFrame.new(0, math.abs(c) * 0.1, 0) * A(-0.04, s * 0.06, s * 0.03)
		pose.Waist = A(0, -s * 0.12, -s * 0.03)
		pose.Neck = A(0.04, s * 0.08, s * 0.03)
		pose.RHip = A(s * 0.5, 0, 0)
		pose.LHip = A(-s * 0.5, 0, 0)
		pose.RKnee = A(-0.1 - 0.7 * math.max(0, math.sin(p + 1.2)), 0, 0)
		pose.LKnee = A(-0.1 - 0.7 * math.max(0, math.sin(p + 1.2 + math.pi)), 0, 0)
		pose.RShoulder = A(-s * 0.55, 0, 0.1)
		pose.LShoulder = A(s * 0.55, 0, -0.1)
		pose.RElbow = A(0.3 + math.max(0, -s) * 0.3, 0, 0)
		pose.LElbow = A(0.3 + math.max(0, s) * 0.3, 0, 0)
	else -- Idle
		local b = math.sin(t * 2.1 + r.Seed)
		local shift = math.sin(t * 0.55 + r.Seed)
		-- coup d'œil toutes les ~4 s
		local cyc = (t + r.Seed) % 4.2
		local look = if cyc < 0.9 then math.sin(cyc / 0.9 * math.pi) * (if math.floor((t + r.Seed) / 4.2) % 2 == 0 then 0.6 else -0.6) else 0
		pose.Root = CFrame.new(shift * 0.06, b * 0.035, 0) * A(0, 0, shift * 0.03)
		pose.Waist = A(b * 0.04, look * 0.25, -shift * 0.04)
		pose.Neck = A(-b * 0.05, look, 0)
		pose.RShoulder = A(0.06, 0, 0.12 + b * 0.05)
		pose.LShoulder = A(0.06, 0, -0.12 - b * 0.05)
		pose.RElbow = A(0.22, 0, 0)
		pose.LElbow = A(0.22, 0, 0)
		pose.RHip = A(0, 0, 0.04 - shift * 0.03)
		pose.LHip = A(0, 0, -0.04 - shift * 0.03)
		pose.RKnee = A(-0.05 - math.max(0, shift) * 0.12, 0, 0)
		pose.LKnee = A(-0.05 - math.max(0, -shift) * 0.12, 0, 0)
	end

	-- actions ponctuelles superposées
	if r.Action then
		local a = (os.clock() - r.ActionStart) / r.ActionLen
		if a >= 1 then
			r.Action = nil
		elseif r.Action == "Rip" then
			local grab = math.clamp(a / 0.35, 0, 1)
			local pull = math.clamp((a - 0.35) / 0.65, 0, 1)
			pose.RShoulder = A(1.8 * grab - 2.5 * pull, 0, 0.2)
			pose.RElbow = A(0.15 + 1.0 * pull, 0, 0)
			pose.RWrist = A(-0.5 * pull, 0, 0)
			pose.Waist = (pose.Waist or CFrame.identity) * A(0, -0.6 * grab + 1.1 * pull, 0)
			pose.Neck = A(0.1, -0.4 * grab + 0.6 * pull, 0)
		elseif r.Action == "Flinch" then
			local f = math.sin(a * math.pi)
			pose.RShoulder = A(0.4 * f, 0, 1.7 * f)
			pose.LShoulder = A(0.4 * f, 0, -1.7 * f)
			pose.Waist = (pose.Waist or CFrame.identity) * A(0.4 * f, 0, 0)
			pose.Neck = A(0.45 * f, 0, 0)
		end
	end
	return pose
end

local BLEND = { Slide = 22, Dash = 24, Land = 26, Jump = 16, Fall = 10, Run = 15, Walk = 12, Idle = 8 }

RunService.Stepped:Connect(function(_, dt)
	local t = os.clock()
	for _, r in rigs do
		if r.Hum.Health > 0 and r.RootPart.Parent then
			local state, speed, vel = stateOf(r, dt)
			r.State = state
			playCustom(r, state)
			if CUSTOM[state] then
				-- ta vraie animation pilote cet état : on relâche les joints
				for key, motor in r.Motors do
					r.Current[key] = CFrame.identity
					_ = motor
				end
				continue
			end
			local pose = computePose(r, state, speed, vel, dt, t)
			local alpha = 1 - math.exp(-dt * (BLEND[state] or 14))
			for key, motor in r.Motors do
				local target = pose[key] or CFrame.identity
				local cur = (r.Current[key] or CFrame.identity):Lerp(target, alpha)
				r.Current[key] = cur
				if motor.Parent then motor.Transform = cur end
			end
		end
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

Remotes.Captured.OnClientEvent:Connect(function(hunter: Player, runner: Player)
	if hunter and hunter.Character then playAction(hunter.Character, "Rip", 0.55) end
	if runner and runner.Character then playAction(runner.Character, "Flinch", 0.45) end
end)
