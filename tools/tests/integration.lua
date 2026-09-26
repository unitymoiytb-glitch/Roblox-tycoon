-- Server Main + Client + TrafficClient running together against the mock, with a simulated clock.
local simTime = 0
SIT.clock = function() return simTime end
SIT.mock.serverTimeFn = function() return simTime end
SIT.mount()
SIT.runServer()
local mock = SIT.mock
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Shared.Config)
local W = Config.World
Config.TestMode.Enabled = false -- this test covers the real economy; tools/tests/testmode.lua covers test mode
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
SIT.runClient("BikeRider")
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
    if not m.PrimaryPart then continue end
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

-- 2) Accept a delivery, walk (teleport) onto the drop pad on the far sidewalk: the rich customer
--    takes it without paying, then Raju pays only part of the order value.
remotes.Action.__onFireServer("START_ITEM_MISSION", "Mystery Bucket")
local start = lastEvent("Mission", "START")
check(start and start[2].Drop and start[2].Customer, "mission starts with a drop point and a customer (" .. tostring(start and start[2].Customer) .. ")")
check(workspace.SIT_World:FindFirstChild("Customer") ~= nil, "the customer waits at their door")
local drop = start[2].Drop
check(drop.Position.X > W.ZoneCenters[1] + W.RoadHalfWidth, "drop point is across the road")
check(drop.Transparency < 1, "drop pad glows locally while it is the target")
root.CFrame = CFrame.new(drop.Position + Vector3.new(0, 3, 0))
frames(2)
local delivered = lastEvent("Mission", "DELIVERED")
check(delivered and type(delivered[2].Line) == "string" and delivered[2].Vendor ~= nil, "customer sneers, refuses to pay, sends you back: \"" .. tostring(delivered and delivered[2].Line) .. "\"")
check(lastEvent("Mission", "COMPLETE") == nil, "no money at the customer's door")
check(drop.Transparency == 1, "drop pad hidden again; target is now Raju")
local function goToVendor() root.CFrame = CFrame.new(vendor.Torso.Position + Vector3.new(0, -0.9, 0)) frames(2) end
goToVendor()
local done = lastEvent("Mission", "COMPLETE")
check(done and done[2].Gross >= math.floor(done[2].OrderValue * Config.Delivery.PlayerShare) and done[2].Gross < done[2].OrderValue and done[2].XP == 28,
    string.format("Raju pays only your cut: ₹%d of a ₹%d order", done and done[2].Reward or -1, done and done[2].OrderValue or -1))

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

-- 5) Stand in the fast lane with a parcel: get hit, parcel broken -> debt to Raju, back to the room.
simTime += 1
remotes.Action.__onFireServer("START_ITEM_MISSION", "Mystery Bucket")
check(lastEvent("Mission", "START") ~= start, "second mission started")
local laneX = W.ZoneCenters[1] + W.LaneOffsets[2]
root.CFrame = CFrame.new(laneX, 3.2, 0)
local hitFrame = frames(60 * 20, function() return lastEvent("Mission", "BROKEN") ~= nil end)
local broken = lastEvent("Mission", "BROKEN")
check(broken ~= nil, string.format("standing in lane 2 gets you hit within %.1f s", hitFrame / 60))
check(broken and broken[2].Debt > 0 and broken[2].TotalDebt == broken[2].Debt, "broken parcel: you owe Raju ₹" .. tostring(broken and broken[2].Debt))
check(lastEvent("UI", "SYNC")[2].Debt == (broken and broken[2].TotalDebt), "debt shows in the HUD sync")
runDelayed(1)
check((root.Position - home.Position).Magnitude < 0.01, "after the hit the player is sent back into the starter room")

-- 5b) Next payout repays the debt first.
remotes.Action.__onFireServer("START_ITEM_MISSION", "Mystery Bucket")
root.CFrame = CFrame.new(lastEvent("Mission", "START")[2].Drop.Position + Vector3.new(0, 3, 0)) frames(2)
goToVendor()
local repaid = lastEvent("Mission", "COMPLETE")
check(repaid and repaid[2].DebtPaid == broken[2].Debt and repaid[2].Debt == 0 and repaid[2].Reward == repaid[2].Gross - repaid[2].DebtPaid,
    string.format("Raju keeps ₹%d of the next payout to clear the debt", repaid and repaid[2].DebtPaid or -1))

-- 5c) Deliver until the bicycle is affordable, buy it: visible bike, faster, jumps higher.
for _ = 1, 20 do
    if lastEvent("UI", "SYNC")[2].Cash >= Config.Vehicles.Bicycle.Price then break end
    simTime += 1
    remotes.Action.__onFireServer("START_ITEM_MISSION", "Mystery Bucket")
    root.CFrame = CFrame.new(lastEvent("Mission", "START")[2].Drop.Position + Vector3.new(0, 3, 0)) frames(2)
    goToVendor()
end
simTime += 1
remotes.Action.__onFireServer("BUY_VEHICLE", "Bicycle")
local bike = char:FindFirstChild("Ride_Bicycle")
local bikeParts = 0
if bike then for _, d in ipairs(bike:GetDescendants()) do if d:IsA("BasePart") and d.Transparency < 1 and not d.CanCollide then bikeParts += 1 end end end
check(bike and bikeParts >= 20, "bicycle is a visible welded model (" .. bikeParts .. " non-colliding parts)")
check(hum.WalkSpeed == Config.Vehicles.Bicycle.Speed and hum.JumpPower == Config.Vehicles.Bicycle.Jump and hum.WalkSpeed > 16, "bike: speed " .. tostring(hum.WalkSpeed) .. ", jump power " .. tostring(hum.JumpPower))
frames(5)

-- 6) Wait for a staged accident: wreck rendered at an angle, smoking, solid, hazard lights.
local sawCrash, sawSmoke, sawSolid, sawAngle = false, false, false, false
frames(60 * 70, function()
    for _, m in ipairs(folder:GetChildren()) do
        if not m.PrimaryPart then continue end
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
-- 7) The train: signals + timetable, then it blasts through; standing on the rails is fatal.
root.CFrame = CFrame.new(W.ZoneCenters[1] - 30, 3.8, 0)
local trainEvt = nil
frames(60 * 90, function() trainEvt = lastEvent("TrainState") return trainEvt ~= nil and trainEvt[1].start > simTime end)
check(trainEvt and trainEvt[1].speed > 150 and trainEvt[1].length > 100, "a commuter train is scheduled (" .. tostring(trainEvt and math.floor(trainEvt[1].speed)) .. " studs/s)")
root.CFrame = CFrame.new(W.ZoneCenters[1] + 0.5, 3.8, 0) -- stand between the rails
local brokenBefore = #clientEvents
local sawTrain, sawLamp = false, false
local trainHit = false
local riders = 0
local hitRemote = remotes.TrafficHit
local oldFire = hitRemote.__onFireServer
hitRemote.__onFireServer = function(id, ...) if id == -1 then trainHit = true end return oldFire(id, ...) end
frames(60 * 12, function()
    local tm = folder:FindFirstChild("CommuterTrain")
    if tm then
        sawTrain = true
        local n = 0 for _, d in ipairs(tm:GetChildren()) do if d.Name == "RoofRider" then n += 1 end end
        riders = math.max(riders, n)
    end
    for _, d in ipairs(workspace.SIT_World.Zone_1:GetChildren()) do if d.Name == "RailSignalLamp" and d.Material.Name == "Neon" then sawLamp = true end end
    return trainHit
end)
check(sawLamp, "rail signals flash before the train")
check(sawTrain, "the train (with riders on the roof) is rendered")
check(trainHit, "standing on the rails gets you hit by the train")
runDelayed(1)
check((root.Position - home.Position).Magnitude < 0.01, "train hit sends you back to the starter room")
check(riders >= 12, riders .. " passengers ride on the train roof")

local horns = 0
for _, inst in ipairs(mock.allInstances) do if inst.ClassName == "Sound" and inst.Name == "Horn" then horns += 1 end end
check(horns <= 4, "at most 4 traffic horn Sound objects exist (" .. horns .. ")")
print(fails == 0 and "ALL INTEGRATION CHECKS PASSED" or ("INTEGRATION FAILURES: " .. fails))
