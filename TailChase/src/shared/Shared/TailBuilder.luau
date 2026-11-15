--!strict
--[[
	TailBuilder - construit la "queue" (chasuble qui pend dans le dos) d'un participant.
	Partagé : le serveur l'attache aux personnages, le client s'en sert pour la queue qui vole vers le chasseur.

	Structure :
		Model "Tail" (Attribute Skin)
		 ├ Seg1 ... SegN   petites plaques souples (Massless, sans collision)
		 └ Weld "Joint" dans chaque segment (Part0 = segment précédent / torse) avec Attribute "BaseC0"
	Le balancement est procédural : EffectsController fait osciller le C0 de chaque Joint (purement visuel, local).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)

local TailBuilder = {}

local WIDTH, THICK = 1.15, 0.14

local function segmentColor(item: Cosmetics.Item, i: number, n: number): Color3
	local colors = item.Colors or { Color3.fromRGB(255, 120, 30) }
	local pattern = item.Pattern or "Solid"
	if pattern == "Stripes" or pattern == "Neon" then
		return colors[((i - 1) % #colors) + 1]
	elseif pattern == "Rainbow" then
		return colors[math.clamp(math.floor((i - 1) / math.max(n - 1, 1) * (#colors - 1) + 0.5) + 1, 1, #colors)]
	elseif pattern == "Flame" or pattern == "Gold" then
		local t = (i - 1) / math.max(n - 1, 1)
		local a = colors[1]
		local b = colors[#colors]
		return a:Lerp(b, t)
	end
	return colors[1]
end

local function studTexture(part: BasePart, face: Enum.NormalId)
	local tex = Instance.new("Texture")
	tex.Texture = Config.StudTexture
	tex.Face = face
	tex.StudsPerTileU = 1
	tex.StudsPerTileV = 1
	tex.Transparency = 0.55
	tex.Parent = part
end

--- Construit les segments ; si `anchorTo` est fourni, le premier segment y est soudé (dans le dos).
function TailBuilder.Build(skinId: string?, anchorTo: BasePart?): Model
	local item = Cosmetics.Get(skinId) or Cosmetics.Get(Cosmetics.DefaultFor("Tail")) :: Cosmetics.Item
	local n = Config.TailSegments
	local L = Config.TailSegmentLength
	local model = Instance.new("Model")
	model.Name = "Tail"
	model:SetAttribute("Skin", item.Id)

	local prev: BasePart? = anchorTo
	for i = 1, n do
		local seg = Instance.new("Part")
		seg.Name = "Seg" .. i
		-- la queue s'affine vers le bout
		local w = WIDTH * (1 - (i - 1) / n * 0.35)
		seg.Size = Vector3.new(w, L, THICK)
		seg.Material = item.Material or Enum.Material.SmoothPlastic
		seg.Color = segmentColor(item, i, n)
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CanTouch = false
		seg.Massless = true
		seg.CastShadow = false
		seg.TopSurface = Enum.SurfaceType.Smooth
		seg.BottomSurface = Enum.SurfaceType.Smooth
		studTexture(seg, Enum.NormalId.Back)
		studTexture(seg, Enum.NormalId.Front)
		seg.Parent = model

		if prev then
			local joint = Instance.new("Weld")
			joint.Name = "Joint"
			joint.Part0 = prev
			joint.Part1 = seg
			local c0: CFrame
			if i == 1 and anchorTo then
				-- dos du torse (+Z local = arrière), un peu en dessous du milieu, incliné vers l'arrière
				c0 = CFrame.new(0, -anchorTo.Size.Y * 0.2, anchorTo.Size.Z / 2 + THICK / 2 + 0.02) * CFrame.Angles(math.rad(-12), 0, 0)
			else
				c0 = CFrame.new(0, -L / 2, 0) * CFrame.Angles(math.rad(-6), 0, 0)
			end
			joint.C0 = c0
			joint.C1 = CFrame.new(0, L / 2, 0)
			joint:SetAttribute("BaseC0", c0)
			joint:SetAttribute("Index", i)
			joint.Parent = seg
		end
		prev = seg
	end

	-- décorations selon le motif
	local last = model:FindFirstChild("Seg" .. n) :: BasePart
	local pattern = item.Pattern
	if pattern == "Flame" then
		local fire = Instance.new("Fire")
		fire.Size = 3
		fire.Heat = 4
		fire.Color = Color3.fromRGB(255, 140, 0)
		fire.SecondaryColor = Color3.fromRGB(255, 40, 0)
		fire.Parent = last
	elseif pattern == "Gold" then
		local sp = Instance.new("Sparkles")
		sp.SparkleColor = Color3.fromRGB(255, 220, 90)
		sp.Parent = last
	elseif pattern == "Neon" then
		local light = Instance.new("PointLight")
		light.Color = (item.Colors or {})[1] or Color3.new(0, 1, 1)
		light.Range = 8
		light.Brightness = 2
		light.Parent = last
	end
	return model
end

--- Torse sur lequel accrocher la queue (R15 : UpperTorso, R6 : Torso).
function TailBuilder.TorsoOf(character: Model): BasePart?
	return (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
end

function TailBuilder.Attach(character: Model, skinId: string?): Model?
	TailBuilder.Remove(character)
	local torso = TailBuilder.TorsoOf(character)
	if not torso then return nil end
	local tail = TailBuilder.Build(skinId, torso)
	tail.Parent = character
	return tail
end

function TailBuilder.Remove(character: Model)
	local old = character:FindFirstChild("Tail")
	if old then old:Destroy() end
end

return TailBuilder
