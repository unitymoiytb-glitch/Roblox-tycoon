-- Runs TrafficSim for 15 simulated minutes (60 Hz) and checks the traffic rules.
SIT.mount()
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Shared.Config)
local TrafficSim = require(RS.Shared.TrafficSim)
local W, T = Config.World, Config.Traffic

local fails = 0
local function check(cond, msg) print((cond and "OK   " or "FAIL ") .. msg) if not cond then fails += 1 end end

local sim = TrafficSim.new(Config, 1, 4242)
sim:populate()
local dt = 1 / 60
local steps = 60 * 60 * 15
local kindSeen, kindCount = {}, {}
local speedSum, speedN = {}, {}
local minSpeed, maxSpeed = {}, {}
local overlaps, maxCount, countMismatch = 0, 0, 0
local maxBytes = 0
local bins = {}
for li = 1, 4 do bins[li] = {} end
local accidentsSeen, twoLane, maxCrashAge = 0, 0, 0
local crashStart = {}
local queueStops = 0
local roundtripBad = 0
local freeAt0 = {0, 0, 0, 0}
local rerollChanges, lastTarget = 0, {}
local t0 = os.clock()
for step = 1, steps do
    sim:step(dt, {0})
    local total = 0
    for li, lane in ipairs(sim.lanes) do
        local laneFree = true
        for i, v in ipairs(lane.vehicles) do
            total += 1
            if not kindSeen[v.id .. v.kind] then kindSeen[v.id .. v.kind] = true kindCount[v.kind] = (kindCount[v.kind] or 0) + 1 end
            local leader = lane.vehicles[i - 1]
            if leader and (leader.s - leader.len / 2) - (v.s + v.len / 2) < -0.01 then overlaps += 1 end
            local z = sim:laneZ(lane, v.s)
            if math.abs(z) <= W.PenHalfLength then bins[li][math.floor((z + W.PenHalfLength) / 10)] = true end
            if not v.crashed and not v.blocked then
                speedSum[v.kind] = (speedSum[v.kind] or 0) + v.v
                speedN[v.kind] = (speedN[v.kind] or 0) + 1
                if v.v > 1 then
                    minSpeed[v.kind] = math.min(minSpeed[v.kind] or 1e9, v.v)
                    maxSpeed[v.kind] = math.max(maxSpeed[v.kind] or 0, v.v)
                end
            end
            if v.crashed then
                crashStart[v.id] = crashStart[v.id] or sim.time
                maxCrashAge = math.max(maxCrashAge, sim.time - crashStart[v.id])
            end
            if lastTarget[v.id] and lastTarget[v.id] ~= v.target then rerollChanges += 1 end
            lastTarget[v.id] = v.target
            -- lane "occupied" around z=0 (vehicle body within 2 studs of the crossing line, or arriving within 0.6 s)
            local ahead = -lane.dir * z -- distance before reaching z=0 along travel direction
            if math.abs(z) < v.len / 2 + 2 or (ahead > 0 and ahead < v.v * 0.6 + v.len / 2) then laneFree = false end
        end
        if laneFree then freeAt0[li] += 1 end
    end
    if total ~= sim.count then countMismatch += 1 end
    maxCount = math.max(maxCount, total)
    for _, acc in ipairs(sim.accidents) do
        if not acc.counted then
            acc.counted = true
            accidentsSeen += 1
            local lanesHit = {}
            for _, v in ipairs(acc.vehicles) do lanesHit[v.lane] = true end
            local n = 0 for _ in pairs(lanesHit) do n += 1 end
            if n >= 2 then twoLane += 1 end
        end
        -- is traffic behind the wreck queueing?
        local lane = sim.lanes[acc.lane]
        for i, v in ipairs(lane.vehicles) do
            if v.crashed then
                local f = lane.vehicles[i + 1]
                if f and not f.crashed and f.v < 0.5 then queueStops += 1 end
                break
            end
        end
    end
    if step % 6 == 0 then
        local buf = sim:encode()
        maxBytes = math.max(maxBytes, buffer.len(buf))
        local zone, _, list = TrafficSim.decode(buf)
        if zone ~= 1 or #list ~= sim.count then roundtripBad += 1 end
        local k = 1
        for _, lane in ipairs(sim.lanes) do
            for _, v in ipairs(lane.vehicles) do
                local d = list[k]
                if not d or d.id ~= v.id or math.abs(d.z - sim:laneZ(lane, v.s)) > 0.02 or math.abs(d.speed - v.v) > 0.02 then roundtripBad += 1 end
                k += 1
            end
        end
    end
end
local elapsed = os.clock() - t0
print(string.format("INFO sim %.0f s of traffic in %.2f s CPU (%.3f ms/step, luau CLI)", steps * dt, elapsed, elapsed / steps * 1000))
check(overlaps == 0, "no two vehicles in a lane ever overlap (" .. overlaps .. ")")
check(countMismatch == 0, "vehicle bookkeeping consistent")
check(maxCount <= T.MaxVehiclesPerZone, "vehicle cap respected (max " .. maxCount .. ")")
check(maxBytes <= 900, "snapshot size fits an UnreliableRemoteEvent (max " .. maxBytes .. " bytes)")
check(roundtripBad == 0, "snapshot encode/decode round-trips exactly")
local totalKinds = 0 for _, n in pairs(kindCount) do totalKinds += n end
local mixLine = {}
for _, k in ipairs({"scooter", "motorbike", "tuktuk", "car"}) do table.insert(mixLine, string.format("%s %.0f%%", k, 100 * (kindCount[k] or 0) / totalKinds)) end
print("INFO traffic mix over " .. totalKinds .. " vehicles: " .. table.concat(mixLine, ", "))
local sc = (kindCount.scooter or 0) / totalKinds
check(sc >= 0.55 and sc <= 0.72, string.format("scooters dominate (%.0f%%)", sc * 100))
local avg = {}
for k, s in pairs(speedSum) do avg[k] = s / speedN[k] end
print(string.format("INFO free-flow mean speed (studs/s): tuktuk %.1f, scooter %.1f, motorbike %.1f, car %.1f (player walks 16)", avg.tuktuk, avg.scooter, avg.motorbike, avg.car))
print(string.format("INFO speed range car %.0f-%.0f, scooter %.0f-%.0f", minSpeed.car, maxSpeed.car, minSpeed.scooter, maxSpeed.scooter))
check(avg.tuktuk < avg.scooter and avg.scooter < avg.motorbike and avg.motorbike < avg.car, "speed hierarchy tuk-tuk < scooter < motorbike < car")
check(maxSpeed.car > 95, "some cars arrive frighteningly fast (max " .. math.floor(maxSpeed.car) .. ")")
check(rerollChanges > 1000, "vehicles periodically change target speed (" .. rerollChanges .. " re-rolls)")
local minutes = steps * dt / 60
print(string.format("INFO %d accidents in %.0f min (%.1f per minute), %d blocked two lanes", accidentsSeen, minutes, accidentsSeen / minutes, twoLane))
check(accidentsSeen >= minutes * 60 / 50 * 0.8 and accidentsSeen <= minutes * 60 / 25 * 1.1, "accident frequency ~ one per 25-50 s")
check(twoLane >= 1, "some accidents block two lanes")
check(maxCrashAge <= T.Accident.DurationMax + 0.05, string.format("wrecks are always cleared (max age %.1f s)", maxCrashAge))
check(queueStops > 0, "traffic queues/stops behind wrecks")
check(sim.stats.cleared == sim.stats.accidents or sim.stats.cleared == sim.stats.accidents - #sim.accidents, "every accident is cleaned up")
local gapless = 0
for li = 1, 4 do
    local n = 0
    for b = 0, math.floor(2 * W.PenHalfLength / 10) - 1 do if bins[li][b] then n += 1 end end
    if n == math.floor(2 * W.PenHalfLength / 10) then gapless += 1 end
end
check(gapless == 4, "every lane carries traffic along the entire walkable length (no dead zones)")
print(string.format("INFO share of time each lane is safe to step into at z=0: %.0f%% %.0f%% %.0f%% %.0f%%", freeAt0[1] / steps * 100, freeAt0[2] / steps * 100, freeAt0[3] / steps * 100, freeAt0[4] / steps * 100))
print(fails == 0 and "ALL TRAFFIC CHECKS PASSED" or ("TRAFFIC FAILURES: " .. fails))
