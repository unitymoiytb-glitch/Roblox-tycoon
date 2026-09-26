-- Weather: renders the brown monsoon rain decided by the server (workspace attributes
-- SIT_Raining / SIT_RainEnds) and makes the ground slippery while it lasts.
--   * rain: a pool of thin brown streak parts falling around the camera (one BulkMoveTo/frame)
--   * sky: local, reversible tweaks of Lighting (darker, brown haze)
--   * slippery: your movement follows your input with a lag (Config.Weather.Traction), so you
--     accelerate slowly, drift in turns and keep sliding when you let go
--   * HUD: a small banner with the time left and the x3 order bonus
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Weather = Config.Weather

local DROPS = 170
local AREA, TOP, BOTTOM = 46, 36, -8
local FALL = 95

-- ---------------------------------------------------------------- rain streaks
local folder = Instance.new("Folder")
folder.Name = "SIT_Rain"
local drops, offsets, cfs = {}, {}, {}
local rng = Random.new(7)
for i = 1, DROPS do
    local p = Instance.new("Part")
    p.Name = "RainDrop"
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = false
    p.Size = Vector3.new(0.07, 2.4, 0.07)
    p.Color = Color3.fromRGB(116, 86, 52)
    p.Material = Enum.Material.SmoothPlastic
    p.Transparency = 0.35
    p.Parent = folder
    drops[i] = p
    offsets[i] = Vector3.new(rng:NextNumber(-AREA, AREA), rng:NextNumber(BOTTOM, TOP), rng:NextNumber(-AREA, AREA))
end
local SLANT = CFrame.Angles(math.rad(8), 0, math.rad(5))

-- ---------------------------------------------------------------- sky
local saved = nil
local function setSky(on)
    local cc = Lighting:FindFirstChild("SIT_Color")
    local atm = Lighting:FindFirstChild("SIT_Atmosphere")
    if on and not saved then
        saved = {Brightness = Lighting.Brightness, OutdoorAmbient = Lighting.OutdoorAmbient}
        if cc then saved.Tint, saved.CCBright = cc.TintColor, cc.Brightness end
        if atm then saved.Density, saved.Haze, saved.AtmColor = atm.Density, atm.Haze, atm.Color end
    end
    if not saved then return end
    local info = TweenInfo.new(4, Enum.EasingStyle.Sine)
    TweenService:Create(Lighting, info, on and {Brightness = saved.Brightness * 0.55, OutdoorAmbient = Color3.fromRGB(100, 88, 70)}
        or {Brightness = saved.Brightness, OutdoorAmbient = saved.OutdoorAmbient}):Play()
    if cc then TweenService:Create(cc, info, on and {TintColor = Color3.fromRGB(214, 184, 142), Brightness = -0.06} or {TintColor = saved.Tint, Brightness = saved.CCBright}):Play() end
    if atm then TweenService:Create(atm, info, on and {Density = 0.46, Haze = 2.4, Color = Color3.fromRGB(150, 118, 80)} or {Density = saved.Density, Haze = saved.Haze, Color = saved.AtmColor}):Play() end
    if not on then saved = nil end
end

-- ---------------------------------------------------------------- HUD banner
local gui = Instance.new("ScreenGui")
gui.Name = "SIT_Weather"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")
local banner = Instance.new("TextLabel")
banner.Size = UDim2.new(0.34, 0, 0, 30)
banner.Position = UDim2.new(0.33, 0, 0, 126)
banner.BackgroundColor3 = Color3.fromRGB(70, 50, 30)
banner.BackgroundTransparency = 0.2
banner.TextColor3 = Color3.fromRGB(255, 226, 170)
banner.Font = Enum.Font.GothamBlack
banner.TextScaled = true
banner.Visible = false
banner.Parent = gui

-- ---------------------------------------------------------------- slippery ground
local controls = nil
task.spawn(function()
    pcall(function()
        local module = player:WaitForChild("PlayerScripts", 10):WaitForChild("PlayerModule", 10)
        controls = require(module):GetControls()
    end)
end)
local slide = Vector3.zero
local raining = false

local function tractionStep(dt)
    if not raining or not controls then slide = Vector3.zero return end
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local cam = workspace.CurrentCamera
    if not hum or not cam or hum.Health <= 0 then return end
    local mv = controls:GetMoveVector()
    local look = cam.CFrame.LookVector
    look = Vector3.new(look.X, 0, look.Z)
    if look.Magnitude < 1e-3 then return end
    look = look.Unit
    local right = Vector3.new(-look.Z, 0, look.X)
    local desired = right * mv.X - look * mv.Z
    if desired.Magnitude > 1 then desired = desired.Unit end
    -- Low traction: the actual direction/speed only slowly catches up with the input.
    slide += (desired - slide) * (1 - math.exp(-dt * Weather.Traction))
    if desired.Magnitude < 0.01 and slide.Magnitude < 0.03 then slide = Vector3.zero end
    hum:Move(slide, false)
end
pcall(function()
    RunService:BindToRenderStep("SIT_RainTraction", Enum.RenderPriority.Character.Value + 1, tractionStep)
end)

-- ---------------------------------------------------------------- per frame
local function update(dt)
    local now = workspace:GetServerTimeNow()
    local isRain = workspace:GetAttribute("SIT_Raining") == true
    if isRain ~= raining then
        raining = isRain
        folder.Parent = raining and workspace or nil
        banner.Visible = raining
        setSky(raining)
        slide = Vector3.zero
    end
    if not raining then return end
    local ends = workspace:GetAttribute("SIT_RainEnds") or now
    local left = math.max(0, math.floor(ends - now))
    banner.Text = string.format("🌧 BROWN RAIN %d:%02d • SLIPPERY • ORDERS x%d", left // 60, left % 60, Weather.PriceMultiplier)
    local cam = workspace.CurrentCamera
    if not cam then return end
    local c = cam.CFrame.Position
    local span = TOP - BOTTOM
    for i, p in ipairs(drops) do
        local o = offsets[i]
        local y = o.Y - FALL * dt
        if y < BOTTOM then y += span end
        o = Vector3.new(o.X, y, o.Z)
        offsets[i] = o
        cfs[i] = CFrame.new(c.X + o.X, c.Y + o.Y, c.Z + o.Z) * SLANT
    end
    workspace:BulkMoveTo(drops, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end
RunService.RenderStepped:Connect(update)
