--[[
	Map "Fête foraine" - circuit surélevé de montagnes russes (boucle Y=14 avec rampes intérieures), manège central au
	toit praticable, grande roue, chapiteaux rayés, stands, auto-tamponneuses, train fantôme (tunnel de slide),
	sucettes géantes et trampolines (jump pads).
]]
local Fete = { Id = "fete", Name = "Fête foraine", Order = 6, Clock = 16.2, Gradient = "pink",
	Icon = "Item/Lucky Block/Lucky Block 1st Outline", Description = "Manège, grande roue, train fantôme" }

function Fete.Build(H, map, spawns)
	local RGB, V3, CF = H.RGB, H.V3, H.CF
	local part, block, pillar = H.part, H.block, H.pillar
	local GROUND, TRACK = RGB(150, 225, 190), RGB(255, 80, 140)
	local POP = { RGB(255, 70, 110), RGB(255, 200, 40), RGB(70, 170, 255), RGB(130, 230, 90), RGB(190, 100, 255) }
	H.arena(map, 120, GROUND, RGB(255, 170, 60), RGB(80, 220, 255), 30)
	local z = H.folder(map, "Fete")
	local HH, R, Wd = 14, 75, 6

	-- allée centrale pavée
	part(z, V3(160, 0.1, 12), CF(0, 0.05, 0), RGB(250, 225, 170), { Name = "Allee", Sides = false })
	part(z, V3(12, 0.08, 74), CF(0, 0.04, -43), RGB(250, 225, 170), { Name = "Allee", Sides = false })
	part(z, V3(12, 0.08, 74), CF(0, 0.04, 43), RGB(250, 225, 170), { Name = "Allee", Sides = false })

	-- circuit des montagnes russes (carré Y=14) + supports + rampes intérieures
	local track = H.folder(z, "Circuit")
	part(track, V3(2 * R + Wd, 1, Wd), CF(0, HH - 0.5, -R), TRACK, { Name = "Rail", Sides = false })
	part(track, V3(2 * R + Wd, 1, Wd), CF(0, HH - 0.5, R), TRACK, { Name = "Rail", Sides = false })
	part(track, V3(Wd, 1, 2 * R - Wd), CF(-R, HH - 0.5, 0), TRACK, { Name = "Rail", Sides = false })
	part(track, V3(Wd, 1, 2 * R - Wd), CF(R, HH - 0.5, 0), TRACK, { Name = "Rail", Sides = false })
	for k = -R, R, 25 do
		for _, s in { -1, 1 } do
			pillar(track, k, s * R, HH - 1, 0.7, RGB(250, 250, 250), 0)
			if math.abs(k) < R then pillar(track, s * R, k, HH - 1, 0.7, RGB(250, 250, 250), 0) end
		end
	end
	local r = R - Wd / 2 - 2.5
	H.slab(track, V3(20, 0, -r), V3(44, HH, -r), 5, RGB(255, 200, 40), 1, "Rampe")
	H.slab(track, V3(r, 0, 20), V3(r, HH, 44), 5, RGB(255, 200, 40), 1, "Rampe")
	H.slab(track, V3(-20, 0, r), V3(-44, HH, r), 5, RGB(255, 200, 40), 1, "Rampe")
	H.slab(track, V3(-r, 0, -20), V3(-r, HH, -44), 5, RGB(255, 200, 40), 1, "Rampe")
	-- wagonnets décoratifs (bloquent un peu le passage : on les saute)
	for i, p in { { -30, -R }, { 40, R }, { R, -10 }, { -R, 30 } } do
		block(z, p[1], p[2], 4, 2, 4, POP[(i % #POP) + 1], HH, { Name = "Wagon" })
	end

	-- manège central (toit Y=10 praticable)
	pillar(z, 0, 0, 1.2, 14, RGB(255, 240, 200), 0.1)
	pillar(z, 0, 0, 9, 1.2, RGB(255, 200, 40), 1.3)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local x, zz = math.cos(a) * 10, math.sin(a) * 10
		pillar(z, x, zz, 7.7, 0.25, RGB(255, 220, 90), 1.3)
		block(z, x, zz, 1.4, 2, 3, POP[(k % #POP) + 1], 3, { Name = "Cheval" })
	end
	part(z, V3(1, 31, 31), CF(0, 9.5, 0) * CFrame.Angles(0, 0, math.rad(90)), RGB(255, 80, 110),
		{ Name = "ToitManege", Shape = Enum.PartType.Cylinder, NoStuds = true })
	pillar(z, 0, 0, 3, 3, RGB(255, 220, 90), 10)
	for _, p in { { 24, 0, -10, 0 }, { -24, 0, 10, 0 } } do
		H.jumpPad(z, V3(p[1], 0.1, p[2]), 72, V3(p[3], 0, p[4]))
	end

	-- grande roue (Nord, hors circuit)
	local hub = V3(0, 26, -100)
	for _, s in { -1, 1 } do H.slab(z, V3(s * 12, 0, -100), hub, 1.4, RGB(250, 250, 250), 1.4, "Pied") end
	local prev
	for k = 0, 16 do
		local a = k / 16 * math.pi * 2
		local p = hub + V3(math.cos(a) * 20, math.sin(a) * 20, 0)
		if prev then H.slab(z, prev, p, 1, RGB(70, 170, 255), 1, "Jante") end
		if k < 16 then
			H.neonStrip(z, V3(0.4, 0.4, 0.4), CF(p), POP[(k % #POP) + 1])
			if k % 2 == 0 then block(z, p.X, p.Z + 2.6, 3, 3, 3, POP[(k / 2 % #POP) + 1], p.Y - 3.2, { Name = "Nacelle" }) end
		end
		prev = p
	end

	-- chapiteaux rayés
	local function tent(x, zz, w, d, h, c1, c2)
		local n = math.floor(w / 2)
		for i = 0, n - 1 do
			block(z, x - w / 2 + 1 + i * 2, zz, 2, h, d, if i % 2 == 0 then c1 else c2, 0, { Name = "Chapiteau" })
		end
		block(z, x, zz, w + 1, 1.2, d + 1, c1, h, { Name = "Toit" })
		block(z, x, zz, w - 4, 1.4, d - 4, c2, h + 1.2, { Name = "Toit" })
		block(z, x, zz, w - 9, 1.4, d - 9, c1, h + 2.6, { Name = "Toit" })
	end
	tent(-45, -35, 18, 14, 8, RGB(255, 60, 80), RGB(255, 245, 235))
	tent(45, 35, 18, 14, 8, RGB(60, 120, 255), RGB(255, 245, 235))

	-- stands
	for i, p in { { -40, 18 }, { 40, -18 }, { -18, 40 }, { 18, -40 } } do
		block(z, p[1], p[2], 8, 3, 4, POP[(i % #POP) + 1], 0.1, { Name = "Stand" })
		block(z, p[1], p[2] + 1, 9, 0.5, 6, RGB(255, 245, 235), 6.5, { Name = "Auvent" })
		pillar(z, p[1] - 4, p[2] + 3.5, 6.4, 0.2, RGB(250, 250, 250), 0.1)
		pillar(z, p[1] + 4, p[2] + 3.5, 6.4, 0.2, RGB(250, 250, 250), 0.1)
	end

	-- auto-tamponneuses (piste à bord bas)
	local bx, bz, bw = 40, -45, 24
	block(z, bx, bz, bw, 0.2, bw, RGB(60, 60, 80), 0, { Name = "Piste" })
	block(z, bx, bz - bw / 2 - 0.5, bw + 2, 1.4, 1, RGB(255, 200, 40), 0, { Name = "Bordure" })
	block(z, bx, bz + bw / 2 + 0.5, bw + 2, 1.4, 1, RGB(255, 200, 40), 0, { Name = "Bordure" })
	block(z, bx - bw / 2 - 0.5, bz, 1, 1.4, bw, RGB(255, 200, 40), 0, { Name = "Bordure" })
	block(z, bx + bw / 2 + 0.5, bz, 1, 1.4, bw, RGB(255, 200, 40), 0, { Name = "Bordure" })
	for i, p in { { -6, -5 }, { 5, 4 }, { -4, 7 } } do
		block(z, bx + p[1], bz + p[2], 3, 1.4, 4, POP[(i % #POP) + 1], 0.2, { Name = "Auto" })
	end

	-- train fantôme + autres tunnels
	H.slideBlock(z, V3(-45, 0, 45), 20, 12, 9, RGB(40, 30, 60), "X")
	H.slideBlock(z, V3(60, 0, 8), 12, 12, 7, RGB(190, 100, 255), "Z")
	H.slideBlock(z, V3(-100, 0, -10), 12, 12, 7, RGB(255, 120, 60), "Z")
	H.slideBlock(z, V3(100, 0, 60), 12, 12, 7, RGB(70, 170, 255), "X")

	-- sucettes géantes
	for i, p in { { -100, 100 }, { 100, -100 }, { 100, 100 }, { -100, -60 }, { 30, 100 } } do
		pillar(z, p[1], p[2], 8, 0.35, RGB(250, 250, 250), 0)
		part(z, V3(0.8, 6, 6), CF(p[1], 10.5, p[2]), POP[(i % #POP) + 1], { Name = "Sucette", Shape = Enum.PartType.Cylinder, NoStuds = true })
	end
	-- trampolines extérieurs (vers le circuit)
	H.jumpPad(z, V3(95, 0, -40), 82, V3(-14, 0, 0))
	H.jumpPad(z, V3(-95, 0, 40), 82, V3(14, 0, 0))

	for _, p in { { 20, 20 }, { -20, -20 }, { 60, 60 }, { -60, -60 }, { -60, 60 }, { 60, -60 } } do
		H.lamp(z, p[1], p[2], 0, RGB(255, 210, 150))
	end

	for _, p in { { 25, 8 }, { -25, -8 }, { 8, 25 }, { -8, -25 }, { 55, 20 }, { -55, -20 }, { 20, -60 }, { -20, 60 },
		{ 105, 0 }, { -105, 20 }, { 0, 108 }, { 60, -105 }, { -60, 105 }, { 110, 85 } } do
		H.spawnPoint(spawns, V3(p[1], 0.1, p[2]))
	end
end

return Fete
