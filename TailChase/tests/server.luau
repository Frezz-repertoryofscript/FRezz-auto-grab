local B = require("./base")
local M = B.M
local captured, results, notifs, roles = 0, 0, {}, {}
local rem = B.RS.Remotes
rem.Captured.FireAllClients = function(_, h, r) captured += 1; print("CAPTURE", h.Name, "->", r.Name) end
rem.Results.FireClient = function(_, p, data) results += 1; print("RESULTS", p.Name, "coins", data.Mine.Coins.Total, "survie", math.floor(data.Mine.Survival), "queues", data.Mine.Tails, data.Headline) end
rem.Notify.FireAllClients = function(_, t) table.insert(notifs, t) end
rem.RoleAssigned.FireClient = function(_, p, role) roles[p.Name] = role end

local a = B.player("Alice", 1)
local b = B.player("Bob", 2)
local c = B.player("Carl", 3)
for _, p in { a, b, c } do p.Character = B.character(p.Name) end

B.run(B.SSS.GameManager)
B.pump(1)
local map = B.workspace:FindFirstChild("Map")
local lobby = B.workspace:FindFirstChild("Lobby")
print("Map:", map ~= nil, "Lobby:", lobby ~= nil, "instances:", M.count.total, "parts:", M.count.Part, "textures:", M.count.Texture)
print("Spawns map:", #map.Spawns:GetChildren(), "lobby:", #lobby.Spawns:GetChildren())
print("Tail Alice:", a.Character:FindFirstChild("Tail") ~= nil, "role", a:GetAttribute("Role"))
print("State:", B.RS:GetAttribute("GameState"))

-- Bob et Carl loin d'Alice (Bob sera capturé s'il est chasseur ou proie, selon tirage) ; on met tout le monde au même endroit
for _, p in { a, b, c } do p:SetAttribute("Ready", true) end
B.pump(2)
print("State après ready:", B.RS:GetAttribute("GameState"))
B.pump(21)
print("State:", B.RS:GetAttribute("GameState"), "roles:", roles.Alice, roles.Bob, roles.Carl)
B.pump(5.5)
print("State:", B.RS:GetAttribute("GameState"), "frozen alice", a:GetAttribute("Frozen"))
B.pump(4)
print("captures:", captured, "runnersLeft", B.RS:GetAttribute("RunnersLeft"))
-- shop : achat
local Shop = B.require(B.SSS.ShopService)
local r1 = Shop.Purchase(a, "tail_striped")
print("achat rayée (100 pièces de départ):", r1.Ok, r1.Message)
local Data = B.require(B.SSS.DataService)
Data.AddCoins(a, 1000)
local r2 = Shop.Purchase(a, "tail_striped")
print("achat rayée après +1000:", r2.Ok, r2.Message, "coins", Data.Get(a).Coins, "equip", Data.Get(a).Equipped.Tail)
local r3 = Shop.Equip(a, "tail_classic")
print("équipe classique:", r3.Ok, r3.Message)
B.pump(200)
print("State fin:", B.RS:GetAttribute("GameState"), "results envoyés:", results, "role Alice:", a:GetAttribute("Role"))
print("notifs:", table.concat(notifs, " | "))
B.pump(15)
print("State:", B.RS:GetAttribute("GameState"))

-- ===== admin : lancement immédiat en SOLO (Bob et Carl partent)
b.Parent = nil; c.Parent = nil
for _, p in { a } do p:SetAttribute("Ready", false) end
B.pump(40)
print("Solo, état (doit rester Lobby sans admin):", B.RS:GetAttribute("GameState"), "IsAdmin:", a:GetAttribute("IsAdmin"))
local inv = rem.AdminCommand.OnServerInvoke
print("cmd End hors manche:", inv(a, "End").Message)
print("cmd ShortRound:", inv(a, "ShortRound").Message)
print("cmd Start:", inv(a, "Start").Message)
B.pump(2)
print("après Start:", B.RS:GetAttribute("GameState"), "role", a:GetAttribute("Role"))
B.pump(6)
print("manche:", B.RS:GetAttribute("GameState"), "durée restante ~", math.floor(B.RS:GetAttribute("EndsAt") - 1000 - B.now()))
print("cmd Start pendant manche:", inv(a, "Start").Message)
print("cmd End:", inv(a, "End").Message)
B.pump(1)
print("après End:", B.RS:GetAttribute("GameState"), "role", a:GetAttribute("Role"))
print("cmd Coins:", inv(a, "Coins").Message, "coins", Data.Get(a).Coins)
rem.TutorialDone.OnServerEvent:Fire(a)
print("TutorialDone:", Data.Get(a).TutorialDone, "| ResetTuto:", inv(a, "ResetTuto").Message, Data.Get(a).TutorialDone)
