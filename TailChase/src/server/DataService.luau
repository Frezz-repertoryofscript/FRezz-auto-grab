--[[
	DataService - sauvegarde DataStore des profils (pièces, achats, équipements, stats).
	  * chargement / sauvegarde avec pcall + retries + backoff
	  * sauvegarde auto toutes les Config.Data.AutoSaveInterval s, à la sortie du joueur et à la fermeture (BindToClose)
	  * si le chargement échoue définitivement, le profil est marqué "NoSave" : on ne risque pas d'écraser les vraies données
	  * leaderstats (Pièces / Queues) + leaderboard du lobby (OrderedDataStore, repli sur les joueurs présents)
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local UI = require(ReplicatedStorage.StudUI)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local DataService = {}
DataService.Profiles = {} :: { [Player]: any }
local loaded = Instance.new("BindableEvent")
DataService.ProfileLoaded = loaded.Event

local store, ordered
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(Config.Data.StoreName)
		ordered = DataStoreService:GetOrderedDataStore(Config.Data.LeaderboardStore)
	end)
	if not ok then
		warn("[DataService] DataStore indisponible (active 'Studio Access to API Services' pour tester la sauvegarde) :", err)
	end
end

local function template()
	return {
		Version = 1,
		Coins = Config.Coins.StartingCoins,
		Owned = {
			[Cosmetics.DefaultFor("Tail")] = true,
			[Cosmetics.DefaultFor("Trail")] = true,
			[Cosmetics.DefaultFor("Capture")] = true,
		},
		Equipped = {
			Tail = Cosmetics.DefaultFor("Tail"),
			Trail = Cosmetics.DefaultFor("Trail"),
			Capture = Cosmetics.DefaultFor("Capture"),
		},
		Stats = { Rounds = 0, TailsTaken = 0, BestSurvival = 0, Wins = 0, CoinsEarned = 0 },
	}
end

--- Complète un profil chargé avec les champs manquants du modèle (migrations simples).
local function reconcile(data, tpl)
	for k, v in tpl do
		if data[k] == nil then
			data[k] = if type(v) == "table" then table.clone(v) else v
		elseif type(v) == "table" and type(data[k]) == "table" then
			reconcile(data[k], v)
		end
	end
	return data
end

--- Exécute fn avec retries + backoff. Retourne ok, résultat.
local function retry(label: string, fn: () -> any)
	local lastErr
	for attempt = 1, Config.Data.Retries do
		local ok, res = pcall(fn)
		if ok then return true, res end
		lastErr = res
		warn(("[DataService] %s : essai %d/%d échoué : %s"):format(label, attempt, Config.Data.Retries, tostring(res)))
		task.wait(Config.Data.RetryDelay * attempt)
	end
	return false, lastErr
end

local function key(player: Player) return "player_" .. player.UserId end

-- -------------------------------------------------------------------- leaderstats
local function setupLeaderstats(player: Player, data)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Pièces"
	coins.Value = data.Coins
	coins.Parent = ls
	local tails = Instance.new("IntValue")
	tails.Name = "Queues"
	tails.Value = data.Stats.TailsTaken
	tails.Parent = ls
	ls.Parent = player
end

local function refreshLeaderstats(player: Player, data)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then return end
	ls["Pièces"].Value = data.Coins
	ls.Queues.Value = data.Stats.TailsTaken
end

--- Copie envoyée au client (pas de référence partagée).
function DataService.Snapshot(player: Player)
	local d = DataService.Profiles[player]
	if not d then return nil end
	return {
		Coins = d.Coins,
		Owned = table.clone(d.Owned),
		Equipped = table.clone(d.Equipped),
		Stats = table.clone(d.Stats),
	}
end

function DataService.Push(player: Player)
	local d = DataService.Profiles[player]
	if not d then return end
	refreshLeaderstats(player, d)
	player:SetAttribute("TrailSkin", d.Equipped.Trail) -- lu par EffectsController de tous les clients
	Remotes.DataUpdated:FireClient(player, DataService.Snapshot(player))
end

-- -------------------------------------------------------------------- load / save
function DataService.Load(player: Player)
	local data
	local noSave = false
	if store then
		local ok, res = retry("Load " .. player.Name, function()
			return store:GetAsync(key(player))
		end)
		if ok then
			data = res
		else
			noSave = true
			warn("[DataService] profil de " .. player.Name .. " non chargé : session sans sauvegarde")
		end
	else
		noSave = true
	end
	if not player.Parent then return end
	data = reconcile(type(data) == "table" and data or {}, template())
	data.NoSave = noSave or nil
	DataService.Profiles[player] = data
	setupLeaderstats(player, data)
	DataService.Push(player)
	loaded:Fire(player, data)
end

function DataService.Save(player: Player)
	local d = DataService.Profiles[player]
	if not d or d.NoSave or not store then return false end
	local payload = table.clone(d)
	payload.NoSave = nil
	local ok = retry("Save " .. player.Name, function()
		store:UpdateAsync(key(player), function()
			return payload
		end)
	end)
	if ordered then
		pcall(function() ordered:SetAsync(key(player), d.Stats.TailsTaken) end)
	end
	return ok
end

function DataService.Get(player: Player)
	return DataService.Profiles[player]
end

--- Attend le profil (max `timeout` s).
function DataService.Wait(player: Player, timeout: number?)
	local t0 = os.clock()
	while not DataService.Profiles[player] and player.Parent and os.clock() - t0 < (timeout or 15) do
		task.wait(0.1)
	end
	return DataService.Profiles[player]
end

function DataService.AddCoins(player: Player, amount: number)
	local d = DataService.Profiles[player]
	if not d then return end
	d.Coins = math.max(0, d.Coins + math.floor(amount))
	if amount > 0 then d.Stats.CoinsEarned += math.floor(amount) end
	DataService.Push(player)
end

-- -------------------------------------------------------------------- leaderboard du lobby
local function renderLeaderboard(entries: { { Name: string, Value: number } })
	for _, board in CollectionService:GetTagged("LeaderboardBoard") do
		local sg = board:FindFirstChildOfClass("SurfaceGui")
		local rows = sg and sg:FindFirstChild("Rows")
		if rows then
			for _, c in rows:GetChildren() do
				if c:IsA("GuiObject") then c:Destroy() end
			end
			for i, e in entries do
				if i > 8 then break end
				local medal = if i == 1 then "#FFD23F" elseif i == 2 then "#E2E6EC" elseif i == 3 then "#FF9A4A" else "#FFFFFF"
				local t = UI.Text(rows, ("<font color=\"%s\">#%d</font>  %s  <font color=\"#60E87A\">%d</font>"):format(medal, i, e.Name, e.Value), {
					Name = "Ligne" .. i, Size = UDim2.new(1, 0, 0, 48), AnchorPoint = Vector2.zero, Position = UDim2.new(),
					AlignX = Enum.TextXAlignment.Left, Max = 38, Rich = true, Thickness = 3,
				})
				t.LayoutOrder = i
			end
			if #entries == 0 then
				UI.Text(rows, "Joue une manche pour apparaître ici !", { Size = UDim2.new(1, 0, 0, 48), AnchorPoint = Vector2.zero,
					Position = UDim2.new(), Max = 32, Font = "Bold" })
			end
		end
	end
end

local function refreshLeaderboard()
	local entries = {}
	local ok = false
	if ordered then
		ok = pcall(function()
			local pages = ordered:GetSortedAsync(false, 8)
			for _, item in pages:GetCurrentPage() do
				local id = tonumber(string.match(item.key, "%d+"))
				local name = "?"
				if id then
					local okName, n = pcall(Players.GetNameFromUserIdAsync, Players, id)
					if okName then name = n end
				end
				table.insert(entries, { Name = name, Value = item.value })
			end
		end)
	end
	if not ok then
		-- repli : joueurs présents sur le serveur
		for p, d in DataService.Profiles do
			table.insert(entries, { Name = p.Name, Value = d.Stats.TailsTaken })
		end
		table.sort(entries, function(a, b) return a.Value > b.Value end)
	end
	renderLeaderboard(entries)
end

-- -------------------------------------------------------------------- init
function DataService.Init()
	Players.PlayerAdded:Connect(function(p) task.spawn(DataService.Load, p) end)
	for _, p in Players:GetPlayers() do task.spawn(DataService.Load, p) end

	Players.PlayerRemoving:Connect(function(p)
		DataService.Save(p)
		DataService.Profiles[p] = nil
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not store then return end
		local pending = 0
		for _, p in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				DataService.Save(p)
				pending -= 1
			end)
		end
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < 25 do task.wait(0.1) end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Data.AutoSaveInterval)
			for _, p in Players:GetPlayers() do task.spawn(DataService.Save, p) end
		end
	end)

	task.spawn(function()
		task.wait(3)
		while true do
			refreshLeaderboard()
			task.wait(Config.Data.LeaderboardRefresh)
		end
	end)

	Remotes.GetProfile.OnServerInvoke = function(player)
		DataService.Wait(player, 10)
		return DataService.Snapshot(player)
	end
end

DataService.RefreshLeaderboard = refreshLeaderboard

return DataService
