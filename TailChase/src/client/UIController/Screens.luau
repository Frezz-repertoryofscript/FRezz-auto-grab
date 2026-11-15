--[[
	Screens - notifications animées + écran de rôle / décompte de début de manche.
	Notifications : Pills StudUI empilées en haut (pop Back-Out, 3 s, fondu), couleur selon le type.
	Écran de rôle : StudPanel rouge (chasseur) ou bleu (participant), icône sticker inclinée qui déborde,
	titre extrudé, consigne, puis décompte 5..1 et "GO !" qui "pop".
]]

local TweenService = game:GetService("TweenService")

local Screens = {}
local RGB = Color3.fromRGB

local KIND_COLOR = {
	hunter = "#FF5A6A",
	success = "#B4FF3C",
	danger = "#FF7A7A",
	go = "#FFD23F",
	info = "#FFFFFF",
}

function Screens.BuildNotifications(ctx)
	local UI, Motion = ctx.UI, ctx.Motion
	local gui = UI.ScreenGui("Notifications", 30, { Parent = ctx.PlayerGui, Menu = false, IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets })
	local holder = UI.new("Frame", { Name = "Pile", BackgroundTransparency = 1, Size = UDim2.fromOffset(640, 260),
		Position = UDim2.new(0.5, 0, 0, 132), AnchorPoint = Vector2.new(0.5, 0) }, gui)
	Motion.BindResponsive(UI.new("UIScale", { Name = "WindowScale" }, holder), 0.9)
	UI.new("UIListLayout", { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder }, holder)

	local api = { Gui = gui }
	local order = 0
	function api.Push(text: string, kind: string?)
		order += 1
		local items = {}
		for _, c in holder:GetChildren() do if c:IsA("Frame") then table.insert(items, c) end end
		if #items >= 4 then
			table.sort(items, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
			items[1]:Destroy()
		end
		local row = UI.new("Frame", { Name = "Notif", BackgroundTransparency = 1, Size = UDim2.fromOffset(640, 40), LayoutOrder = order }, holder)
		local sc = UI.new("UIScale", { Scale = 0.5 }, row)
		local col = KIND_COLOR[kind or "info"] or "#FFFFFF"
		local pill = UI.Pill(row, ('<font color="%s">%s</font>'):format(col, text), { Height = 36, TextSize = 22,
			Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
		ctx.Audio.Play("Notify")
		TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(3, function()
			if not row.Parent then return end
			local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(sc, info, { Scale = 0.6 }):Play()
			for _, d in pill:GetDescendants() do
				if d:IsA("TextLabel") then TweenService:Create(d, info, { TextTransparency = 1 }):Play() end
				if d:IsA("UIStroke") then TweenService:Create(d, info, { Transparency = 1 }):Play() end
			end
			TweenService:Create(pill, info, { BackgroundTransparency = 1 }):Play()
			task.wait(0.32)
			row:Destroy()
		end)
	end
	return api
end

function Screens.BuildRoleScreen(ctx)
	local UI, Icons, Motion = ctx.UI, ctx.Icons, ctx.Motion
	local gui = UI.ScreenGui("EcranRole", 20, { Parent = ctx.PlayerGui, Menu = false })
	local root = UI.new("Frame", { Name = "Ecran", BackgroundTransparency = 1, Size = UDim2.fromOffset(600, 330),
		Position = UDim2.new(0.5, 0, 0.5, -40), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false }, gui)
	local scale = UI.new("UIScale", { Name = "WindowScale" }, root)
	local anim = Instance.new("NumberValue")
	anim.Value = 1
	Motion.BindResponsive(scale, 1, anim)

	local HUNTER = UI.seq(RGB(255, 110, 110), RGB(240, 30, 60), RGB(170, 0, 30))
	local RUNNER = UI.seq(RGB(124, 214, 255), RGB(58, 166, 255), RGB(26, 112, 238))
	local panel = UI.StudPanel(root, { Name = "Panneau", Size = UDim2.fromOffset(540, 160), Position = UDim2.fromOffset(40, 30), Gradient = RUNNER })
	local icon = UI.Image(root, "", { Name = "Icone", Size = UDim2.fromOffset(150, 150), Position = UDim2.fromOffset(70, 40), Rotation = -12, ZIndex = 14 })
	local title, titleShadow = UI.ShadowText(panel, "TU ES PARTICIPANT !", { Font = "Gotham", Max = 50, Size = UDim2.fromOffset(400, 64),
		Position = UDim2.fromOffset(320, 58), Stroke = RGB(2, 30, 60), Thickness = 4, ZIndex = 12 })
	local sub = UI.Text(panel, "", { Font = "Bold", Max = 22, Size = UDim2.fromOffset(400, 50), Position = UDim2.fromOffset(320, 118),
		Stroke = RGB(2, 30, 60), Thickness = 2.4, ZIndex = 12 })
	local countHolder = UI.new("Frame", { Name = "Decompte", BackgroundTransparency = 1, Size = UDim2.fromOffset(300, 120),
		Position = UDim2.fromOffset(310, 262), AnchorPoint = Vector2.new(0.5, 0.5) }, root)
	local countScale = UI.new("UIScale", {}, countHolder)
	local count, countShadow = UI.ShadowText(countHolder, "5", { Font = "Gotham", Max = 110, Size = UDim2.fromScale(1, 1),
		Stroke = RGB(60, 30, 0), Thickness = 6, Offset = 5, Gradient = UI.seq(RGB(255, 240, 130), RGB(255, 160, 0)), ZIndex = 12 })

	local api = { Gui = gui }
	local token = 0

	local function pop(s: UIScale, from: number)
		s.Scale = from
		TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	function api.Show(role: string, countdown: number)
		token += 1
		local my = token
		local hunter = role == "Hunter"
		panel.Degrade.Color = if hunter then HUNTER else RUNNER
		local txt = if hunter then "TU ES CHASSEUR !" else "TU ES PARTICIPANT !"
		title.Text, titleShadow.Text = txt, txt
		local strokeCol = if hunter then RGB(60, 0, 10) else RGB(2, 30, 60)
		title.UIStroke.Color = strokeCol
		titleShadow.UIStroke.Color = strokeCol
		titleShadow.TextColor3 = strokeCol
		sub.UIStroke.Color = strokeCol
		sub.Text = if hunter then "Touche les participants pour leur arracher la queue !" else "Garde ta queue le plus longtemps possible ! Dash et slide pour t'échapper."
		icon.Image = Icons.Get(if hunter then "Player/Skull/Skull 1st Outline" else "Exclusive/Trail/Red Trail 1st Outline")
		Motion.Sway(icon, 4, 2.2)
		root.Visible = true
		anim.Value = 0.6
		TweenService:Create(anim, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 }):Play()
		ctx.Audio.Play("RoundStart")
		task.spawn(function()
			for n = countdown, 1, -1 do
				if token ~= my then return end
				count.Text, countShadow.Text = tostring(n), tostring(n)
				pop(countScale, 1.6)
				ctx.Audio.Play("Countdown")
				task.wait(1)
			end
			if token ~= my then return end
			local go = if hunter then "ATTENDS..." else "GO !"
			count.Text, countShadow.Text = go, go
			pop(countScale, 1.8)
			ctx.Audio.Play("Go")
			ctx.Signals.Fire("Shake", 0.4, 0.2)
			task.wait(0.9)
			if token ~= my then return end
			TweenService:Create(anim, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0.7 }):Play()
			task.wait(0.18)
			if token == my then root.Visible = false end
		end)
	end
	function api.Hide()
		token += 1
		root.Visible = false
	end
	return api
end

return Screens
