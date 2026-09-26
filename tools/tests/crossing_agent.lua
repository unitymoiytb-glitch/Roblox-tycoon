-- Playability probe: simulated pedestrians (walk speed 16) cross all four lanes, stopping on
-- the median. Two policies bracket real players:
--   careful: at a stop, wait until BOTH lanes to the next stop stay clear for the whole walk
--   normal : at a stop, wait until the FIRST lane is clear, then commit through the second
-- Vehicles are read by their current speed (as a player watching traffic would); speed
-- re-rolls and car bursts are what can still surprise them.
SIT.mount()
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Shared.Config)
local TrafficSim = require(RS.Shared.TrafficSim)
local W, T = Config.World, Config.Traffic
local sim = TrafficSim.new(Config, 1, 7)
sim:populate()
local dt = 1 / 60
for _ = 1, 600 do sim:step(dt, {0}) end

local SPEED, R = 16, 0.9
local hitKinds = {}

local function lethal(x, z)
    for _, lane in ipairs(sim.lanes) do
        for _, v in ipairs(lane.vehicles) do
            if not v.crashed and v.v > 3 then
                local spec = T.Kinds[v.kind]
                if math.abs(x - (lane.x + v.off)) < spec.HalfWidth + R and math.abs(z - sim:laneZ(lane, v.s)) < spec.Length / 2 + 0.8 then
                    local key = v.kind .. (v.burst and "(burst)" or "") .. "@lane" .. lane.index
                    hitKinds[key] = (hitKinds[key] or 0) + 1
                    return true
                end
            end
        end
    end
    return false
end

-- Will the strip [x0,x1] at z stay clear of vehicles for the next `dur` seconds?
local function clearFor(x0, x1, z, dur)
    for _, lane in ipairs(sim.lanes) do
        for _, v in ipairs(lane.vehicles) do
            local spec = T.Kinds[v.kind]
            local vx = lane.x + v.off
            if vx + spec.HalfWidth + R > x0 and vx - spec.HalfWidth - R < x1 then
                local vz = sim:laneZ(lane, v.s)
                local reach = spec.Length / 2 + 1.2
                local zEnd = vz + lane.dir * v.v * dur
                if z > math.min(vz, zEnd) - reach and z < math.max(vz, zEnd) + reach then return false end
            end
        end
    end
    return true
end

local function runPolicy(policy)
    local rng = Random.new(3)
    local trials, hits, times, waits = 0, 0, {}, 0
    for _ = 1, 300 do
        for _ = 1, rng:NextInteger(30, 240) do sim:step(dt, {0}) end
        local z = rng:NextNumber(-50, 50)
        local x = -W.RoadHalfWidth - 1.0
        local t, hit, waited = 0, false, 0
        while x < W.RoadHalfWidth + 1.0 and t < 60 do
            local nextStop = (x < -0.05) and 0 or (W.RoadHalfWidth + 1.0)
            local checkEdge = nextStop
            if policy == "normal" then
                checkEdge = (x < -0.05) and (-W.MedianHalfWidth - W.LaneWidth) or (W.MedianHalfWidth + W.LaneWidth)
            end
            local atStop = (x <= -W.RoadHalfWidth - 0.99) or math.abs(x) < 0.01
            if not atStop or clearFor(x - R, checkEdge + R, z, (checkEdge - x) / SPEED + 0.15) then
                x = math.min(nextStop, x + SPEED * dt) -- once moving, commit like a player would
            else
                waited += dt
            end
            sim:step(dt, {z})
            t += dt
            if math.abs(x) < W.RoadHalfWidth + 0.1 and lethal(x, z) then hit = true break end
        end
        trials += 1
        if hit then hits += 1 else table.insert(times, t) end
        waits += waited
    end
    table.sort(times)
    print(string.format("%-8s crossing: %d trials, %.0f%% hit, median %.1f s (p90 %.1f s), mean wait %.1f s",
        policy, trials, 100 * hits / trials, times[math.floor(#times / 2)] or -1, times[math.floor(#times * 0.9)] or -1, waits / trials))
end

runPolicy("careful")
runPolicy("normal")
local parts = {}
for k, n in pairs(hitKinds) do table.insert(parts, k .. "=" .. n) end
table.sort(parts)
print("  hits by vehicle: " .. table.concat(parts, ", "))
