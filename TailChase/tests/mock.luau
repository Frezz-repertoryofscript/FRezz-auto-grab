--!nonstrict
-- Mini mock de l'API Roblox pour exécuter les builders hors Studio (tests de non-crash).
local M = {}
local LOG = {}
M.LOG = LOG

-- ------------------------------------------------------------------ signals
local function Signal()
	local s = { conns = {} }
	function s:Connect(fn) local c = { fn = fn, Connected = true }; table.insert(self.conns, c); c.Disconnect = function() c.Connected = false end; return c end
	s.Once = s.Connect
	function s:Fire(...) for _, c in self.conns do if c.Connected then local co = coroutine.create(c.fn); local ok, err = coroutine.resume(co, ...); if not ok then error(debug.traceback(co, err), 0) end end end end
	function s:Wait() return coroutine.yield() end
	return s
end
M.Signal = Signal

M.typeof = function(v)
	local mt = getmetatable(v)
	if type(mt) == "table" and mt.__type then return mt.__type end
	return type(v)
end
-- ------------------------------------------------------------------ datatypes
local V3mt = {}
local function V3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3mt) end
V3mt.__add = function(a, b) return V3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3mt.__sub = function(a, b) return V3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3mt.__mul = function(a, b)
	if type(a) == "number" then a, b = b, a end
	if type(b) == "number" then return V3(a.X * b, a.Y * b, a.Z * b) end
	return V3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b) if type(b) == "number" then return V3(a.X / b, a.Y / b, a.Z / b) end return V3(a.X / b.X, a.Y / b.Y, a.Z / b.Z) end
V3mt.__unm = function(a) return V3(-a.X, -a.Y, -a.Z) end
V3mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3mt.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2) end
	if k == "Unit" then local m = math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2); if m == 0 then return V3(0, 0, 0) end return V3(v.X / m, v.Y / m, v.Z / m) end
	if k == "Cross" then return function(a, b) return V3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end end
	if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
	if k == "Lerp" then return function(a, b, t) return a + (b - a) * t end end
	error("Vector3." .. tostring(k) .. " inconnu", 2)
end
V3mt.__type = "Vector3"
M.Vector3 = { new = V3, zero = V3(0, 0, 0), one = V3(1, 1, 1), xAxis = V3(1, 0, 0), yAxis = V3(0, 1, 0) }

local V2mt = {}
local function V2(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2mt) end
V2mt.__add = function(a, b) return V2(a.X + b.X, a.Y + b.Y) end
V2mt.__sub = function(a, b) return V2(a.X - b.X, a.Y - b.Y) end
V2mt.__mul = function(a, b) if type(b) == "number" then return V2(a.X * b, a.Y * b) end return V2(a.X * b.X, a.Y * b.Y) end
V2mt.__index = function(v, k) if k == "Magnitude" then return math.sqrt(v.X ^ 2 + v.Y ^ 2) end error("Vector2." .. tostring(k), 2) end
V2mt.__type = "Vector2"
M.Vector2 = { new = V2, zero = V2(0, 0), one = V2(1, 1) }

local CFmt = {}
local function CF(pos) return setmetatable({ Position = pos or V3(), LookVector = V3(0, 0, -1), UpVector = V3(0, 1, 0), RightVector = V3(1, 0, 0) }, CFmt) end
CFmt.__mul = function(a, b)
	if getmetatable(b) == CFmt then return CF(a.Position + b.Position) end
	return a.Position + b -- Vector3
end
CFmt.__add = function(a, b) return CF(a.Position + b) end
CFmt.__sub = function(a, b) return CF(a.Position - b) end
CFmt.__index = function(c, k)
	if k == "Lerp" then return function(a, b, t) return CF(a.Position:Lerp(b.Position, t)) end end
	if k == "VectorToObjectSpace" or k == "VectorToWorldSpace" then return function(_, v) return v end end
	if k == "Inverse" then return function(a) return CF(-a.Position) end end
	if k == "X" then return c.Position.X elseif k == "Y" then return c.Position.Y elseif k == "Z" then return c.Position.Z end
	if k == "ToObjectSpace" then return function(a, b) return b end end
	error("CFrame." .. tostring(k), 2)
end
CFmt.__type = "CFrame"
M.CFrame = {
	new = function(x, y, z) if type(x) == "table" then return CF(x) end return CF(V3(x, y, z)) end,
	Angles = function() return CF(V3()) end,
	fromEulerAnglesXYZ = function() return CF(V3()) end,
	lookAt = function(a, b) return CF(a) end,
	identity = CF(V3()),
}

local UDmt = { __type = "UDim" }
local function UD(s, o) return setmetatable({ Scale = s or 0, Offset = o or 0 }, UDmt) end
UDmt.__add = function(a, b) return UD(a.Scale + b.Scale, a.Offset + b.Offset) end
M.UDim = { new = UD }
local U2mt = { __type = "UDim2" }
local function U2(a, b, c, d) return setmetatable({ X = UD(a, b), Y = UD(c, d), Width = UD(a, b), Height = UD(c, d) }, U2mt) end
U2mt.__add = function(a, b) return U2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset) end
U2mt.__sub = function(a, b) return U2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset) end
M.UDim2 = { new = U2, fromOffset = function(x, y) return U2(0, x or 0, 0, y or 0) end, fromScale = function(x, y) return U2(x or 0, 0, y or 0, 0) end }

local C3mt = { __type = "Color3" }
local function C3(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3mt) end
C3mt.__index = function(c, k)
	if k == "Lerp" then return function(a, b, t) return C3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end end
	if k == "ToHex" then return function() return "ffffff" end end
	error("Color3." .. tostring(k), 2)
end
M.Color3 = { new = C3, fromRGB = function(r, g, b) return C3(r / 255, g / 255, b / 255) end, fromHSV = function() return C3(1, 1, 1) end }

local function typed(t, name) return setmetatable(t, { __type = name }) end
M.ColorSequenceKeypoint = { new = function(t, c) assert(type(t) == "number" and c, "CSK"); return typed({ Time = t, Value = c }, "ColorSequenceKeypoint") end }
M.ColorSequence = { new = function(a, b)
	local kps
	if M.typeof(a) == "table" then kps = a; assert(#kps <= 20, ">20 keypoints"); assert(kps[1].Time == 0 and kps[#kps].Time == 1, "CS bornes")
	elseif b then kps = { { Time = 0, Value = a }, { Time = 1, Value = b } }
	else kps = { { Time = 0, Value = a }, { Time = 1, Value = a } } end
	return typed({ Keypoints = kps }, "ColorSequence") end }
M.NumberSequenceKeypoint = { new = function(t, v) return typed({ Time = t, Value = v }, "NumberSequenceKeypoint") end }
M.NumberSequence = { new = function(a, b) if type(a) == "table" then assert(#a <= 20, ">20 kp"); return typed({ Keypoints = a }, "NumberSequence") end return typed({ Keypoints = { a, b or a } }, "NumberSequence") end }
M.NumberRange = { new = function(a, b) return typed({ Min = a, Max = b or a }, "NumberRange") end }
M.Font = { new = function(f, w) return typed({ Family = f, Weight = w }, "Font") end }
M.TweenInfo = { new = function(...) return typed({ ... }, "TweenInfo") end }
M.Rect = { new = function(...) return typed({ ... }, "Rect") end }
M.RaycastParams = { new = function() return {} end }

-- Enum : Enum.A.B -> token unique
local enumCache = {}
M.Enum = setmetatable({}, { __index = function(_, cat)
	enumCache[cat] = enumCache[cat] or setmetatable({}, { __index = function(t, item)
		local v = setmetatable({ Name = item, EnumType = cat, Value = 1 }, { __type = "EnumItem", __tostring = function() return "Enum." .. cat .. "." .. item end })
		rawset(t, item, v); return v end })
	return enumCache[cat] end })

-- ------------------------------------------------------------------ instances
local ISA = {
	BasePart = { Part = 1, SpawnLocation = 1, WedgePart = 1, MeshPart = 1 },
	GuiObject = { Frame = 1, TextLabel = 1, TextButton = 1, ImageLabel = 1, ImageButton = 1, ScrollingFrame = 1, CanvasGroup = 1 },
	GuiButton = { TextButton = 1, ImageButton = 1 },
	LayerCollector = { ScreenGui = 1, SurfaceGui = 1, BillboardGui = 1 },
	Constraint = { LinearVelocity = 1 },
	JointInstance = { Weld = 1, Motor6D = 1 },
}
local EVENTS = { Activated = 1, MouseEnter = 1, MouseLeave = 1, MouseButton1Down = 1, MouseButton1Up = 1, MouseButton1Click = 1, Triggered = 1, Event = 1,
	Changed = 1, ChildAdded = 1, ChildRemoved = 1, AncestryChanged = 1, Touched = 1, Died = 1, CharacterAdded = 1, CharacterAppearanceLoaded = 1,
	OnClientEvent = 1, OnServerEvent = 1, Completed = 1, AnimationPlayed = 1, DescendantAdded = 1, PlayerAdded = 1, PlayerRemoving = 1,
	RenderStepped = 1, Heartbeat = 1, Stepped = 1, PreSimulation = 1, InputBegan = 1, InputEnded = 1, Destroying = 1 }

local Imt = {}
local count = { total = 0 }
M.count = count
local function newInstance(class)
	count.total += 1
	count[class] = (count[class] or 0) + 1
	local self = setmetatable({}, Imt)
	rawset(self, "__p", { Name = class, ClassName = class })
	rawset(self, "__c", {})
	rawset(self, "__a", {})
	rawset(self, "__e", {})
	rawset(self, "__ps", {})
	return self
end

local methods = {}
function methods:FindFirstChild(name, rec)
	for _, c in rawget(self, "__c") do if c.Name == name then return c end end
	if rec then for _, c in rawget(self, "__c") do local r = c:FindFirstChild(name, true); if r then return r end end end
	return nil
end
function methods:FindFirstChildOfClass(cls) for _, c in rawget(self, "__c") do if c.ClassName == cls then return c end end return nil end
function methods:FindFirstChildWhichIsA(cls) for _, c in rawget(self, "__c") do if c:IsA(cls) then return c end end return nil end
function methods:FindFirstAncestor(name) local p = self.Parent; while p do if p.Name == name then return p end p = p.Parent end return nil end
function methods:WaitForChild(name) local c = self:FindFirstChild(name); if not c then error("WaitForChild bloquerait: " .. name .. " dans " .. self.Name, 2) end return c end
function methods:GetChildren() return table.clone(rawget(self, "__c")) end
function methods:GetDescendants() local out = {}; for _, c in rawget(self, "__c") do table.insert(out, c); for _, d in c:GetDescendants() do table.insert(out, d) end end return out end
function methods:IsA(cls) local cn = rawget(self, "__p").ClassName; if cn == cls or cls == "Instance" then return true end local g = ISA[cls]; return g ~= nil and g[cn] ~= nil end
function methods:IsDescendantOf(x) local p = self.Parent; while p do if p == x then return true end p = p.Parent end return false end
function methods:SetAttribute(k, v) rawget(self, "__a")[k] = v; local s = rawget(self, "__e")["attr_" .. k]; if s then s:Fire() end end
function methods:GetAttribute(k) return rawget(self, "__a")[k] end
function methods:GetAttributeChangedSignal(k) local e = rawget(self, "__e"); e["attr_" .. k] = e["attr_" .. k] or Signal(); return e["attr_" .. k] end
function methods:GetPropertyChangedSignal(k) local e = rawget(self, "__e"); e["prop_" .. k] = e["prop_" .. k] or Signal(); return e["prop_" .. k] end
function methods:Destroy() self.Parent = nil end
function methods:ClearAllChildren() for _, c in self:GetChildren() do c:Destroy() end end
function methods:Clone() return newInstance(self.ClassName) end
function methods:GetFullName() local n = self.Name; local p = self.Parent; while p do n = p.Name .. "." .. n; p = p.Parent end return n end
function methods:PivotTo(cf) rawget(self, "__p").Pivot = cf end
function methods:GetPivot() return rawget(self, "__p").Pivot or M.CFrame.identity end
-- spécifiques
function methods:Play() end
function methods:Stop() end
function methods:Emit() end
function methods:Cancel() end
function methods:FireServer(...) table.insert(LOG, { "FireServer", self.Name, ... }) end
function methods:FireClient(...) end
function methods:FireAllClients(...) end
function methods:InvokeServer(...) local f = M.invokeHandlers[self.Name]; if f then return f(...) end return nil end
function methods:Fire(...) local s = self.Event; s:Fire(...) end
function methods:GetPlayingAnimationTracks() return {} end
function methods:ChangeState() end
function methods:GetState() return M.Enum.HumanoidStateType.Running end
function methods:LoadAnimation() return { Play = function() end, Stop = function() end } end
M.invokeHandlers = {}

Imt.__index = function(self, k)
	local p = rawget(self, "__p")
	local v = p[k]
	if v ~= nil then return v end
	if methods[k] then return methods[k] end
	for _, c in rawget(self, "__c") do if c.Name == k then return c end end
	if EVENTS[k] then local e = rawget(self, "__e"); e[k] = e[k] or Signal(); return e[k] end
	local d = M.defaults[k]
	if d ~= nil then return d end
	return nil
end
Imt.__newindex = function(self, k, v)
	local p = rawget(self, "__p")
	if k == "Parent" then
		local old = p.Parent
		if old then local cs = rawget(old, "__c"); for i, c in cs do if c == self then table.remove(cs, i); break end end end
		p.Parent = v
		if v then table.insert(rawget(v, "__c"), self); local s = rawget(v, "__e").ChildAdded; if s then s:Fire(self) end end
		return
	end
	if type(k) ~= "string" then error("clé invalide", 2) end
	if k:sub(1, 1):lower() == k:sub(1, 1) then error("propriété en minuscule suspecte: " .. k, 2) end
	p[k] = v
	local s = rawget(self, "__e")["prop_" .. k]
	if s then s:Fire() end
end
Imt.__type = "Instance"
Imt.__tostring = function(self) return rawget(self, "__p").Name end

-- valeurs par défaut lues sans avoir été écrites
M.defaults = { Size = V3(2, 2, 2), Position = V3(0, 3, 0), CFrame = CF(V3(0, 3, 0)), AssemblyLinearVelocity = V3(), Health = 100, MaxHealth = 100,
	WalkSpeed = 16, HipHeight = 2, MoveDirection = V3(), FloorMaterial = nil, FieldOfView = 70, ViewportSize = V2(1280, 720),
	Rotation = 0, Visible = true, Enabled = true, ZIndex = 1, Transparency = 0, Value = 0, Scale = 1, Text = "",
	TextColor3 = C3(1, 1, 1), ImageColor3 = C3(1, 1, 1), BackgroundColor3 = C3(1, 1, 1), Color = C3(1, 1, 1), Image = "", UserId = 1, DisplayName = "Testeur",
	AbsoluteSize = V2(100, 100), AbsolutePosition = V2(0, 0), TouchEnabled = true, KeyboardEnabled = false, Anchored = false }

M.Instance = { new = function(class, parent) local i = newInstance(class); if parent then i.Parent = parent end return i end }
M.newInstance = newInstance

-- typeof
M.typeof = function(v)
	local mt = getmetatable(v)
	if type(mt) == "table" and mt.__type then return mt.__type end
	return type(v)
end
return M
