local Config = {}

Config.GameName = "Survive India Tycoon"
Config.DataStoreName = "SIT_PlayerData_v3"
Config.AutosaveSeconds = 60
Config.StartCash = 0
Config.StartXP = 0
Config.HitCompensationPct = 0.15
Config.DailyReward = {
    {Cash=35}, {Scrap=3}, {Cash=45}, {Tokens=1}, {Cash=60, Scrap=4},
    {Cash=75}, {Skin="Rust Rat", Vehicle="Bicycle"}, {Scrap=5}, {Cash=90}, {Tokens=2},
    {Cash=110}, {Scrap=7}, {Cash=130}, {Skin="Dust Burner", Vehicle="Bicycle"}, {Tokens=3},
    {Cash=160}, {Scrap=10}, {Cash=180}, {Tokens=4}, {Cash=220, Scrap=12},
    {Skin="Blue Smoke", Vehicle="Rusty Scooter"}, {Cash=260}, {Tokens=5}, {Scrap=16}, {Cash=320},
    {Tokens=6}, {Cash=360}, {Scrap=20}, {Cash=420}, {Cash=600, Tokens=8, Scrap=24},
}
-- Session track: one reward at 10/20/30/40/50/60 minutes during the current server session.
Config.SessionRewardMinutes = {10,20,30,40,50,60}
Config.SessionRewards = {
    {Cash=30}, {Scrap=5}, {Tokens=1}, {Cash=70, Scrap=6},
    {Skin="Lane Splitter", Vehicle="Bicycle"}, {Cash=150, Tokens=3, Scrap=10},
}
-- The monthly chest only unlocks after 30 consecutive daily claims.
Config.MonthlyReward = {Cash=1200, Tokens=15, Scrap=35, Skin="Royal Chrome", Vehicle="Mega 4x4"}

-- Rank 2 is deliberately paced to take about 10+ minutes for a new player.
Config.Ranks = {
    {Name="Street Runner", XP=0, Price=0, Deliveries=0, Zone=1, Mult=1.0, Item="Suspicious Bucket", Vehicle="Feet", House="Tin Shack"},
    {Name="Courier", XP=360, Price=1400, Deliveries=12, Zone=2, Mult=1.55, Item="Cloud Puffs", Vehicle="Hoverboard", House="Concrete Room"},
    {Name="Delivery Hustler", XP=1500, Price=12000, Deliveries=35, Zone=3, Mult=3.1, Item="Food App Order", Vehicle="Rusty Scooter", House="Small Flat"},
    {Name="Trader", XP=7000, Price=90000, Deliveries=85, Zone=4, Mult=8.4, Item="Electronics Crate", Vehicle="Tuk-Tuk", House="City Apartment"},
    {Name="Business Boss", XP=35000, Price=950000, Deliveries=180, Zone=5, Mult=30.0, Item="Luxury Parcel", Vehicle="SUV", House="Villa"},
    {Name="Maharaja", XP=200000, Price=1000000000000000, Deliveries=500, Zone=5, Mult=120.0, Item="Royal Cargo", Vehicle="Mega 4x4", House="Palace", RebirthsRequired=10}
}


Config.DeliveryItems = {
    [1] = {
        {Name="Mystery Bucket", Mult=1.00, MinDeliveries=0},
        {Name="Questionable Lunch", Mult=1.16, MinDeliveries=2},
        {Name="Cheap Parcel", Mult=1.32, MinDeliveries=5},
    },
    [2] = {
        {Name="Cloud Stick Box", Mult=1.00},
        {Name="Street Snacks", Mult=1.18},
        {Name="Phone Case Bundle", Mult=1.32},
    },
    [3] = {
        {Name="Food App Order", Mult=1.00},
        {Name="Late-Night Burger Bag", Mult=1.20},
        {Name="Fragile Grocery Crate", Mult=1.38},
    },
    [4] = {
        {Name="Electronics Crate", Mult=1.00},
        {Name="Office Documents", Mult=1.24},
        {Name="Premium Phone Box", Mult=1.45},
    },
    [5] = {
        {Name="Luxury Parcel", Mult=1.00},
        {Name="Designer Shopping Bags", Mult=1.30},
        {Name="VIP Contract Case", Mult=1.58},
    },
}

Config.Vehicles = {
    Feet={Speed=16, Price=0, UnlockNPC="Mechanic"},
    Bicycle={Speed=18, Price=350, UnlockNPC="Mechanic"},
    Hoverboard={Speed=22, Price=900, UnlockNPC="Mechanic"},
    ["Rusty Scooter"]={Speed=27, Price=6500, UnlockNPC="Mechanic"},
    ["Tuk-Tuk"]={Speed=32, Price=28000, UnlockNPC="Mechanic"},
    SUV={Speed=38, Price=240000, UnlockNPC="Mechanic"},
    ["Mega 4x4"]={Speed=45, Price=1500000, UnlockNPC="Mechanic"}
}

Config.Businesses = {
    {Id="tea", Name="Chaotic Tea Stall", Price=1200, Income=4, RequiredRank=1},
    {Id="shop", Name="Tiny Corner Shop", Price=22000, Income=16, RequiredRank=2},
    {Id="delivery", Name="Delivery Kitchen", Price=170000, Income=95, RequiredRank=3},
    {Id="electronics", Name="Electronics Bazaar", Price=1100000, Income=650, RequiredRank=4},
    {Id="mall", Name="Mini Mall", Price=12000000, Income=5200, RequiredRank=5}
}

Config.Monetization = {
    Gamepasses = {DoubleCash=0, DoubleXP=0, VIPContracts=0, Premium4x4=0},
    Products = {CashSmall=0, CashBig=0, Lootbox=0, InstantBusiness=0}
}

Config.Lootbox = {
    {Weight=55, Kind="Cash", Amount=100},
    {Weight=25, Kind="Cash", Amount=500},
    {Weight=12, Kind="Cash", Amount=2500},
    {Weight=6, Kind="XP", Amount=1000},
    {Weight=2, Kind="Jackpot", Amount=25000}
}

-- =====================================================================
-- V26 WORLD LAYOUT (shared by server world builder, traffic and client)
-- Every district uses the same compact, sealed "pen":
--   west: home alley -> sidewalk | 4 lanes | sidewalk -> east: drop houses
-- The road runs along Z. Local X is measured from the district centre.
-- =====================================================================
Config.World = {
    ZoneCenters = {-400,-200,0,200,400},
    ZoneNames = {"THE SLUMS","OLD MARKET","DELIVERY DISTRICT","BUSINESS CORE","ROYAL HEIGHTS"},
    LaneWidth = 8,
    LaneOffsets = {-12,-4,4,12},     -- lane centres (local X)
    LaneDirections = {-1,-1,1,1},    -- -1 = travels toward -Z, 1 = toward +Z (keep-left traffic)
    RoadHalfWidth = 16,              -- asphalt from -16 to +16
    SidewalkOuter = 22,              -- sidewalks from +-16 to +-22
    PenHalfLength = 110,             -- walkable Z range is -110..110 (sealed ends)
    AlleyHalfWidth = 6,              -- home alley opening in the west row (Z -6..6)
    AlleyBackX = -37,                -- alley runs from X -22 to -37
    HomeBackX = -51,                 -- starter room interior X -51..-37, Z -9..9
    HomeHalfWidth = 9,
    HomeSpawnBack = 5.5,             -- spawn this far in front of the room's back wall...
    HomeSpawnZ = -0.8,               -- ...slightly left of centre, facing the open front (+X)
    TrafficHalfLength = 175,         -- vehicles live on Z -175..175 (spawn/despawn inside the end tunnels)
    BoundsHeight = 60,               -- invisible walls are far higher than any jump
}

Config.Traffic = {
    SnapshotRate = 0.1,              -- seconds between server snapshots
    MaxVehiclesPerZone = 48,
    SpeedRerollMin = 0.8, SpeedRerollMax = 2.5,
    -- Speed hierarchy (studs/s): tuk-tuk < scooter < motorbike < car. Player walks at 16.
    Kinds = {
        tuktuk    = {Speed={15,22}, Accel=9,  HalfWidth=2.7, Length=8.6,  Top=6.4, Gap={10,22}},
        scooter   = {Speed={23,34}, Accel=16, HalfWidth=1.35,Length=5.6,  Top=5.0, Gap={6,16}},
        motorbike = {Speed={36,50}, Accel=28, HalfWidth=1.45,Length=6.2,  Top=5.0, Gap={8,20}},
        car       = {Speed={54,80}, Accel=26, HalfWidth=3.3, Length=12.0, Top=5.4, Gap={14,30}, BurstChance=0.14, BurstSpeed={98,118}},
    },
    -- Lanes have roles. The two kerb lanes are dense, slow scooter/tuk-tuk streams; the two
    -- inner lanes are sparser fast lanes where cars and motorbikes actually get to speed
    -- (no lane changes, so mixing many scooters into them would pin every car at scooter pace).
    -- Measured over 15 simulated minutes: ~58% scooters, 14% motorbikes, 6% tuk-tuks, 22% cars.
    OuterMix = {scooter=0.86, tuktuk=0.10, motorbike=0.04},
    InnerMix = {scooter=0.10, motorbike=0.28, car=0.62},
    -- Extra spacing between spawned vehicles (studs), before the per-kind gap.
    SpawnSpacing = {Outer={3,16}, Inner={40,95}},
    ZoneSpeedScale = {1.0,1.07,1.14,1.2,1.26},
    ZoneDensityScale = {1.0,0.95,0.9,0.86,0.82},
    Accident = {IntervalMin=25, IntervalMax=50, DurationMin=6, DurationMax=12, FirstDelay=18},
    HornSoundId = "rbxassetid://17737027571", -- the horn used by earlier builds
}

return Config
