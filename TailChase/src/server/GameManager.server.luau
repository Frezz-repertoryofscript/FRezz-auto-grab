--[[
	GameManager - point d'entrée serveur de TAIL CHASE.
	Construit la map, initialise les services et fait tourner la boucle :
		Lobby -> Intermission (20 s, min joueurs prêts) -> Countdown (5 s, figés) -> Round (3 min) -> Results (10 s) -> Lobby

	État répliqué via les Attributes de ReplicatedStorage (lus par l'UI) :
		GameState, EndsAt (temps serveur), ReadyCount, MinPlayers, RunnersLeft, HuntersCount, HuntersReleaseAt
	Captures : détectées et validées UNIQUEMENT ici (distance horizontale + verticale, ligne de vue, cooldown,
	immunité anti-chaîne, état de manche). Le client ne peut pas déclarer une capture.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local MapBuilder = require(script.Parent.MapBuilder)
local DataService = require(script.Parent.DataService)
local ShopService = require(script.Parent.ShopService)
local TailService = require(script.Parent.TailService)
local RoleService = require(script.Parent.RoleService)
local CoinService = require(script.Parent.CoinService)
local MovementService = require(script.Parent.MovementService)

local S = Config.States
local MIN_PLAYERS = if RunService:IsStudio() then Config.StudioMinPlayers else Config.MinPlayers

-- =====================================================================
-- INIT
-- =====================================================================
MapBuilder.Build()
DataService.Init()
ShopService.Init()
TailService.Init()
MovementService.Init()

ReplicatedStorage:SetAttribute("MinPlayers", MIN_PLAYERS)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function setState(state: string, duration: number?)
	ReplicatedStorage:SetAttribute("GameState", state)
	ReplicatedStorage:SetAttribute("EndsAt", if duration then now() + duration else 0)
	Remotes.RoundState:FireAllClients(state, duration or 0)
end

local function notifyAll(text: string, kind: string?)
	Remotes.Notify:FireAllClients(text, kind or "info")
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return nil end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function shuffle<T>(t: { T }): { T }
	for i = #t, 2, -1 do
		local j = math.random(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

local function teleport(player: Player, cf: CFrame)
	local char = player.Character
	if char then
		char:PivotTo(cf)
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then root.AssemblyLinearVelocity = Vector3.zero end
	end
end

local function randomMapSpawn(): CFrame
	local spawns = MapBuilder.GetMapSpawns()
	if #spawns == 0 then return CFrame.new(0, 6, 0) end
	local s = spawns[math.random(1, #spawns)]
	return s.CFrame + Vector3.new(0, 3.5, 0)
end

-- =====================================================================
-- MANCHE
-- =====================================================================
type PData = { Role: string, StartedAsRunner: boolean, CapturedAt: number?, Tails: number, LastCapture: number, ImmuneUntil: number }
type Round = { Players: { [Player]: PData }, GoTime: number, Active: boolean, LastCaptured: Player?, Released: boolean }

local round: Round? = nil

local function readyPlayers(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Ready") and p.Character and DataService.Get(p) then
			table.insert(list, p)
		end
	end
	return list
end

local function countRoles(): (number, number)
	local runners, hunters = 0, 0
	if round then
		for _, d in round.Players do
			if d.Role == "Runner" then runners += 1 elseif d.Role == "Hunter" then hunters += 1 end
		end
	end
	return runners, hunters
end

local function updateCounts()
	local r, h = countRoles()
	ReplicatedStorage:SetAttribute("RunnersLeft", r)
	ReplicatedStorage:SetAttribute("HuntersCount", h)
end

--- Capture validée : la queue est arrachée, le participant devient chasseur.
local function capture(hunter: Player, runner: Player)
	local r = round
	if not r then return end
	local hd, rd = r.Players[hunter], r.Players[runner]
	if not hd or not rd or rd.Role ~= "Runner" or hd.Role ~= "Hunter" then return end
	local t = os.clock()

	rd.Role = "Hunter"
	rd.CapturedAt = now()
	rd.ImmuneUntil = t + Config.NewHunterImmunity
	r.LastCaptured = runner
	hd.Tails += 1
	hd.LastCapture = t

	hunter:SetAttribute("TailsTaken", hd.Tails)
	runner:SetAttribute("ImmuneUntil", now() + Config.NewHunterImmunity)

	local tailCF, skin = TailService.Remove(runner)
	RoleService.Set(runner, "Hunter")
	MovementService.EndSlide(runner)

	local hdata = DataService.Get(hunter)
	local fx = hdata and hdata.Equipped.Capture or "capture_default"
	Remotes.Captured:FireAllClients(hunter, runner, skin, fx, tailCF)
	notifyAll(("%s est devenu chasseur !"):format(runner.DisplayName), "hunter")
	Remotes.Notify:FireClient(hunter, ("Tu as pris une queue ! +%d"):format(Config.Coins.PerTail), "success")
	Remotes.Notify:FireClient(runner, "On t'a arraché ta queue ! À toi de chasser !", "danger")
	updateCounts()
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function checkCaptures()
	local r = round
	if not r or not r.Released then return end
	local t = os.clock()
	local chars = {}
	for p in r.Players do
		if p.Character then table.insert(chars, p.Character) end
	end
	rayParams.FilterDescendantsInstances = chars

	for hunter, hd in r.Players do
		if hd.Role == "Hunter" and t >= hd.ImmuneUntil and t - hd.LastCapture >= Config.HunterCaptureCooldown
			and not hunter:GetAttribute("Frozen") then
			local hr = rootOf(hunter)
			if hr then
				for runner, rd in r.Players do
					if rd.Role == "Runner" and runner ~= hunter then
						local rr = rootOf(runner)
						if rr then
							local d = rr.Position - hr.Position
							local flat = Vector3.new(d.X, 0, d.Z).Magnitude
							if flat <= Config.CaptureDistance and math.abs(d.Y) <= Config.CaptureVerticalMax then
								-- ligne de vue : pas de capture à travers un mur / plafond de tunnel
								local hit = workspace:Raycast(hr.Position, d, rayParams)
								if not hit then
									capture(hunter, runner)
									break
								end
							end
						end
					end
				end
			end
		end
	end
end

local function endRound()
	local r = round
	if not r then return end
	r.Active = false
	local tEnd = now()
	local survivors = {}
	for p, d in r.Players do
		if d.Role == "Runner" and p.Parent then table.insert(survivors, p) end
	end

	local rows = {}
	local mine = {}
	for p, d in r.Players do
		if p.Parent then
			local survival = if d.StartedAsRunner then math.max(0, (d.CapturedAt or tEnd) - r.GoTime) else 0
			local survived = d.Role == "Runner"
			local isLast = if #survivors > 0 then survived else (p == r.LastCaptured)
			local b = CoinService.Reward(p, survival, d.Tails, isLast, survived)
			mine[p] = { Survival = survival, Tails = d.Tails, Coins = b, LastSurvivor = isLast, Survived = survived }
			table.insert(rows, { Name = p.DisplayName, UserId = p.UserId, Survival = math.floor(survival), Tails = d.Tails,
				Coins = b.Total, Survived = survived, LastSurvivor = isLast })
		end
	end
	table.sort(rows, function(a, b)
		if a.Survival ~= b.Survival then return a.Survival > b.Survival end
		return a.Tails > b.Tails
	end)

	setState(S.Results, Config.ResultsTime)
	local headline = if #survivors > 0
		then (if #survivors == 1 then survivors[1].DisplayName .. " a survécu !" else #survivors .. " survivants !")
		else "Les chasseurs ont tout pris !"
	for p, m in mine do
		Remotes.Results:FireClient(p, { Rows = rows, Mine = m, Headline = headline })
	end

	-- retour au lobby
	for p in r.Players do
		if p.Parent then
			RoleService.SetFrozen(p, false)
			p:SetAttribute("TailsTaken", 0)
			p:SetAttribute("ImmuneUntil", 0)
			MovementService.EndSlide(p)
			RoleService.Set(p, "Lobby")
			teleport(p, MapBuilder.GetLobbySpawn())
		end
	end
	round = nil
	updateCounts()
	DataService.RefreshLeaderboard()
	task.wait(Config.ResultsTime)
end

local function runRound()
	local participants = shuffle(readyPlayers())
	if #participants < math.min(2, MIN_PLAYERS) then return end

	local hunterCount = if #participants > Config.ExtraHunterThreshold then 2 else 1
	if #participants < 2 then hunterCount = 0 end -- (Studio solo : manche sans chasseur pour tester le mouvement)
	local spawns = shuffle(MapBuilder.GetMapSpawns())
	local r: Round = { Players = {}, GoTime = 0, Active = true, LastCaptured = nil, Released = false }
	round = r

	for i, p in participants do
		local role = if i <= hunterCount then "Hunter" else "Runner"
		r.Players[p] = { Role = role, StartedAsRunner = role == "Runner", CapturedAt = nil, Tails = 0, LastCapture = 0, ImmuneUntil = 0 }
		p:SetAttribute("TailsTaken", 0)
		RoleService.SetFrozen(p, true)
		RoleService.Set(p, role)
		local sp = spawns[((i - 1) % math.max(#spawns, 1)) + 1]
		teleport(p, if sp then sp.CFrame + Vector3.new(0, 3.5, 0) else randomMapSpawn())
		Remotes.RoleAssigned:FireClient(p, role, Config.CountdownTime)
	end
	updateCounts()
	setState(S.Countdown, Config.CountdownTime)
	task.wait(Config.CountdownTime)

	-- GO : les participants partent, les chasseurs attendent un peu
	r.GoTime = now()
	ReplicatedStorage:SetAttribute("HuntersReleaseAt", now() + Config.HunterReleaseDelay)
	for p, d in r.Players do
		if d.Role == "Runner" and p.Parent then RoleService.SetFrozen(p, false) end
	end
	setState(S.Round, Config.RoundTime)
	notifyAll("GO ! Fuyez !", "go")
	task.delay(Config.HunterReleaseDelay, function()
		if round ~= r or not r.Active then return end
		r.Released = true
		for p, d in r.Players do
			if d.Role == "Hunter" and p.Parent then RoleService.SetFrozen(p, false) end
		end
		notifyAll("Les chasseurs sont lâchés !", "hunter")
	end)

	local endsAt = os.clock() + Config.RoundTime
	while r.Active and os.clock() < endsAt do
		checkCaptures()
		local runners, hunters = countRoles()
		if runners == 0 and hunterCount > 0 then break end
		-- plus aucun chasseur (déconnexions) : un participant au hasard prend le rôle
		if hunters == 0 and hunterCount > 0 then
			if runners >= 2 then
				local pool = {}
				for p, d in r.Players do if d.Role == "Runner" then table.insert(pool, p) end end
				local p = pool[math.random(1, #pool)]
				r.Players[p].Role = "Hunter"
				r.Players[p].CapturedAt = now()
				r.Players[p].ImmuneUntil = os.clock() + Config.NewHunterImmunity
				TailService.Remove(p)
				RoleService.Set(p, "Hunter")
				notifyAll(p.DisplayName .. " devient chasseur !", "hunter")
				updateCounts()
			else
				break
			end
		end
		local count = 0
		for p in r.Players do if p.Parent then count += 1 end end
		if count == 0 then break end
		task.wait(Config.CaptureCheckRate)
	end
	endRound()
end

-- =====================================================================
-- JOUEURS
-- =====================================================================
local function onCharacter(player: Player, char: Model)
	char:WaitForChild("HumanoidRootPart", 10)
	char:WaitForChild("Humanoid", 10)
	if not char.Parent then return end
	task.wait() -- laisse le personnage se poser
	local r = round
	if r and r.Players[player] then
		teleport(player, randomMapSpawn())
		if r.Players[player].Role == "Runner" and not TailService.Has(player) then
			-- (re)spawn d'un participant : il garde son rôle
		end
	else
		if player:GetAttribute("Role") ~= "Lobby" then player:SetAttribute("Role", "Lobby") end
	end
	RoleService.ApplyVisuals(player)
end

local function onPlayer(player: Player)
	player:SetAttribute("Role", "Lobby")
	player:SetAttribute("Ready", false)
	player:SetAttribute("TailsTaken", 0)
	player.CharacterAdded:Connect(function(c) onCharacter(player, c) end)
	player.CharacterAppearanceLoaded:Connect(function()
		RoleService.ApplyVisuals(player) -- les parties du corps peuvent avoir été remplacées
	end)
	if player.Character then task.spawn(onCharacter, player, player.Character) end
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do task.spawn(onPlayer, p) end

Players.PlayerRemoving:Connect(function(p)
	if round and round.Players[p] then
		round.Players[p] = nil
		updateCounts()
	end
end)

DataService.ProfileLoaded:Connect(function(player: Player)
	RoleService.ApplyVisuals(player)
end)

Remotes.SetReady.OnServerEvent:Connect(function(player: Player, ready: any)
	player:SetAttribute("Ready", ready == true)
end)

if MapBuilder.ShopPrompt then
	MapBuilder.ShopPrompt.Triggered:Connect(function(player)
		Remotes.OpenMenu:FireClient(player, "Shop")
	end)
end

-- kill plane : tout joueur qui tombe est replacé
task.spawn(function()
	while true do
		task.wait(0.25)
		for _, p in Players:GetPlayers() do
			local root = rootOf(p)
			if root and root.Position.Y < Config.KillPlaneY then
				if round and round.Players[p] then
					teleport(p, randomMapSpawn())
				else
					teleport(p, MapBuilder.GetLobbySpawn())
				end
				Remotes.Notify:FireClient(p, "Oups ! Replacé.", "info")
			end
		end
	end
end)

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
while true do
	setState(S.Lobby)
	repeat
		ReplicatedStorage:SetAttribute("ReadyCount", #readyPlayers())
		task.wait(1)
	until #readyPlayers() >= MIN_PLAYERS

	setState(S.Intermission, Config.IntermissionTime)
	local t0 = os.clock()
	local cancelled = false
	while os.clock() - t0 < Config.IntermissionTime do
		task.wait(0.25)
		local n = #readyPlayers()
		ReplicatedStorage:SetAttribute("ReadyCount", n)
		if n < MIN_PLAYERS then
			cancelled = true
			break
		end
	end
	if cancelled then
		notifyAll("Pas assez de joueurs, retour à l'attente.", "info")
	else
		local ok, err = pcall(runRound)
		if not ok then
			warn("[GameManager] erreur pendant la manche :", err)
			-- sécurité : on remet tout le monde au lobby
			for _, p in Players:GetPlayers() do
				RoleService.SetFrozen(p, false)
				RoleService.Set(p, "Lobby")
				teleport(p, MapBuilder.GetLobbySpawn())
			end
			round = nil
		end
	end
end
