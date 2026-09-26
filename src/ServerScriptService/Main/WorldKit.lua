-- WorldKit: small building helpers shared by the world modules (ZoneStyles, HazardBuilder,
-- WorldConnectors, WorldHooks). Every decorative part is anchored with CanCollide/CanTouch/
-- CanQuery off; pass collide=true for solid structure (also queryable so cameras don't clip),
-- or collide="query" for camera-blocking but walk-through geometry (roofs, canopies).
local Kit = {}

local rad = math.rad
local V3 = Vector3.new
local RGB = Color3.fromRGB
Kit.V3, Kit.RGB, Kit.M = V3, RGB, Enum.Material

function Kit.P(parent, name, size, cf, color, material, collide)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored = true
    p.Size = size
    p.CFrame = cf
    p.Color = color
    p.Material = material or Enum.Material.SmoothPlastic
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.CanCollide = collide == true
    p.CanTouch = false
    p.CanQuery = collide == true or collide == "query"
    p.CastShadow = (size.X * size.Y * size.Z) > 3
    p.Parent = parent
    return p
end

function Kit.cyl(p) p.Shape = Enum.PartType.Cylinder return p end
function Kit.ball(p) p.Shape = Enum.PartType.Ball return p end

function Kit.wedge(parent, name, size, cf, color, material, collide)
    local w = Instance.new("WedgePart")
    w.Name = name
    w.Anchored = true
    w.Size = size
    w.CFrame = cf
    w.Color = color
    w.Material = material or Enum.Material.SmoothPlastic
    w.CanCollide = collide == true
    w.CanTouch = false
    w.CanQuery = collide == true or collide == "query"
    w.CastShadow = true
    w.Parent = parent
    return w
end

-- Yaw first, then pitch/roll (degrees).
function Kit.CF(x, y, z, ry, rx, rz)
    local cf = CFrame.new(x, y, z)
    if ry and ry ~= 0 then cf = cf * CFrame.Angles(0, rad(ry), 0) end
    if (rx and rx ~= 0) or (rz and rz ~= 0) then cf = cf * CFrame.Angles(rad(rx or 0), 0, rad(rz or 0)) end
    return cf
end

-- Vertical cylinder (axis Y) standing on y0 with the given height.
function Kit.vcyl(parent, name, height, dia, x, y0, z, color, material, collide)
    return Kit.cyl(Kit.P(parent, name, V3(height, dia, dia), CFrame.new(x, y0 + height / 2, z) * CFrame.Angles(0, 0, rad(90)), color, material, collide))
end

-- Dome: a ball whose lower half is hidden inside `base` height (reads as a dome on a drum).
function Kit.dome(parent, name, dia, x, yBase, z, color, material)
    return Kit.ball(Kit.P(parent, name, V3(dia, dia, dia), CFrame.new(x, yBase, z), color, material or Enum.Material.Marble))
end

-- Beam between two points.
function Kit.beam(parent, name, a, b, thick, color, material, collide)
    return Kit.P(parent, name, V3(thick, thick, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color, material, collide)
end

function Kit.surfaceSign(part, text, bg, fg, font)
    local sg = Instance.new("SurfaceGui")
    sg.Name = "Sign"
    sg.Face = Enum.NormalId.Front
    sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    sg.PixelsPerStud = 36
    sg.LightInfluence = 1
    sg.MaxDistance = 260
    sg.Parent = part
    local l = Instance.new("TextLabel")
    l.Size = UDim2.fromScale(1, 1)
    l.BackgroundColor3 = bg or RGB(230, 200, 60)
    l.BackgroundTransparency = bg and 0 or 1
    l.TextColor3 = fg or RGB(30, 24, 20)
    l.TextScaled = true
    l.TextWrapped = true
    if not pcall(function() l.Font = font or Enum.Font.Sarpanch end) then l.Font = Enum.Font.GothamBold end
    l.Text = text
    l.Parent = sg
    return sg
end

function Kit.signBoard(parent, name, size, pos, facing, text, bg, fg, font)
    local p = Kit.P(parent, name, size, CFrame.lookAt(pos, pos + facing), bg or RGB(230, 200, 60))
    Kit.surfaceSign(p, text, bg, fg, font)
    return p
end

-- Floating label (used for hooks so they are obvious from a distance).
function Kit.billboard(part, text, color, maxDist)
    local bb = Instance.new("BillboardGui")
    bb.Name = "Label"
    bb.Size = UDim2.fromOffset(220, 46)
    bb.StudsOffset = V3(0, part.Size.Y / 2 + 2.2, 0)
    bb.AlwaysOnTop = false
    bb.MaxDistance = maxDist or 70
    bb.LightInfluence = 0
    bb.Parent = part
    local l = Instance.new("TextLabel")
    l.Size = UDim2.fromScale(1, 1)
    l.BackgroundTransparency = 0.25
    l.BackgroundColor3 = RGB(12, 12, 16)
    l.TextColor3 = color or RGB(255, 214, 90)
    l.TextScaled = true
    l.Font = Enum.Font.GothamBlack
    l.Text = text
    l.Parent = bb
    return bb
end

-- Row placement: side = -1 (west row, fronts face +X) or 1 (east row, fronts face -X).
-- d = depth behind the front line (sidewalk edge), w = world Z. East is canonical; the west
-- row mirrors yaw/roll so every builder works on both sides.
function Kit.rowCF(cx, W, side, d, y, w, ry, rx, rz)
    local x = cx + side * (W.SidewalkOuter + d)
    if side < 0 then ry, rz = ry and -ry, rz and -rz end
    return Kit.CF(x, y, w, ry, rx, rz)
end

function Kit.facingRoad(side) return V3(-side, 0, 0) end

-- Deterministic pick from a list.
function Kit.pick(list, seed) return list[(math.floor(seed) % #list) + 1] end

return Kit
