--[[
	Tutorial - tutoriel en 4 pages (fenêtre en-tête vert + livre).
	Chaque page : grand stud panel coloré (soleil qui tourne + icône sticker inclinée qui déborde, titre extrudé,
	description Montserrat Bold), une rangée "extra" (touches, gains...), points de pagination, RETOUR (gris) / SUIVANT (bleu)
	puis C'EST PARTI ! (vert) à la dernière page. Pill "1 / 4" sur la jointure de l'en-tête.
	S'ouvre automatiquement au premier passage (profil.TutorialDone == false) et via la tuile "Tuto" du lobby.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Tutorial = {}
local RGB = Color3.fromRGB

function Tutorial.Build(ctx)
	local UI, Icons, Motion = ctx.UI, ctx.Icons, ctx.Motion
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local C = ctx.Config.Coins
	local gui = UI.ScreenGui("MenuTuto", 11, { Parent = ctx.PlayerGui })
	Motion.CreateSounds(gui.Sons)
	local win = UI.Window(gui, { Size = Vector2.new(640, 470), Title = "Comment jouer", Header = "green", TitleWidth = 420,
		Icon = Icons.Get("Item/Book/Yellow Book 1st Outline") })
	local body = win.Corps
	local pill = UI.Pill(win.Fenetre, "1 / 4", { Width = 120, Position = UDim2.new(0.5, 0, 0, win.HeaderHeight), ZIndex = 20 })

	local HUNTER = UI.seq(RGB(255, 110, 110), RGB(240, 30, 60), RGB(170, 0, 30))
	local PAGES = {
		{ Title = "GARDE TA QUEUE !", Gradient = "cyan", Icon = "Exclusive/Trail/Red Trail 1st Outline", Stroke = RGB(2, 30, 60),
			Text = "Chaque participant porte une queue dans le dos. Survis le plus longtemps possible sans te la faire arracher !",
			Extra = { { "3:00", "par manche" }, { "2+", "joueurs" }, { "1-2", "chasseurs" } } },
		{ Title = "LES CHASSEURS", Gradient = HUNTER, Icon = "Player/Skull/Skull 1st Outline", Stroke = RGB(60, 0, 12),
			Text = "Ils brillent en ROUGE à travers les murs. S'ils te touchent, ta queue est arrachée... et tu deviens chasseur à ton tour !",
			Extra = { { "ROUGE", "= danger" }, { "2 s", "d'immunité" }, { "+1", "queue prise" } } },
		{ Title = "BOUGE COMME UN PRO", Gradient = "violet", Icon = "Main/Lighting/Lighting 1st Outline", Stroke = RGB(34, 4, 70),
			Text = "Dash pour t'échapper, slide pour passer dans les mini-tunnels (néon cyan), jump pads verts pour monter sur les toits.",
			Extra = { { "Q / Shift", "DASH" }, { "C / Ctrl", "SLIDE" }, { "Pad vert", "SAUT" } } },
		{ Title = "GAGNE DES PIÈCES", Gradient = "gold", Icon = "Currency/Coin/Golden Coin 1st Outline", Stroke = RGB(70, 34, 0),
			Text = "Dépense-les au Shop du lobby : skins de queue, traînées de dash et effets de capture. Que du style, aucun avantage !",
			Extra = { { "+1", ("/ %d s survie"):format(C.SurvivalSecondsPerCoin) }, { "+" .. C.PerTail, "par queue" }, { "+" .. C.LastSurvivor, "survivant" } } },
	}

	-- ------------------------------------------------------------ éléments réutilisés d'une page à l'autre
	local holder = UI.new("Frame", { Name = "Page", BackgroundTransparency = 1, Size = UDim2.fromOffset(603, 232),
		Position = UDim2.fromOffset(317, 136), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3 }, body)
	local pageScale = UI.new("UIScale", {}, holder)
	local panel = UI.StudPanel(holder, { Name = "Panneau", Size = UDim2.fromOffset(603, 232), Gradient = "cyan", ZIndex = 3 })
	panel.ClipsDescendants = false
	local sun = UI.Sunburst(panel, 300, { Position = UDim2.fromOffset(130, 116), Transparency = 0.5, ZIndex = 4 })
	local icon = UI.Image(panel, "", { Name = "Icone", Size = UDim2.fromOffset(176, 176), Position = UDim2.fromOffset(128, 108), Rotation = -10, ZIndex = 9 })
	local title, titleShadow = UI.ShadowText(panel, "", { Font = "Gotham", Max = 36, Size = UDim2.fromOffset(360, 50),
		Position = UDim2.fromOffset(418, 52), Thickness = 3.6, ZIndex = 10 })
	local desc = UI.Text(panel, "", { Font = "Bold", Max = 21, Size = UDim2.fromOffset(350, 110), Position = UDim2.fromOffset(418, 148),
		Thickness = 2.4, ZIndex = 10 })

	local extras = {}
	for i = 1, 3 do
		local box = UI.InsetBox(body, { Name = "Extra" .. i, Size = UDim2.fromOffset(190, 54), Position = UDim2.fromOffset(16 + (i - 1) * 206, 262) })
		local big = UI.Text(box, "", { Font = "Gotham", Size = UDim2.new(0.5, -6, 1, -6), Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
			AlignX = Enum.TextXAlignment.Left, Max = 24, Gradient = UI.TextGradients.Stock, Stroke = RGB(33, 7, 0), Thickness = 2.6, ZIndex = 6 })
		local small = UI.Text(box, "", { Size = UDim2.new(0.5, -8, 1, -6), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
			AlignX = Enum.TextXAlignment.Right, Max = 17, Thickness = 2.2, ZIndex = 6 })
		extras[i] = { Big = big, Small = small }
	end

	local dots = {}
	for i = 1, #PAGES do
		local d = UI.new("Frame", { Name = "Point" .. i, BackgroundColor3 = RGB(60, 70, 80), BorderSizePixel = 0, Size = UDim2.fromOffset(14, 14),
			Position = UDim2.fromOffset(317 + (i - (#PAGES + 1) / 2) * 24, 336), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 4 }, body)
		UI.new("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
		UI.Stroke(d, UI.Colors.SlotStroke, 2)
		dots[i] = d
	end

	local back = UI.Button(body, { Name = "Retour", Theme = "gray", Size = Vector2.new(160, 52), Position = UDim2.fromOffset(98, 342),
		Text = "RETOUR", TextSize = 26 })
	local nextB = UI.Button(body, { Name = "Suivant", Theme = "blue", Size = Vector2.new(190, 56), Position = UDim2.fromOffset(526, 340),
		Text = "SUIVANT", TextSize = 28 })

	local menu = Motion.Window(gui, win.Fenetre, { Keep = { Notifications = true, Recompenses = true } })
	Motion.Spin(sun, 22)
	Motion.Sway(icon, 4, 1.8)
	local api = { Gui = gui, Menu = menu }
	local page = 1

	local function show(n: number, animate: boolean?)
		page = math.clamp(n, 1, #PAGES)
		local p = PAGES[page]
		panel.Degrade.Color = if typeof(p.Gradient) == "string" then UI.PanelThemes[p.Gradient] else p.Gradient
		icon.Image = Icons.Get(p.Icon)
		title.Text, titleShadow.Text = p.Title, p.Title
		title.UIStroke.Color = p.Stroke
		titleShadow.UIStroke.Color = p.Stroke
		titleShadow.TextColor3 = p.Stroke
		desc.Text = p.Text
		desc.UIStroke.Color = p.Stroke
		for i, e in extras do
			local x = p.Extra[i]
			e.Big.Text = x and x[1] or ""
			e.Small.Text = x and x[2] or ""
		end
		for i, d in dots do
			d.BackgroundColor3 = if i == page then UI.Colors.Selection else RGB(60, 70, 80)
			d.Size = if i == page then UDim2.fromOffset(18, 18) else UDim2.fromOffset(14, 14)
		end
		pill.Texte.Text = ('<font color="#FFD23F">%d</font> / %d'):format(page, #PAGES)
		UI.SetDisabled(back, page == 1)
		local last = page == #PAGES
		UI.Recolor(nextB, if last then "green" else "blue")
		UI.SetButtonText(nextB, if last then "C'EST PARTI !" else "SUIVANT")
		if animate then
			pageScale.Scale = 0.88
			TweenService:Create(pageScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			Motion.Play(gui.Sons, "Carte")
		end
	end

	Motion.BindButton(back, 1.05, gui.Sons, function()
		if page > 1 then show(page - 1, true) end
	end)
	Motion.BindButton(nextB, 1.05, gui.Sons, function()
		if page < #PAGES then
			show(page + 1, true)
		else
			Remotes.TutorialDone:FireServer()
			Motion.Play(gui.Sons, "Achat")
			menu.Close()
			ctx.Notify("Bonne chance ! Clique sur JOUER quand tu es prêt.", "go")
		end
	end)

	function api.Open()
		show(1, false)
		menu.Open()
	end
	function api.Close() menu.Close() end
	show(1, false)
	return api
end

return Tutorial
