--[[
	LobbyMenu - menu gauche du lobby, géométrie exacte du "left menu" de référence (screenshot 01 / exemple 02) :
		Frame 220x292 @ (0,14,0.5,0) ; bouton large 220x64 en haut, puis grille 2x2 de tuiles 106x106
		(centres x 53/167, y 125/239), icône énorme qui déborde, gaps 8 px.
		JOUER (vert prairie = confirmer) -> "PRÊT !" (jaune) ; re-cliquer annule
		SHOP (rouge) · INVENTAIRE (bleu) · TUTO (jaune) · ADMIN (violet, seulement si Player.IsAdmin)
	Badges "!" pulsés : Shop quand un item est achetable, Tuto tant que le tutoriel n'est pas terminé.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyMenu = {}

function LobbyMenu.Build(ctx)
	local UI, Icons, Motion = ctx.UI, ctx.Icons, ctx.Motion
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local player = Players.LocalPlayer
	local gui = UI.ScreenGui("MenuGauche", 4, { Parent = ctx.PlayerGui, Menu = false })
	local panel = UI.new("Frame", { Name = "Panneau", BackgroundTransparency = 1, Size = UDim2.fromOffset(220, 292),
		Position = UDim2.new(0, 14, 0.5, 10), AnchorPoint = Vector2.new(0, 0.5) }, gui)
	Motion.BindResponsive(UI.new("UIScale", { Name = "WindowScale" }, panel))

	local play = UI.Button(panel, { Name = "Jouer", Theme = "meadow", Size = Vector2.new(220, 64), Position = UDim2.fromOffset(110, 32),
		Text = "JOUER", TextSize = 32, TextThickness = 3.2, Icon = Icons.Get("Item/Target/Target 1st Outline") })
	local function tile(name, theme, text, icon, x, y, size)
		return UI.Button(panel, { Name = name, Theme = theme, Size = Vector2.new(106, 106), Position = UDim2.fromOffset(x, y),
			Text = text, IconLayout = "Big", Icon = Icons.Get(icon), TextSize = size or 28 })
	end
	local shop = tile("Shop", "red", "Shop", "Main/Shopping Cart/Red Shopping Cart 1st Outline", 53, 125)
	local inv = tile("Inventaire", "blue", "Sac", "Item/Backpack/Backpack 1st Outline", 167, 125)
	local tuto = tile("Tuto", "yellow", "Tuto", "Item/Book/Yellow Book 1st Outline", 53, 239)
	local admin = tile("Admin", "purple", "Admin", "Item/Hammer/Hammer 1st Outline", 167, 239)

	local shopBadge = UI.NotifBadge(shop)
	local tutoBadge = UI.NotifBadge(tuto)
	Motion.PulseScale(shopBadge.Pulse)
	Motion.PulseScale(tutoBadge.Pulse)
	shopBadge.Visible = false
	tutoBadge.Visible = false

	local api = { Gui = gui }

	local function refreshPlay()
		local ready = player:GetAttribute("Ready") == true
		UI.Recolor(play, if ready then "yellow" else "meadow")
		UI.SetButtonText(play, if ready then "PRÊT !" else "JOUER")
	end
	player:GetAttributeChangedSignal("Ready"):Connect(refreshPlay)
	refreshPlay()

	local function refreshAdmin()
		admin.Visible = player:GetAttribute("IsAdmin") == true
	end
	player:GetAttributeChangedSignal("IsAdmin"):Connect(refreshAdmin)
	refreshAdmin()

	Motion.BindButton(play, 1.04, ctx.Sons, function()
		local ready = not (player:GetAttribute("Ready") == true)
		Remotes.SetReady:FireServer(ready)
		Motion.Float(play, if ready then "En attente des autres joueurs..." else "Annulé", if ready then UI.Colors.FloatSuccess else UI.Colors.FloatWarn)
	end)
	Motion.BindButton(shop, 1.04, ctx.Sons, function() ctx.OpenShop() end)
	Motion.BindButton(inv, 1.04, ctx.Sons, function() ctx.OpenInventory() end)
	Motion.BindButton(tuto, 1.04, ctx.Sons, function() ctx.OpenTutorial() end)
	Motion.BindButton(admin, 1.04, ctx.Sons, function() ctx.OpenAdmin() end)

	--- Badges selon le profil : un item non possédé abordable / tutoriel pas fini.
	function api.SetProfile(profile)
		local affordable = false
		for _, item in ctx.Cosmetics.Items do
			if not profile.Owned[item.Id] and item.Price <= profile.Coins then affordable = true break end
		end
		shopBadge.Visible = affordable
		tutoBadge.Visible = profile.TutorialDone ~= true
	end

	function api.SetVisible(v: boolean)
		panel.Visible = v -- (pas gui.Enabled : StudMotion.Window restaure Enabled à la fermeture d'un menu)
	end
	return api
end

return LobbyMenu
