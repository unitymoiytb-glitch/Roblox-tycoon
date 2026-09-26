# Survive India Tycoon

Roblox delivery / progression tycoon. Start broke in a tin shack, take jobs from Raju,
cross dangerous traffic to deliver, earn ₹ + XP, buy mobility and businesses, rank up
(Street Runner → Courier → Delivery Hustler → Trader → Business Boss → Maharaja).

**Current build:** `builds/Survive_India_Tycoon_V26_1_RAGS_MUSIC.rbxlx`. Open it in Roblox Studio and press Play.
The world is generated at runtime by `ServerScriptService/Main`, so edit mode shows only the spawn.

See [CHANGELOG.md](CHANGELOG.md) for what changed in V26 and what was / was not verified.

## Source layout (Rojo conventions, `default.project.json`)

```
src/ReplicatedStorage/Shared/
  Config.lua            ranks, economy, rewards + V26 World/Traffic tuning
  TrafficSim.lua        pure traffic simulation (lanes, speeds, following, accidents, snapshots)
  VehicleFactory.lua    lightweight scooter / motorbike / tuk-tuk / car models
src/ServerScriptService/Main/
  init.server.lua       game systems: profiles, DataStore fallback, missions, NPCs, rank gates, shop
  PlayerLook.lua        rank-1 street-rags skin + overhead role title
  WorldBuilder.lua      generates workspace.SIT_World (districts, starter shack, GameplayBounds)
  TrafficServer.lua     steps one TrafficSim per occupied district, sends snapshots, validates hits
src/StarterPlayer/StarterPlayerScripts/
  Client.client.lua        HUD, menus, guides, spawn intro camera
  TrafficClient.client.lua renders traffic, client-side hit detection, horns
```

## Build and check

```
# Needs python3 and the luau CLI (https://github.com/luau-lang/luau/releases).
LUAU_BIN=/path/to/luau-folder tools/run_checks.sh
```

This compiles every script, runs the headless tests against a Roblox API mock
(`tools/mock/roblox_mock.lua`), runs the geometric bypass verifier, then builds and validates
the `.rbxlx`. Validation means XML-escaping every script, re-parsing the file with ElementTree
and comparing each script with `src/` byte for byte.

| Tool | Purpose |
| --- | --- |
| `tools/build_rbxlx.py` | build + validate the place file |
| `tools/verify_world.py` | flood-fills every district: containment, no traffic bypass, reachability, clear exit path |
| `tools/tests/traffic_sim.lua` | 15 simulated minutes: overlaps, mix, speed hierarchy, accidents, snapshot size |
| `tools/tests/integration.lua` | server + both client scripts together: delivery, hit and respawn, accident rendering |
| `tools/tests/crossing_agent.lua` | playability probe: simulated careful and impatient crossings |
| `tools/render_preview.py` | approximate ray-traced previews of camera views (not Roblox's renderer) |
