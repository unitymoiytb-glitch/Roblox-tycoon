-- TrafficClient: renders the traffic of the district the player is in, detects hits
-- against exactly what the player sees, and plays the (rate-limited) street horns.
--
--   * server sends ~10 compact snapshots/s (TrafficSim.encode)
--   * vehicles are pooled Models of anchored, non-colliding parts moved with one BulkMoveTo per frame
--   * each vehicle has ONE invisible hitbox; it only becomes solid when the vehicle is stopped
--     (crash wrecks and queues become obstacles you have to walk around)
--   * at most 4 horn Sounds exist, ever
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local VehicleFactory = require(Shared:WaitForChild("VehicleFactory"))
local TrafficSim = require(Shared:WaitForChild("TrafficSim"))
local Remotes = ReplicatedStorage:WaitForChild("SIT_Remotes")
local StateRE = Remotes:WaitForChild("TrafficState")
local HitRE = Remotes:WaitForChild("TrafficHit")

local W, T = Config.World, Config.Traffic
local FLAGS = TrafficSim.Flags
local ROAD_Y = 0.2
local FLIP = CFrame.Angles(0, math.pi, 0)
local band = bit32.band

local folder = Instance.new("Folder")
folder.Name = "SIT_TrafficClient"
folder.Parent = workspace

local pools = {scooter = {}, motorbike = {}, tuktuk = {}, car = {}}
local vehicles = {}
local currentZone = nil
local lastSnapshot = 0
local stamp = 0
local decoded = {}
local hitLock = 0

-- ---------------------------------------------------------------- pooling
local function newEntry(kind, color)
    local spec = T.Kinds[kind]
    local model = VehicleFactory.build(kind, color)
    local hitbox = Instance.new("Part")
    hitbox.Name = "Hitbox"
    hitbox.Anchored = true
    hitbox.Transparency = 1
    hitbox.CanCollide = false
    hitbox.CanTouch = false
    hitbox.CanQuery = false
    hitbox.CastShadow = false
    hitbox.Size = Vector3.new(spec.HalfWidth * 2, spec.Top, spec.Length)
    hitbox.CFrame = CFrame.new(0, spec.Top / 2, 0)
    hitbox.Parent = model
    local parts, offsets, indicators = {}, {}, {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            table.insert(parts, d)
            table.insert(offsets, d.CFrame) -- built at the origin, so this is the local offset
            if d.Name == "Indicator" then table.insert(indicators, d) end
        end
    end
    return {kind = kind, spec = spec, model = model, root = model.PrimaryPart, hitbox = hitbox, parts = parts, offsets = offsets, indicators = indicators}
end

local function acquire(kind, color)
    local e = table.remove(pools[kind])
    if not e then e = newEntry(kind, color) end
    e.model.Parent = folder
    e.solid = false
    e.hitbox.CanCollide = false
    e.crashed = false
    e.blink = nil
    e.yawNow, e.rollNow = 0, 0
    return e
end

local function release(e)
    if e.smoke then e.smoke:Destroy() e.smoke = nil end
    for _, ind in ipairs(e.indicators) do ind.Material = Enum.Material.SmoothPlastic end
    e.model.Parent = nil
    table.insert(pools[e.kind], e)
end

local function clearAll()
    for id, e in pairs(vehicles) do release(e) vehicles[id] = nil end
end

-- ---------------------------------------------------------------- horns
local horns = {}
for i = 1, 4 do
    local s = Instance.new("Sound")
    s.Name = "Horn"
    s.SoundId = T.HornSoundId
    s.RollOffMode = Enum.RollOffMode.InverseTapered
    s.RollOffMinDistance = 10
    s.RollOffMaxDistance = 130
    s.Volume = 0.3
    horns[i] = s
end
local hornIndex, lastHonk = 0, 0
local HORN_PITCH = {scooter = 1.38, motorbike = 1.16, tuktuk = 1.52, car = 0.9}
local HORN_VOLUME = {scooter = 0.22, motorbike = 0.26, tuktuk = 0.24, car = 0.34}

local function honk(e)
    local now = os.clock()
    if now - lastHonk < 0.9 or not e.model.Parent then return end
    lastHonk = now
    hornIndex = hornIndex % #horns + 1
    local s = horns[hornIndex]
    s:Stop()
    s.Parent = e.root
    s.PlaybackSpeed = HORN_PITCH[e.kind] * (0.94 + math.random() * 0.12)
    s.Volume = HORN_VOLUME[e.kind]
    s.TimePosition = 0
    s:Play()
end

local function characterRoot()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart"), char and char:FindFirstChildOfClass("Humanoid")
end

local function randomVehicleNear(minD, maxD, filter)
    local root = characterRoot()
    if not root then return nil end
    local pos = root.Position
    local found, n = nil, 0
    for _, e in pairs(vehicles) do
        local dx, dz = e.x - pos.X, e.z - pos.Z
        local d = math.sqrt(dx * dx + dz * dz)
        if d >= minD and d <= maxD and (not filter or filter(e)) then
            n += 1
            if math.random(1, n) == 1 then found = e end -- reservoir sample
        end
    end
    return found
end

local function onCrash(e)
    local big = e.kind == "car" or e.kind == "tuktuk"
    local smoke = Instance.new("Smoke")
    smoke.Color = Color3.fromRGB(70, 70, 68)
    smoke.Opacity = big and 0.22 or 0.14
    smoke.Size = big and 4 or 2
    smoke.RiseVelocity = big and 3 or 2
    smoke.Parent = e.root
    e.smoke = smoke
    -- A couple of angry horns from the traffic that has to stop.
    task.delay(0.35, function() local v = randomVehicleNear(0, 90, function(x) return not x.crashed end) if v then honk(v) end end)
    task.delay(1.3, function() local v = randomVehicleNear(0, 90, function(x) return not x.crashed end) if v then honk(v) end end)
end

-- ---------------------------------------------------------------- snapshots
StateRE.OnClientEvent:Connect(function(buf)
    if typeof(buf) ~= "buffer" then return end
    local zone, _, list = TrafficSim.decode(buf, decoded)
    if zone ~= currentZone then clearAll() currentZone = zone end
    local cx = W.ZoneCenters[zone]
    if not cx then return end
    local now = os.clock()
    stamp += 1
    for _, d in ipairs(list) do
        local e = vehicles[d.id]
        if e and e.kind ~= d.kind then release(e) e = nil end
        if not e then
            e = acquire(d.kind, d.color)
            e.z, e.prevZ = d.z, d.z
            vehicles[d.id] = e
        end
        e.id = d.id
        e.dir = W.LaneDirections[d.lane] or 1
        e.x = cx + (W.LaneOffsets[d.lane] or 0) + d.off
        e.snapZ, e.snapSpeed, e.snapTime = d.z, d.speed, now
        local crashed = band(d.flags, FLAGS.Crashed) ~= 0
        if crashed and not e.crashed then onCrash(e) end
        e.crashed = crashed
        e.blocked = band(d.flags, FLAGS.Blocked) ~= 0
        e.yawTarget = d.yaw
        e.rollTarget = band(d.flags, FLAGS.Fallen) ~= 0 and (d.yaw >= 0 and -78 or 78) or 0
        e.stamp = stamp
    end
    for id, e in pairs(vehicles) do
        if e.stamp ~= stamp then release(e) vehicles[id] = nil end
    end
    lastSnapshot = now
end)

-- ---------------------------------------------------------------- per frame
local partsBuf, cfBuf, lastCount = {}, {}, 0
local nextAmbientHonk, nextBlockedHonk = os.clock() + 4, os.clock() + 2
local camera = workspace.CurrentCamera

local function kickCamera()
    camera = workspace.CurrentCamera
    if not camera then return end
    local old = camera.FieldOfView
    camera.FieldOfView = math.min(100, old + 26)
    task.delay(0.22, function() if camera then camera.FieldOfView = old end end)
end

RunService.RenderStepped:Connect(function(dt)
    local now = os.clock()
    if currentZone and now - lastSnapshot > 1.5 then clearAll() currentZone = nil end

    local blinkOn = (now * 2.8) % 2 < 1
    local n = 0
    for _, e in pairs(vehicles) do
        e.prevZ = e.z
        -- Advance at the replicated speed, then softly correct toward the extrapolated server position.
        local speed = e.crashed and 0 or e.snapSpeed
        local predicted = e.snapZ + e.dir * speed * math.min(now - e.snapTime, 0.35)
        e.z += e.dir * speed * dt
        local err = predicted - e.z
        if math.abs(err) > 25 then e.z = predicted else e.z += err * math.min(1, dt * 6) end
        local k = math.min(1, dt * 7)
        e.yawNow += ((e.yawTarget or 0) - e.yawNow) * k
        e.rollNow += ((e.rollTarget or 0) - e.rollNow) * k
        local cf = CFrame.new(e.x, ROAD_Y, e.z)
        if e.dir > 0 then cf = cf * FLIP end
        if e.yawNow ~= 0 or e.rollNow ~= 0 then
            cf = cf * CFrame.Angles(0, math.rad(e.yawNow), 0) * CFrame.Angles(0, 0, math.rad(e.rollNow))
        end
        for i, p in ipairs(e.parts) do
            n += 1
            partsBuf[n] = p
            cfBuf[n] = cf * e.offsets[i]
        end
        -- Stopped vehicles (wrecks, jammed queues) become solid obstacles.
        local solid = e.crashed or e.snapSpeed < 2.5
        if solid ~= e.solid then e.solid = solid e.hitbox.CanCollide = solid end
        -- Hazard lights on wrecks.
        if e.crashed and e.blink ~= blinkOn then
            e.blink = blinkOn
            for _, ind in ipairs(e.indicators) do ind.Material = blinkOn and Enum.Material.Neon or Enum.Material.SmoothPlastic end
        end
    end
    for i = n + 1, lastCount do partsBuf[i] = nil cfBuf[i] = nil end
    lastCount = n
    if n > 0 then workspace:BulkMoveTo(partsBuf, cfBuf, Enum.BulkMoveMode.FireCFrameChanged) end

    -- Hit detection against the vehicles exactly as rendered on this screen.
    local root, hum = characterRoot()
    if root and hum and hum.Health > 0 and now > hitLock then
        local pos = root.Position
        local feet = pos.Y - (hum.HipHeight + root.Size.Y / 2)
        for id, e in pairs(vehicles) do
            if not e.crashed and e.snapSpeed > 3 then
                local spec = e.spec
                if math.abs(pos.X - e.x) < spec.HalfWidth + 0.9 and feet < spec.Top + ROAD_Y then
                    local zMin = math.min(e.prevZ, e.z) - spec.Length / 2 - 0.8
                    local zMax = math.max(e.prevZ, e.z) + spec.Length / 2 + 0.8
                    if pos.Z > zMin and pos.Z < zMax then
                        hitLock = now + 2.5
                        HitRE:FireServer(id)
                        kickCamera()
                        honk(e)
                        break
                    end
                end
            end
        end
    end

    -- Street horns: occasional, spatial, never more than ~1 per second.
    if now >= nextAmbientHonk then
        nextAmbientHonk = now + 3.5 + math.random() * 5
        local e = randomVehicleNear(20, 110, function(x) return not x.crashed and x.snapSpeed > 5 end)
        if e and math.random() < 0.8 then honk(e) end
    end
    if now >= nextBlockedHonk then
        nextBlockedHonk = now + 0.6
        local e = randomVehicleNear(0, 85, function(x) return x.blocked end)
        if e and math.random() < 0.3 then honk(e) nextBlockedHonk = now + 1.8 + math.random() * 2 end
    end
end)
