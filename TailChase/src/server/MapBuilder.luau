--[[
	MapBuilder - génère la map studded (≈300x300) et le lobby au démarrage du serveur.

	Pourquoi généré par code : le projet est livré en fichiers Rojo (pas de .rbxl). Si Workspace contient déjà un
	modèle "Map" / "Lobby" (par ex. après l'avoir sauvegardé depuis Studio et retouché à la main), il est réutilisé tel quel.

	Repères (Y = 0 = sol) :
		Place centrale  : centre, anneau surélevé (passerelle) à Y=14, fontaine, rampes, jump pads
		Village (NE)    : 3x3 maisons à toits plats (Y=14) reliés par planches, ruelles avec tunnels de slide
		Toits (SE)      : tours de hauteurs variées, passerelles, jump pads, petit parcours de saut flottant
		Industriel (SO) : conteneurs, échafaudages + passerelle Y=14, gros tunnels de slide dans des blocs-tuyaux
		Jardins (NO)    : haies (labyrinthe à boucles), arbre-plateforme Y=14, étang, haie avec trou de slide
	Chaque zone est reliée à l'anneau central par un pont diagonal à Y=14 -> boucles sur deux niveaux, pas d'impasse.

	Tags (CollectionService) :
		"JumpPad"      Attributes Power (vitesse verticale) / Push (Vector3 horizontal)  -> MovementController
		"SlideCeiling" plafonds de tunnel (CollisionGroup "SlideCeiling", traversés uniquement en slide)
	Dossiers : Map.Spawns (points de départ de manche), Lobby.Spawns (SpawnLocation)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")

local Config = require(ReplicatedStorage.Shared.Config)
local UI = require(ReplicatedStorage.StudUI)

local MapBuilder = {}

local RGB = Color3.fromRGB
local V3 = Vector3.new
local CF = CFrame.new

MapBuilder.LobbyCenter = V3(0, 0, 420)
MapBuilder.RingHeight = 14

-- Palette cohérente (couleurs vives, chaudes)
local PAL = {
	Road = RGB(78, 84, 102),
	RoadLine = RGB(255, 214, 60),
	Plaza = RGB(242, 214, 160),
	PlazaAlt = RGB(226, 186, 128),
	Grass = RGB(110, 200, 70),
	GrassDark = RGB(70, 160, 50),
	Hedge = RGB(50, 140, 60),
	Leaves = RGB(90, 200, 70),
	Trunk = RGB(140, 90, 50),
	Water = RGB(60, 170, 255),
	Concrete = RGB(170, 170, 180),
	Metal = RGB(110, 115, 130),
	Wall = RGB(255, 120, 80),
	Ring = RGB(255, 80, 110),
	Bridge = RGB(255, 190, 40),
	Pad = RGB(60, 255, 120),
	Neon1 = RGB(0, 230, 255),
	Neon2 = RGB(255, 60, 200),
	White = RGB(250, 250, 250),
	Houses = { RGB(255, 160, 160), RGB(160, 210, 255), RGB(255, 230, 140), RGB(190, 255, 170), RGB(230, 180, 255), RGB(255, 200, 150) },
	Roofs = { RGB(220, 70, 60), RGB(60, 120, 220), RGB(240, 150, 30), RGB(60, 170, 90) },
	Containers = { RGB(230, 60, 50), RGB(40, 120, 230), RGB(255, 190, 30), RGB(50, 180, 90), RGB(240, 110, 30) },
	Towers = { RGB(120, 200, 255), RGB(255, 140, 200), RGB(255, 210, 90), RGB(150, 255, 200) },
}

-- =====================================================================
-- HELPERS
-- =====================================================================
local SIDES = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }

local function studs(p: BasePart, sides: boolean?)
	local function add(face)
		local t = Instance.new("Texture")
		t.Name = "Studs"
		t.Texture = Config.StudTexture
		t.Face = face
		t.StudsPerTileU = 1
		t.StudsPerTileV = 1
		t.Transparency = 0.6
		t.Parent = p
	end
	add(Enum.NormalId.Top)
	if sides then
		for _, f in SIDES do add(f) end
	end
end

type PartOpts = {
	Name: string?, Material: Enum.Material?, Shape: Enum.PartType?, CanCollide: boolean?, Transparency: number?,
	Sides: boolean?, NoStuds: boolean?, Tag: string?, CastShadow: boolean?,
}

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, o: PartOpts?): Part
	local opts: PartOpts = o or {}
	local p = Instance.new("Part")
	p.Name = opts.Name or "Part"
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = opts.Material or Enum.Material.Plastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.Shape then p.Shape = opts.Shape end
	if opts.CanCollide == false then p.CanCollide = false end
	if opts.Transparency then p.Transparency = opts.Transparency end
	if opts.CastShadow == false then p.CastShadow = false end
	if not opts.NoStuds and p.Material ~= Enum.Material.Neon and p.Material ~= Enum.Material.Glass then
		studs(p, opts.Sides ~= false and (size.Y >= 3))
	end
	if opts.Tag then CollectionService:AddTag(p, opts.Tag) end
	p.Parent = parent
	return p
end

--- Bloc posé au sol : (x, z) centre, taille, hauteur de base y0.
local function block(parent, x, z, sx, sy, sz, color, y0, o)
	return part(parent, V3(sx, sy, sz), CF(x, (y0 or 0) + sy / 2, z), color, o)
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

--- Rampe/pont entre deux points (dessus de la dalle = segment a->b).
local function slab(parent, a: Vector3, b: Vector3, width: number, color: Color3, thick: number?, name: string?)
	local t = thick or 1
	local len = (b - a).Magnitude
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(mid, b)
	cf = cf * CF(0, -t / 2, 0)
	return part(parent, V3(width, t, len), cf, color, { Name = name or "Rampe", Sides = false })
end

local function railing(parent, a: Vector3, b: Vector3, color: Color3)
	local len = (b - a).Magnitude
	local mid = (a + b) / 2 + V3(0, 0.75, 0)
	return part(parent, V3(0.6, 1.5, len), CFrame.lookAt(mid, b + V3(0, 0.75, 0)), color, { Name = "Rambarde", NoStuds = true })
end

local function pillar(parent, x, z, h, r, color, y0)
	return part(parent, V3(h, r * 2, r * 2), CF(x, (y0 or 0) + h / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color,
		{ Name = "Pilier", Shape = Enum.PartType.Cylinder, NoStuds = true })
end

local function jumpPad(parent, pos: Vector3, power: number, push: Vector3?)
	local base = part(parent, V3(0.6, 7, 7), CF(pos + V3(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), RGB(30, 40, 50),
		{ Name = "JumpPadSocle", Shape = Enum.PartType.Cylinder, NoStuds = true })
	local pad = part(parent, V3(0.4, 5.6, 5.6), CF(pos + V3(0, 0.7, 0)) * CFrame.Angles(0, 0, math.rad(90)), PAL.Pad,
		{ Name = "JumpPad", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Tag = "JumpPad" })
	pad:SetAttribute("Power", power)
	pad:SetAttribute("Push", push or Vector3.zero)
	local att = Instance.new("Attachment")
	att.Parent = pad
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Fleches"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(PAL.Pad)
	pe.Size = NumberSequence.new(0.6, 0)
	pe.Lifetime = NumberRange.new(0.6, 0.9)
	pe.Rate = 12
	pe.Speed = NumberRange.new(8, 12)
	pe.SpreadAngle = Vector2.new(10, 10)
	pe.EmissionDirection = Enum.NormalId.Right -- axe du cylindre tourné = haut
	pe.LightEmission = 1
	pe.Parent = att
	return pad, base
end

local function lamp(parent, x, z, y0, color)
	local y = y0 or 0
	pillar(parent, x, z, 9, 0.35, RGB(40, 44, 56), y)
	local head = part(parent, V3(1.6, 1.2, 1.6), CF(x, y + 9.4, z), color or RGB(255, 230, 150),
		{ Name = "Lampe", Material = Enum.Material.Neon, CastShadow = false })
	part(parent, V3(2.2, 0.4, 2.2), CF(x, y + 10.2, z), RGB(40, 44, 56), { Name = "Chapeau", NoStuds = true })
	local l = Instance.new("PointLight")
	l.Color = color or RGB(255, 210, 140)
	l.Range = 22
	l.Brightness = 1.4
	l.Shadows = false
	l.Parent = head
end

local function tree(parent, x, z, scale, y0)
	local s = scale or 1
	local y = y0 or 0
	block(parent, x, z, 1.6 * s, 6 * s, 1.6 * s, PAL.Trunk, y, { Name = "Tronc" })
	block(parent, x, z, 7 * s, 4 * s, 7 * s, PAL.Leaves, y + 5.5 * s, { Name = "Feuillage", Sides = true })
	block(parent, x, z, 4.6 * s, 3 * s, 4.6 * s, PAL.GrassDark:Lerp(PAL.Leaves, 0.5), y + 9.5 * s, { Name = "Feuillage" })
end

local function bench(parent, x, z, rotY, y0)
	local y = y0 or 0
	local base = CF(x, y, z) * CFrame.Angles(0, math.rad(rotY or 0), 0)
	part(parent, V3(5, 0.5, 1.6), base * CF(0, 1.4, 0), RGB(200, 120, 60), { Name = "Banc" })
	part(parent, V3(5, 1.4, 0.4), base * CF(0, 2.3, 0.7), RGB(200, 120, 60), { Name = "Dossier" })
	part(parent, V3(0.5, 1.2, 1.4), base * CF(-2.1, 0.6, 0), RGB(50, 50, 60), { Name = "Pied", NoStuds = true })
	part(parent, V3(0.5, 1.2, 1.4), base * CF(2.1, 0.6, 0), RGB(50, 50, 60), { Name = "Pied", NoStuds = true })
end

local function neonStrip(parent, size: Vector3, cf: CFrame, color: Color3)
	return part(parent, size, cf, color, { Name = "Neon", Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
end

--[[ Bloc avec tunnel de slide traversant. axis = "X" ou "Z" (sens du tunnel). Ouverture : 5 de large, 3 de haut.
	Le plafond (et tout le haut du bloc) est dans le CollisionGroup "SlideCeiling" : seul un joueur en slide passe. ]]
local TUNNEL_W, TUNNEL_H = 5, 3
local function slideBlock(parent, center: Vector3, length: number, width: number, height: number, color: Color3, axis: string)
	local m = Instance.new("Model")
	m.Name = "TunnelSlide"
	m.Parent = parent
	local side = (width - TUNNEL_W) / 2
	local alongX = axis == "X"
	local function sz(along, across, h)
		return if alongX then V3(along, h, across) else V3(across, h, along)
	end
	local function off(across)
		return if alongX then V3(0, 0, across) else V3(across, 0, 0)
	end
	-- murs latéraux
	local y = center.Y
	part(m, sz(length, side, height), CF(V3(center.X, y + height / 2, center.Z) + off(-(TUNNEL_W / 2 + side / 2))), color, { Name = "Mur" })
	part(m, sz(length, side, height), CF(V3(center.X, y + height / 2, center.Z) + off(TUNNEL_W / 2 + side / 2)), color, { Name = "Mur" })
	-- plafond (traversable en slide uniquement)
	local ceil = part(m, sz(length, TUNNEL_W, height - TUNNEL_H), CF(center.X, y + TUNNEL_H + (height - TUNNEL_H) / 2, center.Z), color,
		{ Name = "Plafond", Tag = "SlideCeiling" })
	ceil.CollisionGroup = "SlideCeiling"
	-- intérieur sombre + bandes néon pour signaler l'entrée
	part(m, sz(length - 0.2, TUNNEL_W - 0.1, 0.1), CF(center.X, y + TUNNEL_H - 0.05, center.Z), RGB(30, 30, 40),
		{ Name = "Ombre", CanCollide = false, NoStuds = true, CastShadow = false })
	for _, s in { -1, 1 } do
		local endOff = if alongX then V3(s * (length / 2 + 0.05), 0, 0) else V3(0, 0, s * (length / 2 + 0.05))
		neonStrip(m, sz(0.2, TUNNEL_W + 0.6, 0.4), CF(V3(center.X, y + TUNNEL_H + 0.2, center.Z) + endOff), PAL.Neon1)
		-- panneau "SLIDE" au dessus de l'entrée
		local sign = part(m, sz(0.3, 4.5, 1.6), CF(V3(center.X, y + math.min(height - 0.9, TUNNEL_H + 1.4), center.Z) + endOff * 1.01), RGB(20, 24, 32),
			{ Name = "PanneauSlide", NoStuds = true, CanCollide = false })
		local face
		if alongX then face = if s > 0 then Enum.NormalId.Right else Enum.NormalId.Left
		else face = if s > 0 then Enum.NormalId.Back else Enum.NormalId.Front end
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.LightInfluence = 0
		sg.Parent = sign
		UI.Text(sg, "SLIDE  [C]", { Size = UDim2.fromScale(1, 1), Max = 44, Color = PAL.Neon1, Stroke = RGB(0, 30, 40), Thickness = 3, Font = "Gotham" })
	end
	return m
end

local function sign(parent: Instance, size: Vector3, cf: CFrame, face: Enum.NormalId, ppu: number?): (Part, SurfaceGui)
	local p = part(parent, size, cf, RGB(22, 26, 36), { Name = "Panneau", NoStuds = true })
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppu or 50
	sg.LightInfluence = 0.2
	sg.Parent = p
	return p, sg
end
MapBuilder.Sign = sign

local function spawnPoint(spawns: Folder, pos: Vector3)
	local s = part(spawns, V3(4, 0.2, 4), CF(pos + V3(0, 0.1, 0)), RGB(255, 255, 255),
		{ Name = "MapSpawn", CanCollide = false, Transparency = 1, NoStuds = true })
	s.CanQuery = false
	s.CanTouch = false
end

-- =====================================================================
-- ZONES
-- =====================================================================
local function buildGround(map)
	local g = folder(map, "Sol")
	-- base (routes)
	part(g, V3(300, 4, 300), CF(0, -2, 0), PAL.Road, { Name = "Route", Sides = false })
	-- marquages de route
	for i = -3, 3 do
		if i ~= 0 then
			part(g, V3(6, 0.1, 1), CF(i * 20, 0.05, 43), PAL.RoadLine, { Name = "Marquage", NoStuds = true, CanCollide = false })
			part(g, V3(6, 0.1, 1), CF(i * 20, 0.05, -43), PAL.RoadLine, { Name = "Marquage", NoStuds = true, CanCollide = false })
			part(g, V3(1, 0.1, 6), CF(43, 0.05, i * 20), PAL.RoadLine, { Name = "Marquage", NoStuds = true, CanCollide = false })
			part(g, V3(1, 0.1, 6), CF(-43, 0.05, i * 20), PAL.RoadLine, { Name = "Marquage", NoStuds = true, CanCollide = false })
		end
	end
	-- dalles de zones (léger trottoir de 0.4)
	part(g, V3(70, 0.4, 70), CF(0, 0.2, 0), PAL.Plaza, { Name = "Place" })
	part(g, V3(30, 0.42, 30), CF(0, 0.21, 0), PAL.PlazaAlt, { Name = "PlaceCentre" })
	part(g, V3(96, 0.4, 96), CF(99, 0.2, -99), RGB(200, 230, 150), { Name = "SolVillage" })
	part(g, V3(96, 0.4, 96), CF(99, 0.2, 99), RGB(150, 160, 190), { Name = "SolToits" })
	part(g, V3(96, 0.4, 96), CF(-99, 0.2, 99), PAL.Concrete, { Name = "SolIndustriel" })
	part(g, V3(96, 0.4, 96), CF(-99, 0.2, -99), PAL.Grass, { Name = "SolJardins" })

	-- murs d'enceinte (hauts, colorés, néon en haut)
	local walls = folder(map, "Enceinte")
	for _, w in {
		{ V3(308, 40, 4), CF(0, 20, -152) }, { V3(308, 40, 4), CF(0, 20, 152) },
		{ V3(4, 40, 300), CF(-152, 20, 0) }, { V3(4, 40, 300), CF(152, 20, 0) },
	} do
		part(walls, w[1], w[2], PAL.Wall, { Name = "Mur" })
		neonStrip(walls, V3(w[1].X + 0.2, 0.8, w[1].Z + 0.2), w[2] * CF(0, 20.4, 0), PAL.Neon2)
	end
end

local function buildPlaza(map, spawns)
	local z = folder(map, "PlaceCentrale")
	local H = MapBuilder.RingHeight
	-- fontaine
	part(z, V3(2, 22, 22), CF(0, 1.4, 0) * CFrame.Angles(0, 0, math.rad(90)), PAL.White, { Name = "Bassin", Shape = Enum.PartType.Cylinder, NoStuds = true })
	part(z, V3(0.4, 19, 19), CF(0, 2.3, 0) * CFrame.Angles(0, 0, math.rad(90)), PAL.Water,
		{ Name = "Eau", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Glass, Transparency = 0.25, NoStuds = true })
	pillar(z, 0, 0, 7, 1.2, PAL.White, 0.4)
	local top = part(z, V3(1.5, 5, 5), CF(0, 8.2, 0) * CFrame.Angles(0, 0, math.rad(90)), PAL.Neon1,
		{ Name = "Jet", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon })
	local att = Instance.new("Attachment"); att.Parent = top
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(RGB(180, 230, 255))
	pe.Size = NumberSequence.new(1.2, 0.2)
	pe.Transparency = NumberSequence.new(0.3, 1)
	pe.Lifetime = NumberRange.new(1, 1.4)
	pe.Rate = 30
	pe.Speed = NumberRange.new(10, 14)
	pe.SpreadAngle = Vector2.new(25, 25)
	pe.Acceleration = V3(0, -25, 0)
	pe.EmissionDirection = Enum.NormalId.Right
	pe.Parent = att

	-- anneau surélevé (passerelle) Y = 14
	local R, Wd = 32, 6
	local ring = folder(z, "Anneau")
	part(ring, V3(2 * R + Wd, 1, Wd), CF(0, H - 0.5, -R), PAL.Ring, { Name = "AnneauN", Sides = false })
	part(ring, V3(2 * R + Wd, 1, Wd), CF(0, H - 0.5, R), PAL.Ring, { Name = "AnneauS", Sides = false })
	part(ring, V3(Wd, 1, 2 * R - Wd), CF(R, H - 0.5, 0), PAL.Ring, { Name = "AnneauE", Sides = false })
	part(ring, V3(Wd, 1, 2 * R - Wd), CF(-R, H - 0.5, 0), PAL.Ring, { Name = "AnneauO", Sides = false })
	neonStrip(ring, V3(2 * R + Wd, 0.3, 0.3), CF(0, H - 1.1, -R - Wd / 2), PAL.Neon1)
	neonStrip(ring, V3(2 * R + Wd, 0.3, 0.3), CF(0, H - 1.1, R + Wd / 2), PAL.Neon1)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			pillar(ring, sx * R, sz * R, H - 1, 1.1, PAL.White)
		end
		pillar(ring, sx * R, 0, H - 1, 0.9, PAL.White)
		pillar(ring, 12, sx * R, H - 1, 0.9, PAL.White)
		pillar(ring, -12, sx * R, H - 1, 0.9, PAL.White)
	end
	-- rambardes extérieures (on peut sauter par dessus)
	railing(ring, V3(-R + 4, H, -R - Wd / 2 + 0.3), V3(R - 4, H, -R - Wd / 2 + 0.3), PAL.White)
	railing(ring, V3(-R + 4, H, R + Wd / 2 - 0.3), V3(R - 4, H, R + Wd / 2 - 0.3), PAL.White)
	-- rampes d'accès (4)
	for _, sx in { -1, 1 } do
		slab(ring, V3(sx * 18, 0.4, 0), V3(sx * 18, H, -R + Wd / 2), 5, PAL.PlazaAlt, 1, "RampeN")
		slab(ring, V3(-sx * 18, 0.4, 0), V3(-sx * 18, H, R - Wd / 2), 5, PAL.PlazaAlt, 1, "RampeS")
	end
	-- jump pads vers l'anneau Nord / Sud
	jumpPad(z, V3(0, 0.4, 20), 80, V3(0, 0, 20))
	jumpPad(z, V3(0, 0.4, -20), 80, V3(0, 0, -20))

	-- ponts diagonaux vers les 4 zones (Y = 14)
	for _, d in { { 1, -1 }, { 1, 1 }, { -1, 1 }, { -1, -1 } } do
		local a = V3(d[1] * (R - 1), H, d[2] * (R - 1))
		local b = V3(d[1] * 61, H, d[2] * 61)
		local br = slab(z, a, b, 5, PAL.Bridge, 1, "Pont")
		_ = br
		local side = (b - a).Unit:Cross(V3(0, 1, 0)) * 2.5
		railing(z, a + side + (b - a).Unit * 3, b + side - (b - a).Unit * 3, PAL.White)
		railing(z, a - side + (b - a).Unit * 3, b - side - (b - a).Unit * 3, PAL.White)
		pillar(z, (a.X + b.X) / 2, (a.Z + b.Z) / 2, H - 1, 0.8, PAL.White)
	end

	-- déco : lampadaires, bancs, arbres en bacs
	for _, p in { { 24, 24 }, { -24, 24 }, { 24, -24 }, { -24, -24 } } do
		lamp(z, p[1], p[2], 0.4)
	end
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + math.pi / 8
		bench(z, math.cos(a) * 14.5, math.sin(a) * 14.5, -math.deg(a) + 90, 0.4)
	end
	for _, p in { { 10, 27 }, { -10, 27 }, { 10, -27 }, { -10, -27 } } do
		block(z, p[1], p[2], 5, 1.2, 5, RGB(160, 100, 60), 0.4, { Name = "Bac" })
		tree(z, p[1], p[2], 0.7, 1.6)
	end
	-- un tunnel de slide en raccourci sous l'anneau Nord (bloc décoratif "kiosque")
	slideBlock(z, V3(0, 0.4, -R + 0.5), 7, 14, 6.5, RGB(255, 170, 60), "Z")

	for _, p in { { 14, 20 }, { -14, 20 }, { 14, -20 }, { -14, -20 } } do
		spawnPoint(spawns, V3(p[1], 0.4, p[2]))
	end
	for _, p in { { 0, 45 }, { 0, -45 }, { 45, 0 }, { -45, 0 } } do
		spawnPoint(spawns, V3(p[1], 0, p[2]))
	end
	-- lampadaires des routes
	for i = -3, 3 do
		if i ~= 0 then
			lamp(z, i * 40, 37.5, 0)
			lamp(z, i * 40, -37.5, 0)
		end
	end
end

local function buildVillage(map, spawns)
	local z = folder(map, "Village")
	local H = MapBuilder.RingHeight
	local centers = { 69, 99, 129 }
	local S = 22
	local k = 0
	for ix, x in centers do
		for iz, zz0 in centers do
			k += 1
			local zc = -zz0
			local col = PAL.Houses[(k % #PAL.Houses) + 1]
			local house = Instance.new("Model")
			house.Name = "Maison" .. k
			house.Parent = z
			block(house, x, zc, S, H - 1, S, col, 0.4, { Name = "Murs" })
			local roofCol = PAL.Roofs[(k % #PAL.Roofs) + 1]
			block(house, x, zc, S + 1, 1, S + 1, roofCol, H - 0.6, { Name = "Toit" })
			-- porte + fenêtres décoratives (sans collision)
			for _, f in { { 0, S / 2 + 0.1 }, { 0, -S / 2 - 0.1 } } do
				part(house, V3(4, 6, 0.3), CF(x + f[1], 3.4, zc + f[2]), RGB(120, 70, 40), { Name = "Porte", CanCollide = false, NoStuds = true })
				for _, wx in { -7, 7 } do
					part(house, V3(3.5, 3, 0.3), CF(x + wx, 9, zc + f[2]), RGB(170, 230, 255),
						{ Name = "Fenetre", CanCollide = false, Material = Enum.Material.Glass, NoStuds = true, Transparency = 0.1 })
				end
			end
			-- cheminée (obstacle sur le toit) sur une maison sur deux
			if k % 2 == 0 then
				block(house, x + 6, zc - 6, 2.5, 4, 2.5, RGB(170, 80, 60), H + 0.4, { Name = "Cheminee" })
			end
			-- planches entre toits (certaines volontairement absentes : saut de 8 studs, faisable avec dash)
			if ix < 3 and not (ix == 2 and iz == 2) then
				slab(z, V3(x + S / 2, H + 0.4, zc), V3(x + 30 - S / 2, H + 0.4, zc), 4, PAL.Bridge, 0.8, "Planche")
			end
			if iz < 3 and not (ix == 1 and iz == 2) then
				slab(z, V3(x, H + 0.4, zc - S / 2), V3(x, H + 0.4, zc - 30 + S / 2), 4, PAL.Bridge, 0.8, "Planche")
			end
		end
	end
	-- rampes d'accès aux toits depuis le sol (côté route)
	slab(z, V3(58 - 26, 0, -99), V3(58 - 0.5, H + 0.4, -99), 6, PAL.PlazaAlt, 1, "RampeVillage")
	slab(z, V3(99, 0, -58 + 26), V3(99, H + 0.4, -58 + 0.5), 6, PAL.PlazaAlt, 1, "RampeVillage")
	-- jump pad dans une ruelle -> toits
	jumpPad(z, V3(84, 0.4, -114), 82, V3(0, 0, 0))
	-- tunnels de slide dans les ruelles (murets de jardin)
	slideBlock(z, V3(84, 0.4, -69), 2.5, 8, 6, RGB(240, 230, 210), "Z")
	slideBlock(z, V3(114, 0.4, -129), 2.5, 8, 6, RGB(240, 230, 210), "Z")
	slideBlock(z, V3(99, 0.4, -114), 2.5, 8, 6, RGB(240, 230, 210), "X")
	-- déco
	for _, p in { { 145, -84 }, { 145, -114 }, { 84, -146 }, { 114, -146 } } do
		tree(z, p[1], p[2], 0.8, 0.4)
	end
	for _, p in { { 66, -55 }, { 132, -55 }, { 55, -120 } } do
		lamp(z, p[1], p[2], 0.4)
	end
	spawnPoint(spawns, V3(84, 0.4, -99))
	spawnPoint(spawns, V3(129, 0.4, -114))
end

local function buildRooftops(map, spawns)
	local z = folder(map, "Toits")
	local S = 18
	-- { x, z, hauteur }
	local towers = {
		{ 69, 69, 14 }, { 99, 69, 20 }, { 129, 69, 26 },
		{ 69, 99, 20 }, { 99, 99, 14 }, { 129, 99, 32 },
		{ 69, 129, 8 }, { 99, 129, 14 }, { 129, 129, 20 },
	}
	for i, t in towers do
		local col = PAL.Towers[(i % #PAL.Towers) + 1]
		local m = Instance.new("Model")
		m.Name = "Tour" .. i
		m.Parent = z
		block(m, t[1], t[2], S, t[3] - 0.4, S, col, 0.4, { Name = "Tour" })
		block(m, t[1], t[2], S + 0.8, 0.6, S + 0.8, RGB(50, 54, 70), t[3] - 0.6, { Name = "Rebord" })
		-- néons verticaux aux coins
		for _, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
			neonStrip(m, V3(0.4, t[3] - 2, 0.4), CF(t[1] + c[1] * (S / 2 + 0.2), t[3] / 2, t[2] + c[2] * (S / 2 + 0.2)), if i % 2 == 0 then PAL.Neon1 else PAL.Neon2)
		end
		-- fenêtres néon
		for y = 4, t[3] - 3, 5 do
			neonStrip(m, V3(S - 4, 1.2, 0.2), CF(t[1], y, t[2] - S / 2 - 0.1), RGB(255, 240, 180))
		end
	end
	-- passerelles entre tours de même hauteur / jump pads entre niveaux
	slab(z, V3(78, 14, 69), V3(90, 14, 99), 4, PAL.Bridge, 0.8, "Passerelle")     -- 14 -> 14 (tour 1 -> tour 5)
	slab(z, V3(99, 14, 108), V3(99, 14, 120), 4, PAL.Bridge, 0.8, "Passerelle")   -- tour 5 -> tour 8
	slab(z, V3(78, 20, 99), V3(90, 20, 69), 4, PAL.Bridge, 0.8, "Passerelle")     -- tour 4 -> tour 2 (20)
	slab(z, V3(108, 20, 69), V3(120, 26, 69), 4, PAL.Bridge, 0.8, "Rampe")        -- tour 2 -> tour 3 (montée)
	slab(z, V3(129, 26, 78), V3(129, 32, 90), 4, PAL.Bridge, 0.8, "Rampe")        -- tour 3 -> tour 6 (sommet)
	slab(z, V3(108, 14, 129), V3(120, 20, 129), 4, PAL.Bridge, 0.8, "Rampe")      -- tour 8 -> tour 9
	jumpPad(z, V3(69, 14, 69), 70, V3(0, 0, 36))     -- tour 1 -> tour 4 (14 -> 20)
	jumpPad(z, V3(69, 8, 129), 85, V3(0, 0, -32))    -- tour 7 -> tour 4
	jumpPad(z, V3(99, 0.4, 84), 95, V3(0, 0, 10))     -- sol -> tour 5 (rue)
	-- rampes depuis le sol
	slab(z, V3(48, 0.4, 129), V3(59.5, 8, 129), 6, PAL.PlazaAlt, 1, "RampeSol")
	slab(z, V3(69, 0.4, 36), V3(69, 14, 59.5), 6, PAL.PlazaAlt, 1, "RampeSol")
	-- parcours de saut flottant (tour 9 -> tour 6)
	local steps = { V3(143, 22.5, 117), V3(144, 25, 111), V3(143, 27.5, 105), V3(144, 30, 99) }
	for i, p in steps do
		part(z, V3(3.5, 1, 3.5), CF(p), PAL.Towers[(i % #PAL.Towers) + 1], { Name = "Saut" .. i, Sides = false })
	end
	-- drapeau au sommet
	pillar(z, 129, 99, 10, 0.25, PAL.White, 32)
	part(z, V3(5, 3, 0.2), CF(131.6, 40.5, 99), PAL.Neon2, { Name = "Drapeau", NoStuds = true, CanCollide = false })
	-- tunnel de slide au sol entre deux tours
	slideBlock(z, V3(84, 0.4, 114), 12, 10, 7, RGB(90, 95, 120), "X")
	spawnPoint(spawns, V3(84, 0.4, 84))
	spawnPoint(spawns, V3(114, 0.4, 84))
end

local function buildIndustrial(map, spawns)
	local z = folder(map, "Industriel")
	local H = MapBuilder.RingHeight
	-- conteneurs (piles)
	local containers = {
		{ -60, 90, 0, "Z" }, { -60, 112, 0, "Z" }, { -78, 140, 0, "X" }, { -140, 60, 0, "Z" },
		{ -140, 85, 0, "Z" }, { -140, 85, 8.6, "Z" }, { -122, 140, 0, "X" }, { -122, 140, 8.6, "X" },
		{ -88, 92, 0, "X" }, { -112, 66, 0, "X" },
	}
	for i, c in containers do
		local col = PAL.Containers[(i % #PAL.Containers) + 1]
		local size = if c[4] == "Z" then V3(8, 8.6, 20) else V3(20, 8.6, 8)
		local p = part(z, size, CF(c[1], 0.4 + c[3] + 4.3, c[2]), col, { Name = "Conteneur" })
		-- nervures
		for s = -2, 2 do
			local off = if c[4] == "Z" then V3(4.05, 0, s * 4) else V3(s * 4, 0, 4.05)
			part(z, if c[4] == "Z" then V3(0.2, 8, 0.6) else V3(0.6, 8, 0.2), p.CFrame + off, col:Lerp(Color3.new(0, 0, 0), 0.25),
				{ Name = "Nervure", NoStuds = true, CanCollide = false })
		end
	end
	-- plateforme d'échafaudage reliée au pont (Y = 14)
	local function platform(x, zz, sx, sz)
		part(z, V3(sx, 1, sz), CF(x, H - 0.5, zz), PAL.Metal, { Name = "Plateforme", Sides = false })
		for _, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
			block(z, x + c[1] * (sx / 2 - 0.6), zz + c[2] * (sz / 2 - 0.6), 0.8, H - 1.4, 0.8, RGB(255, 190, 40), 0.4, { Name = "Poteau", NoStuds = true })
		end
	end
	platform(-64, 64, 14, 14)
	platform(-130, 64, 12, 12)
	platform(-64, 130, 12, 12)
	-- passerelles métalliques
	slab(z, V3(-71, H, 64), V3(-124, H, 64), 4, PAL.Metal, 0.8, "Passerelle")
	slab(z, V3(-64, H, 71), V3(-64, H, 124), 4, PAL.Metal, 0.8, "Passerelle")
	neonStrip(z, V3(53, 0.3, 0.3), CF(-97.5, H - 0.9, 66), RGB(255, 190, 40))
	neonStrip(z, V3(0.3, 0.3, 53), CF(-66, H - 0.9, 97.5), RGB(255, 190, 40))
	-- descentes
	slab(z, V3(-130, H, 70), V3(-130, 0.4, 96), 5, PAL.Metal, 1, "Escalier")
	slab(z, V3(-70, H, 130), V3(-96, 0.4, 130), 5, PAL.Metal, 1, "Escalier")
	-- gros tuyaux (obstacles qu'on saute)
	part(z, V3(30, 3, 3), CF(-112, 1.9, 128), RGB(200, 200, 210), { Name = "Tuyau", Shape = Enum.PartType.Cylinder, NoStuds = true })
	-- cheminées d'usine
	for _, p in { { -138, 138 }, { -138, 110 } } do
		pillar(z, p[1], p[2], 30, 2.5, RGB(190, 70, 60), 0.4)
		neonStrip(z, V3(5.4, 0.6, 5.4), CF(p[1], 24, p[2]), PAL.Neon1)
	end
	-- tunnels de slide (blocs-tuyaux) : vrais raccourcis entre allées
	slideBlock(z, V3(-100, 0.4, 82), 22, 11, 9, RGB(240, 130, 40), "X")
	slideBlock(z, V3(-82, 0.4, 112), 18, 11, 9, RGB(60, 140, 230), "Z")
	slideBlock(z, V3(-112, 0.4, 112), 16, 11, 7, RGB(120, 200, 80), "Z")
	-- jump pad vers la passerelle
	jumpPad(z, V3(-97, 0.4, 70), 80, V3(0, 0, -6))
	for _, p in { { -56, 56 }, { -146, 120 }, { -90, 146 } } do
		lamp(z, p[1], p[2], 0.4, RGB(255, 200, 120))
	end
	spawnPoint(spawns, V3(-80, 0.4, 76))
	spawnPoint(spawns, V3(-100, 0.4, 140))
end

local function buildGardens(map, spawns)
	local z = folder(map, "Jardins")
	local H = MapBuilder.RingHeight
	-- arbre géant avec plateforme reliée au pont (Y = 14)
	block(z, -64, -64, 5, H - 1, 5, PAL.Trunk, 0.4, { Name = "TroncGeant" })
	part(z, V3(16, 1, 16), CF(-64, H - 0.5, -64), RGB(160, 110, 60), { Name = "PlateformeArbre", Sides = false })
	for _, c in { { 6, 6 }, { -6, 6 }, { 6, -6 }, { -6, -6 } } do
		block(z, -64 + c[1], -64 + c[2], 7, 5, 7, PAL.Leaves, 21, { Name = "FeuillageGeant", Sides = true })
	end
	block(z, -64, -64, 10, 4, 10, PAL.GrassDark, 25.5, { Name = "FeuillageGeant" })
	slab(z, V3(-98, 0.4, -64), V3(-72, H, -64), 5, RGB(160, 110, 60), 1, "RampeArbre")
	-- haies (h = 6 : presque trop hautes pour sauter -> on les contourne)
	local hedges = {
		-- { x, z, sx, sz }
		{ -120, -90, 40, 3 }, { -76, -90, 20, 3 },             -- rangée 1 (trou en -95)
		{ -88, -115, 44, 3 }, { -138, -115, 14, 3 },           -- rangée 2 (trou en -125)
		{ -108, -132, 3, 26 },                                 -- verticale
		{ -76, -132, 3, 20 },
	}
	for _, h in hedges do
		block(z, h[1], h[2], h[3], 6, h[4], PAL.Hedge, 0.4, { Name = "Haie" })
	end
	-- haie avec trou de slide (raccourci)
	slideBlock(z, V3(-98, 0.4, -90), 3, 10, 6, PAL.Hedge, "Z")
	slideBlock(z, V3(-125, 0.4, -115), 3, 10, 6, PAL.Hedge, "Z")
	-- étang
	part(z, V3(0.6, 24, 24), CF(-125, 0.5, -132) * CFrame.Angles(0, 0, math.rad(90)), PAL.Water,
		{ Name = "Etang", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Glass, Transparency = 0.2, NoStuds = true })
	-- parterres de fleurs
	local flowers = { RGB(255, 80, 120), RGB(255, 220, 60), RGB(200, 100, 255), RGB(255, 140, 40) }
	for i = 0, 11 do
		local x = -140 + (i % 4) * 9
		local zz = -72 + math.floor(i / 4) * -5
		block(z, x, zz, 2, 1, 2, flowers[(i % #flowers) + 1], 0.4, { Name = "Fleur" })
	end
	for _, p in { { -140, -60 }, { -90, -140 }, { -58, -100 }, { -100, -72 }, { -92, -104 }, { -140, -100 } } do
		tree(z, p[1], p[2], 1, 0.4)
	end
	for _, p in { { -56, -56 }, { -146, -146 }, { -100, -56 } } do
		lamp(z, p[1], p[2], 0.4, RGB(200, 255, 180))
	end
	jumpPad(z, V3(-80, 0.4, -80), 80, V3(10, 0, 10))
	bench(z, -92, -128, 0, 0.4)
	bench(z, -92, -138, 180, 0.4)
	spawnPoint(spawns, V3(-120, 0.4, -100))
	spawnPoint(spawns, V3(-84, 0.4, -140))
end

-- =====================================================================
-- LOBBY
-- =====================================================================
function MapBuilder.BuildLobby(): Model
	local existing = workspace:FindFirstChild("Lobby")
	if existing then return existing end
	local L = MapBuilder.LobbyCenter
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
	local function at(x, y, zz) return CF(L.X + x, L.Y + y, L.Z + zz) end

	-- île
	part(lobby, V3(120, 4, 92), at(0, -2, 0), RGB(120, 210, 80), { Name = "Sol" })
	part(lobby, V3(124, 6, 96), at(0, -6.9, 0), RGB(150, 100, 60), { Name = "Terre", Sides = true })
	part(lobby, V3(16, 0.3, 92), at(0, 0.15, 0), RGB(242, 214, 160), { Name = "Allee", Sides = false })
	-- clôtures
	for _, f in { { V3(120, 2.5, 1), at(0, 1.25, -45.5) }, { V3(120, 2.5, 1), at(0, 1.25, 45.5) }, { V3(1, 2.5, 92), at(-59.5, 1.25, 0) }, { V3(1, 2.5, 92), at(59.5, 1.25, 0) } } do
		part(lobby, f[1], f[2], PAL.White, { Name = "Cloture" })
	end

	-- spawns du lobby (SpawnLocation neutres)
	local spawns = folder(lobby, "Spawns")
	for i, x in { -8, 0, 8 } do
		local s = Instance.new("SpawnLocation")
		s.Name = "LobbySpawn" .. i
		s.Anchored = true
		s.Neutral = true
		s.Duration = 0
		s.Size = V3(6, 1, 6)
		s.CFrame = at(x, 0.5, 30)
		s.Color = RGB(255, 210, 60)
		s.Material = Enum.Material.Plastic
		s.TopSurface = Enum.SurfaceType.Smooth
		studs(s, false)
		s.Parent = spawns
	end

	-- zone d'attente : cercle néon + bancs
	part(lobby, V3(0.4, 30, 30), at(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), RGB(255, 90, 120),
		{ Name = "ZoneAttente", Shape = Enum.PartType.Cylinder, NoStuds = true })
	part(lobby, V3(0.45, 26, 26), at(0, 0.22, 0) * CFrame.Angles(0, 0, math.rad(90)), RGB(255, 240, 200),
		{ Name = "ZoneAttenteCentre", Shape = Enum.PartType.Cylinder, NoStuds = true })
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		bench(lobby, L.X + math.cos(a) * 17, L.Z + math.sin(a) * 17, -math.deg(a) + 90, 0)
	end

	-- titre géant
	local _, tsg = sign(lobby, V3(44, 10, 1), at(0, 15, -42), Enum.NormalId.Back, 30)
	UI.StudPanel(tsg, { Size = UDim2.fromScale(1, 1), Gradient = "pink", Rotation = 25, Corner = 0 })
	UI.ShadowText(tsg, "TAIL CHASE", { Size = UDim2.fromScale(0.95, 0.8), Max = 230, Stroke = RGB(40, 4, 30), Thickness = 8, Offset = 8, Font = "Gotham", ZIndex = 20 })
	pillar(lobby, L.X - 18, L.Z - 42, 10, 0.8, PAL.White, 0)
	pillar(lobby, L.X + 18, L.Z - 42, 10, 0.8, PAL.White, 0)

	-- panneau "comment jouer"
	local _, hsg = sign(lobby, V3(18, 14, 1), at(-22, 7.5, -36), Enum.NormalId.Back, 40)
	local panel = UI.StudPanel(hsg, { Size = UDim2.new(1, 0, 0, 90), Gradient = "blue", Corner = 0 })
	UI.ShadowText(panel, "COMMENT JOUER", { Size = UDim2.fromScale(0.95, 0.8), Max = 60, Stroke = RGB(2, 30, 60), Thickness = 4, ZIndex = 20 })
	UI.Text(hsg, table.concat({
		"<font color=\"#5FB4FF\">PARTICIPANT</font> : garde ta queue le plus longtemps possible !",
		"<font color=\"#FF3A4A\">CHASSEUR</font> : touche un participant pour lui arracher sa queue. Il devient chasseur à son tour.",
		"<font color=\"#FFD23F\">DASH</font> : Q / Shift  -  <font color=\"#FFD23F\">SLIDE</font> : C / Ctrl (passe dans les tunnels)",
		"Pièces : survie, queues prises, participation et bonus du dernier survivant.",
	}, "\n\n"), { Size = UDim2.new(1, -40, 1, -110), Position = UDim2.new(0.5, 0, 0, 100), AnchorPoint = Vector2.new(0.5, 0), Max = 34, Rich = true,
		Font = "Bold", AlignX = Enum.TextXAlignment.Left, AlignY = Enum.TextYAlignment.Top, Thickness = 3 })

	-- leaderboard (rempli par DataService)
	local board, lsg = sign(lobby, V3(18, 14, 1), at(22, 7.5, -36), Enum.NormalId.Back, 40)
	board.Name = "Leaderboard"
	CollectionService:AddTag(board, "LeaderboardBoard")
	local lpanel = UI.StudPanel(lsg, { Size = UDim2.new(1, 0, 0, 90), Gradient = "gold", Corner = 0 })
	UI.ShadowText(lpanel, "TOP QUEUES PRISES", { Size = UDim2.fromScale(0.95, 0.8), Max = 58, Stroke = RGB(70, 34, 0), Thickness = 4, ZIndex = 20 })
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Size = UDim2.new(1, -40, 1, -110)
	rows.Position = UDim2.new(0.5, 0, 0, 100)
	rows.AnchorPoint = Vector2.new(0.5, 0)
	rows.Parent = lsg
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = rows

	-- stand du shop (côté Ouest, face à l'Est)
	local shop = Instance.new("Model")
	shop.Name = "ShopStand"
	shop.Parent = lobby
	part(shop, V3(6, 3.2, 14), at(-44, 1.6, 4), RGB(255, 70, 90), { Name = "Comptoir" })
	part(shop, V3(7, 0.6, 15), at(-44, 3.5, 4), PAL.White, { Name = "Plateau" })
	for i = 0, 6 do
		part(shop, V3(9, 0.5, 2), at(-45, 10.5 - (i % 2) * 0.01, -2 + i * 2) * CFrame.Angles(0, 0, math.rad(-12)),
			if i % 2 == 0 then RGB(255, 60, 80) else PAL.White, { Name = "Auvent", NoStuds = true })
	end
	for _, zz in { -3, 11 } do
		block(shop, L.X - 48, L.Z + zz, 1, 10, 1, PAL.White, 0, { Name = "Poteau", NoStuds = true })
	end
	local _, ssg = sign(shop, V3(1, 4, 12), at(-48.5, 13, 4), Enum.NormalId.Right, 40)
	UI.StudPanel(ssg, { Size = UDim2.fromScale(1, 1), Gradient = "magenta", Corner = 0 })
	UI.ShadowText(ssg, "SHOP", { Size = UDim2.fromScale(0.9, 0.85), Max = 140, Stroke = RGB(40, 0, 50), Thickness = 6, Offset = 5, ZIndex = 20, Font = "Gotham" })
	local promptPart = part(shop, V3(1, 1, 1), at(-40.5, 4.5, 4), RGB(255, 210, 60),
		{ Name = "ShopPrompt", Transparency = 1, CanCollide = false, NoStuds = true })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenShop"
	prompt.ActionText = "Ouvrir le shop"
	prompt.ObjectText = "Stand"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = promptPart
	MapBuilder.ShopPrompt = prompt

	-- petit parcours fun dans le lobby
	jumpPad(lobby, L + V3(44, 0, 20), 75, V3(0, 0, -10))
	for i, p in { V3(44, 12, 6), V3(48, 13, -4), V3(42, 14, -14), V3(48, 15, -24) } do
		part(lobby, V3(4, 1, 4), CF(L + p), PAL.Towers[(i % #PAL.Towers) + 1], { Name = "Saut" .. i, Sides = false })
	end

	-- déco
	for _, p in { { -52, -38 }, { 52, -38 }, { -52, 38 }, { 52, 38 }, { -30, 30 }, { 30, 30 } } do
		tree(lobby, L.X + p[1], L.Z + p[2], 0.9, 0)
	end
	for _, p in { { -10, 18 }, { 10, 18 }, { -10, -20 }, { 10, -20 } } do
		lamp(lobby, L.X + p[1], L.Z + p[2], 0)
	end

	lobby.Parent = workspace
	return lobby
end

-- =====================================================================
-- MAP
-- =====================================================================
function MapBuilder.BuildMap(): Model
	local existing = workspace:FindFirstChild("Map")
	if existing then return existing end
	local map = Instance.new("Model")
	map.Name = "Map"
	local spawns = folder(map, "Spawns")
	buildGround(map)
	buildPlaza(map, spawns)
	buildVillage(map, spawns)
	buildRooftops(map, spawns)
	buildIndustrial(map, spawns)
	buildGardens(map, spawns)
	map.Parent = workspace
	return map
end

function MapBuilder.SetupCollisionGroups()
	pcall(function() PhysicsService:RegisterCollisionGroup("SlideCeiling") end)
	pcall(function() PhysicsService:RegisterCollisionGroup("Sliders") end)
	PhysicsService:CollisionGroupSetCollidable("SlideCeiling", "Sliders", false)
end

function MapBuilder.SetupLighting()
	local Lighting = game:GetService("Lighting")
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local a = Instance.new("Atmosphere")
		a.Density = 0.28
		a.Haze = 1.2
		a.Color = RGB(255, 220, 190)
		a.Decay = RGB(255, 170, 120)
		a.Glare = 0.4
		a.Parent = Lighting
	end
	if not Lighting:FindFirstChild("TC_Bloom") then
		local b = Instance.new("BloomEffect")
		b.Name = "TC_Bloom"
		b.Intensity = 0.6
		b.Size = 28
		b.Threshold = 1.6
		b.Parent = Lighting
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "TC_Couleurs"
		cc.Saturation = 0.18
		cc.Contrast = 0.06
		cc.TintColor = RGB(255, 246, 236)
		cc.Parent = Lighting
		local sun = Instance.new("SunRaysEffect")
		sun.Intensity = 0.06
		sun.Parent = Lighting
	end
end

function MapBuilder.Build()
	MapBuilder.SetupCollisionGroups()
	MapBuilder.SetupLighting()
	local map = MapBuilder.BuildMap()
	local lobby = MapBuilder.BuildLobby()
	-- les plafonds d'une map réutilisée doivent aussi être dans le bon groupe
	for _, p in CollectionService:GetTagged("SlideCeiling") do
		if p:IsA("BasePart") then p.CollisionGroup = "SlideCeiling" end
	end
	if not MapBuilder.ShopPrompt then
		MapBuilder.ShopPrompt = lobby:FindFirstChild("OpenShop", true)
	end
	return map, lobby
end

function MapBuilder.GetMapSpawns(): { BasePart }
	local map = workspace:FindFirstChild("Map")
	local list = {}
	if map and map:FindFirstChild("Spawns") then
		for _, s in map.Spawns:GetChildren() do
			if s:IsA("BasePart") then table.insert(list, s) end
		end
	end
	return list
end

function MapBuilder.GetLobbySpawn(): CFrame
	local lobby = workspace:FindFirstChild("Lobby")
	local spawns = lobby and lobby:FindFirstChild("Spawns")
	if spawns then
		local all = spawns:GetChildren()
		if #all > 0 then
			local s = all[math.random(1, #all)] :: BasePart
			return s.CFrame + Vector3.new(0, 3.5, 0)
		end
	end
	return CFrame.new(MapBuilder.LobbyCenter + Vector3.new(0, 5, 30))
end

return MapBuilder
