-- WorldConnectors: turns five sealed districts into one continuous city.
--
--   * Serpentine arterial road: the end tunnels of neighbouring districts are joined by curved
--     road arcs (north arcs 1-2 and 3-4, south arcs 2-3 and 4-5), plus a road leaving the city
--     at each end. The whole network reads as one winding road on the skyline and from the air.
--   * Transition belts between districts: elevation and landmarks that both block sightlines
--     between gameplay pens and preview the next district's style:
--       1->2 slum hill with a water tower, shacks turning into painted havelis
--       2->3 elevated metro viaduct with a parked metro, mid-rises underneath
--       3->4 raised expressway, billboard towers, first glass towers
--       4->5 terraced palace hill with sandstone ramparts, bastions and domes
--   * Nothing here has an SITZone attribute, so every rank sees the whole skyline (aspiration),
--     and nothing here is walkable from inside a district (gameplay bounds are untouched).
local Kit = require(script.Parent:WaitForChild("WorldKit"))
local P, CF, V3, RGB, M = Kit.P, Kit.CF, Kit.V3, Kit.RGB, Kit.M
local cyl, ball = Kit.cyl, Kit.ball

local WorldConnectors = {}

local ROAD = {RGB(58, 54, 50), RGB(54, 52, 50), RGB(48, 48, 48), RGB(40, 40, 42), RGB(34, 34, 38)}

-- Road arc from (x0, zEnd) to (x1, zEnd), bulging away from the city in zSign direction.
local function arc(folder, x0, x1, zEnd, zSign, width, colA, colB)
    local cx = (x0 + x1) / 2
    local r = math.abs(x1 - x0) / 2
    local n = 16
    for i = 0, n - 1 do
        local a0 = math.pi - (i / n) * math.pi
        local a1 = math.pi - ((i + 1) / n) * math.pi
        local p0 = V3(cx + math.cos(a0) * r, 0.1, zEnd + zSign * math.sin(a0) * r)
        local p1 = V3(cx + math.cos(a1) * r, 0.1, zEnd + zSign * math.sin(a1) * r)
        local mid = (p0 + p1) / 2
        local len = (p1 - p0).Magnitude + 1.2
        local col = colA:Lerp(colB, i / (n - 1))
        P(folder, "ArcRoad", V3(width, 0.4, len), CFrame.lookAt(mid, p1), col, M.Asphalt)
        -- Jersey barriers on both edges, a streetlight every fourth segment.
        local fwd = (p1 - p0).Unit
        local side = V3(-fwd.Z, 0, fwd.X)
        for _, s in ipairs({-1, 1}) do
            local bm = mid + side * s * (width / 2 + 0.4)
            P(folder, "ArcBarrier", V3(0.8, 1.3, len), CFrame.lookAt(bm + V3(0, 0.6, 0), bm + V3(0, 0.6, 0) + fwd), RGB(190, 186, 176), M.Concrete)
        end
        if i % 4 == 0 then
            local lp = mid + side * (width / 2 + 1.6)
            Kit.vcyl(folder, "StreetLight", 11, 0.35, lp.X, 0, lp.Z, RGB(80, 80, 84), M.Metal)
            local head = P(folder, "LampHead", V3(0.9, 0.4, 2.2), CFrame.lookAt(lp + V3(0, 11, 0), lp + V3(0, 11, 0) - side), RGB(255, 236, 190), M.Neon)
            head.CastShadow = false
        end
    end
end

-- Road leaving the city at the far ends: a short curve that fades into the haze.
local function exitRoad(folder, x, zEnd, zSign, xSign, width, col)
    local r = 90
    local n = 8
    local cxc = x + xSign * r
    for i = 0, n - 1 do
        local t0, t1 = i / n * (math.pi / 2), (i + 1) / n * (math.pi / 2)
        local p0 = V3(cxc - xSign * math.cos(t0) * r, 0.1, zEnd + zSign * math.sin(t0) * r)
        local p1 = V3(cxc - xSign * math.cos(t1) * r, 0.1, zEnd + zSign * math.sin(t1) * r)
        P(folder, "ExitRoad", V3(width, 0.4, (p1 - p0).Magnitude + 1.2), CFrame.lookAt((p0 + p1) / 2, p1), col, M.Asphalt)
    end
end

-- A long ridge (flat top + two sloped flanks) running along Z at x. Flanks are tilted blocks
-- sunk into the ground, which read as slopes from any angle.
local function ridge(folder, x, width, height, zMin, zMax, color, material)
    local len = zMax - zMin
    local zc = (zMin + zMax) / 2
    P(folder, "RidgeTop", V3(width, height, len), CFrame.new(x, height / 2, zc), color, material or M.Ground)
    for _, s in ipairs({-1, 1}) do
        local slope = height * 2.2
        P(folder, "RidgeFlank", V3(slope, height, len), CFrame.new(x + s * (width / 2 + slope * 0.32), height * 0.2, zc) * CFrame.Angles(0, 0, math.rad(-s * 28)), color, material or M.Ground)
    end
end

local function box(folder, name, x, y0, z, sx, sy, sz, color, material)
    return P(folder, name, V3(sx, sy, sz), CFrame.new(x, y0 + sy / 2, z), color, material or M.Concrete)
end

-- ---------------------------------------------------------------- transition belts
local belts = {}

belts[1] = function(f, x, W) -- slums -> old market: hill with a water tower
    ridge(f, x, 30, 14, -W.PenHalfLength - 40, W.PenHalfLength + 40, RGB(116, 96, 70))
    for i = -4, 4 do
        local z = i * 46
        box(f, "HillShack", x - 16, 6, z, 8, 6, 10, Kit.pick({RGB(128, 74, 44), RGB(98, 100, 96), RGB(112, 64, 40)}, i + 5), M.CorrodedMetal)
        box(f, "HillHaveli", x + 14, 8, z + 20, 10, 12, 12, Kit.pick({RGB(196, 120, 64), RGB(70, 146, 140), RGB(204, 120, 134)}, i + 5), M.Plaster)
    end
    for _, o in ipairs({{-2.5, -2.5}, {-2.5, 2.5}, {2.5, -2.5}, {2.5, 2.5}}) do
        Kit.beam(f, "TowerLeg", V3(x + o[1], 14, o[2]), V3(x + o[1] * 0.6, 30, o[2] * 0.6), 0.6, RGB(90, 90, 94), M.Metal)
    end
    Kit.vcyl(f, "WaterTank", 8, 9, x, 30, 0, RGB(180, 176, 168), M.Concrete)
    Kit.signBoard(f, "TankSign", V3(8, 2, 0.2), V3(x, 34, -4.6), V3(0, 0, -1), "OLD MARKET →", RGB(120, 30, 30), RGB(255, 226, 140))
end

belts[2] = function(f, x, W) -- old market -> delivery district: metro viaduct
    local len = W.PenHalfLength * 2 + 120
    for z = -len / 2, len / 2, 40 do
        box(f, "ViaductPier", x, 0, z, 3, 17, 3, RGB(170, 166, 158))
    end
    box(f, "ViaductDeck", x, 17, 0, 12, 2, len, RGB(186, 182, 174))
    for _, s in ipairs({-1, 1}) do box(f, "ViaductParapet", x + s * 5.8, 19, 0, 0.5, 1.4, len, RGB(200, 196, 188)) end
    for i = 0, 3 do
        box(f, "MetroCar", x, 19.2, -30 + i * 19, 7, 6, 18, RGB(236, 236, 232), M.Metal)
        box(f, "MetroStripe", x, 21.2, -30 + i * 19, 7.1, 1, 18, RGB(200, 60, 120), M.SmoothPlastic)
    end
    for i = -3, 3 do
        box(f, "MidRise", x + (i % 2 == 0 and -20 or 20), 0, i * 70, 16, 22 + (i % 3) * 4, 24, Kit.pick({RGB(176, 170, 160), RGB(150, 146, 140), RGB(198, 186, 164)}, i + 4))
    end
end

belts[3] = function(f, x, W) -- delivery -> business: raised expressway, billboard towers, glass towers
    local len = W.PenHalfLength * 2 + 120
    for z = -len / 2, len / 2, 45 do box(f, "ExpresswayPier", x - 8, 0, z, 4, 12, 4, RGB(160, 158, 152)) end
    box(f, "Expressway", x - 8, 12, 0, 20, 1.6, len, RGB(60, 60, 62), M.Asphalt)
    for _, z in ipairs({-110, 110}) do
        box(f, "BillboardMast", x + 10, 0, z, 1.2, 26, 1.2, RGB(70, 70, 74), M.Metal)
        Kit.signBoard(f, "Billboard", V3(16, 7, 0.3), V3(x + 10, 29, z), V3(-1, 0, 0), z < 0 and "BUSINESS CORE • 2 KM" or "ZIPPY EATS • FASTER THAN TRAFFIC", RGB(30, 60, 140), RGB(255, 255, 255))
    end
    for i = -2, 2 do
        local t = box(f, "GlassTower", x + 20, 0, i * 90 + 40, 16, 40 + (i % 2) * 18, 16, RGB(70, 110, 140), M.Glass)
        t.Reflectance = 0.25
    end
end

belts[4] = function(f, x, W) -- business -> royal heights: terraced palace hill
    for k = 0, 2 do
        box(f, "Terrace" .. k, x, 0, 0, 60 - k * 16, 5 + k * 5, W.PenHalfLength * 2 + 100 - k * 60, RGB(180, 150, 110):Lerp(RGB(214, 170, 130), k / 2), M.Sandstone)
    end
    local top = 15
    for i = -3, 3 do
        local z = i * 60
        Kit.vcyl(f, "Bastion", 12, 8, x - 14, top, z, RGB(214, 170, 130), M.Sandstone)
        ball(P(f, "BastionDome", V3(8, 8, 8), CFrame.new(x - 14, top + 12, z), RGB(236, 206, 170), M.Sandstone))
    end
    box(f, "Rampart", x - 14, top, 0, 3, 8, W.PenHalfLength * 2 + 20, RGB(200, 156, 118), M.Sandstone)
    Kit.vcyl(f, "HillPalaceDrum", 6, 18, x + 6, top, 0, RGB(240, 232, 214), M.Marble)
    ball(P(f, "HillPalaceDome", V3(18, 18, 18), CFrame.new(x + 6, top + 6, 0), RGB(245, 240, 230), M.Marble))
    P(f, "HillPalaceFinial", V3(0.8, 5, 0.8), CFrame.new(x + 6, top + 17.5, 0), RGB(226, 186, 70), M.Foil)
end

function WorldConnectors.build(world, W)
    local f = Instance.new("Folder")
    f.Name = "Connectors" -- no SITZone: visible to every rank
    f.Parent = world
    local zEnd = W.PenHalfLength + (W.TrafficHalfLength - W.PenHalfLength + 14) + 1
    local width = W.RoadHalfWidth * 2
    local centers = W.ZoneCenters
    for i = 1, #centers - 1 do
        local zSign = (i % 2 == 1) and 1 or -1
        arc(f, centers[i], centers[i + 1], zSign * zEnd, zSign, width, ROAD[i], ROAD[i + 1])
        if belts[i] then belts[i](f, (centers[i] + centers[i + 1]) / 2, W) end
    end
    exitRoad(f, centers[1], -zEnd, -1, -1, width, ROAD[1])
    exitRoad(f, centers[#centers], zEnd, 1, 1, width, ROAD[#ROAD])
    -- Hills closing the far west and far east of the city.
    ridge(f, centers[1] - 90, 20, 16, -W.PenHalfLength - 60, W.PenHalfLength + 60, RGB(110, 92, 70))
    ridge(f, centers[#centers] + 80, 20, 18, -W.PenHalfLength - 60, W.PenHalfLength + 60, RGB(170, 140, 104), M.Sandstone)
    return f
end

return WorldConnectors
