-- TrafficServer: runs one TrafficSim per district that currently has a player in it.
--
-- Performance model:
--   * the server never creates or moves vehicle Instances; it only steps numbers
--   * districts with no players are not simulated at all (their sim is dropped)
--   * 10 snapshots/s per active district, ~12 bytes per vehicle, sent only to players in it
--   * clients render the vehicles, interpolate smoothly, and report their own hits
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TrafficServer = {}

function TrafficServer.start(opts)
    local Config, TrafficSim = opts.Config, opts.TrafficSim
    local W, T = Config.World, Config.Traffic

    local stateRemote
    local ok = pcall(function() stateRemote = Instance.new("UnreliableRemoteEvent") end)
    if not ok or not stateRemote then stateRemote = Instance.new("RemoteEvent") end
    stateRemote.Name = "TrafficState"
    stateRemote.Parent = opts.Remotes

    -- Train timetable per district (only while someone is in the district).
    local trainRemote = Instance.new("RemoteEvent")
    trainRemote.Name = "TrainState"
    trainRemote.Parent = opts.Remotes
    local TR = Config.Train
    local trains, nextTrain, trainId, resendClock = {}, {}, 0, 0

    local sims, idleTime = {}, {}
    local sendClock = 0
    local seedBase = math.floor(os.clock() * 1000) % 100000
    local trainRng = Random.new(seedBase + 77)

    RunService.Heartbeat:Connect(function(dt)
        local byZone = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            local z, root = opts.zoneOfPlayer(plr)
            if z then
                local list = byZone[z]
                if not list then list = {players = {}, focus = {}} byZone[z] = list end
                table.insert(list.players, plr)
                table.insert(list.focus, root.Position.Z)
            end
        end
        for z = 1, #W.ZoneCenters do
            local list = byZone[z]
            if list then
                local sim = sims[z]
                if not sim then
                    sim = TrafficSim.new(Config, z, seedBase + z * 131)
                    sim:populate()
                    sims[z] = sim
                end
                idleTime[z] = 0
                sim:step(dt, list.focus)
                local now = workspace:GetServerTimeNow()
                if not nextTrain[z] then nextTrain[z] = now + TR.FirstDelay + TR.WarnTime end
                if now >= nextTrain[z] - TR.WarnTime then
                    trainId += 1
                    local train = {id = trainId, zone = z, start = nextTrain[z], dir = trainRng:NextNumber() < 0.5 and -1 or 1,
                        speed = TR.Speed * trainRng:NextNumber(0.9, 1.15), length = TR.EngineLength + TR.Coaches * TR.CoachLength, warn = TR.WarnTime}
                    trains[z] = train
                    nextTrain[z] = train.start + trainRng:NextNumber(TR.IntervalMin, TR.IntervalMax)
                    for _, plr in ipairs(list.players) do trainRemote:FireClient(plr, train) end
                end
            elseif sims[z] then
                idleTime[z] = (idleTime[z] or 0) + dt
                if idleTime[z] > 8 then sims[z] = nil trains[z] = nil nextTrain[z] = nil end -- district goes to sleep
            end
        end
        -- Re-send the current timetable once a second so players who just arrived see the train too.
        resendClock += dt
        if resendClock >= 1 then
            resendClock = 0
            for z, list in pairs(byZone) do
                local train = trains[z]
                if train and not TrafficSim.trainDone(train, workspace:GetServerTimeNow(), W.TrafficHalfLength) then
                    for _, plr in ipairs(list.players) do trainRemote:FireClient(plr, train) end
                end
            end
        end
        sendClock += dt
        if sendClock >= T.SnapshotRate then
            sendClock = 0
            for z, list in pairs(byZone) do
                local sim = sims[z]
                if sim then
                    -- Per player: only the traffic around them (the road is ~570 studs long).
                    for i, plr in ipairs(list.players) do
                        stateRemote:FireClient(plr, sim:encode(list.focus[i], T.SnapshotRadius, T.SnapshotMaxVehicles))
                    end
                end
            end
        end
    end)

    -- Clients report hits against the vehicles they see. The server checks the vehicle
    -- exists and is plausibly near the player before applying the penalty.
    opts.HitRemote.OnServerEvent:Connect(function(plr, vehicleId)
        local z, root = opts.zoneOfPlayer(plr)
        local sim = z and sims[z]
        if not sim or type(vehicleId) ~= "number" then return end
        if vehicleId == -1 then
            -- Hit by the train: check it is really passing next to the player.
            local train = trains[z]
            if not train then return end
            local head, tail = TrafficSim.trainSpan(train, workspace:GetServerTimeNow(), W.TrafficHalfLength)
            local pz, px = root.Position.Z, root.Position.X - W.ZoneCenters[z]
            if pz > math.min(head, tail) - 30 and pz < math.max(head, tail) + 30 and math.abs(px) < TR.HalfWidth + 7 then opts.onHit(plr, "train") end
            return
        end
        local v = sim:findVehicle(vehicleId)
        if not v then return end
        if v.crashed and v.v < 3 then return end
        local vx = W.ZoneCenters[z] + W.LaneOffsets[v.lane] + v.off
        local vz = sim:vehicleZ(v)
        local dx, dz = root.Position.X - vx, root.Position.Z - vz
        if dx * dx + dz * dz > 40 * 40 then return end
        opts.onHit(plr)
    end)

    return {sims = sims, remote = stateRemote, trains = trains}
end

return TrafficServer
