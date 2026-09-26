-- Test mode: every delivery is a free promotion, straight up to Maharaja.
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
local fails = 0
local function check(cond, msg) print((cond and "OK   " or "FAIL ") .. msg) if not cond then fails += 1 end end
check(Config.TestMode.Enabled, "test mode is on in this build")
local plr = mock.makePlayer("Tester", 9)
local events = {}
local remotes = RS.SIT_Remotes
for _, r in ipairs(remotes:GetChildren()) do
    r.__onFireClient = function(_, ...) table.insert(events, {r.Name, ...}) end
    r.__onFireServer = function(...) r.OnServerEvent:Fire(plr, ...) end
end
local function last(remote, kind)
    for i = #events, 1, -1 do local e = events[i] if e[1] == remote and (kind == nil or e[2] == kind) then return e end end
end
local function runDelayed()
    for _ = 1, 4 do
        local pending = mock.delayed mock.delayed = {}
        for _, d in ipairs(pending) do d.fn(table.unpack(d.args)) end
    end
end
Players.PlayerAdded:Fire(plr)
local char, root = mock.makeCharacter(plr, plr:GetAttribute("HomeSpawn").Position)
plr.CharacterAdded:Fire(char)
runDelayed()
check(last("UI", "SYNC")[3].Cash >= Config.TestMode.StartCash, "starts with ₹" .. last("UI", "SYNC")[3].Cash .. " (bicycle affordable)")
local names = {}
for n = 1, #Config.Ranks + 1 do
    local sync = last("UI", "SYNC")[3]
    table.insert(names, sync.RankName)
    if sync.Rank >= #Config.Ranks then break end
    local zone = Config.Ranks[sync.Rank].Zone
    simTime += 1
    remotes.Action.__onFireServer("START_ITEM_MISSION", Config.DeliveryItems[zone][1].Name)
    local start = last("Mission", "START")
    root.CFrame = CFrame.new(start[3].Drop.Position + Vector3.new(0, 3, 0))
    RunService.Heartbeat:Fire(1 / 60)
    local vendor = workspace.SIT_World["VendorNPC_" .. zone].Torso
    root.CFrame = CFrame.new(vendor.Position)
    RunService.Heartbeat:Fire(1 / 60)
    local done = last("Mission", "COMPLETE")
    check(done and done[3].Gross >= done[3].OrderValue, "delivery " .. n .. " pays the full order (₹" .. (done and done[3].Gross or -1) .. ")")
    runDelayed()
end
print("INFO ranks reached: " .. table.concat(names, " -> "))
check(#names == #Config.Ranks and names[#names] == Config.Ranks[#Config.Ranks].Name, "one delivery = one rank, all the way to " .. Config.Ranks[#Config.Ranks].Name)
check(math.abs(plr:GetAttribute("HomeSpawn").Position.X - Config.World.ZoneCenters[5]) < 60, "player was moved to the last district")
print(fails == 0 and "ALL TESTMODE CHECKS PASSED" or ("TESTMODE FAILURES: " .. fails))
