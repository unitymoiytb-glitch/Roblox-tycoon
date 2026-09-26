-- HazardClient: renders the moving central hazard of the district the player is in, from the
-- shared deterministic WorldLayout functions (server time), and reports hits on the existing
-- TrafficHit remote with the hazard's negative id. The server re-checks the same functions.
--
--   Zone 1 river    collidable planks that bob / wobble / sink; falling in = hit
--   Zone 2 train    (handled by TrafficClient)
--   Zone 3 crane    tower-crane jibs swinging heavy loads in circles
--   Zone 4 laser    laser fence segments switching on / warning / off in a travelling wave
--   Zone 5 fountain fountain jets bubbling (warning) then erupting
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))
local HitRE = ReplicatedStorage:WaitForChild("SIT_Remotes"):WaitForChild("TrafficHit")

local W = Config.World
local rad = math.rad
local V3 = Vector3.new

local folder = Instance.new("Folder")
folder.Name = "SIT_Hazards"
folder.Parent = workspace

local rig = nil       -- {zone, kind, update(t, dt)}
local hitLock = 0

local function part(name, size, color, material, collide, shape)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored = true
    p.CanCollide = collide == true
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = size.X * size.Y * size.Z > 4
    p.Size = size
    p.Color = color
    p.Material = material or Enum.Material.SmoothPlastic
    if shape then p.Shape = shape end
    p.Parent = folder
    return p
end

local function zoneOfCharacter()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local best, bd = nil, math.huge
    for z, cx in ipairs(W.ZoneCenters) do
        local d = math.abs(root.Position.X - cx)
        if d < bd then best, bd = z, d end
    end
    return (bd < 110) and best or nil, root
end

-- ---------------------------------------------------------------- river
local function buildRiver(zone)
    local R = WorldLayout.River
    local cx = W.ZoneCenters[zone]
    local mh = W.MedianHalfWidth
    local planks = WorldLayout.riverPlanks(W)
    local parts, cfs = {}, {}
    for i, pl in ipairs(planks) do
        local c = pl.kind == "fixed" and Color3.fromRGB(150, 110, 70) or Color3.fromRGB(128, 92, 58)
        pl.part = part("Plank", V3(mh * 2 + 1.2, 0.4, R.PlankWidth), c, Enum.Material.WoodPlanks, true)
        pl.edge = part("PlankEdge", V3(mh * 2 + 1.2, 0.08, 0.15), pl.kind == "fixed" and Color3.fromRGB(80, 170, 80) or (pl.kind == "tilt" and Color3.fromRGB(220, 170, 50) or Color3.fromRGB(200, 70, 50)), Enum.Material.SmoothPlastic)
        parts[#parts + 1] = pl.part
        parts[#parts + 1] = pl.edge
    end
    -- Debris drifting with the current.
    local debris = {}
    local rng = Random.new(zone)
    for i = 1, 12 do
        local d = part("Driftwood", V3(0.4, 0.25, 1.6 + rng:NextNumber()), Color3.fromRGB(96, 74, 50), Enum.Material.Wood)
        debris[i] = {part = d, x = rng:NextNumber(-mh + 1.2, mh - 1.2), z = rng:NextNumber(-W.PenHalfLength, W.PenHalfLength), speed = 2 + rng:NextNumber() * 2}
        parts[#parts + 1] = d
    end
    return {zone = zone, kind = "river", update = function(t, dt)
        local n = 0
        for _, pl in ipairs(planks) do
            local yOff, tilt = WorldLayout.plankState(pl, t)
            local cf = CFrame.new(cx, R.PlankTop - 0.2 + yOff, pl.z) * CFrame.Angles(rad(tilt), 0, 0)
            n += 1 cfs[n] = cf
            n += 1 cfs[n] = cf * CFrame.new(0, 0.22, -R.PlankWidth / 2 + 0.1)
        end
        for _, d in ipairs(debris) do
            d.z += d.speed * dt
            if d.z > W.PenHalfLength then d.z = -W.PenHalfLength end
            n += 1 cfs[n] = CFrame.new(cx + d.x, R.WaterY + 0.08, d.z) * CFrame.Angles(0, rad(d.z * 7 % 360), 0)
        end
        workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
    end}
end

-- ---------------------------------------------------------------- cranes
local function buildCranes(zone)
    local C = WorldLayout.Crane
    local cx = W.ZoneCenters[zone]
    local cranes = WorldLayout.cranes(W)
    local parts, cfs = {}, {}
    local yellow = Color3.fromRGB(236, 190, 40)
    for _, cr in ipairs(cranes) do
        cr.jib = part("Jib", V3(0.7, 0.7, C.Radius + 2.6), yellow, Enum.Material.Metal)
        cr.counter = part("Counterweight", V3(1.4, 1.2, 1.6), Color3.fromRGB(90, 90, 96), Enum.Material.Concrete)
        cr.cable = part("Cable", V3(0.08, 1, 0.08), Color3.fromRGB(20, 20, 20))
        cr.load = part("Load", V3(1.9, 2.2, 1.9), Color3.fromRGB(200, 70, 40), Enum.Material.DiamondPlate)
        cr.stripe = part("LoadStripe", V3(1.95, 0.35, 1.95), Color3.fromRGB(240, 240, 40), Enum.Material.SmoothPlastic)
        for _, p in ipairs({cr.jib, cr.counter, cr.cable, cr.load, cr.stripe}) do parts[#parts + 1] = p end
    end
    local top = 12
    return {zone = zone, kind = "crane", update = function(t)
        local n = 0
        for _, cr in ipairs(cranes) do
            local lx, lz, a = WorldLayout.craneLoad(cr, t)
            local pivot = V3(cx, top, cr.z)
            local dir = V3(math.cos(a), 0, math.sin(a))
            local tip = pivot + dir * C.Radius
            local loadY = (C.LoadBottom + C.LoadTop) / 2 + 0.5
            n += 1 cfs[n] = CFrame.lookAt(pivot + dir * (C.Radius / 2 - 0.8), tip)
            n += 1 cfs[n] = CFrame.lookAt(pivot - dir * 1.8 - V3(0, 0.2, 0), pivot - V3(0, 0.2, 0))
            local cableLen = top - loadY - 1.1
            n += 1 cfs[n] = CFrame.new(cx + lx, loadY + 1.1 + cableLen / 2, lz)
            cr.cable.Size = V3(0.08, cableLen, 0.08)
            n += 1 cfs[n] = CFrame.new(cx + lx, loadY, lz) * CFrame.Angles(0, -a, 0)
            n += 1 cfs[n] = CFrame.new(cx + lx, loadY + 0.4, lz) * CFrame.Angles(0, -a, 0)
        end
        workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
    end}
end

-- ---------------------------------------------------------------- lasers
local function buildLasers(zone)
    local L = WorldLayout.Laser
    local cx = W.ZoneCenters[zone]
    local segs = WorldLayout.laserSegments(W)
    for _, seg in ipairs(segs) do
        seg.beams = {}
        for _, y in ipairs(L.BeamY) do
            local b = part("LaserBeam", V3(0.16, 0.16, L.Segment - 0.8), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
            b.CFrame = CFrame.new(cx + seg.x, 0.5 + y, (seg.z0 + seg.z1) / 2)
            b.CastShadow = false
            table.insert(seg.beams, b)
        end
        seg.shown = nil
    end
    return {zone = zone, kind = "laser", update = function(t)
        for _, seg in ipairs(segs) do
            local st = WorldLayout.laserState(seg, t)
            local vis
            if st == "on" then vis = 0 elseif st == "warn" then vis = ((t * 7) % 1 < 0.5) and 0.2 or 0.85 else vis = 1 end
            if seg.shown ~= vis then
                seg.shown = vis
                for _, b in ipairs(seg.beams) do b.Transparency = vis end
            end
        end
    end}
end

-- ---------------------------------------------------------------- fountains
local function buildFountains(zone)
    local F = WorldLayout.Fountain
    local cx = W.ZoneCenters[zone]
    local jets = WorldLayout.fountainJets(W)
    for _, j in ipairs(jets) do
        local base = CFrame.new(cx + j.x, 0.52, j.z) * CFrame.Angles(0, 0, rad(90))
        j.nozzle = part("Nozzle", V3(0.1, 1.2, 1.2), Color3.fromRGB(222, 182, 72), Enum.Material.Foil, false, Enum.PartType.Cylinder)
        j.nozzle.CFrame = base
        j.ripple = part("Ripple", V3(0.08, 2.6, 2.6), Color3.fromRGB(150, 220, 255), Enum.Material.Neon, false, Enum.PartType.Cylinder)
        j.ripple.CFrame = base * CFrame.new(0.05, 0, 0)
        j.ripple.CastShadow = false
        j.column = part("WaterColumn", V3(F.Height, 1.5, 1.5), Color3.fromRGB(170, 220, 245), Enum.Material.Glass, false, Enum.PartType.Cylinder)
        j.column.CFrame = CFrame.new(cx + j.x, 0.5 + F.Height / 2, j.z) * CFrame.Angles(0, 0, rad(90))
        j.column.CastShadow = false
        j.shown = nil
    end
    return {zone = zone, kind = "fountain", update = function(t)
        for _, j in ipairs(jets) do
            local st = WorldLayout.jetState(j, t)
            if j.shown ~= st then
                j.shown = st
                j.ripple.Transparency = (st == "warn") and 0.2 or 1
                j.column.Transparency = (st == "erupt") and 0.3 or 1
            end
        end
    end}
end

local BUILDERS = {river = buildRiver, crane = buildCranes, laser = buildLasers, fountain = buildFountains}

local function clearRig()
    for _, c in ipairs(folder:GetChildren()) do c:Destroy() end
    rig = nil
end

RunService.RenderStepped:Connect(function(dt)
    local zone, root = zoneOfCharacter()
    if not zone then
        if rig then clearRig() end
        return
    end
    if not rig or rig.zone ~= zone then
        clearRig()
        local kind = WorldLayout.hazardKind(zone)
        local b = BUILDERS[kind]
        if b then rig = b(zone) else rig = {zone = zone, kind = kind, update = function() end} end
    end
    local t = workspace:GetServerTimeNow()
    rig.update(t, dt)
    -- Hit check against what is on screen.
    local hitId = WorldLayout.HitIds[rig.kind]
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hitId or not hum or hum.Health <= 0 or os.clock() < hitLock then return end
    local pos = root.Position
    local feet = pos.Y - (hum.HipHeight + root.Size.Y / 2)
    local r = math.max(0.9, char:GetAttribute("RideHalfWidth") or 0)
    if WorldLayout.isDanger(zone, W, pos.X - W.ZoneCenters[zone], pos.Z, pos.Y, feet, t, r, 0) then
        hitLock = os.clock() + 2.5
        HitRE:FireServer(hitId)
    end
end)
