# CHANGELOG

## V29 WORLD (world branch)

See [MERGE_NOTES.md](MERGE_NOTES.md) for the full per-file list and the contracts for the
systems branch. Main, Client and Config are **unchanged**; no remotes or profile data changed.

- **One continuous city:**
  - the 5 districts are connected by a serpentine road (curved arcs between the tunnels)
  - transition belts that block sightlines and preview the next district: slum hill with a
    water tower, a metro viaduct, an expressway with glass towers, a terraced palace hill
  - ridges at both ends of the city
- **Visual progression:** new building variants per district.
  - 2: havelis, bazaar, tall houses
  - 3: mid-rises, shutter rows, cloud kitchen
  - 4: glass towers, stepped offices, plaza
  - 5: palace wings, marble villas, gateway, and a Grand Palace landmark
- **Homes evolve with rank:** Tin Shack → Concrete Room → Small Flat → City Apartment →
  Palace Suite (same footprint, new interior, alley dressing, sign).
- **One hazard per district** in the median, deterministic from server time; the client
  renders it and the server re-validates hits:
  - 1: river crossing on bobbing, tilting and sinking planks (replaces the train). Falling
    in counts as a hit.
  - 2: the train (moved from district 1, same behaviour)
  - 3: tower cranes swinging loads
  - 4: laser fence wave (on / warning / off)
  - 5: fountain jets (bubbling warning, then eruption)
- **Hook models only (no logic):**
  - `CrateKiosk_Z1..Z5`, `SpecialContractBoard_Z1..Z5`, `BlackMarketContract_Z2` (placeholder
    for a skill-based delivery; no gambling or wagers), `RoyalGarage_Z5`
  - each carries `Hook`/`Zone` attributes and a `PromptAnchor` attachment
- **Collectible models:** Skybike MK2, Gold Tuk-Tuk, Courier Jetboard, Neon Delivery Drone,
  Armored SUV, Hypercar X, Royal Convoy, Flying Maharaja Throne.
  - shown in the kiosks
  - templates in `ReplicatedStorage.SIT_CollectibleTemplates`
- **Parody cameos** (original characters, no real faces): Chai-Fluencer Rinku,
  Mr. Moneybags, Superstar Dhamaka Dev, Captain Sixer, DJ Masala Queen.
- **Verified offline:** `tools/run_checks.sh` passes in full.
  - geometry: 0 failures, including "visible geometry closes every block except the tunnels"
  - traffic
  - integration, with the new tests: train in zone 2, river fall → respawn, forged hazard
    hit rejected, each hazard alternates safe and dangerous
  - test mode
  - rbxlx build with XML round trip
- **Not verified in Studio:**
  - no Roblox screenshots; previews 10 and 11 come from the offline renderer
  - still to test in Studio: physics feel on the moving planks, lighting and materials,
    performance on mobile

## V28 PROTOTYPE

- **Levels 2x longer:** the walkable road goes from 220 to 440 studs, and traffic runs over
  570 studs.
  - District 1 gets 14 extra buildings on the home side and 11 extra on the delivery side.
  - 8 drop points instead of 6, spread over ±196 (was ±94), so deliveries mean real distance.
  - 4 extra sidewalk barricades, more mud patches, and more poles, wires and background
    buildings.
  - The other districts are extended the same way.
  - Each player only receives the vehicles within 190 studs (packets stay under the
    UnreliableRemoteEvent limit), with a cap of 80 vehicles per district.
- **Every vehicle is modelled and ridden:**
  - scooter (rusty, or blue with the Blue Smoke skin), tuk-tuk, SUV and Mega 4x4 (bigger
    wheels, light bar, bull bar, chrome with Royal Chrome)
  - these reuse the traffic models, welded and scaled under the player; windows are
    see-through so you can see the driver
  - glowing hoverboard with thrusters
  - `VehicleRider.client.lua` (replaces BikeRider) poses the body: pedalling, seated on a
    scooter, hands on the wheel, or surf stance on the hoverboard
  - each vehicle has its own jump power; traffic hits account for the vehicle's width
- **Brown rain:** 1 minute every 15 minutes (first shower 2 min after the server starts).
  - Brown streaks around the camera, a darker, muddy sky, and a banner showing the time left.
  - **Slippery ground:** your movement follows your input with a lag (slow starts, drifting
    turns, you keep sliding when you let go), on foot and on every vehicle.
  - **Orders placed during the rain pay x3.**
  - Tuning in `Config.Weather`.
- **Classic economy:** test mode is off.
  - Raju pays 100% of the order again (no cut); broken-parcel debt is still there.
  - Old vehicle prices and rank thresholds.
- **Horns ÷2:** random interval 7–17 s (was 3.5–8.5), stuck vehicles honk half as often,
  at least 1.8 s between horns, one horn per accident instead of two.
- **Music:** ID 106840103375464 removed at your request. It's now a playlist
  (`Config.Music.SoundIds`) with shuffle and crossfade.
  - I don't provide any IDs: Roblox is unreachable from my environment, so I can't check
    any, and I won't invent them.
  - Fill it from Toolbox > Audio ("sitar", "bollywood", "tabla"…).
- **Verified offline:**
  - geometry of all 5 districts (containment, no bypass without crossing, the 8 drops
    reachable)
  - 15 min of traffic
  - integration: every vehicle modelled with its pose, speed and width; rain starts at
    120 s, x3 order (₹165 vs ₹55), rain stops after 60 s; train; debt; rich customers
  - test mode (enabled only by the test)
- **Needs Studio testing:**
  - the rendering of the ride poses and the scale of the vehicles on real avatars
  - the feel of the rain slide (it depends on the PlayerModule; tune `Traction`)
  - performance: district 1 is now ~1,170 parts

## V27.1 TEST MODE + MUSIC DIAGNOSTICS

- **Test mode** (`Config.TestMode`, on in this build; set `Enabled = false` before publishing):
  - each paid delivery promotes you straight to the next rank, for free, all the way to
    Maharaja (5 deliveries), with a teleport to the matching district
  - Raju pays 100% of the order
  - a broken parcel costs no debt
  - you start with ₹500, enough for the bicycle
- **Music:** the IDs live in `Config.Music.SoundIds` (volume 0.4). The client preloads the
  sound and waits for it to load.
  - If Roblox refuses the asset (not public, not owned by the game's owner, or not shared
    with the experience), the reason goes to the Output and a "🔇 Music blocked by Roblox"
    message appears on screen.
  - No new ID was invented.
- **Verified offline:** `tools/tests/testmode.lua` (5 deliveries → Maharaja, full payment,
  teleport to district 5), and the full suite with the normal economy still green.
  **Not verified:** whether ID 106840103375464 is playable for your account.

## V27 TRAIN + BIKE + DEBT

**Not done, deliberately:** the customers are *not* a "higher caste". Using caste (a real,
living system of discrimination) as a game mechanic is excluded by the project's own rules.
Customers are **rich, snobbish people** who look down on you because you're poor, and the
gameplay (humiliation, no payment) is otherwise identical.

- **Train:** a railway replaces the median between the two carriageways (a 12-stud-wide
  corridor with ballast, sleepers, rails and yellow kerbs).
  - About every 35–70 s a commuter train (locomotive + 6 coaches, ~120 studs, 155–200
    studs/s) crosses the whole block in ~2 s. There are people riding on the roof (18) and
    hanging out of the doors.
  - 4 s before it arrives, 4 red signals flash and a deep horn sounds from the signal nearest
    to you, then the locomotive horn.
  - The train kills anyone between its rails, jumping included. The corridor is otherwise
    safe from cars.
  - Rendering: the server sends only a timetable; every client computes the position from
    server time (smooth, zero replication), with swept hit detection that the server
    re-checks.
- **Delivery flow:**
  - You carry the parcel to a **rich customer** who appears at their door (6 profiles: Rich
    Customer, Snobby Landlord, Spoiled Rich Kid, Posh Aunty, Gold-Chain Uncle, Impatient
    Boss; sunglasses, gold chain, watch).
  - They take the parcel, **insult you** (10 lines about your poverty and your dirt) and
    **don't pay**.
  - You have to go back to Raju: he pays **70% of the order value** (`Config.Delivery.PlayerShare`).
- **Broken parcel = debt:** hit by a vehicle or the train *while carrying the parcel* →
  "YOU BROKE THE …" dialog → a debt of 40% of the order value to Raju → back to your room.
  - The debt shows in red in the HUD and is deducted from the next payouts.
  - A hit *on the way back* costs nothing: Raju still owes you the payment.
  - Rebirth wipes the debt.
- **Bicycle:**
  - A real welded Indian delivery bike, visible to everyone: wheels, rusted frame,
    handlebar, saddle, pedals, rear rack with a parcel, basket and a light.
  - **Speed 26** (was 18; walking is 16) and a **jump of 60** (bunny hop).
  - `BikeRider.client.lua` stops the walk animation and poses the R15 body: seated,
    pedalling in rhythm with speed (legs still in the air), hands on the handlebar.
  - The other vehicles' speeds were shifted to keep the progression (Hoverboard 28,
    Scooter 31…).
- **Music:** `rbxassetid://106840103375464` (already in place since V26.1). The YouTube link
  can't be used directly in Roblox; the audio has to be uploaded to Roblox.
- "SHARMA KIRANA STORE" renamed to "LUCKY KIRANA STORE" (Sharma is a caste-marked surname).
- **Verified offline (mock integration):**
  - customer at the door, insult with no payment, return to Raju, partial payment
    (₹38 on a ₹55 order)
  - hit while carrying → ₹22 debt → next payout deducted
  - bike bought, 22 visible parts, speed and jump applied
  - a train scheduled at 197 studs/s: signals flash, it is rendered with 18 roof riders,
    and a player on the rails gets hit and sent home
  - geometry of all 5 districts OK with the new road
- **Needs Studio testing:**
  - the visual quality of the bike pedalling (Motor6D.Transform override; R15 only, R6 players
    get the bike without the pose)
  - the feel of the train's speed
  - the economy (70% share + debt slows the first rank; tune `Config.Delivery`)

## V26.1 RAGS + MUSIC

- **Background music** is now `rbxassetid://106840103375464`, in `Client.client.lua` at volume 0.2.
- **Starting skin (rank 1):** new module `ServerScriptService/Main/PlayerLook.lua`.
  - The avatar's Shirt, Pants and T-shirt are stored away. The torso is recoloured as a
    sweat-stained vest and the legs as mud-brown trousers, in Fabric material.
  - 11 welded, non-colliding details: stains, a rip showing skin on the chest and the knee, a
    sewn-on patch, back grime, a ragged hem, a mud splash, a frayed cuff and bare dirty feet.
  - The player's skin colour is never changed. No clothing asset IDs are used.
- **Title above the player:** "LESS THAN NOTHING" (rank 1 `Title`, set in `Config.Ranks`), with
  the player's name below. Roblox's default overhead name is hidden.
  - After a promotion the rags come off, the avatar's own clothes return, and the title shows
    the rank name (e.g. "COURIER"). Rebirth puts the rags back on. No respawn is needed.
- **Verified:** the mock integration test checks the title, the rags, that skin is untouched,
  and the rank-2 restore and rank-1 reapply. **Not verified:** how it looks on real R15/R6
  avatars in Studio, and whether the music asset plays.

## V26 POLISHED_START (from V25 CHAOS_POLISH)

**Inputs:** only `Survive_India_Tycoon_V25_CHAOS_POLISH.rbxlx` was supplied. The source zip,
the starter-house reference image and the screenshot were not in the session. The V25 sources
were extracted from the `.rbxlx` (committed as the baseline), and the starter room was built
from the written description of the reference.

### Root causes found in V25
- **Traffic bypass:** the road was 122 studs wide, but traffic only used the 4 lanes at ±18, so
  ~37 studs of empty asphalt on each side was a safe walkway. The drop points (±29) sat inside
  that safe strip, so half of all deliveries never needed to cross a lane.
- Traffic only ran z −270…235, but the walls were at ±309. The home, hub and vendor all sat in
  that traffic-free end zone, so the road could be crossed at z > 235 with no risk.
- The side walls at ±71.2 also cut off the Broker (x −495) and the zone-1 promotion guard
  (x −312). **Rank-up was unreachable.**
- **Ugly spawn:** a 28×24 box with slab props. The camera script assumed a −Z exit.
- **Lag:** ~90 vehicles (1,731 parts) were moved server-side with `PivotTo`, one coroutine per
  vehicle on `Heartbeat:Wait()`. Every vehicle part had its own `Touched` handler. All 2,845 world
  parts were `CanTouch`, 515 were Neon and 183 were semi-transparent. The client re-walked every
  world descendant on each cash `SYNC`.

### STARTER HOUSE
- Rebuilt as one compact 14×18 open-front lean-to (89 parts) in `WorldBuilder.buildStarterHome`:
  - **Structure:** timber frame (posts, girts, rafters, lintel) and overlapping rusted
    corrugated sheets with a blue tarp and a reclaimed-board panel. The uneven 3-sheet roof has a
    light gap and a tyre and brick weighing it down.
  - **Bed (mid-left):** a pallet, a mattress with rolled edges, two stains, a thin pillow, a
    dirty blanket draped over the edge, and sandals.
  - **Cooking (front-right):** a brick chulha with glowing embers (small light), a black pot,
    a pan, firewood, an oil can, a bottle, a tin and soot on the wall.
  - **Storage (back-right):** a crate, a sack, a shelf with jars, a tin and folded clothes, plus
    a calendar.
  - **Washing:** a bucket, a steel basin and a jerrycan.
  - **Atmosphere:** laundry along the left wall, one bare bulb with a warm shadow-casting
    PointLight, wiring to the street pole, one puddle and two bits of litter.
  - **Outside:** a muddy apron, a puddle, an old tyre, a bucket and a crate.
- The player spawns inside, facing the open front. The central exit path is collision-free
  (verified).
- The place's SpawnLocation is invisible inside the room, facing the exit, so the first frame is
  already right.
- The intro camera is a 2.5 s pan. It opens on the room (bed, bulb, laundry, exit on the
  right) and eases to an over-the-shoulder view down the alley to the road. It releases
  immediately if the player walks off.

### WORLD LAYOUT
- Each district is now one compact, sealed block:
  `room → 14-stud alley → Raju → sidewalk | 2 lanes | median | 2 lanes | sidewalk → drop houses`.
  The road is 34.4 studs wide (V25: 122). Nothing is a long empty walk.
- District 1 has 8 west-row structures and 11 east-row structures plus compound walls
  (tea stall, garage, broker office, stalls, drop shacks, two-storey houses and a landmark
  shop). All share the same rusted-tin, timber and cloth language, with varied heights and
  roofs. Distant hazy blocks, trees, wires and poles add depth.
- The **delivery drops are glowing pads on the far sidewalk**, so every delivery crosses the
  road there and back. Drops glow locally only while targeted.
- The Mechanic and Broker stand at their shopfronts on the home sidewalk in every district,
  so upgrades stay reachable after rank-ups. The promotion guard stands at a closed gate on the
  far side. Rank-up now teleports you to the next district's home; rebirth returns you home.
- Districts 2–5 use the same sealed footprint with lighter concrete buildings (~160 parts each).
- Lighting: `Technology = Future` is set in the place file and the interior ambient is darker,
  so the bulb reads. The Baseplate was removed (it z-fought the generated ground).
- HUD: a slimmer, centred top bar, a smaller Server Master label and a more transparent left
  panel. Zone visibility now updates only when the rank changes. The rank-1 progress hint is no
  longer overwritten.

### TRAFFIC
- There are 4 lanes of 8 studs (two each way, keep-left) around a raised median. Vehicles never
  change lanes; each keeps a small fixed offset inside its lane.
- **Lane roles:**
  - The kerb lanes are dense scooter and tuk-tuk streams.
  - The inner lanes are sparser fast lanes for cars and motorbikes. Without lane changes,
    scooters in those lanes would pin every car to scooter pace (measured median car speed was
    28 before this fix).
- Measured mix: **~60% scooters, 13% motorbikes, 7% tuk-tuks, 20% cars**.
- **Speed hierarchy** (free-flow means, studs/s; the player walks at 16):
  tuk-tuk 18 < scooter 24 < motorbike 44 < car 66.
  - About 14% of car speed re-rolls are bursts of 98–118.
  - Each vehicle re-rolls its target speed every 0.8–2.5 s and eases toward it (no jitter).
  - Vehicles follow the one ahead and never overlap, which creates natural queues and braking.
- Traffic runs z ±175. The pen is sealed at ±110, and vehicles spawn and despawn inside dark end
  tunnels, so **there is no traffic-free end zone**.
- The median centre is mathematically outside every vehicle's hit reach, so it is a readable
  halfway refuge. Every other spot on the asphalt, including lane lines, can be hit.
- **Crossing probe** (simulated players): a patient crossing takes a median ~10 s with ~2% hits.
  Rushing the second lane takes ~3.5 s with ~40% hits.
- **Horns:** at most 4 Sound objects exist in total, reused. They play spatially (RollOff
  10–130) with per-vehicle pitch, roughly one ambient horn every 3.5–8.5 s, plus occasional
  honks from blocked vehicles and after crashes. They use the V25 asset `rbxassetid://17737027571`;
  no new asset IDs were invented.

### ACCIDENTS
- The accidents are staged, with no physics simulation. Every 25–50 s (first after 18 s), a
  moving vehicle near a player crashes: it slides to a stop angled across its lane, and 2-wheelers
  fall over.
  - ~50% of crashes are side impacts with a vehicle in the neighbouring lane, blocking 2 lanes.
  - ~30% are rear-end pile-ups.
- Following traffic brakes and queues behind the wreck, and adjacent lanes slow down to pass it.
- On the client, a wreck smokes and blinks its hazard indicators. Stopped wrecks and stopped
  queues become solid obstacles, so they change your path and can shelter you. A couple of
  angry horns sound.
- Wrecks clear after 6–12 s and traffic resumes. They never accumulate (15-minute test: 25
  accidents, all cleared, max age 11.8 s).

### BOUNDARIES
- **Visual layer:** everything that visually closes the block also collides:
  - shopfront counters, tin fronts with doors, and a compound wall
  - a gate grille and alley shack walls
  - sidewalk barricades (a cart, crates and a tin sheet)
  - median planters and fences
  - tunnel buildings with "NO PEDESTRIANS" boards
  
  A flood fill using only visible geometry stays inside the block everywhere except the two
  tunnel mouths, which the invisible walls close.
- **GameplayBounds** (one folder per district, 66 parts in total): 60-stud-tall invisible walls
  (`CanCollide`, not `CanQuery`/`CanTouch`, so the camera ignores them). They trace the exact
  edge of the walkable space: both sidewalks, the alley and the home room, with the road ends
  sealed.
  - Sidewalk barricades (±48 west, −41/+42 east) and median blockers (±45) each have their own
    60-stud blocker, so walking along a sidewalk means stepping into a live lane.
- **Proof (all 5 districts):**
  - flood fill with a 0.45-stud character radius and 0.25-stud grid
  - bounds only: reachable ⊆ designed corridor, and the map edge is never reached
  - with the lanes treated as lethal, **no drop point and no far-side cell is reachable**
  - every drop and every NPC prompt is reachable
  - a mutation test confirms that removing a wall is detected

### PERFORMANCE
| | V25 | V26 |
| --- | --- | --- |
| Server world parts | 2,845 | 1,464 |
| Vehicle parts moved by the server | 1,731 (~90 vehicles, all districts) | **0** |
| Vehicle `Touched` handlers | one per vehicle part | **0** (one hitbox per vehicle, client-side check) |
| `CanTouch` world parts | 2,845 | 4 (mud patches) |
| Neon / semi-transparent parts | 515 / 183 | 45 / 0 |
| Districts simulated | all 5, each vehicle polling | only districts with a player; empty ones sleep |

- The server simulates numbers only (~0.03 ms per step for a full district). It sends 10
  snapshots/s of ≤584 bytes per district via `UnreliableRemoteEvent`, falling back to
  `RemoteEvent`, and only to players in that district.
- The client renders pooled vehicle models with one `workspace:BulkMoveTo` per frame and does
  hit detection against exactly what it draws, including the swept path. Because of that, fast
  cars can't tunnel through you and latency doesn't cause unfair hits.
- Decorative parts are `CanCollide`/`CanTouch`/`CanQuery = false`. Small parts don't cast
  shadows. There are 2 lights in the starter room.

### VERIFICATION
**Actually verified (offline; see `tools/run_checks.sh`):**
- All 8 scripts compile with `luau-compile`.
- The `.rbxlx` parses with `xml.etree.ElementTree`. Every script is XML-escaped and round-trips
  byte-for-byte, and referents are unique.
- The real server `Main`, `Client` and `TrafficClient` run together headlessly against a Roblox
  API mock. The test covers:
  - spawn in the room facing the exit
  - traffic rendered in its lanes
  - Raju's menu, then a delivery completed across the road (₹55, 28 XP, the same payout as V25)
  - the mechanic unlocking and the guard refusing an unqualified player
  - being hit in lane 2, which fails the delivery and sends you home
  - an accident rendering angled, smoking and solid
  - no more than 4 horn Sounds
- Geometric containment, the bypass proof and reachability for all 5 districts, as above.
- 15 simulated minutes of traffic: no overlaps, the vehicle cap respected, the mix, the speed
  hierarchy, the accident frequency, 2-lane blocks, queues, cleanup and no dead zones.
- Static sweeps: no V25 coordinates, lane offsets, boundaries or gate triggers remain, there is
  a single world generator, and there is exactly one StarterHome (in district 1).
- Approximate previews in `docs/previews/`. These come from my own numpy ray-caster, **not
  Roblox's renderer**. They are only meant to judge composition and scale, and the sun direction
  in them is an assumption.

**Still needs Roblox Studio runtime testing (not verified here):**
- The real look under Roblox materials and Future lighting, and the whole first-minute feel.
- Traffic feel (speeds, density, the fairness of the ~0.9-stud hit margin) on real devices.
  All the tuning is in `Config.Traffic`.
- That horn `rbxassetid://17737027571` still plays. The network here could not reach Roblox to
  check it. The music asset `1844405452` was kept unchanged from V25.
- R15 collision against the invisible walls and props (the verifier models the character as a
  0.9-stud-wide body).
- Default camera behaviour inside the small room after the intro pan.
- Mobile HUD layout, FPS, and the cost of Future lighting on low-end devices. You can switch
  Lighting.Technology to ShadowMap if needed.
- Rank-up teleport to district 2. The code path is written and reviewed but was not exercised by
  the integration test.
- The DataStore in a published place. The unpublished fallback is unchanged from V25.
