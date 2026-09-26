# MERGE NOTES — world branch (V29 WORLD)

Base: V28 prototype (commit b4110cc). The branch was built to merge alongside the parallel
systems branch with as few conflicts as possible.

## Files NOT touched (merge boundary)

- `src/ServerScriptService/Main/init.server.lua` (Main): unchanged
- `src/StarterPlayer/StarterPlayerScripts/Client.client.lua`: unchanged
- `src/ReplicatedStorage/Shared/Config.lua`: unchanged. **No Config key was added, removed or
  changed.** Shared world constants live in the new `Shared/WorldLayout.lua`.
- No remote was added, renamed or removed. No profile/DataStore field was touched.

## New files

| File | Role |
|---|---|
| `src/ReplicatedStorage/Shared/WorldLayout.lua` | Shared world constants + deterministic hazard functions (river planks, cranes, lasers, fountains), `hazardKind(zone)`, `HitIds`, `isDanger(...)` used by both client and server |
| `src/ServerScriptService/Main/WorldKit.lua` | Part/sign/geometry helpers shared by the world modules |
| `src/ServerScriptService/Main/ZoneStyles.lua` | Per-zone building variants (2 haveli/bazaar/tall house, 3 mid-rise/shutters/cloud kitchen, 4 glass tower/stepped office/plaza, 5 palace wing/marble villa/gateway), zone landmarks (Grand Palace), rank homes |
| `src/ServerScriptService/Main/HazardBuilder.lua` | Static median geometry for each zone's hazard (river bed/banks/bamboo rail, train rails+signals, crane masts, laser pylons, fountain floor) |
| `src/ServerScriptService/Main/WorldConnectors.lua` | Serpentine road arcs joining the tunnels of neighbouring districts, exit roads, transition belts (slum hill, metro viaduct, expressway, palace hill), end ridges |
| `src/ServerScriptService/Main/WorldHooks.lua` | Hook models only: `CrateKiosk_Z1..Z5`, `SpecialContractBoard_Z1..Z5`, `BlackMarketContract_Z2`, `RoyalGarage_Z5`, parody cameos, collectible templates |
| `src/StarterPlayer/StarterPlayerScripts/HazardClient.client.lua` | Renders the moving hazard of the player's current district and reports hits |

## Modified files

| File | Change |
|---|---|
| `src/ServerScriptService/Main/WorldBuilder.lua` | Requires the new modules; road split around the river in zone 1; median built by HazardBuilder (inline rail code moved out); ground tiles leave a gap for the river channel; zone 1 west shack replaced by the crate kiosk; zones 2-5 use ZoneStyles buildings/homes; hooks, cameos, connectors; `simpleBlock` / `buildSimpleHome` removed (superseded by ZoneStyles) |
| `src/ServerScriptService/Main/TrafficServer.lua` | Train only scheduled in zones where `hazardKind == "train"` (zone 2); new server validation branch for hazard hit ids |
| `src/ReplicatedStorage/Shared/VehicleFactory.lua` | New collectible model builders + `VehicleFactory.Collectibles` list; existing builders unchanged |
| `tools/make_harness.py` | Auto-loads every Shared / Main module and client script |
| `tools/verify_world.py` | Corridor-only climbable check |
| `tools/render_preview.py` | Free camera views (`cam=name:x,y,z:tx,ty,tz:fov`) |
| `tools/run_checks.sh` | Builds `builds/Survive_India_Tycoon_V29_WORLD.rbxlx` |
| `tools/tests/integration.lua` | Train test moved to zone 2; river fall test; forged-hazard rejection; hazard safe/danger timing |
| `tools/tests/scene_dump.lua` | Runs HazardClient and dumps its parts |

## Behaviour contracts for the systems branch

- **TrafficHit remote (unchanged name/signature):** `FireServer(id)`. Positive = vehicle, `-1` = train
  (as before), plus new negative ids: `-2` river, `-3` crane, `-4` laser, `-5` fountain. The
  server ignores an id that is not the current district's hazard and re-checks it with
  `WorldLayout.isDanger` at the server time (0–0.6 s back, 1.5 stud slack). A valid hit calls
  the same `onHit` callback as vehicles (parcel broken / debt / respawn, unchanged in Main).
- **Hazard per district:** 1 river crossing (replaces the train there), 2 train (unchanged
  behaviour, moved from zone 1), 3 swinging crane loads, 4 laser fence wave, 5 fountain jets.
  `Config.Train` is still used, now for zone 2.
- **Hook contract:** every hook model has attributes `Hook` (e.g. `"CrateKiosk"`,
  `"SpecialContract"`, `"BlackMarketContract"`, `"RoyalGarage"`) and `Zone`, and contains an
  `Attachment` named `PromptAnchor` where the systems branch should parent its
  ProximityPrompt. No prompts or logic are created by this branch.
- **Collectible templates:** `ReplicatedStorage.SIT_CollectibleTemplates` holds one Model per
  entry of `VehicleFactory.Collectibles` (`Id`, `Name`, `Rarity`): Skybike MK2, Gold Tuk-Tuk,
  Courier Jetboard, Neon Delivery Drone, Armored SUV, Hypercar X, Royal Convoy, Flying Maharaja
  Throne. They are display models; the systems branch decides how they are unlocked and ridden.
- **BlackMarketContract_Z2 is a placeholder for a skill-based high-risk delivery.** Its `Note`
  attribute says so explicitly. There is no casino, wager, random paid reward or currency/item
  stake anywhere in this branch. The crates at the kiosks are decorative models; if the systems
  branch ever makes them purchasable, it must follow Roblox's paid random item rules (disclose odds).
- **Parody cameos** are original characters (Chai-Fluencer Rinku, Mr. Moneybags, Superstar Dhamaka
  Dev, Captain Sixer, DJ Masala Queen): blocky NPC models with name boards, no real faces,
  names or logos.
- **Visibility:** zone content keeps the `SITZone` attribute (Client hides zones above your rank).
  The `Connectors` folder has no `SITZone`, so the skyline is visible to everyone.
- **River:** respectful, Ganges-inspired (lotus pads, boats, bamboo rails), no religious
  imagery or mockery.

## Performance notes

- Decorative parts are anchored with CanTouch/CanQuery off (WorldKit defaults).
- Moving hazards are only built on the client for the district the player is in, and are
  moved with `BulkMoveTo` or property toggles; nothing is spawned per frame.
- Server work for hazards is pure math on hit reports; no hazard simulation on the server.
- Total generated world: ~4.7k parts across 5 districts + connectors (headless count).

## Verification status

- Verified headless (Luau CLI + Roblox API mock), all passing via `tools/run_checks.sh`:
  compile, world geometry (containment, no bypass, visible geometry closes every block except
  the tunnel mouths, 0 failures), traffic simulation, server+client integration (including
  the new hazard tests), test mode, rbxlx build + XML round trip.
- **NOT verified in Roblox Studio.** No runtime screenshots: the two previews in
  `docs/previews/10_*` and `11_*` come from the offline numpy ray-caster, not Roblox's
  renderer. Materials, lighting, physics feel on the moving planks, and performance on
  devices still need a Studio playtest.
