--[[
	Map "Néon City" - de nuit, sol sombre quadrillé de néons, tours aux arêtes lumineuses.
	Niveau 1 (Y=14) : 4 tours reliées par des ponts au disque holographique central.
	Niveau 2 (Y=22) : 4 tours longues reliées en boucle par des "ponts de lumière" ; jump pads depuis le niveau 1.
	Tuyaux néon de slide au sol, pads vers le disque central.
]]
local Neon = { Id = "neon", Name = "Néon City", Order = 4, Clock = 0.5, Gradient = "magenta",
	Icon = "Main/Lighting/Purple Lighting 1st Outline", Description = "Nuit, ponts de lumière, néons" }

function Neon.Build(H, map, spawns)
	local RGB, V3, CF = H.RGB, H.V3, H.CF
	local part, block, pillar, neon = H.part, H.block, H.pillar, H.neonStrip
	local FLOOR, BODY = RGB(26, 28, 42), RGB(44, 48, 70)
	local CYAN, PINK, GOLD = RGB(0, 235, 255), RGB(255, 40, 200), RGB(255, 210, 60)
	H.arena(map, 120, FLOOR, RGB(36, 40, 60), PINK, 34)
	local z = H.folder(map, "Neon")

	-- quadrillage lumineux (hauteurs différentes pour les deux sens : pas de faces communes aux croisements)
	for k = -90, 90, 30 do
		part(z, V3(240, 0.06, 0.3), CF(0, 0.03, k), CYAN, { Name = "Grille", Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
		part(z, V3(0.3, 0.09, 240), CF(k, 0.045, 0), PINK, { Name = "Grille", Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	end

	local function tower(x, zz, sx, sz, h, col)
		local m = Instance.new("Model"); m.Name = "Tour"; m.Parent = z
		block(m, x, zz, sx, h - 0.6, sz, BODY, 0, { Name = "Corps" })
		block(m, x, zz, sx + 0.8, 0.6, sz + 0.8, RGB(20, 22, 32), h - 0.6, { Name = "Toit" })
		for _, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
			neon(m, V3(0.4, h - 1.2, 0.4), CF(x + c[1] * (sx / 2 + 0.2), (h - 0.6) / 2, zz + c[2] * (sz / 2 + 0.2)), col)
		end
		for y = 4, h - 3, 6 do
			neon(m, V3(sx, 0.4, 0.2), CF(x, y, zz - sz / 2 - 0.1), col)
			neon(m, V3(sx, 0.4, 0.2), CF(x, y, zz + sz / 2 + 0.1), col)
			neon(m, V3(0.2, 0.4, sz), CF(x - sx / 2 - 0.1, y, zz), col)
			neon(m, V3(0.2, 0.4, sz), CF(x + sx / 2 + 0.1, y, zz), col)
		end
		local l = Instance.new("PointLight"); l.Color = col; l.Range = 24; l.Brightness = 1.5; l.Parent = m:FindFirstChild("Toit")
		return m
	end
	-- niveau 1
	for _, s in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do tower(s[1] * 50, s[2] * 50, 20, 20, 14, CYAN) end
	-- niveau 2
	tower(0, -85, 28, 16, 22, PINK); tower(0, 85, 28, 16, 22, PINK)
	tower(-85, 0, 16, 28, 22, PINK); tower(85, 0, 16, 28, 22, PINK)
	-- tours d'angle décoratives
	for _, s in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do tower(s[1] * 100, s[2] * 100, 14, 14, 30, GOLD) end

	-- disque holographique central (Y=14)
	pillar(z, 0, 0, 13, 3, BODY, 0)
	part(z, V3(1, 32, 32), CF(0, 13.5, 0) * CFrame.Angles(0, 0, math.rad(90)), RGB(30, 34, 52),
		{ Name = "Disque", Shape = Enum.PartType.Cylinder, NoStuds = true })
	part(z, V3(0.3, 33, 33), CF(0, 13.1, 0) * CFrame.Angles(0, 0, math.rad(90)), CYAN,
		{ Name = "DisqueNeon", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, CanCollide = false })
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		neon(z, V3(1, 1, 1), CF(math.cos(a) * 10, 24, math.sin(a) * 10), if k % 2 == 0 then CYAN else PINK)
	end
	-- ponts niveau 1 : coins intérieurs des tours -> disque
	for _, s in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		H.slab(z, V3(s[1] * 40, 14, s[2] * 40), V3(s[1] * 11, 14, s[2] * 11), 5, RGB(60, 66, 96), 0.8, "Pont")
	end
	-- ponts de lumière niveau 2 (boucle)
	local function lightBridge(a, b)
		H.slab(z, a, b, 5, CYAN, 0.6, "PontLumiere").Material = Enum.Material.Neon
	end
	lightBridge(V3(14, 22, -77), V3(77, 22, -14))
	lightBridge(V3(77, 22, 14), V3(14, 22, 77))
	lightBridge(V3(-14, 22, 77), V3(-77, 22, 14))
	lightBridge(V3(-77, 22, -14), V3(-14, 22, -77))
	-- accès : rampes sol -> niveau 1, pads niveau 1 -> niveau 2, pads sol -> disque
	for _, s in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		H.slab(z, V3(s[1] * 50, 0, s[2] * 86), V3(s[1] * 50, 14, s[2] * 60.5), 6, RGB(60, 66, 96), 1, "Rampe")
		H.jumpPad(z, V3(s[1] * 55, 14, s[2] * 55), 82, V3(-s[1] * 10, 0, -s[2] * 10))
	end
	for _, p in { { 25, 0, -12, 0 }, { -25, 0, 12, 0 }, { 0, 25, 0, -12 }, { 0, -25, 0, 12 } } do
		H.jumpPad(z, V3(p[1], 0, p[2]), 80, V3(p[3], 0, p[4]))
	end

	-- tuyaux de slide
	H.slideBlock(z, V3(0, 0, 52), 16, 11, 7, RGB(40, 30, 70), "X")
	H.slideBlock(z, V3(0, 0, -52), 16, 11, 7, RGB(40, 30, 70), "X")
	H.slideBlock(z, V3(52, 0, 0), 16, 11, 7, RGB(40, 30, 70), "Z")
	H.slideBlock(z, V3(-52, 0, 0), 16, 11, 7, RGB(40, 30, 70), "Z")

	-- bornes lumineuses
	for _, p in { { 30, 75 }, { -30, -75 }, { 75, -30 }, { -75, 30 }, { 105, 50 }, { -105, -50 } } do
		H.lamp(z, p[1], p[2], 0, if p[1] > 0 then CYAN else PINK)
	end

	for _, p in { { 30, 30 }, { -30, -30 }, { 30, -30 }, { -30, 30 }, { 70, 70 }, { -70, -70 }, { 70, -70 }, { -70, 70 },
		{ 0, 110 }, { 0, -110 }, { 110, 0 }, { -110, 0 }, { 40, 105 }, { -40, -105 } } do
		H.spawnPoint(spawns, V3(p[1], 0.1, p[2]))
	end
end

return Neon
