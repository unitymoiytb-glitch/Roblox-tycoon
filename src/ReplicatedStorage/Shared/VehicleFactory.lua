-- VehicleFactory: builds lightweight visual traffic models.
-- Every part is anchored and has CanCollide/CanTouch/CanQuery = false, so the models
-- cost nothing for physics. Collision and hit detection use ONE hitbox per vehicle
-- (see TrafficClient). Models are built at the origin facing -Z with wheels resting on y=0.
local VehicleFactory = {}

local SKIN = {
    Color3.fromRGB(141,98,70), Color3.fromRGB(118,80,56), Color3.fromRGB(168,120,86), Color3.fromRGB(96,66,48),
}
local SHIRTS = {
    Color3.fromRGB(196,72,58), Color3.fromRGB(58,98,160), Color3.fromRGB(226,214,190), Color3.fromRGB(70,128,92),
    Color3.fromRGB(214,160,52), Color3.fromRGB(120,72,140), Color3.fromRGB(60,60,66), Color3.fromRGB(180,110,150),
}
local SCOOTER_BODY = {
    Color3.fromRGB(232,232,228), Color3.fromRGB(188,40,44), Color3.fromRGB(40,86,160), Color3.fromRGB(28,28,30),
    Color3.fromRGB(150,154,160), Color3.fromRGB(96,150,70), Color3.fromRGB(230,196,70),
}
local CAR_BODY = {
    Color3.fromRGB(236,236,232), Color3.fromRGB(176,178,182), Color3.fromRGB(160,34,36), Color3.fromRGB(34,52,110),
    Color3.fromRGB(60,62,66), Color3.fromRGB(222,222,214), Color3.fromRGB(120,40,30),
}
local DARK = Color3.fromRGB(30,30,32)
local GLASS = Color3.fromRGB(46,58,68)
local TYRE = Color3.fromRGB(22,22,22)

local function pick(list, seed, salt)
    return list[((seed * 7 + (salt or 0) * 13) % #list) + 1]
end

local function newPart(model, name, size, pos, color, material, shape, rot)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = (size.X * size.Y * size.Z) > 1.5
    p.Size = size
    p.Color = color
    p.Material = material or Enum.Material.SmoothPlastic
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    if shape then p.Shape = shape end
    local cf = CFrame.new(pos)
    if rot then cf = cf * rot end
    p.CFrame = cf
    p.Parent = model
    return p
end

local function wheel(model, x, z, dia, width)
    -- Cylinder axis is the part's X axis: sideways, exactly like a real axle.
    return newPart(model, "Wheel", Vector3.new(width, dia, dia), Vector3.new(x, dia / 2, z), TYRE, Enum.Material.Rubber, Enum.PartType.Cylinder)
end

local function rider(model, seed, baseY, z, lean, helmet)
    local skin = pick(SKIN, seed, 1)
    local shirt = pick(SHIRTS, seed, 2)
    newPart(model, "RiderTorso", Vector3.new(1.45, 1.7, 0.85), Vector3.new(0, baseY + 0.85, z), shirt, Enum.Material.Fabric, nil, CFrame.Angles(math.rad(-lean), 0, 0))
    newPart(model, "RiderLegs", Vector3.new(1.3, 0.55, 1.5), Vector3.new(0, baseY + 0.1, z - 0.7), Color3.fromRGB(52,52,60), Enum.Material.Fabric)
    newPart(model, "RiderArms", Vector3.new(2.0, 0.42, 1.5), Vector3.new(0, baseY + 1.25, z - 1.0), shirt, Enum.Material.Fabric, nil, CFrame.Angles(math.rad(-18), 0, 0))
    newPart(model, "RiderHead", Vector3.new(1.0, 1.0, 1.0), Vector3.new(0, baseY + 2.2, z - 0.15), skin, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
    if helmet then
        newPart(model, "Helmet", Vector3.new(1.18, 1.18, 1.18), Vector3.new(0, baseY + 2.35, z - 0.1), pick({Color3.fromRGB(200,40,40), Color3.fromRGB(240,240,240), Color3.fromRGB(30,30,30), Color3.fromRGB(40,90,180)}, seed, 3), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
    else
        newPart(model, "Hair", Vector3.new(1.05, 0.45, 1.05), Vector3.new(0, baseY + 2.62, z - 0.05), Color3.fromRGB(26,20,16), Enum.Material.SmoothPlastic)
    end
end

local function pillion(model, seed, baseY, z)
    local shirt = pick(SHIRTS, seed, 5)
    newPart(model, "PillionTorso", Vector3.new(1.35, 1.6, 0.8), Vector3.new(0, baseY + 0.8, z), shirt, Enum.Material.Fabric)
    newPart(model, "PillionHead", Vector3.new(0.95, 0.95, 0.95), Vector3.new(0, baseY + 2.05, z + 0.05), pick(SKIN, seed, 6), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
    -- Long scarf / dupatta trailing behind: cheap, very readable motion cue.
    newPart(model, "Scarf", Vector3.new(0.9, 0.12, 1.4), Vector3.new(0, baseY + 1.35, z + 0.9), pick({Color3.fromRGB(214,90,120), Color3.fromRGB(240,170,40), Color3.fromRGB(90,170,190)}, seed, 7), Enum.Material.Fabric, nil, CFrame.Angles(math.rad(12), 0, 0))
end

local builders = {}

builders.scooter = function(model, seed, opts)
    local body = pick(SCOOTER_BODY, seed, 0)
    wheel(model, 0, -1.9, 1.35, 0.45)
    wheel(model, 0, 1.75, 1.35, 0.5)
    newPart(model, "RearBody", Vector3.new(1.5, 1.15, 2.6), Vector3.new(0, 1.35, 1.05), body, Enum.Material.Metal)
    newPart(model, "Floorboard", Vector3.new(1.3, 0.25, 1.9), Vector3.new(0, 0.78, -0.55), DARK)
    newPart(model, "LegShield", Vector3.new(1.5, 1.9, 0.35), Vector3.new(0, 1.6, -1.55), body, Enum.Material.Metal, nil, CFrame.Angles(math.rad(12), 0, 0))
    newPart(model, "Seat", Vector3.new(1.3, 0.35, 2.0), Vector3.new(0, 2.08, 0.95), DARK)
    newPart(model, "Handlebar", Vector3.new(2.1, 0.28, 0.35), Vector3.new(0, 2.95, -1.8), DARK, Enum.Material.Metal)
    newPart(model, "HeadLight", Vector3.new(0.6, 0.45, 0.2), Vector3.new(0, 2.7, -2.0), Color3.fromRGB(255,236,190), Enum.Material.Neon)
    newPart(model, "TailLight", Vector3.new(0.7, 0.25, 0.15), Vector3.new(0, 1.7, 2.37), Color3.fromRGB(220,40,40), Enum.Material.Neon)
    if opts.rider ~= false then
        rider(model, seed, 2.25, 0.55, 4, seed % 3 == 0)
        if seed % 4 == 1 then pillion(model, seed, 2.25, 1.65) end
    end
end

builders.motorbike = function(model, seed, opts)
    local body = pick({Color3.fromRGB(20,20,22), Color3.fromRGB(170,30,30), Color3.fromRGB(36,70,150), Color3.fromRGB(80,82,86)}, seed, 0)
    wheel(model, 0, -2.3, 1.7, 0.4)
    wheel(model, 0, 2.2, 1.7, 0.5)
    newPart(model, "Engine", Vector3.new(1.2, 1.0, 1.7), Vector3.new(0, 1.15, 0), Color3.fromRGB(70,70,74), Enum.Material.Metal)
    newPart(model, "Tank", Vector3.new(1.35, 0.85, 1.9), Vector3.new(0, 2.05, -0.55), body, Enum.Material.Metal)
    newPart(model, "Seat", Vector3.new(1.15, 0.3, 2.1), Vector3.new(0, 2.05, 1.3), DARK)
    newPart(model, "Frame", Vector3.new(0.35, 0.35, 4.2), Vector3.new(0, 1.55, 0.1), DARK, Enum.Material.Metal, nil, CFrame.Angles(math.rad(-6), 0, 0))
    newPart(model, "Fork", Vector3.new(0.3, 2.3, 0.3), Vector3.new(0, 1.95, -2.05), Color3.fromRGB(190,190,195), Enum.Material.Metal, nil, CFrame.Angles(math.rad(-20), 0, 0))
    newPart(model, "Handlebar", Vector3.new(2.3, 0.22, 0.25), Vector3.new(0, 3.05, -1.65), DARK, Enum.Material.Metal)
    newPart(model, "HeadLight", Vector3.new(0.55, 0.55, 0.3), Vector3.new(0, 2.7, -2.2), Color3.fromRGB(255,236,190), Enum.Material.Neon)
    newPart(model, "Exhaust", Vector3.new(0.3, 0.3, 2.3), Vector3.new(0.72, 0.95, 1.2), Color3.fromRGB(150,150,154), Enum.Material.Metal)
    newPart(model, "TailLight", Vector3.new(0.5, 0.25, 0.15), Vector3.new(0, 2.2, 2.4), Color3.fromRGB(220,40,40), Enum.Material.Neon)
    if opts.rider ~= false then
        rider(model, seed, 2.2, 0.8, 14, seed % 2 == 0)
        if seed % 5 == 2 then pillion(model, seed, 2.2, 1.85) end
    end
end

builders.tuktuk = function(model, seed, opts)
    -- Green lower body + yellow canopy, the classic CNG auto-rickshaw look.
    local lower = pick({Color3.fromRGB(46,120,64), Color3.fromRGB(28,28,28), Color3.fromRGB(46,120,64)}, seed, 0)
    local canopy = Color3.fromRGB(236,190,40)
    wheel(model, 0, -3.3, 1.5, 0.5)
    wheel(model, -2.0, 2.5, 1.5, 0.55)
    wheel(model, 2.0, 2.5, 1.5, 0.55)
    newPart(model, "Lower", Vector3.new(4.6, 1.5, 6.6), Vector3.new(0, 1.55, 0.5), lower, Enum.Material.Metal)
    newPart(model, "Nose", Vector3.new(2.2, 2.4, 1.6), Vector3.new(0, 2.2, -3.2), lower, Enum.Material.Metal)
    newPart(model, "Windshield", Vector3.new(3.8, 1.8, 0.15), Vector3.new(0, 4.25, -2.6), GLASS, Enum.Material.Glass)
    newPart(model, "Canopy", Vector3.new(5.0, 0.35, 6.6), Vector3.new(0, 5.8, 0.2), canopy, Enum.Material.Fabric)
    newPart(model, "CanopyBack", Vector3.new(5.0, 2.8, 0.25), Vector3.new(0, 4.3, 3.45), canopy, Enum.Material.Fabric)
    newPart(model, "PostL", Vector3.new(0.22, 3.0, 0.22), Vector3.new(-2.3, 4.2, -2.5), DARK, Enum.Material.Metal)
    newPart(model, "PostR", Vector3.new(0.22, 3.0, 0.22), Vector3.new(2.3, 4.2, -2.5), DARK, Enum.Material.Metal)
    newPart(model, "BackSeat", Vector3.new(4.2, 1.6, 0.6), Vector3.new(0, 3.1, 2.7), DARK)
    newPart(model, "HeadLight", Vector3.new(0.6, 0.6, 0.2), Vector3.new(0, 3.1, -4.05), Color3.fromRGB(255,236,190), Enum.Material.Neon)
    newPart(model, "Indicator", Vector3.new(0.4, 0.3, 0.2), Vector3.new(-1.9, 2.2, -2.9), Color3.fromRGB(255,150,30), Enum.Material.SmoothPlastic)
    newPart(model, "Indicator", Vector3.new(0.4, 0.3, 0.2), Vector3.new(1.9, 2.2, -2.9), Color3.fromRGB(255,150,30), Enum.Material.SmoothPlastic)
    if opts.rider ~= false then
        rider(model, seed, 2.35, -1.3, 2, false)
        if seed % 2 == 0 then pillion(model, seed + 1, 2.2, 2.1) end
    end
end

builders.car = function(model, seed, opts)
    local taxi = seed % 5 == 0
    local body = taxi and Color3.fromRGB(24,24,24) or pick(CAR_BODY, seed, 0)
    wheel(model, -2.75, -3.9, 2.1, 0.8)
    wheel(model, 2.75, -3.9, 2.1, 0.8)
    wheel(model, -2.75, 3.8, 2.1, 0.8)
    wheel(model, 2.75, 3.8, 2.1, 0.8)
    newPart(model, "Body", Vector3.new(6.4, 1.9, 11.6), Vector3.new(0, 1.9, 0), body, Enum.Material.Metal)
    newPart(model, "Glass", Vector3.new(5.7, 1.75, 5.8), Vector3.new(0, 3.72, 0.6), GLASS, Enum.Material.Glass)
    newPart(model, "Roof", Vector3.new(5.9, 0.35, 5.0), Vector3.new(0, 4.75, 0.8), taxi and Color3.fromRGB(236,196,40) or body, Enum.Material.Metal)
    newPart(model, "Hood", Vector3.new(6.0, 0.4, 3.2), Vector3.new(0, 2.95, -4.1), taxi and Color3.fromRGB(236,196,40) or body, Enum.Material.Metal, nil, CFrame.Angles(math.rad(-4), 0, 0))
    newPart(model, "BumperF", Vector3.new(6.5, 0.6, 0.45), Vector3.new(0, 1.2, -5.9), DARK)
    newPart(model, "BumperR", Vector3.new(6.5, 0.6, 0.45), Vector3.new(0, 1.2, 5.9), DARK)
    newPart(model, "HeadLightL", Vector3.new(1.2, 0.5, 0.2), Vector3.new(-2.2, 2.3, -5.85), Color3.fromRGB(255,240,200), Enum.Material.Neon)
    newPart(model, "HeadLightR", Vector3.new(1.2, 0.5, 0.2), Vector3.new(2.2, 2.3, -5.85), Color3.fromRGB(255,240,200), Enum.Material.Neon)
    newPart(model, "TailLights", Vector3.new(5.6, 0.45, 0.2), Vector3.new(0, 2.35, 5.85), Color3.fromRGB(200,30,30), Enum.Material.Neon)
    newPart(model, "Indicator", Vector3.new(0.5, 0.35, 0.2), Vector3.new(-3.05, 2.3, -5.8), Color3.fromRGB(255,150,30), Enum.Material.SmoothPlastic)
    newPart(model, "Indicator", Vector3.new(0.5, 0.35, 0.2), Vector3.new(3.05, 2.3, -5.8), Color3.fromRGB(255,150,30), Enum.Material.SmoothPlastic)
    newPart(model, "Plate", Vector3.new(1.9, 0.5, 0.1), Vector3.new(0, 1.3, -6.15), Color3.fromRGB(236,232,210))
    if opts.rider ~= false then
        newPart(model, "DriverHead", Vector3.new(1.0, 1.0, 1.0), Vector3.new(-1.3, 3.9, -0.4), pick(SKIN, seed, 1), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
    end
end

-- kind: "scooter" | "motorbike" | "tuktuk" | "car"
-- opts.rider=false builds a parked, empty vehicle.
function VehicleFactory.build(kind, seed, opts)
    opts = opts or {}
    seed = math.floor(seed or 0)
    local model = Instance.new("Model")
    model.Name = "Vehicle_" .. kind
    local root = newPart(model, "Root", Vector3.new(0.4, 0.4, 0.4), Vector3.new(0, 0.2, 0), DARK)
    root.Transparency = 1
    model.PrimaryPart = root
    local builder = builders[kind] or builders.scooter
    builder(model, seed, opts)
    return model
end

return VehicleFactory
