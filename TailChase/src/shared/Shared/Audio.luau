--[[
	Audio - lecture des sons définis dans Config.Sounds (client).
	Les IDs qui commencent par "PLACEHOLDER_" sont ignorés sans erreur (à renseigner plus tard).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local Config = require(ReplicatedStorage.Shared.Config)

local Audio = {}

local function valid(def): boolean
	return def ~= nil and type(def.Id) == "string" and def.Id ~= "" and not def.Id:find("^PLACEHOLDER")
end

--- Joue un son une fois. `parent` = BasePart/Attachment pour un son 3D, nil pour un son 2D.
function Audio.Play(name: string, parent: Instance?, pitchJitter: number?): Sound?
	local def = Config.Sounds[name]
	if not valid(def) then return nil end
	local s = Instance.new("Sound")
	s.Name = "SFX_" .. name
	s.SoundId = def.Id
	s.Volume = def.Volume or 0.5
	local j = pitchJitter or 0
	s.PlaybackSpeed = (def.Pitch or 1) * (1 + (math.random() * 2 - 1) * j)
	s.RollOffMaxDistance = 120
	s.Parent = parent or SoundService
	s:Play()
	Debris:AddItem(s, 6)
	return s
end

--- Musique en boucle (une seule à la fois). name = nil coupe la musique.
local current: Sound? = nil
local currentName: string? = nil
function Audio.Music(name: string?)
	if name == currentName then return end
	currentName = name
	if current then
		local old = current
		current = nil
		task.spawn(function()
			for i = 10, 0, -1 do
				old.Volume = old.Volume * 0.8
				task.wait(0.05)
			end
			old:Destroy()
		end)
	end
	if not name then return end
	local def = Config.Sounds[name]
	if not valid(def) then return end
	local s = Instance.new("Sound")
	s.Name = "Music_" .. name
	s.SoundId = def.Id
	s.Looped = true
	s.Volume = def.Volume or 0.3
	s.Parent = SoundService
	s:Play()
	current = s
end

return Audio
