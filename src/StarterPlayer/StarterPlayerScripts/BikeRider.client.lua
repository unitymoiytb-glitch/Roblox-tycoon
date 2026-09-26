-- BikeRider: when the server welds a "Ride_Bicycle" model to the character, the player rides
-- instead of walking: the walk/run animations are stopped and the R15 joints are posed
-- procedurally every frame (seated hips, pedalling legs in time with speed, hands on the
-- handlebar). No animation assets needed. Speed/jump come from Config.Vehicles.Bicycle.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local rad = math.rad

local JOINTS = {
    LeftHip = "LeftUpperLeg", RightHip = "RightUpperLeg", LeftKnee = "LeftLowerLeg", RightKnee = "RightLowerLeg",
    LeftShoulder = "LeftUpperArm", RightShoulder = "RightUpperArm", LeftElbow = "LeftLowerArm", RightElbow = "RightLowerArm",
    Waist = "UpperTorso",
}

local state = nil -- {char, hum, root, motors, animate, phase}

local function findMotors(char)
    local motors = {}
    for joint, partName in pairs(JOINTS) do
        local part = char:FindFirstChild(partName)
        local m = part and part:FindFirstChild(joint)
        if m and m:IsA("Motor6D") then motors[joint] = m end
    end
    return motors
end

local function stopRiding()
    if not state then return end
    for _, m in pairs(state.motors) do
        if m.Parent then m.Transform = CFrame.new() end
    end
    if state.animate and state.animate.Parent then state.animate.Disabled = false end
    state = nil
end

local function startRiding(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.RigType ~= Enum.HumanoidRigType.R15 then return end
    local animate = char:FindFirstChild("Animate")
    if animate then animate.Disabled = true end
    local animator = hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(0.1) end
    end
    state = {char = char, hum = hum, root = root, motors = findMotors(char), animate = animate, phase = 0}
end

RunService.Stepped:Connect(function(_, dt)
    local char = player.Character
    local riding = char and char:FindFirstChild("Ride_Bicycle") ~= nil
    if riding and (not state or state.char ~= char) then
        stopRiding()
        startRiding(char)
    elseif not riding and state then
        stopRiding()
    end
    if not state then return end
    local hum, root, m = state.hum, state.root, state.motors
    local v = root.AssemblyLinearVelocity
    local speed = Vector3.new(v.X, 0, v.Z).Magnitude
    local airborne = hum.FloorMaterial == Enum.Material.Air
    -- Cadence follows ground speed; freewheel (legs level) in the air or when stopped.
    if not airborne then state.phase = (state.phase + dt * speed * 0.55) % (math.pi * 2) end
    local pump = (airborne or speed < 1) and 0 or 1
    local s = math.sin(state.phase) * pump
    local c = math.cos(state.phase) * pump
    local function set(name, cf) local mm = m[name] if mm then mm.Transform = cf end end
    -- Seated: thighs forward ~65 deg, knees bent, pedalling half a turn out of phase.
    set("LeftHip", CFrame.Angles(rad(65 + 22 * s), 0, 0))
    set("RightHip", CFrame.Angles(rad(65 - 22 * s), 0, 0))
    set("LeftKnee", CFrame.Angles(rad(-(60 + 28 * c)), 0, 0))
    set("RightKnee", CFrame.Angles(rad(-(60 - 28 * c)), 0, 0))
    -- Lean forward onto the handlebar, arms reaching down to the grips.
    set("Waist", CFrame.Angles(rad(-14), 0, rad(2 * s)))
    set("LeftShoulder", CFrame.Angles(rad(62), 0, rad(-6)))
    set("RightShoulder", CFrame.Angles(rad(62), 0, rad(6)))
    set("LeftElbow", CFrame.Angles(rad(18), 0, 0))
    set("RightElbow", CFrame.Angles(rad(18), 0, 0))
end)

player.CharacterRemoving:Connect(function() state = nil end)
