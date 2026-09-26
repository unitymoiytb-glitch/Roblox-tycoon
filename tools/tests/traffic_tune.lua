-- Compares lane-mix settings: how fast do cars actually move inside the walkable stretch?
SIT.mount()
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Shared.Config)
local TrafficSim = require(RS.Shared.TrafficSim)
Config.Traffic.MaxVehiclesPerZone = 48
local variants = {
    {name = "D", outer = {scooter = 0.86, tuktuk = 0.10, motorbike = 0.04}, inner = {scooter = 0.10, motorbike = 0.28, car = 0.62}, so = {3, 16}, si = {40, 95}},
    {name = "E", outer = {scooter = 0.84, tuktuk = 0.12, motorbike = 0.04}, inner = {scooter = 0.10, motorbike = 0.30, car = 0.60}, so = {4, 18}, si = {36, 90}},
    {name = "lane roles A", outer = {scooter = 0.84, tuktuk = 0.11, motorbike = 0.05}, inner = {scooter = 0.08, motorbike = 0.37, car = 0.55}, so = {6, 24}, si = {34, 86}},
    {name = "lane roles B", outer = {scooter = 0.86, tuktuk = 0.10, motorbike = 0.04}, inner = {scooter = 0.12, motorbike = 0.33, car = 0.55}, so = {4, 18}, si = {30, 80}},
    {name = "lane roles C", outer = {scooter = 0.85, tuktuk = 0.11, motorbike = 0.04}, inner = {scooter = 0.10, motorbike = 0.30, car = 0.60}, so = {5, 20}, si = {40, 95}},
    {name = "current", outer = Config.Traffic.OuterMix, inner = Config.Traffic.InnerMix},
    {name = "fewer inner scooters", outer = {scooter = 0.86, tuktuk = 0.10, motorbike = 0.04}, inner = {scooter = 0.30, motorbike = 0.25, car = 0.45}},
    {name = "no inner scooters", outer = {scooter = 0.84, tuktuk = 0.12, motorbike = 0.04}, inner = {scooter = 0.0, motorbike = 0.40, car = 0.60}},
}
for _, var in ipairs(variants) do
    Config.Traffic.OuterMix, Config.Traffic.InnerMix = var.outer, var.inner
    if var.so then Config.Traffic.SpawnSpacing = {Outer = var.so, Inner = var.si} end
    local sim = TrafficSim.new(Config, 1, 99)
    sim:populate()
    local carSpeeds, kinds, seen = {}, {}, {}
    for step = 1, 60 * 60 * 6 do
        sim:step(1 / 60, {0})
        if step % 10 == 0 then
            for _, lane in ipairs(sim.lanes) do
                for _, v in ipairs(lane.vehicles) do
                    if not seen[v.id .. v.kind] then seen[v.id .. v.kind] = true kinds[v.kind] = (kinds[v.kind] or 0) + 1 end
                    if v.kind == "car" and not v.crashed and math.abs(sim:laneZ(lane, v.s)) < 110 then table.insert(carSpeeds, v.v) end
                end
            end
        end
    end
    table.sort(carSpeeds)
    local fast = 0 for _, s in ipairs(carSpeeds) do if s > 65 then fast += 1 end end
    local tot = 0 for _, n in pairs(kinds) do tot += n end
    print(string.format("%-22s car p50 %.0f p90 %.0f, >65 %.0f%% | mix sc %.0f%% moto %.0f%% tuk %.0f%% car %.0f%% | peak count %d",
        var.name, carSpeeds[math.floor(#carSpeeds * 0.5)], carSpeeds[math.floor(#carSpeeds * 0.9)], 100 * fast / #carSpeeds,
        100 * (kinds.scooter or 0) / tot, 100 * (kinds.motorbike or 0) / tot, 100 * (kinds.tuktuk or 0) / tot, 100 * (kinds.car or 0) / tot, sim.count))
end
