-- HazardBuilder: the STATIC part of every district's central strip (between the carriageways).
-- The moving parts (planks, train, crane loads, laser beams, fountain jets) are rendered by the
-- clients from the shared WorldLayout time functions; see HazardClient / TrafficClient.
--
--   1 river    river channel (bed, stone banks, bamboo railings with gaps at every plank)
--   2 train    railway: ballast, sleepers, rails, flashing signals (the V27 train lives here now)
--   3 crane    metro-construction strip: gravel, crane masts, yellow danger discs
--   4 laser    granite security strip: laser pylons along two fences, LED edges
--   5 fountain marble promenade with gold kerbs (jets are client-side)
local Kit = require(script.Parent:WaitForChild("WorldKit"))
local P, CF, V3, RGB, M = Kit.P, Kit.CF, Kit.V3, Kit.RGB, Kit.M
local cyl, ball = Kit.cyl, Kit.ball

local HazardBuilder = {}

local function warnSigns(folder, cx, W, text, bg, fg)
    local mh = W.MedianHalfWidth
    for i, z in ipairs({-150, -60, 60, 150}) do
        local s = (i % 2 == 0) and 1 or -1
        local post = Kit.vcyl(folder, "WarnPost", 5, 0.25, cx + s * (mh - 0.6), 0.5, z, RGB(50, 50, 54), M.Metal)
        Kit.signBoard(folder, "HazardSign", V3(3.6, 1.4, 0.12), V3(cx + s * (mh - 0.6), 5.2, z + 0.2), V3(-s, 0, 0), text, bg or RGB(236, 196, 40), fg or RGB(20, 20, 20))
    end
end

local function floorStrip(folder, cx, W, color, material, kerbColor)
    local mh = W.MedianHalfWidth
    local len = W.TrafficHalfLength * 2 + 20
    P(folder, "MedianFloor", V3(mh * 2, 0.5, len), CFrame.new(cx, 0.25, 0), color, material, true)
    for _, s in ipairs({-1, 1}) do
        P(folder, "MedianKerb", V3(0.4, 0.62, len), CFrame.new(cx + s * (mh - 0.2), 0.31, 0), kerbColor, M.Concrete)
    end
end

-- ---------------------------------------------------------------- 1: river
function HazardBuilder.river(folder, cx, W, WorldLayout)
    local R = WorldLayout.River
    local mh = W.MedianHalfWidth
    local len = W.TrafficHalfLength * 2 + 40
    local m = Instance.new("Model") m.Name = "RiverCrossing" m.Parent = folder
    local depth = 0.2 - R.BedY
    P(m, "RiverBed", V3(mh * 2, 1, len), CFrame.new(cx, R.BedY - 0.5, 0), RGB(70, 58, 42), M.Mud, true)
    for _, s in ipairs({-1, 1}) do
        P(m, "Embankment", V3(0.6, depth, len), CFrame.new(cx + s * (mh - 0.3), R.BedY + depth / 2, 0), RGB(150, 138, 118), M.Slate, true)
        P(m, "BankStone", V3(1.0, 0.3, len), CFrame.new(cx + s * (mh - 0.5), 0.35, 0), RGB(176, 164, 140), M.Slate)
    end
    for _, zs in ipairs({-1, 1}) do
        P(m, "ChannelEnd", V3(mh * 2, depth, 1), CFrame.new(cx, R.BedY + depth / 2, zs * len / 2), RGB(150, 138, 118), M.Slate, true)
    end
    local water = P(m, "Water", V3(mh * 2 - 1.2, 0.3, len), CFrame.new(cx, R.WaterY - 0.15, 0), RGB(96, 112, 96), M.Glass)
    water.Transparency = 0.2
    water.Reflectance = 0.2
    water.CastShadow = false
    -- Bamboo railings along both banks, with a gap at the head of every plank.
    local planks = WorldLayout.riverPlanks(W)
    local gap = R.PlankWidth + 1.4
    for _, s in ipairs({-1, 1}) do
        local prev = -W.PenHalfLength
        for i = 1, #planks + 1 do
            local stop = planks[i] and (planks[i].z - gap / 2) or W.PenHalfLength
            local seg = stop - prev
            if seg > 0.5 then
                P(m, "BambooRail", V3(0.3, 2.8, seg), CFrame.new(cx + s * (mh - 0.25), 1.75, prev + seg / 2), RGB(170, 150, 90), M.Wood, true)
            end
            prev = planks[i] and (planks[i].z + gap / 2) or stop
        end
    end
    -- Plank landing marks on both banks: a fixed (always safe) plank gets a green post.
    for _, pl in ipairs(planks) do
        local c = pl.kind == "fixed" and RGB(70, 170, 80) or (pl.kind == "tilt" and RGB(220, 170, 50) or RGB(200, 70, 50))
        P(m, "PlankPost", V3(0.35, 1.6, 0.35), CFrame.new(cx - (mh - 0.25), 1.1, pl.z + R.PlankWidth / 2 + 0.4), c, M.Wood)
    end
    -- Lotus pads and two moored wooden boats.
    local rng = Random.new(42)
    for i = 1, 26 do
        local z = rng:NextNumber(-W.PenHalfLength, W.PenHalfLength)
        cyl(P(m, "LotusPad", V3(0.06, 1.6 + rng:NextNumber(), 1.6 + rng:NextNumber()), CFrame.new(cx + rng:NextNumber(-4.2, 4.2), R.WaterY + 0.03, z) * CFrame.Angles(0, 0, math.rad(90)), RGB(64, 120, 70), M.Grass))
        if i % 4 == 0 then ball(P(m, "LotusFlower", V3(0.5, 0.5, 0.5), CFrame.new(cx + rng:NextNumber(-4, 4), R.WaterY + 0.2, z + 0.6), RGB(236, 150, 180), M.SmoothPlastic)) end
    end
    for _, z in ipairs({-95, 118}) do
        P(m, "BoatHull", V3(2.2, 0.8, 7), CFrame.new(cx - 3.2, R.WaterY + 0.2, z), RGB(120, 76, 44), M.WoodPlanks)
        Kit.wedge(m, "BoatBow", V3(2.2, 0.8, 1.6), CFrame.new(cx - 3.2, R.WaterY + 0.2, z - 4.3), RGB(120, 76, 44), M.WoodPlanks)
        P(m, "BoatSeat", V3(2, 0.2, 0.6), CFrame.new(cx - 3.2, R.WaterY + 0.55, z + 1), RGB(150, 100, 60), M.Wood)
    end
    warnSigns(m, cx, W, "⚠ RIVER • USE THE PLANKS", RGB(40, 110, 150), RGB(255, 255, 255))
    return m
end

-- ---------------------------------------------------------------- 2: train
function HazardBuilder.train(folder, cx, W, WorldLayout, detail)
    local mh = W.MedianHalfWidth
    local railLen = W.TrafficHalfLength * 2 + 20
    P(folder, "Ballast", V3(mh * 2, 0.5, railLen), CFrame.new(cx, 0.25, 0), RGB(112, 102, 92), M.Pebble, true)
    for _, s in ipairs({-1, 1}) do
        P(folder, "RailKerb", V3(0.4, 0.62, railLen), CFrame.new(cx + s * (mh - 0.2), 0.31, 0), RGB(214, 184, 60), M.Concrete)
        P(folder, "Rail", V3(0.3, 0.3, railLen), CFrame.new(cx + s * 2.4, 0.78, 0), RGB(150, 150, 156), M.Metal)
    end
    local step = detail and 5 or 10
    for zz = -W.PenHalfLength - 8, W.PenHalfLength + 8, step do
        P(folder, "Sleeper", V3(7.2, 0.22, 0.9), CFrame.new(cx, 0.6, zz), RGB(120, 114, 104), M.Concrete)
    end
    for _, sp in ipairs({{-1, -30}, {1, 30}, {-1, 72}, {1, -72}, {-1, 150}, {1, -150}}) do
        local x = cx + sp[1] * (mh - 0.8)
        Kit.vcyl(folder, "SignalPost", 6.5, 0.3, x, 0, sp[2], RGB(40, 40, 42), M.Metal)
        local lamp = ball(P(folder, "RailSignalLamp", V3(0.9, 0.9, 0.9), CFrame.new(x, 6.4, sp[2]), RGB(90, 20, 18), M.SmoothPlastic))
        lamp.CastShadow = false
        Kit.signBoard(folder, "TrainWarning", V3(3.2, 1.2, 0.12), V3(x, 5.0, sp[2] + 0.2), V3(-sp[1], 0, 0), "⚠ TRAINS", RGB(236, 196, 40), RGB(20, 20, 20))
    end
end

-- ---------------------------------------------------------------- 3: cranes
function HazardBuilder.crane(folder, cx, W, WorldLayout)
    local C = WorldLayout.Crane
    local m = Instance.new("Model") m.Name = "ConstructionStrip" m.Parent = folder
    floorStrip(m, cx, W, RGB(130, 120, 106), M.Pebble, RGB(236, 196, 40))
    for _, crane in ipairs(WorldLayout.cranes(W)) do
        cyl(P(m, "DangerDisc", V3(0.06, (C.Radius + 1) * 2, (C.Radius + 1) * 2), CFrame.new(cx, 0.53, crane.z) * CFrame.Angles(0, 0, math.rad(90)), RGB(210, 170, 40), M.SmoothPlastic))
        cyl(P(m, "SafeHub", V3(0.07, 2.6, 2.6), CFrame.new(cx, 0.54, crane.z) * CFrame.Angles(0, 0, math.rad(90)), RGB(40, 40, 42), M.SmoothPlastic))
        P(m, "MastBase", V3(2.2, 1, 2.2), CFrame.new(cx, 1, crane.z), RGB(120, 120, 124), M.Concrete, true)
        Kit.vcyl(m, "Mast", 10.5, 1.0, cx, 1.5, crane.z, RGB(236, 190, 40), M.Metal, true)
    end
    warnSigns(m, cx, W, "⚠ CRANES • WATCH THE LOAD")
    return m
end

-- ---------------------------------------------------------------- 4: lasers
function HazardBuilder.laser(folder, cx, W, WorldLayout)
    local L = WorldLayout.Laser
    local m = Instance.new("Model") m.Name = "SecurityStrip" m.Parent = folder
    floorStrip(m, cx, W, RGB(50, 52, 58), M.Granite, RGB(200, 204, 210))
    local len = W.PenHalfLength * 2
    for _, s in ipairs({-1, 1}) do
        local led = P(m, "LEDEdge", V3(0.2, 0.1, len), CFrame.new(cx + s * (W.MedianHalfWidth - 0.6), 0.56, 0), RGB(80, 170, 255), M.Neon)
        led.CastShadow = false
    end
    for _, x in ipairs(L.FenceX) do
        for z = -W.PenHalfLength, W.PenHalfLength, L.Segment do
            P(m, "LaserPylon", V3(0.7, L.Top + 0.4, 0.7), CFrame.new(cx + x, 0.5 + (L.Top + 0.4) / 2, z), RGB(60, 64, 72), M.Metal, true)
            P(m, "PylonCap", V3(0.8, 0.25, 0.8), CFrame.new(cx + x, L.Top + 1.05, z), RGB(255, 60, 60), M.Neon)
        end
    end
    warnSigns(m, cx, W, "⚠ SECURITY LASERS", RGB(30, 30, 36), RGB(255, 80, 80))
    return m
end

-- ---------------------------------------------------------------- 5: fountains
function HazardBuilder.fountain(folder, cx, W, WorldLayout)
    local m = Instance.new("Model") m.Name = "FountainPromenade" m.Parent = folder
    floorStrip(m, cx, W, RGB(236, 232, 224), M.Marble, RGB(222, 182, 72))
    -- Shallow reflecting channel lines between the jet rows.
    for _, x in ipairs({-1.8, 1.8}) do
        local c = P(m, "Channel", V3(0.6, 0.05, W.PenHalfLength * 2), CFrame.new(cx + x, 0.53, 0), RGB(90, 170, 200), M.Glass)
        c.Transparency = 0.2
    end
    warnSigns(m, cx, W, "⚠ ROYAL FOUNTAINS", RGB(90, 20, 40), RGB(255, 214, 90))
    return m
end

function HazardBuilder.build(folder, cx, W, zone, WorldLayout, detail)
    local kind = WorldLayout.hazardKind(zone)
    local fn = HazardBuilder[kind]
    return fn(folder, cx, W, WorldLayout, detail)
end

return HazardBuilder
