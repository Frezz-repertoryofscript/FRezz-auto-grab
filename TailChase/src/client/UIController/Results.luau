--[[
	Results - écran de résultats animé (fenêtre en-tête doré + trophée).
		3 grandes cartes (slots à soleil) : SURVIE / QUEUES / PIÈCES (les pièces défilent avec un tic sonore)
		détail des gains (InsetBox, valeurs surlignées #FFD23F)
		classement de la manche (liste d'InsetBox)
	S'ouvre via StudMotion.Window (rebond, flou 18, FOV +8), se ferme seul après Config.ResultsTime.
]]

local TweenService = game:GetService("TweenService")

local Results = {}
local RGB = Color3.fromRGB

function Results.Build(ctx)
	local UI, Icons, Motion = ctx.UI, ctx.Icons, ctx.Motion
	local gui = UI.ScreenGui("MenuResultats", 12, { Parent = ctx.PlayerGui })
	Motion.CreateSounds(gui.Sons)
	local win = UI.Window(gui, { Size = Vector2.new(640, 470), Title = "Résultats", Header = "gold",
		Icon = Icons.Get("Item/Trophy/Golden Trophy 1st Outline") })
	local headline = UI.Pill(win.Fenetre, "", { Width = 360, Position = UDim2.new(0.5, 0, 0, win.HeaderHeight), ZIndex = 20 })

	local function card(x: number, top: string, icon: string)
		local s = UI.ItemSlot(win.Corps, { Name = "Carte" .. top, Button = false, Size = Vector2.new(170, 130), Position = UDim2.fromOffset(x, 36),
			Icon = Icons.Get(icon), IconScale = 0.6, Title = "-", TitleMax = 30, Top = top, ZIndex = 3 })
		s.Icone.Rotation = -10
		return s
	end
	local cSurv = card(37, "SURVIE", "Item/Clock/Clock 1st Outline")
	local cTails = card(232, "QUEUES", "Exclusive/Trail/Red Trail 1st Outline")
	local cCoins = card(427, "PIÈCES", "Currency/Coin/Golden Coin 1st Outline")
	cCoins.Rayons.Soleil.ImageColor3 = RGB(255, 210, 60)
	Motion.SpinSunbursts(win.Corps, 20)

	local detail = UI.InsetBox(win.Corps, { Name = "Detail", Size = UDim2.fromOffset(560, 40), Position = UDim2.fromOffset(37, 182) })
	local detailText = UI.Text(detail, "", { Size = UDim2.new(1, -16, 1, -6), Max = 19, Rich = true, Thickness = 2.4, ZIndex = 6 })

	local list = UI.ScrollList(win.Corps, { Name = "Classement", Size = UDim2.fromOffset(572, 150), Position = UDim2.fromOffset(31, 232),
		Padding = 6, PadTop = 4, PadLeft = 6 })

	local menu = Motion.Window(gui, win.Fenetre, { Keep = { Notifications = true } })
	local api = { Gui = gui, Menu = menu }
	local token = 0

	local function setTitle(slot, text: string)
		slot.Nom.Text = text
	end

	function api.Show(data)
		token += 1
		local my = token
		local m = data.Mine
		headline.Texte.Text = ('<font color="#FFD23F">%s</font>'):format(data.Headline or "Fin de la manche !")
		setTitle(cSurv, ctx.Duration(m.Survival))
		setTitle(cTails, "x" .. tostring(m.Tails))
		setTitle(cCoins, "+0")
		local b = m.Coins
		detailText.Text = ('Survie <font color="#FFD23F">+%d</font>   Queues <font color="#FFD23F">+%d</font>   Participation <font color="#FFD23F">+%d</font>%s')
			:format(b.Survival, b.Tails, b.Participation, if b.Bonus > 0 then ('   Survivant <font color="#60E87A">+%d</font>'):format(b.Bonus) else "")

		for _, c in list:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		for i, row in data.Rows do
			local box = UI.InsetBox(list, { Name = "Ligne" .. i, Size = UDim2.fromOffset(554, 36), LayoutOrder = i,
				Transparency = if row.Name == ctx.Player.DisplayName then 0 else 0.25,
				Color = if row.Name == ctx.Player.DisplayName then RGB(30, 60, 30) else nil })
			local medal = if i == 1 then "#FFD23F" elseif i == 2 then "#E2E6EC" elseif i == 3 then "#FF9A4A" else "#FFFFFF"
			UI.Text(box, ('<font color="%s">#%d</font>  %s%s'):format(medal, i, row.Name, if row.Survived then '  <font color="#60E87A">SURVIVANT</font>' else ""),
				{ Size = UDim2.new(0.6, -10, 1, 0), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
					AlignX = Enum.TextXAlignment.Left, Max = 18, Rich = true, Thickness = 2.2, ZIndex = 6 })
			UI.Text(box, ('%s   x%d   <font color="#FFD23F">+%d</font>'):format(ctx.Duration(row.Survival), row.Tails, row.Coins),
				{ Size = UDim2.new(0.4, -10, 1, 0), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
					AlignX = Enum.TextXAlignment.Right, Max = 18, Rich = true, Thickness = 2.2, ZIndex = 6 })
		end

		menu.Open()
		if m.Survived or m.LastSurvivor then ctx.Audio.Play("Victory") end
		-- cartes qui "pop" une par une, puis pièces qui défilent
		for i, c in { cSurv, cTails, cCoins } do
			local sc = c:FindFirstChild("ButtonScale") :: UIScale
			sc.Scale = 0.3
			task.delay(0.15 + i * 0.15, function()
				if token ~= my then return end
				TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				Motion.Play(gui.Sons, "Carte")
			end)
		end
		task.delay(0.8, function()
			local total = b.Total
			local t0 = os.clock()
			local last = -1
			while token == my do
				local a = math.clamp((os.clock() - t0) / 1.4, 0, 1)
				local v = math.floor(total * (1 - (1 - a) ^ 2))
				if v ~= last then
					setTitle(cCoins, "+" .. v)
					if v % 3 == 0 then ctx.Audio.Play("CoinTick", nil, 0.05) end
					last = v
				end
				if a >= 1 then break end
				task.wait()
			end
			if token == my then
				Motion.Float(cCoins, "+" .. total .. " pièces !", UI.Colors.FloatSuccess)
			end
		end)
		task.delay(ctx.Config.ResultsTime - 0.3, function()
			if token == my then menu.Close() end
		end)
	end
	return api
end

return Results
