-- Server + clients for a few simulated seconds, then dump every visible part in the workspace
-- (world, NPCs, client-rendered traffic) plus a blocky stand-in avatar at the spawn point.
local simTime = 0
SIT.clock = function() return simTime end
SIT.mount()
SIT.runServer()
local mock = SIT.mock
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local plr = mock.makePlayer("Preview", 1)
local pg = Instance.new("PlayerGui") pg.Name = "PlayerGui" pg.Parent = plr
Players.__props.LocalPlayer = plr
for _, r in ipairs(RS.SIT_Remotes:GetChildren()) do
    r.__onFireClient = function(_, ...) r.OnClientEvent:Fire(...) end
    r.__onFireServer = function(...) r.OnServerEvent:Fire(plr, ...) end
end
Players.PlayerAdded:Fire(plr)
local home = plr:GetAttribute("HomeSpawn")
local char, root = mock.makeCharacter(plr, home.Position)
plr.CharacterAdded:Fire(char)
SIT.runClient("TrafficClient")
local seconds = tonumber(PREVIEW_SECONDS) or 42
for i = 1, 60 * seconds do
    simTime += 1 / 60
    RunService.Heartbeat:Fire(1 / 60)
    RunService.RenderStepped:Fire(1 / 60)
end
-- Stand-in avatar (R15-ish proportions) at the spawn, facing the exit.
local av = Instance.new("Model") av.Name = "Avatar" av.Parent = workspace
local function ap(size, off, col)
    local p = Instance.new("Part") p.Size = size p.CFrame = home * CFrame.new(off) p.Color = col p.Material = Enum.Material.SmoothPlastic p.Parent = av
end
ap(Vector3.new(2, 1.6, 1), Vector3.new(0, 0.3, 0), Color3.fromRGB(60, 90, 140))
ap(Vector3.new(2, 0.6, 1), Vector3.new(0, -0.8, 0), Color3.fromRGB(50, 50, 60))
ap(Vector3.new(0.9, 2.0, 0.9), Vector3.new(-0.5, -2.1, 0), Color3.fromRGB(50, 50, 60))
ap(Vector3.new(0.9, 2.0, 0.9), Vector3.new(0.5, -2.1, 0), Color3.fromRGB(50, 50, 60))
ap(Vector3.new(0.8, 2.2, 0.8), Vector3.new(-1.4, 0.1, 0), Color3.fromRGB(150, 105, 75))
ap(Vector3.new(0.8, 2.2, 0.8), Vector3.new(1.4, 0.1, 0), Color3.fromRGB(150, 105, 75))
ap(Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.8, 0), Color3.fromRGB(150, 105, 75))
local function dumpRoot(rootInst)
    for _, d in ipairs(rootInst:GetDescendants()) do
        if d:IsA("BasePart") and d.Transparency < 0.95 and (d.LocalTransparencyModifier or 0) < 0.95 then
            local cf, s = d.CFrame, d.Size
            local r = cf.r
            print(string.format("PART\t%s\t%s\t%.3f,%.3f,%.3f\t%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\t%.3f,%.3f,%.3f\t%s\t%s\t%s\t%.2f\t%s\t%d,%d,%d\t%s\t%.2f",
                d.Name, d.ClassName, cf.px, cf.py, cf.pz, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], s.X, s.Y, s.Z,
                tostring(d.CanCollide), tostring(d.CanQuery), tostring(d.CanTouch), d.Transparency, tostring(d.Shape and d.Shape.Name or "Block"),
                math.floor(d.Color.R * 255 + 0.5), math.floor(d.Color.G * 255 + 0.5), math.floor(d.Color.B * 255 + 0.5), d.Material and d.Material.Name or "Plastic", d.Reflectance or 0))
        end
    end
end
dumpRoot(workspace.SIT_World)
dumpRoot(workspace.SIT_TrafficClient)
dumpRoot(av)
print(string.format("CAMHOME\t%.3f,%.3f,%.3f\t%.4f,%.4f,%.4f", home.Position.X, home.Position.Y, home.Position.Z, home.LookVector.X, home.LookVector.Y, home.LookVector.Z))
