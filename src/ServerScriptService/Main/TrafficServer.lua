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

    local sims, idleTime = {}, {}
    local sendClock = 0
    local seedBase = math.floor(os.clock() * 1000) % 100000

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
            elseif sims[z] then
                idleTime[z] = (idleTime[z] or 0) + dt
                if idleTime[z] > 8 then sims[z] = nil end -- district goes to sleep
            end
        end
        sendClock += dt
        if sendClock >= T.SnapshotRate then
            sendClock = 0
            for z, list in pairs(byZone) do
                local sim = sims[z]
                if sim then
                    local buf = sim:encode()
                    for _, plr in ipairs(list.players) do stateRemote:FireClient(plr, buf) end
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
        local v = sim:findVehicle(vehicleId)
        if not v then return end
        if v.crashed and v.v < 3 then return end
        local vx = W.ZoneCenters[z] + W.LaneOffsets[v.lane] + v.off
        local vz = sim:vehicleZ(v)
        local dx, dz = root.Position.X - vx, root.Position.Z - vz
        if dx * dx + dz * dz > 40 * 40 then return end
        opts.onHit(plr)
    end)

    return {sims = sims, remote = stateRemote}
end

return TrafficServer
