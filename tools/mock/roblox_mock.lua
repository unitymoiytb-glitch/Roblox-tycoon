-- Minimal Roblox API mock so the game's Luau can run headlessly under the `luau` CLI.
-- Only what the project uses is implemented; the math types (Vector3/CFrame) are exact.
local mock = {}

local typeTags = {}
local realTypeof = typeof
function typeof(v)
    local mt = getmetatable(v)
    if type(mt) == "table" and typeTags[mt] then return typeTags[mt] end
    return realTypeof(v)
end

-- ------------------------------------------------------------------ Vector3
local V3mt = {}
typeTags[V3mt] = "Vector3"
local function V3(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, V3mt) end
V3mt.__index = function(v, k)
    if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
    if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) return m > 0 and V3(v.X / m, v.Y / m, v.Z / m) or V3(0, 0, 0) end
    if k == "Lerp" then return function(a, b, t) return V3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end end
    if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
    if k == "Cross" then return function(a, b) return V3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end end
    return nil
end
V3mt.__add = function(a, b) return V3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3mt.__sub = function(a, b) return V3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3mt.__unm = function(a) return V3(-a.X, -a.Y, -a.Z) end
V3mt.__mul = function(a, b)
    if type(a) == "number" then return V3(b.X * a, b.Y * a, b.Z * a) end
    if type(b) == "number" then return V3(a.X * b, a.Y * b, a.Z * b) end
    return V3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
    if type(b) == "number" then return V3(a.X / b, a.Y / b, a.Z / b) end
    return V3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3mt.__tostring = function(v) return string.format("%.3f, %.3f, %.3f", v.X, v.Y, v.Z) end
Vector3 = {new = V3, zero = V3(0, 0, 0), one = V3(1, 1, 1), xAxis = V3(1, 0, 0), yAxis = V3(0, 1, 0), zAxis = V3(0, 0, 1)}
Vector2 = {new = function(x, y) return {X = x or 0, Y = y or 0} end}

-- ------------------------------------------------------------------ CFrame
local CFmt = {}
typeTags[CFmt] = "CFrame"
local function mkCF(px, py, pz, r)
    return setmetatable({px = px, py = py, pz = pz, r = r}, CFmt)
end
local ID = {1, 0, 0, 0, 1, 0, 0, 0, 1}
local function matmul(a, b)
    local r = {}
    for i = 0, 2 do
        for j = 0, 2 do
            r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
        end
    end
    return r
end
local function matvec(a, x, y, z)
    return a[1] * x + a[2] * y + a[3] * z, a[4] * x + a[5] * y + a[6] * z, a[7] * x + a[8] * y + a[9] * z
end
CFmt.__index = function(cf, k)
    local r = cf.r
    if k == "Position" or k == "p" then return V3(cf.px, cf.py, cf.pz) end
    if k == "X" then return cf.px end
    if k == "Y" then return cf.py end
    if k == "Z" then return cf.pz end
    if k == "LookVector" then return V3(-r[3], -r[6], -r[9]) end
    if k == "RightVector" then return V3(r[1], r[4], r[7]) end
    if k == "UpVector" then return V3(r[2], r[5], r[8]) end
    if k == "Rotation" then return mkCF(0, 0, 0, r) end
    if k == "Inverse" then
        return function(c)
            local t = {c.r[1], c.r[4], c.r[7], c.r[2], c.r[5], c.r[8], c.r[3], c.r[6], c.r[9]}
            local x, y, z = matvec(t, -c.px, -c.py, -c.pz)
            return mkCF(x, y, z, t)
        end
    end
    if k == "ToObjectSpace" then return function(c, o) return c:Inverse() * o end end
    if k == "ToWorldSpace" then return function(c, o) return c * o end end
    if k == "PointToObjectSpace" then return function(c, v) return c:Inverse() * v end end
    if k == "PointToWorldSpace" then return function(c, v) return c * v end end
    if k == "GetComponents" then return function(c) return c.px, c.py, c.pz, table.unpack(c.r) end end
    return nil
end
CFmt.__mul = function(a, b)
    if getmetatable(b) == V3mt then
        local x, y, z = matvec(a.r, b.X, b.Y, b.Z)
        return V3(x + a.px, y + a.py, z + a.pz)
    end
    local x, y, z = matvec(a.r, b.px, b.py, b.pz)
    return mkCF(x + a.px, y + a.py, z + a.pz, matmul(a.r, b.r))
end
CFmt.__add = function(a, v) return mkCF(a.px + v.X, a.py + v.Y, a.pz + v.Z, a.r) end
CFmt.__sub = function(a, v) return mkCF(a.px - v.X, a.py - v.Y, a.pz - v.Z, a.r) end
CFmt.__tostring = function(c) return string.format("CF(%.2f,%.2f,%.2f)", c.px, c.py, c.pz) end

local function rx(a) local c, s = math.cos(a), math.sin(a) return {1, 0, 0, 0, c, -s, 0, s, c} end
local function ry(a) local c, s = math.cos(a), math.sin(a) return {c, 0, s, 0, 1, 0, -s, 0, c} end
local function rz(a) local c, s = math.cos(a), math.sin(a) return {c, -s, 0, s, c, 0, 0, 0, 1} end
local function lookAt(eye, target, up)
    up = up or V3(0, 1, 0)
    local f = (target - eye).Unit
    local rgt = f:Cross(up)
    if rgt.Magnitude < 1e-6 then rgt = V3(1, 0, 0) end
    rgt = rgt.Unit
    local u = rgt:Cross(f)
    local b = -f
    return mkCF(eye.X, eye.Y, eye.Z, {rgt.X, u.X, b.X, rgt.Y, u.Y, b.Y, rgt.Z, u.Z, b.Z})
end
CFrame = {
    new = function(a, b, c, ...)
        if a == nil then return mkCF(0, 0, 0, ID) end
        if type(a) == "number" then
            local extra = {...}
            if #extra == 9 then return mkCF(a, b, c, extra) end
            return mkCF(a, b, c, ID)
        end
        if b ~= nil then return lookAt(a, b) end
        return mkCF(a.X, a.Y, a.Z, ID)
    end,
    Angles = function(x, y, z) return mkCF(0, 0, 0, matmul(matmul(rx(x), ry(y)), rz(z))) end,
    fromOrientation = function(x, y, z) return mkCF(0, 0, 0, matmul(matmul(ry(y), rx(x)), rz(z))) end,
    lookAt = lookAt,
}
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFrame.identity = CFrame.new()

-- ------------------------------------------------------------------ Color3 / UDim2
local C3mt = {}
typeTags[C3mt] = "Color3"
local function C3(r, g, b) return setmetatable({R = r, G = g, B = b}, C3mt) end
C3mt.__index = function(c, k)
    if k == "Lerp" then return function(a, b, t) return C3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end end
    return nil
end
Color3 = {
    new = function(r, g, b) return C3(r or 0, g or 0, b or 0) end,
    fromRGB = function(r, g, b) return C3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end,
    fromHSV = function(h, s, v) return C3(v, v, v) end,
}
local function udim2(...) return {kind = "UDim2", ...} end
UDim2 = {new = udim2, fromScale = udim2, fromOffset = udim2}
UDim = {new = function(...) return {...} end}
TweenInfo = {new = function(...) return {...} end}
NumberSequence = {new = function(...) return {...} end}
ColorSequence = {new = function(...) return {...} end}

-- ------------------------------------------------------------------ Enum
local function enumItem(t, n) return setmetatable({EnumType = t, Name = n}, {__tostring = function() return "Enum." .. t .. "." .. n end}) end
Enum = setmetatable({}, {__index = function(_, t)
    local cache = {}
    return setmetatable({}, {__index = function(_, n)
        cache[n] = cache[n] or enumItem(t, n)
        return cache[n]
    end})
end})
do -- stable identity for Enum items
    local types = {}
    Enum = setmetatable({}, {__index = function(_, t)
        if not types[t] then
            local items = {}
            types[t] = setmetatable({}, {__index = function(_, n) items[n] = items[n] or enumItem(t, n) return items[n] end})
        end
        return types[t]
    end})
end

-- ------------------------------------------------------------------ Random (deterministic xorshift)
local RandomMt = {}
RandomMt.__index = RandomMt
function RandomMt:NextNumber(a, b)
    local x = self.s
    x = bit32.bxor(x, bit32.lshift(x, 13))
    x = bit32.bxor(x, bit32.rshift(x, 17))
    x = bit32.bxor(x, bit32.lshift(x, 5))
    self.s = x
    local f = x / 4294967296
    if a then return a + (b - a) * f end
    return f
end
function RandomMt:NextInteger(a, b) return math.min(b, a + math.floor(self:NextNumber() * (b - a + 1))) end
Random = {new = function(seed) seed = math.floor(seed or 1) % 4294967295 if seed == 0 then seed = 2463534242 end return setmetatable({s = seed}, RandomMt) end}

-- ------------------------------------------------------------------ signals
local SigMt = {}
SigMt.__index = SigMt
function SigMt:Connect(fn) table.insert(self.handlers, fn) return {Disconnect = function() end, Connected = true} end
function SigMt:Once(fn) return self:Connect(fn) end
function SigMt:Fire(...) for _, h in ipairs(self.handlers) do h(...) end end
function SigMt:Wait() return 1 / 60 end
local function Signal() return setmetatable({handlers = {}}, SigMt) end
mock.Signal = Signal

-- ------------------------------------------------------------------ Instances
local isA = {
    Part = {"Part", "BasePart", "PVInstance", "Instance"},
    WedgePart = {"WedgePart", "BasePart", "PVInstance", "Instance"},
    SpawnLocation = {"SpawnLocation", "Part", "BasePart", "PVInstance", "Instance"},
    Model = {"Model", "PVInstance", "Instance"},
    Workspace = {"Workspace", "Model", "Instance"},
    Folder = {"Folder", "Instance"},
    RemoteEvent = {"RemoteEvent", "Instance"},
    UnreliableRemoteEvent = {"UnreliableRemoteEvent", "Instance"},
    Sound = {"Sound", "Instance"},
    ScreenGui = {"ScreenGui", "LayerCollector", "GuiBase2d", "Instance"},
    Frame = {"Frame", "GuiObject", "Instance"},
    TextLabel = {"TextLabel", "GuiObject", "Instance"},
    TextButton = {"TextButton", "GuiButton", "GuiObject", "Instance"},
    BillboardGui = {"BillboardGui", "LayerCollector", "Instance"},
    SurfaceGui = {"SurfaceGui", "LayerCollector", "Instance"},
}
local InstMt = {}
typeTags[InstMt] = "Instance"
mock.allInstances = {}
local methods = {}
local eventNames = {Touched = true, Triggered = true, OnServerEvent = true, OnClientEvent = true, MouseButton1Click = true, ChildAdded = true, Changed = true, Completed = true, CharacterAdded = true, Died = true, CharacterRemoving = true, CharacterAppearanceLoaded = true}

local function newInstance(class)
    local inst = setmetatable({__props = {ClassName = class, Name = class, __children = {}, __attrs = {}}}, InstMt)
    local p = inst.__props
    if isA[class] and table.find(isA[class], "BasePart") then
        p.Anchored = false p.CanCollide = true p.CanTouch = true p.CanQuery = true p.CastShadow = true
        p.Transparency = 0 p.Size = V3(4, 1, 2) p.CFrame = CFrame.new() p.Reflectance = 0 p.LocalTransparencyModifier = 0
        p.Massless = false p.Color = Color3.fromRGB(163, 162, 165) p.Material = Enum.Material.Plastic
    end
    table.insert(mock.allInstances, inst)
    return inst
end
InstMt.__index = function(inst, k)
    local p = rawget(inst, "__props")
    if methods[k] then return methods[k] end
    if k == "Position" and p.CFrame then return p.CFrame.Position end
    if k == "Parent" then return p.Parent end
    local v = p[k]
    if v ~= nil then return v end
    if eventNames[k] then p[k] = Signal() return p[k] end
    local child = methods.FindFirstChild(inst, k)
    if child then return child end
    return nil
end
InstMt.__newindex = function(inst, k, v)
    local p = rawget(inst, "__props")
    if k == "Parent" then
        if p.Parent then
            local ch = p.Parent.__props.__children
            local i = table.find(ch, inst)
            if i then table.remove(ch, i) end
        end
        p.Parent = v
        if v then table.insert(v.__props.__children, inst) end
        return
    end
    if k == "Position" then
        local cf = p.CFrame or CFrame.new()
        p.CFrame = mkCF(v.X, v.Y, v.Z, cf.r)
        return
    end
    p[k] = v
end
InstMt.__tostring = function(inst) return inst.__props.Name end

function methods.IsA(inst, c) local l = isA[inst.__props.ClassName] return (l and table.find(l, c) ~= nil) or inst.__props.ClassName == c or c == "Instance" end
function methods.GetChildren(inst) return table.clone(inst.__props.__children) end
function methods.GetDescendants(inst)
    local out = {}
    local function rec(i) for _, c in ipairs(i.__props.__children) do table.insert(out, c) rec(c) end end
    rec(inst)
    return out
end
function methods.FindFirstChild(inst, name, recursive)
    for _, c in ipairs(inst.__props.__children) do if c.__props.Name == name then return c end end
    if recursive then for _, c in ipairs(inst.__props.__children) do local f = methods.FindFirstChild(c, name, true) if f then return f end end end
    return nil
end
function methods.FindFirstChildOfClass(inst, class)
    for _, c in ipairs(inst.__props.__children) do if c.__props.ClassName == class then return c end end
    return nil
end
function methods.FindFirstChildWhichIsA(inst, class)
    for _, c in ipairs(inst.__props.__children) do if methods.IsA(c, class) then return c end end
    return nil
end
function methods.FindFirstAncestorOfClass(inst, class)
    local p = inst.__props.Parent
    while p do if p.__props.ClassName == class then return p end p = p.__props.Parent end
    return nil
end
function methods.WaitForChild(inst, name) return methods.FindFirstChild(inst, name) end
function methods.Destroy(inst) inst.Parent = nil inst.__props.__destroyed = true end
function methods.Clone(inst) return inst end
function methods.SetAttribute(inst, k, v) inst.__props.__attrs[k] = v end
function methods.GetAttribute(inst, k) return inst.__props.__attrs[k] end
function methods.GetPivot(inst)
    if inst.__props.PrimaryPart then return inst.__props.PrimaryPart.CFrame end
    return inst.__props.CFrame or CFrame.new()
end
function methods.PivotTo(inst, cf)
    local pp = inst.__props.PrimaryPart
    if not pp then
        if inst.__props.CFrame then inst.__props.CFrame = cf end
        return
    end
    local inv = pp.CFrame:Inverse()
    for _, d in ipairs(methods.GetDescendants(inst)) do
        if methods.IsA(d, "BasePart") then d.__props.CFrame = cf * (inv * d.__props.CFrame) end
    end
end
function methods.Play() end
function methods.Stop() end
function methods.Connect() end
function methods.FireClient(inst, ...) if inst.__onFireClient then inst.__onFireClient(...) end end
function methods.FireServer(inst, ...) if inst.__onFireServer then inst.__onFireServer(...) end end
function methods.FireAllClients() end
function methods.GetPlayers() return mock.players end
function methods.GetPlayerFromCharacter(_, char) for _, p in ipairs(mock.players) do if p.Character == char then return p end end return nil end
function methods.GetPlayerByUserId() return nil end
function methods.BulkMoveTo(_, parts, cfs)
    mock.bulkMoves = (mock.bulkMoves or 0) + 1
    assert(#parts == #cfs, "BulkMoveTo arrays differ in length")
    for i, p in ipairs(parts) do p.__props.CFrame = cfs[i] end
end
function methods.GetDataStore() error("DataStore unavailable (mock)") end
function methods.UserOwnsGamePassAsync() return false end
function methods.Create() return {Play = function() end, Completed = Signal()} end
function methods.GetServerTimeNow() return mock.serverTimeFn and mock.serverTimeFn() or os.clock() end
function methods.GetSunDirection() return V3(0, 1, 0) end

Instance = {new = function(class, parent)
    local i = newInstance(class)
    if parent then i.Parent = parent end
    return i
end}

-- ------------------------------------------------------------------ services & globals
mock.players = {}
workspace = newInstance("Workspace") workspace.Name = "Workspace"
local services = {Workspace = workspace}
game = newInstance("DataModel")
local runService
function methods.GetService(_, name)
    if not services[name] then
        local s = newInstance(name)
        s.Name = name
        s.Parent = game
        services[name] = s
        if name == "RunService" then
            s.__props.Heartbeat = Signal()
            s.__props.RenderStepped = Signal()
            s.__props.Stepped = Signal()
        elseif name == "Players" then
            s.__props.PlayerAdded = Signal()
            s.__props.PlayerRemoving = Signal()
        elseif name == "MarketplaceService" then
            s.__props.PromptGamePassPurchaseFinished = Signal()
        end
    end
    return services[name]
end
function methods.BindToClose() end
function methods.BindToRenderStep(_, name, prio, fn) mock.renderSteps = mock.renderSteps or {} mock.renderSteps[name] = fn end
function methods.HasAppearanceLoaded() return true end
function methods.Disconnect() end
workspace.Parent = game
workspace.__props.CurrentCamera = newInstance("Camera")
workspace.__props.CurrentCamera.__props.FieldOfView = 70
workspace.__props.CurrentCamera.__props.CFrame = CFrame.new()

mock.mainThread = coroutine.running()
-- task library: spawn runs immediately, delays and waits are recorded (not run).
mock.delayed = {}
task = {
    spawn = function(fn, ...) local co = coroutine.create(fn) local ok, err = coroutine.resume(co, ...) if not ok then error(err) end return co end,
    delay = function(t, fn, ...) table.insert(mock.delayed, {t = t, fn = fn, args = {...}}) end,
    -- Yields only inside task.spawn'ed coroutines (they are simply never resumed); on the main thread it returns.
    wait = function(t) if coroutine.running() ~= mock.mainThread and coroutine.isyieldable() then coroutine.yield() end return t or 0 end,
    defer = function(fn, ...) table.insert(mock.delayed, {t = 0, fn = fn, args = {...}}) end,
}
wait = task.wait
warn = function(...) print("[warn]", ...) end

function mock.makePlayer(name, userId)
    local plr = newInstance("Player")
    plr.Name = name
    plr.__props.DisplayName = name
    plr.__props.UserId = userId or 1
    plr.__props.CharacterAdded = Signal()
    plr.__props.CharacterAppearanceLoaded = Signal()
    plr.Parent = methods.GetService(game, "Players")
    table.insert(mock.players, plr)
    return plr
end

function mock.makeCharacter(plr, pos)
    local char = newInstance("Model")
    char.Name = plr.Name
    local root = newInstance("Part")
    root.Name = "HumanoidRootPart"
    root.Size = V3(2, 2, 1)
    root.CFrame = CFrame.new(pos)
    root.Parent = char
    char.PrimaryPart = root
    local hum = newInstance("Humanoid")
    hum.__props.Health = 100
    hum.__props.MaxHealth = 100
    hum.__props.HipHeight = 2
    hum.__props.WalkSpeed = 16
    hum.Parent = char
    for name, size, off in pairs({Head = {V3(1.2, 1.2, 1.2), 1.8}, UpperTorso = {V3(2, 1.6, 1), 0.3}, LowerTorso = {V3(2, 0.4, 1), -0.8},
        LeftUpperLeg = {V3(1, 1.2, 1), -1.6}, RightUpperLeg = {V3(1, 1.2, 1), -1.6}, LeftLowerLeg = {V3(1, 1.1, 1), -2.6},
        RightLowerLeg = {V3(1, 1.1, 1), -2.6}, LeftFoot = {V3(1, 0.3, 1), -3.3}, RightFoot = {V3(1, 0.3, 1), -3.3}}) do
        local bp = newInstance("Part") bp.Name = name bp.Size = size[1] bp.CFrame = CFrame.new(pos + V3(0, size[2], 0))
        bp.Color = name == "Head" and Color3.fromRGB(150, 105, 75) or Color3.fromRGB(40, 80, 160) bp.Parent = char
    end
    local shirt = newInstance("Shirt") shirt.Name = "Shirt" shirt.Parent = char
    char.Parent = workspace
    plr.Character = char
    return char, root, hum
end

return mock
