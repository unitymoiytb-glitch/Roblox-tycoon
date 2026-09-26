local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

-- V19 visual pass: warmer, denser, cinematic slum lighting without requiring external assets.
Lighting.ClockTime=16.8
Lighting.Brightness=2.35
Lighting.EnvironmentDiffuseScale=.55
Lighting.EnvironmentSpecularScale=.35
Lighting.ShadowSoftness=.65
Lighting.Ambient=Color3.fromRGB(95,82,72)
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
local zoneCenters={-400,-200,0,200,400}
local zoneNames={"THE SLUMS","OLD MARKET","DELIVERY DISTRICT","BUSINESS CORE","ROYAL HEIGHTS"}
local pickupParts, dropParts = {}, {}
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
        VendorSeen=p.VendorSeen,OwnedVehicles=p.OwnedVehicles,Passes=p.Passes,NextRank=nextRank and {Name=nextRank.Name,XP=nextRank.XP,Price=nextRank.Price,Deliveries=nextRank.Deliveries} or nil})
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
local function part(parent,name,size,pos,color,material)
    local p=Instance.new("Part") p.Name=name p.Size=size p.Position=pos p.Anchored=true p.Color=color
    p.Material=material or Enum.Material.SmoothPlastic p.TopSurface=Enum.SurfaceType.Smooth p.BottomSurface=Enum.SurfaceType.Smooth p.Parent=parent return p
end
local function wedge(parent,name,size,pos,color,material,orientation)
    local w=Instance.new("WedgePart") w.Name=name w.Size=size w.Position=pos w.Anchored=true w.Color=color w.Material=material or Enum.Material.Metal
    w.TopSurface=Enum.SurfaceType.Smooth w.BottomSurface=Enum.SurfaceType.Smooth w.Orientation=orientation or Vector3.zero w.Parent=parent return w
end
local function billboard(base,text,w,h,offset)
    local bb=Instance.new("BillboardGui") bb.Size=UDim2.fromOffset(w or 260,h or 70) bb.StudsOffset=offset or Vector3.new(0,4,0) bb.AlwaysOnTop=true bb.MaxDistance=28 bb.Parent=base
    local l=Instance.new("TextLabel") l.Size=UDim2.fromScale(1,1) l.BackgroundTransparency=.18 l.BackgroundColor3=Color3.fromRGB(10,10,10)
    l.TextColor3=Color3.new(1,1,1) l.TextScaled=true l.TextWrapped=true l.Font=Enum.Font.GothamBold l.Text=text l.Parent=bb return l
end

local function makeShack(parent,center,width,depth,height,tintA,tintB)
    local model=Instance.new("Model") model.Name="Shack" model.Parent=parent
    part(model,"Floor",Vector3.new(width,.7,depth),center+Vector3.new(0,.35,0),Color3.fromRGB(72,56,41),Enum.Material.Ground)
    part(model,"WallL",Vector3.new(.8,height,depth),center+Vector3.new(-width/2,height/2,0),tintA,Enum.Material.CorrodedMetal)
    part(model,"WallR",Vector3.new(.8,height,depth),center+Vector3.new(width/2,height/2,0),tintB,Enum.Material.CorrodedMetal)
    part(model,"Back",Vector3.new(width,height,.8),center+Vector3.new(0,height/2,depth/2),tintB,Enum.Material.CorrodedMetal)
    part(model,"FrontScrapL",Vector3.new(width*.20,height*.88,.45),center+Vector3.new(-width*.40,height*.44,-depth/2),tintA,Enum.Material.CorrodedMetal)
    part(model,"FrontScrapR",Vector3.new(width*.20,height*.76,.45),center+Vector3.new(width*.40,height*.38,-depth/2),tintB,Enum.Material.CorrodedMetal)
    local lintel=part(model,"FrontLintel",Vector3.new(width*.50,.38,.5),center+Vector3.new(0,height*.82,-depth/2),Color3.fromRGB(98,88,79),Enum.Material.CorrodedMetal)
    lintel.Orientation=Vector3.new(0,0,math.random(-6,6))
    local roof=part(model,"Roof",Vector3.new(width+1.1,.6,depth+1.4),center+Vector3.new(0,height+.25,0),Color3.fromRGB(88,82,74),Enum.Material.CorrodedMetal)
    roof.Orientation=Vector3.new(0,math.random(-8,8),math.random(-3,3))
    for i=1,math.random(5,8) do
        local pw=math.random(2,5)
        local ph=math.random(2,4)
        local side=(i%2==0) and -1 or 1
        local px=center.X + side*(width/2 + 0.12)
        local py=1.2 + math.random()*math.max(2,height-3)
        local pz=center.Z + math.random(-depth*0.40,depth*0.40)
        local patchColor=(math.random()<0.45) and Color3.fromRGB(math.random(80,150),math.random(80,150),math.random(80,150)) or Color3.fromRGB(math.random(85,130),math.random(60,100),math.random(48,90))
        local patch=part(model,"OuterPatch",Vector3.new(.24,ph,pw),Vector3.new(px,py,pz),patchColor,Enum.Material.CorrodedMetal)
        patch.Orientation=Vector3.new(math.random(-6,6),math.random(-12,12),math.random(-10,10))
    end
    if math.random() < 0.85 then
        local wire=part(model,"LaundryWire",Vector3.new(width*.7,.06,.06),center+Vector3.new(0,height*.75,depth/2+.4),Color3.fromRGB(40,40,40),Enum.Material.Metal) wire.CanCollide=false
        local cloth=part(model,"Laundry",Vector3.new(math.max(3,width*.22),math.random(2,3),.08),center+Vector3.new(math.random(-3,3),height*.62,depth/2+.55),Color3.fromRGB(math.random(90,180),math.random(60,140),math.random(60,140)),Enum.Material.Fabric) cloth.CanCollide=false
    end
    local mat=part(model,"Mattress",Vector3.new(math.max(4,width*.32),.45,math.max(6,depth*.42)),center+Vector3.new(-width*.22,.95,-depth*.04),Color3.fromRGB(96,81,64),Enum.Material.Fabric)
    local stain=part(model,"Stain",Vector3.new(1.9,.05,2.4),mat.Position+Vector3.new(.2,.26,.3),Color3.fromRGB(61,47,31),Enum.Material.SmoothPlastic)
    stain.CanCollide=false
    local shelf=part(model,"Shelf",Vector3.new(4.0,.18,1.0),center+Vector3.new(width*.25,4.4,depth*.22),Color3.fromRGB(78,57,36),Enum.Material.WoodPlanks) shelf.CanCollide=false
    local bottle=part(model,"Bottle",Vector3.new(.55,1.4,.55),center+Vector3.new(width*.24,4.95,depth*.22),Color3.fromRGB(44,98,61),Enum.Material.Glass) bottle.Transparency=.18 bottle.CanCollide=false
    local pot=part(model,"Pot",Vector3.new(1.6,.85,1.6),center+Vector3.new(width*.30,1.25,depth*.30),Color3.fromRGB(72,72,76),Enum.Material.Metal) pot.Shape=Enum.PartType.Cylinder pot.Orientation=Vector3.new(0,0,90) pot.CanCollide=false
    local junk=part(model,"Junk",Vector3.new(1.6,1.6,1.6),center+Vector3.new(width*.28,.95,depth*.18),Color3.fromRGB(43,43,40),Enum.Material.SmoothPlastic)
    junk.Orientation=Vector3.new(0,math.random(0,180),0)
    local puddle=part(model,"Puddle",Vector3.new(math.max(2,width*.22),.04,math.max(3,depth*.18)),center+Vector3.new(width*.18,0.73,-depth*.24),Color3.fromRGB(69,58,37),Enum.Material.SmoothPlastic) puddle.Transparency=.18 puddle.CanCollide=false
    local board=part(model,"Board",Vector3.new(math.max(4,width*.25),.2,1),center+Vector3.new(width*.1,.9,-depth*.22),Color3.fromRGB(81,57,36),Enum.Material.WoodPlanks)
    board.Orientation=Vector3.new(0,math.random(-25,25),6)
    local bulb=part(model,"Bulb",Vector3.new(.48,.48,.48),center+Vector3.new(0,height*.76,0),Color3.fromRGB(255,225,160),Enum.Material.Neon) bulb.Shape=Enum.PartType.Ball bulb.CanCollide=false
    local cord=part(model,"BulbCord",Vector3.new(.06,1.6,.06),center+Vector3.new(0,height*.90,0),Color3.fromRGB(28,28,28),Enum.Material.Metal) cord.CanCollide=false
    if math.random() < 0.9 then
        local canopy=part(model,"Awning",Vector3.new(math.max(4,width*.35),.2,2.4),center+Vector3.new(0,height*.6,-depth/2-1.1),Color3.fromRGB(73,92,94),Enum.Material.CorrodedMetal)
        canopy.Orientation=Vector3.new(math.random(-18,-6),0,math.random(-5,5))
    end
    if math.random() < .75 then
        local poster=part(model,"Poster",Vector3.new(math.max(2,width*.16),math.random(2,3),.05),center+Vector3.new(-width/2-.03,math.random(3,6),math.random(-2,2)),Color3.fromRGB(math.random(80,170),math.random(60,150),math.random(50,130)),Enum.Material.SmoothPlastic)
        poster.CanCollide=false poster.Orientation=Vector3.new(0,0,math.random(-10,10))
    end
    return model
end

local function addFavelaFacadeDetail(parent,cx,cz,side,seed)
    local rng=Random.new(seed)
    local wallX=cx+side*rng:NextNumber(112,151)
    local wallZ=cz+rng:NextNumber(-12,12)
    -- Color patches, balconies, pipes and water tanks add silhouette complexity.
    local patch=part(parent,"PaintedTin",Vector3.new(.22,rng:NextNumber(3,6),rng:NextNumber(4,8)),Vector3.new(wallX, rng:NextNumber(3,7), wallZ),Color3.fromRGB(rng:NextInteger(75,165),rng:NextInteger(65,145),rng:NextInteger(55,125)),Enum.Material.CorrodedMetal)
    patch.Orientation=Vector3.new(rng:NextNumber(-6,6),rng:NextNumber(-8,8),rng:NextNumber(-8,8))
    if rng:NextNumber()<.7 then
        local balcony=part(parent,"TinyBalcony",Vector3.new(rng:NextNumber(5,9),.35,rng:NextNumber(2.5,4)),Vector3.new(wallX-side*1.8,rng:NextNumber(6,10),wallZ),Color3.fromRGB(82,59,39),Enum.Material.WoodPlanks)
        local rail=part(parent,"BalconyRail",Vector3.new(rng:NextNumber(5,9),1.2,.18),balcony.Position+Vector3.new(-side*1.5,1,.0),Color3.fromRGB(67,64,58),Enum.Material.Metal) rail.CanCollide=false
    end
    if rng:NextNumber()<.75 then
        local tank=part(parent,"WaterTank",Vector3.new(3.2,2.5,3.2),Vector3.new(wallX-side*2,rng:NextNumber(10,15),wallZ+rng:NextNumber(-3,3)),Color3.fromRGB(45,59,68),Enum.Material.Metal)
        tank.Shape=Enum.PartType.Cylinder tank.Orientation=Vector3.new(0,0,90)
    end
end

local oldWorld=workspace:FindFirstChild("SIT_World") if oldWorld then oldWorld:Destroy() end
local World=Instance.new("Folder") World.Name="SIT_World" World.Parent=workspace
part(World,"Ground",Vector3.new(1000,2,700),Vector3.new(0,-1,0),Color3.fromRGB(112,96,73),Enum.Material.Ground)
local Hazards=Instance.new("Folder") Hazards.Name="Hazards" Hazards.Parent=World
local slowedPlayers={}
local function registerSlowHazard(zoneFolder,name,size,pos,color,material,factor,labelText)
    local hz=part(zoneFolder,name,size,pos,color,material)
    hz.Transparency=.18 hz.CanCollide=false hz:SetAttribute("HazardSlow",factor or 0.75)
    hz:SetAttribute("HazardText",labelText or "Muck")
    hz.Parent=Hazards
    hz.Touched:Connect(function(hit)
        local char=hit:FindFirstAncestorOfClass("Model")
        local plr=char and Players:GetPlayerFromCharacter(char)
        if not plr or slowedPlayers[plr] then return end
        local hum=char and char:FindFirstChildOfClass("Humanoid")
        local p=profiles[plr]
        if not hum or not p then return end
        slowedPlayers[plr]=true
        local normal=(Config.Vehicles[p.Vehicle] or Config.Vehicles.Feet).Speed
        hum.WalkSpeed=math.max(8, math.floor(normal*(factor or 0.75)))
        UIRE:FireClient(plr,"TOAST","🐌 "..(labelText or "Dirty sludge").." slowed you down")
        task.delay(1.7,function()
            if plr.Parent and hum.Parent then hum.WalkSpeed=(Config.Vehicles[(profiles[plr] and profiles[plr].Vehicle) or "Feet"] or Config.Vehicles.Feet).Speed end
            slowedPlayers[plr]=nil
        end)
    end)
    return hz
end

local zoneColors={Color3.fromRGB(74,62,49),Color3.fromRGB(105,86,67),Color3.fromRGB(135,128,114),Color3.fromRGB(178,180,184),Color3.fromRGB(224,226,232)}
local roadColors={Color3.fromRGB(49,45,41),Color3.fromRGB(43,43,41),Color3.fromRGB(38,38,39),Color3.fromRGB(31,31,33),Color3.fromRGB(24,25,28)}
for z=1,5 do
    local cx=zoneCenters[z]
    local zoneFolder=Instance.new("Folder") zoneFolder.Name="Zone_"..z zoneFolder:SetAttribute("SITZone",z) zoneFolder.Parent=World
    part(zoneFolder,"Road_Z"..z,Vector3.new(122,1,640),Vector3.new(cx,.05,0),roadColors[z],z>=4 and Enum.Material.Asphalt or Enum.Material.Concrete)
    -- Streets visibly improve as rank increases.
    local sidewalkColor = z<=2 and Color3.fromRGB(103,92,78) or (z==3 and Color3.fromRGB(150,150,146) or Color3.fromRGB(205,205,208))
    part(zoneFolder,"SidewalkL",Vector3.new(9,1.2,640),Vector3.new(cx-66,.6,0),sidewalkColor,z>=3 and Enum.Material.Concrete or Enum.Material.Ground)
    part(zoneFolder,"SidewalkR",Vector3.new(9,1.2,640),Vector3.new(cx+66,.6,0),sidewalkColor,z>=3 and Enum.Material.Concrete or Enum.Material.Ground)
    -- Four compact traffic lanes, with three broken separators.
    for _,dividerX in ipairs({-12,0,12}) do
        for zz=-280,280,35 do
            local laneColor=z>=4 and Color3.fromRGB(246,242,210) or Color3.fromRGB(210,194,132)
            part(zoneFolder,"LaneDivider",Vector3.new(.7,.08,14),Vector3.new(cx+dividerX,.62,zz),laneColor,Enum.Material.Neon)
        end
    end
    if z==1 then
        -- True containment: the outer edge of each sidewalk is a hard wall, so the player cannot bypass the road outside the playable strip.
        for _,side in ipairs({-1,1}) do
            local edgeX=cx+side*71.2
            local hard=part(zoneFolder,"HardBoundary_"..side,Vector3.new(.55,16,632),Vector3.new(edgeX,8,0),Color3.new(1,1,1),Enum.Material.SmoothPlastic)
            hard.Transparency=1 hard.CanCollide=true
            -- Cheap visual fence segments hide the invisible boundary and make the street feel enclosed.
            for zz=-276,276,46 do
                local panel=part(zoneFolder,"BoundaryTin_"..side,Vector3.new(.45,2.8,40),Vector3.new(edgeX-side*.28,1.55,zz),Color3.fromRGB(88+math.random(0,28),70+math.random(0,22),55+math.random(0,18)),Enum.Material.CorrodedMetal)
                panel.Orientation=Vector3.new(0,0,math.random(-2,2))
                local post=part(zoneFolder,"BoundaryPost_"..side,Vector3.new(.5,3.4,.5),Vector3.new(edgeX-side*.5,1.85,zz-20),Color3.fromRGB(75,59,46),Enum.Material.WoodPlanks)
            end
        end
        -- End caps stop players running around the ends of the boundary.
        local endA=part(zoneFolder,"EndBoundaryA",Vector3.new(145,16,.6),Vector3.new(cx,8,-309),Color3.new(1,1,1),Enum.Material.SmoothPlastic) endA.Transparency=1
        local endB=part(zoneFolder,"EndBoundaryB",Vector3.new(145,16,.6),Vector3.new(cx,8,309),Color3.new(1,1,1),Enum.Material.SmoothPlastic) endB.Transparency=1
        -- Alternating sidewalk closures force repeated dives into live traffic.
        local leftBlocks={-235,-125,-15,95,205}
        local rightBlocks={-185,-75,35,145}
        local function barricade(side,zz,index)
            local bx=cx+side*66
            local barrier=part(zoneFolder,"SidewalkBarricade_"..side.."_"..index,Vector3.new(12.5,3.2,1.5),Vector3.new(bx,2.15,zz),Color3.fromRGB(102,72,51),Enum.Material.WoodPlanks)
            local blocker=part(zoneFolder,"BarricadeBlocker_"..side.."_"..index,Vector3.new(10.5,9,2.2),Vector3.new(cx+side*66.2,4.5,zz),Color3.new(1,1,1),Enum.Material.SmoothPlastic)
            blocker.Transparency=1 blocker.CanCollide=true
            for i=1,6 do
                local stripe=part(zoneFolder,"BarricadeStripe",Vector3.new(2.4,.72,.12),Vector3.new(bx-4.6+(i-1)*1.85,2.20,zz-side*.82),(i%2==0) and Color3.fromRGB(214,202,174) or Color3.fromRGB(151,67,53),Enum.Material.SmoothPlastic)
                stripe.CanCollide=false
            end
            local scrap=part(zoneFolder,"BarricadeScrap",Vector3.new(12,.18,2.8),Vector3.new(bx,3.9,zz),Color3.fromRGB(95,92,82),Enum.Material.CorrodedMetal) scrap.Orientation=Vector3.new(0,0,side*4) scrap.CanCollide=false
        end
        for i,zz in ipairs(leftBlocks) do barricade(-1,zz,i) end
        for i,zz in ipairs(rightBlocks) do barricade(1,zz,i) end
    end
    pickupParts[z],dropParts[z]={},{}
    for i=1,7 do
        local side=(i%2==0) and 1 or -1 local zp=-270+(i-1)*90
        -- No generated district buildings: only invisible mission points remain around the road.
        local pk=part(zoneFolder,"Pickup_Z"..z.."_"..i,Vector3.new(7,1,7),Vector3.new(cx+side*29,.6,zp-15),Color3.fromRGB(255,166,35),Enum.Material.Neon)
        pk.Transparency=1 pk.CanCollide=false
        local dp=part(zoneFolder,"Drop_Z"..z.."_"..i,Vector3.new(7,1,7),Vector3.new(cx-side*29,.6,zp+15),Color3.fromRGB(45,235,115),Enum.Material.Neon)
        dp.Transparency=1 dp.CanCollide=false
        pickupParts[z][i]=pk dropParts[z][i]=dp
    end
    -- Slums are filthy; later districts progressively lose the litter.
    local trashCount=({10,8,4,2,0})[z]
    for i=1,trashCount do
        local side=math.random()<.5 and -1 or 1
        local trash=part(zoneFolder,"Trash",Vector3.new(math.random(1,4),math.random(1,2),math.random(1,4)),Vector3.new(cx+side*math.random(74,101),.8,math.random(-270,245)),Color3.fromRGB(math.random(55,105),math.random(45,85),math.random(35,70)),Enum.Material.SmoothPlastic)
        trash.Orientation=Vector3.new(math.random(0,30),math.random(0,180),math.random(0,30))
    end
    if z==1 then
        -- Rebuild the block around the starter home using the same open-front shack vibe.
        for i=1,20 do
            local side=math.random()<.5 and -1 or 1
            local pos=Vector3.new(cx+side*math.random(50,64),.12,math.random(-255,245))
            local stain=part(zoneFolder,"GroundGrime",Vector3.new(math.random(3,8),.05,math.random(2,6)),pos,Color3.fromRGB(math.random(68,96),math.random(54,72),math.random(32,48)),Enum.Material.SmoothPlastic)
            stain.Transparency=.15 stain.CanCollide=false stain.Orientation=Vector3.new(0,math.random(0,180),0)
        end
        for i=1,10 do
            local hx = cx + ((i%2==0) and -50 or -56)
            local hz = -210 + i*44
            registerSlowHazard(zoneFolder,"MuckPatch",Vector3.new(math.random(6,10),.08,math.random(5,9)),Vector3.new(hx,.12,hz),Color3.fromRGB(82,69,34),Enum.Material.Mud,0.72,"Thick mud")
        end
        for i=1,8 do
            local hx = cx + ((i%2==0) and 50 or 56)
            local hz = 50 + i*24
            registerSlowHazard(zoneFolder,"PoopPatch",Vector3.new(math.random(3,5),.08,math.random(3,5)),Vector3.new(hx,.12,hz),Color3.fromRGB(74,49,26),Enum.Material.Mud,0.62,"Filthy sludge")
        end
        for i=1,14 do
            local pile=part(zoneFolder,"TrashPile",Vector3.new(math.random(3,7),math.random(2,4),math.random(3,7)),Vector3.new(cx-58+math.random(-5,7),.9,-250+i*34),Color3.fromRGB(58,58,52),Enum.Material.SmoothPlastic)
            pile.Orientation=Vector3.new(0,math.random(0,180),0)
        end
        for i=1,10 do
            local sign=part(zoneFolder,"HandPaintedSign",Vector3.new(.18,3.3,6.5),Vector3.new(cx-68.5,4.1,-290+(i-1)*60),Color3.fromRGB(math.random(90,190),math.random(65,160),math.random(45,130)),Enum.Material.WoodPlanks)
            sign.Orientation=Vector3.new(0,math.random(-10,10),math.random(-5,5)) sign.CanCollide=false
        end
        for _,side in ipairs({-1,1}) do
            local drain=part(zoneFolder,"OpenDrain",Vector3.new(3,.28,610),Vector3.new(cx+side*69.2,.2,0),Color3.fromRGB(40,49,37),Enum.Material.SmoothPlastic) drain.Transparency=.05 drain.CanCollide=false
        end
        -- rows of shacks along the road, but keep home/hub corridor clear.
        local shackSpecs={
            {-78,-194,16,16,8},{-80,-132,18,16,8},{-78,-70,16,16,8},{-80,-8,18,16,8},{-78,54,16,16,8},{-80,118,18,16,8},
            {78,-176,16,16,8},{80,-112,18,16,8},{78,-46,16,16,8},{80,20,18,16,8},{78,86,16,16,8},{80,150,18,16,8}
        }
        for idx,spec in ipairs(shackSpecs) do
            local sx,sz,w,d,h = table.unpack(spec)
            -- leave the immediate starter-house area more open.
            if not (sz > 220 and math.abs(sx+62) < 85) then
                local shack=makeShack(zoneFolder,Vector3.new(cx+sx,h/2,sz),w,d,h,Color3.fromRGB(80+((idx*17)%45),70+((idx*9)%38),58+((idx*7)%26)),Color3.fromRGB(90+((idx*11)%40),78+((idx*5)%34),68+((idx*13)%28)))
                shack:SetAttribute("SITZone",1)
                if idx%3==0 then
                    local barrel=part(shack,"BlueDrum",Vector3.new(2.1,2.7,2.1),Vector3.new(cx+sx+math.random(-4,4),1.5,sz-d/2-3),Color3.fromRGB(51,96,138),Enum.Material.Metal)
                    barrel.Shape=Enum.PartType.Cylinder barrel.Orientation=Vector3.new(0,0,90)
                end
                if idx%2==0 then
                    local fence=part(shack,"Fence",Vector3.new(math.random(6,12),2.8,.18),Vector3.new(cx+sx+math.random(-2,2),1.6,sz-d/2-4.8),Color3.fromRGB(112,94,71),Enum.Material.WoodPlanks)
                    fence.Orientation=Vector3.new(0,math.random(-18,18),0)
                end
            end
        end
        -- a few stacked shacks in the far background for depth.
        
    end



    -- A home in every district. Rank 1 begins in a dirty open-front tin shack.
    local homeZ=(z==1 and 276 or 298) local homeX=cx-34
    local homeModel=Instance.new("Model") homeModel.Name="Home_Z"..z homeModel:SetAttribute("SITZone",z) homeModel.Parent=zoneFolder
    if z==1 then
        -- STARTER SHACK V24: smaller, closer, and lighter so it reads better and runs smoother.
        local roomW,roomD,roomH=28,24,9.2
        part(homeModel,"PackedEarthFloor",Vector3.new(roomW,1,roomD),Vector3.new(homeX,.5,homeZ),Color3.fromRGB(82,62,43),Enum.Material.Ground)
        part(homeModel,"BackTin",Vector3.new(roomW,roomH,.5),Vector3.new(homeX,roomH/2,homeZ+roomD/2),Color3.fromRGB(83,67,55),Enum.Material.CorrodedMetal)
        part(homeModel,"LeftTin",Vector3.new(.5,roomH,roomD),Vector3.new(homeX-roomW/2,roomH/2,homeZ),Color3.fromRGB(66,76,73),Enum.Material.CorrodedMetal)
        part(homeModel,"RightTin",Vector3.new(.5,roomH,roomD),Vector3.new(homeX+roomW/2,roomH/2,homeZ),Color3.fromRGB(111,73,51),Enum.Material.CorrodedMetal)
        -- Patchwork panels break the huge flat walls and create the layered look from the concept image.
        local wallCols={Color3.fromRGB(117,77,52),Color3.fromRGB(72,91,88),Color3.fromRGB(94,79,64),Color3.fromRGB(130,83,53),Color3.fromRGB(83,84,75)}
        for i=1,5 do
            local pw=5.6
            local patch=part(homeModel,"BackPanel"..i,Vector3.new(pw,roomH-.8,.16),Vector3.new(homeX-roomW/2+2.8+(i-1)*5.6,roomH/2,homeZ+roomD/2-.34),wallCols[i],Enum.Material.CorrodedMetal)
            patch.Orientation=Vector3.new(math.random(-1,1),math.random(-2,2),math.random(-2,2)) patch.CanCollide=false
        end
        for i=1,3 do
            local zoff=-7.8+(i-1)*7.8
            local lp=part(homeModel,"LeftPanel"..i,Vector3.new(.16,roomH-.7,7.5),Vector3.new(homeX-roomW/2+.34,roomH/2,homeZ+zoff),wallCols[((i+1)%#wallCols)+1],Enum.Material.CorrodedMetal) lp.CanCollide=false
            local rp=part(homeModel,"RightPanel"..i,Vector3.new(.16,roomH-.7,7.5),Vector3.new(homeX+roomW/2-.34,roomH/2,homeZ+zoff),wallCols[((i+3)%#wallCols)+1],Enum.Material.CorrodedMetal) rp.CanCollide=false
        end
        local timber=Color3.fromRGB(79,54,35)
        for _,xoff in ipairs({-13.2,13.2}) do
            part(homeModel,"FrontPost",Vector3.new(.8,10,.8),Vector3.new(homeX+xoff,5.0,homeZ-11.6),timber,Enum.Material.WoodPlanks)
            part(homeModel,"BackPost",Vector3.new(.8,10,.8),Vector3.new(homeX+xoff,5.0,homeZ+11.6),timber,Enum.Material.WoodPlanks)
        end
        for _,zoff in ipairs({-8,0,8}) do
            part(homeModel,"RoofBeam",Vector3.new(27,.55,.55),Vector3.new(homeX,9.15,homeZ+zoff),timber,Enum.Material.WoodPlanks)
        end
        local roofCols={Color3.fromRGB(80,77,71),Color3.fromRGB(105,83,64),Color3.fromRGB(69,84,82),Color3.fromRGB(122,76,50)}
        for i=1,4 do
            local rx=homeX-10.2+(i-1)*6.8
            local sheet=part(homeModel,"RoofSheet"..i,Vector3.new(7.2,.34,26),Vector3.new(rx,9.6+((i%2)*.05),homeZ),roofCols[((i-1)%#roofCols)+1],Enum.Material.CorrodedMetal)
            sheet.Orientation=Vector3.new(0,math.random(-2,2),math.random(-3,3))
        end
        local mattress=part(homeModel,"FilthyMattress",Vector3.new(9,.70,10),Vector3.new(homeX-7.7,1.02,homeZ+1.6),Color3.fromRGB(104,89,69),Enum.Material.Fabric) mattress.CanCollide=false
        local pillow=part(homeModel,"Pillow",Vector3.new(3.1,.5,2.1),Vector3.new(homeX-10.4,1.45,homeZ+5.1),Color3.fromRGB(126,116,97),Enum.Material.Fabric) pillow.CanCollide=false
        local blanket=part(homeModel,"Blanket",Vector3.new(5.8,.18,4.2),Vector3.new(homeX-6.2,1.42,homeZ-.6),Color3.fromRGB(96,66,62),Enum.Material.Fabric) blanket.CanCollide=false blanket.Orientation=Vector3.new(0,-10,4)
        local tableTop=part(homeModel,"RoughTable",Vector3.new(5.2,.4,2.8),Vector3.new(homeX-2.1,2.6,homeZ+7.8),Color3.fromRGB(88,59,37),Enum.Material.WoodPlanks)
        for _,xo in ipairs({-2.0,2.0}) do part(homeModel,"TableLeg",Vector3.new(.35,2.3,.35),Vector3.new(homeX-2.1+xo,1.3,homeZ+7.8),timber,Enum.Material.WoodPlanks) end
        local stove=part(homeModel,"CookingBlock",Vector3.new(4.2,1.9,3.8),Vector3.new(homeX+9.0,1.45,homeZ+6.2),Color3.fromRGB(87,67,53),Enum.Material.Brick)
        local fire=part(homeModel,"Coals",Vector3.new(1.8,.16,1.8),Vector3.new(homeX+9.0,2.42,homeZ+6.2),Color3.fromRGB(188,73,35),Enum.Material.Neon) fire.CanCollide=false
        local pot=part(homeModel,"BlackCookingPot",Vector3.new(2.5,1.2,2.5),Vector3.new(homeX+9.0,3.0,homeZ+6.2),Color3.fromRGB(43,42,40),Enum.Material.Metal) pot.Shape=Enum.PartType.Cylinder pot.Orientation=Vector3.new(0,0,90) pot.CanCollide=false
        local bucket=part(homeModel,"DirtyBucket",Vector3.new(2.3,2.4,2.3),Vector3.new(homeX+7.8,1.35,homeZ-5.0),Color3.fromRGB(112,104,92),Enum.Material.SmoothPlastic) bucket.Shape=Enum.PartType.Cylinder bucket.Orientation=Vector3.new(0,0,90)
        local line1=part(homeModel,"ClothesLine",Vector3.new(18,.06,.06),Vector3.new(homeX,6.9,homeZ+1.4),Color3.fromRGB(25,25,25),Enum.Material.Metal) line1.CanCollide=false
        local clothCols={Color3.fromRGB(72,80,92),Color3.fromRGB(154,142,126),Color3.fromRGB(116,56,51)}
        for i=1,3 do
            local c=part(homeModel,"HangingCloth"..i,Vector3.new(3.1,3.2,.08),Vector3.new(homeX-5.5+(i-1)*4.6,5.55,homeZ+1.45),clothCols[i],Enum.Material.Fabric) c.CanCollide=false
        end
        local bulb=part(homeModel,"BareBulb",Vector3.new(.58,.58,.58),Vector3.new(homeX-1.0,7.1,homeZ-1.8),Color3.fromRGB(255,221,153),Enum.Material.Neon) bulb.Shape=Enum.PartType.Ball bulb.CanCollide=false
        local wire=part(homeModel,"BulbWire",Vector3.new(.07,2.1,.07),Vector3.new(homeX-1.0,8.15,homeZ-1.8),Color3.fromRGB(22,22,22),Enum.Material.Metal) wire.CanCollide=false
        local light=Instance.new("PointLight") light.Color=Color3.fromRGB(255,205,135) light.Brightness=.85 light.Range=16 light.Shadows=true light.Parent=bulb
        local shelf=part(homeModel,"WallShelf",Vector3.new(5.5,.28,1.4),Vector3.new(homeX+8.6,5.8,homeZ+8.7),Color3.fromRGB(79,55,35),Enum.Material.WoodPlanks) shelf.CanCollide=false
        local greenBottle=part(homeModel,"GreenBottle",Vector3.new(.55,1.5,.55),Vector3.new(homeX+7.2,6.7,homeZ+8.7),Color3.fromRGB(42,91,54),Enum.Material.Glass) greenBottle.Transparency=.15 greenBottle.CanCollide=false
        local smallTin=part(homeModel,"SmallTin",Vector3.new(.8,.9,.8),Vector3.new(homeX+9.0,6.45,homeZ+8.7),Color3.fromRGB(126,91,62),Enum.Material.Metal) smallTin.CanCollide=false
        local rag=part(homeModel,"WallRag",Vector3.new(2.5,3.8,.08),Vector3.new(homeX+13.72,5.4,homeZ+1.8),Color3.fromRGB(142,128,107),Enum.Material.Fabric) rag.CanCollide=false
        local crate2=part(homeModel,"CrateCorner",Vector3.new(3.6,2.2,3.4),Vector3.new(homeX+9.8,1.6,homeZ-7.8),Color3.fromRGB(90,60,37),Enum.Material.WoodPlanks)
        local tyre=part(homeModel,"OldTyre",Vector3.new(2.6,2.6,.7),Vector3.new(homeX-11.0,1.45,homeZ-7.8),Color3.fromRGB(27,27,27),Enum.Material.Rubber) tyre.Shape=Enum.PartType.Cylinder tyre.Orientation=Vector3.new(0,0,90) tyre.CanCollide=false
        local frontL=part(homeModel,"FrontScrapL",Vector3.new(5,6.8,.35),Vector3.new(homeX-11.5,3.5,homeZ-11.9),Color3.fromRGB(96,75,56),Enum.Material.CorrodedMetal)
        local frontR=part(homeModel,"FrontScrapR",Vector3.new(5,6.4,.35),Vector3.new(homeX+11.5,3.3,homeZ-11.9),Color3.fromRGB(82,90,86),Enum.Material.CorrodedMetal)
        local rug=part(homeModel,"EntryRug",Vector3.new(5,.09,3.4),Vector3.new(homeX,1.05,homeZ-7.8),Color3.fromRGB(111,78,54),Enum.Material.Fabric) rug.CanCollide=false
        for i=1,3 do
            local pd=part(homeModel,"MuddyPuddle"..i,Vector3.new(math.random(3,5),.04,math.random(2,4)),Vector3.new(homeX+math.random(-10,10),1.02,homeZ+math.random(-8,7)),Color3.fromRGB(58,49,31),Enum.Material.SmoothPlastic) pd.Transparency=.18 pd.CanCollide=false pd.Orientation=Vector3.new(0,math.random(0,180),0)
        end
        for i=1,5 do
            local litter=part(homeModel,"Litter"..i,Vector3.new(math.random(4,10)/10,.07,math.random(5,12)/10),Vector3.new(homeX+math.random(-12,12),1.09,homeZ+math.random(-9,9)),Color3.fromRGB(math.random(70,160),math.random(55,120),math.random(40,95)),Enum.Material.SmoothPlastic) litter.CanCollide=false litter.Orientation=Vector3.new(0,math.random(0,180),0)
        end
        local apron=part(homeModel,"MuddyApron",Vector3.new(24,.10,10),Vector3.new(homeX,1.04,homeZ-16),Color3.fromRGB(94,73,49),Enum.Material.Ground) apron.CanCollide=false
        local apronPuddle=part(homeModel,"ApronPuddle",Vector3.new(6,.04,3.2),Vector3.new(homeX+4,1.11,homeZ-16),Color3.fromRGB(54,47,31),Enum.Material.SmoothPlastic) apronPuddle.Transparency=.16 apronPuddle.CanCollide=false
        homeSpawns[z]=CFrame.lookAt(Vector3.new(homeX,3.1,homeZ+2.8),Vector3.new(homeX,3.1,homeZ-18))
    else
        -- no district buildings beyond the starter house for this focused iteration
        homeSpawns[z]=CFrame.new(homeX,4,homeZ-17)
        homeModel:Destroy()
    end
end

local rankGuards={}
local vendorModels={}

-- Compact local hub: the important NPCs live near the player's home in each district.
for z=1,5 do
    local cx=zoneCenters[z]
    local hubZ=(z==1 and 258 or 258)
    local hub=part(World,"HubFloor_Z"..z,Vector3.new(92,.35,40),Vector3.new(cx-52,.18,hubZ),z==1 and Color3.fromRGB(87,72,55) or Color3.fromRGB(145+z*12,145+z*12,145+z*12),z>=3 and Enum.Material.Concrete or Enum.Material.Ground)
    hub:SetAttribute("SITZone",z)
    if z==1 then
        local path=part(World,"HomePath_Z1",Vector3.new(9,.12,18),Vector3.new(cx-34,.22,260),Color3.fromRGB(105,86,67),Enum.Material.Ground)
        path:SetAttribute("SITZone",1)
        local alleyPoleA=part(World,"AlleyPoleA",Vector3.new(.25,9,.25),Vector3.new(cx-44,4.5,258),Color3.fromRGB(83,71,54),Enum.Material.WoodPlanks) alleyPoleA:SetAttribute("SITZone",1)
        local alleyPoleB=part(World,"AlleyPoleB",Vector3.new(.25,9,.25),Vector3.new(cx-24,4.5,258),Color3.fromRGB(83,71,54),Enum.Material.WoodPlanks) alleyPoleB:SetAttribute("SITZone",1)
        local line=part(World,"AlleyLine",Vector3.new(45,.06,.06),Vector3.new(cx-34,8.1,258),Color3.fromRGB(32,32,32),Enum.Material.Metal) line.CanCollide=false line:SetAttribute("SITZone",1)
        local cloth=part(World,"AlleyCloth",Vector3.new(6,3,.08),Vector3.new(cx-30,6.2,258),Color3.fromRGB(127,66,52),Enum.Material.Fabric) cloth.CanCollide=false cloth:SetAttribute("SITZone",1)
        for i=1,5 do
            local zz=210-i*74
            local poleL=part(World,"UtilityPoleL",Vector3.new(.35,10,.35),Vector3.new(cx-67.5,5,zz),Color3.fromRGB(73,59,44),Enum.Material.WoodPlanks) poleL:SetAttribute("SITZone",1)
            local poleR=part(World,"UtilityPoleR",Vector3.new(.35,10,.35),Vector3.new(cx+67.5,5,zz+18),Color3.fromRGB(73,59,44),Enum.Material.WoodPlanks) poleR:SetAttribute("SITZone",1)
            local wire1=part(World,"UtilityWire",Vector3.new(135,.05,.05),Vector3.new(cx,9.0,zz+9),Color3.fromRGB(25,25,25),Enum.Material.Metal) wire1.CanCollide=false wire1:SetAttribute("SITZone",1)
        end
        for i=1,4 do
            local zc=-180+i*92
            local bag=part(World,"StreetBag",Vector3.new(2.2,2.0,2.2),Vector3.new(cx-60,1.4,zc),Color3.fromRGB(28,28,27),Enum.Material.SmoothPlastic) bag:SetAttribute("SITZone",1)
            local drum=part(World,"StreetDrum",Vector3.new(2.0,2.6,2.0),Vector3.new(cx+60,1.6,zc+28),Color3.fromRGB(52,94,129),Enum.Material.Metal) drum.Shape=Enum.PartType.Cylinder drum.Orientation=Vector3.new(0,0,90) drum:SetAttribute("SITZone",1)
        end
    end
end

-- Cleanup only hidden homes from later zones.
for _,obj in ipairs(World:GetDescendants()) do
    if obj:IsA("Model") then
        local n=obj.Name
        if n:match("^Home_Z[2-5]$") then
            obj:Destroy()
        end
    end
end

local function makeNPC(name,pos,color,title,actionText,zoneIndex,dialog)
    local model=Instance.new("Model") model.Name=name model:SetAttribute("SITZone",zoneIndex) model.Parent=World
    local torso=part(model,"Torso",Vector3.new(2.8,3.2,1.8),pos+Vector3.new(0,3.1,0),color)
    local hips=part(model,"Hips",Vector3.new(2.4,1.1,1.6),pos+Vector3.new(0,1.75,0),Color3.fromRGB(58,58,64))
    local legL=part(model,"LegL",Vector3.new(.7,2.1,.7),pos+Vector3.new(-.55,.65,0),Color3.fromRGB(36,36,42))
    local legR=part(model,"LegR",Vector3.new(.7,2.1,.7),pos+Vector3.new(.55,.65,0),Color3.fromRGB(36,36,42))
    local armL=part(model,"ArmL",Vector3.new(.55,2.2,.55),pos+Vector3.new(-1.8,3.0,0),Color3.fromRGB(191,139,95))
    local armR=part(model,"ArmR",Vector3.new(.55,2.2,.55),pos+Vector3.new(1.8,3.0,0),Color3.fromRGB(191,139,95))
    local head=part(model,"Head",Vector3.new(2.1,2.1,2.1),pos+Vector3.new(0,5.6,0),Color3.fromRGB(191,139,95))
    head.Shape=Enum.PartType.Ball
    local face=Instance.new("Decal") face.Name="Face" face.Texture="rbxasset://textures/face.png" face.Face=Enum.NormalId.Front face.Parent=head
    local hair=part(model,"Hair",Vector3.new(2.15,.8,2.15),pos+Vector3.new(0,6.35,0),Color3.fromRGB(34,24,18),Enum.Material.SmoothPlastic)
    hair.Shape=Enum.PartType.Ball
    local promptBase=torso
    local crate=part(model,"VendorCrate",Vector3.new(2.4,1.4,2.4),pos+Vector3.new(2.8,.7,0),Color3.fromRGB(105,72,42),Enum.Material.WoodPlanks)
    crate.Orientation=Vector3.new(0,18,0)
    billboard(head,title,260,65,Vector3.new(0,2.2,0))
    local prompt=Instance.new("ProximityPrompt") prompt.ActionText=actionText prompt.ObjectText=title prompt.HoldDuration=.2 prompt.MaxActivationDistance=13 prompt.RequiresLineOfSight=false prompt.Parent=promptBase
    return model,prompt,torso
end

-- One delivery vendor per district. Talking to the vendor is now the only way to start work.
local vendorTitles={"📦 Raju — Delivery Jobs","📦 Market Vendor","🍔 Delivery Dispatcher","💻 Business Courier","💎 VIP Fixer"}
local vendorColors={Color3.fromRGB(113,77,47),Color3.fromRGB(115,91,52),Color3.fromRGB(52,103,126),Color3.fromRGB(62,76,110),Color3.fromRGB(105,76,28)}
for z=1,5 do
    local cx=zoneCenters[z]
    local vendorPos = (z==1) and Vector3.new(cx-44,0,239) or Vector3.new(cx-40,0,258)
    local model,prompt,torso=makeNPC("VendorNPC_"..z,vendorPos,vendorColors[z],vendorTitles[z],"Ask for work",z,"")
    vendorModels[z]=model
    if z==1 then
        local stall=Instance.new("Model") stall.Name="DeliveryStall_Z1" stall:SetAttribute("SITZone",1) stall.Parent=World
        part(stall,"Table",Vector3.new(9,1,4),vendorPos+Vector3.new(0,1,-3.5),Color3.fromRGB(92,62,37),Enum.Material.WoodPlanks)
        local tarp=part(stall,"Tarp",Vector3.new(12,.25,7),vendorPos+Vector3.new(0,7,-2),Color3.fromRGB(137,71,55),Enum.Material.Fabric) tarp.Orientation=Vector3.new(-5,0,3)
        part(stall,"PoleL",Vector3.new(.25,7,.25),vendorPos+Vector3.new(-5.2,3.5,-2),Color3.fromRGB(64,54,44),Enum.Material.Wood)
        part(stall,"PoleR",Vector3.new(.25,7,.25),vendorPos+Vector3.new(5.2,3.5,-2),Color3.fromRGB(64,54,44),Enum.Material.Wood)
        local boxA=part(stall,"ParcelA",Vector3.new(2,1.5,2),vendorPos+Vector3.new(-2.4,2,-3.4),Color3.fromRGB(146,112,72),Enum.Material.WoodPlanks)
        local boxB=part(stall,"ParcelB",Vector3.new(1.6,1.1,1.8),vendorPos+Vector3.new(2.5,1.8,-3.5),Color3.fromRGB(120,93,61),Enum.Material.WoodPlanks)
    end
    prompt.Triggered:Connect(function(plr)
        local p=profiles[plr] if not p then return end
        local currentZone=math.clamp(rankData(p).Zone,1,5)
        if currentZone~=z then UIRE:FireClient(plr,"TOAST","This vendor does not work with you yet.") return end
        if activeMissions[plr] then UIRE:FireClient(plr,"TOAST","Finish your current delivery first.") return end
        p.VendorSeen[z]=true
        local available={}
        for _,it in ipairs(Config.DeliveryItems[z] or {}) do
            if p.TotalDeliveries >= (it.MinDeliveries or 0) then table.insert(available,it) end
        end
        UIRE:FireClient(plr,"VENDOR_MENU",{Zone=z,Title=vendorTitles[z],Items=available})
    end)
end

-- Mechanic and broker stay discoverable in the first district.
local mechanic,mechanicPrompt=makeNPC("MechanicNPC",Vector3.new(-470,0,258),Color3.fromRGB(42,92,130),"🔧 Jugaad Mechanic","Talk",1,"")
mechanicPrompt.Triggered:Connect(function(plr)
    local p=profiles[plr] if not p then return end
    if p.TotalDeliveries < 1 then UIRE:FireClient(plr,"NPC",{Key="Locked",Title="🔧 Jugaad Mechanic",Text="Bring me proof you can survive one delivery first."}) return end
    p.NPCUnlocks.Mechanic=true
    UIRE:FireClient(plr,"NPC",{Key="Mechanic",Title="🔧 Jugaad Mechanic",Text="You survived. Good. A junk bicycle costs ₹350. Save up, then buy it if you want to cross faster."}) sync(plr)
end)
local broker,brokerPrompt=makeNPC("BrokerNPC",Vector3.new(-495,0,258),Color3.fromRGB(70,115,65),"💼 Street Broker","Talk",1,"")
brokerPrompt.Triggered:Connect(function(plr)
    local p=profiles[plr] if not p then return end
    if p.TotalDeliveries < 4 then UIRE:FireClient(plr,"NPC",{Key="Locked",Title="💼 Street Broker",Text="Come back after 4 deliveries. Then we can talk business."}) return end
    p.NPCUnlocks.Broker=true
    UIRE:FireClient(plr,"NPC",{Key="Broker",Title="💼 Street Broker",Text="Now you look useful. A tea stall costs ₹1200 and pays slowly while you keep delivering."}) sync(plr)
end)

local guardColors={Color3.fromRGB(90,125,165),Color3.fromRGB(88,105,145),Color3.fromRGB(80,80,92),Color3.fromRGB(45,45,50)}
for z=1,4 do
    local gateX=(zoneCenters[z]+zoneCenters[z+1])/2
    local gate=part(World,"GateTrigger_"..z,Vector3.new(6,18,640),Vector3.new(gateX,9,0),Color3.new(1,1,1),Enum.Material.SmoothPlastic)
    gate:SetAttribute("PromotionGateFor",z+1) gate.Transparency=1 gate.CanCollide=false
    local guard,prompt,torso=makeNPC("GuardNPC_"..z,Vector3.new(gateX-12,0,0),guardColors[z],"🛑 "..Config.Ranks[z+1].Name,"Talk",z,"")
    rankGuards[z]=guard
    local function reject(plr,fromTouch)
        local p=profiles[plr] if not p then return end
        if p.Rank>z then return false end
        local nr=Config.Ranks[z+1]
        local ready=(p.Cash>=nr.Price) and (p.XP>=nr.XP) and (p.TotalDeliveries>=(nr.Deliveries or 0)) and (p.Rebirths>=(nr.RebirthsRequired or 0))
        if ready then
            UIRE:FireClient(plr,"RANK_OFFER",{Name=nr.Name,Price=nr.Price,XP=nr.XP,Deliveries=nr.Deliveries,CurrentXP=p.XP,CurrentCash=p.Cash,CurrentDeliveries=p.TotalDeliveries})
        else
            UIRE:FireClient(plr,"GUARD_BLOCK",{Title="🛑 "..nr.Name,Text="Not yet. Go make deliveries, then come back when you have earned your place."})
        end
        if fromTouch then
            local char=plr.Character local root=char and char:FindFirstChild("HumanoidRootPart")
            if root then
                local direction=Vector3.new(-1,0,0)
                root.AssemblyLinearVelocity=direction*55+Vector3.new(0,18,0)
                task.delay(.22,function() if root.Parent then root.CFrame=CFrame.new(gateX-28,4,root.Position.Z) end end)
            end
        end
        return true
    end
    prompt.Triggered:Connect(function(plr) reject(plr,false) end)
    local touchCd={}
    gate.Touched:Connect(function(hit)
        local char=hit:FindFirstAncestorOfClass("Model") local plr=char and Players:GetPlayerFromCharacter(char)
        if not plr or touchCd[plr] then return end
        touchCd[plr]=true task.delay(1,function() touchCd[plr]=nil end)
        reject(plr,true)
    end)
end

-- Higher-rank districts stay hidden until they are unlocked.

local function wheel(model,cf)
    local w=Instance.new("Part") w.Name="Wheel" w.Shape=Enum.PartType.Cylinder w.Size=Vector3.new(2.2,1.2,2.2) w.Color=Color3.fromRGB(20,20,20) w.Material=Enum.Material.Rubber w.Anchored=true
    w.CFrame=cf*CFrame.Angles(0,0,math.rad(90)) w.Parent=model return w
end
local function makeCarModel(name,pos,kind,color)
    local m=Instance.new("Model") m.Name=name m.Parent=World
    local sizeMap={motorbike=Vector3.new(3.8,0.95,8.6), scooter=Vector3.new(3.5,0.9,7.8), tuktuk=Vector3.new(6.8,1.2,10.8), compact=Vector3.new(7.8,1.25,13.8)}
    local base=part(m,"Chassis",sizeMap[kind] or Vector3.new(8,1.2,14),pos,color,Enum.Material.Metal)
    m.PrimaryPart=base
    local function rider(offY,offZ,scale)
        scale=scale or 1
        part(m,"RiderTorso",Vector3.new(1.2*scale,1.9*scale,.9*scale),pos+Vector3.new(0,offY,offZ),Color3.fromRGB(28+math.random(0,110),55+math.random(0,120),90+math.random(0,120)),Enum.Material.SmoothPlastic)
        local head=part(m,"RiderHead",Vector3.new(.9*scale,.9*scale,.9*scale),pos+Vector3.new(0,offY+1.2*scale,offZ-.18),Color3.fromRGB(125+math.random(0,80),88+math.random(0,55),62+math.random(0,40)),Enum.Material.SmoothPlastic)
        head.Shape=Enum.PartType.Ball
        local face=Instance.new("Decal") face.Name="Face" face.Texture="rbxasset://textures/face.png" face.Face=Enum.NormalId.Front face.Parent=head
        part(m,"RiderArmL",Vector3.new(.34*scale,1.25*scale,.34*scale),pos+Vector3.new(-.78*scale,offY+.05,-1.08*scale),Color3.fromRGB(125,95,74),Enum.Material.SmoothPlastic)
        part(m,"RiderArmR",Vector3.new(.34*scale,1.25*scale,.34*scale),pos+Vector3.new(.78*scale,offY+.05,-1.08*scale),Color3.fromRGB(125,95,74),Enum.Material.SmoothPlastic)
        part(m,"RiderLegL",Vector3.new(.40*scale,1.55*scale,.40*scale),pos+Vector3.new(-.28*scale,offY-.95,0.85*scale),Color3.fromRGB(42,42,48),Enum.Material.SmoothPlastic)
        part(m,"RiderLegR",Vector3.new(.40*scale,1.55*scale,.40*scale),pos+Vector3.new(.28*scale,offY-.95,0.85*scale),Color3.fromRGB(42,42,48),Enum.Material.SmoothPlastic)
    end
    if kind=="motorbike" or kind=="scooter" then
        base.Transparency=.06
        local tankColor=(kind=="scooter") and Color3.fromRGB(228,228,228) or color
        part(m,"Seat",Vector3.new(1.8,.58,2.4),pos+Vector3.new(0,1.1,.45),Color3.fromRGB(35,35,35),Enum.Material.SmoothPlastic)
        part(m,"Tank",Vector3.new(kind=="scooter" and 2.2 or 2.0,1.35,kind=="scooter" and 2.5 or 2.0),pos+Vector3.new(0,1.5,-.2),tankColor,Enum.Material.Metal)
        part(m,"RearFrame",Vector3.new(.45,.45,3.4),pos+Vector3.new(0,.95,1.3),Color3.fromRGB(70,70,74),Enum.Material.Metal)
        part(m,"FrontForkL",Vector3.new(.28,2.9,.28),pos+Vector3.new(-.42,1.65,-2.2),Color3.fromRGB(205,205,210),Enum.Material.Metal)
        part(m,"FrontForkR",Vector3.new(.28,2.9,.28),pos+Vector3.new(.42,1.65,-2.2),Color3.fromRGB(205,205,210),Enum.Material.Metal)
        part(m,"HandleBar",Vector3.new(3.2,.22,.22),pos+Vector3.new(0,2.55,-2.22),Color3.fromRGB(45,45,48),Enum.Material.Metal)
        part(m,"HeadLight",Vector3.new(.75,.75,.58),pos+Vector3.new(0,2.05,-2.7),Color3.fromRGB(255,236,178),Enum.Material.Neon)
        part(m,"RearLight",Vector3.new(.62,.40,.38),pos+Vector3.new(0,1.18,2.72),Color3.fromRGB(255,60,60),Enum.Material.Neon)
        part(m,"Exhaust",Vector3.new(.34,.34,2.45),pos+Vector3.new(.72,.72,1.28),Color3.fromRGB(115,115,120),Enum.Material.Metal)
        rider(2.35,.25, kind=="scooter" and 1.02 or 1.08)
        wheel(m,CFrame.new(pos+Vector3.new(0,.42,-2.48)))
        wheel(m,CFrame.new(pos+Vector3.new(0,.42,2.4)))
    elseif kind=="tuktuk" then
        part(m,"Body",Vector3.new(6.4,3.4,8.8),pos+Vector3.new(0,2.2,0),Color3.fromRGB(238,196,46),Enum.Material.Metal)
        part(m,"Cabin",Vector3.new(5.6,2.3,4.6),pos+Vector3.new(0,4.0,-1.8),Color3.fromRGB(42,118,62),Enum.Material.Metal)
        part(m,"Roof",Vector3.new(6.3,.3,7.6),pos+Vector3.new(0,5.3,0),Color3.fromRGB(32,32,32),Enum.Material.Metal)
        part(m,"Wind",Vector3.new(4.8,1.8,.2),pos+Vector3.new(0,3.8,-4.0),Color3.fromRGB(140,195,220),Enum.Material.Glass).Transparency=.25
        rider(2.9,-1.2,.92)
        wheel(m,CFrame.new(pos+Vector3.new(-1.7,.55,-3.2)))
        wheel(m,CFrame.new(pos+Vector3.new(1.7,.55,-3.2)))
        wheel(m,CFrame.new(pos+Vector3.new(0,.55,3.5)))
    else -- compact car, visibly larger and faster-looking than scooters
        part(m,"LowerBody",Vector3.new(7.5,1.7,12.2),pos+Vector3.new(0,1.55,0),color,Enum.Material.Metal)
        part(m,"Hood",Vector3.new(7.1,1.0,3.4),pos+Vector3.new(0,2.45,-4.4),color,Enum.Material.Metal)
        part(m,"Trunk",Vector3.new(7.0,.9,2.8),pos+Vector3.new(0,2.35,4.7),color,Enum.Material.Metal)
        local cabin=part(m,"Cabin",Vector3.new(6.2,2.35,5.8),pos+Vector3.new(0,3.55,-.3),Color3.fromRGB(92,105,120),Enum.Material.Metal)
        local windshield=wedge(m,"Windshield",Vector3.new(5.7,1.9,2.3),pos+Vector3.new(0,3.55,-3.0),Color3.fromRGB(110,168,204),Enum.Material.Glass,Vector3.new(0,180,0)) windshield.Transparency=.2
        local rearGlass=wedge(m,"RearGlass",Vector3.new(5.5,1.7,1.9),pos+Vector3.new(0,3.45,2.7),Color3.fromRGB(110,168,204),Enum.Material.Glass,Vector3.new(0,0,0)) rearGlass.Transparency=.22
        part(m,"BumperFront",Vector3.new(7.6,.45,.45),pos+Vector3.new(0,1.15,-6.1),Color3.fromRGB(35,35,38),Enum.Material.Metal)
        part(m,"BumperRear",Vector3.new(7.5,.4,.45),pos+Vector3.new(0,1.15,6.1),Color3.fromRGB(35,35,38),Enum.Material.Metal)
        part(m,"FrontLightL",Vector3.new(1.15,.55,.28),pos+Vector3.new(-2.2,2.05,-6.15),Color3.fromRGB(255,240,185),Enum.Material.Neon)
        part(m,"FrontLightR",Vector3.new(1.15,.55,.28),pos+Vector3.new(2.2,2.05,-6.15),Color3.fromRGB(255,240,185),Enum.Material.Neon)
        part(m,"Plate",Vector3.new(2.3,.55,.12),pos+Vector3.new(0,1.55,-6.18),Color3.fromRGB(240,235,210),Enum.Material.SmoothPlastic)
        rider(3.15,-.95,1.02)
        local passHead=part(m,"PassengerHead",Vector3.new(.82,.82,.82),pos+Vector3.new(.95,3.95,-.8),Color3.fromRGB(140,103,78),Enum.Material.SmoothPlastic)
        passHead.Shape=Enum.PartType.Ball
        wheel(m,CFrame.new(pos+Vector3.new(-2.55,.72,-4.1)))
        wheel(m,CFrame.new(pos+Vector3.new(2.55,.72,-4.1)))
        wheel(m,CFrame.new(pos+Vector3.new(-2.55,.72,4.15)))
        wheel(m,CFrame.new(pos+Vector3.new(2.55,.72,4.15)))
    end
    return m
end

local traffic={}
local laneBlocks={}
local trafficLaneOffsets={-18,-6,6,18}
local function zoneHasActivePlayer(zoneIndex)
    for plr,p in pairs(profiles) do
        if plr.Parent and p and rankData(p).Zone==zoneIndex then return true end
    end
    return false
end
local function spawnTraffic(laneIndex,z,speed,zoneIndex,kind)
    local cx=zoneCenters[zoneIndex or 1]
    laneIndex=math.clamp(laneIndex or 1,1,#trafficLaneOffsets)
    local laneX=cx+trafficLaneOffsets[laneIndex]
    local bodyColor=(kind=="tuktuk" and Color3.fromRGB(238,196,46)) or (kind=="compact" and Color3.fromHSV(math.random(),.35,.78)) or Color3.fromHSV(math.random(),.55,.9)
    local model=makeCarModel("Traffic_"..kind,Vector3.new(laneX,1.35,z),kind,bodyColor) model:SetAttribute("SITZone",zoneIndex or 1)
    -- Spatial traffic horns. Only some vehicles honk so the street feels chaotic without becoming a constant wall of noise.
    if math.random() < ((zoneIndex or 1)==1 and .22 or .16) then
        local horn=Instance.new("Sound")
        horn.Name="Horn"
        horn.SoundId="rbxassetid://17737027571"
        horn.Volume=(kind=="compact" and .28) or (kind=="tuktuk" and .23) or .18
        horn.PlaybackSpeed=.90+math.random()*.18
        horn.RollOffMode=Enum.RollOffMode.InverseTapered
        horn.RollOffMinDistance=8
        horn.RollOffMaxDistance=95
        horn.Parent=model.PrimaryPart
        task.spawn(function()
            while model.Parent and horn.Parent do
                task.wait(12+math.random()*18)
                if model.Parent and horn.Parent and zoneHasActivePlayer(zoneIndex or 1) then
                    horn.PlaybackSpeed=.90+math.random()*.20
                    horn:Play()
                end
            end
        end)
    end
    local hitCooldown={}
    for _,d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then
        d.Touched:Connect(function(hit)
            local char=hit:FindFirstAncestorOfClass("Model") local plr=char and Players:GetPlayerFromCharacter(char)
            if not plr or hitCooldown[plr] then return end hitCooldown[plr]=true task.delay(1,function() hitCooldown[plr]=nil end)
            TrafficRE:FireClient(plr)
            local mission=activeMissions[plr]
            if mission then local c=math.floor((mission.potential or 0)*Config.HitCompensationPct) activeMissions[plr]=nil if c>0 then addCash(plr,c,"traffic compensation") end MissionRE:FireClient(plr,"FAILED",{Compensation=c}) end
            local root=char:FindFirstChild("HumanoidRootPart")
            if root then
                root.AssemblyLinearVelocity=Vector3.zero
                task.delay(.35,function()
                    if not plr.Parent or not char.Parent then return end
                    local p=profiles[plr] local r=char:FindFirstChild("HumanoidRootPart") local hum=char:FindFirstChildOfClass("Humanoid")
                    if p and r then
                        local rz=math.clamp(rankData(p).Zone,1,5)
                        r.AssemblyLinearVelocity=Vector3.zero
                        r.CFrame=homeSpawns[rz] or CFrame.new(zoneCenters[rz],4,280)
                        if hum then hum.Health=hum.MaxHealth end
                        UIRE:FireClient(plr,"TOAST","💥 Flattened. Back home. Try again.")
                    end
                end)
            end
        end)
    end end
    task.spawn(function()
        local minZ,maxZ=-270,235
        while model.Parent do
            local startZ=minZ
            local endZ=maxZ
            local currentSpeed=speed*(0.82+math.random()*0.36)
            local zz=startZ
            local nextShift=os.clock()+0.55+math.random()*1.05
            model:PivotTo(CFrame.lookAt(Vector3.new(laneX,1.35,startZ),Vector3.new(laneX,1.35,startZ+10)))
            while model.Parent and zz<endZ do
                if not zoneHasActivePlayer(zoneIndex or 1) then
                    task.wait(.35)
                else
                    local dt=RunService.Heartbeat:Wait()
                    if os.clock()>=nextShift then
                        currentSpeed=speed*(0.50+math.random()*1.18) -- strong random braking/acceleration, fixed lane
                        nextShift=os.clock()+0.45+math.random()*1.45
                    end
                    local blocked=false
                    local zBlocks=laneBlocks[zoneIndex or 1]
                    local block=zBlocks and zBlocks[laneIndex]
                    if block and os.clock()<block.untilTime and zz < block.z and block.z-zz < 28 then
                        currentSpeed=math.max(1.8,currentSpeed*.86)
                        if block.z-zz < 13 then blocked=true end
                    end
                    if not blocked then zz += currentSpeed*dt end
                    local pos=Vector3.new(laneX,1.35,zz)
                    model:PivotTo(CFrame.lookAt(pos,pos+Vector3.new(0,0,9)))
                end
            end
            model:PivotTo(CFrame.lookAt(Vector3.new(laneX,1.35,startZ),Vector3.new(laneX,1.35,startZ+10)))
            task.wait(math.random(1,5)/10)
        end
    end)
end

local trafficPlans={
    [1]={Count=16, Min=32, Max=46, Mix={motorbike=0.08, scooter=0.72, tuktuk=0.04, compact=0.16}},
    [2]={Count=17, Min=36, Max=50, Mix={motorbike=0.08, scooter=0.66, tuktuk=0.05, compact=0.21}},
    [3]={Count=18, Min=40, Max=56, Mix={motorbike=0.07, scooter=0.59, tuktuk=0.05, compact=0.29}},
    [4]={Count=19, Min=44, Max=62, Mix={motorbike=0.06, scooter=0.51, tuktuk=0.05, compact=0.38}},
    [5]={Count=20, Min=48, Max=68, Mix={motorbike=0.05, scooter=0.45, tuktuk=0.04, compact=0.46}},
}
local function pickKind(mix)
    local r=math.random()
    local acc=0
    for _,k in ipairs({"motorbike","scooter","tuktuk","compact"}) do
        acc += mix[k] or 0
        if r<=acc then return k end
    end
    return "motorbike"
end
for zi,cx in ipairs(zoneCenters) do
    local plan=trafficPlans[zi]
    for n=1,plan.Count do
        local lane=((n-1)%#trafficLaneOffsets)+1
        local z0=-255+math.floor((n-1)/#trafficLaneOffsets)*62+math.random(-7,7)
        local kind=pickKind(plan.Mix)
        local typeBias=(kind=="compact" and 2.45) or (kind=="motorbike" and 1.22) or (kind=="scooter" and 0.92) or 0.66
        spawnTraffic(lane,z0,math.random(plan.Min,plan.Max)*typeBias,zi,kind)
    end
end

-- Dynamic motorcycle/car crashes temporarily block one or two lanes and create short traffic jams.
local function setModelCollision(model,enabled)
    for _,d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then d.CanCollide=enabled end
    end
end
local function spawnRoadAccident(zoneIndex)
    if zoneIndex~=1 then return end
    laneBlocks[zoneIndex]=laneBlocks[zoneIndex] or {}
    local lane=math.random(1,#trafficLaneOffsets)
    local secondLane=math.clamp(lane+(math.random()<.5 and -1 or 1),1,#trafficLaneOffsets)
    if secondLane==lane then secondLane=math.clamp(lane==1 and 2 or lane-1,1,#trafficLaneOffsets) end
    local crashZ=math.random(-165,145)
    local duration=7+math.random()*5
    local untilTime=os.clock()+duration
    laneBlocks[zoneIndex][lane]={z=crashZ,untilTime=untilTime}
    laneBlocks[zoneIndex][secondLane]={z=crashZ+4,untilTime=untilTime}
    local cx=zoneCenters[zoneIndex]
    local folder=Instance.new("Model") folder.Name="TrafficAccident" folder:SetAttribute("SITZone",zoneIndex) folder.Parent=World
    local carX=cx+trafficLaneOffsets[lane]
    local bikeX=cx+trafficLaneOffsets[secondLane]
    local car=makeCarModel("CrashedCar",Vector3.new(carX,1.35,crashZ),"compact",Color3.fromRGB(122,54,42)) car.Parent=folder
    car:PivotTo(CFrame.new(carX,1.35,crashZ)*CFrame.Angles(0,math.rad(28),0))
    setModelCollision(car,true)
    local bike=makeCarModel("CrashedBike",Vector3.new(bikeX,1.35,crashZ+4),"motorbike",Color3.fromRGB(44,89,139)) bike.Parent=folder
    bike:PivotTo(CFrame.new(bikeX,1.05,crashZ+4)*CFrame.Angles(0,math.rad(-22),math.rad(68)))
    setModelCollision(bike,true)
    local smoke=Instance.new("Smoke") smoke.Name="CrashSmoke" smoke.Color=Color3.fromRGB(75,75,72) smoke.Opacity=.28 smoke.Size=6 smoke.RiseVelocity=3 smoke.Parent=car.PrimaryPart
    local hazard=part(folder,"HazardLight",Vector3.new(.7,.4,.7),Vector3.new(carX,3.1,crashZ-1.2),Color3.fromRGB(255,92,32),Enum.Material.Neon) hazard.CanCollide=false
    local horn=Instance.new("Sound") horn.SoundId="rbxassetid://17737027571" horn.Volume=.38 horn.PlaybackSpeed=.86 horn.RollOffMinDistance=8 horn.RollOffMaxDistance=105 horn.Parent=car.PrimaryPart pcall(function() horn:Play() end)
    task.spawn(function()
        local on=true
        while folder.Parent and os.clock()<untilTime do
            hazard.Transparency=on and 0 or .7 on=not on task.wait(.35)
        end
    end)
    task.delay(duration,function()
        if laneBlocks[zoneIndex] then
            local b1=laneBlocks[zoneIndex][lane] if b1 and b1.untilTime<=os.clock()+.15 then laneBlocks[zoneIndex][lane]=nil end
            local b2=laneBlocks[zoneIndex][secondLane] if b2 and b2.untilTime<=os.clock()+.15 then laneBlocks[zoneIndex][secondLane]=nil end
        end
        if folder.Parent then folder:Destroy() end
    end)
end

task.spawn(function()
    task.wait(10)
    while true do
        task.wait(20+math.random()*18)
        spawnRoadAccident(1)
    end
end)

local function clearVehicleVisual(plr)
    if vehicleVisuals[plr] then vehicleVisuals[plr]:Destroy() vehicleVisuals[plr]=nil end
end
local function weldPart(model,root,size,offset,color,shape)
    local p=Instance.new("Part") p.Size=size p.Color=color p.Material=Enum.Material.Metal p.CanCollide=false p.Massless=true p.Anchored=false p.Shape=shape or Enum.PartType.Block p.CFrame=root.CFrame*offset p.Parent=model
    local w=Instance.new("WeldConstraint") w.Part0=root w.Part1=p w.Parent=p return p
end
local function applyVehicleVisual(plr)
    clearVehicleVisual(plr) local p=profiles[plr] local char=plr.Character if not p or not char or p.Vehicle=="Feet" then return end
    local root=char:FindFirstChild("HumanoidRootPart") if not root then return end
    local m=Instance.new("Model") m.Name="Ride_"..p.Vehicle m.Parent=char vehicleVisuals[plr]=m
    if p.Vehicle=="Bicycle" then
        -- Bicycle visual disabled for stability; keep only the movement upgrade.
        m:Destroy() vehicleVisuals[plr]=nil return
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
    activeMissions[plr]={stage="drop",drop=dp,potential=base,traveled=0,lastPos=nil,item=selected.Name}
    MissionRE:FireClient(plr,"START",{Drop=dp,Item=selected.Name,Potential=base})
end
RunService.Heartbeat:Connect(function()
    for plr,m in pairs(activeMissions) do
        local root=plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
        if root then
            if m.lastPos then m.traveled+=math.min((root.Position-m.lastPos).Magnitude,12) end m.lastPos=root.Position
            if m.stage=="drop" and (root.Position-m.drop.Position).Magnitude<9 then
                local p=profiles[plr] local bonus=math.floor(m.traveled*.018*rankData(p).Mult) local reward=m.potential+bonus local xp=28
                p.TotalDeliveries+=1 activeMissions[plr]=nil
                addCash(plr,reward,"delivery") addXP(plr,xp)
                MissionRE:FireClient(plr,"COMPLETE",{Reward=reward,XP=xp,Count=p.TotalDeliveries})
                if p.TotalDeliveries==1 then UIRE:FireClient(plr,"MILESTONE",{Title="FIRST DELIVERY!",Text="Speed upgrade unlocked • go see the mechanic",Icon="🚲"})
                elseif p.TotalDeliveries==2 then UIRE:FireClient(plr,"MILESTONE",{Title="NEW CARGO",Text="Questionable Lunch contracts are now available",Icon="📦"})
                elseif p.TotalDeliveries==4 then UIRE:FireClient(plr,"MILESTONE",{Title="BUSINESS UNLOCKED",Text="The Street Broker will finally talk to you",Icon="💼"})
                elseif p.TotalDeliveries==5 then UIRE:FireClient(plr,"MILESTONE",{Title="RISKIER CARGO",Text="Cheap Parcel contracts now pay more",Icon="⚠️"})
                elseif p.TotalDeliveries==8 then UIRE:FireClient(plr,"MILESTONE",{Title="YOU'RE GETTING CLOSE",Text="4 more deliveries until the next district",Icon="🔥"}) end
            end
        end
    end
end)

local function tryRankUp(plr)
    local p=profiles[plr] if not p then return end local nr=Config.Ranks[p.Rank+1]
    if not nr then sync(plr,"Already max rank") return end
    if (nr.RebirthsRequired or 0)>p.Rebirths then sync(plr,"Need "..nr.RebirthsRequired.." rebirths") return end
    if p.TotalDeliveries<(nr.Deliveries or 0) then sync(plr,"Need "..nr.Deliveries.." total deliveries") return end
    if p.XP<nr.XP then sync(plr,"Need "..nr.XP.." XP") return end
    if p.Cash<nr.Price then sync(plr,"Need ₹"..fmt(nr.Price)) return end
    p.Cash-=nr.Price p.Rank+=1 p.Vehicle=nr.Vehicle p.OwnedVehicles[nr.Vehicle]=true applyVehicleVisual(plr)
    local hum=plr.Character and plr.Character:FindFirstChildOfClass("Humanoid") if hum then hum.WalkSpeed=Config.Vehicles[p.Vehicle].Speed end
    sync(plr,"RANK UP → "..nr.Name)
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
        local hum=plr.Character and plr.Character:FindFirstChildOfClass("Humanoid") if hum then hum.WalkSpeed=v.Speed end applyVehicleVisual(plr) sync(plr,"Equipped "..arg)
    elseif action=="BUY_BUSINESS" then
        if not p.NPCUnlocks.Broker then sync(plr,"Find the street broker first") return end
        for _,b in ipairs(Config.Businesses) do if b.Id==arg and not p.Businesses[b.Id] then
            if p.Rank<(b.RequiredRank or 1) then sync(plr,"Need rank "..b.RequiredRank) return end
            if p.Cash<b.Price then sync(plr,"Not enough cash") return end p.Cash-=b.Price p.Businesses[b.Id]=true sync(plr,"Bought "..b.Name) return
        end end
    elseif action=="REBIRTH" then
        if p.Rank<#Config.Ranks-1 then sync(plr,"Reach Business Boss first") return end local cost=1000000*(3^p.Rebirths)
        if p.Cash<cost then sync(plr,"Need ₹"..fmt(cost)) return end p.Rebirths+=1 p.Cash=0 p.XP=0 p.Rank=1 p.Vehicle="Feet" p.OwnedVehicles={Feet=true} p.Businesses={} p.TotalDeliveries=0 clearVehicleVisual(plr) sync(plr,"REBIRTH #"..p.Rebirths)

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
    plr.CharacterAdded:Connect(function(char)
        task.wait(.5) local p=profiles[plr] local hum=char:FindFirstChildOfClass("Humanoid") if hum then hum.WalkSpeed=(Config.Vehicles[p.Vehicle] or Config.Vehicles.Feet).Speed end
        local root=char:FindFirstChild("HumanoidRootPart") if root then local z=math.clamp(rankData(p).Zone,1,5) root.CFrame=homeSpawns[z] or CFrame.new(zoneCenters[z],4,280) end applyVehicleVisual(plr)
    end)
    task.delay(1.5,function() sync(plr,"Talk to NPCs to discover upgrades") end)
end)
Players.PlayerRemoving:Connect(function(plr) save(plr) clearVehicleVisual(plr) profiles[plr]=nil activeMissions[plr]=nil sessionStarts[plr]=nil sessionClaimIndex[plr]=nil remoteCooldowns[plr]=nil end)
task.spawn(function() while true do task.wait(Config.AutosaveSeconds) for plr in pairs(profiles) do save(plr) end end end)
game:BindToClose(function() for plr in pairs(profiles) do save(plr) end task.wait(1) end)
