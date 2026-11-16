--[[
	Map "Château" - cour pavée entourée de remparts praticables (Y=13) avec créneaux, 4 tours d'angle (Y=22),
	donjon central (Y=20) traversé par un tunnel de slide, poternes de slide dans chaque rempart, douves et ponts.
	Boucle haute : le chemin de ronde fait tout le tour ; rampes intérieures + jump pads vers les tours et le donjon.
]]
local Chateau = { Id = "chateau", Name = "Château", Order = 3, Clock = 17.4, Gradient = "violet",
	Icon = "Item/Shield/Shield 1st Outline", Description = "Remparts, donjon et douves" }

function Chateau.Build(H, map, spawns)
	local RGB, V3, CF = H.RGB, H.V3, H.CF
	local part, block, pillar = H.part, H.block, H.pillar
	local STONE, DARK, GRASS, WOOD, BANNER = RGB(165, 165, 180), RGB(110, 112, 128), RGB(110, 190, 80), RGB(150, 100, 60), RGB(220, 40, 60)
	local W, T, WH = 70, 6, 13 -- demi-taille intérieure+épaisseur, épaisseur, hauteur des remparts
	H.arena(map, 120, GRASS, RGB(90, 150, 70), RGB(255, 200, 80), 30)
	local z = H.folder(map, "Chateau")

	-- cour pavée
	part(z, V3(2 * (W - T / 2), 0.1, 2 * (W - T / 2)), CF(0, 0.05, 0), RGB(200, 195, 180), { Name = "Paves", Sides = false })

	-- remparts : morceaux + poternes de slide + porte centrale (linteau)
	local inner, outer = W - T / 2, W + T / 2 -- 67, 73
	local c = W                                -- axe du mur
	local function wallSide(alongX: boolean, sign: number)
		local lo, hi = if alongX then -outer else -inner, if alongX then outer else inner
		local segs = { { lo, -45 }, { -35, -6 }, { 6, 35 }, { 45, hi } }
		for _, sg in segs do
			local mid, len = (sg[1] + sg[2]) / 2, sg[2] - sg[1]
			if alongX then block(z, mid, sign * c, len, WH, T, STONE, 0, { Name = "Rempart" })
			else block(z, sign * c, mid, T, WH, len, STONE, 0, { Name = "Rempart" }) end
		end
		for _, m in { -40, 40 } do
			local pos = if alongX then V3(m, 0, sign * c) else V3(sign * c, 0, m)
			H.slideBlock(z, pos, T, 10, WH, DARK, if alongX then "Z" else "X")
		end
		-- porte : linteau au-dessus d'une ouverture de 9 de haut
		if alongX then block(z, 0, sign * c, 12, WH - 9, T, DARK, 9, { Name = "Linteau" })
		else block(z, sign * c, 0, T, WH - 9, 12, DARK, 9, { Name = "Linteau" }) end
		-- créneaux côté extérieur (hors zones des tours)
		for k = -42, 42, 6 do
			local o = sign * (outer - 1)
			if alongX then block(z, k, o, 2, 1.6, 2, STONE, WH, { Name = "Creneau" })
			else block(z, o, k, 2, 1.6, 2, STONE, WH, { Name = "Creneau" }) end
		end
		-- bannières côté cour
		for _, m in { -12, 12 } do
			local face = sign * (inner - 0.15)
			if alongX then part(z, V3(4, 7, 0.2), CF(m, 7, face), BANNER, { Name = "Banniere", CanCollide = false, NoStuds = true })
			else part(z, V3(0.2, 7, 4), CF(face, 7, m), BANNER, { Name = "Banniere", CanCollide = false, NoStuds = true }) end
		end
	end
	wallSide(true, -1); wallSide(true, 1); wallSide(false, -1); wallSide(false, 1)

	-- tours d'angle (cylindres Y=22) + jump pads sur le chemin de ronde
	for _, s in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		pillar(z, s[1] * W, s[2] * W, 22, 9, STONE, 0)
		H.neonStrip(z, V3(0.6, 0.6, 0.6), CF(s[1] * W, 32, s[2] * W), RGB(255, 200, 80))
		pillar(z, s[1] * W, s[2] * W, 9, 0.25, WOOD, 22)
		part(z, V3(0.2, 3, 5), CF(s[1] * W, 29.5, s[2] * W + 2.6), BANNER, { Name = "Drapeau", CanCollide = false, NoStuds = true })
		H.jumpPad(z, V3(s[1] * 53, WH, s[2] * W), 88, V3(s[1] * 12, 0, 0))
	end

	-- rampes intérieures vers le chemin de ronde (collées à la face intérieure)
	local r = inner - 2.5
	H.slab(z, V3(20, 0.1, -r), V3(42, WH, -r), 5, WOOD, 1, "Escalier")
	H.slab(z, V3(r, 0.1, 20), V3(r, WH, 42), 5, WOOD, 1, "Escalier")
	H.slab(z, V3(-20, 0.1, r), V3(-42, WH, r), 5, WOOD, 1, "Escalier")
	H.slab(z, V3(-r, 0.1, -20), V3(-r, WH, -42), 5, WOOD, 1, "Escalier")

	-- donjon (Y=20) coupé en deux par un tunnel de slide Est-Ouest
	block(z, 0, -9, 30, 20, 12, STONE, 0, { Name = "Donjon" })
	block(z, 0, 9, 30, 20, 12, STONE, 0, { Name = "Donjon" })
	H.slideBlock(z, V3(0, 0, 0), 30, 6, 20, DARK, "X")
	pillar(z, 0, 12, 10, 0.25, WOOD, 20)
	part(z, V3(0.2, 3.5, 6), CF(0, 28, 15.1), RGB(255, 210, 60), { Name = "Etendard", CanCollide = false, NoStuds = true })
	H.jumpPad(z, V3(0, 0.1, 30), 112, V3(0, 0, -14))
	H.jumpPad(z, V3(0, 0.1, -30), 112, V3(0, 0, 14))

	-- cour : puits, étals, bottes de foin, mannequins
	pillar(z, 38, 38, 2.4, 3.2, STONE, 0.1)
	part(z, V3(0.2, 5.6, 5.6), CF(38, 2.6, 38) * CFrame.Angles(0, 0, math.rad(90)), RGB(60, 150, 230),
		{ Name = "Eau", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Glass, NoStuds = true })
	for i, p in { { -38, 38 }, { 38, -38 } } do
		block(z, p[1], p[2], 10, 3, 4, WOOD, 0.1, { Name = "Etal" })
		for k = 0, 4 do
			block(z, p[1] - 4 + k * 2, p[2] + 2.5, 2, 0.5, 6, if (k + i) % 2 == 0 then BANNER else RGB(250, 250, 250), 7, { Name = "Auvent" })
		end
		pillar(z, p[1] - 4.5, p[2] + 5, 7, 0.2, WOOD, 0.1)
		pillar(z, p[1] + 4.5, p[2] + 5, 7, 0.2, WOOD, 0.1)
	end
	for _, p in { { -45, -20 }, { 46, 18 }, { -20, 48 }, { 24, -50 } } do
		block(z, p[1], p[2], 4, 2.5, 3, RGB(230, 200, 90), 0.1, { Name = "Foin" })
	end
	for _, p in { { -30, -30 }, { 30, 30 } } do
		pillar(z, p[1], p[2], 4, 0.3, WOOD, 0.1)
		block(z, p[1], p[2], 2.4, 2.4, 1, RGB(200, 160, 110), 3, { Name = "Mannequin" })
	end
	for _, p in { { -55, -55 }, { 55, -55 }, { -55, 55 }, { 55, 55 }, { -15, -40 }, { 15, 40 } } do
		H.lamp(z, p[1], p[2], 0.1, RGB(255, 160, 70))
	end

	-- douves (eau peu profonde) + ponts devant les portes
	local m1, m2 = 82, 94
	local moat = { { 0, -(m1 + m2) / 2, 2 * m2, m2 - m1 }, { 0, (m1 + m2) / 2, 2 * m2, m2 - m1 },
		{ -(m1 + m2) / 2, 0, m2 - m1, 2 * m1 }, { (m1 + m2) / 2, 0, m2 - m1, 2 * m1 } }
	for _, w in moat do
		part(z, V3(w[3], 0.2, w[4]), CF(w[1], 0.1, w[2]), RGB(50, 140, 220), { Name = "Douves", Material = Enum.Material.Glass, Transparency = 0.15 })
	end
	block(z, 0, -(m1 + m2) / 2, 12, 0.6, m2 - m1 + 4, WOOD, 0, { Name = "Pont" })
	block(z, 0, (m1 + m2) / 2, 12, 0.6, m2 - m1 + 4, WOOD, 0, { Name = "Pont" })
	block(z, -(m1 + m2) / 2, 0, m2 - m1 + 4, 0.6, 12, WOOD, 0, { Name = "Pont" })
	block(z, (m1 + m2) / 2, 0, m2 - m1 + 4, 0.6, 12, WOOD, 0, { Name = "Pont" })

	-- extérieur : arbres + camp
	for _, p in { { -105, -105 }, { 105, -105 }, { -105, 105 }, { 105, 105 }, { -105, 40 }, { 105, -40 }, { 40, 105 }, { -40, -105 } } do
		H.tree(z, p[1], p[2], 1.1, 0)
	end

	for _, p in { { -30, 15 }, { 30, -15 }, { -45, 45 }, { 45, -45 }, { 20, 55 }, { -20, -55 }, { 55, 20 }, { -55, -20 },
		{ 0, 105 }, { 0, -105 }, { 105, 0 }, { -105, 0 }, { 100, 60 }, { -100, -60 } } do
		H.spawnPoint(spawns, V3(p[1], 0.1, p[2]))
	end
end

return Chateau
