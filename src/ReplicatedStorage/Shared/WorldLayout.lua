-- WorldLayout: world-branch constants and the deterministic central hazards of every district.
--
-- Kept separate from Config so the world branch never has to edit Config/Main/Client.
-- Every hazard is a pure function of server time (workspace:GetServerTimeNow()), so:
--   * each client animates it locally (smooth, zero replication),
--   * each client checks hits against exactly what it sees,
--   * the server re-checks the same function (TrafficServer) before applying a hit.
-- All positions are LOCAL to the district: x from the district centre, z along the road.
local WorldLayout = {}

-- ---------------------------------------------------------------- districts
WorldLayout.Themes = {
    {Key = "slums",    Name = "THE SLUMS",         Hazard = "river"},    -- improvised tin + timber
    {Key = "market",   Name = "OLD MARKET",        Hazard = "train"},    -- painted havelis, arcades
    {Key = "delivery", Name = "DELIVERY DISTRICT", Hazard = "crane"},    -- concrete mid-rises, neon
    {Key = "business", Name = "BUSINESS CORE",     Hazard = "laser"},    -- glass towers, plazas
    {Key = "royal",    Name = "ROYAL HEIGHTS",     Hazard = "fountain"}, -- sandstone + marble palaces
}

-- Hit ids sent on the existing TrafficHit remote (positive ids are traffic vehicles, -1 the train).
WorldLayout.HitIds = {river = -2, crane = -3, laser = -4, fountain = -5}
WorldLayout.HazardByHitId = {[-2] = "river", [-3] = "crane", [-4] = "laser", [-5] = "fountain"}

function WorldLayout.hazardKind(zone)
    local t = WorldLayout.Themes[zone]
    return t and t.Hazard or "train"
end

-- ---------------------------------------------------------------- Zone 1: river + planks
-- A slow brown river runs between the carriageways. Narrow planks bridge it:
--   fixed  - always safe, but only every ~48 studs
--   bob    - up 3.5 s, wobbles 1 s (warning), sinks under the water for 2 s, rises 0.5 s
--   tilt   - always up, but rocks gently from side to side
WorldLayout.River = {
    WaterY = -1.2,       -- water surface
    BedY = -7,           -- river bed
    PlankTop = 0.35,     -- plank walking surface when up
    PlankWidth = 1.9,    -- along the road (narrow!)
    Spacing = 8,
    BobPeriod = 7,
    FallY = -0.8,        -- root below this, inside the channel = fell in
}

function WorldLayout.riverPlanks(W)
    local R = WorldLayout.River
    local planks = {}
    local i = 0
    for z = -W.PenHalfLength + 6, W.PenHalfLength - 6, R.Spacing do
        i += 1
        local kind = (i % 6 == 0) and "fixed" or ((i % 3 == 0) and "tilt" or "bob")
        table.insert(planks, {index = i, z = z, kind = kind, phase = (i * 1.37) % R.BobPeriod})
    end
    return planks
end

-- Returns yOffset (0 = up, negative = sunk), tilt in degrees, and whether it can be stood on.
function WorldLayout.plankState(plank, t)
    local R = WorldLayout.River
    if plank.kind == "fixed" then return 0, 0, true end
    if plank.kind == "tilt" then return 0, math.sin(t * 1.3 + plank.phase) * 9, true end
    local c = (t + plank.phase) % R.BobPeriod
    if c < 3.5 then return 0, 0, true end
    if c < 4.5 then return -0.15 * (c - 3.5), math.sin(c * 22) * 5, true end -- warning wobble
    if c < 6.5 then return -2.6, 0, false end                               -- under water
    return -2.6 + 2.6 * ((c - 6.5) / 0.5), 0, false                         -- rising
end

-- ---------------------------------------------------------------- Zone 3: construction cranes
-- A metro-construction strip: small tower cranes every 12 studs swing a heavy load in a circle.
-- Spacing/radius chosen so the swept circles overlap: there is no permanently safe gap between cranes.
WorldLayout.Crane = {Spacing = 11, Radius = 5.0, Period = 6.5, LoadHalf = 0.95, HitRadius = 1.9, LoadBottom = 1.4, LoadTop = 3.6}

function WorldLayout.cranes(W)
    local C = WorldLayout.Crane
    local list = {}
    local i = 0
    for z = -W.PenHalfLength + 8, W.PenHalfLength - 8, C.Spacing do
        i += 1
        table.insert(list, {index = i, z = z, dir = (i % 2 == 0) and 1 or -1, phase = (i * 0.9) % (math.pi * 2)})
    end
    return list
end

function WorldLayout.craneLoad(crane, t)
    local C = WorldLayout.Crane
    local a = crane.phase + crane.dir * t * (math.pi * 2 / C.Period)
    return math.cos(a) * C.Radius, crane.z + math.sin(a) * C.Radius, a
end

-- ---------------------------------------------------------------- Zone 4: security lasers
-- Two laser fences run along the median (x = -3 and x = +3), cut into 14-stud segments.
-- Each segment cycles on (2.2 s) -> blinking warning (0.6 s) -> off (2.2 s), in a travelling wave.
-- Beams reach 7.8 studs: higher than a standing jump, so you cannot hop over a live fence.
WorldLayout.Laser = {FenceX = {-3, 3}, Segment = 14, OnTime = 2.2, WarnTime = 0.6, OffTime = 2.2, Top = 7.8, HitHalf = 0.8, BeamY = {1.2, 3.2, 5.2, 7.2}}

function WorldLayout.laserSegments(W)
    local L = WorldLayout.Laser
    local list = {}
    local i = 0
    for z0 = -W.PenHalfLength, W.PenHalfLength - L.Segment, L.Segment do
        for f, x in ipairs(L.FenceX) do
            i += 1
            table.insert(list, {index = i, x = x, z0 = z0, z1 = z0 + L.Segment, phase = (z0 / L.Segment) * 0.45 + (f - 1) * 1.9})
        end
    end
    return list
end

-- "on" | "warn" | "off"
function WorldLayout.laserState(seg, t)
    local L = WorldLayout.Laser
    local c = (t + seg.phase) % (L.OnTime + L.WarnTime + L.OffTime)
    if c < L.OnTime then return "on" end
    if c < L.OnTime + L.WarnTime then return "warn" end
    return "off"
end

-- ---------------------------------------------------------------- Zone 5: royal fountain jets
-- Rows of fountain jets across a marble promenade. Each jet: off -> bubbling warning -> erupts.
WorldLayout.Fountain = {RowSpacing = 9, Columns = {-3.6, 0, 3.6}, OffTime = 2.2, WarnTime = 0.8, EruptTime = 1.6, HitRadius = 1.6, Height = 9}

function WorldLayout.fountainJets(W)
    local F = WorldLayout.Fountain
    local list = {}
    local row = 0
    for z = -W.PenHalfLength + 6, W.PenHalfLength - 6, F.RowSpacing do
        row += 1
        for c, x in ipairs(F.Columns) do
            table.insert(list, {row = row, x = x, z = z, phase = (row * 0.35 + c * 0.9) % (F.OffTime + F.WarnTime + F.EruptTime)})
        end
    end
    return list
end

-- "off" | "warn" | "erupt"
function WorldLayout.jetState(jet, t)
    local F = WorldLayout.Fountain
    local c = (t + jet.phase) % (F.OffTime + F.WarnTime + F.EruptTime)
    if c < F.OffTime then return "off" end
    if c < F.OffTime + F.WarnTime then return "warn" end
    return "erupt"
end

-- ---------------------------------------------------------------- shared hit test
-- Is a player (root at local lx, lz, height rootY, feet at feetY, horizontal radius r) in danger?
-- Used by HazardClient (exact) and by TrafficServer (with `slack` studs of latency tolerance).
function WorldLayout.isDanger(zone, W, lx, lz, rootY, feetY, t, r, slack)
    slack = slack or 0
    local kind = WorldLayout.hazardKind(zone)
    if kind == "river" then
        return math.abs(lx) < W.MedianHalfWidth - 0.3 + slack and rootY < WorldLayout.River.FallY + slack * 0.5
    elseif kind == "crane" then
        local C = WorldLayout.Crane
        if feetY > C.LoadTop + slack then return false end
        for _, crane in ipairs(WorldLayout.cranes(W)) do
            if math.abs(lz - crane.z) < C.Radius + C.HitRadius + r + slack then
                local x, z = WorldLayout.craneLoad(crane, t)
                local dx, dz = lx - x, lz - z
                if dx * dx + dz * dz < (C.HitRadius + r + slack) ^ 2 then return true end
            end
        end
        return false
    elseif kind == "laser" then
        local L = WorldLayout.Laser
        if feetY > L.Top + slack then return false end
        for _, seg in ipairs(WorldLayout.laserSegments(W)) do
            if lz >= seg.z0 - slack and lz <= seg.z1 + slack and math.abs(lx - seg.x) < L.HitHalf + r + slack
                and WorldLayout.laserState(seg, t) == "on" then
                return true
            end
        end
        return false
    elseif kind == "fountain" then
        local F = WorldLayout.Fountain
        if feetY > F.Height + slack then return false end
        for _, jet in ipairs(WorldLayout.fountainJets(W)) do
            local dx, dz = lx - jet.x, lz - jet.z
            if dx * dx + dz * dz < (F.HitRadius + r + slack) ^ 2 and WorldLayout.jetState(jet, t) == "erupt" then return true end
        end
        return false
    end
    return false
end

return WorldLayout
