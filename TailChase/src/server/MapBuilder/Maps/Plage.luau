--[[
	Map "Plage tropicale" - sable chaud, mer turquoise, paillotes sur pilotis reliées par des ponts de corde (Y=14),
	bar central surélevé, rochers percés de tunnels de slide, ponton, tour de surveillance, jump pads.
	Boucle haute : bar central <-> 4 paillotes, paillotes Nord reliées par la cabane du phare.
]]
local Plage = { Id = "plage", Name = "Plage", Order = 2, Clock = 13.5, Gradient = "amber",
	Icon = "Nature/Planet/Green Planet 1st Outline", Description = "Paillotes, rochers et ponton" }

function Plage.Build(H, map, spawns)
	local RGB, V3, CF = H.RGB, H.V3, H.CF
	local part, block, slab, pillar = H.part, H.block, H.slab, H.pillar
	local SAND, WATER, WOOD, STRAW, ROCK = RGB(240, 216, 160), RGB(40, 180, 235), RGB(170, 110, 60), RGB(235, 200, 110), RGB(150, 145, 140)
	local HH = 14
	H.arena(map, 120, SAND, RGB(80, 200, 220), RGB(255, 120, 200), 30)
	local z = H.folder(map, "Plage")

	-- mer (au Nord) : eau peu profonde praticable + écume
	part(z, V3(240, 0.3, 50), CF(0, 0.15, -95), WATER, { Name = "Mer", Material = Enum.Material.Glass, Transparency = 0.2 })
	part(z, V3(240, 0.1, 3), CF(0, 0.05, -68.5), RGB(250, 250, 255), { Name = "Ecume", NoStuds = true })

	-- ponton vers le large
	block(z, 0, -92, 8, 1, 40, WOOD, 2, { Name = "Ponton" })
	for _, pz in { -76, -92, -108 } do
		for _, px in { -3.5, 3.5 } do pillar(z, px, pz, 2, 0.5, RGB(120, 80, 40), 0) end
	end
	H.slab(z, V3(0, 0, -64), V3(0, 3, -72), 8, WOOD, 1, "RampePonton")
	H.jumpPad(z, V3(0, 3, -108), 95, V3(0, 0, 18))

	-- plateformes surélevées (paillotes) + bar central
	local function platform(x, zz, size, name, roof)
		local m = Instance.new("Model"); m.Name = name; m.Parent = z
		part(m, V3(size, 1, size), CF(x, HH - 0.5, zz), WOOD, { Name = "Plancher", Sides = false })
		for _, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
			pillar(m, x + c[1] * (size / 2 - 1), zz + c[2] * (size / 2 - 1), HH - 1, 0.6, RGB(120, 80, 40), 0)
		end
		if roof then
			-- cabane au centre (on fait le tour par le plancher) + toit de paille
			block(m, x, zz, size - 8, 7, size - 8, RGB(200, 150, 90), HH, { Name = "Cabane" })
			block(m, x, zz, size - 6, 1.2, size - 6, STRAW, HH + 7, { Name = "Paille" })
			block(m, x, zz, size - 10, 1, size - 10, STRAW:Lerp(RGB(200, 160, 60), 0.4), HH + 8.2, { Name = "PailleHaut" })
		end
		return m
	end
	platform(0, 10, 26, "Bar", false)
	block(z, 0, 10, 8, 1.2, 3, RGB(255, 90, 120), HH, { Name = "Comptoir" })
	local huts = { { -62, -30 }, { 62, -30 }, { 78, 52 }, { -78, 52 } }
	for i, h in huts do platform(h[1], h[2], 20, "Paillote" .. i, true) end
	platform(0, 88, 18, "CabanePhare", true)
	-- ponts de corde (Y = 14)
	local function rope(a, b) H.slab(z, a, b, 4, RGB(205, 160, 100), 0.6, "PontDeCorde") end
	rope(V3(-13, HH, 4), V3(-52, HH, -24))
	rope(V3(13, HH, 4), V3(52, HH, -24))
	rope(V3(13, HH, 18), V3(68, HH, 46))
	rope(V3(-13, HH, 18), V3(-68, HH, 46))
	rope(V3(68, HH, 60), V3(9, HH, 84))
	rope(V3(-68, HH, 60), V3(-9, HH, 84))
	-- accès depuis le sable
	H.slab(z, V3(0, 0, 48), V3(0, HH, 23.5), 6, WOOD, 1, "EscalierBar")
	H.slab(z, V3(-30, 0, 10), V3(-13.5, HH, 10), 5, WOOD, 1, "EscalierBar")
	H.jumpPad(z, V3(-62, 0, -46), 80, V3(0, 0, 10))
	H.jumpPad(z, V3(62, 0, -46), 80, V3(0, 0, 10))
	H.jumpPad(z, V3(78, 0, 70), 80, V3(0, 0, -12))

	-- rochers percés (tunnels de slide)
	H.slideBlock(z, V3(-30, 0, 40), 14, 13, 8, ROCK, "X")
	H.slideBlock(z, V3(40, 0, 10), 14, 13, 7, ROCK, "Z")
	H.slideBlock(z, V3(-95, 0, -5), 12, 13, 8, ROCK, "Z")
	H.slideBlock(z, V3(100, 0, 95), 12, 13, 7, ROCK, "X")
	for _, r in { { -100, 100, 9 }, { 105, 15, 7 }, { 30, 105, 6 }, { -50, 95, 5 } } do
		block(z, r[1], r[2], r[3] * 2, r[3], r[3] * 1.6, ROCK, 0, { Name = "Rocher" })
	end

	-- tour de surveillance
	for _, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do pillar(z, 95 + c[1] * 3, -50 + c[2] * 3, 8, 0.4, RGB(250, 250, 250), 0) end
	part(z, V3(8, 1, 8), CF(95, 8.5, -50), RGB(255, 70, 70), { Name = "Vigie" })
	H.jumpPad(z, V3(95, 0, -38), 70, V3(0, 0, -10))

	-- palmiers, parasols, serviettes
	local function palm(x, zz, hgt)
		for i = 0, hgt - 1 do
			block(z, x + (i % 2) * 0.3, zz, 1.6, 1, 1.6, RGB(150, 100, 55), i, { Name = "Stipe" })
		end
		for k = 0, 3 do
			local a = k * math.pi / 2 + 0.4
			local tip = V3(x + math.cos(a) * 6, hgt - 1.5, zz + math.sin(a) * 6)
			H.slab(z, V3(x, hgt + 0.6, zz), tip, 2.4, RGB(60, 190, 70), 0.3, "Palme")
		end
		part(z, V3(1.2, 1.2, 1.2), CF(x + 0.6, hgt - 0.4, zz + 0.6), RGB(110, 70, 30), { Name = "Coco", Shape = Enum.PartType.Ball, NoStuds = true })
	end
	for _, p in { { -100, -55, 11 }, { -40, -58, 10 }, { 40, -56, 12 }, { 105, -60, 10 }, { -105, 40, 12 }, { 108, 50, 11 },
		{ -30, 75, 9 }, { 40, 70, 10 }, { 20, -30, 9 }, { -20, -35, 11 } } do
		palm(p[1], p[2], p[3])
	end
	local colors = { RGB(255, 80, 120), RGB(80, 160, 255), RGB(255, 210, 60), RGB(120, 230, 120) }
	for i, p in { { -60, 10 }, { 60, 25 }, { -25, -45 }, { 30, -45 }, { 90, -10 }, { -90, 75 } } do
		pillar(z, p[1], p[2], 6, 0.2, RGB(240, 240, 240), 0)
		part(z, V3(0.4, 8, 8), CF(p[1], 6.2, p[2]) * CFrame.Angles(0, 0, math.rad(90)), colors[(i % 4) + 1],
			{ Name = "Parasol", Shape = Enum.PartType.Cylinder, NoStuds = true })
		part(z, V3(3, 0.08, 5.5), CF(p[1] + 3.5, 0.04, p[2]), colors[((i + 1) % 4) + 1], { Name = "Serviette", NoStuds = true, CanCollide = false })
	end
	for _, p in { { -45, 0 }, { 45, 0 }, { 10, 45 }, { -80, -45 }, { 80, -45 }, { 0, -55 } } do
		H.lamp(z, p[1], p[2], 0, RGB(255, 170, 90))
	end

	for _, p in { { -20, 30 }, { 20, 30 }, { -60, 20 }, { 60, 40 }, { -100, 20 }, { 100, 30 }, { -70, -50 }, { 70, -50 },
		{ -20, -50 }, { 25, -55 }, { -40, 100 }, { 50, 100 }, { 0, 65 }, { -105, -20 } } do
		H.spawnPoint(spawns, V3(p[1], 0, p[2]))
	end
end

return Plage
