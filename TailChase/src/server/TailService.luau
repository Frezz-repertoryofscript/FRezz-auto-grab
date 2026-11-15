--[[
	TailService - queues des participants (attache / retrait / skin équipé).
	La queue est construite par Shared.TailBuilder ; le balancement est animé côté client (EffectsController).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TailBuilder = require(ReplicatedStorage.Shared.TailBuilder)
local DataService = require(script.Parent.DataService)
local ShopService = require(script.Parent.ShopService)

local TailService = {}

function TailService.SkinOf(player: Player): string?
	local d = DataService.Get(player)
	return d and d.Equipped.Tail or nil
end

function TailService.Give(player: Player)
	local char = player.Character
	if not char then return end
	TailBuilder.Attach(char, TailService.SkinOf(player))
end

--- Retire la queue ; retourne le CFrame du 1er segment (pour l'effet "queue qui vole") et le skin.
function TailService.Remove(player: Player): (CFrame?, string?)
	local char = player.Character
	if not char then return nil, nil end
	local tail = char:FindFirstChild("Tail")
	if not tail then return nil, nil end
	local seg = tail:FindFirstChild("Seg1")
	local cf = seg and seg.CFrame
	local skin = tail:GetAttribute("Skin")
	tail:Destroy()
	return cf, skin
end

function TailService.Has(player: Player): boolean
	local char = player.Character
	return char ~= nil and char:FindFirstChild("Tail") ~= nil
end

function TailService.Init()
	-- changement de skin depuis le shop : on remplace la queue si elle est portée
	ShopService.OnEquipped.Event:Connect(function(player: Player, category: string)
		if category == "Tail" and TailService.Has(player) then
			TailService.Give(player)
		end
	end)
end

return TailService
