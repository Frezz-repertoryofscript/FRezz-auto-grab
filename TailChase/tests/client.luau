local B = require("./base")
local M = B.M
local me = B.player("Alice", 1)
local other = B.player("Bob", 2)
B.Players.LocalPlayer = me
me.Character = B.character("Alice")
other.Character = B.character("Bob")
me:SetAttribute("Role", "Lobby")
B.RS:SetAttribute("GameState", "Lobby")
B.RS:SetAttribute("MinPlayers", 4)
-- queue sur Bob (construite par le TailBuilder partagé)
local TB = B.require(B.RS.Shared.TailBuilder)
TB.Attach(other.Character, "tail_rainbow")
local profile = { Coins = 1234, Owned = { tail_classic = true, trail_default = true, capture_default = true, tail_flame = true },
	Equipped = { Tail = "tail_classic", Trail = "trail_default", Capture = "capture_default" }, Stats = { Rounds = 0, TailsTaken = 0 } }
M.invokeHandlers.GetProfile = function() return profile end
M.invokeHandlers.ShopPurchase = function(id) return { Ok = false, Message = "Pas assez de pièces", Profile = profile } end
M.invokeHandlers.ShopEquip = function(id) profile.Equipped.Tail = id; return { Ok = true, Message = "Équipé !", Profile = profile } end

for _, n in { "MovementController", "AnimationController", "EffectsController", "UIController" } do
	B.run(B.SPS[n]); print("lancé", n)
end
B.pump(0.5)
local pg = me.PlayerGui
local names = {}
for _, g in pg:GetChildren() do table.insert(names, g.Name) end
print("ScreenGuis:", table.concat(names, ", "))
print("instances:", M.count.total)
local rem = B.RS.Remotes
rem.DataUpdated.OnClientEvent:Fire(profile)
rem.Notify.OnClientEvent:Fire("Bob est devenu chasseur !", "hunter")
rem.Notify.OnClientEvent:Fire("Tu as pris une queue ! +10", "success")
-- shop : clic sur un bouton d'achat / équiper
local shop = pg.MenuShop
shop.Basculer:Fire(true)
B.pump(0.5)
local cell = shop.Fenetre.Corps.Liste:FindFirstChild("Cellule_tail_neon")
print("cellule neon visible:", cell.Visible, "bouton:", cell.Action.Texte and cell.Action.Texte.Text)
cell.Action.Activated:Fire()
local flame = shop.Fenetre.Corps.Liste:FindFirstChild("Cellule_tail_flame")
print("flame bouton:", flame.Action.Name, flame.Action:GetAttribute("Theme"))
flame.Action.Activated:Fire()
B.pump(0.5)
print("flame après équipe:", flame.Action:GetAttribute("Theme"))
shop.Fenetre.Onglets.Onglet_Trail.Activated:Fire()
print("tail cell visible après onglet Trail:", cell.Visible, "trail cell:", shop.Fenetre.Corps.Liste.Cellule_trail_fire.Visible)
shop.Basculer:Fire(false)
local inv = pg.MenuInventaire
local invNeon = inv.Fenetre.Corps.Liste.Cellule_tail_neon
print("inventaire: neon visible (non possédé):", invNeon.Visible, "flame visible:", inv.Fenetre.Corps.Liste.Cellule_tail_flame.Visible)
-- lobby : jouer
pg.MenuLobby.Panneau.Jouer.Activated:Fire()
-- manche
B.RS:SetAttribute("GameState", "Countdown")
B.RS:SetAttribute("EndsAt", 1000 + B.now() + 5)
me:SetAttribute("Role", "Runner")
rem.RoleAssigned.OnClientEvent:Fire("Runner", 5)
B.pump(1)
print("menu lobby visible pendant manche:", pg.MenuLobby.Panneau.Visible, "écran rôle:", pg.EcranRole.Ecran.Visible)
B.RS:SetAttribute("GameState", "Round")
B.RS:SetAttribute("EndsAt", 1000 + B.now() + 180)
B.RS:SetAttribute("HuntersReleaseAt", 1000 + B.now() + 3)
B.RS:SetAttribute("RunnersLeft", 3)
B.pump(6)
print("timer:", pg.HudTailChase.Minuteur.Boite.Texte.Text, "sous:", pg.HudTailChase.Minuteur.Sous.Text)
-- dash + slide
B.actions.TC_Dash("TC_Dash", M.Enum.UserInputState.Begin)
B.pump(0.1)
print("dash bar:", pg.HudTailChase.Dash.BarreDash.Valeur.Text)
B.actions.TC_Slide("TC_Slide", M.Enum.UserInputState.Begin)
B.pump(0.3)
me.Character:SetAttribute("Sliding", true)
me.Character:SetAttribute("Dashing", true)
B.pump(1.5)
me.Character:SetAttribute("Sliding", false)
-- mobile
pg.HudTailChase.Mobile.BoutonDash.Activated:Fire()
-- capture
rem.Captured.OnClientEvent:Fire(other, me, "tail_classic", "capture_hearts", M.CFrame.new(0, 3, 1))
other:SetAttribute("TailsTaken", 1)
B.pump(1)
-- résultats
B.RS:SetAttribute("GameState", "Results")
me:SetAttribute("Role", "Lobby")
rem.Results.OnClientEvent:Fire({ Headline = "Bob a survécu !", Mine = { Survival = 83, Tails = 2, LastSurvivor = true, Survived = true,
	Coins = { Survival = 16, Tails = 20, Participation = 25, Bonus = 50, Total = 111 } },
	Rows = { { Name = "Alice", Survival = 83, Tails = 2, Coins = 111, Survived = true }, { Name = "Bob", Survival = 0, Tails = 1, Coins = 35, Survived = false } } })
B.pump(3)
print("résultats pièces:", pg.MenuResultats.Fenetre.Corps:FindFirstChild("CartePIÈCES").Nom.Text, "| détail:", pg.MenuResultats.Fenetre.Corps.Detail.Texte.Text)
B.pump(10)
print("résultats fenêtre visible après 13s:", pg.MenuResultats.Fenetre.Visible, "menu lobby:", pg.MenuLobby.Panneau.Visible)
print("FireServer:")
for _, l in M.LOG do print("  ", l[2], l[3]) end
print("OK client")
