--[[
	AdminPanel - fenêtre "Admin" (archétype D "upgrade / prestige" du kit : en-tête violet, 2 stud panels d'état,
	boîte d'info, gros CTA en ligne, rangée de petites actions).
		LANCER (vert, confirmer)   TERMINER (rouge, détruire)
		TOUS PRÊTS (bleu)  +1000 (vert argent)  MANCHE 60s (violet, bascule)  REVOIR TUTO (gris)
	Les commandes sont validées côté serveur (AdminService) ; la tuile n'apparaît que si Player.IsAdmin.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminPanel = {}
local RGB = Color3.fromRGB

function AdminPanel.Build(ctx)
	local UI, Icons, Motion, Config = ctx.UI, ctx.Icons, ctx.Motion, ctx.Config
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local gui = UI.ScreenGui("MenuAdmin", 11, { Parent = ctx.PlayerGui })
	Motion.CreateSounds(gui.Sons)
	local win = UI.Window(gui, { Size = Vector2.new(600, 452), Title = "Admin", Header = "purple",
		Icon = Icons.Get("Item/Hammer/Hammer 1st Outline") })
	local body = win.Corps
	UI.Pill(win.Fenetre, '<font color="#FFD23F">Panneau de contrôle</font>', { Width = 240, Position = UDim2.new(0.5, 0, 0, win.HeaderHeight), ZIndex = 20 })

	-- ------------------------------------------------------------ état
	local function statPanel(x, grad, title, icon)
		local p = UI.StudPanel(body, { Size = UDim2.fromOffset(270, 104), Position = UDim2.fromOffset(x, 22), Gradient = grad, ZIndex = 3 })
		UI.Text(p, title, { Name = "Titre", Size = UDim2.new(1, -90, 0, 26), Position = UDim2.new(0, 90, 0, 24), AnchorPoint = Vector2.new(0, 0.5),
			AlignX = Enum.TextXAlignment.Left, Max = 22, Thickness = 2.6, ZIndex = 7 })
		local v, vs = UI.ShadowText(p, "-", { Name = "Valeur", Size = UDim2.new(1, -96, 0, 50), Position = UDim2.new(0, 90, 0, 66), AnchorPoint = Vector2.new(0, 0.5),
			AlignX = Enum.TextXAlignment.Left, Max = 40, Thickness = 3.2, ZIndex = 7 })
		UI.Image(p, Icons.Get(icon), { Size = UDim2.fromOffset(84, 84), Position = UDim2.fromOffset(44, 50), Rotation = -10, ZIndex = 9 })
		return v, vs
	end
	local stateText, stateShadow = statPanel(16, "cyan", "ÉTAT", "Item/Clock/Golden Clock 1st Outline")
	local playersText, playersShadow = statPanel(309, "violet", "JOUEURS PRÊTS", "Player/4 Players/4 Players 1st Outline")

	local info = UI.InsetBox(body, { Name = "Info", Size = UDim2.fromOffset(563, 64), Position = UDim2.fromOffset(16, 140) })
	local infoText = UI.Text(info, "", { Size = UDim2.new(1, -24, 1, -10), Max = 18, Rich = true, Font = "Bold",
		Color = RGB(220, 235, 245), Thickness = 2.2, ZIndex = 6 })

	-- ------------------------------------------------------------ actions
	local actions = {}
	local function action(name, cmd, p)
		p.Name = name
		local b = UI.Button(body, p)
		actions[cmd] = b
		Motion.BindButton(b, 1.04, gui.Sons, function()
			local ok, res = pcall(Remotes.AdminCommand.InvokeServer, Remotes.AdminCommand, cmd)
			if ok and res and res.Ok then
				Motion.Play(gui.Sons, "Achat", 1.2)
				Motion.Float(b, res.Message, UI.Colors.FloatSuccess)
				if cmd == "Start" then task.delay(0.6, function() ctx.CloseAll() end) end
			else
				Motion.Play(gui.Sons, "Refus")
				Motion.Shake(b)
				Motion.Float(b, if ok and res then res.Message else "Erreur", UI.Colors.FloatError)
			end
			if ok and res and res.ShortRound ~= nil then
				ctx.AdminShortRound = res.ShortRound
			end
		end)
		return b
	end
	action("Lancer", "Start", { Theme = "green", Size = Vector2.new(270, 74), Position = UDim2.fromOffset(151, 254),
		Text = "LANCER", TextSize = 38, Icon = Icons.Get("Item/Rocket/Rocket 1st Outline") })
	action("Terminer", "End", { Theme = "red", Size = Vector2.new(270, 74), Position = UDim2.fromOffset(444, 254),
		Text = "TERMINER", TextSize = 34, Icon = Icons.Get("UI/Skip/Skip 1st Outline") })
	local small = {
		{ "TousPrets", "AllReady", "blue", "TOUS PRÊTS", "Player/Add Player/Add Player 1st Outline" },
		{ "Pieces", "Coins", "green", "+" .. Config.AdminCoinsGift, "Currency/Coin/Golden Coin 1st Outline" },
		{ "MancheCourte", "ShortRound", "purple", "MANCHE " .. Config.AdminShortRoundTime .. "s", "Item/Clock/Clock 1st Outline" },
		{ "RevoirTuto", "ResetTuto", "gray", "TUTO", "Item/Book/Yellow Book 1st Outline" },
	}
	for i, a in small do
		action(a[1], a[2], { Theme = a[3], Size = Vector2.new(134, 54), Position = UDim2.fromOffset(83 + (i - 1) * 144, 330),
			Text = a[4], TextSize = 19, Icon = Icons.Get(a[5]), IconSize = 0.8 })
	end

	local menu = Motion.Window(gui, win.Fenetre, { Keep = { Notifications = true, Recompenses = true } })
	local api = { Gui = gui, Menu = menu }

	local LABEL = { Lobby = "ATTENTE", Intermission = "INTERMISSION", Countdown = "DÉCOMPTE", Round = "MANCHE", Results = "RÉSULTATS" }
	function api.Update()
		if not menu.IsOpen then return end
		local st = ReplicatedStorage:GetAttribute("GameState") or "Lobby"
		local left = math.max(0, (ReplicatedStorage:GetAttribute("EndsAt") or 0) - workspace:GetServerTimeNow())
		local s = (LABEL[st] or st) .. (if st ~= "Lobby" then "  " .. Motion.Duration(math.ceil(left)) else "")
		stateText.Text, stateShadow.Text = s, s
		local ready = ReplicatedStorage:GetAttribute("ReadyCount") or 0
		local p = ("%d / %d"):format(ready, #game:GetService("Players"):GetPlayers())
		playersText.Text, playersShadow.Text = p, p
		local short = ctx.AdminShortRound == true
		infoText.Text = ('LANCER saute l\'intermission (seul : manche <font color="#FFD23F">sans chasseur</font> pour tester).\nDurée des manches : <font color="#FFD23F">%d s</font>   ·   Minimum normal : <font color="#FFD23F">%d joueurs</font>')
			:format(if short then Config.AdminShortRoundTime else Config.RoundTime, ReplicatedStorage:GetAttribute("MinPlayers") or Config.MinPlayers)
		local inRound = st == "Round" or st == "Countdown"
		UI.SetDisabled(actions.Start, inRound)
		UI.SetDisabled(actions.End, not inRound)
	end

	function api.Open() menu.Open(); api.Update() end
	function api.Close() menu.Close() end
	return api
end

return AdminPanel
