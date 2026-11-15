--[[
	Hud - HUD permanent construit avec le kit StudUI (offsets 1050x620 + une WindowScale par racine).
		Haut centre  : minuteur (InsetBox + Pill d'état) + sous-titre (départ des chasseurs / joueurs prêts)
		Haut gauche  : badge de rôle (bouton stud recoloré) + participants restants
		Bas gauche   : pièces (MoneyText + pièce dorée) + queues prises
		Bas centre   : barre de cooldown du dash + rappel des touches
		Bas droite   : boutons tactiles Dash / Slide (mobile uniquement)
]]

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Hud = {}

local RGB = Color3.fromRGB

function Hud.Build(ctx)
	local UI, Icons, Motion = ctx.UI, ctx.Icons, ctx.Motion
	local gui = UI.ScreenGui("HudTailChase", 4, { Parent = ctx.PlayerGui, Menu = false, IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets })
	local api = { Gui = gui }

	local function root(name, size, pos, anchor)
		local f = UI.new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(size.X, size.Y),
			Position = pos, AnchorPoint = anchor }, gui)
		local sc = UI.new("UIScale", { Name = "WindowScale" }, f)
		Motion.BindResponsive(sc, 0.9)
		return f
	end

	-- ------------------------------------------------------------ minuteur
	local top = root("Minuteur", Vector2.new(300, 120), UDim2.new(0.5, 0, 0, 4), Vector2.new(0.5, 0))
	local box = UI.InsetBox(top, { Name = "Boite", Size = UDim2.fromOffset(210, 62), Position = UDim2.fromOffset(45, 22) })
	local timerText, timerShadow = UI.ShadowText(box, "--:--", { Font = "Gotham", Max = 44, Size = UDim2.new(1, -16, 1, -8),
		Stroke = RGB(8, 12, 14), Thickness = 3, ZIndex = 8 })
	local pill = UI.Pill(top, "LOBBY", { Width = 190, Position = UDim2.fromOffset(150, 22), TextSize = 18 })
	local subText = UI.Text(top, "", { Name = "Sous", Font = "Gotham", Size = UDim2.fromOffset(320, 26), Position = UDim2.fromOffset(150, 102),
		Max = 20, Rich = true, Stroke = RGB(10, 12, 16), Thickness = 2.6 })

	function api.SetTimer(text: string, urgent: boolean?)
		timerText.Text = text
		timerShadow.Text = text
		timerText.TextColor3 = if urgent then RGB(255, 110, 110) else Color3.new(1, 1, 1)
	end
	function api.SetState(text: string)
		pill.Texte.Text = text
	end
	function api.SetSub(text: string)
		subText.Text = text
	end

	-- ------------------------------------------------------------ rôle + restants
	local roleRoot = root("Role", Vector2.new(240, 120), UDim2.fromOffset(12, 8), Vector2.zero)
	local badge = UI.Button(roleRoot, { Name = "Badge", Theme = "gray", Size = Vector2.new(220, 64), Position = UDim2.fromOffset(110, 32),
		Text = "LOBBY", TextSize = 30, Icon = Icons.Get("Main/House/Blue House 1st Outline") })
	badge.Active = false
	badge.Selectable = false
	local restRow = UI.new("Frame", { Name = "Restants", BackgroundTransparency = 1, Size = UDim2.fromOffset(230, 40),
		Position = UDim2.fromOffset(0, 72) }, roleRoot)
	UI.Image(restRow, Icons.Get("Player/4 Players/4 Players 1st Outline"), { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(24, 20), Rotation = -8 })
	local restText, restShadow = UI.ShadowText(restRow, "", { Font = "Gotham", Max = 24, Size = UDim2.fromOffset(180, 30),
		Position = UDim2.fromOffset(48, 22), AnchorPoint = Vector2.new(0, 0.5), AlignX = Enum.TextXAlignment.Left,
		Stroke = RGB(10, 12, 16), Thickness = 3, ZIndex = 4 })

	local ROLE_LOOK = {
		Hunter = { "red", "CHASSEUR", "Player/Skull/Skull 1st Outline" },
		Runner = { "blue", "PARTICIPANT", "Item/Shoe/Blue Shoe 1st Outline" },
		Lobby = { "gray", "LOBBY", "Main/House/Blue House 1st Outline" },
	}
	function api.SetRole(role: string)
		local look = ROLE_LOOK[role] or ROLE_LOOK.Lobby
		UI.Recolor(badge, look[1])
		UI.SetButtonText(badge, look[2])
		badge.Icone.Image = Icons.Get(look[3])
		local sc = badge:FindFirstChild("ButtonScale")
		if sc then
			sc.Scale = 1.15
			TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	function api.SetRemaining(text: string)
		restText.Text = text
		restShadow.Text = text
		restRow.Visible = text ~= ""
	end

	-- ------------------------------------------------------------ pièces + queues prises
	local stats = root("Stats", Vector2.new(320, 110), UDim2.new(0, 12, 1, -12), Vector2.new(0, 1))
	UI.Image(stats, Icons.Get("Currency/Coin/Golden Coin 1st Outline"), { Name = "Piece", Size = UDim2.fromOffset(46, 46),
		Position = UDim2.fromOffset(24, 28), Rotation = -10, ZIndex = 3 })
	local moneyHolder = UI.new("Frame", { Name = "Argent", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40), Position = UDim2.fromOffset(52, 8) }, stats)
	local moneyText, moneyShadow = UI.MoneyText(moneyHolder, "0")
	UI.Image(stats, Icons.Get("Exclusive/Trail/Red Trail 1st Outline"), { Name = "QueueIcone", Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(24, 80), Rotation = -12, ZIndex = 3 })
	local tailsText, tailsShadow = UI.ShadowText(stats, "Queues prises : 0", { Font = "Gotham", Max = 24, Size = UDim2.fromOffset(260, 30),
		Position = UDim2.fromOffset(52, 82), AnchorPoint = Vector2.new(0, 0.5), AlignX = Enum.TextXAlignment.Left,
		Stroke = RGB(24, 25, 21), Thickness = 3, ZIndex = 2 })

	local shownCoins = 0
	function api.SetCoins(n: number)
		local from = shownCoins
		shownCoins = n
		local t0 = os.clock()
		task.spawn(function()
			while true do
				local a = math.clamp((os.clock() - t0) / 0.6, 0, 1)
				local v = math.floor(from + (n - from) * a)
				local s = tostring(v):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
				moneyText.Text = s
				moneyShadow.Text = s
				if a >= 1 then break end
				task.wait()
			end
		end)
	end
	function api.SetTails(n: number)
		local s = "Queues prises : " .. n
		tailsText.Text = s
		tailsShadow.Text = s
		if n > 0 then
			tailsText.TextColor3 = UI.Colors.FloatSuccess
			task.delay(0.6, function() tailsText.TextColor3 = Color3.new(1, 1, 1) end)
		end
	end

	-- ------------------------------------------------------------ dash
	local dashRoot = root("Dash", Vector2.new(300, 84), UDim2.new(0.5, 0, 1, -10), Vector2.new(0.5, 1))
	UI.Text(dashRoot, "[Q] DASH     [C] SLIDE", { Name = "Touches", Font = "Gotham", Size = UDim2.fromOffset(300, 22),
		Position = UDim2.fromOffset(150, 14), Max = 17, Stroke = RGB(10, 12, 16), Thickness = 2.4 })
	local bar = UI.ProgressBar(dashRoot, { Name = "BarreDash", Size = UDim2.fromOffset(250, 34), Position = UDim2.fromOffset(25, 36),
		Progress = 1, Text = "DASH PRÊT", Fill = UI.seq(RGB(143, 227, 252), RGB(31, 142, 245)) })
	local fill = bar:FindFirstChild("Remplissage") :: Frame
	local valueText = bar:FindFirstChild("Valeur") :: TextLabel
	UI.Image(dashRoot, Icons.Get("Main/Lighting/Blue Lighting 1st Outline"), { Name = "Eclair", Size = UDim2.fromOffset(46, 46),
		Position = UDim2.fromOffset(26, 52), Rotation = -12, ZIndex = 12 })
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		dashRoot.Touches.Visible = false
	end

	function api.UpdateDash(readyAt: number, cooldown: number)
		local left = readyAt - os.clock()
		if left <= 0 or cooldown <= 0 then
			fill.Size = UDim2.fromScale(1, 1)
			valueText.Text = "DASH PRÊT"
		else
			fill.Size = UDim2.fromScale(math.clamp(1 - left / cooldown, 0, 1), 1)
			valueText.Text = ("DASH %.1fs"):format(left)
		end
	end

	-- ------------------------------------------------------------ boutons tactiles
	if UserInputService.TouchEnabled then
		local mob = root("Mobile", Vector2.new(250, 130), UDim2.new(1, -12, 1, -150), Vector2.new(1, 1))
		local dashBtn = UI.Button(mob, { Name = "BoutonDash", Theme = "blue", Size = Vector2.new(106, 106), Position = UDim2.fromOffset(62, 65),
			IconLayout = "Big", Icon = Icons.Get("Main/Lighting/Lighting 1st Outline"), Text = "DASH", TextSize = 26 })
		local slideBtn = UI.Button(mob, { Name = "BoutonSlide", Theme = "green", Size = Vector2.new(106, 106), Position = UDim2.fromOffset(186, 65),
			IconLayout = "Big", Icon = Icons.Get("Item/Shoe/Red Shoe 1st Outline"), Text = "SLIDE", TextSize = 26 })
		Motion.BindButton(dashBtn, 1.04, ctx.Sons, function() ctx.Signals.Fire("MobileAction", "Dash") end)
		Motion.BindButton(slideBtn, 1.04, ctx.Sons, function() ctx.Signals.Fire("MobileAction", "Slide") end)
		api.Mobile = mob
	end

	function api.SetInRound(inRound: boolean)
		dashRoot.Visible = true
		roleRoot.Visible = true
		if api.Mobile then api.Mobile.Visible = true end
		_ = inRound
	end

	return api
end

return Hud
