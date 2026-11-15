--[[
	ShopService - achats et équipement des cosmétiques (validés côté serveur).
	RemoteFunctions :
		ShopPurchase(itemId) -> { Ok, Message, Profile }
		ShopEquip(itemId)    -> { Ok, Message, Profile }

	Points d'extension monétisation (non implémentés) :
		ShopService.GrantProduct(player, productId)  à appeler depuis MarketplaceService.ProcessReceipt
		ShopService.HasGamepass(player, passId)      à brancher sur UserOwnsGamePassAsync
	Les IDs se déclarent dans Config.Monetization.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local ShopService = {}
ShopService.OnEquipped = Instance.new("BindableEvent") -- (player, category, itemId) -> TailService rafraîchit la queue

local busy: { [Player]: boolean } = {}

local function result(ok: boolean, msg: string, player: Player)
	return { Ok = ok, Message = msg, Profile = DataService.Snapshot(player) }
end

function ShopService.Purchase(player: Player, itemId: any)
	if typeof(itemId) ~= "string" then return result(false, "Item invalide", player) end
	local item = Cosmetics.Get(itemId)
	local d = DataService.Get(player)
	if not item or not d then return result(false, "Item introuvable", player) end
	if d.Owned[itemId] then return result(false, "Déjà possédé", player) end
	if busy[player] then return result(false, "Patiente...", player) end
	if d.Coins < item.Price then return result(false, "Pas assez de pièces", player) end
	busy[player] = true
	d.Coins -= item.Price
	d.Owned[itemId] = true
	d.Equipped[item.Category] = itemId -- on équipe directement ce qu'on vient d'acheter
	busy[player] = nil
	DataService.Push(player)
	ShopService.OnEquipped:Fire(player, item.Category, itemId)
	return result(true, "Acheté !", player)
end

function ShopService.Equip(player: Player, itemId: any)
	if typeof(itemId) ~= "string" then return result(false, "Item invalide", player) end
	local item = Cosmetics.Get(itemId)
	local d = DataService.Get(player)
	if not item or not d then return result(false, "Item introuvable", player) end
	if not d.Owned[itemId] then return result(false, "Pas encore acheté", player) end
	d.Equipped[item.Category] = itemId
	DataService.Push(player)
	ShopService.OnEquipped:Fire(player, item.Category, itemId)
	return result(true, "Équipé !", player)
end

--- EXTENSION : produit développeur acheté (Robux). Retourne true si le produit a été accordé.
function ShopService.GrantProduct(player: Player, productId: number): boolean
	local def = Config.Monetization.DeveloperProducts[productId]
	if not def then return false end
	-- TODO quand les produits existeront :
	-- if def.Kind == "Coins" then DataService.AddCoins(player, def.Amount) return true end
	return false
end

--- EXTENSION : possession d'un gamepass (non branché).
function ShopService.HasGamepass(_player: Player, _passId: number): boolean
	return false
end

function ShopService.Init()
	Remotes.ShopPurchase.OnServerInvoke = ShopService.Purchase
	Remotes.ShopEquip.OnServerInvoke = ShopService.Equip
	-- MarketplaceService.ProcessReceipt = function(receipt) ... ShopService.GrantProduct(...) end  (à activer plus tard)
end

return ShopService
