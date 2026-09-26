local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local SoundService=game:GetService("SoundService")
local MarketplaceService=game:GetService("MarketplaceService")
local TweenService=game:GetService("TweenService")

local player=Players.LocalPlayer
local Remotes=ReplicatedStorage:WaitForChild("SIT_Remotes")
local MissionRE=Remotes:WaitForChild("Mission")
local UIRE=Remotes:WaitForChild("UI")
local ActionRE=Remotes:WaitForChild("Action")
local TrafficRE=Remotes:WaitForChild("TrafficHit")
local Config=require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local music=SoundService:FindFirstChild("SIT_IndiaMusic") or Instance.new("Sound")
music.Name="SIT_IndiaMusic"
music.SoundId="rbxassetid://1844405452"
music.Looped=true
music.Volume=.28
music.Parent=SoundService
if not music.IsPlaying then pcall(function() music:Play() end) end

local gui=Instance.new("ScreenGui")
gui.Name="SIT_UI"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.Parent=player:WaitForChild("PlayerGui")

local function label(parent,text,pos,size,scaled)
    local l=Instance.new("TextLabel")
    l.BackgroundColor3=Color3.fromRGB(14,14,17)
    l.BackgroundTransparency=.1
    l.TextColor3=Color3.new(1,1,1)
    l.Text=text
    l.Position=pos
    l.Size=size
    l.Font=Enum.Font.GothamBold
    l.TextScaled=scaled~=false
    l.Parent=parent
    return l
end

local function button(parent,text,pos,size,cb)
    local b=Instance.new("TextButton")
    b.BackgroundColor3=Color3.fromRGB(255,170,35)
    b.TextColor3=Color3.fromRGB(25,20,10)
    b.Text=text
    b.Position=pos
    b.Size=size
    b.Font=Enum.Font.GothamBold
    b.TextScaled=true
    b.Parent=parent
    if cb then b.MouseButton1Click:Connect(cb) end
    return b
end

local top=Instance.new("Frame")
top.Position=UDim2.new(0,0,0,48)
top.Size=UDim2.new(1,0,0,66)
top.BackgroundTransparency=.08
top.BackgroundColor3=Color3.fromRGB(8,8,10)
top.Parent=gui
local cash=label(top,"₹0",UDim2.new(.015,0,.12,0),UDim2.new(.18,0,.72,0))
local rank=label(top,"Street Runner",UDim2.new(.20,0,.12,0),UDim2.new(.23,0,.72,0))
local xp=label(top,"0 XP",UDim2.new(.44,0,.12,0),UDim2.new(.14,0,.72,0))
local deliveries=label(top,"0 DEL",UDim2.new(.59,0,.12,0),UDim2.new(.12,0,.72,0))
local master=label(gui,"👑 SERVER MASTER: ...",UDim2.new(.34,0,0,112),UDim2.new(.32,0,0,42))
local shopTopButton=button(top,"SHOP",UDim2.new(.72,0,.12,0),UDim2.new(.12,0,.72,0),nil)
button(top,"1ST PERSON",UDim2.new(.85,0,.12,0),UDim2.new(.14,0,.72,0),function()
    player.CameraMode=player.CameraMode==Enum.CameraMode.Classic and Enum.CameraMode.LockFirstPerson or Enum.CameraMode.Classic
end)

local left=Instance.new("Frame")
left.Position=UDim2.new(.015,0,0,160)
left.Size=UDim2.new(0,280,0,330)
left.BackgroundColor3=Color3.fromRGB(10,10,13)
left.BackgroundTransparency=.12
left.Parent=gui
local missionTitle=label(left,"NO ACTIVE DELIVERY",UDim2.new(.04,0,.03,0),UDim2.new(.92,0,.12,0))
local missionInfo=label(left,"Explore your block. Interactions appear when you get close.",UDim2.new(.04,0,.17,0),UDim2.new(.92,0,.21,0),false)
missionInfo.TextWrapped=true missionInfo.TextSize=17
local findVendor=label(left,"",UDim2.new(.05,0,.41,0),UDim2.new(.9,0,.12,0))
findVendor.BackgroundTransparency=1
local resourceLine=label(left,"🔩 0 SCRAP     🎟 0 TOKENS",UDim2.new(.05,0,.54,0),UDim2.new(.9,0,.08,0),false)
resourceLine.TextSize=14 resourceLine.BackgroundTransparency=1
local rewardsButton=button(left,"🎁 CLAIM REWARDS",UDim2.new(.05,0,.63,0),UDim2.new(.9,0,.11,0),nil)
local rebirthButton=button(left,"REBIRTH",UDim2.new(.05,0,.76,0),UDim2.new(.9,0,.10,0),function() ActionRE:FireServer("REBIRTH") end)
rebirthButton.Visible=false
rewardsButton.Visible=false
shopTopButton.Visible=false
local progress=label(left,"KEEP WORKING",UDim2.new(.05,0,.88,0),UDim2.new(.9,0,.09,0),false)
progress.TextWrapped=true progress.TextSize=14

local showToast

local rewards=Instance.new("Frame")
rewards.Position=UDim2.new(.5,-220,.5,-190) rewards.Size=UDim2.new(0,440,0,380)
rewards.BackgroundColor3=Color3.fromRGB(12,12,16) rewards.Visible=false rewards.Parent=gui
local rewardsTitle=label(rewards,"🎁 REWARD CENTER",UDim2.new(.05,0,.04,0),UDim2.new(.9,0,.1,0))
local dailyStatus=label(rewards,"DAILY • READY",UDim2.new(.06,0,.18,0),UDim2.new(.88,0,.09,0),false)
local hourlyStatus=label(rewards,"SESSION • 10 MIN",UDim2.new(.06,0,.40,0),UDim2.new(.88,0,.09,0),false)
local monthlyStatus=label(rewards,"30-DAY CHEST • 0/30",UDim2.new(.06,0,.62,0),UDim2.new(.88,0,.09,0),false)
button(rewards,"CLAIM DAILY",UDim2.new(.06,0,.28,0),UDim2.new(.88,0,.09,0),function() ActionRE:FireServer("CLAIM_DAILY") end)
button(rewards,"CLAIM SESSION REWARD",UDim2.new(.06,0,.50,0),UDim2.new(.88,0,.09,0),function() ActionRE:FireServer("CLAIM_HOURLY") end)
button(rewards,"CLAIM 30-DAY CHEST",UDim2.new(.06,0,.72,0),UDim2.new(.88,0,.09,0),function() ActionRE:FireServer("CLAIM_MONTHLY") end)
button(rewards,"CLOSE",UDim2.new(.32,0,.86,0),UDim2.new(.36,0,.09,0),function() rewards.Visible=false end)
rewardsButton.MouseButton1Click:Connect(function() rewards.Visible=not rewards.Visible end)

local shop=Instance.new("Frame")
shop.Position=UDim2.new(.5,-245,.5,-225) shop.Size=UDim2.new(0,490,0,450)
shop.BackgroundColor3=Color3.fromRGB(12,12,16) shop.Visible=false shop.Parent=gui
label(shop,"🛒 SURVIVE SHOP",UDim2.new(.05,0,.03,0),UDim2.new(.9,0,.10,0))
local shopInfo=label(shop,"Permanent boosts + optional shortcuts. Core progression stays playable for free.",UDim2.new(.07,0,.14,0),UDim2.new(.86,0,.09,0),false)
shopInfo.TextWrapped=true shopInfo.TextSize=14
local function promptPass(key)
    local id=Config.Monetization.Gamepasses[key]
    if not id or id==0 then showToast("Set the "..key.." Game Pass ID in Config before publishing") return end
    MarketplaceService:PromptGamePassPurchase(player,id)
end
local function promptProduct(key)
    local id=Config.Monetization.Products[key]
    if not id or id==0 then showToast("Set the "..key.." Developer Product ID in Config before publishing") return end
    MarketplaceService:PromptProductPurchase(player,id)
end
button(shop,"💰 2x CASH",UDim2.new(.06,0,.26,0),UDim2.new(.42,0,.10,0),function() promptPass("DoubleCash") end)
button(shop,"⚡ 2x XP",UDim2.new(.52,0,.26,0),UDim2.new(.42,0,.10,0),function() promptPass("DoubleXP") end)
button(shop,"📦 VIP CONTRACTS",UDim2.new(.06,0,.39,0),UDim2.new(.42,0,.10,0),function() promptPass("VIPContracts") end)
button(shop,"🚙 PREMIUM 4x4",UDim2.new(.52,0,.39,0),UDim2.new(.42,0,.10,0),function() promptPass("Premium4x4") end)
button(shop,"💵 CASH PACK",UDim2.new(.06,0,.54,0),UDim2.new(.42,0,.10,0),function() promptProduct("CashSmall") end)
button(shop,"💎 BIG CASH PACK",UDim2.new(.52,0,.54,0),UDim2.new(.42,0,.10,0),function() promptProduct("CashBig") end)
button(shop,"🎁 3 LOOTBOX TOKENS",UDim2.new(.06,0,.67,0),UDim2.new(.42,0,.10,0),function() promptProduct("Lootbox") end)
button(shop,"🏪 INSTANT BUSINESS",UDim2.new(.52,0,.67,0),UDim2.new(.42,0,.10,0),function() promptProduct("InstantBusiness") end)
button(shop,"🎲 OPEN LOOTBOX (3 TOKENS)",UDim2.new(.12,0,.80,0),UDim2.new(.76,0,.08,0),function() ActionRE:FireServer("OPEN_LOOTBOX") end)
button(shop,"CLOSE",UDim2.new(.32,0,.90,0),UDim2.new(.36,0,.07,0),function() shop.Visible=false end)
shopTopButton.MouseButton1Click:Connect(function() shop.Visible=not shop.Visible end)

local function fmtWait(sec)
    sec=math.max(0,math.floor(sec or 0))
    if sec<=0 then return "READY TO CLAIM" end
    local h=math.floor(sec/3600) local m=math.floor((sec%3600)/60)
    if h>0 then return h.."h "..m.."m" end
    return m.."m"
end

local right=Instance.new("Frame")
right.Position=UDim2.new(1,-295,.15,0)
right.Size=UDim2.new(0,280,0,520)
right.BackgroundColor3=Color3.fromRGB(10,10,13)
right.BackgroundTransparency=.12
right.Visible=false
right.Parent=gui
local rightTitle=label(right,"UPGRADES",UDim2.new(.05,0,.02,0),UDim2.new(.9,0,.07,0))
local function clearRight()
    for _,c in ipairs(right:GetChildren()) do if c~=rightTitle then c:Destroy() end end
end
local function openGarage()
    clearRight() right.Visible=true rightTitle.Text="🔧 GARAGE"
    local y=.12
    for _,name in ipairs({"Feet","Bicycle","Hoverboard","Rusty Scooter","Tuk-Tuk","SUV","Mega 4x4"}) do
        local v=Config.Vehicles[name]
        button(right,name.."  ₹"..v.Price,UDim2.new(.05,0,y,0),UDim2.new(.9,0,.09,0),function() ActionRE:FireServer("BUY_VEHICLE",name) end)
        y+=.105
    end
    button(right,"CLOSE",UDim2.new(.28,0,.86,0),UDim2.new(.44,0,.09,0),function() right.Visible=false end)
end
local function openBusiness()
    clearRight() right.Visible=true rightTitle.Text="💼 BUSINESSES"
    local y=.12
    for _,b in ipairs(Config.Businesses) do
        button(right,b.Name.."  ₹"..b.Price,UDim2.new(.05,0,y,0),UDim2.new(.9,0,.09,0),function() ActionRE:FireServer("BUY_BUSINESS",b.Id) end)
        y+=.105
    end
    button(right,"CLOSE",UDim2.new(.28,0,.86,0),UDim2.new(.44,0,.09,0),function() right.Visible=false end)
end

local toast=label(gui,"",UDim2.new(.29,0,.84,0),UDim2.new(.42,0,.075,0))
toast.Visible=false
showToast=function(t)
    toast.Text=t toast.Visible=true
    task.delay(2.6,function() if toast.Text==t then toast.Visible=false end end)
end

local milestone=Instance.new("Frame")
milestone.Position=UDim2.new(.5,-240,.18,-70) milestone.Size=UDim2.new(0,480,0,140)
milestone.BackgroundColor3=Color3.fromRGB(12,18,24) milestone.BackgroundTransparency=.05 milestone.Visible=false milestone.Parent=gui
local milestoneIcon=label(milestone,"✨",UDim2.new(.03,0,.18,0),UDim2.new(.18,0,.64,0))
milestoneIcon.BackgroundTransparency=1
local milestoneTitle=label(milestone,"UNLOCKED",UDim2.new(.22,0,.12,0),UDim2.new(.73,0,.34,0),false)
milestoneTitle.TextSize=27 milestoneTitle.TextXAlignment=Enum.TextXAlignment.Left milestoneTitle.BackgroundTransparency=1
local milestoneText=label(milestone,"",UDim2.new(.22,0,.48,0),UDim2.new(.73,0,.34,0),false)
milestoneText.TextSize=17 milestoneText.TextWrapped=true milestoneText.TextXAlignment=Enum.TextXAlignment.Left milestoneText.BackgroundTransparency=1
local milestoneSerial=0
local function showMilestone(data)
    milestoneSerial+=1 local serial=milestoneSerial
    milestoneIcon.Text=data.Icon or "✨" milestoneTitle.Text=data.Title or "UNLOCKED" milestoneText.Text=data.Text or ""
    milestone.Position=UDim2.new(.5,-240,.12,-90) milestone.BackgroundTransparency=1 milestone.Visible=true
    TweenService:Create(milestone,TweenInfo.new(.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(.5,-240,.18,-70),BackgroundTransparency=.05}):Play()
    task.delay(3.2,function()
        if serial~=milestoneSerial then return end
        local tw=TweenService:Create(milestone,TweenInfo.new(.22),{Position=UDim2.new(.5,-240,.14,-90),BackgroundTransparency=1}) tw:Play()
        tw.Completed:Wait() if serial==milestoneSerial then milestone.Visible=false end
    end)
end

local dialog=Instance.new("Frame")
dialog.Position=UDim2.new(.5,-260,.63,-100)
dialog.Size=UDim2.new(0,520,0,180)
dialog.BackgroundColor3=Color3.fromRGB(12,12,15)
dialog.Visible=false
dialog.Parent=gui
local dialogTitle=label(dialog,"NPC",UDim2.new(.04,0,.05,0),UDim2.new(.92,0,.24,0))
local dialogText=label(dialog,"",UDim2.new(.05,0,.31,0),UDim2.new(.9,0,.38,0),false)
dialogText.TextWrapped=true dialogText.TextSize=18
local dialogAction=button(dialog,"OK",UDim2.new(.32,0,.75,0),UDim2.new(.36,0,.17,0),function() dialog.Visible=false end)

local rankOffer=Instance.new("Frame")
rankOffer.Position=UDim2.new(.5,-250,.5,-175)
rankOffer.Size=UDim2.new(0,500,0,350)
rankOffer.BackgroundColor3=Color3.fromRGB(12,12,15)
rankOffer.Visible=false
rankOffer.Parent=gui
local roTitle=label(rankOffer,"PROMOTION",UDim2.new(.05,0,.05,0),UDim2.new(.9,0,.13,0))
local roInfo=label(rankOffer,"",UDim2.new(.07,0,.21,0),UDim2.new(.86,0,.47,0),false)
roInfo.TextWrapped=true roInfo.TextSize=20
button(rankOffer,"LET ME THROUGH",UDim2.new(.08,0,.75,0),UDim2.new(.4,0,.14,0),function() ActionRE:FireServer("TRY_RANK_UP") rankOffer.Visible=false end)
button(rankOffer,"LATER",UDim2.new(.52,0,.75,0),UDim2.new(.4,0,.14,0),function() rankOffer.Visible=false end)

local vendorMenu=Instance.new("Frame")
vendorMenu.Position=UDim2.new(.5,-280,.5,-210)
vendorMenu.Size=UDim2.new(0,560,0,420)
vendorMenu.BackgroundColor3=Color3.fromRGB(12,12,15)
vendorMenu.Visible=false
vendorMenu.Parent=gui
local vendorTitle=label(vendorMenu,"CHOOSE DELIVERY",UDim2.new(.05,0,.04,0),UDim2.new(.9,0,.12,0))
local vendorSubtitle=label(vendorMenu,"Higher-paying items are worth more if you survive the traffic.",UDim2.new(.06,0,.17,0),UDim2.new(.88,0,.12,0),false)
vendorSubtitle.TextWrapped=true vendorSubtitle.TextSize=16
local vendorButtons={}
for i=1,3 do
    vendorButtons[i]=button(vendorMenu,"ITEM",UDim2.new(.08,0,.31+(i-1)*.16,0),UDim2.new(.84,0,.12,0),nil)
end
button(vendorMenu,"CANCEL",UDim2.new(.30,0,.84,0),UDim2.new(.4,0,.09,0),function() vendorMenu.Visible=false end)

local marker=nil
local arrow=nil
local targetPart=nil
local promoArrow=nil
local tutorialArrow=nil
local currentRank=1

local function orientSpawnTowardExit(char)
    task.wait(1.0)
    if currentRank~=1 then return end
    local root=char and char:FindFirstChild("HumanoidRootPart")
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    local cam=workspace.CurrentCamera
    if not root or not cam then return end
    -- Starter shack opens toward -Z; always face the street, independent of old map coordinates.
    local exitLook=Vector3.new(root.Position.X,root.Position.Y,root.Position.Z-30)
    root.CFrame=CFrame.lookAt(root.Position,exitLook)
    root.AssemblyLinearVelocity=Vector3.zero
    if hum then hum.AutoRotate=false end
    cam.CameraType=Enum.CameraType.Scriptable
    local cameraPos=root.Position + Vector3.new(0,5.5,9.5)
    cam.CFrame=CFrame.lookAt(cameraPos,Vector3.new(root.Position.X,root.Position.Y+2,root.Position.Z-24))
    task.wait(1.15)
    if hum then hum.AutoRotate=true end
    if cam then
        cam.CameraType=Enum.CameraType.Custom
        if hum then cam.CameraSubject=hum end
    end
end

player.CharacterAdded:Connect(function(char)
    task.spawn(function() orientSpawnTowardExit(char) end)
end)
if player.Character then task.spawn(function() orientSpawnTowardExit(player.Character) end) end

local function setTutorialVendorGuide(enabled)
    if tutorialArrow then tutorialArrow:Destroy() tutorialArrow=nil end
    if not enabled then return end
    local world=workspace:FindFirstChild("SIT_World")
    local vendor=world and world:FindFirstChild("VendorNPC_1")
    local torso=vendor and vendor:FindFirstChild("Torso")
    if not torso then return end
    tutorialArrow=Instance.new("BillboardGui")
    tutorialArrow.Name="FirstJobGuide" tutorialArrow.Size=UDim2.fromOffset(220,105) tutorialArrow.AlwaysOnTop=true tutorialArrow.StudsOffset=Vector3.new(0,8,0) tutorialArrow.Adornee=torso tutorialArrow.Parent=torso
    local t=Instance.new("TextLabel")
    t.Size=UDim2.fromScale(1,1) t.BackgroundTransparency=.12 t.BackgroundColor3=Color3.fromRGB(8,18,28) t.TextColor3=Color3.fromRGB(80,180,255) t.TextStrokeTransparency=.2 t.TextScaled=true t.TextWrapped=true t.Font=Enum.Font.GothamBlack
    t.Text="⬇ FIRST JOB\nTALK TO RAJU" t.Parent=tutorialArrow
end

local function setNpcGuide(modelName,text,color)
    if tutorialArrow then tutorialArrow:Destroy() tutorialArrow=nil end
    if not modelName then return end
    local world=workspace:FindFirstChild("SIT_World")
    local npc=world and world:FindFirstChild(modelName)
    local torso=npc and npc:FindFirstChild("Torso")
    if not torso then return end
    tutorialArrow=Instance.new("BillboardGui")
    tutorialArrow.Name="OnboardingGuide" tutorialArrow.Size=UDim2.fromOffset(245,110) tutorialArrow.AlwaysOnTop=true tutorialArrow.StudsOffset=Vector3.new(0,8,0) tutorialArrow.Adornee=torso tutorialArrow.Parent=torso
    local t=Instance.new("TextLabel")
    t.Size=UDim2.fromScale(1,1) t.BackgroundTransparency=.1 t.BackgroundColor3=Color3.fromRGB(8,18,28) t.TextColor3=color or Color3.fromRGB(80,180,255) t.TextStrokeTransparency=.2 t.TextScaled=true t.TextWrapped=true t.Font=Enum.Font.GothamBlack
    t.Text=text t.Parent=tutorialArrow
end

local function setTarget(part,color)
    targetPart=part
    if marker then marker:Destroy() marker=nil end
    if arrow then arrow:Destroy() arrow=nil end
    marker=Instance.new("Highlight")
    marker.FillColor=color marker.OutlineColor=Color3.new(1,1,1)
    marker.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop marker.Adornee=part marker.Parent=part
    arrow=Instance.new("BillboardGui")
    arrow.Name="DeliveryArrow" arrow.Size=UDim2.fromOffset(90,90) arrow.AlwaysOnTop=true arrow.StudsOffset=Vector3.new(0,6,0) arrow.Adornee=part arrow.Parent=part
    local a=Instance.new("TextLabel")
    a.Size=UDim2.fromScale(1,1) a.BackgroundTransparency=1 a.Text="▼" a.TextColor3=Color3.fromRGB(60,155,255) a.TextStrokeTransparency=.2 a.TextScaled=true a.Font=Enum.Font.GothamBlack a.Parent=arrow
end
local function clearTarget()
    targetPart=nil
    if marker then marker:Destroy() marker=nil end
    if arrow then arrow:Destroy() arrow=nil end
end

local nav=label(gui,"",UDim2.new(.38,0,.91,0),UDim2.new(.24,0,.055,0))
nav.BackgroundTransparency=.28 nav.Visible=false
RunService.RenderStepped:Connect(function()
    local char=player.Character local root=char and char:FindFirstChild("HumanoidRootPart")
    if targetPart and targetPart.Parent and root then
        local d=(root.Position-targetPart.Position).Magnitude nav.Visible=true nav.Text="🔵 DELIVERY  "..math.floor(d).."m"
    elseif promoArrow and promoArrow.Parent and promoArrow.Adornee and root then
        local d=(root.Position-promoArrow.Adornee.Position).Magnitude nav.Visible=true nav.Text="🟡 NEXT DISTRICT  "..math.floor(d).."m"
    else
        nav.Visible=false
    end
end)

local function setLocalHidden(inst,hidden)
    if inst:IsA("BasePart") then inst.LocalTransparencyModifier=hidden and 1 or 0 end
    if inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then inst.Enabled=not hidden end
end

local function applyZoneVisibility(rankValue)
    currentRank=rankValue or 1
    local world=workspace:FindFirstChild("SIT_World") if not world then return end
    for _,obj in ipairs(world:GetDescendants()) do
        local owner=obj local zone=nil
        while owner and owner~=world do
            zone=owner:GetAttribute("SITZone")
            if zone then break end
            owner=owner.Parent
        end
        if zone then setLocalHidden(obj,zone>currentRank) end
        if obj:IsA("BasePart") and obj:GetAttribute("PromotionGateFor") then obj.LocalTransparencyModifier=1 end
    end
end

local function setPromotionGuide(enabled,nextName)
    if promoArrow then promoArrow:Destroy() promoArrow=nil end
    if not enabled then return end
    local world=workspace:FindFirstChild("SIT_World")
    local guard=world and world:FindFirstChild("GuardNPC_"..tostring(currentRank))
    local torso=guard and guard:FindFirstChild("Torso")
    if not torso then return end
    promoArrow=Instance.new("BillboardGui")
    promoArrow.Name="PromotionGuide" promoArrow.Size=UDim2.fromOffset(200,105) promoArrow.AlwaysOnTop=true promoArrow.StudsOffset=Vector3.new(0,8,0) promoArrow.Adornee=torso promoArrow.Parent=torso
    local t=Instance.new("TextLabel")
    t.Size=UDim2.fromScale(1,1) t.BackgroundTransparency=.15 t.BackgroundColor3=Color3.fromRGB(20,15,3) t.TextColor3=Color3.fromRGB(255,210,55) t.TextStrokeTransparency=.25 t.TextScaled=true t.TextWrapped=true t.Font=Enum.Font.GothamBlack
    t.Text="⬇ YOU'RE READY\nGO SEE THE GUARD"
    t.Parent=promoArrow
end

UIRE.OnClientEvent:Connect(function(kind,data)
    if kind=="SYNC" then
        cash.Text="₹"..math.floor(data.Cash or 0)
        rank.Text=data.RankName or "?"
        xp.Text=math.floor(data.XP or 0).." XP"
        deliveries.Text=(data.TotalDeliveries or 0).." DEL"
        resourceLine.Text="🔩 "..tostring(data.Scrap or 0).." SCRAP     🎟 "..tostring(data.Tokens or 0).." TOKENS"
        local streak=data.DailyStreak or 0
        if streak>=30 then
            dailyStatus.Text="DAILY • 30/30 COMPLETE"
        else
            dailyStatus.Text="DAILY • Day "..tostring(streak+1).." / 30 • "..fmtWait(data.DailyWait)
        end
        if data.SessionDone then
            hourlyStatus.Text="SESSION • ALL 10-60 MIN REWARDS CLAIMED"
        else
            hourlyStatus.Text="SESSION • "..tostring(data.SessionMinutes or 10).." MIN • "..fmtWait(data.SessionWait)
        end
        if data.MonthlyReady then
            monthlyStatus.Text="30-DAY CHEST • READY TO CLAIM"
        else
            monthlyStatus.Text="30-DAY CHEST • "..tostring(streak).."/30 DAYS"
        end
        applyZoneVisibility(data.Rank or 1)
        local del=data.TotalDeliveries or 0
        local seenFirstVendor=data.VendorSeen and data.VendorSeen[1]
        local ownsBike=data.OwnedVehicles and data.OwnedVehicles.Bicycle
        rewardsButton.Visible=del>=1
        shopTopButton.Visible=del>=2
        rebirthButton.Visible=(data.Rank or 1)>=4
        if (data.Rank or 1)==1 and del==0 and not seenFirstVendor then
            setNpcGuide("VendorNPC_1","⬇ FIRST JOB\nTALK TO RAJU",Color3.fromRGB(80,180,255))
            missionTitle.Text="STEP 1 • GET A JOB"
            missionInfo.Text="Walk out of your room and talk to Raju. Your first delivery starts there."
            progress.Text="FIRST GOAL • survive 1 delivery"
        elseif (data.Rank or 1)==1 and del>=1 and not ownsBike then
            setNpcGuide("MechanicNPC","⬇ NEW UPGRADE\nBUY A BICYCLE",Color3.fromRGB(90,220,255))
            missionTitle.Text="STEP 2 • GET FASTER"
            missionInfo.Text="You can afford a bicycle now. Talk to the mechanic before your next run."
            progress.Text="BICYCLE • ₹350"
        elseif (data.Rank or 1)==1 and del>=4 and not (data.NPCUnlocks and data.NPCUnlocks.Broker) then
            setNpcGuide("BrokerNPC","⬇ BUSINESS UNLOCK\nTALK TO BROKER",Color3.fromRGB(100,235,135))
            missionTitle.Text="STEP 3 • MAKE MONEY WHILE MOVING"
            missionInfo.Text="The Street Broker will finally talk to you. Unlock your first passive business."
            progress.Text="TEA STALL • ₹1200"
        elseif not data.PromotionReady then
            if tutorialArrow then tutorialArrow:Destroy() tutorialArrow=nil end
            if (data.Rank or 1)==1 then
                missionTitle.Text="CLIMB OUT OF THE SLUMS"
                missionInfo.Text=tostring(math.max(0,12-del)).." deliveries left until Courier. New cargo appears as you prove yourself."
                progress.Text=tostring(del).." / 12 DELIVERIES • ₹"..tostring(math.floor(data.Cash or 0)).." / 1400"
            end
        end
        if data.PromotionReady and data.NextRank then
            if tutorialArrow then tutorialArrow:Destroy() tutorialArrow=nil end
            progress.Text="🟡 PROMOTION READY — go see the guard"
            setPromotionGuide(true,data.NextRank.Name)
        else
            progress.Text="KEEP WORKING"
            setPromotionGuide(false)
        end
        if data.Toast then showToast(data.Toast) end
    elseif kind=="TOAST" then
        showToast(data)
    elseif kind=="MILESTONE" then
        showMilestone(data or {})
    elseif kind=="MASTER" then
        master.Text="👑 SERVER MASTER: "..tostring(data)
    elseif kind=="NPC" then
        dialogTitle.Text=data.Title dialogText.Text=data.Text dialog.Visible=true
        dialogAction.Text="OK"
        local key=data.Key
        dialogAction.MouseButton1Click:Once(function()
            dialog.Visible=false
            if key=="Mechanic" then openGarage() elseif key=="Broker" then openBusiness() end
        end)
    elseif kind=="GUARD_BLOCK" then
        dialogTitle.Text=data.Title or "NOT YET"
        dialogText.Text=data.Text or "You are not ready for this district."
        dialogAction.Text="FINE"
        dialog.Visible=true
    elseif kind=="RANK_OFFER" then
        roTitle.Text="THE GUARD WILL LET YOU INTO "..string.upper(data.Name)
        roInfo.Text="Cash: ₹"..data.CurrentCash.." / ₹"..data.Price.."\nXP: "..data.CurrentXP.." / "..data.XP.."\nDeliveries: "..data.CurrentDeliveries.." / "..data.Deliveries.."\n\nPay the promotion cost and unlock the next district."
        rankOffer.Visible=true
    elseif kind=="VENDOR_MENU" then
        setTutorialVendorGuide(false)
        vendorTitle.Text=data.Title or "CHOOSE DELIVERY"
        local items=data.Items or {}
        for i,b in ipairs(vendorButtons) do
            local item=items[i]
            if item then
                b.Visible=true
                b.Text=item.Name.."   •   x"..string.format("%.2f",item.Mult or 1).." payout"
                b.MouseButton1Click:Once(function()
                    vendorMenu.Visible=false
                    ActionRE:FireServer("START_ITEM_MISSION",item.Name)
                end)
            else
                b.Visible=false
            end
        end
        vendorMenu.Visible=true
    end
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr,passId,purchased)
    if plr==player and purchased then showToast("Purchase complete — rejoin if the boost does not appear immediately") end
end)

MissionRE.OnClientEvent:Connect(function(kind,data)
    if kind=="START" then
        missionTitle.Text="DELIVER: "..data.Item
        missionInfo.Text="You already have the item. Follow the BLUE arrow and survive. Potential ₹"..data.Potential
        setTarget(data.Drop,Color3.fromRGB(40,240,120))
    elseif kind=="COMPLETE" then
        missionTitle.Text="DELIVERY COMPLETE ✓"
        missionInfo.Text="+₹"..data.Reward.." • +"..data.XP.." XP\nYou survived delivery #"..tostring(data.Count or "?").."."
        clearTarget() showToast("+₹"..data.Reward.." • DELIVERY COMPLETE")
    elseif kind=="FAILED" then
        missionTitle.Text="MISSION FAILED 💥"
        missionInfo.Text="Compensation ₹"..data.Compensation.." • go back to the vendor."
        clearTarget() showToast("YOU GOT WRECKED")
    end
end)

TrafficRE.OnClientEvent:Connect(function()
    local cam=workspace.CurrentCamera
    if not cam then return end
    local old=cam.FieldOfView cam.FieldOfView=96
    task.delay(.22,function() if cam then cam.FieldOfView=old end end)
end)

task.spawn(function()
    local world=workspace:WaitForChild("SIT_World",15)
    if world then task.wait(.6) applyZoneVisibility(currentRank) end
end)
