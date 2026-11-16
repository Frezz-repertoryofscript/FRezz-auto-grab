local B = require("./base")
local M = B.M
local me = B.player("Alice", 1)
local other = B.player("Bob", 2)
B.Players.LocalPlayer = me
me.Character = B.character("Alice")
other.Character = B.character("Bob")
me:SetAttribute("Role", "Lobby")
B.RS:SetAttribute("GameState", "Lobby")
B.RS:SetAttribute("MinPlayers", 2)
local Http = B.services.HttpService
B.RS:SetAttribute("MapCatalog", Http:JSONEncode({ { Id = "ville", Name = "Ville", Description = "d", Icon = "Main/House/Blue House 1st Outline", Gradient = "cyan" },
	{ Id = "neon", Name = "Néon City", Description = "d", Icon = "Main/Lighting/Purple Lighting 1st Outline", Gradient = "magenta" },
	{ Id = "plage", Name = "Plage", Description = "d", Icon = "Nature/Planet/Green Planet 1st Outline", Gradient = "amber" } }))
local Icons0 = B.require(B.RS.CheckUIIcons)
_ = Icons0
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
-- tutoriel (doit s'ouvrir tout seul : TutorialDone absent du profil)
B.pump(2)
local tuto = pg.MenuTuto.Fenetre
print("tuto ouvert auto:", tuto.Visible, "titre:", tuto.Corps.Page.Panneau.Texte.Text)
for i = 1, 3 do tuto.Corps.Suivant.Activated:Fire() end
print("page 4:", tuto.Corps.Page.Panneau.Texte.Text, "bouton:", tuto.Corps.Suivant.Texte.Text, "extra:", tuto.Corps.Extra2:FindFirstChild("Texte") and tuto.Corps.Extra2.Texte.Text)
tuto.Corps.Retour.Activated:Fire()
print("retour -> page 3:", tuto.Corps.Page.Panneau.Texte.Text)
tuto.Corps.Suivant.Activated:Fire(); tuto.Corps.Suivant.Activated:Fire()
B.pump(0.5)
print("tuto fermé:", tuto.Visible == false)
-- admin
me:SetAttribute("IsAdmin", true)
print("tuile admin visible:", pg.MenuGauche.Panneau.Admin.Visible)
M.invokeHandlers.AdminCommand = function(cmd) return { Ok = true, Message = "ok " .. cmd, ShortRound = cmd == "ShortRound" } end
pg.MenuGauche.Panneau.Admin.Activated:Fire()
B.pump(0.5)
print("admin ouvert:", pg.MenuAdmin.Fenetre.Visible, "état:", pg.MenuAdmin.Fenetre.Corps.Panneau.Valeur.Text)
pg.MenuAdmin.Fenetre.Corps.MancheCourte.Activated:Fire()
B.pump(0.1)
print("info admin:", pg.MenuAdmin.Fenetre.Corps.Info.Texte.Text)
pg.MenuAdmin.Fenetre.Corps.Lancer.Activated:Fire()
B.pump(1)
print("admin fermé après LANCER:", pg.MenuAdmin.Fenetre.Visible == false)
-- bouton + de l'argent
pg.HudTailChase.Stats.LigneArgent.EmplacementPlus.BoutonPlus.Activated:Fire()
B.pump(0.5)
print("+ ouvre le shop:", pg.MenuShop.Fenetre.Visible); pg.MenuShop.Basculer:Fire(false); B.pump(0.3)
print("badge shop:", pg.MenuGauche.Panneau.Shop.Nouveau.Visible)
-- vote de map
me:SetAttribute("Ready", true)
B.RS:SetAttribute("GameState", "Intermission"); B.RS:SetAttribute("EndsAt", 1000 + B.now() + 20)
B.RS:SetAttribute("Votes_ville", 0); B.RS:SetAttribute("Votes_neon", 0); B.RS:SetAttribute("Votes_plage", 0)
B.RS:SetAttribute("VoteOptions", Http:JSONEncode({ "ville", "neon", "plage" }))
B.pump(0.5)
local vote = pg.MenuVote.Fenetre
print("vote ouvert auto:", vote.Visible, "tuiles:", vote.Corps.Map_neon ~= nil, "bouton HUD:", pg.HudTailChase.Minuteur.BoutonVote.Visible)
vote.Corps.Map_neon.Bouton.Activated:Fire()
B.RS:SetAttribute("Votes_neon", 2)
B.pump(0.2)
print("après vote:", vote.Corps.Map_neon.Bouton.Texte.Text, vote.Corps.Map_neon.Votes.Text, "couronne:", vote.Corps.Map_neon.Couronne.Visible, vote.Corps.Map_ville.Couronne.Visible)
print("pill:", pg.MenuVote.Fenetre.Minuteur.Texte.Text)
B.RS:SetAttribute("VoteOptions", nil)
B.pump(0.5)
print("vote fermé à la fin:", vote.Visible == false, "bouton HUD caché:", pg.HudTailChase.Minuteur.BoutonVote.Visible == false)
me:SetAttribute("Ready", false)
B.RS:SetAttribute("GameState", "Lobby")
-- lobby : jouer
pg.MenuGauche.Panneau.Jouer.Activated:Fire()
-- manche
B.RS:SetAttribute("GameState", "Countdown")
B.RS:SetAttribute("EndsAt", 1000 + B.now() + 5)
me:SetAttribute("Role", "Runner")
rem.RoleAssigned.OnClientEvent:Fire("Runner", 5)
B.pump(1)
print("menu lobby visible pendant manche:", pg.MenuGauche.Panneau.Visible, "écran rôle:", pg.EcranRole.Ecran.Visible)
B.RS:SetAttribute("GameState", "Round"); B.RS:SetAttribute("MapName", "Néon City")
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
rem.Captured.OnClientEvent:Fire(me, other, "tail_rainbow", "capture_default", M.CFrame.new(0, 3, 1))
B.pump(0.5)
print("bannière:", pg.Recompenses.Banniere.Visible, pg.Recompenses.Banniere.Texte.Text, pg.Recompenses.Banniere.Carte.Nom.Text, pg.Recompenses.Banniere.Carte.Etiquette.Text)
-- résultats
B.RS:SetAttribute("GameState", "Results")
me:SetAttribute("Role", "Lobby")
rem.Results.OnClientEvent:Fire({ Headline = "Bob a survécu !", Mine = { Survival = 83, Tails = 2, LastSurvivor = true, Survived = true,
	Coins = { Survival = 16, Tails = 20, Participation = 25, Bonus = 50, Total = 111 } },
	Rows = { { Name = "Alice", Survival = 83, Tails = 2, Coins = 111, Survived = true }, { Name = "Bob", Survival = 0, Tails = 1, Coins = 35, Survived = false } } })
B.pump(3)
print("résultats pièces:", pg.MenuResultats.Fenetre.Corps:FindFirstChild("CartePIÈCES").Nom.Text, "| détail:", pg.MenuResultats.Fenetre.Corps.Detail.Texte.Text)
B.pump(10)
print("résultats fenêtre visible après 13s:", pg.MenuResultats.Fenetre.Visible, "menu lobby:", pg.MenuGauche.Panneau.Visible)
print("FireServer:")
for _, l in M.LOG do print("  ", l[2], l[3]) end
print("OK client")
