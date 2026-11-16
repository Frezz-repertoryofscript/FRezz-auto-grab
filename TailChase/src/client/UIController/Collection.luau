--[[
	Collection - fenêtres Shop et Inventaire (archétype "grille de slots + colonne d'onglets", cf. exemple 05 du kit).
		Shop       : en-tête image rose + panier, tous les items, bouton Acheter (vert, prix) / Équiper (bleu) / Équipé (gris)
		Inventaire : en-tête bleu + sac, uniquement les items possédés, bouton Équiper / Équipé
	Onglets (à droite, hors fenêtre) : Queues / Traînées / Captures. Rareté = étiquette en dégradé + soleil teinté.
	L'item équipé a le liseré de sélection lime (pulsé).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Collection = {}
local RGB = Color3.fromRGB

function Collection.Build(ctx, mode: string)
	local UI, Icons, Motion, Cosmetics = ctx.UI, ctx.Icons, ctx.Motion, ctx.Cosmetics
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local isShop = mode == "Shop"
	local gui = UI.ScreenGui(if isShop then "MenuShop" else "MenuInventaire", 11, { Parent = ctx.PlayerGui })
	Motion.CreateSounds(gui.Sons)
	local win = UI.Window(gui, {
		Size = Vector2.new(640, 470), Position = UDim2.new(0.5, -80, 0.5, 0),
		Title = if isShop then "Shop" else "Inventaire",
		-- en-tête stud généré par le kit (l'ancienne texture "image" du shop n'est pas disponible hors du jeu de référence)
		Header = if isShop then "pink" else "blue",
		Icon = Icons.Get(if isShop then "Main/Shopping Bag/Red Shopping Bag 1st Outline" else "Item/Chest/Chest 1st Outline"),
	})
	local coinsPill = UI.Pill(win.Fenetre, "", { Width = 230, Position = UDim2.new(0.5, 0, 0, win.HeaderHeight), ZIndex = 20 })

	local grid = UI.ScrollList(win.Corps, { Size = UDim2.fromOffset(626, 382), Position = UDim2.fromOffset(4, 4),
		Grid = Vector2.new(140, 184), GridGap = 12, PadTop = 26, PadLeft = 12 })

	-- onglets
	local tabsFrame = UI.new("Frame", { Name = "Onglets", BackgroundTransparency = 1, Size = UDim2.fromOffset(162, 392),
		Position = UDim2.fromOffset(646, 78) }, win.Fenetre)
	local tabs, base = {}, {}
	for i, cat in Cosmetics.Categories do
		local b = UI.Button(tabsFrame, { Name = "Onglet_" .. cat.Id, Theme = cat.Theme, Size = Vector2.new(150, 58),
			Position = UDim2.fromOffset(83, 34 + (i - 1) * 68), Text = cat.Label, TextSize = 24, Icon = Icons.Get(cat.Icon) })
		b:SetAttribute("Categorie", cat.Id)
		table.insert(tabs, b)
		table.insert(base, b.Position)
	end

	local menu = Motion.Window(gui, win.Fenetre, { Keep = { Notifications = true, Recompenses = true } })
	local api = { Gui = gui, Menu = menu, Window = win }
	local currentCat = Cosmetics.Categories[1].Id
	local cells: { [string]: Frame } = {}
	local busy = false

	local function rarityColor(r: string): Color3
		local rr = UI.Rarities[r]
		return if rr then rr.tab.fond.Keypoints[1].Value else Color3.new(1, 1, 1)
	end

	-- --------------------------------------------------------- bouton d'action d'une cellule
	local function setAction(cell: Frame, item, profile)
		local old = cell:FindFirstChild("Action")
		if old then old:Destroy() end
		local owned = profile and profile.Owned[item.Id]
		local equipped = profile and profile.Equipped[item.Category] == item.Id
		local btn
		if equipped then
			btn = UI.Button(cell, { Name = "Action", Theme = "gray", Size = Vector2.new(140, 46), Position = UDim2.fromOffset(70, 160),
				Text = "ÉQUIPÉ", TextSize = 24, Icon = UI.Assets.Check })
			UI.SetDisabled(btn, true)
		elseif owned then
			btn = UI.Button(cell, { Name = "Action", Theme = "blue", Size = Vector2.new(140, 46), Position = UDim2.fromOffset(70, 160),
				Text = "ÉQUIPER", TextSize = 24 })
		else
			btn = UI.Button(cell, { Name = "Action", Style = "Glossy", Theme = "cash", Size = Vector2.new(140, 46), Position = UDim2.fromOffset(70, 160),
				Text = ctx.Abbreviate(item.Price), FixedTextSize = 26, Icon = Icons.Get("Currency/Coin/Golden Coin 1st Outline") })
		end
		Motion.BindButton(btn, 1.05, gui.Sons)
		btn.Activated:Connect(function()
			if equipped or busy then return end
			busy = true
			local remote = if owned then Remotes.ShopEquip else Remotes.ShopPurchase
			local ok, res = pcall(remote.InvokeServer, remote, item.Id)
			busy = false
			if ok and res and res.Ok then
				if not owned then
					Motion.Play(gui.Sons, "Achat", 1)
					ctx.Audio.Play("Purchase")
					Motion.Float(btn, "Acheté !", UI.Colors.FloatSuccess)
				else
					Motion.Float(btn, "Équipé !", UI.Colors.FloatSuccess)
				end
				if res.Profile then ctx.SetProfile(res.Profile) end
			else
				Motion.Play(gui.Sons, "Refus")
				Motion.Shake(btn)
				Motion.Float(btn, if ok and res then res.Message else "Erreur", UI.Colors.FloatError)
			end
		end)
	end

	-- --------------------------------------------------------- cellules
	for i, item in Cosmetics.Items do
		local cell = UI.new("Frame", { Name = "Cellule_" .. item.Id, BackgroundTransparency = 1, Size = UDim2.fromOffset(140, 184),
			LayoutOrder = i }, grid)
		cell:SetAttribute("Categorie", item.Category)
		local slot = UI.ItemSlot(cell, { Name = "Carte", Button = false, Size = Vector2.new(140, 130), Icon = Icons.Get(item.Icon),
			IconScale = 0.66, Title = item.Name, TitleMax = 20, Tag = string.upper(item.Rarity), TagColor = Color3.new(1, 1, 1) })
		local tag = slot:FindFirstChild("Etiquette")
		local rr = UI.Rarities[item.Rarity]
		if tag and rr then UI.Gradient(tag, rr.text, 90) end
		local sun = slot:FindFirstChild("Soleil", true)
		if sun then sun.ImageColor3 = rarityColor(item.Rarity) end
		slot.Icone.Rotation = -8
		cells[item.Id] = cell
	end
	Motion.SpinSunbursts(grid, 20)

	local function applyFilter(profile)
		for id, cell in cells do
			local item = Cosmetics.Get(id)
			local owned = profile and profile.Owned[id]
			cell.Visible = item ~= nil and item.Category == currentCat and (isShop or owned == true)
		end
	end

	function api.Refresh(profile)
		if not profile then return end
		coinsPill.Texte.Text = ('<font color="#FFD23F">%s</font> pièces'):format(ctx.Abbreviate(profile.Coins))
		for id, cell in cells do
			local item = Cosmetics.Get(id)
			if item then
				setAction(cell, item, profile)
				local sel = cell.Carte.Lisere:FindFirstChild("Selection")
				if sel then
					local on = profile.Equipped[item.Category] == id
					sel.Enabled = on
					if on then Motion.PulseStroke(sel) else Motion.StopIdle(sel) end
				end
			end
		end
		applyFilter(profile)
	end

	local function choose(tab)
		Motion.SelectTab(tabs, tab, 6, base)
		currentCat = tab:GetAttribute("Categorie")
		applyFilter(ctx.GetProfile())
	end
	for _, b in tabs do
		Motion.BindButton(b, 1.05, gui.Sons, function() choose(b) end)
	end
	choose(tabs[1])

	-- l'icône d'en-tête se balance (comme le panier de la référence)
	if win.Icone then Motion.Sway(win.Icone, 3, 1.6) end

	function api.Open() menu.Open() end
	function api.Close() menu.Close() end
	_ = RGB
	return api
end

return Collection
