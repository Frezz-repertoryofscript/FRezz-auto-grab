--!strict
--[[
	Cosmetics - catalogue du shop (cosmétiques uniquement, aucun avantage de gameplay).
	Chaque item : Id, Category ("Tail" | "Trail" | "Capture"), Name, Price, Rarity (échelle StudUI), Icon (chemin CheckUIIcons),
	+ les paramètres visuels lus par TailBuilder / EffectsController.
	Pour ajouter un item : ajoute une entrée ici, c'est tout (le shop et l'inventaire sont générés depuis cette liste).
]]

local C3 = Color3.fromRGB

export type Item = {
	Id: string,
	Category: string,
	Name: string,
	Price: number,
	Rarity: string,
	Icon: string,
	Colors: { Color3 }?,
	Material: Enum.Material?,
	Pattern: string?, -- "Solid" | "Stripes" | "Flame" | "Rainbow" | "Gold" | "Neon"
	Color: Color3?,
	Fx: string?,
	Default: boolean?,
}

local Cosmetics = {}

Cosmetics.Categories = {
	{ Id = "Tail", Label = "Queues", Icon = "Exclusive/Trail/Red Trail 1st Outline", Theme = "red" },
	{ Id = "Trail", Label = "Traînées", Icon = "Main/Lighting/Lighting 1st Outline", Theme = "blue" },
	{ Id = "Capture", Label = "Captures", Icon = "Main/Star/Golden Star 1st Outline", Theme = "yellow" },
}

Cosmetics.Items = {
	-- ------------------------------------------------------------------ QUEUES
	{ Id = "tail_classic", Category = "Tail", Name = "Classique", Price = 0, Rarity = "Common", Default = true,
		Icon = "Exclusive/Trail/Red Trail 1st Outline", Pattern = "Solid", Colors = { C3(255, 120, 30) }, Material = Enum.Material.SmoothPlastic },
	{ Id = "tail_striped", Category = "Tail", Name = "Rayée", Price = 250, Rarity = "Uncommon",
		Icon = "Exclusive/Trail/Blue Trail 1st Outline", Pattern = "Stripes", Colors = { C3(255, 255, 255), C3(40, 120, 255) }, Material = Enum.Material.SmoothPlastic },
	{ Id = "tail_flame", Category = "Tail", Name = "Flamme", Price = 600, Rarity = "Rare",
		Icon = "Main/Fire/Fire 1st Outline", Pattern = "Flame", Colors = { C3(255, 230, 60), C3(255, 120, 0), C3(220, 20, 0) }, Material = Enum.Material.Neon },
	{ Id = "tail_rainbow", Category = "Tail", Name = "Arc-en-ciel", Price = 1200, Rarity = "Epic",
		Icon = "Exclusive/Trail/Purple Trail 1st Outline", Pattern = "Rainbow", Colors = { C3(255, 40, 80), C3(255, 150, 0), C3(255, 230, 0), C3(40, 220, 60), C3(0, 190, 255), C3(140, 60, 255) }, Material = Enum.Material.SmoothPlastic },
	{ Id = "tail_gold", Category = "Tail", Name = "Dorée", Price = 2500, Rarity = "Legendary",
		Icon = "Item/Crown/Crown 1st Outline", Pattern = "Gold", Colors = { C3(255, 210, 60), C3(255, 170, 20) }, Material = Enum.Material.Foil },
	{ Id = "tail_neon", Category = "Tail", Name = "Néon", Price = 4000, Rarity = "Mythic",
		Icon = "Main/Lighting/Blue Lighting 1st Outline", Pattern = "Neon", Colors = { C3(0, 255, 230), C3(255, 0, 200) }, Material = Enum.Material.Neon },

	-- ------------------------------------------------------------------ TRAÎNÉES DE DASH
	{ Id = "trail_default", Category = "Trail", Name = "Vent", Price = 0, Rarity = "Common", Default = true,
		Icon = "Exclusive/Trail/Blue Trail 1st Outline", Colors = { C3(255, 255, 255), C3(180, 220, 255) } },
	{ Id = "trail_lime", Category = "Trail", Name = "Éclair vert", Price = 300, Rarity = "Uncommon",
		Icon = "Main/Lighting/Green Lighting 1st Outline", Colors = { C3(200, 255, 60), C3(40, 200, 0) } },
	{ Id = "trail_fire", Category = "Trail", Name = "Brasier", Price = 800, Rarity = "Rare",
		Icon = "Main/Fire/Fire 1st Outline", Colors = { C3(255, 230, 60), C3(255, 40, 0) } },
	{ Id = "trail_galaxy", Category = "Trail", Name = "Galaxie", Price = 1800, Rarity = "Epic",
		Icon = "Main/Lighting/Purple Lighting 1st Outline", Colors = { C3(120, 60, 255), C3(255, 60, 200) } },
	{ Id = "trail_rainbow", Category = "Trail", Name = "Prisme", Price = 3500, Rarity = "Legendary",
		Icon = "Exclusive/Trail/Yellow Trail 1st Outline", Colors = { C3(255, 40, 80), C3(255, 230, 0), C3(0, 200, 255) } },

	-- ------------------------------------------------------------------ EFFETS DE CAPTURE
	{ Id = "capture_default", Category = "Capture", Name = "Pouf", Price = 0, Rarity = "Common", Default = true,
		Icon = "Main/Star/Golden Star 1st Outline", Fx = "Puff", Color = C3(255, 255, 255) },
	{ Id = "capture_stars", Category = "Capture", Name = "Étoiles", Price = 400, Rarity = "Uncommon",
		Icon = "Main/Star/Blue Star 1st Outline", Fx = "Stars", Color = C3(255, 230, 80) },
	{ Id = "capture_hearts", Category = "Capture", Name = "Cœurs", Price = 900, Rarity = "Rare",
		Icon = "Main/Heart/Heart 1st Outline", Fx = "Hearts", Color = C3(255, 80, 140) },
	{ Id = "capture_skull", Category = "Capture", Name = "Crâne", Price = 1600, Rarity = "Epic",
		Icon = "Player/Skull/Skull 1st Outline", Fx = "Skull", Color = C3(170, 90, 255) },
	{ Id = "capture_coins", Category = "Capture", Name = "Jackpot", Price = 3000, Rarity = "Legendary",
		Icon = "Currency/Coin/Golden Coin 1st Outline", Fx = "Coins", Color = C3(255, 200, 40) },
} :: { Item }

Cosmetics.ById = {} :: { [string]: Item }
for _, item in Cosmetics.Items do
	Cosmetics.ById[item.Id] = item
end

function Cosmetics.Get(id: string?): Item?
	if not id then return nil end
	return Cosmetics.ById[id]
end

--- Item par défaut d'une catégorie (gratuit, possédé d'office).
function Cosmetics.DefaultFor(category: string): string
	for _, item in Cosmetics.Items do
		if item.Category == category and item.Default then return item.Id end
	end
	return ""
end

function Cosmetics.ByCategory(category: string): { Item }
	local list = {}
	for _, item in Cosmetics.Items do
		if item.Category == category then table.insert(list, item) end
	end
	table.sort(list, function(a, b) return a.Price < b.Price end)
	return list
end

return Cosmetics
