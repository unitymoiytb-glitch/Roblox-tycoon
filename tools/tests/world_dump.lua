-- Runs the real server Main against the mock and dumps every BasePart of SIT_World.
SIT.mount()
SIT.runServer()
local world = workspace:FindFirstChild("SIT_World")
assert(world, "SIT_World was not built")
local function path(inst)
    local t = {}
    while inst and inst ~= workspace do table.insert(t, 1, inst.Name) inst = inst.Parent end
    return table.concat(t, "/")
end
local count = 0
for _, d in ipairs(world:GetDescendants()) do
    if d:IsA("BasePart") then
        count += 1
        local cf, s = d.CFrame, d.Size
        local r = cf.r
        print(string.format("PART\t%s\t%s\t%.3f,%.3f,%.3f\t%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\t%.3f,%.3f,%.3f\t%s\t%s\t%s\t%.2f\t%s\t%d,%d,%d\t%s\t%.2f",
            path(d), d.ClassName, cf.px, cf.py, cf.pz, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], s.X, s.Y, s.Z,
            tostring(d.CanCollide), tostring(d.CanQuery), tostring(d.CanTouch), d.Transparency, tostring(d.Shape and d.Shape.Name or "Block"),
            math.floor(d.Color.R * 255 + 0.5), math.floor(d.Color.G * 255 + 0.5), math.floor(d.Color.B * 255 + 0.5), d.Material and d.Material.Name or "Plastic", d.Reflectance or 0))
    end
end
local sp = workspace:FindFirstChildOfClass("SpawnLocation")
print(string.format("SPAWNLOC\t%.3f,%.3f,%.3f\t%.3f,%.3f,%.3f", sp.CFrame.px, sp.CFrame.py, sp.CFrame.pz, sp.CFrame.LookVector.X, sp.CFrame.LookVector.Y, sp.CFrame.LookVector.Z))
-- NPCs (prompt positions)
for _, d in ipairs(world:GetChildren()) do
    if d:IsA("Model") and d:FindFirstChild("Torso") then
        local t = d:FindFirstChild("Torso")
        print(string.format("NPC\t%s\t%.3f,%.3f,%.3f", d.Name, t.Position.X, t.Position.Y, t.Position.Z))
    end
end
print("TOTALPARTS", count)
