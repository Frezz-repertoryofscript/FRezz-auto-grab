--[[
	LobbyMenu - menu gauche du lobby (archétype du "left menu" de l'exemple 02) :
		bouton large JOUER (vert = confirmer)  ->  devient "PRÊT !" (jaune) ; re-cliquer annule
		tuiles 106x106 : SHOP (rouge) / INVENTAIRE (bleu), badge "!" pulsé sur le shop
	Visible seulement hors manche.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyMenu = {}

function LobbyMenu.Build(ctx)
	local UI, Icons, Motion = ctx.UI, ctx.Icons, ctx.Motion
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local player = Players.LocalPlayer
	local gui = UI.ScreenGui("MenuLobby", 5, { Parent = ctx.PlayerGui, Menu = false })
	local panel = UI.new("Frame", { Name = "Panneau", BackgroundTransparency = 1, Size = UDim2.fromOffset(220, 186),
		Position = UDim2.new(0, 14, 0.5, 20), AnchorPoint = Vector2.new(0, 0.5) }, gui)
	Motion.BindResponsive(UI.new("UIScale", { Name = "WindowScale" }, panel))

	local play = UI.Button(panel, { Name = "Jouer", Theme = "meadow", Size = Vector2.new(220, 64), Position = UDim2.fromOffset(110, 32),
		Text = "JOUER", TextSize = 32, TextThickness = 3.2, Icon = Icons.Get("Item/Target/Target 1st Outline") })
	local shop = UI.Button(panel, { Name = "Shop", Theme = "red", Size = Vector2.new(106, 106), Position = UDim2.fromOffset(53, 129),
		Text = "Shop", IconLayout = "Big", Icon = Icons.Get("Main/Shopping Cart/Red Shopping Cart 1st Outline"), TextSize = 28 })
	local inv = UI.Button(panel, { Name = "Inventaire", Theme = "blue", Size = Vector2.new(106, 106), Position = UDim2.fromOffset(167, 129),
		Text = "Inventaire", IconLayout = "Big", Icon = Icons.Get("Item/Backpack/Backpack 1st Outline"), TextSize = 19 })
	local badge = UI.NotifBadge(shop)
	Motion.PulseScale(badge.Pulse)

	local api = { Gui = gui }

	local function refreshPlay()
		local ready = player:GetAttribute("Ready") == true
		UI.Recolor(play, if ready then "yellow" else "meadow")
		UI.SetButtonText(play, if ready then "PRÊT !" else "JOUER")
	end
	player:GetAttributeChangedSignal("Ready"):Connect(refreshPlay)
	refreshPlay()

	Motion.BindButton(play, 1.04, ctx.Sons, function()
		local ready = not (player:GetAttribute("Ready") == true)
		Remotes.SetReady:FireServer(ready)
		Motion.Float(play, if ready then "En attente des autres joueurs..." else "Annulé", if ready then UI.Colors.FloatSuccess else UI.Colors.FloatWarn)
	end)
	Motion.BindButton(shop, 1.04, ctx.Sons, function()
		badge.Visible = false
		ctx.OpenShop()
	end)
	Motion.BindButton(inv, 1.04, ctx.Sons, function() ctx.OpenInventory() end)

	function api.SetVisible(v: boolean)
		panel.Visible = v -- (pas gui.Enabled : StudMotion.Window restaure Enabled à la fermeture d'un menu)
	end
	return api
end

return LobbyMenu
