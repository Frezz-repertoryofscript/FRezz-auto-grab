--[[
	Map "Village alpin" - neige, lac gelé glissant au centre, chalets à toits plats enneigés (Y≈14.4) reliés par des
	passerelles en boucle, tremplin de ski avec pad de saut, tunnels de slide dans des congères, sapins et bonshommes de neige.
]]
local Neige = { Id = "neige", Name = "Village alpin", Order = 5, Clock = 10.5, Gradient = "blue",
	Icon = "Nature/Cloud/Cloud 1st Outline", Description = "Lac gelé, chalets et tremplin" }

function Neige.Build(H, map, spawns)
	local RGB, V3, CF = H.RGB, H.V3, H.CF
	local part, block, pillar = H.part, H.block, H.pillar
	local SNOW, ICE, WOOD, DARKWOOD, PINE = RGB(242, 246, 255), RGB(170, 220, 255), RGB(160, 100, 60), RGB(110, 70, 45), RGB(40, 120, 70)
	H.arena(map, 120, SNOW, RGB(120, 160, 210), RGB(120, 220, 255), 30)
	local z = H.folder(map, "Neige")
	local ROOF = 14.4

	-- lac gelé (matériau Ice : on glisse !)
	part(z, V3(70, 0.2, 70), CF(0, 0.1, 0), ICE, { Name = "LacGele", Material = Enum.Material.Ice, Transparency = 0.1 })
	for _, p in { { -10, 8 }, { 14, -12 }, { 4, 20 } } do
		part(z, V3(6, 0.05, 0.4), CF(p[1], 0.225, p[2]), RGB(255, 255, 255), { Name = "Fissure", NoStuds = true, CanCollide = false })
	end

	-- chalets (toits plats praticables)
	local function chalet(x, zz, sx, sz, roofCol)
		local m = Instance.new("Model"); m.Name = "Chalet"; m.Parent = z
		block(m, x, zz, sx, 13, sz, WOOD, 0, { Name = "Murs" })
		block(m, x, zz, sx + 2, 1, sz + 2, roofCol, 13, { Name = "Toit" })
		block(m, x, zz, sx + 1, 0.4, sz + 1, SNOW, 14, { Name = "Neige" })
		block(m, x + sx / 4, zz + sz / 4, 2.4, 3.5, 2.4, RGB(150, 70, 60), ROOF, { Name = "Cheminee" })
		-- fenêtres lumineuses
		for _, side in { -1, 1 } do
			part(m, V3(3, 3, 0.2), CF(x - sx / 4, 8, zz + side * (sz / 2 + 0.15)), RGB(255, 220, 140),
				{ Name = "Fenetre", Material = Enum.Material.Neon, CanCollide = false })
			part(m, V3(3, 3, 0.2), CF(x + sx / 4, 8, zz + side * (sz / 2 + 0.15)), RGB(255, 220, 140),
				{ Name = "Fenetre", Material = Enum.Material.Neon, CanCollide = false })
		end
		part(m, V3(4, 6, 0.2), CF(x, 3, zz + sz / 2 + 0.15), DARKWOOD, { Name = "Porte", CanCollide = false, NoStuds = true })
		return m
	end
	chalet(70, 40, 20, 16, RGB(200, 50, 50)); chalet(70, -40, 20, 16, RGB(60, 90, 200))
	chalet(-70, 40, 20, 16, RGB(60, 90, 200)); chalet(-70, -40, 20, 16, RGB(200, 50, 50))
	chalet(0, 85, 20, 16, RGB(240, 160, 30)); chalet(0, -85, 20, 16, RGB(240, 160, 30))

	-- passerelles en boucle (bords de toit)
	local function walk(a, b) H.slab(z, a, b, 4, DARKWOOD, 0.6, "Passerelle") end
	walk(V3(70, ROOF, 31), V3(70, ROOF, -31))
	walk(V3(-70, ROOF, 31), V3(-70, ROOF, -31))
	walk(V3(11, ROOF, 80), V3(59, ROOF, 45))
	walk(V3(-11, ROOF, 80), V3(-59, ROOF, 45))
	walk(V3(11, ROOF, -80), V3(59, ROOF, -45))
	walk(V3(-11, ROOF, -80), V3(-59, ROOF, -45))
	-- accès : rampes extérieures + pads
	H.slab(z, V3(110, 0, 40), V3(81, ROOF, 40), 6, DARKWOOD, 1, "Rampe")
	H.slab(z, V3(-110, 0, -40), V3(-81, ROOF, -40), 6, DARKWOOD, 1, "Rampe")
	H.jumpPad(z, V3(0, 0, 62), 82, V3(0, 0, 14))
	H.jumpPad(z, V3(0, 0, -62), 82, V3(0, 0, -14))

	-- tremplin de ski
	H.slab(z, V3(-30, 0, -108), V3(-80, 18, -108), 8, SNOW, 1, "Tremplin")
	block(z, -87, -108, 14, 18, 12, RGB(200, 210, 230), 0, { Name = "PlateformeTremplin" })
	H.jumpPad(z, V3(-89, 18, -108), 95, V3(40, 0, 24))
	for k = 0, 4 do
		part(z, V3(0.4, 1.2, 0.4), CF(-35 - k * 10, 0.6 + k * 3.6 + 1, -112.5), RGB(255, 60, 60), { Name = "Fanion", CanCollide = false, NoStuds = true })
	end

	-- congères percées (tunnels de slide)
	H.slideBlock(z, V3(-40, 0, 62), 14, 12, 7, SNOW, "X")
	H.slideBlock(z, V3(40, 0, -62), 14, 12, 7, SNOW, "X")
	H.slideBlock(z, V3(100, 0, -90), 12, 12, 7, SNOW, "Z")
	H.slideBlock(z, V3(-100, 0, 90), 12, 12, 7, SNOW, "Z")

	-- sapins
	local function pine(x, zz, s)
		block(z, x, zz, 1.2 * s, 3 * s, 1.2 * s, DARKWOOD, 0, { Name = "Tronc" })
		block(z, x, zz, 7 * s, 3 * s, 7 * s, PINE, 3 * s, { Name = "Sapin" })
		block(z, x, zz, 5 * s, 3 * s, 5 * s, PINE:Lerp(SNOW, 0.08), 6 * s, { Name = "Sapin" })
		block(z, x, zz, 3 * s, 2.5 * s, 3 * s, PINE:Lerp(SNOW, 0.15), 9 * s, { Name = "Sapin" })
		block(z, x, zz, 1.6 * s, 0.6 * s, 1.6 * s, SNOW, 11.5 * s, { Name = "NeigeSapin" })
	end
	for _, p in { { -105, -60, 1.1 }, { 105, 70, 1 }, { -105, 10, 0.9 }, { 105, -10, 1.2 }, { 40, 105, 1 }, { -40, 105, 1.1 },
		{ 35, -100, 0.9 }, { -20, -60, 0.8 }, { 25, 55, 0.8 }, { -45, -20, 0.9 }, { 48, 15, 0.9 }, { 90, 105, 1 } } do
		pine(p[1], p[2], p[3])
	end
	-- bonshommes de neige
	for _, p in { { -25, 45 }, { 30, -45 }, { 95, 0 } } do
		part(z, V3(4, 4, 4), CF(p[1], 2, p[2]), SNOW, { Name = "Boule", Shape = Enum.PartType.Ball, NoStuds = true })
		part(z, V3(3, 3, 3), CF(p[1], 5.2, p[2]), SNOW, { Name = "Boule", Shape = Enum.PartType.Ball, NoStuds = true })
		part(z, V3(2.1, 2.1, 2.1), CF(p[1], 7.5, p[2]), SNOW, { Name = "Tete", Shape = Enum.PartType.Ball, NoStuds = true })
		part(z, V3(0.3, 0.3, 1.2), CF(p[1], 7.5, p[2] - 1.3), RGB(255, 140, 30), { Name = "Carotte", NoStuds = true, CanCollide = false })
	end
	for _, p in { { 45, 35 }, { -45, -35 }, { 45, -35 }, { -45, 35 }, { 0, 50 }, { 0, -50 } } do
		H.lamp(z, p[1], p[2], 0, RGB(255, 200, 120))
	end
	_ = pillar

	for _, p in { { 20, 20 }, { -20, -20 }, { 25, -25 }, { -25, 25 }, { 90, 60 }, { -90, -60 }, { 90, -60 }, { -90, 60 },
		{ 60, 100 }, { -60, -100 }, { 100, 20 }, { -100, -20 }, { 0, 108 }, { 0, -108 } } do
		H.spawnPoint(spawns, V3(p[1], 0.2, p[2]))
	end
end

return Neige
