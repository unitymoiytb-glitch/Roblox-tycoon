-- TrafficSim: pure, allocation-light traffic simulation for ONE district.
-- It owns no Instances. The server steps it and replicates compact snapshots;
-- clients render the vehicles and do their own hit detection.
--
-- Rules:
--   * vehicles never leave their lane (no lane changes)
--   * each vehicle re-rolls a target speed every 0.8-2.5 s and eases toward it
--   * vehicles follow the one ahead (no overlaps), which creates natural queues
--   * staged accidents stop 1-2 vehicles at an angle for 6-12 s, then clear
local TrafficSim = {}
TrafficSim.__index = TrafficSim

local KIND_NAMES = {"scooter", "motorbike", "tuktuk", "car"}
local KIND_IDS = {scooter = 1, motorbike = 2, tuktuk = 3, car = 4}
TrafficSim.KindNames = KIND_NAMES
TrafficSim.KindIds = KIND_IDS

local FLAG_CRASHED, FLAG_BLOCKED, FLAG_BURST, FLAG_FALLEN = 1, 2, 4, 8
TrafficSim.Flags = {Crashed = FLAG_CRASHED, Blocked = FLAG_BLOCKED, Burst = FLAG_BURST, Fallen = FLAG_FALLEN}

local HEADER_BYTES, VEHICLE_BYTES = 8, 12
TrafficSim.HeaderBytes, TrafficSim.VehicleBytes = HEADER_BYTES, VEHICLE_BYTES

local function rand(rng, a, b) return a + (b - a) * rng:NextNumber() end

local function pickKind(rng, mix)
    local r, acc, last = rng:NextNumber(), 0, nil
    for _, k in ipairs(KIND_NAMES) do
        local w = mix[k]
        if w then
            acc += w
            last = k
            if r <= acc then return k end
        end
    end
    return last or "scooter"
end

function TrafficSim.new(Config, zoneIndex, seed)
    local W, T = Config.World, Config.Traffic
    local self = setmetatable({}, TrafficSim)
    self.zone = zoneIndex
    self.W, self.T = W, T
    self.rng = Random.new(seed or (zoneIndex * 7919 + 17))
    self.halfLength = W.TrafficHalfLength
    self.length = W.TrafficHalfLength * 2
    self.speedScale = T.ZoneSpeedScale[zoneIndex] or 1
    self.densityScale = T.ZoneDensityScale[zoneIndex] or 1
    self.time = 0
    self.nextId = 1
    self.count = 0
    self.lanes = {}
    for i, offset in ipairs(W.LaneOffsets) do
        local outer = (i == 1 or i == #W.LaneOffsets)
        self.lanes[i] = {index = i, x = offset, dir = W.LaneDirections[i], outer = outer, vehicles = {}, pendingKind = nil, pendingGap = 0}
    end
    self.accidents = {}
    self.nextAccident = T.Accident.FirstDelay
    self.stats = {spawned = 0, despawned = 0, accidents = 0, cleared = 0}
    return self
end

function TrafficSim:laneZ(lane, s)
    if lane.dir > 0 then return -self.halfLength + s end
    return self.halfLength - s
end

function TrafficSim:rollTarget(v)
    local spec = self.T.Kinds[v.kind]
    local lo, hi = spec.Speed[1], spec.Speed[2]
    local target = rand(self.rng, lo, hi)
    v.burst = false
    local r = self.rng:NextNumber()
    if v.kind == "car" and r < (spec.BurstChance or 0) then
        target = rand(self.rng, spec.BurstSpeed[1], spec.BurstSpeed[2])
        v.burst = true
    elseif v.kind == "scooter" and r < 0.12 then
        target = lo * 0.55 -- rider brakes for a moment
    elseif v.kind == "motorbike" and r < 0.2 then
        target = hi * 1.12 -- throttle blip
    end
    v.target = target * self.speedScale
    v.nextRoll = self.time + rand(self.rng, self.T.SpeedRerollMin, self.T.SpeedRerollMax)
end

function TrafficSim:makeVehicle(lane, kind, s)
    local spec = self.T.Kinds[kind]
    local laneHalf = self.W.LaneWidth / 2
    local maxOff = math.max(0, laneHalf - spec.HalfWidth - 0.35)
    if kind == "car" then maxOff = math.min(maxOff, 0.25) elseif kind == "tuktuk" then maxOff = math.min(maxOff, 0.6) end
    local v = {
        id = self.nextId, kind = kind, lane = lane.index, s = s, v = 0, target = 0, nextRoll = 0,
        len = spec.Length, hw = spec.HalfWidth, accel = spec.Accel,
        off = rand(self.rng, -maxOff, maxOff), color = self.rng:NextInteger(0, 255),
        crashed = false, yaw = 0, blocked = false, burst = false,
    }
    self.nextId = (self.nextId % 65000) + 1
    self:rollTarget(v)
    v.v = v.target
    return v
end

function TrafficSim:choosePending(lane)
    local mix = lane.outer and self.T.OuterMix or self.T.InnerMix
    lane.pendingKind = pickKind(self.rng, mix)
    local spacing = lane.outer and self.T.SpawnSpacing.Outer or self.T.SpawnSpacing.Inner
    local kindGap = self.T.Kinds[lane.pendingKind].Gap
    lane.pendingGap = (rand(self.rng, spacing[1], spacing[2]) + rand(self.rng, kindGap[1], kindGap[2])) * self.densityScale
end

-- Fill every lane end-to-end so a newly activated district already looks busy.
function TrafficSim:populate()
    for _, lane in ipairs(self.lanes) do
        lane.vehicles = {}
        self:choosePending(lane)
        local s = self.length - self.rng:NextNumber() * 20
        while s > 0 and self.count < self.T.MaxVehiclesPerZone do
            local kind = lane.pendingKind
            local v = self:makeVehicle(lane, kind, s)
            table.insert(lane.vehicles, v) -- front to back
            self.count += 1
            self.stats.spawned += 1
            local gap = lane.pendingGap
            self:choosePending(lane)
            s -= v.len / 2 + gap + self.T.Kinds[lane.pendingKind].Length / 2
        end
    end
end

function TrafficSim:spawnIfRoom(lane)
    if self.count >= self.T.MaxVehiclesPerZone then return end
    if not lane.pendingKind then self:choosePending(lane) end
    local back = lane.vehicles[#lane.vehicles]
    local newLen = self.T.Kinds[lane.pendingKind].Length
    if back and (back.s - back.len / 2) - newLen / 2 < lane.pendingGap then return end
    local v = self:makeVehicle(lane, lane.pendingKind, 0)
    if back then v.v = math.min(v.target, back.v + 4) end
    table.insert(lane.vehicles, v)
    self.count += 1
    self.stats.spawned += 1
    self:choosePending(lane)
end

function TrafficSim:findVehicle(id)
    for _, lane in ipairs(self.lanes) do
        for i, v in ipairs(lane.vehicles) do
            if v.id == id then return v, lane, i end
        end
    end
    return nil
end

function TrafficSim:vehicleZ(v)
    return self:laneZ(self.lanes[v.lane], v.s)
end

local function crashVehicle(self, v, sign)
    v.crashed = true
    v.burst = false
    local twoWheel = (v.kind == "scooter" or v.kind == "motorbike")
    local mag = twoWheel and rand(self.rng, 35, 70) or rand(self.rng, 22, 34)
    v.yaw = sign * mag
    v.fallen = twoWheel
end

-- Stage an accident close to where players are so they actually see it.
function TrafficSim:tryAccident(focusZs)
    local W = self.W
    local candidates = {}
    for _, lane in ipairs(self.lanes) do
        for _, v in ipairs(lane.vehicles) do
            if not v.crashed and v.v > 8 then
                local z = self:laneZ(lane, v.s)
                if math.abs(z) < W.PenHalfLength - 18 then
                    local near = (#focusZs == 0) and math.abs(z) < 70
                    for _, fz in ipairs(focusZs) do
                        local d = math.abs(z - fz)
                        if d < 60 and d > 10 then near = true break end
                    end
                    if near then table.insert(candidates, v) end
                end
            end
        end
    end
    if #candidates == 0 then return false end
    local a = candidates[self.rng:NextInteger(1, #candidates)]
    local sign = self.rng:NextNumber() < 0.5 and -1 or 1
    crashVehicle(self, a, sign)
    local involved = {a}
    local roll = self.rng:NextNumber()
    local aZ = self:vehicleZ(a)
    if roll < 0.5 then
        -- Side impact with a vehicle in the neighbouring lane: blocks two lanes.
        local best, bestD = nil, 18
        for _, li in ipairs({a.lane - 1, a.lane + 1}) do
            local lane = self.lanes[li]
            if lane then
                for _, v in ipairs(lane.vehicles) do
                    if not v.crashed then
                        local d = math.abs(self:laneZ(lane, v.s) - aZ)
                        if d < bestD then best, bestD = v, d end
                    end
                end
            end
        end
        if best then crashVehicle(self, best, -sign) table.insert(involved, best) end
    elseif roll < 0.8 then
        -- Pile-up: the follower in the same lane rear-ends the first vehicle.
        local lane = self.lanes[a.lane]
        for i, v in ipairs(lane.vehicles) do
            if v == a then
                local f = lane.vehicles[i + 1]
                if f and not f.crashed and (a.s - f.s) < 32 then crashVehicle(self, f, -sign) table.insert(involved, f) end
                break
            end
        end
    end
    local duration = rand(self.rng, self.T.Accident.DurationMin, self.T.Accident.DurationMax)
    table.insert(self.accidents, {vehicles = involved, clearAt = self.time + duration, z = aZ, lane = a.lane})
    self.stats.accidents += 1
    return true
end

function TrafficSim:clearAccident(acc)
    for _, v in ipairs(acc.vehicles) do
        local _, lane, i = self:findVehicle(v.id)
        if lane and lane.vehicles[i] == v then
            table.remove(lane.vehicles, i)
            self.count -= 1
        end
    end
    self.stats.cleared += 1
end

-- focusZs: Z positions of players in this district (used to place accidents).
function TrafficSim:step(dt, focusZs)
    dt = math.min(dt, 0.1)
    self.time += dt
    focusZs = focusZs or {}
    local limitS = self.length
    -- Accidents near the crash site make the neighbouring lanes rubberneck.
    for _, lane in ipairs(self.lanes) do
        local list = lane.vehicles
        local i = 1
        while i <= #list do
            local v = list[i]
            local leader = list[i - 1]
            if v.crashed then
                v.v = math.max(0, v.v - 45 * dt)
                v.blocked = false
            else
                if self.time >= v.nextRoll then self:rollTarget(v) end
                local desired = v.target
                v.blocked = false
                if leader then
                    local gap = (leader.s - leader.len / 2) - (v.s + v.len / 2)
                    local safe = 2.5 + v.v * 0.32
                    if gap < safe then
                        local cap = math.max(0, leader.v + (gap - 2.5) * 1.6)
                        if cap < desired then
                            if desired - cap > 8 then v.blocked = true end
                            desired = cap
                        end
                    end
                end
                for _, acc in ipairs(self.accidents) do
                    if math.abs(acc.lane - lane.index) == 1 then
                        local z = self:laneZ(lane, v.s)
                        if math.abs(z - acc.z) < 16 and desired > 12 then desired = 12 v.blocked = true end
                    end
                end
                if desired > v.v then
                    v.v = math.min(desired, v.v + v.accel * dt)
                else
                    v.v = math.max(desired, v.v - 70 * dt)
                end
            end
            v.s += v.v * dt
            if leader then
                local maxS = leader.s - leader.len / 2 - v.len / 2 - 1.2
                if v.s > maxS then
                    v.s = maxS
                    v.v = math.min(v.v, leader.v)
                end
            end
            i += 1
        end
        -- Despawn from the front once fully inside the far tunnel.
        while list[1] and (list[1].s - list[1].len / 2) > limitS do
            local v = list[1]
            if v.crashed then break end
            table.remove(list, 1)
            self.count -= 1
            self.stats.despawned += 1
        end
        self:spawnIfRoom(lane)
    end
    for i = #self.accidents, 1, -1 do
        local acc = self.accidents[i]
        if self.time >= acc.clearAt then
            self:clearAccident(acc)
            table.remove(self.accidents, i)
        end
    end
    if self.time >= self.nextAccident then
        self:tryAccident(focusZs)
        local A = self.T.Accident
        self.nextAccident = self.time + rand(self.rng, A.IntervalMin, A.IntervalMax)
    end
end

-- ------------------------------------------------------------------ network
-- Snapshot layout (little endian):
--   header: u8 version, u8 zone, u16 count, f32 simTime
--   vehicle: u16 id, u8 kind, u8 lane, u8 flags, i16 z*50, u16 speed*50, i8 lateral*20, i8 yawDeg, u8 color
-- zCenter/radius/maxCount (optional): only vehicles near one player, closest first.
function TrafficSim:encode(zCenter, radius, maxCount)
    local picked = {}
    for _, lane in ipairs(self.lanes) do
        for _, v in ipairs(lane.vehicles) do
            local z = self:laneZ(lane, v.s)
            if not zCenter or math.abs(z - zCenter) <= radius then
                table.insert(picked, {v = v, lane = lane, z = z})
            end
        end
    end
    if zCenter and maxCount and #picked > maxCount then
        table.sort(picked, function(a, b) return math.abs(a.z - zCenter) < math.abs(b.z - zCenter) end)
        for i = #picked, maxCount + 1, -1 do picked[i] = nil end
    end
    local n = #picked
    local buf = buffer.create(HEADER_BYTES + VEHICLE_BYTES * n)
    buffer.writeu8(buf, 0, 1)
    buffer.writeu8(buf, 1, self.zone)
    buffer.writeu16(buf, 2, n)
    buffer.writef32(buf, 4, self.time)
    local o = HEADER_BYTES
    for _, e in ipairs(picked) do
        local v, lane = e.v, e.lane
        local flags = 0
        if v.crashed then flags += FLAG_CRASHED end
        if v.blocked then flags += FLAG_BLOCKED end
        if v.burst then flags += FLAG_BURST end
        if v.fallen and v.crashed then flags += FLAG_FALLEN end
        buffer.writeu16(buf, o, v.id)
        buffer.writeu8(buf, o + 2, KIND_IDS[v.kind])
        buffer.writeu8(buf, o + 3, lane.index)
        buffer.writeu8(buf, o + 4, flags)
        buffer.writei16(buf, o + 5, math.clamp(math.floor(e.z * 50 + 0.5), -32768, 32767))
        buffer.writeu16(buf, o + 7, math.clamp(math.floor(v.v * 50 + 0.5), 0, 65535))
        buffer.writei8(buf, o + 9, math.clamp(math.floor(v.off * 20 + 0.5), -127, 127))
        buffer.writei8(buf, o + 10, math.clamp(math.floor(v.yaw + 0.5), -127, 127))
        buffer.writeu8(buf, o + 11, v.color)
        o += VEHICLE_BYTES
    end
    return buf
end

-- Commuter train: head Z at server time `now`. It starts inside one end tunnel and runs
-- the whole length of the district in `dir` (+1 / -1). Returns head, tail Z.
function TrafficSim.trainSpan(train, now, halfLength)
    local head = -train.dir * (halfLength + 5) + train.dir * train.speed * (now - train.start)
    return head, head - train.dir * train.length
end

function TrafficSim.trainDone(train, now, halfLength)
    return now - train.start > (2 * halfLength + train.length + 20) / train.speed
end

function TrafficSim.decode(buf, out)
    out = out or {}
    table.clear(out)
    local zone = buffer.readu8(buf, 1)
    local n = buffer.readu16(buf, 2)
    local t = buffer.readf32(buf, 4)
    local o = HEADER_BYTES
    for i = 1, n do
        out[i] = {
            id = buffer.readu16(buf, o),
            kind = KIND_NAMES[buffer.readu8(buf, o + 2)] or "scooter",
            lane = buffer.readu8(buf, o + 3),
            flags = buffer.readu8(buf, o + 4),
            z = buffer.readi16(buf, o + 5) / 50,
            speed = buffer.readu16(buf, o + 7) / 50,
            off = buffer.readi8(buf, o + 9) / 20,
            yaw = buffer.readi8(buf, o + 10),
            color = buffer.readu8(buf, o + 11),
        }
        o += VEHICLE_BYTES
    end
    return zone, t, out
end

return TrafficSim
