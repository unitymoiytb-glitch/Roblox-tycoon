-- ZoneStyles: per-district architecture and the player's evolving home.
--
--   Zone 2 OLD MARKET        painted havelis with arcades + jharokha balconies, bazaar stalls
--   Zone 3 DELIVERY DISTRICT concrete mid-rises with window bands, AC units, neon cloud kitchens
--   Zone 4 BUSINESS CORE     glass towers on stone podiums, stepped offices, lobby plazas
--   Zone 5 ROYAL HEIGHTS     sandstone palace wings with chhatris, marble domed villas, gateways
--
-- Homes (same footprint as the starter shack, so bounds and spawn stay identical):
--   Tin Shack (zone 1, WorldBuilder) -> Concrete Room -> Small Flat -> City Apartment -> Palace Suite
local Kit = require(script.Parent:WaitForChild("WorldKit"))
local P, CF, V3, RGB, M = Kit.P, Kit.CF, Kit.V3, Kit.RGB, Kit.M
local cyl, ball = Kit.cyl, Kit.ball

local ZoneStyles = {}

local PAL = {
    market = {RGB(196,120,64), RGB(64,110,150), RGB(70,146,140), RGB(204,120,134), RGB(214,170,70), RGB(150,90,150)},
    delivery = {RGB(176,170,160), RGB(150,146,140), RGB(198,186,164), RGB(136,150,160), RGB(186,160,140)},
    business = {RGB(64,104,136), RGB(80,120,150), RGB(52,86,110), RGB(96,130,146)},
    royal = {RGB(214,170,130), RGB(226,196,160), RGB(236,232,222), RGB(222,160,140)},
}
local GOLD = RGB(222, 182, 72)
local DARK = RGB(30, 30, 34)
local CLOTH = {RGB(206,72,96), RGB(230,164,40), RGB(66,140,110), RGB(88,112,190), RGB(186,76,48), RGB(150,90,160)}

local function at(ctx, d, y, w, ry, rx, rz) return Kit.rowCF(ctx.cx, ctx.W, ctx.side, d, y, w, ry, rx, rz) end
local function model(ctx, name) local m = Instance.new("Model") m.Name = name m.Parent = ctx.folder return m end
local function sign(ctx, m, text, d, y, wc, width, bg, fg)
    Kit.signBoard(m, "Sign", V3(width, 1.7, 0.2), at(ctx, d, y, wc).Position, Kit.facingRoad(ctx.side), text, bg, fg)
end

-- Solid building mass (keeps the row closed) + optional plinth.
local function mass(ctx, m, w0, w1, depth, h, color, material)
    local wc = (w0 + w1) / 2
    return P(m, "Mass", V3(depth, h, w1 - w0 - 0.4), at(ctx, depth / 2, h / 2, wc), color, material or M.Concrete, true)
end

-- Dark window rectangles in rows on the front face.
local function windows(ctx, m, w0, w1, y0, rows, rowGap, color, frame)
    local Wd = w1 - w0
    local cols = math.max(1, math.floor(Wd / 7))
    for r = 0, rows - 1 do
        for c = 1, cols do
            local w = w0 + (c - 0.5) * Wd / cols
            P(m, "Window", V3(0.15, 2.2, 2.0), at(ctx, -0.06, y0 + r * rowGap, w), color or DARK, M.Glass)
        end
    end
end

-- ================================================================ ZONE 2: OLD MARKET
local market = {}

function market.haveli(ctx, w0, w1, rng)
    local m = model(ctx, "Haveli")
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    local col = Kit.pick(PAL.market, rng:NextInteger(1, 60))
    local h = 13 + rng:NextNumber() * 4
    mass(ctx, m, w0, w1, 14, h, col, M.Plaster)
    -- Ground-floor arcade: pillars, arches (half-cylinders) and a dark recess behind.
    P(m, "ArcadeShade", V3(0.2, 5.6, Wd - 1.2), at(ctx, -0.05, 2.8, wc), RGB(40, 32, 26))
    local n = math.max(2, math.floor(Wd / 6))
    for i = 0, n do
        local w = w0 + 0.6 + i * (Wd - 1.2) / n
        P(m, "Pillar", V3(0.9, 6.2, 0.9), at(ctx, -0.5, 3.1, w), RGB(236, 220, 190), M.Plaster)
    end
    for i = 1, n do
        local w = w0 + 0.6 + (i - 0.5) * (Wd - 1.2) / n
        local span = (Wd - 1.2) / n
        cyl(P(m, "Arch", V3(0.6, span, span * 0.7), at(ctx, -0.45, 6.2, w), RGB(236, 220, 190), M.Plaster))
    end
    P(m, "Cornice", V3(1.2, 0.6, Wd), at(ctx, -0.4, 7.2, wc), RGB(236, 220, 190), M.Plaster)
    -- Jharokha balconies on the upper floor.
    for i = 1, 2 do
        local w = w0 + i * Wd / 3
        P(m, "Jharokha", V3(1.6, 2.6, 2.6), at(ctx, -0.8, 9.6, w), RGB(236, 220, 190), M.Plaster)
        P(m, "JharokhaWindow", V3(0.1, 1.6, 1.8), at(ctx, -1.62, 9.8, w), DARK, M.Glass)
        P(m, "JharokhaRoof", V3(2.2, 0.35, 3.2), at(ctx, -0.8, 11.1, w, 0, 0, 8), col:Lerp(RGB(90, 40, 30), 0.4), M.Plaster)
    end
    -- Crenellated parapet.
    for i = 0, math.floor(Wd / 5) do
        P(m, "Merlon", V3(0.8, 1.0, 1.6), at(ctx, 0.4, h + 0.5, w0 + 1 + i * 5), col, M.Plaster)
    end
    P(m, "Awning", V3(2.6, 0.12, Wd - 1), at(ctx, -1.5, 6.9, wc, 0, 0, 14), Kit.pick(CLOTH, rng:NextInteger(1, 30)), M.Fabric)
    return m
end

function market.bazaar(ctx, w0, w1, rng, opts)
    local m = model(ctx, "BazaarStall")
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    local col = Kit.pick(PAL.market, rng:NextInteger(1, 60))
    mass(ctx, m, w0, w1, 14, 9.5, col, M.Plaster)
    P(m, "Counter", V3(1.6, 2.8, Wd - 1.4), at(ctx, 0.9, 1.4, wc), RGB(110, 76, 46), M.WoodPlanks, true)
    -- Spice / produce heaps on the counter.
    for i = 1, math.max(3, math.floor(Wd / 3)) do
        local w = w0 + 1 + (i - 0.5) * (Wd - 2) / math.max(3, math.floor(Wd / 3))
        ball(P(m, "Heap", V3(1.3, 1.3, 1.3), at(ctx, 0.9, 3.0, w), Kit.pick({RGB(200, 50, 30), RGB(230, 170, 30), RGB(210, 110, 30), RGB(120, 150, 50), RGB(150, 60, 40)}, i + rng:NextInteger(1, 9)), M.Sand))
    end
    for i = 1, 3 do
        P(m, "HangingCloth", V3(0.1, 3.2, 1.2), at(ctx, -1.8, 5.6, w0 + i * Wd / 4), Kit.pick(CLOTH, i + 2), M.Fabric)
    end
    -- Striped canopy.
    for i = 0, 3 do
        P(m, "Canopy", V3(3.4, 0.14, (Wd - 0.6) / 4), at(ctx, -1.6, 7.6, w0 + 0.3 + (i + 0.5) * (Wd - 0.6) / 4, 0, 0, 12), i % 2 == 0 and RGB(230, 226, 214) or Kit.pick(CLOTH, rng:NextInteger(1, 9)), M.Fabric, "query")
    end
    if opts.sign then sign(ctx, m, opts.sign, -0.3, 8.8, wc, math.min(Wd - 2, 9), RGB(120, 30, 30), RGB(255, 226, 140)) end
    return m
end

function market.tallHouse(ctx, w0, w1, rng)
    local m = model(ctx, "TallHouse")
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    local col = Kit.pick(PAL.market, rng:NextInteger(1, 60))
    mass(ctx, m, w0, w1, 14, 8, col:Lerp(RGB(200, 190, 170), 0.3), M.Plaster)
    P(m, "Floor2", V3(14, 6, Wd), at(ctx, 6.5, 11, wc), col, M.Plaster, true)          -- juts out over the street
    P(m, "Floor3", V3(12, 5, Wd - 2), at(ctx, 7.5, 16.5, wc), col:Lerp(RGB(255, 255, 255), 0.25), M.Plaster, true)
    windows(ctx, m, w0, w1, 4, 1, 0, DARK, RGB(236, 220, 190))
    for _, y in ipairs({11, 16.5}) do
        for i = 1, 2 do P(m, "Window", V3(0.15, 2, 1.8), at(ctx, y == 11 and -0.56 or 1.44, y, w0 + i * Wd / 3), DARK, M.Glass) end
    end
    Kit.vcyl(m, "Tank", 2.6, 2.8, 0, 0, 0, RGB(30, 30, 32)).CFrame = at(ctx, 8, 20.3, wc) * CFrame.Angles(0, 0, math.rad(90))
    for i = 1, 2 do P(m, "Laundry", V3(0.08, 1.5, 1.6), at(ctx, -0.8, 13, w0 + i * Wd / 3), Kit.pick(CLOTH, i + 4), M.Fabric) end
    return m
end

-- ================================================================ ZONE 3: DELIVERY DISTRICT
local delivery = {}
local DELIVERY_SIGNS = {"ZIPPY EATS • 10 MIN", "BIRYANI EXPRESS", "QUICKMART 24x7", "CLOUD KITCHEN 7", "PARCEL HUB", "DOSA DASH"}

function delivery.midrise(ctx, w0, w1, rng)
    local m = model(ctx, "MidRise")
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    local h = 20 + rng:NextNumber() * 8
    mass(ctx, m, w0, w1, 14, h, Kit.pick(PAL.delivery, rng:NextInteger(1, 60)))
    for y = 5, h - 3, 4 do
        P(m, "WindowBand", V3(0.15, 1.8, Wd - 1.6), at(ctx, -0.06, y, wc), RGB(40, 52, 62), M.Glass)
        P(m, "Ledge", V3(0.7, 0.3, Wd - 1), at(ctx, -0.3, y - 1.2, wc), RGB(210, 206, 198), M.Concrete)
        if rng:NextNumber() < 0.6 then P(m, "ACUnit", V3(0.9, 0.9, 1.3), at(ctx, -0.5, y - 0.6, w0 + 1.5 + rng:NextNumber() * (Wd - 3)), RGB(220, 220, 214), M.Metal) end
    end
    local bb = P(m, "RoofBillboardFrame", V3(0.5, 5, math.min(Wd - 2, 14)), at(ctx, 4, h + 3, wc), DARK, M.Metal)
    Kit.signBoard(m, "RoofBillboard", V3(math.min(Wd - 2, 14), 4.2, 0.2), at(ctx, 3.7, h + 3.2, wc).Position, Kit.facingRoad(ctx.side),
        Kit.pick(DELIVERY_SIGNS, rng:NextInteger(1, 60)), Kit.pick({RGB(230, 80, 40), RGB(40, 150, 90), RGB(220, 40, 80), RGB(40, 90, 200)}, rng:NextInteger(1, 9)), RGB(255, 255, 255))
    return m
end

function delivery.shutterRow(ctx, w0, w1, rng, opts)
    local m = model(ctx, "ShutterRow")
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    local h = 15 + rng:NextNumber() * 3
    mass(ctx, m, w0, w1, 14, h, Kit.pick(PAL.delivery, rng:NextInteger(1, 60)))
    local n = math.max(2, math.floor(Wd / 8))
    for i = 1, n do
        local w = w0 + (i - 0.5) * Wd / n
        P(m, "Shutter", V3(0.2, 4.6, Wd / n - 1.2), at(ctx, -0.1, 2.3, w), RGB(140, 140, 136), M.DiamondPlate)
        P(m, "ShopSign", V3(0.25, 1.1, Wd / n - 1.2), at(ctx, -0.2, 5.3, w), Kit.pick({RGB(40, 120, 70), RGB(200, 60, 40), RGB(40, 80, 170), RGB(230, 150, 30)}, i + rng:NextInteger(1, 5)), M.SmoothPlastic)
    end
    windows(ctx, m, w0, w1, 8.5, 2, 3.6, RGB(40, 52, 62), RGB(200, 196, 188))
    for i = 1, 2 do P(m, "Balcony", V3(1.4, 0.3, 3.2), at(ctx, -0.7, 10.8, w0 + i * Wd / 3), RGB(190, 186, 178), M.Concrete) end
    if opts.sign then sign(ctx, m, opts.sign, -0.3, 6.6, wc, math.min(Wd - 2, 10), RGB(30, 40, 60), RGB(255, 255, 255)) end
    return m
end

function delivery.cloudKitchen(ctx, w0, w1, rng)
    local m = model(ctx, "CloudKitchen")
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    mass(ctx, m, w0, w1, 14, 12, RGB(60, 62, 70), M.Metal)
    local neon = P(m, "NeonStrip", V3(0.2, 0.5, Wd - 1), at(ctx, -0.12, 9.6, wc), Kit.pick({RGB(255, 60, 120), RGB(60, 220, 255), RGB(255, 180, 40)}, rng:NextInteger(1, 9)), M.Neon)
    neon.CastShadow = false
    -- Wall of pick-up lockers.
    for r = 0, 1 do
        for c = 0, 3 do
            P(m, "Locker", V3(0.15, 1.5, 1.5), at(ctx, -0.08, 2 + r * 1.7, w0 + 2 + c * 1.7), Kit.pick({RGB(230, 90, 40), RGB(240, 200, 60), RGB(80, 160, 90)}, r + c), M.Metal)
        end
    end
    for i = 1, 2 do Kit.vcyl(m, "Exhaust", 3, 1.1, 0, 0, 0, RGB(170, 170, 170), M.Metal).CFrame = at(ctx, 6 + i * 2, 13.5, wc) * CFrame.Angles(0, 0, math.rad(90)) end
    sign(ctx, m, Kit.pick(DELIVERY_SIGNS, rng:NextInteger(1, 60)), -0.3, 7.6, wc, math.min(Wd - 2, 10), RGB(20, 20, 24), RGB(255, 200, 60))
    return m
end

-- ================================================================ ZONE 4: BUSINESS CORE
local business = {}
local CORP = {"NOVA CAPITAL", "SKYBRIDGE CORP", "ORBIT TECH", "LOTUS BANK", "APEX HOLDINGS", "ZENITH MEDIA"}

function business.glassTower(ctx, w0, w1, rng)
    local m = model(ctx, "GlassTower")
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    local h = 38 + rng:NextNumber() * 28
    P(m, "Podium", V3(14, 8, Wd - 0.4), at(ctx, 7, 4, wc), RGB(180, 176, 168), M.Granite, true)
    P(m, "Tower", V3(11, h, Wd - 3), at(ctx, 8, 8 + h / 2, wc), Kit.pick(PAL.business, rng:NextInteger(1, 60)), M.Glass, true).Reflectance = 0.25
    for i = 0, 3 do
        P(m, "Fin", V3(0.5, h, 0.5), at(ctx, 2.3, 8 + h / 2, w0 + 1.5 + i * (Wd - 3) / 3), RGB(210, 214, 220), M.Metal)
    end
    P(m, "Crown", V3(12, 1.2, Wd - 2), at(ctx, 8, 8 + h + 0.6, wc), RGB(210, 214, 220), M.Metal)
    Kit.vcyl(m, "Antenna", 10, 0.4, 0, 0, 0, RGB(200, 200, 204), M.Metal).CFrame = at(ctx, 9, 8 + h + 6, wc) * CFrame.Angles(0, 0, math.rad(90))
    P(m, "Entrance", V3(0.2, 5, math.min(Wd - 4, 8)), at(ctx, -0.1, 2.5, wc), RGB(40, 60, 76), M.Glass)
    P(m, "Canopy", V3(3, 0.3, math.min(Wd - 2, 10)), at(ctx, -1.4, 5.6, wc), RGB(210, 214, 220), M.Metal, "query")
    sign(ctx, m, Kit.pick(CORP, rng:NextInteger(1, 60)), -0.3, 7, wc, math.min(Wd - 4, 10), RGB(20, 24, 30), RGB(200, 230, 255))
    return m
end

function business.steppedOffice(ctx, w0, w1, rng)
    local m = model(ctx, "SteppedOffice")
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    local col = RGB(200, 196, 188)
    for i = 0, 2 do
        local d0 = i * 3
        P(m, "Tier" .. i, V3(14 - d0, 12, Wd - 0.4 - i * 2), at(ctx, d0 + (14 - d0) / 2, 6 + i * 12, wc), col, M.Concrete, true)
        P(m, "GlassBand", V3(0.2, 7, Wd - 2 - i * 2), at(ctx, d0 - 0.05, 6.5 + i * 12, wc), RGB(60, 96, 124), M.Glass).Reflectance = 0.2
        if i > 0 then
            P(m, "TerracePlanter", V3(1.4, 1, Wd - 3 - i * 2), at(ctx, d0 - 1.2, i * 12 + 0.5, wc), RGB(70, 110, 60), M.Grass)
        end
    end
    sign(ctx, m, Kit.pick(CORP, rng:NextInteger(1, 60)), -0.3, 11, wc, math.min(Wd - 4, 10), RGB(20, 24, 30), RGB(255, 255, 255))
    return m
end

function business.plaza(ctx, w0, w1, rng)
    local m = model(ctx, "LobbyPlaza")
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    P(m, "Lobby", V3(12, 7, Wd - 0.4), at(ctx, 8, 3.5, wc), RGB(70, 100, 120), M.Glass, true).Reflectance = 0.2
    P(m, "Roof", V3(14, 0.6, Wd), at(ctx, 7, 7.3, wc), RGB(220, 222, 226), M.Metal, "query")
    P(m, "FrontWall", V3(0.6, 7, Wd - 0.4), at(ctx, 0.3, 3.5, wc), RGB(90, 120, 140), M.Glass, true).Reflectance = 0.25
    -- Abstract sculpture of stacked, twisted cubes.
    for i = 0, 2 do
        P(m, "Sculpture", V3(2.2 - i * 0.5, 2.2 - i * 0.5, 2.2 - i * 0.5), at(ctx, 3.5, 8.8 + i * 1.7, wc, i * 25, i * 15, 0), GOLD, M.Foil)
    end
    for i = 1, 2 do
        Kit.vcyl(m, "Planter", 1.2, 2.4, 0, 0, 0, RGB(120, 120, 124), M.Concrete).CFrame = at(ctx, 2, 8.2, w0 + i * Wd / 3) * CFrame.Angles(0, 0, math.rad(90))
        ball(P(m, "Shrub", V3(2.4, 2.4, 2.4), at(ctx, 2, 9.6, w0 + i * Wd / 3), RGB(60, 110, 60), M.LeafyGrass))
    end
    return m
end

-- ================================================================ ZONE 5: ROYAL HEIGHTS
local royal = {}

-- Chhatri: small domed rooftop pavilion (4 slim pillars + slab + dome).
local function chhatri(ctx, m, d, y, w, size, stone)
    for _, o in ipairs({{-1, -1}, {-1, 1}, {1, -1}, {1, 1}}) do
        P(m, "ChhatriPillar", V3(0.3, size, 0.3), at(ctx, d + o[1] * size * 0.35, y + size / 2, w + o[2] * size * 0.35), stone, M.Sandstone)
    end
    P(m, "ChhatriSlab", V3(size * 1.1, 0.3, size * 1.1), at(ctx, d, y + size, w), stone, M.Sandstone)
    ball(P(m, "ChhatriDome", V3(size, size, size), at(ctx, d, y + size + 0.1, w), stone, M.Sandstone))
    P(m, "Finial", V3(0.2, 0.9, 0.2), at(ctx, d, y + size * 1.55, w), GOLD, M.Foil)
end

function royal.palaceWing(ctx, w0, w1, rng)
    local m = model(ctx, "PalaceWing")
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    local stone = Kit.pick(PAL.royal, rng:NextInteger(1, 60))
    local h = 15 + rng:NextNumber() * 4
    P(m, "Plinth", V3(14.6, 1.4, Wd), at(ctx, 7, 0.7, wc), stone:Lerp(RGB(120, 90, 70), 0.3), M.Sandstone, true)
    P(m, "Wing", V3(14, h, Wd - 0.6), at(ctx, 7.3, 1.4 + h / 2, wc), stone, M.Sandstone, true)
    -- One row of tall arched windows over a single gold string course (few, large parts).
    local n = math.max(2, math.floor(Wd / 6.5))
    for i = 1, n do
        local w = w0 + (i - 0.5) * Wd / n
        P(m, "ArchWindow", V3(0.15, 5, 2.2), at(ctx, -0.06, 9, w), RGB(50, 36, 30), M.Glass)
        cyl(P(m, "ArchTop", V3(0.2, 2.2, 2.2), at(ctx, -0.07, 11.5, w, 90), RGB(50, 36, 30), M.Glass))
    end
    P(m, "StringCourse", V3(0.3, 0.4, Wd), at(ctx, -0.15, 6.2, wc), GOLD, M.Foil)
    P(m, "GroundArcade", V3(0.2, 4, Wd - 2), at(ctx, -0.05, 3.4, wc), RGB(80, 56, 44), M.Sandstone)
    P(m, "Cornice", V3(1, 0.7, Wd), at(ctx, -0.3, 1.4 + h - 0.6, wc), GOLD, M.Foil)
    for i = 0, math.floor(Wd / 5) do
        P(m, "Merlon", V3(0.8, 1.1, 1.8), at(ctx, 0.4, 1.4 + h + 0.55, w0 + 1 + i * 5), stone, M.Sandstone)
    end
    chhatri(ctx, m, 5, 1.4 + h, w0 + Wd * 0.25, 3, stone)
    chhatri(ctx, m, 5, 1.4 + h, w0 + Wd * 0.75, 3, stone)
    return m
end

function royal.marbleVilla(ctx, w0, w1, rng)
    local m = model(ctx, "MarbleVilla")
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    local marble = RGB(238, 234, 226)
    P(m, "Plinth", V3(14.6, 1.2, Wd), at(ctx, 7, 0.6, wc), RGB(200, 196, 186), M.Marble, true)
    P(m, "Villa", V3(12, 11, Wd - 1), at(ctx, 8, 6.7, wc), marble, M.Marble, true)
    -- Portico: columns + pediment.
    for i = 0, 3 do
        Kit.vcyl(m, "Column", 8, 0.9, 0, 0, 0, marble, M.Marble).CFrame = at(ctx, 1, 5.2, wc - 4.5 + i * 3) * CFrame.Angles(0, 0, math.rad(90))
    end
    P(m, "Pediment", V3(3, 1, 12), at(ctx, 1, 9.7, wc), marble, M.Marble)
    -- Marble balustrade along the front: the forecourt is private, and now it visibly says so.
    P(m, "Balustrade", V3(0.6, 2.4, Wd - 0.4), at(ctx, 0.3, 1.2, wc), marble, M.Marble, true)
    P(m, "BalustradeRail", V3(0.9, 0.3, Wd - 0.4), at(ctx, 0.3, 2.5, wc), GOLD, M.Foil)
    P(m, "GoldBand", V3(3.1, 0.3, 12.1), at(ctx, 1, 9.1, wc), GOLD, M.Foil)
    -- Central dome on a drum.
    Kit.vcyl(m, "Drum", 3, 7, 0, 0, 0, marble, M.Marble).CFrame = at(ctx, 8, 13.7, wc) * CFrame.Angles(0, 0, math.rad(90))
    ball(P(m, "Dome", V3(7.4, 7.4, 7.4), at(ctx, 8, 15.2, wc), rng:NextNumber() < 0.5 and marble or GOLD, rng:NextNumber() < 0.5 and M.Marble or M.Foil))
    P(m, "Finial", V3(0.3, 2, 0.3), at(ctx, 8, 19.6, wc), GOLD, M.Foil)
    return m
end

function royal.gateway(ctx, w0, w1, rng, opts)
    local m = model(ctx, "RoyalGateway")
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    local stone = RGB(214, 150, 120)
    for _, w in ipairs({w0 + 3, w1 - 3}) do
        P(m, "Tower", V3(8, 22, 6), at(ctx, 4, 11, w), stone, M.Sandstone, true)
        chhatri(ctx, m, 4, 22, w, 4, stone)
    end
    P(m, "ArchSpan", V3(8, 8, Wd - 12), at(ctx, 4, 16, wc), stone, M.Sandstone, true)
    P(m, "Gate", V3(0.4, 12, Wd - 12), at(ctx, 0.2, 6, wc), RGB(80, 40, 30), M.WoodPlanks, true)
    cyl(P(m, "ArchCurve", V3(0.5, Wd - 12, Wd - 12), at(ctx, 0.1, 12, wc, 90), RGB(80, 40, 30), M.WoodPlanks))
    P(m, "GoldStuds", V3(0.2, 0.4, Wd - 12.5), at(ctx, -0.05, 6, wc), GOLD, M.Foil)
    sign(ctx, m, opts.sign or "ROYAL HEIGHTS", -0.3, 18.5, wc, math.min(Wd - 13, 12), RGB(90, 20, 40), RGB(255, 214, 90))
    return m
end

ZoneStyles.Builders = {
    [2] = {market.haveli, market.bazaar, market.tallHouse},
    [3] = {delivery.midrise, delivery.shutterRow, delivery.cloudKitchen},
    [4] = {business.glassTower, business.steppedOffice, business.plaza},
    [5] = {royal.palaceWing, royal.marbleVilla, royal.palaceWing, royal.gateway},
}

-- Build one row segment in the district's style. `variant` picks the design deterministically.
function ZoneStyles.building(ctx, w0, w1, variant, opts)
    local list = ZoneStyles.Builders[ctx.zone]
    local fn = list[((variant - 1) % #list) + 1]
    return fn(ctx, w0, w1, ctx.rng, opts or {})
end

-- The big landmark facing the home alley in each district.
function ZoneStyles.landmark(ctx, w0, w1)
    local z = ctx.zone
    if z == 5 then
        -- Grand palace facade: raised plinth, big central dome, two minaret-free corner towers.
        local m = model(ctx, "GrandPalace")
        local Wd, wc = w1 - w0, (w0 + w1) / 2
        local stone = RGB(236, 206, 170)
        P(m, "Plinth", V3(14.6, 2, Wd), at(ctx, 7, 1, wc), RGB(200, 170, 140), M.Sandstone, true)
        P(m, "Hall", V3(14, 18, Wd - 1), at(ctx, 7.3, 11, wc), stone, M.Sandstone, true)
        Kit.vcyl(m, "Drum", 4, 12, 0, 0, 0, stone, M.Sandstone).CFrame = at(ctx, 7, 22, wc) * CFrame.Angles(0, 0, math.rad(90))
        ball(P(m, "GreatDome", V3(13, 13, 13), at(ctx, 7, 24, wc), RGB(245, 240, 230), M.Marble))
        P(m, "Finial", V3(0.5, 3.5, 0.5), at(ctx, 7, 32, wc), GOLD, M.Foil)
        for _, w in ipairs({w0 + 2.5, w1 - 2.5}) do
            P(m, "CornerTower", V3(5, 24, 5), at(ctx, 5, 12, w), stone, M.Sandstone, true)
            chhatri(ctx, m, 5, 24, w, 3.6, stone)
        end
        P(m, "Portal", V3(0.3, 10, 8), at(ctx, -0.05, 7, wc), RGB(70, 40, 34), M.WoodPlanks)
        cyl(P(m, "PortalArch", V3(0.3, 8, 8), at(ctx, -0.06, 12, wc, 90), RGB(70, 40, 34), M.WoodPlanks))
        P(m, "GoldFrieze", V3(0.4, 0.8, Wd - 2), at(ctx, -0.2, 18.8, wc), GOLD, M.Foil)
        return m
    end
    local list = ZoneStyles.Builders[z]
    return list[1](ctx, w0, w1, ctx.rng, {})
end

-- ================================================================ HOMES (zones 2-5)
-- Same 14x18 footprint and open front as the starter shack; alley walls close the sides.
local HOME = {
    [2] = {Name = "ConcreteRoom", Wall = RGB(170, 200, 186), Floor = RGB(140, 64, 52), FloorMat = M.Concrete, Ceiling = RGB(200, 200, 196), Alley = RGB(150, 136, 118), AlleyMat = M.Cobblestone},
    [3] = {Name = "SmallFlat", Wall = RGB(232, 222, 200), Floor = RGB(196, 196, 190), FloorMat = M.Marble, Ceiling = RGB(240, 238, 232), Alley = RGB(168, 166, 160), AlleyMat = M.Concrete},
    [4] = {Name = "CityApartment", Wall = RGB(220, 218, 214), Floor = RGB(130, 94, 62), FloorMat = M.WoodPlanks, Ceiling = RGB(236, 236, 236), Alley = RGB(90, 92, 98), AlleyMat = M.Granite},
    [5] = {Name = "PalaceSuite", Wall = RGB(240, 226, 196), Floor = RGB(240, 238, 232), FloorMat = M.Marble, Ceiling = RGB(236, 220, 180), Alley = RGB(150, 30, 40), AlleyMat = M.Fabric},
}

local function interior2(m, S, ox)
    -- Concrete Room: charpai cot, steel trunk, ceiling fan, tube light, TV on a stool, gas stove shelf.
    P(m, "CotFrame", V3(6.2, 0.5, 3.4), S(-3.2, 2.1, -6.6), RGB(110, 76, 44), M.Wood, true)
    P(m, "CotWeave", V3(5.8, 0.15, 3.0), S(-3.2, 2.4, -6.6), RGB(200, 180, 130), M.Fabric)
    for _, o in ipairs({{-2.9, -1.5}, {-2.9, 1.5}, {2.9, -1.5}, {2.9, 1.5}}) do P(m, "CotLeg", V3(0.35, 1.3, 0.35), S(-3.2 + o[1], 1.3, -6.6 + o[2]), RGB(90, 60, 36), M.Wood) end
    P(m, "Pillow", V3(1.2, 0.4, 2.2), S(-5.6, 2.7, -6.6), RGB(220, 210, 190), M.Fabric)
    P(m, "SteelTrunk", V3(2.6, 1.4, 1.6), S(1.2, 1.7, -7.6), RGB(60, 90, 140), M.Metal, true)
    P(m, "StoveShelf", V3(4.5, 2.6, 1.8), S(3.5, 2.3, 8), RGB(160, 160, 156), M.Concrete, true)
    P(m, "GasStove", V3(2.4, 0.3, 1.2), S(3.5, 3.75, 8), RGB(40, 40, 42), M.Metal)
    Kit.vcyl(m, "PressureCooker", 1.1, 1, 0, 0, 0, RGB(190, 190, 194), M.Metal).CFrame = S(3.1, 4.5, 8) * CFrame.Angles(0, 0, math.rad(90))
    P(m, "Stool", V3(1.6, 1.6, 1.6), S(-4.6, 1.8, 6.6), RGB(120, 84, 50), M.Wood, true)
    P(m, "TV", V3(1.4, 1.3, 1.9), S(-4.6, 3.25, 6.6), RGB(30, 30, 32), M.Plastic)
    P(m, "Screen", V3(0.05, 1, 1.6), S(-3.88, 3.25, 6.6), RGB(90, 140, 190), M.Neon)
    local tube = P(m, "TubeLight", V3(0.2, 0.2, 4), S(-6.8, 7.5, 0), RGB(235, 245, 255), M.Neon)
    local l = Instance.new("PointLight") l.Color = RGB(235, 240, 255) l.Brightness = 1.2 l.Range = 18 l.Parent = tube
    P(m, "FanHub", V3(0.6, 0.5, 0.6), S(0, 8.6, 0), RGB(120, 110, 100), M.Metal)
    for i = 0, 2 do P(m, "FanBlade", V3(3.2, 0.08, 0.6), S(0, 8.4, 0, i * 120) * CFrame.new(1.8, 0, 0), RGB(150, 140, 126), M.Metal) end
    P(m, "Calendar", V3(0.08, 1.6, 1.2), S(-6.95, 5, 3), RGB(226, 212, 184))
end

local function interior3(m, S, ox)
    -- Small Flat: sofa, coffee table, fridge, dining set, bed, window with curtain, clock.
    P(m, "SofaBase", V3(2.4, 1.2, 5.5), S(-5.4, 1.6, -5.2), RGB(160, 60, 50), M.Fabric, true)
    P(m, "SofaBack", V3(0.8, 1.8, 5.5), S(-6.4, 2.6, -5.2), RGB(150, 54, 46), M.Fabric)
    P(m, "CoffeeTable", V3(2, 0.3, 3), S(-2.6, 2.1, -5.2), RGB(110, 80, 56), M.Wood, true)
    P(m, "Fridge", V3(2, 5.5, 2), S(5.6, 3.75, 7.6), RGB(236, 236, 234), M.SmoothPlastic, true)
    P(m, "DiningTable", V3(3, 0.3, 2), S(1.5, 2.9, 6.8), RGB(130, 94, 60), M.Wood, true)
    for _, o in ipairs({-1.8, 1.8}) do P(m, "Chair", V3(1.2, 2, 1.2), S(1.5 + o, 2, 5.2), RGB(120, 86, 56), M.Wood) end
    P(m, "Bed", V3(4.2, 1, 5.6), S(-4.6, 1.5, 5.8), RGB(110, 80, 56), M.Wood, true)
    P(m, "BedSheet", V3(4, 0.3, 5.4), S(-4.6, 2.15, 5.8), RGB(90, 130, 180), M.Fabric)
    P(m, "Window", V3(4, 3, 0.15), S(0, 5, -9.05), RGB(170, 210, 230), M.Glass)
    for i = -1, 1 do P(m, "Grille", V3(0.15, 3, 0.15), S(i * 1.3, 5, -9), RGB(60, 60, 62), M.Metal) end
    P(m, "Curtain", V3(1.2, 3.6, 0.15), S(-2.6, 5, -8.9), RGB(210, 170, 60), M.Fabric)
    cyl(P(m, "Clock", V3(0.1, 1.2, 1.2), S(-6.95, 6, 0), RGB(240, 240, 236), M.SmoothPlastic))
    local panel = P(m, "CeilingLight", V3(2.4, 0.15, 2.4), S(0, 8.9, 0), RGB(255, 246, 226), M.Neon)
    local l = Instance.new("PointLight") l.Color = RGB(255, 240, 210) l.Brightness = 1.3 l.Range = 20 l.Parent = panel
end

local function interior4(m, S, ox)
    -- City Apartment: floor-to-ceiling window, L-sofa, TV wall, rug, plants, pendant lights, island.
    local glass = P(m, "PanoramaWindow", V3(0.3, 7.5, 16), S(-6.9, 4.8, 0), RGB(150, 190, 220), M.Glass, true)
    glass.Reflectance = 0.3
    P(m, "SofaLong", V3(2.4, 1.2, 7), S(-4.6, 1.6, -4), RGB(80, 84, 92), M.Fabric, true)
    P(m, "SofaSide", V3(5, 1.2, 2.4), S(-2.3, 1.6, -7.4), RGB(80, 84, 92), M.Fabric, true)
    P(m, "SofaBack", V3(0.8, 1.6, 7), S(-5.7, 2.6, -4), RGB(70, 74, 82), M.Fabric)
    P(m, "Rug", V3(6, 0.05, 6), S(-1.5, 1.03, -3.5), RGB(200, 180, 150), M.Fabric)
    P(m, "TVWall", V3(0.6, 4, 7), S(3.5, 3, -8.6, 90), RGB(40, 40, 44), M.Wood)
    P(m, "TVScreen", V3(5.5, 3, 0.1), S(3.5, 3.6, -8.25), RGB(40, 90, 160), M.Neon)
    P(m, "Island", V3(3, 2.8, 5), S(3.8, 2.4, 6), RGB(240, 240, 238), M.Marble, true)
    for i = -1, 1 do
        P(m, "PendantWire", V3(0.05, 2.2, 0.05), S(3.8, 7.9, 6 + i * 1.6), RGB(20, 20, 20))
        local b = ball(P(m, "Pendant", V3(0.7, 0.7, 0.7), S(3.8, 6.7, 6 + i * 1.6), RGB(255, 226, 170), M.Neon))
        if i == 0 then local l = Instance.new("PointLight") l.Color = RGB(255, 226, 180) l.Brightness = 1.4 l.Range = 20 l.Parent = b end
    end
    for _, z in ipairs({-8, 8}) do
        Kit.vcyl(m, "Pot", 1.4, 1.4, 0, 0, 0, RGB(230, 230, 226), M.Concrete).CFrame = S(-6, 1.7, z) * CFrame.Angles(0, 0, math.rad(90))
        ball(P(m, "Plant", V3(2.2, 2.2, 2.2), S(-6, 3.4, z), RGB(60, 120, 60), M.LeafyGrass))
    end
    P(m, "Artwork", V3(0.1, 2.4, 3.6), S(-6.8, 5, 4), RGB(220, 120, 60), M.SmoothPlastic)
end

local function interior5(m, S, ox)
    -- Palace Suite: canopy bed, chandelier, throne chair, red carpet with gold border, gilded arches.
    P(m, "BedBase", V3(6, 1.4, 6), S(-3.5, 1.7, -5.5), GOLD, M.Foil, true)
    P(m, "Mattress", V3(5.6, 0.8, 5.6), S(-3.5, 2.8, -5.5), RGB(150, 30, 40), M.Fabric)
    for _, o in ipairs({{-2.8, -2.8}, {-2.8, 2.8}, {2.8, -2.8}, {2.8, 2.8}}) do
        P(m, "BedPost", V3(0.35, 7, 0.35), S(-3.5 + o[1], 4.5, -5.5 + o[2]), GOLD, M.Foil)
    end
    P(m, "Canopy", V3(6.2, 0.3, 6.2), S(-3.5, 8, -5.5), RGB(150, 30, 40), M.Fabric)
    for _, o in ipairs({-3, 3}) do P(m, "Drape", V3(0.1, 5, 1.4), S(-3.5 + o, 5.4, -2.6), RGB(170, 40, 50), M.Fabric) end
    for i = 1, 3 do P(m, "Pillow", V3(1.2, 0.6, 1.6), S(-5.8, 3.5, -7.3 + i * 1.4), RGB(230, 190, 80), M.Fabric) end
    P(m, "Carpet", V3(12, 0.05, 6), S(0.5, 1.03, 2.5), RGB(150, 30, 40), M.Fabric)
    P(m, "CarpetBorder", V3(12.4, 0.04, 6.4), S(0.5, 1.02, 2.5), GOLD, M.Foil)
    P(m, "ThroneSeat", V3(2.6, 1.6, 2.6), S(-5, 1.8, 5), GOLD, M.Foil, true)
    P(m, "ThroneCushion", V3(2.2, 0.5, 2.2), S(-5, 2.85, 5), RGB(150, 30, 40), M.Fabric)
    P(m, "ThroneBack", V3(0.6, 5, 2.8), S(-6.2, 4.6, 5), GOLD, M.Foil)
    ball(P(m, "ThroneCrest", V3(1.8, 1.8, 1.8), S(-6.2, 7.3, 5), GOLD, M.Foil))
    -- Chandelier.
    cyl(P(m, "ChandelierRing", V3(0.3, 3.4, 3.4), S(0.5, 7.8, 0, 0, 0, 90), GOLD, M.Foil))
    for i = 0, 5 do
        local a = math.rad(i * 60)
        ball(P(m, "Crystal", V3(0.5, 0.5, 0.5), S(0.5 + math.cos(a) * 1.5, 7.4, math.sin(a) * 1.5), RGB(255, 246, 220), M.Neon))
    end
    local core = ball(P(m, "ChandelierCore", V3(0.9, 0.9, 0.9), S(0.5, 7.3, 0), RGB(255, 236, 190), M.Neon))
    local l = Instance.new("PointLight") l.Color = RGB(255, 220, 160) l.Brightness = 1.6 l.Range = 22 l.Shadows = true l.Parent = core
    -- Gilded arches on the side walls.
    for _, sz in ipairs({-8.8, 8.8}) do
        for i = -1, 1 do
            P(m, "Pilaster", V3(0.6, 7, 0.4), S(i * 4, 4.5, sz), GOLD, M.Foil)
        end
        P(m, "ArchBand", V3(12, 0.5, 0.4), S(0, 8.2, sz), GOLD, M.Foil)
    end
    P(m, "Mirror", V3(0.1, 3, 2), S(-6.95, 5, 1), RGB(200, 220, 230), M.Glass).Reflectance = 0.6
end

local INTERIORS = {[2] = interior2, [3] = interior3, [4] = interior4, [5] = interior5}

function ZoneStyles.home(folder, cx, W, zone)
    local spec = HOME[zone]
    local m = Instance.new("Model") m.Name = spec.Name m.Parent = folder
    local ox = cx + (W.HomeBackX + W.AlleyBackX) / 2
    local function S(sx, y, sz, ry, rx, rz) return CF(ox + sx, y, sz, ry, rx, rz) end
    P(m, "Floor", V3(14.4, 1.0, 18.4), S(0, 0.5, 0), spec.Floor, spec.FloorMat, true)
    P(m, "Back", V3(0.4, 9.5, 18.4), S(-7.2, 5.5, 0), spec.Wall, M.Plaster, true)
    P(m, "Left", V3(14.4, 9.5, 0.4), S(0, 5.5, -9.2), spec.Wall, M.Plaster, true)
    P(m, "Right", V3(14.4, 9.5, 0.4), S(0, 5.5, 9.2), spec.Wall, M.Plaster, true)
    P(m, "Ceiling", V3(15.4, 0.6, 19.4), S(0, 10.5, 0), spec.Ceiling, M.Plaster, true)
    -- Front: open like the shack, framed by a lintel so the room reads from the alley.
    P(m, "Lintel", V3(0.8, 1.2, 18.4), S(7.1, 9.6, 0), zone == 5 and GOLD or spec.Wall:Lerp(RGB(90, 80, 70), 0.3), zone == 5 and M.Foil or M.Plaster)
    INTERIORS[zone](m, S, ox)
    -- Alley between the home and the street, dressed per district.
    local x0, x1 = cx + W.AlleyBackX, cx - W.SidewalkOuter
    local xm, len = (x0 + x1) / 2, x1 - x0
    P(m, "AlleyFloor", V3(len, 0.8, W.AlleyHalfWidth * 2), CFrame.new(xm, 0.4, 0), spec.Alley, spec.AlleyMat, true)
    local wallCol = spec.Wall:Lerp(RGB(120, 110, 100), 0.25)
    for _, s in ipairs({-1, 1}) do
        P(m, "AlleyWall", V3(len, 12, 0.6), CFrame.new(xm, 6, s * (W.AlleyHalfWidth + 0.3)), wallCol, M.Plaster, true)
        P(m, "HomeWall", V3(2, 12, 3.4), CFrame.new(x0 - 1, 6, s * (W.AlleyHalfWidth + 1.7)), wallCol, M.Plaster, true)
        if zone == 2 then
            for i = 1, 3 do
                ball(P(m, "Lantern", V3(0.8, 0.8, 0.8), CFrame.new(x0 + i * len / 4, 8.5, s * (W.AlleyHalfWidth - 0.4)), Kit.pick(CLOTH, i + s), M.Neon))
            end
        elseif zone == 3 then
            P(m, "MeterBoxes", V3(3, 2, 0.4), CFrame.new(xm, 5, s * (W.AlleyHalfWidth - 0.1)), RGB(120, 120, 116), M.Metal)
        elseif zone == 4 then
            P(m, "LEDStrip", V3(len, 0.15, 0.15), CFrame.new(xm, 9, s * (W.AlleyHalfWidth - 0.1)), RGB(200, 230, 255), M.Neon)
            Kit.vcyl(m, "Planter", 1.2, 1.8, x0 + len * 0.7, 0.8, s * (W.AlleyHalfWidth - 1.2), RGB(60, 60, 64), M.Concrete)
        elseif zone == 5 then
            for i = 1, 3 do
                Kit.vcyl(m, "Colonnade", 9, 0.8, x0 + i * len / 4, 0.8, s * (W.AlleyHalfWidth - 0.6), RGB(240, 234, 222), M.Marble)
            end
            P(m, "GoldFrieze", V3(len, 0.5, 0.3), CFrame.new(xm, 10, s * (W.AlleyHalfWidth - 0.2)), GOLD, M.Foil)
        end
    end
    local l = Kit.signBoard(m, "HomeSign", V3(4.6, 1.2, 0.15), V3(x1 - 0.5, 10.6, 0), V3(1, 0, 0), ({[2] = "MY CONCRETE ROOM", [3] = "MY SMALL FLAT", [4] = "MY CITY APARTMENT", [5] = "MY PALACE"})[zone], zone == 5 and RGB(90, 20, 40) or RGB(30, 40, 60), RGB(255, 226, 150))
    return m
end

return ZoneStyles
