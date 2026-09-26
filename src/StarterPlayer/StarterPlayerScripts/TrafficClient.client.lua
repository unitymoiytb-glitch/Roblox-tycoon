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
    if now - lastHonk < Config.Horns.MinGap or not e.model.Parent then return end
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
        -- On a scooter/tuk-tuk/car the player is as wide as the ride.
        local playerR = math.max(0.9, player.Character:GetAttribute("RideHalfWidth") or 0)
        for id, e in pairs(vehicles) do
            if not e.crashed and e.snapSpeed > 3 then
                local spec = e.spec
                if math.abs(pos.X - e.x) < spec.HalfWidth + playerR and feet < spec.Top + ROAD_Y then
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
        nextAmbientHonk = now + Config.Horns.AmbientMin + math.random() * (Config.Horns.AmbientMax - Config.Horns.AmbientMin)
        local e = randomVehicleNear(20, 110, function(x) return not x.crashed and x.snapSpeed > 5 end)
        if e and math.random() < 0.8 then honk(e) end
    end
    if now >= nextBlockedHonk then
        nextBlockedHonk = now + 0.6
        local e = randomVehicleNear(0, 85, function(x) return x.blocked end)
        if e and math.random() < Config.Horns.BlockedChance then honk(e) nextBlockedHonk = now + 3.6 + math.random() * 4 end
    end
end)

-- ---------------------------------------------------------------- commuter train
-- The server only sends a timetable {zone, start (server time), dir, speed, length}.
-- Every client computes the same position from workspace:GetServerTimeNow(), so the train
-- is smooth, costs no replication, and hits are checked against what the player sees.
local TR = Config.Train
local TrainRE = Remotes:WaitForChild("TrainState")
local trainState, trainRig = nil, nil
local lampCache = {}
local warnHorn = Instance.new("Sound")
warnHorn.Name = "TrainWarning"
warnHorn.SoundId = T.HornSoundId
warnHorn.RollOffMode = Enum.RollOffMode.InverseTapered
warnHorn.RollOffMinDistance = 20
warnHorn.RollOffMaxDistance = 260
warnHorn.Volume = 0.5
warnHorn.PlaybackSpeed = 0.62

local RIDER_SHIRTS = {Color3.fromRGB(226,220,206), Color3.fromRGB(196,72,58), Color3.fromRGB(58,98,160), Color3.fromRGB(214,160,52), Color3.fromRGB(70,128,92), Color3.fromRGB(120,72,140)}
local RIDER_SKIN = {Color3.fromRGB(141,98,70), Color3.fromRGB(118,80,56), Color3.fromRGB(168,120,86)}

local function buildTrain()
    local model = Instance.new("Model")
    model.Name = "CommuterTrain"
    local parts, offsets = {}, {}
    local function add(name, size, pos, color, material, shape)
        local p = Instance.new("Part")
        p.Name = name
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.CastShadow = size.X * size.Y * size.Z > 20
        p.Size = size
        p.Color = color
        p.Material = material or Enum.Material.Metal
        if shape then p.Shape = shape end
        p.CFrame = CFrame.new(pos)
        p.Parent = model
        table.insert(parts, p)
        table.insert(offsets, p.CFrame)
        return p
    end
    local V = Vector3.new
    local hw, bottom = TR.HalfWidth, 1.3
    local h = TR.Height - bottom
    local el, cl = TR.EngineLength, TR.CoachLength
    -- Locomotive (front at z = 0, train extends toward +Z, faces -Z).
    local engine = add("EngineBody", V(hw * 2, h, el - 1), V(0, bottom + h / 2, el / 2 + 0.5), Color3.fromRGB(44,70,140))
    add("EngineStripe", V(hw * 2 + 0.06, 0.9, el - 1), V(0, bottom + h * 0.45, el / 2 + 0.5), Color3.fromRGB(236,226,196))
    add("Windscreen", V(hw * 2 - 1.2, 1.6, 0.2), V(0, bottom + h * 0.8, 0.42), Color3.fromRGB(30,40,50), Enum.Material.Glass)
    add("HeadLight", V(1.0, 0.8, 0.2), V(0, bottom + h * 0.35, 0.4), Color3.fromRGB(255,240,200), Enum.Material.Neon)
    add("EngineRoof", V(hw * 2 - 0.6, 0.5, el - 2), V(0, bottom + h + 0.25, el / 2 + 0.5), Color3.fromRGB(120,122,126))
    add("EngineUnder", V(hw * 2 - 1, 1.2, el - 2), V(0, 0.8, el / 2 + 0.5), Color3.fromRGB(24,24,24))
    for i = 1, TR.Coaches do
        local z0 = el + (i - 1) * cl
        local zc = z0 + cl / 2
        local body = (i % 2 == 0) and Color3.fromRGB(122,40,36) or Color3.fromRGB(52,84,132)
        add("Coach", V(hw * 2, h, cl - 0.8), V(0, bottom + h / 2, zc), body)
        add("Windows", V(hw * 2 + 0.06, 1.3, cl - 4), V(0, bottom + h * 0.62, zc), Color3.fromRGB(26,28,30), Enum.Material.SmoothPlastic)
        add("Door", V(hw * 2 + 0.08, h * 0.8, 1.3), V(0, bottom + h * 0.42, z0 + 1.4), Color3.fromRGB(30,30,32), Enum.Material.SmoothPlastic)
        add("CoachRoof", V(hw * 2 - 0.4, 0.45, cl - 1.2), V(0, bottom + h + 0.22, zc), Color3.fromRGB(128,128,130))
        add("CoachUnder", V(hw * 2 - 1, 1.2, cl - 2), V(0, 0.8, zc), Color3.fromRGB(24,24,24))
        -- People riding on the roof...
        for k = 1, 3 do
            local seed = i * 7 + k
            local x = (k - 2) * 1.9 + ((seed % 3) - 1) * 0.3
            local z = z0 + 2.5 + k * 3.6
            add("RoofRider", V(1.3, 1.5, 0.8), V(x, bottom + h + 1.2, z), RIDER_SHIRTS[seed % #RIDER_SHIRTS + 1], Enum.Material.Fabric)
            add("RoofRiderHead", V(0.95, 0.95, 0.95), V(x, bottom + h + 2.4, z), RIDER_SKIN[seed % #RIDER_SKIN + 1], Enum.Material.SmoothPlastic, Enum.PartType.Ball)
        end
        -- ...and one hanging out of the open door.
        local side = (i % 2 == 0) and 1 or -1
        add("DoorHanger", V(0.8, 1.6, 1.0), V(side * (hw + 0.45), bottom + h * 0.55, z0 + 1.4), RIDER_SHIRTS[(i * 3) % #RIDER_SHIRTS + 1], Enum.Material.Fabric)
        add("DoorHangerHead", V(0.9, 0.9, 0.9), V(side * (hw + 0.55), bottom + h * 0.55 + 1.2, z0 + 1.4), RIDER_SKIN[i % #RIDER_SKIN + 1], Enum.Material.SmoothPlastic, Enum.PartType.Ball)
    end
    local horn = Instance.new("Sound")
    horn.Name = "TrainHorn"
    horn.SoundId = T.HornSoundId
    horn.PlaybackSpeed = 0.5
    horn.Volume = 0.9
    horn.RollOffMode = Enum.RollOffMode.InverseTapered
    horn.RollOffMinDistance = 30
    horn.RollOffMaxDistance = 420
    horn.Parent = engine
    return {model = model, parts = parts, offsets = offsets, horn = horn}
end

local function signalLamps(zone)
    if lampCache[zone] then return lampCache[zone] end
    local world = workspace:FindFirstChild("SIT_World")
    local zf = world and world:FindFirstChild("Zone_" .. zone)
    if not zf then return {} end
    local lamps = {}
    for _, d in ipairs(zf:GetChildren()) do
        if d.Name == "RailSignalLamp" then table.insert(lamps, d) end
    end
    lampCache[zone] = lamps
    return lamps
end

local function setLamps(zone, on)
    for _, lamp in ipairs(signalLamps(zone)) do
        if lamp:GetAttribute("On") ~= on then
            lamp:SetAttribute("On", on)
            lamp.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
            lamp.Color = on and Color3.fromRGB(255, 40, 30) or Color3.fromRGB(90, 20, 18)
        end
    end
end

TrainRE.OnClientEvent:Connect(function(train)
    if type(train) == "table" and type(train.start) == "number" then
        if not trainState or trainState.id ~= train.id then train.honked = {} trainState = train end
    end
end)

local lampZone, prevHead = nil, nil
local function parkTrain()
    if trainRig and trainRig.model.Parent then trainRig.model.Parent = nil end
    prevHead = nil
end

RunService.RenderStepped:Connect(function()
    local tr = trainState
    local now = workspace:GetServerTimeNow()
    if not tr or tr.zone ~= currentZone or TrafficSim.trainDone(tr, now, W.TrafficHalfLength) then
        if lampZone then setLamps(lampZone, false) lampZone = nil end
        parkTrain()
        return
    end
    local t = now - tr.start
    lampZone = tr.zone
    setLamps(tr.zone, t > -tr.warn and (now * 3) % 2 < 1)
    local root, hum = characterRoot()
    -- Warning horns from the signal nearest the player, then the engine horn as it enters.
    local function honkOnce(key, sound, parent)
        if tr.honked[key] then return end
        tr.honked[key] = true
        if parent then sound.Parent = parent end
        sound.TimePosition = 0
        sound:Play()
    end
    if t > -tr.warn and root then
        local best, bestD = nil, math.huge
        for _, lamp in ipairs(signalLamps(tr.zone)) do
            local d = math.abs(lamp.Position.Z - root.Position.Z)
            if d < bestD then best, bestD = lamp, d end
        end
        if best then
            honkOnce("warn1", warnHorn, best)
            if t > -1.6 then honkOnce("warn2", warnHorn, best) end
        end
    end
    if t < -0.2 then parkTrain() return end
    if not trainRig then trainRig = buildTrain() end
    if not trainRig.model.Parent then trainRig.model.Parent = folder end
    honkOnce("engine", trainRig.horn)
    local cx = W.ZoneCenters[tr.zone]
    local head, tail = TrafficSim.trainSpan(tr, now, W.TrafficHalfLength)
    local cf = CFrame.new(cx, 0.5, head)
    if tr.dir > 0 then cf = cf * FLIP end
    local cfs = table.create(#trainRig.parts)
    for i, off in ipairs(trainRig.offsets) do cfs[i] = cf * off end
    workspace:BulkMoveTo(trainRig.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
    -- Hit check (swept over this frame so the 175 stud/s train cannot skip past the player).
    if root and hum and hum.Health > 0 and os.clock() > hitLock then
        local pos = root.Position
        local feet = pos.Y - (hum.HipHeight + root.Size.Y / 2)
        local zMin = math.min(head, tail, prevHead or head) - 0.8
        local zMax = math.max(head, tail, prevHead or head) + 0.8
        local playerR = math.max(0.9, player.Character:GetAttribute("RideHalfWidth") or 0)
        if math.abs(pos.X - cx) < TR.HalfWidth + playerR and feet < TR.Height + 1 and pos.Z > zMin and pos.Z < zMax then
            hitLock = os.clock() + 2.5
            HitRE:FireServer(-1)
            kickCamera()
        end
    end
    prevHead = head
end)
