local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

-- Warm late-afternoon light. Lighting.Technology (Future) is set in the place file itself.
Lighting.ClockTime=16.8
Lighting.Brightness=2.35
Lighting.EnvironmentDiffuseScale=.55
Lighting.EnvironmentSpecularScale=.35
Lighting.ShadowSoftness=.65
Lighting.Ambient=Color3.fromRGB(76,66,58) -- darker interiors so the starter-room bulb reads as the light source
Lighting.OutdoorAmbient=Color3.fromRGB(125,112,98)
local oldAtmos=Lighting:FindFirstChild("SIT_Atmosphere") if oldAtmos then oldAtmos:Destroy() end
local atmosphere=Instance.new("Atmosphere") atmosphere.Name="SIT_Atmosphere" atmosphere.Density=.24 atmosphere.Offset=.15 atmosphere.Color=Color3.fromRGB(225,205,178) atmosphere.Decay=Color3.fromRGB(110,94,80) atmosphere.Glare=.08 atmosphere.Haze=1.35 atmosphere.Parent=Lighting
local oldCC=Lighting:FindFirstChild("SIT_Color") if oldCC then oldCC:Destroy() end
local cc=Instance.new("ColorCorrectionEffect") cc.Name="SIT_Color" cc.Brightness=.015 cc.Contrast=.13 cc.Saturation=.11 cc.TintColor=Color3.fromRGB(255,238,218) cc.Parent=Lighting
local oldBloom=Lighting:FindFirstChild("SIT_Bloom") if oldBloom then oldBloom:Destroy() end
local bloom=Instance.new("BloomEffect") bloom.Name="SIT_Bloom" bloom.Intensity=.22 bloom.Size=16 bloom.Threshold=1.55 bloom.Parent=Lighting

local Store = nil
local dataStoreEnabled = false
pcall(function()
    Store = DataStoreService:GetDataStore(Config.DataStoreName)
end)

local oldRemotes = ReplicatedStorage:FindFirstChild("SIT_Remotes")
if oldRemotes then oldRemotes:Destroy() end
local Remotes = Instance.new("Folder") Remotes.Name = "SIT_Remotes" Remotes.Parent = ReplicatedStorage
local function remote(name)
    local r = Instance.new("RemoteEvent") r.Name=name r.Parent=Remotes return r
end
local MissionRE=remote("Mission")
local UIRE=remote("UI")
local ActionRE=remote("Action")
local TrafficRE=remote("TrafficHit")

local remoteCooldowns = {}
local function allowAction(plr, key, cooldown)
    remoteCooldowns[plr] = remoteCooldowns[plr] or {}
    local now = os.clock()
    local last = remoteCooldowns[plr][key] or 0
    if now-last < (cooldown or .15) then return false end
    remoteCooldowns[plr][key] = now
    return true
end

local function ownsPass(plr, passId)
    if not passId or passId==0 then return false end
    local ok,res=pcall(function() return MarketplaceService:UserOwnsGamePassAsync(plr.UserId,passId) end)
    return ok and res or false
end

local profiles, activeMissions = {}, {}
local vehicleVisuals = {}
local sessionStarts, sessionClaimIndex = {}, {}
local zoneCenters=Config.World.ZoneCenters
local zoneNames=Config.World.ZoneNames
local dropParts = {}
local homeSpawns = {}

local function newProfile()
    return {Cash=0,XP=0,Rank=1,Rebirths=0,Vehicle="Feet",OwnedVehicles={Feet=true},Businesses={},
        LastDaily=0,DailyStreak=0,LastHourly=0,HourlyClaims=0,LastMonthly=0,Scrap=0,Tokens=0,VehicleSkins={},ActiveSkin=nil,TotalDeliveries=0,BestCash=0,
        NPCUnlocks={Mechanic=false,Broker=false},VendorSeen={},Passes={}}
end
local function mergeProfile(saved)
    local p=newProfile()
    if type(saved)=="table" then for k,v in pairs(saved) do p[k]=v end end
    p.OwnedVehicles=type(p.OwnedVehicles)=="table" and p.OwnedVehicles or {Feet=true}
    p.Businesses=type(p.Businesses)=="table" and p.Businesses or {}
    p.NPCUnlocks=type(p.NPCUnlocks)=="table" and p.NPCUnlocks or {Mechanic=false,Broker=false}
    p.VendorSeen=type(p.VendorSeen)=="table" and p.VendorSeen or {}
    p.VehicleSkins=type(p.VehicleSkins)=="table" and p.VehicleSkins or {}
    p.Passes=type(p.Passes)=="table" and p.Passes or {}
    p.Scrap=tonumber(p.Scrap) or 0 p.Tokens=tonumber(p.Tokens) or 0
    p.Debt=math.max(0,tonumber(p.Debt) or 0)
    if Config.TestMode.Enabled and type(saved)~="table" then p.Cash=math.max(p.Cash,Config.TestMode.StartCash or 0) end
    return p
end
local function save(plr)
    local p=profiles[plr] if not p or not Store or not dataStoreEnabled then return end
    pcall(function() Store:SetAsync("u_"..plr.UserId,p) end)
end
local function rankData(p) return Config.Ranks[p.Rank] or Config.Ranks[1] end
local suffixes={"","K","M","B","T","Qa","Qi","Sx","Sp","Oc","No","Dc"}
local function fmt(n)
    n=tonumber(n) or 0 local i=1
    while math.abs(n)>=1000 and i<#suffixes do n=n/1000 i=i+1 end
    return i==1 and tostring(math.floor(n)) or string.format("%.2f%s",n,suffixes[i])
end
local sync

local function rewardText(r)
    local bits={}
    if (r.Cash or 0)>0 then table.insert(bits,"₹"..fmt(r.Cash)) end
    if (r.Scrap or 0)>0 then table.insert(bits,"🔩 "..r.Scrap.." scrap") end
    if (r.Tokens or 0)>0 then table.insert(bits,"🎟 "..r.Tokens.." tokens") end
    if r.Skin then table.insert(bits,"🎨 "..r.Skin.." skin") end
    return table.concat(bits," + ")
end
local function grantReward(plr,r,label)
    local p=profiles[plr] if not p or not r then return end
    p.Cash+=(r.Cash or 0) p.Scrap+=(r.Scrap or 0) p.Tokens+=(r.Tokens or 0)
    if r.Skin then p.VehicleSkins[r.Skin]={Vehicle=r.Vehicle or "Any",Unlocked=os.time()} p.ActiveSkin=r.Skin end
    p.BestCash=math.max(p.BestCash or 0,p.Cash)
    sync(plr,(label or "Reward").." • "..rewardText(r))
end

sync = function(plr,toast)
    local p=profiles[plr] if not p then return end
    local nextRank=Config.Ranks[p.Rank+1]
    local promotionReady=false
    if nextRank then
        promotionReady=(p.Cash>=nextRank.Price) and (p.XP>=nextRank.XP) and (p.TotalDeliveries>=(nextRank.Deliveries or 0)) and (p.Rebirths>=(nextRank.RebirthsRequired or 0))
    end
    local now=os.time()
    local dailyWait=math.max(0,20*3600-(now-(p.LastDaily or 0)))
    local sessionIndex=sessionClaimIndex[plr] or 0
    local nextSession=sessionIndex+1
    local sessionElapsed=math.max(0,now-(sessionStarts[plr] or now))
    local sessionMinutes=Config.SessionRewardMinutes[nextSession]
    local sessionWait=sessionMinutes and math.max(0,sessionMinutes*60-sessionElapsed) or 0
    local monthlyReady=(p.DailyStreak or 0)>=30
    UIRE:FireClient(plr,"SYNC",{Cash=p.Cash,XP=p.XP,Rank=p.Rank,RankName=rankData(p).Name,Rebirths=p.Rebirths,
        Vehicle=p.Vehicle,Businesses=p.Businesses,TotalDeliveries=p.TotalDeliveries,Toast=toast,NPCUnlocks=p.NPCUnlocks,PromotionReady=promotionReady,
        Scrap=p.Scrap,Tokens=p.Tokens,Skins=p.VehicleSkins,ActiveSkin=p.ActiveSkin,DailyStreak=p.DailyStreak,DailyWait=dailyWait,
        SessionStep=nextSession,SessionMinutes=sessionMinutes,SessionWait=sessionWait,SessionDone=(sessionMinutes==nil),MonthlyReady=monthlyReady,MonthlyDaysRemaining=math.max(0,30-(p.DailyStreak or 0)),
        VendorSeen=p.VendorSeen,OwnedVehicles=p.OwnedVehicles,Debt=p.Debt or 0,Passes=p.Passes,NextRank=nextRank and {Name=nextRank.Name,XP=nextRank.XP,Price=nextRank.Price,Deliveries=nextRank.Deliveries} or nil})
end
local function addCash(plr,amount,reason)
    local p=profiles[plr] if not p then return end
    local mult=(p.Passes and p.Passes.DoubleCash) and 2 or 1
    amount=amount*mult
    p.Cash += math.max(0,math.floor(amount)) p.BestCash=math.max(p.BestCash or 0,p.Cash)
    sync(plr,reason and ("+₹"..fmt(amount).." • "..reason) or nil)
end
local function addXP(plr,amount)
    local p=profiles[plr] if not p then return end
    if p.Passes and p.Passes.DoubleXP then amount=amount*2 end
    p.XP+=math.max(0,math.floor(amount)) sync(plr)
end
local function billboard(base,text,w,h,offset)
    local bb=Instance.new("BillboardGui") bb.Size=UDim2.fromOffset(w or 260,h or 70) bb.StudsOffset=offset or Vector3.new(0,4,0) bb.AlwaysOnTop=true bb.MaxDistance=28 bb.Parent=base
    local l=Instance.new("TextLabel") l.Size=UDim2.fromScale(1,1) l.BackgroundTransparency=.18 l.BackgroundColor3=Color3.fromRGB(10,10,10)
    l.TextColor3=Color3.new(1,1,1) l.TextScaled=true l.TextWrapped=true l.Font=Enum.Font.GothamBold l.Text=text l.Parent=bb return l
end

-- =====================================================================
-- WORLD (V26): one sealed, compact block per district. See WorldBuilder.
-- =====================================================================
local WorldBuilder = require(script:WaitForChild("WorldBuilder"))
local TrafficServer = require(script:WaitForChild("TrafficServer"))
local PlayerLook = require(script:WaitForChild("PlayerLook"))
local VehicleFactory = require(ReplicatedStorage.Shared:WaitForChild("VehicleFactory"))
local TrafficSim = require(ReplicatedStorage.Shared:WaitForChild("TrafficSim"))

local layout = WorldBuilder.build(Config, VehicleFactory)
local World = layout.World
for z, info in ipairs(layout.zones) do
    dropParts[z] = info.drops
    homeSpawns[z] = info.homeSpawn
end

-- The place's SpawnLocation sits invisibly inside the starter room, facing the open front,
-- so the very first frame a new player sees is the room and the street beyond it.
local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
if not spawnLocation then
    spawnLocation = Instance.new("SpawnLocation") spawnLocation.Name = "SpawnLocation" spawnLocation.Parent = workspace
end
spawnLocation.Anchored = true
spawnLocation.Size = Vector3.new(4, 0.2, 4)
spawnLocation.CFrame = CFrame.lookAt(Vector3.new(homeSpawns[1].Position.X, 0.95, homeSpawns[1].Position.Z), Vector3.new(homeSpawns[1].Position.X + 10, 0.95, homeSpawns[1].Position.Z))
spawnLocation.Transparency = 1
spawnLocation.CanCollide = false
spawnLocation.CanQuery = false
spawnLocation.Neutral = true
spawnLocation.Duration = 0
for _, d in ipairs(spawnLocation:GetChildren()) do if d:IsA("Decal") then d:Destroy() end end

-- Slow mud patches (one Touched connection per patch, only a handful exist).
local slowedPlayers={}
for _, info in ipairs(layout.zones) do
    for _, hz in ipairs(info.hazards) do
        hz.Touched:Connect(function(hit)
            local char=hit:FindFirstAncestorOfClass("Model")
            local plr=char and Players:GetPlayerFromCharacter(char)
            if not plr or slowedPlayers[plr] then return end
            local hum=char and char:FindFirstChildOfClass("Humanoid")
            local p=profiles[plr]
            if not hum or not p then return end
            slowedPlayers[plr]=true
            local normal=(Config.Vehicles[p.Vehicle] or Config.Vehicles.Feet).Speed
            hum.WalkSpeed=math.max(8, math.floor(normal*0.72))
            UIRE:FireClient(plr,"TOAST","🐌 Thick mud slowed you down")
            task.delay(1.7,function()
                if plr.Parent and hum.Parent then hum.WalkSpeed=(Config.Vehicles[(profiles[plr] and profiles[plr].Vehicle) or "Feet"] or Config.Vehicles.Feet).Speed end
                slowedPlayers[plr]=nil
            end)
        end)
    end
end

local function zoneOfPlayer(plr)
    local char=plr.Character local root=char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local best,bd=nil,math.huge
    for z,cx in ipairs(zoneCenters) do local d=math.abs(root.Position.X-cx) if d<bd then best,bd=z,d end end
    if bd>110 then return nil end
    return best,root
end

local function teleportHome(plr,zoneIndex)
    local char=plr.Character local root=char and char:FindFirstChild("HumanoidRootPart")
    local spawnCF=homeSpawns[zoneIndex] or homeSpawns[1]
    plr:SetAttribute("HomeSpawn",spawnCF)
    if root then
        root.AssemblyLinearVelocity=Vector3.zero
        root.CFrame=spawnCF
    end
end

-- Rank 1 wears street rags with "LESS THAN NOTHING" overhead; later ranks show their rank name.
local function refreshLook(plr)
    local p=profiles[plr] local char=plr.Character
    if not p or not char then return end
    PlayerLook.apply(char,rankData(p),p.Rank,plr.DisplayName)
end

local rankGuards={}
local vendorModels={}

-- Blocky street NPC built around a CFrame (faces the CFrame's look direction).
-- NPC parts never collide, so they can never block the walkway.
local function makeNPC(name,cf,color,title,actionText,zoneIndex)
    local model=Instance.new("Model") model.Name=name model:SetAttribute("SITZone",zoneIndex) model.Parent=World
    local function np(pname,size,offset,col,shape)
        local p=Instance.new("Part") p.Name=pname p.Size=size p.CFrame=cf*CFrame.new(offset) p.Anchored=true p.Color=col
        p.Material=Enum.Material.SmoothPlastic p.TopSurface=Enum.SurfaceType.Smooth p.BottomSurface=Enum.SurfaceType.Smooth
        p.CanCollide=false p.CanTouch=false p.CanQuery=false
        if shape then p.Shape=shape end
        p.Parent=model return p
    end
    local skin=Color3.fromRGB(160,112,78)
    local torso=np("Torso",Vector3.new(2.6,3.0,1.5),Vector3.new(0,3.9,0),color)
    np("Hips",Vector3.new(2.3,1.0,1.4),Vector3.new(0,2.0,0),Color3.fromRGB(58,58,64))
    np("LegL",Vector3.new(0.8,2.0,0.9),Vector3.new(-0.6,1.0,0),Color3.fromRGB(46,42,40))
    np("LegR",Vector3.new(0.8,2.0,0.9),Vector3.new(0.6,1.0,0),Color3.fromRGB(46,42,40))
    np("ArmL",Vector3.new(0.6,2.6,0.7),Vector3.new(-1.65,3.8,0),skin)
    np("ArmR",Vector3.new(0.6,2.6,0.7),Vector3.new(1.65,3.8,0),skin)
    local head=np("Head",Vector3.new(1.9,1.9,1.9),Vector3.new(0,6.4,0),skin,Enum.PartType.Ball)
    local face=Instance.new("Decal") face.Name="Face" face.Texture="rbxasset://textures/face.png" face.Face=Enum.NormalId.Front face.Parent=head
    np("Hair",Vector3.new(1.95,0.6,1.95),Vector3.new(0,7.15,0.05),Color3.fromRGB(34,24,18))
    billboard(head,title,260,65,Vector3.new(0,2.4,0))
    local prompt=Instance.new("ProximityPrompt") prompt.ActionText=actionText prompt.ObjectText=title prompt.HoldDuration=.2 prompt.MaxActivationDistance=13 prompt.RequiresLineOfSight=false prompt.Parent=torso
    return model,prompt,torso
end

-- One delivery vendor per district, standing where the home alley meets the street.
local vendorTitles={"📦 Raju — Delivery Jobs","📦 Market Vendor","🍔 Delivery Dispatcher","💻 Business Courier","💎 VIP Fixer"}
local vendorColors={Color3.fromRGB(113,77,47),Color3.fromRGB(115,91,52),Color3.fromRGB(52,103,126),Color3.fromRGB(62,76,110),Color3.fromRGB(105,76,28)}
for z,info in ipairs(layout.zones) do
    local model,prompt=makeNPC("VendorNPC_"..z,info.vendorCF,vendorColors[z],vendorTitles[z],"Ask for work",z)
    vendorModels[z]=model
    prompt.Triggered:Connect(function(plr)
        local p=profiles[plr] if not p then return end
        local currentZone=math.clamp(rankData(p).Zone,1,5)
        if currentZone~=z then UIRE:FireClient(plr,"TOAST","This vendor does not work with you yet.") return end
        local m=activeMissions[plr]
        if m and m.stage=="return" then UIRE:FireClient(plr,"TOAST","Raju: \"Come here, I'll count your cut.\"") return end
        if m then UIRE:FireClient(plr,"TOAST","Finish your current delivery first.") return end
        p.VendorSeen[z]=true
        local available={}
        for _,it in ipairs(Config.DeliveryItems[z] or {}) do
            if p.TotalDeliveries >= (it.MinDeliveries or 0) then table.insert(available,it) end
        end
        UIRE:FireClient(plr,"VENDOR_MENU",{Zone=z,Title=vendorTitles[z],Items=available})
    end)
end

-- Mechanic and broker live on the home-side sidewalk of every district, so upgrades
-- stay reachable after a rank-up. District 1 keeps the names the client guides point at.
for z,info in ipairs(layout.zones) do
    local mechName=(z==1) and "MechanicNPC" or ("MechanicNPC_Z"..z)
    local brokerName=(z==1) and "BrokerNPC" or ("BrokerNPC_Z"..z)
    local mechCF,brokerCF=info.mechanicCF,info.brokerCF
    if z>1 then
        -- Later districts use solid shop blocks, so these two stand on the sidewalk in front of them.
        mechCF=mechCF+Vector3.new(4.2,0,0) brokerCF=brokerCF+Vector3.new(4.2,0,0)
    end
    local _,mechanicPrompt=makeNPC(mechName,mechCF,Color3.fromRGB(42,92,130),"🔧 Jugaad Mechanic","Talk",z)
    mechanicPrompt.Triggered:Connect(function(plr)
        local p=profiles[plr] if not p then return end
        if p.TotalDeliveries < 1 then UIRE:FireClient(plr,"NPC",{Key="Locked",Title="🔧 Jugaad Mechanic",Text="Bring me proof you can survive one delivery first."}) return end
        p.NPCUnlocks.Mechanic=true
        UIRE:FireClient(plr,"NPC",{Key="Mechanic",Title="🔧 Jugaad Mechanic",Text="You survived. Good. A junk bicycle costs ₹350. Save up, then buy it if you want to cross faster."}) sync(plr)
    end)
    local _,brokerPrompt=makeNPC(brokerName,brokerCF,Color3.fromRGB(70,115,65),"💼 Street Broker","Talk",z)
    brokerPrompt.Triggered:Connect(function(plr)
        local p=profiles[plr] if not p then return end
        if p.TotalDeliveries < 4 then UIRE:FireClient(plr,"NPC",{Key="Locked",Title="💼 Street Broker",Text="Come back after 4 deliveries. Then we can talk business."}) return end
        p.NPCUnlocks.Broker=true
        UIRE:FireClient(plr,"NPC",{Key="Broker",Title="💼 Street Broker",Text="Now you look useful. A tea stall costs ₹1200 and pays slowly while you keep delivering."}) sync(plr)
    end)
end

-- Promotion guards stand at the closed gate on the FAR side of the road,
-- so even ranking up means crossing traffic one more time.
local guardColors={Color3.fromRGB(90,125,165),Color3.fromRGB(88,105,145),Color3.fromRGB(80,80,92),Color3.fromRGB(45,45,50)}
for z=1,4 do
    local info=layout.zones[z]
    local guard,prompt=makeNPC("GuardNPC_"..z,info.guardCF,guardColors[z],"🛑 "..Config.Ranks[z+1].Name,"Talk",z)
    rankGuards[z]=guard
    prompt.Triggered:Connect(function(plr)
        local p=profiles[plr] if not p then return end
        if p.Rank>z then UIRE:FireClient(plr,"TOAST","You already outrank this gate.") return end
        local nr=Config.Ranks[z+1]
        local ready=(p.Cash>=nr.Price) and (p.XP>=nr.XP) and (p.TotalDeliveries>=(nr.Deliveries or 0)) and (p.Rebirths>=(nr.RebirthsRequired or 0))
        if ready then
            UIRE:FireClient(plr,"RANK_OFFER",{Name=nr.Name,Price=nr.Price,XP=nr.XP,Deliveries=nr.Deliveries,CurrentXP=p.XP,CurrentCash=p.Cash,CurrentDeliveries=p.TotalDeliveries})
        else
            UIRE:FireClient(plr,"GUARD_BLOCK",{Title="🛑 "..nr.Name,Text="Not yet. Go make deliveries, then come back when you have earned your place."})
        end
    end)
end

-- =====================================================================
-- TRAFFIC (V26): server simulates numbers only; clients render + detect hits.
-- =====================================================================
local hitCooldown={}
local function onTrafficHit(plr)
    local now=os.clock()
    if hitCooldown[plr] and now-hitCooldown[plr]<2 then return end
    hitCooldown[plr]=now
    local char=plr.Character
    local mission=activeMissions[plr]
    local p0=profiles[plr]
    if mission and p0 and mission.stage=="drop" then
        -- The parcel is smashed: the vendor wants it paid back.
        local debt=Config.TestMode.Enabled and 0 or math.floor((mission.potential or 0)*Config.Delivery.BrokenDebtPct)
        p0.Debt=(p0.Debt or 0)+debt
        activeMissions[plr]=nil
        if mission.customer then mission.customer:Destroy() mission.customer=nil end
        MissionRE:FireClient(plr,"BROKEN",{Item=mission.item,Debt=debt,TotalDebt=p0.Debt})
        sync(plr)
    elseif mission and mission.stage=="return" then
        UIRE:FireClient(plr,"TOAST","💥 Knocked down. Raju still owes you: walk back to him.")
    end
    local root=char and char:FindFirstChild("HumanoidRootPart")
    if root then
        root.AssemblyLinearVelocity=Vector3.zero
        task.delay(.35,function()
            if not plr.Parent or not char.Parent then return end
            local p=profiles[plr] local hum=char:FindFirstChildOfClass("Humanoid")
            if p then
                teleportHome(plr,math.clamp(rankData(p).Zone,1,5))
                if hum then hum.Health=hum.MaxHealth end
                if not activeMissions[plr] then UIRE:FireClient(plr,"TOAST","💥 Flattened. Back to your room.") end
            end
        end)
    end
end

TrafficServer.start({
    Config=Config,
    TrafficSim=TrafficSim,
    Remotes=Remotes,
    HitRemote=TrafficRE,
    zoneOfPlayer=zoneOfPlayer,
    onHit=onTrafficHit,
})


local function clearVehicleVisual(plr)
    if vehicleVisuals[plr] then vehicleVisuals[plr]:Destroy() vehicleVisuals[plr]=nil end
end
local function weldPart(model,root,size,offset,color,shape)
    local p=Instance.new("Part") p.Size=size p.Color=color p.Material=Enum.Material.Metal p.CanCollide=false p.CanTouch=false p.CanQuery=false p.Massless=true p.Anchored=false p.Shape=shape or Enum.PartType.Block p.CFrame=root.CFrame*offset p.Parent=model
    local w=Instance.new("WeldConstraint") w.Part0=root w.Part1=p w.Parent=p return p
end
-- Welded part between two points in the root's local space (bike tubes).
local function weldTube(model,root,a,b,thick,color,material)
    local p=Instance.new("Part") p.Size=Vector3.new(thick,thick,(b-a).Magnitude) p.Color=color p.Material=material or Enum.Material.Metal
    p.CanCollide=false p.CanTouch=false p.CanQuery=false p.Massless=true p.Anchored=false p.CastShadow=false
    p.CFrame=root.CFrame*CFrame.lookAt((a+b)/2,b) p.Parent=model
    local w=Instance.new("WeldConstraint") w.Part0=root w.Part1=p w.Parent=p return p
end

-- Rusty Indian delivery bicycle welded under the rider (visible to everyone). Built in the
-- root part's space: forward is -Z, the ground is `g` below the root. BikeRider.client.lua
-- poses the legs/arms so the player pedals instead of walking.
local function buildBicycle(m,root,char)
    local hum=char:FindFirstChildOfClass("Humanoid")
    local g=-((hum and hum.HipHeight or 2)+root.Size.Y/2)
    local frame=Color3.fromRGB(48,78,60) local chrome=Color3.fromRGB(170,170,175) local black=Color3.fromRGB(22,22,22)
    local V=Vector3.new
    for _,wz in ipairs({1.9,-2.0}) do
        local tyre=weldPart(m,root,V(0.3,2.5,2.5),CFrame.new(0,g+1.25,wz),black,Enum.PartType.Cylinder) tyre.Material=Enum.Material.Rubber tyre.Name="Tyre"
        local rim=weldPart(m,root,V(0.34,2.0,2.0),CFrame.new(0,g+1.25,wz),chrome,Enum.PartType.Cylinder) rim.Name="Rim"
        weldPart(m,root,V(0.4,0.5,0.5),CFrame.new(0,g+1.25,wz),Color3.fromRGB(60,60,64),Enum.PartType.Cylinder).Name="Hub"
    end
    local A=V(0,g+1.25,1.9) local B=V(0,g+0.95,0.15) local S=V(0,-1.35,0.4) local H=V(0,-0.1,-1.5) local F=V(0,g+1.25,-2.0)
    weldTube(m,root,B,S,0.24,frame,Enum.Material.CorrodedMetal) weldTube(m,root,B,H,0.26,frame,Enum.Material.CorrodedMetal)
    weldTube(m,root,S,H,0.22,frame,Enum.Material.CorrodedMetal) weldTube(m,root,B,A,0.16,frame,Enum.Material.CorrodedMetal)
    weldTube(m,root,S,A,0.16,frame,Enum.Material.CorrodedMetal) weldTube(m,root,H,F,0.18,chrome)
    weldTube(m,root,H,V(0,0.25,-1.72),0.18,chrome)
    weldPart(m,root,V(2.1,0.18,0.18),CFrame.new(0,0.28,-1.75),black).Name="Handlebar"
    weldPart(m,root,V(0.65,0.22,1.15),CFrame.new(0,-1.18,0.45),Color3.fromRGB(40,30,24)).Name="Saddle"
    weldPart(m,root,V(1.3,0.12,0.14),CFrame.new(0,g+0.95,0.15),chrome).Name="Crank"
    weldPart(m,root,V(0.5,0.1,0.35),CFrame.new(0.75,g+0.95,-0.1),black).Name="Pedal"
    weldPart(m,root,V(0.5,0.1,0.35),CFrame.new(-0.75,g+0.95,0.4),black).Name="Pedal"
    -- Delivery gear: rear carrier with a strapped parcel, wire basket up front.
    weldPart(m,root,V(1.0,0.12,1.7),CFrame.new(0,g+2.7,1.75),chrome).Name="Carrier"
    local box=weldPart(m,root,V(1.2,0.9,1.2),CFrame.new(0,g+3.22,1.75),Color3.fromRGB(160,120,76)) box.Material=Enum.Material.Cardboard box.Name="Parcel"
    local basket=weldPart(m,root,V(1.3,0.8,1.0),CFrame.new(0,-0.35,-2.35),Color3.fromRGB(110,90,60)) basket.Material=Enum.Material.Fabric basket.Name="Basket"
    weldPart(m,root,V(0.35,0.3,0.2),CFrame.new(0,-0.05,-2.55),Color3.fromRGB(255,236,190)).Material=Enum.Material.Neon
end

local function applyMovement(plr)
    local p=profiles[plr] local hum=plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
    if not p or not hum then return end
    local v=Config.Vehicles[p.Vehicle] or Config.Vehicles.Feet
    hum.WalkSpeed=v.Speed
    hum.UseJumpPower=true
    hum.JumpPower=v.Jump or 50
end

local function applyVehicleVisual(plr)
    clearVehicleVisual(plr) local p=profiles[plr] local char=plr.Character if not p or not char or p.Vehicle=="Feet" then return end
    local root=char:FindFirstChild("HumanoidRootPart") if not root then return end
    local m=Instance.new("Model") m.Name="Ride_"..p.Vehicle m.Parent=char vehicleVisuals[plr]=m
    if p.Vehicle=="Bicycle" then
        buildBicycle(m,root,char)
    elseif p.Vehicle=="Hoverboard" then
        weldPart(m,root,Vector3.new(4,.35,1.6),CFrame.new(0,-2.7,.1),Color3.fromRGB(35,185,240))
    elseif p.Vehicle=="Rusty Scooter" then
        weldPart(m,root,Vector3.new(2,.6,5),CFrame.new(0,-2.2,.2),(p.ActiveSkin=="Blue Smoke") and Color3.fromRGB(45,125,220) or Color3.fromRGB(125,72,45))
        weldPart(m,root,Vector3.new(.4,3,.4),CFrame.new(0,-.9,-1.8),Color3.fromRGB(50,50,50))
    elseif p.Vehicle=="Tuk-Tuk" then
        weldPart(m,root,Vector3.new(6,3,7),CFrame.new(0,-.7,1.0),Color3.fromRGB(40,145,85))
        weldPart(m,root,Vector3.new(6.5,.35,7.3),CFrame.new(0,1.05,1.0),Color3.fromRGB(235,185,40))
    elseif p.Vehicle=="SUV" or p.Vehicle=="Mega 4x4" then
        local s=p.Vehicle=="Mega 4x4" and 1.25 or 1
        weldPart(m,root,Vector3.new(7*s,2.4*s,10*s),CFrame.new(0,-.5,1.2),(p.ActiveSkin=="Royal Chrome" and p.Vehicle=="Mega 4x4") and Color3.fromRGB(210,215,220) or (p.Vehicle=="Mega 4x4" and Color3.fromRGB(20,20,20) or Color3.fromRGB(90,90,105)))
        weldPart(m,root,Vector3.new(6.2*s,2.2*s,5*s),CFrame.new(0,1.1,1.0),Color3.fromRGB(35,45,55))
    end
end

local function businessIncome(p) local t=0 for _,b in ipairs(Config.Businesses) do if p.Businesses[b.Id] then t+=b.Income end end return t end
task.spawn(function() while true do task.wait(10) for plr,p in pairs(profiles) do local inc=businessIncome(p) if inc>0 then addCash(plr,inc*10,"passive businesses") end end end end)

local promote -- defined with the rank code below

-- Rich customers: they take the parcel, sneer, and never pay. Fictional wealth/status only.
local CUSTOMERS={
    {Title="💰 Rich Customer",Shirt=Color3.fromRGB(236,236,230)},
    {Title="🕶 Snobby Landlord",Shirt=Color3.fromRGB(60,64,90)},
    {Title="👑 Spoiled Rich Kid",Shirt=Color3.fromRGB(200,40,60)},
    {Title="💎 Posh Aunty",Shirt=Color3.fromRGB(170,60,140)},
    {Title="🏦 Gold-Chain Uncle",Shirt=Color3.fromRGB(230,190,70)},
    {Title="📱 Impatient Boss",Shirt=Color3.fromRGB(40,40,44)},
}
local INSULTS={
    "Don't touch my gate with those filthy hands. Put it on the floor.",
    "You smell like the gutter. Stand further back.",
    "Late again. People like you never learn anything.",
    "Payment? Go beg your vendor. I don't hand money to street rats.",
    "Look at your clothes. Did you sleep in a drain?",
    "Tip? Be grateful I even opened the door for you.",
    "If this is scratched, I'll make sure you never work here again.",
    "Stop staring at my house and get lost.",
    "Ugh. Next time send someone presentable.",
    "Don't breathe on the parcel. Now go away.",
}

local function makeCustomer(cf,info,zoneIndex)
    local model=Instance.new("Model") model.Name="Customer" model:SetAttribute("SITZone",zoneIndex) model.Parent=World
    local function np(name,size,offset,col,shape,mat)
        local p=Instance.new("Part") p.Name=name p.Size=size p.CFrame=cf*CFrame.new(offset) p.Anchored=true p.Color=col
        p.Material=mat or Enum.Material.SmoothPlastic p.CanCollide=false p.CanTouch=false p.CanQuery=false
        if shape then p.Shape=shape end p.Parent=model return p
    end
    local skin=Color3.fromRGB(176,128,92)
    np("Torso",Vector3.new(2.6,3.0,1.5),Vector3.new(0,3.9,0),info.Shirt,nil,Enum.Material.Fabric)
    np("Belly",Vector3.new(2.4,1.2,1.1),Vector3.new(0,3.2,-0.6),info.Shirt,nil,Enum.Material.Fabric)
    np("Legs",Vector3.new(2.2,2.4,1.2),Vector3.new(0,1.2,0),Color3.fromRGB(230,226,214),nil,Enum.Material.Fabric)
    np("ArmL",Vector3.new(0.6,2.4,0.7),Vector3.new(-1.65,3.9,-0.2),info.Shirt,nil,Enum.Material.Fabric)
    np("ArmR",Vector3.new(0.6,2.4,0.7),Vector3.new(1.65,3.9,-0.2),info.Shirt,nil,Enum.Material.Fabric)
    local head=np("Head",Vector3.new(1.9,1.9,1.9),Vector3.new(0,6.4,0),skin,Enum.PartType.Ball)
    local face=Instance.new("Decal") face.Texture="rbxasset://textures/face.png" face.Face=Enum.NormalId.Front face.Parent=head
    np("Sunglasses",Vector3.new(1.7,0.35,0.2),Vector3.new(0,6.6,-0.9),Color3.fromRGB(15,15,15))
    np("GoldChain",Vector3.new(1.4,0.2,0.2),Vector3.new(0,4.9,-0.8),Color3.fromRGB(240,200,60),nil,Enum.Material.Neon)
    np("GoldWatch",Vector3.new(0.7,0.3,0.8),Vector3.new(1.65,3.0,-0.2),Color3.fromRGB(240,200,60),nil,Enum.Material.Metal)
    billboard(head,info.Title,240,52,Vector3.new(0,2.3,0))
    return model
end

local function startMission(plr,itemName)
    local p=profiles[plr] if not p or activeMissions[plr] then return end
    local z=math.clamp(rankData(p).Zone,1,5)
    local selected=nil
    for _,it in ipairs(Config.DeliveryItems[z] or {}) do if it.Name==itemName then selected=it break end end
    if not selected then UIRE:FireClient(plr,"TOAST","Talk to your district vendor and choose an item.") return end
    local b=math.random(1,#dropParts[z]) local dp=dropParts[z][b]
    local vendor=vendorModels[z] and vendorModels[z]:FindFirstChild("Torso")
    local dist=vendor and (vendor.Position-dp.Position).Magnitude or 150
    local base=math.max(p.Rank==1 and 55 or 18,math.floor((16+dist*.12)*rankData(p).Mult*(selected.Mult or 1)*(1+p.Rebirths*.08)*((p.Passes and p.Passes.VIPContracts) and 1.20 or 1)))
    -- The customer waits at their door, just behind the far sidewalk.
    local info=CUSTOMERS[math.random(1,#CUSTOMERS)]
    local doorPos=Vector3.new(zoneCenters[z]+Config.World.SidewalkOuter+2.2,0.8,dp.Position.Z)
    local customer=makeCustomer(CFrame.lookAt(doorPos,doorPos-Vector3.new(1,0,0)),info,z)
    activeMissions[plr]={stage="drop",zone=z,drop=dp,potential=base,traveled=0,lastPos=nil,item=selected.Name,customer=customer,customerTitle=info.Title}
    MissionRE:FireClient(plr,"START",{Drop=dp,Item=selected.Name,Potential=base,Customer=info.Title,Share=Config.Delivery.PlayerShare})
end

local function removeCustomer(m,delay)
    local c=m and m.customer
    if not c then return end
    m.customer=nil
    if delay then task.delay(delay,function() if c.Parent then c:Destroy() end end) else c:Destroy() end
end

local function payAtVendor(plr,m)
    local p=profiles[plr]
    local bonus=math.floor(m.traveled*.018*rankData(p).Mult)
    local share=Config.TestMode.Enabled and 1 or Config.Delivery.PlayerShare
    local gross=math.floor(m.potential*share)+bonus
    local repay=math.min(p.Debt or 0,math.floor(gross*Config.Delivery.DebtRepayPct))
    p.Debt=(p.Debt or 0)-repay
    local net=gross-repay
    local xp=28
    p.TotalDeliveries+=1 activeMissions[plr]=nil
    if net>0 then addCash(plr,net,"Raju paid you") else sync(plr,"Raju kept everything for your debt") end
    addXP(plr,xp)
    MissionRE:FireClient(plr,"COMPLETE",{Reward=net,Gross=gross,OrderValue=m.potential,DebtPaid=repay,Debt=p.Debt,XP=xp,Count=p.TotalDeliveries})
    if p.TotalDeliveries==1 then UIRE:FireClient(plr,"MILESTONE",{Title="FIRST DELIVERY!",Text="Buy a bicycle • go see the mechanic",Icon="🚲"})
    elseif p.TotalDeliveries==2 then UIRE:FireClient(plr,"MILESTONE",{Title="NEW CARGO",Text="Questionable Lunch contracts are now available",Icon="📦"})
    elseif p.TotalDeliveries==4 then UIRE:FireClient(plr,"MILESTONE",{Title="BUSINESS UNLOCKED",Text="The Street Broker will finally talk to you",Icon="💼"})
    elseif p.TotalDeliveries==5 then UIRE:FireClient(plr,"MILESTONE",{Title="RISKIER CARGO",Text="Cheap Parcel contracts now pay more",Icon="⚠️"})
    elseif p.TotalDeliveries==8 then UIRE:FireClient(plr,"MILESTONE",{Title="YOU'RE GETTING CLOSE",Text="4 more deliveries until the next district",Icon="🔥"}) end
    -- Test mode: every paid delivery is an instant, free promotion to the next rank.
    if Config.TestMode.Enabled and Config.TestMode.RankUpEveryDelivery and Config.Ranks[p.Rank+1] then
        task.delay(1.2,function() if plr.Parent and profiles[plr]==p and Config.Ranks[p.Rank+1] then promote(plr,true) end end)
    end
end

RunService.Heartbeat:Connect(function()
    for plr,m in pairs(activeMissions) do
        local root=plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
        if root then
            if m.lastPos then m.traveled+=math.min((root.Position-m.lastPos).Magnitude,12) end m.lastPos=root.Position
            if m.stage=="drop" and (root.Position-m.drop.Position).Magnitude<9 then
                -- Delivered, but the customer refuses to pay: back across the road to the vendor.
                m.stage="return"
                local vendor=vendorModels[m.zone] and vendorModels[m.zone]:FindFirstChild("Torso")
                m.vendor=vendor
                MissionRE:FireClient(plr,"DELIVERED",{Customer=m.customerTitle,Line=INSULTS[math.random(1,#INSULTS)],Vendor=vendor,
                    Expected=math.floor(m.potential*Config.Delivery.PlayerShare),OrderValue=m.potential})
                removeCustomer(m,6)
            elseif m.stage=="return" and m.vendor and ((root.Position-m.vendor.Position)*Vector3.new(1,0,1)).Magnitude<11 then
                payAtVendor(plr,m)
            end
        end
    end
end)

promote=function(plr,free)
    local p=profiles[plr] if not p then return end local nr=Config.Ranks[p.Rank+1]
    if not nr then return end
    if not free then p.Cash-=nr.Price end
    p.Rank+=1 p.Vehicle=nr.Vehicle p.OwnedVehicles[nr.Vehicle]=true applyVehicleVisual(plr)
    applyMovement(plr)
    sync(plr,"RANK UP → "..nr.Name) refreshLook(plr)
    -- Districts are sealed blocks, so a promotion moves the player into the next one.
    local newZone=math.clamp(nr.Zone,1,5)
    task.delay(.6,function()
        if not plr.Parent then return end
        teleportHome(plr,newZone)
        UIRE:FireClient(plr,"MILESTONE",{Title="WELCOME TO "..zoneNames[newZone],Text="You are now a "..nr.Name..". Find this district's vendor.",Icon="🏙"})
    end)
end

local function tryRankUp(plr)
    local p=profiles[plr] if not p then return end local nr=Config.Ranks[p.Rank+1]
    if not nr then sync(plr,"Already max rank") return end
    if (nr.RebirthsRequired or 0)>p.Rebirths then sync(plr,"Need "..nr.RebirthsRequired.." rebirths") return end
    if p.TotalDeliveries<(nr.Deliveries or 0) then sync(plr,"Need "..nr.Deliveries.." total deliveries") return end
    if p.XP<nr.XP then sync(plr,"Need "..nr.XP.." XP") return end
    if p.Cash<nr.Price then sync(plr,"Need ₹"..fmt(nr.Price)) return end
    promote(plr,false)
end

ActionRE.OnServerEvent:Connect(function(plr,action,arg)
    if not allowAction(plr,tostring(action),.12) then return end
    local p=profiles[plr] if not p then return end
    if action=="START_ITEM_MISSION" then startMission(plr,arg)
    elseif action=="TRY_RANK_UP" then tryRankUp(plr)
    elseif action=="BUY_VEHICLE" and Config.Vehicles[arg] then
        if not p.NPCUnlocks.Mechanic then sync(plr,"Find the mechanic first") return end
        local v=Config.Vehicles[arg]
        if p.OwnedVehicles[arg] then
            p.Vehicle=arg
        else
            if p.Cash<v.Price then sync(plr,"Not enough cash") return end
            p.Cash-=v.Price p.OwnedVehicles[arg]=true p.Vehicle=arg
        end
        applyMovement(plr) applyVehicleVisual(plr) sync(plr,"Equipped "..arg)
    elseif action=="BUY_BUSINESS" then
        if not p.NPCUnlocks.Broker then sync(plr,"Find the street broker first") return end
        for _,b in ipairs(Config.Businesses) do if b.Id==arg and not p.Businesses[b.Id] then
            if p.Rank<(b.RequiredRank or 1) then sync(plr,"Need rank "..b.RequiredRank) return end
            if p.Cash<b.Price then sync(plr,"Not enough cash") return end p.Cash-=b.Price p.Businesses[b.Id]=true sync(plr,"Bought "..b.Name) return
        end end
    elseif action=="REBIRTH" then
        if p.Rank<#Config.Ranks-1 then sync(plr,"Reach Business Boss first") return end local cost=1000000*(3^p.Rebirths)
        if p.Cash<cost then sync(plr,"Need ₹"..fmt(cost)) return end p.Rebirths+=1 p.Cash=0 p.XP=0 p.Rank=1 p.Vehicle="Feet" p.OwnedVehicles={Feet=true} p.Businesses={} p.TotalDeliveries=0 p.Debt=0 activeMissions[plr]=nil clearVehicleVisual(plr) applyMovement(plr) sync(plr,"REBIRTH #"..p.Rebirths) teleportHome(plr,1) refreshLook(plr)

    elseif action=="OPEN_LOOTBOX" then
        if (p.Tokens or 0)<3 then sync(plr,"Need 3 tokens for a lootbox") return end
        p.Tokens-=3
        local total=0 for _,e in ipairs(Config.Lootbox) do total+=e.Weight end
        local roll=math.random()*total local picked=Config.Lootbox[1] local acc=0
        for _,e in ipairs(Config.Lootbox) do acc+=e.Weight if roll<=acc then picked=e break end end
        if picked.Kind=="Cash" or picked.Kind=="Jackpot" then addCash(plr,picked.Amount,"lootbox")
        elseif picked.Kind=="XP" then addXP(plr,picked.Amount) sync(plr,"+"..picked.Amount.." XP • lootbox") end
    elseif action=="CLAIM_DAILY" then
        local now=os.time() local elapsed=now-(p.LastDaily or 0)
        if (p.DailyStreak or 0)>=30 then sync(plr,"30/30 days complete — claim the monthly chest first") return end
        if elapsed<20*3600 then sync(plr,"Daily reward is not ready yet") return end
        p.DailyStreak=(elapsed<48*3600) and math.clamp((p.DailyStreak or 0)+1,1,30) or 1
        p.LastDaily=now
        grantReward(plr,Config.DailyReward[p.DailyStreak],"DAY "..p.DailyStreak.." / 30 CLAIMED")
    elseif action=="CLAIM_HOURLY" then
        local idx=(sessionClaimIndex[plr] or 0)+1
        local minutes=Config.SessionRewardMinutes[idx]
        if not minutes then sync(plr,"All 60-minute session rewards claimed") return end
        local elapsed=os.time()-(sessionStarts[plr] or os.time())
        if elapsed<minutes*60 then sync(plr,"Stay in game until "..minutes.." minutes") return end
        sessionClaimIndex[plr]=idx
        grantReward(plr,Config.SessionRewards[idx],minutes.." MIN SESSION REWARD")
    elseif action=="CLAIM_MONTHLY" then
        if (p.DailyStreak or 0)<30 then sync(plr,"Monthly chest unlocks after 30 consecutive daily claims") return end
        p.LastMonthly=os.time()
        p.DailyStreak=0
        grantReward(plr,Config.MonthlyReward,"30-DAY CHEST")
    end
end)

local productMap={}
for key,id in pairs(Config.Monetization.Products) do if id and id~=0 then productMap[id]=key end end
MarketplaceService.ProcessReceipt=function(receiptInfo)
    local plr=Players:GetPlayerByUserId(receiptInfo.PlayerId)
    if not plr then return Enum.ProductPurchaseDecision.NotProcessedYet end
    local p=profiles[plr] if not p then return Enum.ProductPurchaseDecision.NotProcessedYet end
    local kind=productMap[receiptInfo.ProductId]
    if not kind then return Enum.ProductPurchaseDecision.PurchaseGranted end
    if kind=="CashSmall" then addCash(plr,10000,"Robux pack")
    elseif kind=="CashBig" then addCash(plr,250000,"Robux pack")
    elseif kind=="Lootbox" then p.Tokens=(p.Tokens or 0)+3 sync(plr,"+3 tokens • premium lootbox")
    elseif kind=="InstantBusiness" then
        for _,b in ipairs(Config.Businesses) do if not p.Businesses[b.Id] and p.Rank>=(b.RequiredRank or 1) then p.Businesses[b.Id]=true sync(plr,"Unlocked "..b.Name) break end end
    end
    return Enum.ProductPurchaseDecision.PurchaseGranted
end

local currentMaster=nil
local function updateMaster()
    local best,score=nil,-1
    for plr,p in pairs(profiles) do local s=(p.Rank or 1)*1e15+(p.Rebirths or 0)*1e12+(p.BestCash or p.Cash or 0) if s>score then best,score=plr,s end end
    if best~=currentMaster then currentMaster=best for plr in pairs(profiles) do UIRE:FireClient(plr,"MASTER",best and best.DisplayName or "Nobody") end end
end
task.spawn(function() while true do task.wait(3) updateMaster() end end)

Players.PlayerAdded:Connect(function(plr)
    local saved=nil
    if Store then local ok,res=pcall(function() return Store:GetAsync("u_"..plr.UserId) end) if ok then saved=res dataStoreEnabled=true else warn("DataStore unavailable in local test; using temporary profile.") end end
    profiles[plr]=mergeProfile(saved)
    local p=profiles[plr]
    p.Passes={
        DoubleCash=ownsPass(plr,Config.Monetization.Gamepasses.DoubleCash),
        DoubleXP=ownsPass(plr,Config.Monetization.Gamepasses.DoubleXP),
        VIPContracts=ownsPass(plr,Config.Monetization.Gamepasses.VIPContracts),
        Premium4x4=ownsPass(plr,Config.Monetization.Gamepasses.Premium4x4),
    }
    if p.Passes.Premium4x4 then p.OwnedVehicles["Mega 4x4"]=true end
    local leaderstats=Instance.new("Folder") leaderstats.Name="leaderstats" leaderstats.Parent=plr
    local rankValue=Instance.new("StringValue") rankValue.Name="Rank" rankValue.Value=rankData(p).Name rankValue.Parent=leaderstats
    local cashValue=Instance.new("IntValue") cashValue.Name="Cash" cashValue.Value=math.min(2147483647,math.floor(p.Cash or 0)) cashValue.Parent=leaderstats
    task.spawn(function() while plr.Parent and profiles[plr] do task.wait(1) local pp=profiles[plr] if pp then rankValue.Value=rankData(pp).Name cashValue.Value=math.min(2147483647,math.floor(pp.Cash or 0)) end end end)
    sessionStarts[plr]=os.time() sessionClaimIndex[plr]=0
    plr:SetAttribute("HomeSpawn",homeSpawns[math.clamp(rankData(p).Zone,1,5)])
    plr.CharacterAdded:Connect(function(char)
        task.wait(.5) applyMovement(plr)
        teleportHome(plr,math.clamp(rankData(p).Zone,1,5)) applyVehicleVisual(plr)
        -- Wait for the avatar's clothes/body to load before swapping them for rags.
        if not plr:HasAppearanceLoaded() then
            local loaded=false
            local conn=plr.CharacterAppearanceLoaded:Connect(function() loaded=true end)
            local t0=os.clock()
            while not loaded and os.clock()-t0<5 and char.Parent do task.wait(.1) end
            conn:Disconnect()
        end
        if char.Parent then refreshLook(plr) end
    end)
    task.delay(1.5,function() sync(plr,"Talk to NPCs to discover upgrades") end)
end)
Players.PlayerRemoving:Connect(function(plr) if activeMissions[plr] then removeCustomer(activeMissions[plr]) end save(plr) clearVehicleVisual(plr) profiles[plr]=nil activeMissions[plr]=nil sessionStarts[plr]=nil sessionClaimIndex[plr]=nil remoteCooldowns[plr]=nil hitCooldown[plr]=nil slowedPlayers[plr]=nil end)
task.spawn(function() while true do task.wait(Config.AutosaveSeconds) for plr in pairs(profiles) do save(plr) end end end)
game:BindToClose(function() for plr in pairs(profiles) do save(plr) end task.wait(1) end)
