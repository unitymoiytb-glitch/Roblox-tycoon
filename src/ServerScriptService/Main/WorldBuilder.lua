-- WorldBuilder: generates workspace.SIT_World.
--
-- Every district is one compact, SEALED block laid out across the road:
--
--   (west)  starter room -> short alley -> Raju -> sidewalk | 4 lanes | sidewalk -> drop houses  (east)
--
-- Local X is measured from the district centre, the road runs along Z.
-- Walkable space is ONLY: both sidewalks + road (Z -110..110), the home alley and the home room.
-- Two layers keep the player inside it:
--   1. visual: shop counters, tin walls, compound walls, carts, tunnel buildings at the road ends
--   2. GameplayBounds: 60-stud invisible walls that trace the exact edge of the walkable space
-- So the only way from the home side to a drop point is straight through the traffic lanes.
local WorldBuilder = {}

local rad = math.rad
local V3 = Vector3.new
local RGB = Color3.fromRGB
local M = Enum.Material

-- ------------------------------------------------------------ palette
local C = {
    rust1 = RGB(128,74,44), rust2 = RGB(112,64,40), rust3 = RGB(140,88,52), rust4 = RGB(104,74,50),
    tin1 = RGB(98,100,96), tin2 = RGB(86,94,96), tin3 = RGB(112,106,98),
    tarpBlue = RGB(52,86,124), tarpGreen = RGB(62,98,70), tarpOrange = RGB(196,110,46),
    wood = RGB(98,70,44), woodDark = RGB(72,50,32), woodLight = RGB(130,98,62),
    mud = RGB(84,64,44), mudDark = RGB(66,50,36), dirt = RGB(96,74,52),
    concrete = RGB(128,120,108), plaster = RGB(170,156,132), brick = RGB(132,78,56),
    dark = RGB(26,24,22), black = RGB(18,18,18),
    paint = {RGB(190,118,126), RGB(72,146,146), RGB(150,166,86), RGB(112,148,186), RGB(196,152,72), RGB(170,120,170)},
    cloth = {RGB(206,72,96), RGB(230,164,40), RGB(66,140,110), RGB(226,220,206), RGB(88,112,190), RGB(186,76,48), RGB(150,90,160)},
}
local RUSTS = {C.rust1, C.tin1, C.rust2, C.tin2, C.rust3, C.tin3, C.rust4}

-- ------------------------------------------------------------ part helpers
-- Decorative by default: no collision, no touch, no raycast queries.
local function P(parent, name, size, cf, color, material, collide)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored = true
    p.Size = size
    p.CFrame = cf
    p.Color = color
    p.Material = material or M.SmoothPlastic
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.CanCollide = collide == true
    p.CanTouch = false
    -- Solid geometry stays queryable so the camera does not clip through walls/roofs.
    p.CanQuery = collide == true or collide == "query"
    p.CastShadow = (size.X * size.Y * size.Z) > 3
    p.Parent = parent
    return p
end

local function cyl(p)
    p.Shape = Enum.PartType.Cylinder
    return p
end

local function ball(p)
    p.Shape = Enum.PartType.Ball
    return p
end

-- CFrame helper: yaw first, then pitch/roll (all degrees).
local function CF(x, y, z, ry, rx, rz)
    local cf = CFrame.new(x, y, z)
    if ry and ry ~= 0 then cf = cf * CFrame.Angles(0, rad(ry), 0) end
    if (rx and rx ~= 0) or (rz and rz ~= 0) then cf = cf * CFrame.Angles(rad(rx or 0), 0, rad(rz or 0)) end
    return cf
end

-- A vertical cylinder (axis along Y): drums, buckets, tanks, poles.
local function vcyl(parent, name, height, dia, x, y, z, color, material, collide)
    return cyl(P(parent, name, V3(height, dia, dia), CFrame.new(x, y, z) * CFrame.Angles(0, 0, rad(90)), color, material, collide))
end

-- Two-segment sagging wire between two points.
local function wire(parent, a, b, sag, color)
    local mid = (a + b) / 2 - V3(0, sag or 0.8, 0)
    for _, seg in ipairs({{a, mid}, {mid, b}}) do
        local p0, p1 = seg[1], seg[2]
        local len = (p1 - p0).Magnitude
        P(parent, "Wire", V3(0.07, 0.07, len), CFrame.lookAt((p0 + p1) / 2, p1), color or C.black, M.SmoothPlastic)
    end
end

local function surfaceSign(part, text, bg, fg, face, font)
    local sg = Instance.new("SurfaceGui")
    sg.Name = "Sign"
    sg.Face = face or Enum.NormalId.Front
    sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    sg.PixelsPerStud = 36
    sg.LightInfluence = 1
    sg.MaxDistance = 220
    sg.Parent = part
    local l = Instance.new("TextLabel")
    l.Size = UDim2.fromScale(1, 1)
    l.BackgroundColor3 = bg or RGB(230,200,60)
    l.BackgroundTransparency = bg and 0 or 1
    l.TextColor3 = fg or RGB(30,24,20)
    l.TextScaled = true
    l.TextWrapped = true
    -- Hand-painted look; fall back to a stock font if this one is ever unavailable.
    if not pcall(function() l.Font = font or Enum.Font.Sarpanch end) then l.Font = Enum.Font.GothamBold end
    l.Text = text
    l.Parent = sg
    return sg
end

-- Sign board that faces a direction (unit vector in XZ).
local function signBoard(parent, name, size, pos, facing, text, bg, fg)
    local p = P(parent, name, size, CFrame.lookAt(pos, pos + facing), bg or RGB(230,200,60), M.SmoothPlastic)
    surfaceSign(p, text, bg, fg, Enum.NormalId.Front)
    return p
end

-- ------------------------------------------------------------ bounds
local function boundsWall(folder, name, x0, x1, z0, z1, height)
    local sx, sz = math.abs(x1 - x0), math.abs(z1 - z0)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored = true
    p.Size = V3(sx, height, sz)
    p.CFrame = CFrame.new((x0 + x1) / 2, height / 2 - 1, (z0 + z1) / 2)
    p.Transparency = 1
    p.CanCollide = true
    p.CanTouch = false
    p.CanQuery = false -- camera and raycasts ignore it
    p.CastShadow = false
    p.Parent = folder
    return p
end

-- ------------------------------------------------------------ district context
-- side = -1 (west row, fronts face +X) or 1 (east row, fronts face -X).
-- d = depth behind the front line (0 at the sidewalk edge, growing away from the road), w = world Z.
local function rowCF(cx, W, side, d, y, w, ry, rx, rz)
    local x = cx + side * (W.SidewalkOuter + d)
    if side < 0 then ry, rz = ry and -ry, rz and -rz end
    return CF(x, y, w, ry, rx, rz)
end

local function facingRoad(side) return V3(-side, 0, 0) end

-- ------------------------------------------------------------ row structures
local builders = {}

-- Generic corrugated tin shack, fronting the sidewalk.
-- style: "closed" (tin front + door) or "counter" (shop counter + half-rolled shutter)
local function tinShack(ctx, w0, w1, opts)
    local folder, cx, W, side, rng = ctx.folder, ctx.cx, ctx.W, ctx.side, ctx.rng
    local m = Instance.new("Model") m.Name = opts.name or "Shack" m.Parent = folder
    local D = opts.depth or 15
    local H = opts.height or (8.6 + rng:NextNumber() * 1.6)
    local Wd = w1 - w0
    local wc = (w0 + w1) / 2
    local function at(d, y, w, ry, rx, rz) return rowCF(cx, W, side, d, y, w, ry, rx, rz) end
    local ci = rng:NextInteger(1, #RUSTS)
    local function rust(k) return RUSTS[((ci + k) % #RUSTS) + 1] end
    -- Side and back walls (solid).
    P(m, "SideA", V3(D, H - 0.2, 0.3), at(D / 2, (H - 0.2) / 2, w0 + 0.15), rust(0), M.CorrodedMetal, true)
    P(m, "SideB", V3(D, H - 0.6, 0.3), at(D / 2, (H - 0.6) / 2, w1 - 0.15), rust(2), M.CorrodedMetal, true)
    P(m, "Back", V3(0.3, H - 1.4, Wd), at(D - 0.15, (H - 1.4) / 2, wc), rust(4), M.CorrodedMetal, true)
    -- Uneven two-sheet roof sloping to the back, overhanging the sidewalk.
    local slope = 5.5 + rng:NextNumber() * 3
    for i, half in ipairs({-1, 1}) do
        local wid = Wd / 2 + 0.35
        P(m, "Roof" .. i, V3(D + 3.0, 0.22, wid), at((D - 3.0) / 2, H - 0.55 + i * 0.07, wc + half * Wd / 4, rng:NextNumber() * 2 - 1, rng:NextNumber() * 2 - 1, -slope), rust(i + 1), M.CorrodedMetal, "query")
    end
    -- Front posts.
    P(m, "PostA", V3(0.55, H + 0.2, 0.55), at(0.3, (H + 0.2) / 2, w0 + 0.4), C.woodDark, M.Wood)
    P(m, "PostB", V3(0.55, H + 0.2, 0.55), at(0.3, (H + 0.2) / 2, w1 - 0.4), C.woodDark, M.Wood)
    if opts.style == "counter" then
        P(m, "Counter", V3(1.4, 3.0, Wd - 1.4), at(0.9, 1.5, wc), C.wood, M.WoodPlanks, true)
        P(m, "CounterTop", V3(1.9, 0.2, Wd - 1.1), at(0.8, 3.1, wc), C.woodLight, M.Wood)
        P(m, "ShutterDrum", V3(0.9, 0.9, Wd - 0.8), at(0.55, H - 1.1, wc), C.tin1, M.Metal)
        P(m, "Shutter", V3(0.15, 2.0, Wd - 1.0), at(0.45, H - 2.5, wc), RGB(120,118,112), M.DiamondPlate)
        P(m, "BackGoods", V3(0.9, 3.4, Wd - 2.2), at(D - 0.9, 3.4, wc), opts.goods or C.cloth[rng:NextInteger(1, #C.cloth)], M.Fabric)
        P(m, "Awning", V3(3.2, 0.12, Wd - 0.6), at(-1.3, H - 2.0, wc, 0, 0, 14), opts.awning or C.cloth[rng:NextInteger(1, #C.cloth)], M.Fabric)
        local bulb = ball(P(m, "ShopBulb", V3(0.45, 0.45, 0.45), at(2.4, H - 2.4, wc), RGB(255,214,150), M.Neon))
        bulb.CastShadow = false
    else
        local door = 3.2
        local sideW = (Wd - door) / 2
        P(m, "FrontA", V3(0.3, H - 0.4, sideW), at(0.15, (H - 0.4) / 2, w0 + sideW / 2), rust(3), M.CorrodedMetal, true)
        P(m, "FrontB", V3(0.3, H - 0.8, sideW), at(0.15, (H - 0.8) / 2, w1 - sideW / 2), rust(5), M.CorrodedMetal, true)
        P(m, "OverDoor", V3(0.3, H - 7, door), at(0.15, 7 + (H - 7) / 2, wc), rust(1), M.CorrodedMetal, true)
        P(m, "Door", V3(0.25, 6.4, door), at(0.45, 3.2, wc), opts.door or C.woodDark, M.WoodPlanks, true)
        P(m, "WindowCloth", V3(0.1, 1.8, math.min(2.6, sideW - 0.8)), at(-0.05, 5.0, w0 + sideW / 2, 0, 0, 0), C.cloth[rng:NextInteger(1, #C.cloth)], M.Fabric)
    end
    -- One patched sheet so no two shacks read the same.
    P(m, "Patch", V3(0.12, 2.2 + rng:NextNumber() * 2, 2.4 + rng:NextNumber() * 2), at(-0.12, 2.6 + rng:NextNumber() * 3, w0 + 1.6 + rng:NextNumber() * (Wd - 3.2), 0, rng:NextNumber() * 8 - 4, 0), rng:NextNumber() < 0.5 and C.tarpBlue or rust(6), rng:NextNumber() < 0.5 and M.Fabric or M.CorrodedMetal)
    if opts.tank then
        vcyl(m, "WaterTank", 2.6, 2.8, 0, H + 1.1, 0, RGB(32,32,34), M.SmoothPlastic).CFrame = at(D * 0.55, H + 1.1, wc + Wd * 0.2) * CFrame.Angles(0, 0, rad(90))
    end
    if opts.laundry then
        local y = H - 2.2
        P(m, "Line", V3(0.06, 0.06, Wd - 1), at(-1.6, y, wc), C.black)
        for i = 1, 3 do
            P(m, "Cloth", V3(0.08, 1.5 + rng:NextNumber(), 1.2 + rng:NextNumber() * 0.8), at(-1.6, y - 1.0, w0 + i * Wd / 4), C.cloth[rng:NextInteger(1, #C.cloth)], M.Fabric)
        end
    end
    if opts.drum then
        vcyl(m, "Drum", 2.7, 2.1, 0, 0, 0, RGB(40,86,140), M.SmoothPlastic, true).CFrame = at(-0.6, 1.35 + 0.8, w0 + 1.4) * CFrame.Angles(0, 0, rad(90))
    end
    if opts.sign then
        local pos = at(-0.35, H - 1.6, wc).Position
        signBoard(m, "Sign", V3(math.min(Wd - 2, 7), 1.5, 0.15), pos, facingRoad(side), opts.sign, opts.signBg, opts.signFg)
    end
    return m
end

-- Brick ground floor + tin upper room: the "doing slightly better" neighbour.
local function twoStorey(ctx, w0, w1, opts)
    local folder, cx, W, side, rng = ctx.folder, ctx.cx, ctx.W, ctx.side, ctx.rng
    local m = Instance.new("Model") m.Name = opts.name or "House" m.Parent = folder
    local D, Wd, wc = opts.depth or 14, w1 - w0, (w0 + w1) / 2
    local function at(d, y, w, ry, rx, rz) return rowCF(cx, W, side, d, y, w, ry, rx, rz) end
    local paint = opts.paint or C.paint[rng:NextInteger(1, #C.paint)]
    local H1 = 8.4
    P(m, "Ground", V3(D, H1, Wd - 0.2), at(D / 2, H1 / 2, wc), paint, M.Concrete, true)
    P(m, "Plinth", V3(0.3, 1.2, Wd - 0.2), at(-0.05, 0.6, wc), C.concrete, M.Concrete)
    P(m, "Door", V3(0.2, 6.2, 3.0), at(-0.08, 3.1, opts.doorW or wc), opts.door or RGB(70,110,140), M.WoodPlanks)
    P(m, "Window", V3(0.2, 2.0, 2.6), at(-0.08, 5.0, wc + (Wd / 2 - 2.4) * (opts.doorW and -1 or 1)), C.dark, M.SmoothPlastic)
    P(m, "Slab", V3(D + 2.2, 0.45, Wd + 0.2), at(D / 2 - 1.1, H1 + 0.22, wc), C.concrete, M.Concrete, "query")
    P(m, "Rail", V3(0.15, 1.2, Wd), at(-2.0, H1 + 1.05, wc), RGB(60,62,64), M.Metal)
    local upper = RUSTS[rng:NextInteger(1, #RUSTS)]
    P(m, "Upper", V3(D - 3.5, 6.0, Wd - 1.2), at(D / 2 + 1.0, H1 + 3.4, wc), upper, M.CorrodedMetal, true)
    P(m, "UpperDoor", V3(0.2, 4.6, 2.2), at(2.2, H1 + 2.7, wc + Wd / 4), C.woodDark, M.WoodPlanks)
    P(m, "UpperRoof", V3(D - 1.5, 0.22, Wd - 0.4), at(D / 2 + 0.6, H1 + 6.6, wc, 0, 0, -4), RUSTS[rng:NextInteger(1, #RUSTS)], M.CorrodedMetal, "query")
    vcyl(m, "WaterTank", 3.0, 3.2, 0, 0, 0, RGB(30,30,32), M.SmoothPlastic).CFrame = at(D - 3, H1 + 8.4, wc - Wd / 4) * CFrame.Angles(0, 0, rad(90))
    for i = 1, 2 do
        P(m, "Laundry", V3(0.08, 1.6, 1.8), at(-2.1, H1 + 0.5, w0 + i * Wd / 3), C.cloth[rng:NextInteger(1, #C.cloth)], M.Fabric)
    end
    if opts.sign then
        signBoard(m, "Sign", V3(math.min(Wd - 2, 8), 1.6, 0.15), at(-0.3, H1 - 1.3, wc).Position, facingRoad(side), opts.sign, opts.signBg, opts.signFg)
    end
    return m
end

-- Tall corrugated compound wall with a tree peeking over: closes long stretches cheaply.
local function compound(ctx, w0, w1, opts)
    local folder, cx, W, side, rng = ctx.folder, ctx.cx, ctx.W, ctx.side, ctx.rng
    local m = Instance.new("Model") m.Name = "CompoundWall" m.Parent = folder
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    local function at(d, y, w, ry, rx, rz) return rowCF(cx, W, side, d, y, w, ry, rx, rz) end
    P(m, "Wall", V3(0.6, 11, Wd), at(0.3, 5.5, wc), RUSTS[rng:NextInteger(1, #RUSTS)], M.CorrodedMetal, true)
    local n = math.max(2, math.floor(Wd / 9))
    for i = 1, n do
        local ww = Wd / n
        P(m, "Sheet", V3(0.15, 6 + rng:NextNumber() * 4, ww + 0.6), at(-0.08, 3.5 + rng:NextNumber(), w0 + (i - 0.5) * ww, 0, rng:NextNumber() * 3 - 1.5, 0), RUSTS[rng:NextInteger(1, #RUSTS)], M.CorrodedMetal)
    end
    if opts.tree ~= false then
        local tw = wc + (rng:NextNumber() - 0.5) * Wd * 0.4
        vcyl(m, "Trunk", 13, 1.4, 0, 0, 0, RGB(84,66,50), M.Wood).CFrame = at(6, 6.5, tw) * CFrame.Angles(0, 0, rad(90))
        for i = 1, 3 do
            ball(P(m, "Leaves", V3(1, 1, 1) * (7 + rng:NextNumber() * 3), at(5 + rng:NextNumber() * 3, 13 + rng:NextNumber() * 3, tw + (i - 2) * 3.5), RGB(68 + i * 6, 100 + i * 4, 52), M.LeafyGrass))
        end
    end
    -- Scrap heaped against the wall base.
    P(m, "Scrap", V3(2.2, 2.0, 4.5), at(-1.1, 1.0, w0 + Wd * 0.3, 18, 0, 12), C.tin1, M.CorrodedMetal)
    cyl(P(m, "Tyre", V3(0.8, 2.4, 2.4), at(-0.7, 1.3, w0 + Wd * 0.6, 90, 0, 10), C.black, M.Rubber))
    return m
end

-- Closed promotion gate with a sign naming the next district. The guard stands in front of it.
local function gate(ctx, w0, w1, opts)
    local folder, cx, W, side = ctx.folder, ctx.cx, ctx.W, ctx.side
    local m = Instance.new("Model") m.Name = "PromotionGate" m.Parent = folder
    local wc = (w0 + w1) / 2
    local function at(d, y, w, ry, rx, rz) return rowCF(cx, W, side, d, y, w, ry, rx, rz) end
    P(m, "PillarA", V3(2.2, 13, 2.2), at(1.4, 6.5, w0 + 1.1), C.plaster, M.Brick, true)
    P(m, "PillarB", V3(2.2, 13, 2.2), at(1.4, 6.5, w1 - 1.1), C.plaster, M.Brick, true)
    P(m, "Grille", V3(0.3, 8, w1 - w0 - 4.4), at(2.6, 4, wc), RGB(64,66,68), M.DiamondPlate, true)
    P(m, "WallTop", V3(0.8, 5, w1 - w0 - 4.4), at(2.6, 10.5, wc), C.plaster, M.Concrete, true)
    signBoard(m, "GateSign", V3(w1 - w0 - 1, 2.6, 0.3), at(0.2, 14.3, wc).Position, facingRoad(side), opts.sign or "NEXT DISTRICT", RGB(40,60,120), RGB(255,230,120))
    P(m, "Beam", V3(1.2, 1.2, w1 - w0), at(1.4, 13.2, wc), C.plaster, M.Concrete)
    P(m, "Stripe", V3(0.12, 0.9, w1 - w0 - 4.6), at(2.4, 7.2, wc), RGB(230,190,40), M.SmoothPlastic)
    return m
end

-- Street-facing landmark opposite the home alley: the thing you see from your bed.
local function landmark(ctx, w0, w1, opts)
    local folder, cx, W, side = ctx.folder, ctx.cx, ctx.W, ctx.side
    local m = Instance.new("Model") m.Name = "Landmark" m.Parent = folder
    local Wd, wc, D = w1 - w0, (w0 + w1) / 2, 14
    local function at(d, y, w, ry, rx, rz) return rowCF(cx, W, side, d, y, w, ry, rx, rz) end
    P(m, "Floor1", V3(D, 8.5, Wd), at(D / 2, 4.25, wc), RGB(72,146,146), M.Concrete, true)
    P(m, "Shutter", V3(0.2, 5.6, Wd - 6), at(-0.1, 2.8, wc), RGB(120,120,116), M.DiamondPlate)
    P(m, "ShopAwning", V3(3.0, 0.14, Wd - 4), at(-1.4, 6.6, wc, 0, 0, 15), RGB(196,60,52), M.Fabric)
    signBoard(m, "ShopSign", V3(Wd - 5, 1.7, 0.2), at(-0.3, 7.6, wc).Position, facingRoad(side), opts.sign or "KIRANA STORE", RGB(236,196,50), RGB(120,20,20))
    P(m, "Floor2", V3(D - 1, 7, Wd - 1), at(D / 2 + 0.5, 12, wc), RGB(196,122,134), M.Concrete, true)
    P(m, "Balcony", V3(2.4, 0.4, Wd - 3), at(-1.0, 8.9, wc), C.concrete, M.Concrete)
    P(m, "BalconyRail", V3(0.15, 1.3, Wd - 3), at(-2.1, 9.75, wc), RGB(40,110,90), M.Metal)
    for i = 1, 3 do
        P(m, "Window", V3(0.2, 2.2, 2.2), at(-0.02, 12.2, w0 + i * Wd / 4), C.dark)
    end
    for i = 1, 3 do
        P(m, "Saree", V3(0.08, 2.2, 2.0), at(-2.15, 9.1, w0 + 3 + i * (Wd - 6) / 4), C.cloth[i + 1], M.Fabric)
    end
    P(m, "Floor3", V3(D - 5, 5.5, Wd - 6), at(D / 2 + 2.5, 18.2, wc), C.rust1, M.CorrodedMetal, true)
    P(m, "Roof3", V3(D - 3.5, 0.25, Wd - 4.5), at(D / 2 + 2.2, 21.1, wc, 0, 0, -4), C.tin1, M.CorrodedMetal, "query")
    vcyl(m, "Tank", 3.0, 3.4, 0, 0, 0, RGB(30,30,32), M.SmoothPlastic).CFrame = at(2.5, 17.1, w0 + 3) * CFrame.Angles(0, 0, rad(90))
    vcyl(m, "Tank", 3.0, 3.4, 0, 0, 0, RGB(210,190,60), M.SmoothPlastic).CFrame = at(2.5, 17.1, w1 - 3) * CFrame.Angles(0, 0, rad(90))
    -- Big faded wall advert on the south side wall, seen when walking down the far sidewalk.
    local ad = P(m, "WallAd", V3(D - 2, 6, 0.2), at(D / 2, 12.5, w0 - 0.12), RGB(236,226,196), M.SmoothPlastic)
    ad.CFrame = CFrame.lookAt(ad.Position, ad.Position + V3(0, 0, -1))
    surfaceSign(ad, "GOLDEN CUP CHAI\n₹10 ONLY", RGB(236,226,196), RGB(170,40,30), Enum.NormalId.Front)
    return m
end

-- Mechanic's workshop: open front blocked by a workbench and tyre stacks, parked scooter inside.
local function garage(ctx, w0, w1, opts)
    local folder, cx, W, side, rng = ctx.folder, ctx.cx, ctx.W, ctx.side, ctx.rng
    local m = tinShack(ctx, w0, w1, {name = "MechanicGarage", style = "counter", depth = 15, height = 10, sign = opts.sign, signBg = RGB(40,80,140), signFg = RGB(255,255,255), goods = RGB(60,60,64), awning = RGB(52,86,124)})
    local wc = (w0 + w1) / 2
    local function at(d, y, w, ry, rx, rz) return rowCF(cx, W, side, d, y, w, ry, rx, rz) end
    for i, w in ipairs({w0 + 1.6, w1 - 1.6}) do
        for k = 0, 2 do
            cyl(P(m, "TyreStack", V3(0.8, 2.3, 2.3), at(1.2, 0.5 + k * 0.82, w, 0, 0, 90), C.black, M.Rubber))
        end
    end
    if ctx.VehicleFactory then
        local sc = ctx.VehicleFactory.build("scooter", rng:NextInteger(1, 50), {rider = false})
        sc.Name = "RepairScooter"
        sc:PivotTo(at(6, 0.9, wc, 70))
        sc.Parent = m
    end
    P(m, "ToolBoard", V3(0.15, 2.6, 5), at(14.6, 5.2, wc), RGB(170,150,110), M.WoodPlanks)
    return m
end

-- Barricade that fully closes a sidewalk: cart + crates + tin sheet, backed by an invisible blocker.
local function sidewalkBarricade(ctx, w)
    local folder, cx, W, side, bounds = ctx.folder, ctx.cx, ctx.W, ctx.side, ctx.bounds
    local m = Instance.new("Model") m.Name = "SidewalkBarricade" m.Parent = folder
    local x0 = cx + side * W.RoadHalfWidth
    local x1 = cx + side * W.SidewalkOuter
    local xm = (x0 + x1) / 2
    -- Handcart loaded with sacks (collides).
    P(m, "Cart", V3(4.6, 0.35, 2.6), CF(xm + side * 0.4, 2.0, w, 0, 0, side * 4), C.wood, M.WoodPlanks, true)
    P(m, "CartBase", V3(4.4, 1.6, 2.2), CF(xm + side * 0.4, 1.0, w), C.woodDark, M.WoodPlanks, true)
    for _, dz in ipairs({-1.45, 1.45}) do
        cyl(P(m, "CartWheel", V3(0.3, 2.4, 2.4), CF(xm + side * 0.4, 1.4, w + dz, 90), C.woodDark, M.Wood))
    end
    P(m, "Load", V3(3.6, 1.4, 2.2), CF(xm + side * 0.3, 2.9, w, 8), RGB(92,140,64), M.Fabric)
    P(m, "Sack", V3(1.6, 1.3, 1.4), CF(xm + side * 1.8, 3.8, w, -14, 0, 9), RGB(156,128,86), M.Fabric)
    -- Crates at the kerb end and a tin sheet leaning on them.
    P(m, "Crate", V3(1.8, 1.8, 1.8), CF(x0 + side * 1.0, 1.7, w - 0.5, 12), C.woodLight, M.WoodPlanks, true)
    P(m, "Crate", V3(1.6, 1.6, 1.6), CF(x0 + side * 1.0, 3.4, w - 0.4, -8), C.wood, M.WoodPlanks, true)
    P(m, "TinSheet", V3(0.15, 4.2, 3.2), CF(x0 + side * 0.25, 2.6, w + 0.5, 0, 0, side * 12), C.rust2, M.CorrodedMetal)
    P(m, "StripedBar", V3(math.abs(x1 - x0) - 0.4, 0.5, 0.25), CF(xm, 4.8, w - 1.4), RGB(214,60,48), M.SmoothPlastic)
    local blockerX0, blockerX1 = math.min(x0, x1), math.max(x0, x1)
    boundsWall(bounds, "SidewalkBlocker", blockerX0, blockerX1, w - 1.5, w + 1.5, W.BoundsHeight)
    return m
end

-- ------------------------------------------------------------ road + tunnels
local function buildRoad(folder, cx, W, z, detail)
    local L = W.TrafficHalfLength * 2 + 20
    local roadColor = ({RGB(58,54,50), RGB(54,52,50), RGB(48,48,48), RGB(40,40,42), RGB(34,34,38)})[z]
    local walk = ({RGB(124,114,100), RGB(132,124,112), RGB(150,148,142), RGB(176,176,172), RGB(206,204,198)})[z]
    P(folder, "Road", V3(W.RoadHalfWidth * 2, 0.4, L), CFrame.new(cx, 0, 0), roadColor, M.Asphalt, true)
    local walkLen = W.PenHalfLength * 2 + 20
    for _, side in ipairs({-1, 1}) do
        local w = W.SidewalkOuter - W.RoadHalfWidth
        P(folder, "Sidewalk", V3(w, 0.8, walkLen), CFrame.new(cx + side * (W.RoadHalfWidth + w / 2), 0.4, 0), walk, z <= 2 and M.Concrete or M.Pavement, true)
        P(folder, "Kerb", V3(0.5, 0.84, walkLen), CFrame.new(cx + side * (W.RoadHalfWidth + 0.25), 0.42, 0), z <= 2 and RGB(170,150,76) or RGB(210,210,204), M.Concrete)
    end
    -- Railway between the two carriageways: ballast bed, sleepers, two rails, warning kerbs.
    -- Cars never reach it, but a commuter train blasts through every 35-70 s (TrainClient).
    local mh = W.MedianHalfWidth
    local railLen = W.TrafficHalfLength * 2 + 20
    P(folder, "Ballast", V3(mh * 2, 0.5, railLen), CFrame.new(cx, 0.25, 0), RGB(112,102,92), M.Pebble, true)
    for _, s in ipairs({-1, 1}) do
        P(folder, "RailKerb", V3(0.4, 0.62, railLen), CFrame.new(cx + s * (mh - 0.2), 0.31, 0), z <= 2 and RGB(214,184,60) or RGB(230,230,226), M.Concrete)
        P(folder, "Rail", V3(0.3, 0.3, railLen), CFrame.new(cx + s * 2.4, 0.78, 0), RGB(150,150,156), M.Metal)
    end
    local sleeperStep = detail and 3.5 or 7
    for zz = -W.PenHalfLength - 8, W.PenHalfLength + 8, sleeperStep do
        P(folder, "Sleeper", V3(7.2, 0.22, 0.9), CFrame.new(cx, 0.6, zz), RGB(120,114,104), M.Concrete)
    end
    -- Level-crossing style signals: the lamps flash red before and while a train passes.
    for i, sp in ipairs({{-1, -30}, {1, 30}, {-1, 72}, {1, -72}}) do
        local x = cx + sp[1] * (mh - 0.8)
        vcyl(folder, "SignalPost", 6.5, 0.3, x, 3.25, sp[2], RGB(40,40,42), M.Metal)
        local lamp = ball(P(folder, "RailSignalLamp", V3(0.9, 0.9, 0.9), CFrame.new(x, 6.4, sp[2]), RGB(90,20,18), M.SmoothPlastic))
        lamp.CastShadow = false
        signBoard(folder, "TrainWarning", V3(3.2, 1.2, 0.12), V3(x, 5.0, sp[2] + 0.2), V3(-sp[1], 0, 0), "⚠ TRAINS", RGB(236,196,40), RGB(20,20,20))
    end
    local step = detail and 13 or 26
    for _, dx in ipairs({-(mh + W.LaneWidth), mh + W.LaneWidth}) do
        for zz = -W.PenHalfLength - 30, W.PenHalfLength + 30, step do
            P(folder, "LaneDash", V3(0.35, 0.05, 5), CFrame.new(cx + dx, 0.22, zz), RGB(206,200,184), M.SmoothPlastic)
        end
    end
end

-- Tunnel building bridging each road end. Traffic spawns/despawns in its dark interior.
local function buildTunnel(folder, cx, W, zSign, z, rng)
    local m = Instance.new("Model") m.Name = "RoadTunnel" m.Parent = folder
    local z0 = zSign * W.PenHalfLength
    local depth = W.TrafficHalfLength - W.PenHalfLength + 14
    local zc = z0 + zSign * depth / 2
    local color = ({RGB(150,132,112), RGB(160,146,128), RGB(170,166,160), RGB(186,188,192), RGB(214,210,200)})[z]
    local rh = W.RoadHalfWidth
    local side = W.SidewalkOuter + 12
    -- Solid blocks on both sides close the sidewalks.
    for _, s in ipairs({-1, 1}) do
        P(m, "Block", V3(side - rh, 20, depth), CFrame.new(cx + s * (rh + (side - rh) / 2), 10, zc), color, M.Brick, true)
        -- Black/yellow hazard board on the corner facing the pen.
        P(m, "Hazard", V3(3.0, 5, 0.2), CFrame.new(cx + s * (rh + 1.6), 3.2, z0 - zSign * 0.12), RGB(236,196,40), M.SmoothPlastic)
        for k = -1, 1 do
            P(m, "HazardStripe", V3(0.7, 5.6, 0.22), CFrame.new(cx + s * (rh + 1.6) + k * 1.0, 3.2, z0 - zSign * 0.14) * CFrame.Angles(0, 0, rad(35)), C.black, M.SmoothPlastic)
        end
    end
    P(m, "Span", V3(rh * 2, 8, depth), CFrame.new(cx, 16, zc), color, M.Brick, true)
    P(m, "Ceiling", V3(rh * 2, 0.4, depth), CFrame.new(cx, 11.8, zc), RGB(20,18,16), M.SmoothPlastic)
    for _, s in ipairs({-1, 1}) do
        P(m, "InnerWall", V3(0.3, 12, depth), CFrame.new(cx + s * (rh - 0.1), 6, zc), RGB(24,22,20), M.SmoothPlastic, true)
        -- Red "no pedestrians" board on each tunnel corner: the reason you cannot walk in there.
        signBoard(m, "NoPedestrians", V3(3.4, 2.4, 0.2), V3(cx + s * (rh + 1.9), 7.4, z0 - zSign * 0.2), V3(0, 0, -zSign), "⛔ NO\nPEDESTRIANS", RGB(190,30,30), RGB(255,255,255))
    end
    P(m, "BackCap", V3(rh * 2, 12, 0.5), CFrame.new(cx, 6, z0 + zSign * depth), C.black, M.SmoothPlastic, true)
    local signPos = V3(cx, 15.5, z0 - zSign * 0.3)
    signBoard(m, "TunnelSign", V3(18, 3, 0.3), signPos, V3(0, 0, -zSign), zSign > 0 and "RING ROAD  ↑" or "BYPASS ROAD  ↓", RGB(26,90,56), RGB(240,240,230))
    for k = 1, 3 do
        P(m, "Window", V3(2.2, 2.4, 0.2), CFrame.new(cx - rh - 6 + k * 8.5, 16.5 + (k % 2) * 0.6, z0 - zSign * 0.08), C.dark)
    end
    vcyl(m, "Tank", 3, 3.4, cx + rh + 6, 21.5, zc, RGB(30,30,32), M.SmoothPlastic)
end

-- Distant hazy blocks to give the skyline depth (big and few).
local function buildBackdrop(folder, cx, z, rng)
    local base = ({RGB(150,136,120), RGB(160,150,136), RGB(176,172,166), RGB(190,192,196), RGB(216,212,204)})[z]
    local specs = {
        {60, 26, -58, 22, 40}, {72, 34, 12, 18, 28}, {62, 22, 72, 24, 40}, {100, 44, -22, 16, 18},
        {-72, 22, -52, 20, 44}, {-80, 30, 40, 20, 30}, {-66, 18, 92, 14, 20}, {-104, 38, -4, 16, 18},
    }
    for _, s in ipairs(specs) do
        local x, h, zz, w, d = s[1], s[2], s[3], s[4], s[5]
        local col = base:Lerp(RGB(120,110,100), rng:NextNumber() * 0.4)
        local b = P(folder, "Backdrop", V3(w, h, d), CFrame.new(cx + x, h / 2, zz), col, M.Concrete)
        b.CastShadow = false
    end
end

-- ------------------------------------------------------------ starter home (district 1)
local function buildStarterHome(folder, cx, W)
    local m = Instance.new("Model") m.Name = "StarterHome" m.Parent = folder
    local ox = cx + (W.HomeBackX + W.AlleyBackX) / 2 -- room centre X (-44)
    local F = 1.0 -- floor top
    local function S(sx, y, sz, ry, rx, rz) return CF(ox + sx, y, sz, ry, rx, rz) end
    local function Sv(sx, y, sz) return V3(ox + sx, y, sz) end

    -- FLOOR --------------------------------------------------------------
    P(m, "EarthFloor", V3(14.4, 1.0, 18.4), S(0, 0.5, 0), RGB(86,64,44), M.Ground, true)
    P(m, "WornPath", V3(9, 0.05, 5.5), S(2.5, F + 0.02, 0.2), RGB(70,52,36), M.Mud)
    P(m, "ReedMat", V3(7.4, 0.06, 5.0), S(-1.0, F + 0.03, -6.1, 3), RGB(150,122,78), M.Fabric)

    -- WALLS: overlapping corrugated sheets, a tarp and reclaimed boards -----
    P(m, "BackSheetA", V3(0.22, 7.9, 6.4), S(-7.15, F + 3.9, -5.95, 0, 1.2, 0), C.rust1, M.CorrodedMetal, true)
    P(m, "BackSheetB", V3(0.22, 8.2, 6.2), S(-7.32, F + 4.05, 0.55, 0, -0.8, 0), RGB(88,96,98), M.CorrodedMetal, true)
    P(m, "BackSheetC", V3(0.22, 7.7, 6.4), S(-7.15, F + 3.8, 6.1, 0, 0.6, 0), C.rust4, M.CorrodedMetal, true)
    P(m, "LeftSheetA", V3(5.3, 8.0, 0.22), S(-4.6, F + 4.0, -9.15), RGB(112,66,42), M.CorrodedMetal, true)
    P(m, "LeftTarp", V3(5.0, 7.4, 0.14), S(0.3, F + 3.9, -9.3), C.tarpBlue, M.Fabric, true)
    P(m, "LeftSheetC", V3(4.8, 8.8, 0.22), S(4.8, F + 4.4, -9.15, 0, 0, 1.5), RGB(96,98,92), M.CorrodedMetal, true)
    P(m, "RightSheetA", V3(5.4, 8.0, 0.22), S(-4.5, F + 4.0, 9.15), RGB(92,98,96), M.CorrodedMetal, true)
    P(m, "RightBoards", V3(5.0, 7.8, 0.3), S(0.4, F + 3.9, 9.2), RGB(104,78,52), M.WoodPlanks, true)
    P(m, "RightSheetC", V3(4.8, 8.9, 0.22), S(4.8, F + 4.45, 9.15), RGB(132,80,46), M.CorrodedMetal, true)
    -- Crooked sheet on the front-left corner frames the open front.
    P(m, "FrontReturn", V3(0.22, 8.4, 2.8), S(7.05, F + 4.2, -7.8, 0, 0, -2), RGB(96,72,50), M.CorrodedMetal, true)

    -- TIMBER FRAME -------------------------------------------------------
    for _, sz in ipairs({-8.85, 8.85}) do
        P(m, "BackPost", V3(0.6, 8.2, 0.6), S(-6.9, F + 4.1, sz), C.woodDark, M.Wood)
        P(m, "FrontPost", V3(0.65, 9.5, 0.65), S(6.9, F + 4.75, sz), C.woodDark, M.Wood)
        P(m, "SideGirt", V3(14, 0.35, 0.35), S(0, F + 3.6, sz * 0.985), C.wood, M.Wood)
    end
    P(m, "BackGirt", V3(0.35, 0.35, 17.6), S(-6.85, F + 3.6, 0), C.wood, M.Wood)
    P(m, "BackPlate", V3(0.5, 0.5, 18.4), S(-6.9, 9.1, 0), C.woodDark, M.Wood)
    P(m, "FrontLintel", V3(0.7, 0.7, 18.8), S(6.95, 10.35, 0, 0, 0.8, 0), C.woodDark, M.Wood)
    local slope = math.deg(math.atan(1.25 / 14))
    for _, sz in ipairs({-6.2, 0.2, 6.4}) do
        P(m, "Rafter", V3(16, 0.45, 0.45), S(0.2, 9.75, sz, 0, 0, slope), C.wood, M.Wood)
    end

    -- ROOF: three uneven sheets with a thin light gap, weighed down by junk --
    local roofCols = {RGB(118,72,46), RGB(92,90,84), RGB(132,86,54)}
    local roofZ = {{-6.2, 6.9}, {0.75, 6.6}, {6.45, 6.7}}
    for i, r in ipairs(roofZ) do
        P(m, "RoofSheet" .. i, V3(17.4, 0.22, r[2]), S(1.1, 10.17 + (i - 2) * 0.08, r[1], (i - 2) * 1.2, (i - 2) * 1.4, slope), roofCols[i], M.CorrodedMetal, true)
    end
    cyl(P(m, "RoofTyre", V3(0.7, 2.4, 2.4), S(-2, 10.65, -5, 0, 0, 90), C.black, M.Rubber))
    P(m, "RoofBrick", V3(1.2, 0.6, 0.6), S(3, 10.75, 5.5, 20), C.brick, M.Brick)

    -- FRONT: curtain drawn aside, threshold plank --------------------------
    P(m, "Curtain", V3(0.35, 8.4, 1.5), S(6.95, F + 4.8, 8.0), RGB(130,46,40), M.Fabric)
    P(m, "CurtainTie", V3(0.45, 0.3, 1.6), S(6.95, F + 3.6, 8.0), RGB(200,160,60), M.Fabric)
    P(m, "Threshold", V3(0.9, 0.2, 12.5), S(7.0, F + 0.05, -0.2), C.wood, M.WoodPlanks)

    -- BED (mid-left, where the spawn camera sees it): pallet + mattress with rolled edges, pillow, blanket, stains
    P(m, "Pallet", V3(7.0, 0.45, 4.6), S(-1.2, F + 0.225, -6.2), RGB(112,86,58), M.WoodPlanks, true)
    P(m, "Mattress", V3(6.6, 0.55, 3.6), S(-1.2, F + 0.72, -6.2, 0, 0, 0.8), RGB(152,130,98), M.Fabric, true)
    for _, dz in ipairs({-1.85, 1.85}) do
        cyl(P(m, "MattressEdge", V3(6.6, 0.62, 0.62), S(-1.2, F + 0.74, -6.2 + dz), RGB(138,116,86), M.Fabric))
    end
    P(m, "StainA", V3(1.9, 0.04, 1.3), S(-0.3, F + 1.01, -5.7, 22), RGB(104,80,50), M.SmoothPlastic)
    P(m, "StainB", V3(1.0, 0.04, 0.8), S(-2.5, F + 1.01, -6.9, -15), RGB(112,86,56), M.SmoothPlastic)
    P(m, "Pillow", V3(1.3, 0.45, 2.9), S(-3.8, F + 1.2, -6.1, 6, 0, 4), RGB(182,170,146), M.Fabric)
    P(m, "Blanket", V3(3.6, 0.2, 4.1), S(0.5, F + 1.12, -6.1, -7, 0, -2), RGB(126,58,52), M.Fabric)
    P(m, "BlanketDrape", V3(2.8, 1.0, 0.18), S(0.7, F + 0.62, -4.0, -5, -18, 0), RGB(118,54,48), M.Fabric)
    P(m, "SandalL", V3(0.5, 0.12, 1.0), S(2.9, F + 0.06, -4.2, 12), RGB(40,30,24), M.Rubber)
    P(m, "SandalR", V3(0.5, 0.12, 1.0), S(3.5, F + 0.06, -3.95, -8), RGB(40,30,24), M.Rubber)

    -- STORAGE: crate, sack, shelf with jars, calendar ----------------------
    P(m, "Crate", V3(2.6, 2.3, 2.8), S(-5.5, F + 1.15, 6.6, 8), RGB(116,84,52), M.WoodPlanks, true)
    P(m, "CrateSlat", V3(2.7, 0.35, 2.9), S(-5.5, F + 1.7, 6.6, 8), RGB(84,60,38), M.WoodPlanks)
    P(m, "Sack", V3(1.6, 2.0, 1.3), S(-3.1, F + 1.0, 7.9, 10, 0, -6), RGB(156,128,86), M.Fabric)
    P(m, "Shelf", V3(1.3, 0.22, 5.2), S(-6.4, 5.5, 4.6), RGB(98,72,46), M.Wood)
    for _, sz in ipairs({2.6, 6.6}) do
        P(m, "Bracket", V3(1.0, 0.7, 0.25), S(-6.5, 5.05, sz), C.woodDark, M.Wood)
    end
    cyl(P(m, "JarAmber", V3(0.9, 0.7, 0.7), S(-6.4, 6.07, 2.9, 0, 0, 90), RGB(150,98,40), M.Glass))
    cyl(P(m, "JarGreen", V3(1.1, 0.55, 0.55), S(-6.4, 6.16, 3.8, 0, 0, 90), RGB(50,92,58), M.Glass))
    cyl(P(m, "Tin", V3(0.8, 0.8, 0.8), S(-6.3, 6.0, 5.2, 0, 0, 90), RGB(160,150,130), M.Metal))
    P(m, "FoldedClothes", V3(1.1, 0.6, 1.6), S(-6.35, 5.92, 6.4), RGB(70,100,140), M.Fabric)
    P(m, "Calendar", V3(0.08, 1.9, 1.4), S(-6.98, 5.2, -1.2), RGB(226,212,184), M.SmoothPlastic)
    P(m, "CalendarTop", V3(0.1, 0.45, 1.4), S(-6.96, 6.0, -1.2), RGB(176,52,40), M.SmoothPlastic)

    -- COOKING: brick chulha with embers, pot, pan, bottles and tins --------
    P(m, "Chulha", V3(2.8, 1.1, 2.4), S(3.6, F + 0.55, 7.6), C.brick, M.Brick, true)
    P(m, "FireMouth", V3(1.0, 0.55, 0.1), S(3.6, F + 0.45, 6.38), RGB(24,18,14), M.SmoothPlastic)
    local embers = P(m, "Embers", V3(0.8, 0.12, 0.3), S(3.6, F + 0.28, 6.45), RGB(255,120,40), M.Neon)
    local glow = Instance.new("PointLight") glow.Color = RGB(255,140,60) glow.Range = 7 glow.Brightness = 1.2 glow.Shadows = false glow.Parent = embers
    cyl(P(m, "Pot", V3(1.1, 1.6, 1.6), S(3.6, F + 1.65, 7.6, 0, 0, 90), RGB(40,38,36), M.Metal))
    cyl(P(m, "Pan", V3(0.18, 1.5, 1.5), S(5.8, F + 0.9, 8.85, 90), RGB(50,48,46), M.Metal))
    P(m, "Soot", V3(2.6, 2.6, 0.06), S(3.6, F + 3.3, 9.0), RGB(44,38,32), M.SmoothPlastic)
    cyl(P(m, "Firewood", V3(1.8, 0.35, 0.35), S(1.6, F + 0.2, 8.3, 10), RGB(92,64,40), M.Wood))
    cyl(P(m, "Firewood", V3(1.8, 0.35, 0.35), S(1.7, F + 0.52, 7.95, -6), RGB(100,70,44), M.Wood))
    P(m, "OilCan", V3(0.8, 1.2, 0.6), S(5.6, F + 0.6, 7.3), RGB(196,160,52), M.Metal)
    cyl(P(m, "WaterBottle", V3(1.1, 0.45, 0.45), S(5.9, F + 0.55, 6.4, 0, 0, 90), RGB(120,170,190), M.SmoothPlastic))
    cyl(P(m, "TinCan", V3(0.6, 0.55, 0.55), S(1.9, F + 0.3, 7.1, 0, 0, 90), RGB(170,160,140), M.Metal))

    -- WASHING: bucket, steel basin, sack, jerrycan (front-left) ------------
    cyl(P(m, "Bucket", V3(2.0, 1.9, 1.9), S(4.7, F + 1.0, -6.9, 0, 0, 90), RGB(46,88,140), M.Plastic, true))
    cyl(P(m, "Basin", V3(0.5, 2.8, 2.8), S(-5.6, F + 0.25, -7.4, 0, 0, 90), RGB(150,146,140), M.Metal))
    P(m, "RiceSack", V3(1.6, 1.9, 1.3), S(5.9, F + 0.95, -4.5, 20, 0, 5), RGB(148,120,80), M.Fabric)
    P(m, "Jerrycan", V3(0.8, 1.3, 1.1), S(5.6, F + 0.65, -8.3), RGB(206,170,40), M.Plastic)

    -- LIGHT: one bare bulb, wired along the rafter and out to the street pole
    local bulb = ball(P(m, "BareBulb", V3(0.5, 0.5, 0.5), S(0.4, 7.4, -2.4), RGB(255,214,150), M.Neon))
    bulb.CastShadow = false
    local light = Instance.new("PointLight") light.Color = RGB(255,190,120) light.Brightness = 1.6 light.Range = 20 light.Shadows = true light.Parent = bulb
    P(m, "Socket", V3(0.25, 0.35, 0.25), S(0.4, 7.7, -2.4), C.dark)
    P(m, "BulbCord", V3(0.06, 2.2, 0.06), S(0.4, 8.9, -2.4), C.black)
    P(m, "CeilingWire", V3(6.8, 0.06, 0.06), S(3.8, 10.05, -2.4, 0, 0, slope), C.black)
    P(m, "SwitchBox", V3(0.2, 0.6, 0.45), S(-6.98, 4.6, 1.5), RGB(200,196,184))
    P(m, "SwitchWire", V3(0.05, 4.4, 0.05), S(-6.96, 7.1, 1.5), C.black)

    -- LAUNDRY strung along the left wall above the bed, out of the walkway and the camera's view line
    P(m, "IndoorLine", V3(12.6, 0.06, 0.06), S(-0.4, 7.4, -8.3), C.black)
    P(m, "Towel", V3(1.3, 1.6, 0.08), S(-4.2, 6.55, -8.25, -4), RGB(206,200,184), M.Fabric)
    P(m, "Dupatta", V3(2.3, 2.6, 0.08), S(-1.2, 6.05, -8.2), RGB(196,124,44), M.Fabric)
    P(m, "Shirt", V3(1.7, 1.9, 0.08), S(2.2, 6.4, -8.25, 5), RGB(72,110,152), M.Fabric)

    -- FLOOR MESS: one puddle, two bits of litter ---------------------------
    local puddle = P(m, "Puddle", V3(2.4, 0.05, 1.6), S(5.0, F + 0.03, -2.7, 18), RGB(58,52,42), M.SmoothPlastic)
    puddle.Reflectance = 0.25
    P(m, "Paper", V3(0.5, 0.35, 0.45), S(1.9, F + 0.17, 3.4, 30), RGB(220,214,196), M.SmoothPlastic)
    P(m, "PlasticBag", V3(0.8, 0.3, 0.6), S(-0.6, F + 0.15, 6.2, 20), RGB(60,120,190), M.Plastic)

    -- OUTSIDE APRON --------------------------------------------------------
    P(m, "MuddyApron", V3(6, 0.06, 11), S(9.8, 0.83, 0.3), RGB(78,58,40), M.Mud)
    local ap = P(m, "ApronPuddle", V3(3.4, 0.05, 2.0), S(11.5, 0.86, 3.4, -12), RGB(56,50,40), M.SmoothPlastic)
    ap.Reflectance = 0.25
    cyl(P(m, "OldTyre", V3(0.75, 2.4, 2.4), S(10.5, 2.0, 5.3, 90, 0, 8), C.black, M.Rubber))
    cyl(P(m, "OrangeBucket", V3(1.3, 1.2, 1.2), S(12.5, 1.45, -5.0, 0, 0, 90), RGB(200,110,40), M.Plastic))
    P(m, "OutsideCrate", V3(2, 1.6, 2), S(9.2, 1.6, -5.0, 14), C.woodLight, M.WoodPlanks, true)

    return m, Sv
end

-- The alley between the starter room and the street: dirt path, laundry overhead, Raju's stall.
local function buildAlley(folder, cx, W)
    local m = Instance.new("Model") m.Name = "HomeAlley" m.Parent = folder
    local x0, x1 = cx + W.AlleyBackX, cx - W.SidewalkOuter
    local xm = (x0 + x1) / 2
    local len = x1 - x0
    P(m, "AlleyFloor", V3(len, 0.8, W.AlleyHalfWidth * 2), CFrame.new(xm, 0.4, 0), C.dirt, M.Ground, true)
    P(m, "MudStreak", V3(len - 4, 0.05, 2.2), CF(xm, 0.82, 1.8, 4), C.mudDark, M.Mud)
    P(m, "Drain", V3(len, 0.06, 0.8), CFrame.new(xm, 0.82, W.AlleyHalfWidth - 0.6), RGB(48,52,40), M.SmoothPlastic)
    -- Two laundry lines crossing the alley, high enough to walk under.
    for i, lx in ipairs({x0 + 4.5, x0 + 10}) do
        P(m, "AlleyLine", V3(0.06, 0.06, W.AlleyHalfWidth * 2 + 1), CFrame.new(lx, 8.6, 0), C.black)
        for k = 1, 3 do
            local col = C.cloth[((i * 3 + k) % #C.cloth) + 1]
            P(m, "AlleyCloth", V3(1.4 + (k % 2) * 0.6, 2.0 + (k % 3) * 0.4, 0.08), CF(lx, 7.4 - (k % 3) * 0.2, -W.AlleyHalfWidth + k * 3.0, 90), col, M.Fabric)
        end
    end
    -- Raju's delivery stall at the alley mouth (south side, out of the walking line).
    local sx, sz = x1 - 3.8, -W.AlleyHalfWidth + 1.2
    P(m, "StallCounter", V3(3.4, 2.2, 2.0), CF(sx, 1.9, sz), C.wood, M.WoodPlanks, true)
    P(m, "StallTop", V3(3.8, 0.2, 2.4), CF(sx, 3.05, sz), C.woodLight, M.Wood)
    P(m, "ParcelA", V3(1.3, 1.0, 1.1), CF(sx - 0.8, 3.65, sz, 12), RGB(170,128,80), M.SmoothPlastic)
    P(m, "ParcelB", V3(1.0, 0.8, 0.9), CF(sx + 0.7, 3.55, sz + 0.2, -9), RGB(150,112,70), M.SmoothPlastic)
    P(m, "ParcelC", V3(0.8, 0.6, 0.8), CF(sx + 0.6, 4.25, sz + 0.1, 20), RGB(186,146,96), M.SmoothPlastic)
    P(m, "StallTarp", V3(5.5, 0.15, 4.2), CF(sx + 0.6, 7.6, sz + 0.3, 0, -8, 3), RGB(40,120,120), M.Fabric, "query")
    for _, dx in ipairs({-2.4, 3.2}) do
        P(m, "TarpPole", V3(0.25, 7.4, 0.25), CF(sx + dx, 3.9, sz - 1.4), C.woodDark, M.Wood)
    end
    signBoard(m, "RajuSign", V3(4.6, 1.3, 0.15), V3(sx + 0.6, 6.4, sz - 1.55), V3(-1, 0, 0.6).Unit, "RAJU DELIVERY", RGB(230,196,52), RGB(90,20,20))
    -- Street pole at the alley mouth: the home's power line is tapped from here.
    local poleX, poleZ = x1 - 0.8, W.AlleyHalfWidth + 1.4
    vcyl(m, "Pole", 13, 0.55, poleX, 6.5, poleZ, RGB(110,104,96), M.Concrete)
    P(m, "CrossArm", V3(0.3, 0.3, 3.2), CFrame.new(poleX, 12.4, poleZ), C.woodDark, M.Wood)
    P(m, "Transformer", V3(1.2, 1.8, 1.2), CFrame.new(poleX - 0.9, 10.4, poleZ), RGB(80,86,80), M.Metal)
    wire(m, V3(cx + W.AlleyBackX + 0.1, 10.3, 0.3), V3(poleX, 12.3, poleZ - 1.2), 1.2)
    wire(m, V3(poleX, 12.3, poleZ + 1.2), V3(cx - W.SidewalkOuter - 1, 9.5, 20), 0.8)
    return m, CFrame.lookAt(V3(x1 - 2.6, 0.8, -3.9), V3(x0 + 4, 0.8, 0.5))
end

-- ------------------------------------------------------------ utility poles & wires across the road
local function buildStreetWires(folder, cx, W)
    local m = Instance.new("Model") m.Name = "StreetWires" m.Parent = folder
    local xw, xe = cx - W.SidewalkOuter - 0.8, cx + W.SidewalkOuter + 0.8
    local pairsZ = {{-44, -30}, {44, 30}, {88, 72}, {-88, -74}}
    for _, pz in ipairs(pairsZ) do
        vcyl(m, "Pole", 13, 0.5, xw, 6.5, pz[1], RGB(110,104,96), M.Concrete)
        vcyl(m, "Pole", 13, 0.5, xe, 6.5, pz[2], RGB(110,104,96), M.Concrete)
        wire(m, V3(xw, 12.4, pz[1]), V3(xe, 12.2, pz[2]), 1.6)
        wire(m, V3(xw, 11.6, pz[1]), V3(xe, 11.5, pz[2]), 2.2)
    end
    wire(m, V3(xw, 12.0, -44), V3(xw, 12.0, 44), 1.2)
    wire(m, V3(xe, 12.0, -30), V3(xe, 12.0, 30), 1.0)
end

-- ------------------------------------------------------------ generic later-district buildings
local function simpleBlock(ctx, w0, w1, opts)
    local folder, cx, W, side, rng = ctx.folder, ctx.cx, ctx.W, ctx.side, ctx.rng
    local m = Instance.new("Model") m.Name = "Building" m.Parent = folder
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    local function at(d, y, w, ry, rx, rz) return rowCF(cx, W, side, d, y, w, ry, rx, rz) end
    local h = opts.height or (10 + rng:NextNumber() * 10)
    P(m, "Block", V3(14, h, Wd - 0.4), at(7, h / 2, wc), opts.color or C.paint[rng:NextInteger(1, #C.paint)], opts.material or M.Concrete, true)
    P(m, "Shopfront", V3(0.2, 5.5, Wd - 4), at(-0.1, 2.75, wc), RGB(40,44,50), M.Glass)
    P(m, "Awning", V3(2.6, 0.15, Wd - 2.5), at(-1.2, 6.4, wc, 0, 0, 12), C.cloth[rng:NextInteger(1, #C.cloth)], M.Fabric)
    if opts.sign then
        signBoard(m, "Sign", V3(math.min(Wd - 3, 9), 1.6, 0.15), at(-0.3, 7.6, wc).Position, facingRoad(side), opts.sign, opts.signBg, opts.signFg)
    end
    return m
end

local function buildSimpleHome(folder, cx, W, z)
    local m = Instance.new("Model") m.Name = "DistrictHome" m.Parent = folder
    local ox = cx + (W.HomeBackX + W.AlleyBackX) / 2
    local wallCol = ({nil, RGB(170,150,120), RGB(186,178,164), RGB(200,200,196), RGB(226,218,196)})[z]
    P(m, "Floor", V3(14.4, 1.0, 18.4), CFrame.new(ox, 0.5, 0), RGB(150,140,126), M.Concrete, true)
    P(m, "Back", V3(0.4, 10, 18.4), CFrame.new(ox - 7.2, 5, 0), wallCol, M.Concrete, true)
    P(m, "Left", V3(14.4, 10, 0.4), CFrame.new(ox, 5, -9.2), wallCol, M.Concrete, true)
    P(m, "Right", V3(14.4, 10, 0.4), CFrame.new(ox, 5, 9.2), wallCol, M.Concrete, true)
    P(m, "Roof", V3(15.4, 0.5, 19.4), CFrame.new(ox, 10.2, 0), RGB(120,116,110), M.Concrete, true)
    P(m, "Bed", V3(6.5, 1.4, 4.0), CFrame.new(ox - 3.3, 1.7, -6.4), RGB(90,70,50), M.WoodPlanks, true)
    P(m, "Sheet", V3(6.3, 0.3, 3.8), CFrame.new(ox - 3.3, 2.55, -6.4), RGB(70,100,150), M.Fabric)
    local lamp = ball(P(m, "Lamp", V3(0.6, 0.6, 0.6), CFrame.new(ox - 0.5, 8.4, 0), RGB(255,230,180), M.Neon))
    local l = Instance.new("PointLight") l.Range = 18 l.Brightness = 1.2 l.Color = RGB(255,220,170) l.Parent = lamp
    local x0, x1 = cx + W.AlleyBackX, cx - W.SidewalkOuter
    P(m, "AlleyFloor", V3(x1 - x0, 0.8, W.AlleyHalfWidth * 2), CFrame.new((x0 + x1) / 2, 0.4, 0), RGB(140,132,120), M.Concrete, true)
    -- Alley side walls (the neighbouring buildings).
    for _, s in ipairs({-1, 1}) do
        P(m, "AlleyWall", V3(x1 - x0, 12, 0.6), CFrame.new((x0 + x1) / 2, 6, s * (W.AlleyHalfWidth + 0.3)), wallCol, M.Concrete, true)
        P(m, "HomeWall", V3(2, 12, 3.4), CFrame.new(x0 - 1, 6, s * (W.AlleyHalfWidth + 1.7)), wallCol, M.Concrete, true)
    end
    return m
end

-- ------------------------------------------------------------ gameplay bounds (one district)
local function buildBounds(bounds, cx, W)
    local H = W.BoundsHeight
    local T = 2
    local so, pl = W.SidewalkOuter, W.PenHalfLength
    local ah, ab = W.AlleyHalfWidth, W.AlleyBackX
    local hb, hh = W.HomeBackX, W.HomeHalfWidth
    local X = function(v) return cx + v end
    -- Outer edges of the road + sidewalk corridor.
    boundsWall(bounds, "WestLineNorth", X(-so - T), X(-so), ah, pl + T, H)
    boundsWall(bounds, "WestLineSouth", X(-so - T), X(-so), -pl - T, -ah, H)
    boundsWall(bounds, "EastLine", X(so), X(so + T), -pl - T, pl + T, H)
    boundsWall(bounds, "EndNorth", X(-so - T), X(so + T), pl, pl + T, H)
    boundsWall(bounds, "EndSouth", X(-so - T), X(so + T), -pl - T, -pl, H)
    -- Home alley.
    boundsWall(bounds, "AlleyNorth", X(ab - T), X(-so), ah, ah + T, H)
    boundsWall(bounds, "AlleySouth", X(ab - T), X(-so), -ah - T, -ah, H)
    -- Home room (slightly wider than the alley; the corner pieces close the step).
    boundsWall(bounds, "HomeNorth", X(hb - T), X(ab), hh, hh + T, H)
    boundsWall(bounds, "HomeSouth", X(hb - T), X(ab), -hh - T, -hh, H)
    boundsWall(bounds, "HomeCornerN", X(ab - T), X(ab), ah, hh + T, H)
    boundsWall(bounds, "HomeCornerS", X(ab - T), X(ab), -hh - T, -ah, H)
    boundsWall(bounds, "HomeBack", X(hb - T), X(hb), -hh - T, hh + T, H)
end

-- ------------------------------------------------------------ public
function WorldBuilder.build(Config, VehicleFactory)
    local W = Config.World
    local oldWorld = workspace:FindFirstChild("SIT_World")
    if oldWorld then oldWorld:Destroy() end
    local World = Instance.new("Folder")
    World.Name = "SIT_World"
    World.Parent = workspace

    local ground = P(World, "Ground", V3(1000, 2, 700), CFrame.new(0, -1, 0), RGB(104,88,66), M.Ground, true)
    ground.CastShadow = false

    local layout = {World = World, zones = {}}
    local dropZs = {-94, -58, -22, 24, 60, 94}

    for z, cx in ipairs(W.ZoneCenters) do
        local rng = Random.new(1000 + z * 97)
        local zoneFolder = Instance.new("Folder")
        zoneFolder.Name = "Zone_" .. z
        zoneFolder:SetAttribute("SITZone", z)
        zoneFolder.Parent = World
        local bounds = Instance.new("Folder")
        bounds.Name = "GameplayBounds"
        bounds.Parent = zoneFolder
        local info = {cx = cx, folder = zoneFolder, drops = {}, hazards = {}}
        layout.zones[z] = info

        buildRoad(zoneFolder, cx, W, z, z == 1)
        buildBounds(bounds, cx, W)
        buildTunnel(zoneFolder, cx, W, 1, z, rng)
        buildTunnel(zoneFolder, cx, W, -1, z, rng)
        buildBackdrop(zoneFolder, cx, z, rng)

        local nextName = W.ZoneNames[z + 1]
        local nextRank = Config.Ranks[z + 1]
        local gateSign = nextName and ("→ " .. nextName .. "\n" .. string.upper(nextRank and nextRank.Name or "") .. " ONLY") or nil
        local westCtx = {folder = zoneFolder, cx = cx, W = W, side = -1, rng = rng, bounds = bounds, VehicleFactory = VehicleFactory}
        local eastCtx = {folder = zoneFolder, cx = cx, W = W, side = 1, rng = rng, bounds = bounds, VehicleFactory = VehicleFactory}

        if z == 1 then
            buildStarterHome(zoneFolder, cx, W)
            local _, vendorCF = buildAlley(zoneFolder, cx, W)
            info.vendorCF = vendorCF
            buildStreetWires(zoneFolder, cx, W)
            -- WEST ROW (home side)
            local flankDepth = -W.AlleyBackX - W.SidewalkOuter
            tinShack(westCtx, 6, 20, {name = "NeighbourShack", style = "closed", laundry = true, drum = true, depth = flankDepth})
            tinShack(westCtx, -20, -6, {name = "TeaStall", style = "counter", depth = flankDepth, sign = "CHAOTIC CHAI", signBg = RGB(196,60,52), signFg = RGB(255,240,200), awning = RGB(196,60,52), goods = RGB(180,140,90)})
            garage(westCtx, 20, 38, {sign = "JUGAAD MOTOR WORKS"})
            tinShack(westCtx, -38, -20, {name = "BrokerOffice", style = "counter", sign = "STREET BROKER", signBg = RGB(40,110,70), signFg = RGB(240,240,220), goods = RGB(90,70,50), awning = RGB(62,98,70)})
            tinShack(westCtx, 38, 56, {name = "VegStall", style = "counter", goods = RGB(96,140,60), tank = true})
            tinShack(westCtx, -56, -38, {name = "WestShack", style = "closed", tank = true, laundry = true})
            twoStorey(westCtx, 56, 78, {name = "WestHouse"})
            tinShack(westCtx, -78, -56, {name = "ScrapStall", style = "counter", goods = RGB(110,110,104), drum = true})
            compound(westCtx, 78, W.PenHalfLength, {})
            compound(westCtx, -W.PenHalfLength, -78, {})
            -- EAST ROW (delivery side)
            compound(eastCtx, -W.PenHalfLength, -100, {tree = false})
            tinShack(eastCtx, -100, -84, {name = "DropShack", style = "closed", door = RGB(60,110,150), laundry = true})
            gate(eastCtx, -84, -66, {sign = gateSign})
            tinShack(eastCtx, -66, -50, {name = "DropShack", style = "closed", door = RGB(150,70,60), tank = true})
            tinShack(eastCtx, -50, -32, {name = "FruitStall", style = "counter", goods = RGB(220,150,40), awning = RGB(230,164,40)})
            twoStorey(eastCtx, -32, -12, {name = "DropHouse", paint = C.paint[1]})
            landmark(eastCtx, -12, 12, {sign = "LUCKY KIRANA STORE"})
            tinShack(eastCtx, 12, 34, {name = "DropShack", style = "closed", door = RGB(70,130,90), laundry = true, drum = true})
            tinShack(eastCtx, 34, 50, {name = "PhoneStall", style = "counter", sign = "MOBILE RECHARGE", signBg = RGB(40,70,160), signFg = RGB(255,255,255), goods = RGB(60,60,64)})
            twoStorey(eastCtx, 50, 70, {name = "DropHouse", paint = C.paint[4]})
            tinShack(eastCtx, 70, 86, {name = "EastShack", style = "closed", tank = true})
            tinShack(eastCtx, 86, 102, {name = "DropShack", style = "closed", door = RGB(170,120,40), laundry = true})
            compound(eastCtx, 102, W.PenHalfLength, {tree = false})
            -- Sidewalk barricades: walking along a sidewalk means stepping into a live lane.
            sidewalkBarricade(westCtx, 48)
            sidewalkBarricade(westCtx, -48)
            sidewalkBarricade(eastCtx, -41)
            sidewalkBarricade(eastCtx, 42)
            info.mechanicCF = CFrame.lookAt(V3(cx - W.SidewalkOuter - 2.6, 0.8, 29), V3(cx, 0.8, 29))
            info.brokerCF = CFrame.lookAt(V3(cx - W.SidewalkOuter - 2.6, 0.8, -29), V3(cx, 0.8, -29))
            -- Slow mud on the sidewalks (only four patches; each is one Touched part).
            for _, spec in ipairs({{-1, 64}, {-1, -66}, {1, 8}, {1, -72}}) do
                local x = cx + spec[1] * (W.RoadHalfWidth + (W.SidewalkOuter - W.RoadHalfWidth) / 2)
                local hz = P(zoneFolder, "MuckPatch", V3(4.5, 0.08, 7), CFrame.new(x, 0.83, spec[2]), RGB(82,69,34), M.Mud)
                hz.CanTouch = true
                table.insert(info.hazards, hz)
            end
        else
            buildSimpleHome(zoneFolder, cx, W, z)
            info.vendorCF = CFrame.lookAt(V3(cx - W.SidewalkOuter - 2.6, 0.8, -3.9), V3(cx + W.AlleyBackX + 4, 0.8, 0.5))
            local signs = {nil, {"SPICE BAZAAR", "OLD MARKET TAILORS", "SWEETS"}, {"FOOD HUB", "24x7 PHARMACY", "CLOUD KITCHEN"}, {"ELECTRONICS", "CO-WORKING", "BANK"}, {"LUXURY MALL", "JEWELLERS", "PRIVATE CLUB"}}
            local s = signs[z]
            simpleBlock(westCtx, 6, 32, {sign = s[1]})
            simpleBlock(westCtx, -32, -6, {sign = "GARAGE", signBg = RGB(40,80,140), signFg = RGB(255,255,255)})
            simpleBlock(westCtx, 32, 70, {})
            simpleBlock(westCtx, -70, -32, {sign = "BROKER", signBg = RGB(40,110,70), signFg = RGB(255,255,255)})
            simpleBlock(westCtx, 70, W.PenHalfLength, {})
            simpleBlock(westCtx, -W.PenHalfLength, -70, {})
            simpleBlock(eastCtx, -W.PenHalfLength, -84, {})
            if nextName then gate(eastCtx, -84, -66, {sign = gateSign}) else simpleBlock(eastCtx, -84, -66, {}) end
            simpleBlock(eastCtx, -66, -36, {sign = s[2]})
            simpleBlock(eastCtx, -36, -10, {})
            simpleBlock(eastCtx, -10, 16, {sign = s[3]})
            simpleBlock(eastCtx, 16, 44, {})
            simpleBlock(eastCtx, 44, 76, {})
            simpleBlock(eastCtx, 76, W.PenHalfLength, {})
            info.mechanicCF = CFrame.lookAt(V3(cx - W.SidewalkOuter - 2.6, 0.8, -12), V3(cx, 0.8, -12))
            info.brokerCF = CFrame.lookAt(V3(cx - W.SidewalkOuter - 2.6, 0.8, -40), V3(cx, 0.8, -40))
        end

        if nextName then
            info.guardCF = CFrame.lookAt(V3(cx + W.SidewalkOuter + 2.4, 0.8, -75), V3(cx, 0.8, -75))
        end
        -- Delivery drop points: glowing pads on the far sidewalk in front of the east-row doors.
        for i, dz in ipairs(dropZs) do
            local x = cx + W.RoadHalfWidth + (W.SidewalkOuter - W.RoadHalfWidth) / 2
            local dp = P(zoneFolder, "Drop_Z" .. z .. "_" .. i, V3(5, 0.2, 5), CFrame.new(x, 0.95, dz), RGB(45,235,115), M.Neon)
            dp.Transparency = 1
            dp.CastShadow = false
            info.drops[i] = dp
        end
        -- Spawn inside the home room, a few studs from the back wall, facing the open front (+X).
        local spawnPos = V3(cx + W.HomeBackX + W.HomeSpawnBack, 4.0, W.HomeSpawnZ)
        info.homeSpawn = CFrame.lookAt(spawnPos, spawnPos + V3(1, 0, 0))
    end
    return layout
end

return WorldBuilder
