--[[
	MapVote - fenêtre de vote de map pendant l'intermission (archétype C "calendrier de récompenses" du kit :
	grandes tuiles stud panel colorées, soleil qui tourne derrière l'icône, nom en MAJUSCULES, bouton d'état).
		VOTER (vert)  ->  VOTÉ ! (gris) sur la tuile choisie ; on peut changer d'avis.
		Compteur de votes par tuile, couronne qui se balance sur la map en tête, Pill "Fin du vote dans 12 s".
	S'ouvre seule au début de l'intermission, se ferme seule à la fin ; bouton VOTE du HUD pour la rouvrir.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local MapVote = {}
local RGB = Color3.fromRGB

function MapVote.Build(ctx)
	local UI, Icons, Motion = ctx.UI, ctx.Icons, ctx.Motion
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local gui = UI.ScreenGui("MenuVote", 11, { Parent = ctx.PlayerGui })
	Motion.CreateSounds(gui.Sons)
	local win = UI.Window(gui, { Size = Vector2.new(640, 440), Title = "Vote de map", Header = "blue", TitleWidth = 400,
		Icon = Icons.Get("Item/Location Pin/Location Pin 1st Outline") })
	local pill = UI.Pill(win.Fenetre, "", { Width = 260, Position = UDim2.new(0.5, 0, 0, win.HeaderHeight), ZIndex = 20 })
	local menu = Motion.Window(gui, win.Fenetre, { Keep = { Notifications = true, Recompenses = true } })

	local api = { Gui = gui, Menu = menu }
	local tiles = {}
	local myVote: string? = nil
	local catalog = {}

	local function loadCatalog()
		local raw = ReplicatedStorage:GetAttribute("MapCatalog")
		if typeof(raw) == "string" then
			local ok, list = pcall(HttpService.JSONDecode, HttpService, raw)
			if ok then for _, m in list do catalog[m.Id] = m end end
		end
	end

	local function clear()
		for _, t in tiles do t.Frame:Destroy() end
		table.clear(tiles)
	end

	local function refresh()
		local best, bestN = nil, 0
		for _, t in tiles do
			local n = ReplicatedStorage:GetAttribute("Votes_" .. t.Id) or 0
			t.Count.Text = ('<font color="#FFD23F">%d</font> vote%s'):format(n, if n > 1 then "s" else "")
			if n > bestN then best, bestN = t, n elseif n == bestN then best = nil end
			local mine = myVote == t.Id
			UI.Recolor(t.Button, if mine then "gray" else "green")
			UI.SetButtonText(t.Button, if mine then "VOTÉ !" else "VOTER")
			t.Selection.Enabled = mine
		end
		for _, t in tiles do t.Crown.Visible = t == best end
	end

	--- (Re)construit les tuiles à partir de VoteOptions.
	local function build()
		clear()
		myVote = nil
		local raw = ReplicatedStorage:GetAttribute("VoteOptions")
		if typeof(raw) ~= "string" then return false end
		local ok, ids = pcall(HttpService.JSONDecode, HttpService, raw)
		if not ok or #ids == 0 then return false end
		if next(catalog) == nil then loadCatalog() end
		local n = #ids
		local w, gap = 192, 14
		local x0 = (635 - (n * w + (n - 1) * gap)) / 2
		for i, id in ids do
			local m = catalog[id] or { Name = id, Description = "", Icon = "Main/Star/Golden Star 1st Outline", Gradient = "cyan" }
			local x = x0 + (i - 1) * (w + gap)
			local tile = UI.StudPanel(win.Corps, { Name = "Map_" .. id, Size = UDim2.fromOffset(w, 290), Position = UDim2.fromOffset(x, 30),
				Gradient = m.Gradient or "cyan", ZIndex = 3 })
			local sel = UI.Stroke(tile, UI.Colors.Selection, 4, 0, nil, "Selection")
			sel.Enabled = false
			UI.ShadowText(tile, string.upper(m.Name), { Size = UDim2.new(1, -14, 0, 36), Position = UDim2.new(0.5, 0, 0, 28), Max = 28,
				Thickness = 3.2, Stroke = RGB(10, 22, 40), ZIndex = 9 })
			UI.Sunburst(tile, 190, { Position = UDim2.fromScale(0.5, 0.4), ZIndex = 4 })
			UI.Image(tile, Icons.Get(m.Icon or "Main/Star/Golden Star 1st Outline"), { Name = "Icone", Size = UDim2.fromOffset(104, 104),
				Position = UDim2.fromScale(0.5, 0.4), Rotation = -8, ZIndex = 6 })
			UI.Text(tile, m.Description or "", { Font = "Bold", Size = UDim2.new(1, -18, 0, 36), Position = UDim2.new(0.5, 0, 1, -98), Max = 16,
				Thickness = 2.2, Stroke = RGB(10, 22, 40), ZIndex = 8 })
			local count = UI.Text(tile, "", { Name = "Votes", Size = UDim2.new(1, -18, 0, 24), Position = UDim2.new(0.5, 0, 1, -66), Max = 20,
				Rich = true, Thickness = 2.6, Stroke = RGB(10, 22, 40), ZIndex = 8 })
			local btn = UI.Button(tile, { Name = "Bouton", Theme = "green", Size = Vector2.new(166, 46), Position = UDim2.new(0.5, 0, 1, -28),
				Text = "VOTER", TextSize = 24, ZIndex = 8 })
			local crown = UI.Image(tile, Icons.Get("Item/Crown/Crown 1st Outline"), { Name = "Couronne", Size = UDim2.fromOffset(58, 58),
				Position = UDim2.new(1, -6, 0, 2), Rotation = 14, ZIndex = 14 })
			crown.Visible = false
			Motion.Sway(crown, 6, 2.4)
			Motion.BindButton(btn, 1.05, gui.Sons, function()
				if myVote == id then return end
				myVote = id
				Remotes.MapVote:FireServer(id)
				Motion.Play(gui.Sons, "Achat", 1.3)
				Motion.Float(btn, "+1 vote !", UI.Colors.FloatSuccess)
				local sc = tile:FindFirstChildOfClass("UIScale") or UI.new("UIScale", {}, tile)
				sc.Scale = 1.06
				TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				refresh()
			end)
			table.insert(tiles, { Id = id, Frame = tile, Count = count, Button = btn, Selection = sel, Crown = crown })
			ReplicatedStorage:GetAttributeChangedSignal("Votes_" .. id):Connect(function()
				if tiles[i] and tiles[i].Id == id then refresh() end
			end)
		end
		Motion.SpinSunbursts(win.Corps, 20)
		refresh()
		return true
	end

	function api.Update()
		if not menu.IsOpen then return end
		local left = math.max(0, (ReplicatedStorage:GetAttribute("EndsAt") or 0) - workspace:GetServerTimeNow())
		pill.Texte.Text = ('Fin du vote dans <font color="#FFD23F">%d s</font>'):format(math.ceil(left))
	end
	function api.HasVote(): boolean
		return #tiles > 0
	end
	function api.Open()
		if #tiles == 0 and not build() then return end
		menu.Open()
		api.Update()
	end
	function api.Close() menu.Close() end

	ReplicatedStorage:GetAttributeChangedSignal("VoteOptions"):Connect(function()
		if ReplicatedStorage:GetAttribute("VoteOptions") then
			if build() and not ctx.InRound() and ctx.Player:GetAttribute("Ready") == true then menu.Open() end
		else
			clear()
			menu.Close()
		end
	end)
	return api
end

return MapVote
