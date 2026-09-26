-- PlayerLook: the starting "street rags" skin and the role title shown above the player.
--
-- Rank 1 players wear filthy, torn clothes built from the character itself (no clothing
-- asset IDs needed): the avatar's Shirt/Pants are stored away, torso and legs are recoloured
-- as grimy cloth, and a few welded, non-colliding patches add stains, rips showing skin,
-- a ragged hem and bare feet. The player's own skin colour is never changed.
-- apply() is idempotent and reversible, so a rank-up can swap the look without a respawn.
local PlayerLook = {}

local RGB = Color3.fromRGB
local SHIRT = RGB(158, 138, 104)      -- sweat-stained, once-white vest
local PANTS = RGB(84, 66, 48)         -- mud-brown trousers
local DIRT = RGB(92, 72, 48)
local DIRT_DARK = RGB(58, 46, 34)
local PATCH = RGB(64, 86, 108)        -- sewn-on scrap of blue cloth

local TORSO_PARTS = {"UpperTorso", "LowerTorso", "Torso"}
local LEG_PARTS = {"LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg", "Left Leg", "Right Leg"}
local FEET = {"LeftFoot", "RightFoot"}

local function skinColor(char)
    local head = char:FindFirstChild("Head")
    return head and head.Color or RGB(160, 112, 78)
end

-- Remember a body part's look once, so it can be restored exactly.
local function remember(part)
    if part:GetAttribute("SIT_OrigColor") == nil then
        part:SetAttribute("SIT_OrigColor", part.Color)
        part:SetAttribute("SIT_OrigMaterial", part.Material.Name)
    end
end

local function recolor(part, color)
    remember(part)
    part.Color = color
    part.Material = Enum.Material.Fabric
end

-- Welded detail on the surface of a body part. `face` = -1 front, 1 back (local Z).
local function detail(folder, part, name, size, x, y, face, color, rotZ)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.Color = color
    p.Material = Enum.Material.Fabric
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.Massless = true
    p.CastShadow = false
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    local z = face * (part.Size.Z / 2 + size.Z / 2 - 0.01)
    p.CFrame = part.CFrame * CFrame.new(x * part.Size.X / 2, y * part.Size.Y / 2, z) * CFrame.Angles(0, 0, math.rad(rotZ or 0))
    local w = Instance.new("WeldConstraint")
    w.Part0 = part
    w.Part1 = p
    w.Parent = p
    p.Parent = folder
    return p
end

local function addRags(char)
    local folder = Instance.new("Folder")
    folder.Name = "SIT_Rags"
    folder.Parent = char
    local skin = skinColor(char)
    local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    if torso then
        detail(folder, torso, "Stain", Vector3.new(0.7, 0.55, 0.05), -0.35, 0.1, -1, DIRT, 12)
        detail(folder, torso, "Stain", Vector3.new(0.45, 0.35, 0.05), 0.45, -0.45, -1, DIRT_DARK, -20)
        detail(folder, torso, "RipShowingSkin", Vector3.new(0.4, 0.28, 0.05), 0.35, 0.45, -1, skin, 25)
        detail(folder, torso, "SewnPatch", Vector3.new(0.55, 0.5, 0.05), -0.3, 0.2, 1, PATCH, -8)
        detail(folder, torso, "BackGrime", Vector3.new(0.9, 0.4, 0.05), 0.2, -0.5, 1, DIRT_DARK, 6)
        -- Ragged hem: three torn strips hanging over the waist.
        for i, x in ipairs({-0.6, 0.05, 0.6}) do
            detail(folder, torso, "TornHem", Vector3.new(0.34, 0.32, 0.05), x, -1.08, -1, i == 2 and DIRT or SHIRT, (i - 2) * 14)
        end
    end
    for _, name in ipairs({"LeftUpperLeg", "Left Leg"}) do
        local leg = char:FindFirstChild(name)
        if leg then
            detail(folder, leg, "KneeRip", Vector3.new(0.45, 0.35, 0.05), 0.05, -0.55, -1, skin, 10)
            break
        end
    end
    for _, name in ipairs({"RightLowerLeg", "Right Leg"}) do
        local leg = char:FindFirstChild(name)
        if leg then
            detail(folder, leg, "MudSplash", Vector3.new(0.6, 0.5, 0.05), 0, -0.3, -1, DIRT_DARK, -15)
            detail(folder, leg, "FrayedCuff", Vector3.new(0.75, 0.18, 0.05), 0, -0.85, -1, DIRT, 4)
            break
        end
    end
end

local function storedClothes(char, create)
    local f = char:FindFirstChild("SIT_StoredClothes")
    if not f and create then
        f = Instance.new("Folder")
        f.Name = "SIT_StoredClothes"
        f.Parent = char
    end
    return f
end

local function setRags(char, on)
    if on then
        if char:FindFirstChild("SIT_Rags") then return end
        local store = storedClothes(char, true)
        for _, c in ipairs(char:GetChildren()) do
            if c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") then c.Parent = store end
        end
        for _, n in ipairs(TORSO_PARTS) do local p = char:FindFirstChild(n) if p then recolor(p, SHIRT) end end
        for _, n in ipairs(LEG_PARTS) do local p = char:FindFirstChild(n) if p then recolor(p, PANTS) end end
        -- Bare, dirty feet: the skin colour, slightly muddied.
        for _, n in ipairs(FEET) do
            local p = char:FindFirstChild(n)
            if p then remember(p) p.Color = skinColor(char):Lerp(DIRT, 0.35) end
        end
        addRags(char)
    else
        local rags = char:FindFirstChild("SIT_Rags")
        if rags then rags:Destroy() end
        for _, p in ipairs(char:GetChildren()) do
            if p:IsA("BasePart") and p:GetAttribute("SIT_OrigColor") ~= nil then
                p.Color = p:GetAttribute("SIT_OrigColor")
                pcall(function() p.Material = Enum.Material[p:GetAttribute("SIT_OrigMaterial")] end)
                p:SetAttribute("SIT_OrigColor", nil)
                p:SetAttribute("SIT_OrigMaterial", nil)
            end
        end
        local store = storedClothes(char, false)
        if store then
            for _, c in ipairs(store:GetChildren()) do c.Parent = char end
            store:Destroy()
        end
    end
end

local function setTitle(char, title, displayName, lowest)
    local head = char:FindFirstChild("Head")
    if not head then return end
    local bb = head:FindFirstChild("SIT_Title")
    if not bb then
        bb = Instance.new("BillboardGui")
        bb.Name = "SIT_Title"
        bb.Size = UDim2.fromOffset(230, 54)
        bb.StudsOffset = Vector3.new(0, 2.7, 0)
        bb.MaxDistance = 70
        bb.LightInfluence = 0
        bb.Parent = head
        local role = Instance.new("TextLabel")
        role.Name = "Role"
        role.Size = UDim2.new(1, 0, 0.62, 0)
        role.BackgroundTransparency = 1
        role.Font = Enum.Font.GothamBlack
        role.TextScaled = true
        role.TextStrokeTransparency = 0.25
        role.Parent = bb
        local name = Instance.new("TextLabel")
        name.Name = "PlayerName"
        name.Size = UDim2.new(1, 0, 0.38, 0)
        name.Position = UDim2.fromScale(0, 0.62)
        name.BackgroundTransparency = 1
        name.Font = Enum.Font.GothamBold
        name.TextScaled = true
        name.TextColor3 = RGB(235, 230, 220)
        name.TextStrokeTransparency = 0.4
        name.Parent = bb
    end
    bb.Role.Text = string.upper(title)
    bb.Role.TextColor3 = lowest and RGB(196, 176, 150) or RGB(255, 214, 90)
    bb.Role.TextStrokeColor3 = lowest and RGB(40, 24, 16) or RGB(60, 36, 0)
    bb.PlayerName.Text = displayName
    -- The billboard already shows the name; hide Roblox's default overhead name.
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
end

-- rankIndex: 1 = starting rank (rags + "LESS THAN NOTHING"), higher ranks show their rank name.
function PlayerLook.apply(char, rankInfo, rankIndex, displayName)
    if not char then return end
    local lowest = rankIndex <= 1
    setRags(char, lowest)
    setTitle(char, rankInfo.Title or rankInfo.Name, displayName, lowest)
end

return PlayerLook
