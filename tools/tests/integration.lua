-- Server Main + Client + TrafficClient running together against the mock, with a simulated clock.
local simTime = 0
SIT.clock = function() return simTime end
SIT.mount()
SIT.runServer()
local mock = SIT.mock
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Shared.Config)
local W = Config.World
local fails = 0
local function check(cond, msg) print((cond and "OK   " or "FAIL ") .. msg) if not cond then fails += 1 end end

local plr = mock.makePlayer("Tester", 7)
local pg = Instance.new("PlayerGui") pg.Name = "PlayerGui" pg.Parent = plr
Players.__props.LocalPlayer = plr

-- Wire remotes: server->client and client->server.
local clientEvents = {}
local remotes = RS:FindFirstChild("SIT_Remotes")
for _, r in ipairs(remotes:GetChildren()) do
    r.__onFireClient = function(target, ...)
        assert(target == plr, "FireClient to unknown player")
        local args = {...}
        table.insert(clientEvents, {remote = r.Name, args = args})
        r.OnClientEvent:Fire(...)
    end
    r.__onFireServer = function(...) r.OnServerEvent:Fire(plr, ...) end
end
local function lastEvent(remoteName, kind)
    for i = #clientEvents, 1, -1 do
        local e = clientEvents[i]
        if e.remote == remoteName and (kind == nil or e.args[1] == kind) then return e.args end
    end
    return nil
end
local function runDelayed(maxT)
    local pending = mock.delayed
    mock.delayed = {}
    for _, d in ipairs(pending) do
        if d.t <= maxT then d.fn(table.unpack(d.args)) else table.insert(mock.delayed, d) end
    end
end

Players.PlayerAdded:Fire(plr)
local home = plr:GetAttribute("HomeSpawn")
check(typeof(home) == "CFrame", "server publishes HomeSpawn attribute")
local char, root, hum = mock.makeCharacter(plr, home.Position)
plr.CharacterAdded:Fire(char)
check((root.Position - home.Position).Magnitude < 0.01 and root.CFrame.LookVector.X > 0.99, "character is placed in the starter room facing the exit (+X)")

local title = char.Head:FindFirstChild("SIT_Title")
check(title and title.Role.Text == "LESS THAN NOTHING" and title.PlayerName.Text == "Tester", "rank-1 player shows LESS THAN NOTHING above their head")
local rags = char:FindFirstChild("SIT_Rags")
check(rags and #rags:GetChildren() >= 8 and char:FindFirstChild("Shirt") == nil and char.UpperTorso.Material.Name == "Fabric", "rank-1 player wears the torn, dirty rags (" .. (rags and #rags:GetChildren() or 0) .. " details)")
check(char.Head.Color.R > 0.5 and char.Head:GetAttribute("SIT_OrigColor") == nil, "skin colour untouched")
do -- promotion swaps the look back without a respawn, and rebirth puts the rags back on
    local PlayerLook = require(SIT.mainScript.PlayerLook)
    PlayerLook.apply(char, Config.Ranks[2], 2, "Tester")
    check(char:FindFirstChild("SIT_Rags") == nil and char:FindFirstChild("Shirt") ~= nil and char.UpperTorso.Material.Name ~= "Fabric"
        and char.Head.SIT_Title.Role.Text == "COURIER", "rank 2 restores the avatar's own clothes and shows COURIER")
    PlayerLook.apply(char, Config.Ranks[1], 1, "Tester")
    check(char:FindFirstChild("SIT_Rags") ~= nil and char:FindFirstChild("Shirt") == nil, "back to rank 1 (rebirth) puts the rags back on")
end
SIT.runClient("Client")
SIT.runClient("TrafficClient")
runDelayed(2)

local function frames(n, onFrame)
    for i = 1, n do
        simTime += 1 / 60
        RunService.Heartbeat:Fire(1 / 60)
        RunService.RenderStepped:Fire(1 / 60)
        if onFrame and onFrame(i) then return i end
    end
    return n
end
frames(120)
local folder = workspace:FindFirstChild("SIT_TrafficClient")
local models = folder and #folder:GetChildren() or 0
check(models >= 20 and models <= Config.Traffic.MaxVehiclesPerZone, "client renders the district's traffic (" .. models .. " vehicles)")
check((mock.bulkMoves or 0) >= 100, "vehicles are moved with one BulkMoveTo per frame (" .. tostring(mock.bulkMoves) .. " calls)")

-- Rendered vehicles stay exactly in their lanes (x = lane centre + fixed lateral offset).
local worstLane = 0
for _, m in ipairs(folder:GetChildren()) do
    local x = m.PrimaryPart.Position.X - W.ZoneCenters[1]
    local best = math.huge
    for _, lo in ipairs(W.LaneOffsets) do best = math.min(best, math.abs(x - lo)) end
    worstLane = math.max(worstLane, best)
end
check(worstLane <= W.LaneWidth / 2 - 1.3, string.format("every rendered vehicle is inside a lane (max offset %.2f)", worstLane))

-- 1) Talk to Raju -> vendor menu.
local vendor = workspace.SIT_World:FindFirstChild("VendorNPC_1")
local prompt = vendor.Torso:FindFirstChildOfClass("ProximityPrompt")
prompt.Triggered:Fire(plr)
local menu = lastEvent("UI", "VENDOR_MENU")
check(menu and #menu[2].Items >= 1 and menu[2].Items[1].Name == "Mystery Bucket", "Raju opens the delivery menu")

-- 2) Accept a delivery, walk (teleport) onto the drop pad on the far sidewalk.
remotes.Action.__onFireServer("START_ITEM_MISSION", "Mystery Bucket")
local start = lastEvent("Mission", "START")
check(start and start[2].Drop, "mission starts with a drop point")
local drop = start[2].Drop
check(drop.Position.X > W.ZoneCenters[1] + W.RoadHalfWidth, "drop point is across the road")
check(drop.Transparency < 1, "drop pad glows locally while it is the target")
root.CFrame = CFrame.new(drop.Position + Vector3.new(0, 3, 0))
frames(2)
local done = lastEvent("Mission", "COMPLETE")
check(done and done[2].Reward >= 55 and done[2].XP == 28, "delivery completes and pays (₹" .. (done and done[2].Reward or 0) .. ", " .. (done and done[2].XP or 0) .. " XP)")
check(drop.Transparency == 1, "drop pad hidden again after completion")

-- 3) Mechanic unlocks after one delivery.
local mech = workspace.SIT_World:FindFirstChild("MechanicNPC")
mech.Torso:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
local npc = lastEvent("UI", "NPC")
check(npc and npc[2].Key == "Mechanic", "mechanic talks after the first delivery")
remotes.Action.__onFireServer("BUY_VEHICLE", "Bicycle")
check(lastEvent("UI", "SYNC")[2].Toast ~= nil, "vehicle purchase handled (" .. tostring(lastEvent("UI", "SYNC")[2].Toast) .. ")")

-- 4) Guard refuses an unqualified player.
local guard = workspace.SIT_World:FindFirstChild("GuardNPC_1")
guard.Torso:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
check(lastEvent("UI", "GUARD_BLOCK") ~= nil, "promotion guard blocks an unqualified player")

-- 5) Stand in the fast lane: get hit, lose the delivery, respawn at home.
simTime += 1
remotes.Action.__onFireServer("START_ITEM_MISSION", "Mystery Bucket")
check(lastEvent("Mission", "START") ~= start, "second mission started")
local laneX = W.ZoneCenters[1] + W.LaneOffsets[2]
root.CFrame = CFrame.new(laneX, 3.2, 0)
local hitFrame = frames(60 * 20, function() return lastEvent("Mission", "FAILED") ~= nil end)
check(lastEvent("Mission", "FAILED") ~= nil, string.format("standing in lane 2 gets you hit within %.1f s", hitFrame / 60))
runDelayed(1)
check((root.Position - home.Position).Magnitude < 0.01, "after the hit the player is sent back into the starter room")

-- 6) Wait for a staged accident: wreck rendered at an angle, smoking, solid, hazard lights.
local sawCrash, sawSmoke, sawSolid, sawAngle = false, false, false, false
frames(60 * 70, function()
    for _, m in ipairs(folder:GetChildren()) do
        local hb = m:FindFirstChild("Hitbox")
        if hb and hb.CanCollide then sawSolid = true end
        if m.PrimaryPart:FindFirstChildOfClass("Smoke") then sawSmoke = true end
        local look = m.PrimaryPart.CFrame.LookVector
        if math.abs(look.X) > 0.3 then sawAngle = true sawCrash = true end
    end
    return sawCrash and sawSmoke and sawSolid
end)
check(sawCrash and sawAngle, "a staged accident appears (vehicle turned across its lane)")
check(sawSolid, "stopped wrecks/queues become solid obstacles on the client")
check(sawSmoke, "wreck smokes")
local horns = 0
for _, inst in ipairs(mock.allInstances) do if inst.ClassName == "Sound" and inst.Name == "Horn" then horns += 1 end end
check(horns <= 4, "at most 4 horn Sound objects exist (" .. horns .. ")")
print(fails == 0 and "ALL INTEGRATION CHECKS PASSED" or ("INTEGRATION FAILURES: " .. fails))
