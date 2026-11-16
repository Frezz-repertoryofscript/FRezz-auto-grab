--!nonstrict
local M = require("./mock")
local SRC = require("./sources")
local I = M.newInstance
local B = { M = M }

-- ------------------------------------------------------------------ ordonnanceur (temps virtuel)
local now = 0
local queue = {}
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then error(debug.traceback(co, err), 0) end
end
local task = {}
function task.wait(t) table.insert(queue, { co = coroutine.running(), at = now + (t or 0.03) }); coroutine.yield(); return t or 0.03 end
function task.spawn(fn, ...) local co = if type(fn) == "thread" then fn else coroutine.create(fn); resume(co, ...); return co end
task.defer = task.spawn
function task.delay(t, fn, ...) local co = coroutine.create(fn); local args = { ... }; table.insert(queue, { co = co, at = now + (t or 0), args = args }); return co end
function task.cancel() end
B.task = task
function B.now() return now end

local services = {}
local game = I("DataModel"); game.Name = "Game"
B.game = game
local function svc(name, class) local s = I(class or name); s.Name = name; services[name] = s; s.Parent = game; return s end
game.GetService = function(_, n) assert(services[n], "service inconnu " .. n); return services[n] end
local closeFns = {}
game.BindToClose = function(_, fn) table.insert(closeFns, fn) end

local workspace = svc("Workspace")
local camera = I("Camera"); camera.Name = "Camera"; camera.Parent = workspace; camera.FieldOfView = 70; camera.ViewportSize = M.Vector2.new(1280, 720); camera.CFrame = M.CFrame.new(0, 10, 10)
workspace.CurrentCamera = camera
workspace.Raycast = function() return nil end
workspace.GetServerTimeNow = function() return 1000 + now end
local RS = svc("ReplicatedStorage")
local SSS = svc("ServerScriptService")
local Players = svc("Players")
svc("Lighting"); game.CreatorType = M.Enum.CreatorType.User; game.CreatorId = 1; svc("StarterGui"); svc("SoundService"); svc("Debris"); svc("MarketplaceService"); svc("ContextActionService"); svc("StarterPlayer")
local Run = svc("RunService")
Run.IsStudio = function() return true end
Run.IsServer = function() return true end
Run.IsClient = function() return true end
local renderSteps = {}
Run.BindToRenderStep = function(_, n, p, fn) renderSteps[n] = fn end
local TS = svc("TweenService")
TS.Create = function(_, obj, info, goals)
	local t = I("Tween")
	t.Play = function() for k, v in goals do obj[k] = v end end
	return t
end
local CS = svc("CollectionService")
local tags = {}
CS.AddTag = function(_, inst, tag) tags[tag] = tags[tag] or {}; table.insert(tags[tag], inst) end
CS.GetTagged = function(_, tag) return tags[tag] or {} end
CS.HasTag = function(_, inst, tag) for _, x in tags[tag] or {} do if x == inst then return true end end return false end
local PS = svc("PhysicsService")
PS.RegisterCollisionGroup = function() end
PS.CollisionGroupSetCollidable = function() end
local DSS = svc("DataStoreService")
DSS.GetDataStore = function() error("Studio access to API services disabled") end
DSS.GetOrderedDataStore = function() error("disabled") end
local UIS = svc("UserInputService"); UIS.TouchEnabled = true; UIS.KeyboardEnabled = false
local CAS = services.ContextActionService
CAS.BindActionAtPriority = function(_, name, fn) B.actions = B.actions or {}; B.actions[name] = fn end
CAS.BindAction = CAS.BindActionAtPriority
local SG = services.StarterGui
SG.GetCoreGuiEnabled = function() return true end
SG.SetCoreGuiEnabled = function() end
SG.SetCore = function() end
services.Debris.AddItem = function() end
local Http = svc("HttpService")
local jsonStore = {}
Http.JSONEncode = function(_, t) table.insert(jsonStore, t); return "json#" .. #jsonStore end
Http.JSONDecode = function(_, str) return table.clone(jsonStore[tonumber(str:match("%d+"))]) end
local CP = svc("ContentProvider")
B.failAssets = {}
CP.PreloadAsync = function(_, ids, cb)
	for _, id in ids do cb(id, if B.failAssets[id] then M.Enum.AssetFetchStatus.Failure else M.Enum.AssetFetchStatus.Success) end
end
Players.GetPlayers = function() local out = {}; for _, c in Players:GetChildren() do if c.ClassName == "Player" then table.insert(out, c) end end return out end
Players.GetPlayerFromCharacter = function(_, ch) for _, p in Players:GetPlayers() do if p.Character == ch then return p end end return nil end
Players.GetNameFromUserIdAsync = function() return "X" end

-- ------------------------------------------------------------------ require / scripts
local env0 = {
	game = game, workspace = workspace, Instance = M.Instance, Vector3 = M.Vector3, Vector2 = M.Vector2, CFrame = M.CFrame, UDim = M.UDim, UDim2 = M.UDim2,
	Color3 = M.Color3, ColorSequence = M.ColorSequence, ColorSequenceKeypoint = M.ColorSequenceKeypoint, NumberSequence = M.NumberSequence,
	NumberSequenceKeypoint = M.NumberSequenceKeypoint, NumberRange = M.NumberRange, Font = M.Font, Enum = M.Enum, TweenInfo = M.TweenInfo,
	RaycastParams = M.RaycastParams, Rect = M.Rect, typeof = M.typeof,
	type = function(v) local mt = getmetatable(v); if type(mt) == "table" and mt.__type then return "userdata" end return type(v) end, task = task, warn = function(...) B.warns = (B.warns or 0) + 1; print("WARN", ...) end,
	tick = function() return now end, os = setmetatable({ clock = function() return now end }, { __index = os }),
}
local cache = {}
local function load(inst)
	local path = rawget(inst, "__p").Source
	local src = SRC[path]
	assert(src, "source manquante " .. tostring(path))
	local fn, err = loadstring(src, "=" .. path)
	if not fn then error(err) end
	local env = setmetatable({ script = inst }, { __index = function(_, k) local v = env0[k]; if v ~= nil then return v end return _G[k] end })
	env.require = function(m)
		assert(m ~= nil, "require(nil) depuis " .. path)
		if cache[m] == nil then cache[m] = { load(m)() } end
		return table.unpack(cache[m])
	end
	setfenv(fn, env)
	return fn
end
local function module(parent, name, path) local m = I("ModuleScript"); m.Name = name; m.Source = path; m.Parent = parent; return m end
local function folder(parent, name) local f = I("Folder"); f.Name = name; f.Parent = parent; return f end

module(RS, "StudUI", "shared/StudKit/StudUI.luau")
module(RS, "StudMotion", "shared/StudKit/StudMotion.luau")
module(RS, "CheckUIIcons", "shared/StudKit/CheckUIIcons.luau")
local shared = folder(RS, "Shared")
for _, n in { "Config", "Cosmetics", "TailBuilder", "Audio", "ClientSignals" } do module(shared, n, "shared/Shared/" .. n .. ".luau") end
local rem = folder(RS, "Remotes")
for _, n in { "RoundState", "Notify", "RoleAssigned", "Captured", "MoveAction", "Results", "DataUpdated", "SetReady", "OpenMenu", "TutorialDone", "MapVote" } do local r = I("RemoteEvent"); r.Name = n; r.Parent = rem end
for _, n in { "ShopPurchase", "ShopEquip", "GetProfile", "AdminCommand" } do local r = I("RemoteFunction"); r.Name = n; r.Parent = rem end
local mb = module(SSS, "MapBuilder", "server/MapBuilder/init.luau")
local mapsF = folder(mb, "Maps")
for _, n in { "Plage", "Chateau", "Neon", "Neige", "Fete" } do module(mapsF, n, "server/MapBuilder/Maps/" .. n .. ".luau") end
for _, n in { "DataService", "ShopService", "TailService", "RoleService", "CoinService", "MovementService", "AdminService" } do module(SSS, n, "server/" .. n .. ".luau") end
local gm = I("Script"); gm.Name = "GameManager"; gm.Source = "server/GameManager.server.luau"; gm.Parent = SSS

local sps = I("StarterPlayerScripts")
for _, n in { "MovementController", "AnimationController", "EffectsController" } do local s = I("LocalScript"); s.Name = n; s.Source = "client/" .. n .. ".client.luau"; s.Parent = sps end
local uic = I("LocalScript"); uic.Name = "UIController"; uic.Source = "client/UIController/init.client.luau"; uic.Parent = sps
for _, n in { "Hud", "LobbyMenu", "Collection", "Results", "Screens", "AdminPanel", "Tutorial", "MapVote", "AssetGuard" } do module(uic, n, "client/UIController/" .. n .. ".luau") end

B.RS, B.SSS, B.SPS, B.Players, B.Run, B.workspace, B.services = RS, SSS, sps, Players, Run, workspace, services

function B.run(scriptInst) task.spawn(load(scriptInst)) end
function B.require(m) if cache[m] == nil then cache[m] = { load(m)() } end return table.unpack(cache[m]) end

-- ------------------------------------------------------------------ personnages
function B.character(name)
	local ch = I("Model"); ch.Name = name
	local function p(n, size) local x = I("Part"); x.Name = n; x.Size = size or M.Vector3.new(2, 2, 1); x.Position = M.Vector3.new(0, 3, 0); x.CFrame = M.CFrame.new(0, 3, 0); x.AssemblyLinearVelocity = M.Vector3.new(10, 0, 0); x.Parent = ch; return x end
	local hrp = p("HumanoidRootPart")
	local att = I("Attachment"); att.Name = "RootAttachment"; att.Parent = hrp
	for _, n in { "LowerTorso", "UpperTorso", "Head", "RightUpperArm", "LeftUpperArm", "RightLowerArm", "LeftLowerArm", "RightUpperLeg", "LeftUpperLeg", "RightLowerLeg", "LeftLowerLeg" } do p(n) end
	local joints = { LowerTorso = "Root", UpperTorso = "Waist", Head = "Neck", RightUpperArm = "RightShoulder", LeftUpperArm = "LeftShoulder", RightLowerArm = "RightElbow",
		LeftLowerArm = "LeftElbow", RightUpperLeg = "RightHip", LeftUpperLeg = "LeftHip", RightLowerLeg = "RightKnee", LeftLowerLeg = "LeftKnee" }
	for part, j in joints do local m = I("Motor6D"); m.Name = j; m.Parent = ch[part] end
	local hum = I("Humanoid"); hum.Name = "Humanoid"; hum.RigType = M.Enum.HumanoidRigType.R15; hum.FloorMaterial = M.Enum.Material.Plastic; hum.Parent = ch
	local animator = I("Animator"); animator.Parent = hum
	local anim = I("LocalScript"); anim.Name = "Animate"; anim.Parent = ch
	ch.Parent = workspace
	return ch
end
function B.player(name, uid)
	local pl = I("Player"); pl.Name = name; pl.DisplayName = name; pl.UserId = uid
	local pg = I("PlayerGui"); pg.Name = "PlayerGui"; pg.Parent = pl
	pl.Parent = Players
	return pl
end

-- ------------------------------------------------------------------ boucle de temps
function B.pump(seconds, step)
	step = step or 0.05
	local target = now + seconds
	while now < target do
		now += step
		local due = {}
		local rest = {}
		for _, q in queue do if q.at <= now then table.insert(due, q) else table.insert(rest, q) end end
		queue = rest
		for _, q in due do
			if coroutine.status(q.co) == "suspended" then resume(q.co, table.unpack(q.args or {})) end
		end
		for _, n in { "Stepped", "Heartbeat", "RenderStepped", "PreSimulation" } do
			local s = rawget(Run, "__e")[n]
			if s then s:Fire(if n == "Stepped" then now else step, step) end
		end
		for _, fn in renderSteps do fn(step) end
	end
end
return B
