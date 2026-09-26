-- WorldHooks: physical models for systems the systems/monetization branch will wire up.
-- Everything here is a MODEL/PLACEHOLDER ONLY: no economy, no prompts, no remotes.
--
-- Hook contract (for the systems branch):
--   * each hook model has attribute Hook = "<Kind>" and Zone = <district>
--   * each has an Attachment named "PromptAnchor" where a ProximityPrompt should be parented
--   Kinds: CrateKiosk (CrateKiosk_Z1..Z5), SpecialContract (SpecialContractBoard_Z1..Z5),
--          BlackMarketContract (BlackMarketContract_Z2: reserved for a SKILL-BASED high-risk
--          delivery, never a currency/item wager), Cameo (decorative parody NPCs), RoyalGarage.
--   * ReplicatedStorage.SIT_CollectibleTemplates holds one Model per rare crate collectible
--     (attributes CollectibleId, DisplayName, Rarity), ready to :Clone().
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent:WaitForChild("WorldKit"))
local P, CF, V3, RGB, M = Kit.P, Kit.CF, Kit.V3, Kit.RGB, Kit.M
local cyl, ball = Kit.cyl, Kit.ball

local WorldHooks = {}

local GOLD = RGB(222, 182, 72)
local RARITY = {Rare = RGB(60, 150, 255), Epic = RGB(170, 80, 255), Legendary = RGB(255, 190, 40), Mythic = RGB(255, 70, 110)}

local function at(ctx, d, y, w, ry) return Kit.rowCF(ctx.cx, ctx.W, ctx.side, d, y, w, ry) end

local function anchor(part, localOffset)
    local a = Instance.new("Attachment")
    a.Name = "PromptAnchor"
    a.Position = localOffset or Vector3.zero
    a.Parent = part
    return a
end

local function tag(model, kind, zone)
    model:SetAttribute("Hook", kind)
    model:SetAttribute("Zone", zone)
end

local collectibleInfo = {}

local function showcase(model, VehicleFactory, id, cf, scale)
    local info = collectibleInfo[id]
    local v = VehicleFactory.build(id, 7, {rider = false})
    v.Name = "Showcase_" .. id
    v:SetAttribute("CollectibleId", id)
    v:PivotTo(cf)
    v.Parent = model
    return v
end

-- Pedestal with a rarity-coloured glowing ring.
local function pedestal(model, cf, dia, rarity)
    cyl(P(model, "Pedestal", V3(0.8, dia, dia), cf * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)), RGB(40, 40, 46), M.Metal))
    local ring = cyl(P(model, "RarityRing", V3(0.15, dia + 0.3, dia + 0.3), cf * CFrame.new(0, 0.82, 0) * CFrame.Angles(0, 0, math.rad(90)), RARITY[rarity] or GOLD, M.Neon))
    ring.CastShadow = false
end

-- ---------------------------------------------------------------- crate kiosk
local KIOSK_STYLE = {
    {Body = RGB(230, 120, 40), Mat = M.CorrodedMetal, Show = {"skybike_mk2", "courier_jetboard"}},
    {Body = RGB(70, 146, 140), Mat = M.Plaster, Show = {"gold_tuktuk", "delivery_drone"}},
    {Body = RGB(60, 62, 70), Mat = M.Metal, Show = {"armored_suv"}},
    {Body = RGB(70, 104, 136), Mat = M.Glass, Show = {"hypercar_x"}},
    {Body = RGB(236, 206, 170), Mat = M.Sandstone, Show = {"flying_throne"}},
}

function WorldHooks.crateKiosk(ctx, w0, w1, VehicleFactory)
    local z = ctx.zone
    local st = KIOSK_STYLE[z]
    local m = Instance.new("Model") m.Name = "CrateKiosk_Z" .. z m.Parent = ctx.folder
    tag(m, "CrateKiosk", z)
    local Wd, wc, D = w1 - w0, (w0 + w1) / 2, 13
    P(m, "Floor", V3(D, 0.8, Wd), at(ctx, D / 2, 0.4, wc), RGB(60, 60, 66), M.Concrete, true)
    P(m, "Back", V3(0.5, 10, Wd), at(ctx, D, 5, wc), st.Body, st.Mat, true)
    P(m, "SideA", V3(D, 10, 0.5), at(ctx, D / 2, 5, w0 + 0.25), st.Body, st.Mat, true)
    P(m, "SideB", V3(D, 10, 0.5), at(ctx, D / 2, 5, w1 - 0.25), st.Body, st.Mat, true)
    P(m, "Roof", V3(D + 2, 0.5, Wd + 0.6), at(ctx, D / 2 - 1, 10.2, wc), st.Body:Lerp(RGB(20, 20, 20), 0.3), st.Mat, "query")
    local counter = P(m, "Counter", V3(1.4, 2.8, Wd - 1), at(ctx, 0.9, 2.2, wc), RGB(34, 34, 40), M.Metal, true)
    local strip = P(m, "CounterGlow", V3(0.1, 0.25, Wd - 1.2), at(ctx, 0.15, 3.4, wc), RGB(255, 200, 60), M.Neon)
    strip.CastShadow = false
    anchor(counter, V3(-ctx.side * 0.8, 0.6, 0))
    local signPart = Kit.signBoard(m, "KioskSign", V3(math.min(Wd - 2, 12), 2.2, 0.25), at(ctx, -0.2, 11.8, wc).Position, Kit.facingRoad(ctx.side), "🎁 MYSTERY CRATES", RGB(20, 20, 26), RGB(255, 206, 70))
    Kit.billboard(signPart, "🎁 CRATE KIOSK", RGB(255, 206, 70), 90)
    -- Stacks of crates with glowing rarity lids.
    local rarities = {"Rare", "Epic", "Legendary", "Mythic", "Rare", "Epic"}
    for i, r in ipairs(rarities) do
        local w = w0 + 1.8 + ((i - 1) % 3) * 1.9
        local y = 1.8 + math.floor((i - 1) / 3) * 1.8
        P(m, "Crate", V3(1.7, 1.7, 1.7), at(ctx, 11, y, w, i * 7), RGB(110, 76, 46), M.WoodPlanks)
        P(m, "CrateLid", V3(1.72, 0.2, 1.72), at(ctx, 11, y + 0.9, w, i * 7), RARITY[r], M.Neon).CastShadow = false
    end
    -- Rare vehicles on display, side-on to the street.
    local slots = #st.Show
    for i, id in ipairs(st.Show) do
        local w = w0 + Wd * (i / (slots + 1)) + 2
        local base = at(ctx, 6.5, 0.8, w)
        local info = collectibleInfo[id]
        pedestal(m, base, 7, info and info.Rarity)
        showcase(m, VehicleFactory, id, CFrame.new(base.Position + V3(0, 0.9, 0)))
    end
    return m
end

-- ---------------------------------------------------------------- special contract board
function WorldHooks.contractBoard(folder, cx, W, zone)
    local m = Instance.new("Model") m.Name = "SpecialContractBoard_Z" .. zone m.Parent = folder
    tag(m, "SpecialContract", zone)
    local x = cx - W.SidewalkOuter - 5
    local zf = W.AlleyHalfWidth - 0.35
    local face = V3(0, 0, -1)
    local board = P(m, "Board", V3(4.8, 3.4, 0.25), CFrame.lookAt(V3(x, 4.6, zf), V3(x, 4.6, zf) + face), RGB(120, 84, 50), M.WoodPlanks)
    anchor(board, V3(0, -1.5, -1.2))
    local header = Kit.signBoard(m, "Header", V3(4.8, 0.9, 0.2), V3(x, 6.9, zf - 0.1), face, "★ SPECIAL CONTRACTS ★", RGB(150, 30, 30), RGB(255, 226, 120))
    Kit.billboard(header, "★ SPECIAL CONTRACT", RGB(255, 120, 90), 60)
    local notes = {RGB(245, 240, 220), RGB(250, 220, 120), RGB(220, 240, 250), RGB(245, 240, 220), RGB(255, 190, 190)}
    for i, c in ipairs(notes) do
        local nx = x - 1.8 + ((i - 1) % 3) * 1.6
        local ny = 5.4 - math.floor((i - 1) / 3) * 1.4
        P(m, "Note", V3(1.1, 1.1, 0.05), CFrame.lookAt(V3(nx, ny, zf - 0.16), V3(nx, ny, zf - 0.16) + face) * CFrame.Angles(0, 0, math.rad((i * 13) % 11 - 5)), c)
    end
    for _, dx in ipairs({-2.2, 2.2}) do P(m, "Post", V3(0.3, 6, 0.3), CFrame.new(x + dx, 3, zf + 0.05), RGB(80, 60, 40), M.Wood) end
    local star = ball(P(m, "Star", V3(0.6, 0.6, 0.6), CFrame.new(x + 2.2, 7.6, zf - 0.2), RGB(255, 220, 90), M.Neon))
    local l = Instance.new("PointLight") l.Range = 8 l.Brightness = 1 l.Color = RGB(255, 210, 120) l.Parent = star
    return m
end

-- ---------------------------------------------------------------- black market (zone 2)
function WorldHooks.blackMarket(ctx, w0, w1)
    local m = Instance.new("Model") m.Name = "BlackMarketContract_Z" .. ctx.zone m.Parent = ctx.folder
    tag(m, "BlackMarketContract", ctx.zone)
    m:SetAttribute("Note", "Reserved for a skill-based high-risk delivery. Never a currency or item wager.")
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    P(m, "BackWall", V3(0.6, 12, Wd), at(ctx, 13, 6, wc), RGB(56, 50, 46), M.Brick, true)
    P(m, "SideA", V3(13, 12, 0.6), at(ctx, 6.5, 6, w0 + 0.3), RGB(56, 50, 46), M.Brick, true)
    P(m, "SideB", V3(13, 12, 0.6), at(ctx, 6.5, 6, w1 - 0.3), RGB(56, 50, 46), M.Brick, true)
    P(m, "Tarp", V3(10, 0.2, Wd - 4), at(ctx, 5, 7.5, wc, 0), RGB(30, 30, 34), M.Fabric, "query")
    local table_ = P(m, "Table", V3(2, 2.6, 8), at(ctx, 1.4, 1.3, wc), RGB(70, 50, 34), M.WoodPlanks, true)
    -- Rusty sheet fence closes the rest of the front (the table is the only "window").
    for _, span in ipairs({{w0 + 0.6, wc - 4}, {wc + 4, w1 - 0.6}}) do
        local len = span[2] - span[1]
        if len > 0.5 then P(m, "ScrapFence", V3(0.3, 4.2, len), at(ctx, 0.4, 2.1, (span[1] + span[2]) / 2), RGB(90, 70, 56), M.CorrodedMetal, true) end
    end
    anchor(table_, V3(-ctx.side * 1.2, 0.6, 0))
    for i = 1, 4 do P(m, "Crate", V3(2, 2, 2), at(ctx, 8 + (i % 2) * 2.2, 1 + math.floor((i - 1) / 2) * 2, wc - 3 + i * 1.2, i * 11), RGB(60, 44, 30), M.WoodPlanks) end
    local lamp = ball(P(m, "Lantern", V3(0.6, 0.6, 0.6), at(ctx, 3, 6.6, wc), RGB(255, 150, 60), M.Neon))
    local l = Instance.new("PointLight") l.Range = 10 l.Brightness = 0.8 l.Color = RGB(255, 140, 60) l.Parent = lamp
    local s = Kit.signBoard(m, "Sign", V3(8, 1.4, 0.2), at(ctx, -0.2, 8.6, wc).Position, Kit.facingRoad(ctx.side), "BLACK MARKET CONTRACTS • SKILL ONLY", RGB(16, 16, 18), RGB(120, 255, 140))
    Kit.billboard(s, "☠ BLACK MARKET CONTRACT", RGB(120, 255, 140), 60)
    return m
end

-- ---------------------------------------------------------------- royal garage (zone 5)
function WorldHooks.royalGarage(ctx, w0, w1, VehicleFactory)
    local m = Instance.new("Model") m.Name = "RoyalGarage_Z" .. ctx.zone m.Parent = ctx.folder
    tag(m, "RoyalGarage", ctx.zone)
    local Wd, wc = w1 - w0, (w0 + w1) / 2
    local stone = RGB(236, 206, 170)
    P(m, "Floor", V3(14, 1, Wd), at(ctx, 7, 0.5, wc), RGB(240, 236, 228), M.Marble, true)
    P(m, "Back", V3(0.6, 14, Wd), at(ctx, 14, 7, wc), stone, M.Sandstone, true)
    P(m, "SideA", V3(14, 14, 0.8), at(ctx, 7, 7, w0 + 0.4), stone, M.Sandstone, true)
    P(m, "SideB", V3(14, 14, 0.8), at(ctx, 7, 7, w1 - 0.4), stone, M.Sandstone, true)
    P(m, "Roof", V3(15, 0.8, Wd + 1), at(ctx, 7, 14.4, wc), stone, M.Sandstone, "query")
    for i = 0, 5 do Kit.vcyl(m, "Column", 13, 1, 0, 0, 0, RGB(245, 240, 230), M.Marble).CFrame = at(ctx, 0.8, 7, w0 + 2 + i * (Wd - 4) / 5) * CFrame.Angles(0, 0, math.rad(90)) end
    local rail = P(m, "VelvetRope", V3(0.3, 0.3, Wd - 1.2), at(ctx, 0.3, 1.8, wc), RGB(150, 20, 40), M.Fabric, true)
    anchor(rail, V3(-ctx.side * 0.8, 0.5, 0))
    local signPart = Kit.signBoard(m, "Sign", V3(12, 2, 0.25), at(ctx, -0.2, 15.6, wc).Position, Kit.facingRoad(ctx.side), "ROYAL GARAGE", RGB(90, 20, 40), RGB(255, 214, 90))
    Kit.billboard(signPart, "👑 ROYAL CONVOY", RGB(255, 214, 90), 90)
    pedestal(m, at(ctx, 7, 1, wc), 10, "Mythic")
    showcase(m, VehicleFactory, "royal_convoy", CFrame.new(at(ctx, 7, 1.1, wc + 4).Position))
    return m
end

-- ---------------------------------------------------------------- parody cameos
-- Original, fictional celebrity-style characters (no real people, faces or brands).
local CAMEOS = {
    {Id = "dhamaka_dev", Title = "🎬 Superstar Dhamaka Dev", Suit = RGB(245, 245, 240), Pants = RGB(245, 245, 240), Props = "star"},
    {Id = "captain_sixer", Title = "🏏 Captain Sixer", Suit = RGB(240, 240, 232), Pants = RGB(240, 240, 232), Props = "bat"},
    {Id = "dj_masala", Title = "🎤 DJ Masala Queen", Suit = RGB(255, 60, 170), Pants = RGB(30, 30, 40), Props = "dj"},
    {Id = "chai_fluencer", Title = "📱 Chai-Fluencer Rinku", Suit = RGB(40, 170, 160), Pants = RGB(40, 40, 60), Props = "selfie"},
    {Id = "moneybags", Title = "💼 Mr. Moneybags", Suit = RGB(24, 24, 28), Pants = RGB(24, 24, 28), Props = "tophat"},
}

local function cameo(folder, cf, spec, zone)
    local m = Instance.new("Model") m.Name = "Cameo_" .. spec.Id m.Parent = folder
    tag(m, "Cameo", zone)
    local function np(name, size, off, col, mat, shape)
        local p = P(m, name, size, cf * CFrame.new(off), col, mat or M.SmoothPlastic)
        if shape then p.Shape = shape end
        return p
    end
    local skin = RGB(170, 120, 86)
    np("LegL", V3(0.8, 2.2, 0.9), V3(-0.55, 1.1, 0), spec.Pants, M.Fabric)
    np("LegR", V3(0.8, 2.2, 0.9), V3(0.55, 1.1, 0), spec.Pants, M.Fabric)
    local torso = np("Torso", V3(2.4, 2.8, 1.3), V3(0, 3.6, 0), spec.Suit, M.Fabric)
    np("ArmL", V3(0.6, 2.5, 0.7), V3(-1.55, 3.6, 0), spec.Suit, M.Fabric)
    np("ArmR", V3(0.6, 2.5, 0.7), V3(1.55, 4.4, -0.6), spec.Suit, M.Fabric).CFrame = cf * CFrame.new(1.55, 4.6, -0.5) * CFrame.Angles(math.rad(60), 0, 0)
    local head = np("Head", V3(1.8, 1.8, 1.8), V3(0, 5.9, 0), skin, M.SmoothPlastic, Enum.PartType.Ball)
    local face = Instance.new("Decal") face.Texture = "rbxasset://textures/face.png" face.Face = Enum.NormalId.Front face.Parent = head
    np("Hair", V3(1.85, 0.6, 1.85), V3(0, 6.6, 0.05), RGB(24, 18, 14))
    if spec.Props == "star" then
        np("Sunglasses", V3(1.6, 0.35, 0.2), V3(0, 6.05, -0.85), RGB(10, 10, 10))
        np("GoldChain", V3(1.4, 0.2, 0.2), V3(0, 4.6, -0.7), GOLD, M.Neon)
        ball(np("Spotlight", V3(1, 1, 1), V3(0, 9.5, -2), RGB(255, 250, 220), M.Neon))
    elseif spec.Props == "bat" then
        np("Cap", V3(1.9, 0.4, 2.3), V3(0, 6.8, -0.3), RGB(30, 60, 140))
        np("Bat", V3(0.5, 3.4, 0.25), V3(2.1, 4.6, -1.2), RGB(210, 180, 120), M.Wood)
    elseif spec.Props == "dj" then
        np("Headphones", V3(2.1, 0.5, 0.5), V3(0, 6.1, 0), RGB(20, 20, 24))
        np("DJDeck", V3(3.4, 1.2, 1.6), V3(0, 2.6, -1.6), RGB(30, 30, 36), M.Metal)
        np("DeckGlow", V3(3.2, 0.1, 1.4), V3(0, 3.25, -1.6), RGB(60, 220, 255), M.Neon)
    elseif spec.Props == "selfie" then
        np("SelfieStick", V3(0.15, 0.15, 3), V3(1.6, 5.6, -2.2), RGB(40, 40, 44), M.Metal)
        np("Phone", V3(0.8, 1.3, 0.1), V3(1.6, 5.8, -3.7), RGB(20, 20, 24), M.Glass)
        cyl(np("RingLight", V3(0.1, 2.2, 2.2), V3(-2.2, 5.8, -1.6), RGB(255, 250, 240), M.Neon))
    elseif spec.Props == "tophat" then
        np("TopHat", V3(1.4, 1.6, 1.4), V3(0, 7.4, 0), RGB(20, 20, 22))
        np("Monocle", V3(0.4, 0.4, 0.1), V3(0.4, 6.0, -0.9), GOLD, M.Neon)
        np("MoneyBag", V3(1.4, 1.6, 1.4), V3(-1.8, 2.2, -0.6), RGB(120, 150, 70), M.Fabric)
    end
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(240, 50) bb.StudsOffset = V3(0, 2.6, 0) bb.MaxDistance = 60 bb.Parent = head
    local l = Instance.new("TextLabel")
    l.Size = UDim2.fromScale(1, 1) l.BackgroundTransparency = 0.2 l.BackgroundColor3 = RGB(12, 12, 16)
    l.TextColor3 = RGB(255, 214, 90) l.TextScaled = true l.Font = Enum.Font.GothamBlack l.Text = spec.Title l.Parent = bb
    anchor(torso, V3(0, 0, -1))
    return m
end

function WorldHooks.cameos(folder, cx, W, zone)
    local picks = zone == 4 and {{"chai_fluencer", 52}, {"moneybags", -50}} or (zone == 5 and {{"dhamaka_dev", 60}, {"captain_sixer", -44}, {"dj_masala", 104}} or {})
    for _, p in ipairs(picks) do
        for _, spec in ipairs(CAMEOS) do
            if spec.Id == p[1] then
                local pos = V3(cx + W.SidewalkOuter + 2.4, 0.8, p[2])
                cameo(folder, CFrame.lookAt(pos, pos - V3(1, 0, 0)), spec, zone)
            end
        end
    end
end

-- ---------------------------------------------------------------- collectible templates
function WorldHooks.collectibleTemplates(VehicleFactory)
    local old = ReplicatedStorage:FindFirstChild("SIT_CollectibleTemplates")
    if old then old:Destroy() end
    local f = Instance.new("Folder")
    f.Name = "SIT_CollectibleTemplates"
    for _, info in ipairs(VehicleFactory.Collectibles) do
        collectibleInfo[info.Id] = info
        local mdl = VehicleFactory.build(info.Id, 7, {rider = false})
        mdl.Name = info.Id
        mdl:SetAttribute("CollectibleId", info.Id)
        mdl:SetAttribute("DisplayName", info.Name)
        mdl:SetAttribute("Rarity", info.Rarity)
        mdl.Parent = f
    end
    f.Parent = ReplicatedStorage
    return f
end

return WorldHooks
