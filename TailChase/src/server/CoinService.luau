--[[
	CoinService - calcule et verse les pièces de fin de manche.
		survie        : 1 pièce / Config.Coins.SurvivalSecondsPerCoin secondes
		queues prises : Config.Coins.PerTail par queue
		participation : Config.Coins.Participation
		dernier survivant : Config.Coins.LastSurvivor (survivants à la fin, sinon le dernier capturé)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)

local CoinService = {}

export type Breakdown = { Survival: number, Tails: number, Participation: number, Bonus: number, Total: number }

function CoinService.Compute(survivalSeconds: number, tails: number, lastSurvivor: boolean): Breakdown
	local c = Config.Coins
	local b = {
		Survival = math.floor(math.max(0, survivalSeconds) / c.SurvivalSecondsPerCoin),
		Tails = tails * c.PerTail,
		Participation = c.Participation,
		Bonus = if lastSurvivor then c.LastSurvivor else 0,
		Total = 0,
	}
	b.Total = b.Survival + b.Tails + b.Participation + b.Bonus
	return b
end

--- Verse les pièces et met à jour les stats. Retourne le détail.
function CoinService.Reward(player: Player, survivalSeconds: number, tails: number, lastSurvivor: boolean, survived: boolean): Breakdown
	local b = CoinService.Compute(survivalSeconds, tails, lastSurvivor)
	local d = DataService.Get(player)
	if d then
		d.Stats.Rounds += 1
		d.Stats.TailsTaken += tails
		d.Stats.BestSurvival = math.max(d.Stats.BestSurvival, math.floor(survivalSeconds))
		if survived then d.Stats.Wins += 1 end
		DataService.AddCoins(player, b.Total)
	end
	return b
end

return CoinService
