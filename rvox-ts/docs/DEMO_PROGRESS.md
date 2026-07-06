# Demo Progress Log

Running report of work against [DEMO_PLAN.md](DEMO_PLAN.md), maintained by the
`/loop` session. Newest iteration on top. Nothing here is committed — all
changes sit in the working tree for review.

Test baseline at session start: **110/110** passing. Current: **201/201**.
Live boot: **VICTORY run + block-by-block construction both verified in-engine.**

---

## Iteration 17 — buildings are machines: stations gate on construction (§3/§6)

### ✅ Finished

Production is now gated on building it: the smelter and forge **come online only
when their building is finished**, instead of existing globally at run start.
`RunCoordinator` places smelter and forge build sites, and registers their
stations on `economy.building_completed` (the forge activates its handle + sword
stations). So the flow is now: gather → **build the smelter/forge** → produce →
train.
- [run_coordinator.gd](../scripts/mission/run_coordinator.gd) — build sites +
  `_on_building_completed` → `_activate_station`.
- Tests: [test_run_coordinator.gd](../tests/test_run_coordinator.gd) — no
  stations until buildings finish; smelter completion activates 1 station, forge
  activates 2, an unrelated building activates none. Full suite **201/201**.
- Boot-verified: four buildings (storage yard, watchtower, smelter, forge) are
  raised block-by-block from the opening ("Building Watchtower: 1/4", stock
  drawn down), zero run errors.

The demo now exercises the full "buildings are machines" pillar — you build the
forge before it can forge.

### 🔜 Next

1. **BuildSite from HUD placement** — placing a building creates a site the
   villagers build (needs your playtest for feel).
2. Real World Forge blueprint blocks instead of placeholder cubes.
3. Difficulty tuning; threaded meshing.

---

## Iteration 16 — watchtower → raid defense (buildings matter in combat, §6)

### ✅ Finished

Building a watchtower now actually strengthens the settlement: `RaidController`
listens to `economy.building_completed`, counts finished **watchtowers**, and
factors them into raid resolution (`resolve(swordsmen, watchtower_count,
raid_size)` — a tower joins the garrison). The demo now places a watchtower
build site alongside the storage yard, so a builder raises it and it defends
later nights.
- [raid_controller.gd](../scripts/mission/raid_controller.gd),
  wired through `GameMain` (economy passed to `bind`) and
  [run_coordinator.gd](../scripts/mission/run_coordinator.gd).
- Tests: [test_raid_controller.gd](../tests/test_raid_controller.gd) — the
  resolver takes a tower count; added that a watchtower turns a losing fight,
  and that a completed watchtower (`building_completed`) is counted and saves an
  otherwise-doomed raid. Full suite **200/200**.

Now the buildings a builder raises feed back into the combat loop — the first
real "building → gameplay" link (stations-inside-buildings is the next one).

### 🔜 Next

1. **Stations inside completed buildings** — forge/smelter activate on their
   building's completion (rather than globally at run start).
2. **BuildSite from HUD placement** — placing a building creates a site the
   villagers build, instead of an instant box (needs your playtest).
3. Difficulty tuning; real World Forge blueprint blocks; threaded meshing.

---

## Iteration 15 — workers place blocks 1/5 → 5/5 (§5, the block-built pillar)

### ✅ Finished — and verified live in the running game

The gameplan's headline: **a worker physically raises a building block by
block.** Reworked the construction model to be block-based and gave it a real
builder:
- [build_site.gd](../scripts/buildings/build_site.gd) is now block-based —
  `place_block()` raises the structure one block at a time, emitting
  `block_placed(placed, total)` ("3/5") and completing on the last block; each
  block consumes `material_per_block`.
- [builder_brain.gd](../scripts/workers/builder_brain.gd) — a Unit-decoupled
  state machine (IDLE → TO_STOCKPILE → TO_SITE → PLACING) that claims a
  construct job, hauls one block's materials from the stockpile, carries it to
  the site, places the block, and loops until the building is raised — waiting
  at the stockpile if materials run short.
- [build_controller.gd](../scripts/workers/build_controller.gd) spawns builders,
  ticks their brains, and **renders a block mesh per placed block** so the
  structure visibly rises. `EconomyController` posts a builder-role construct
  job per site (`build_site_added`), and gatherers vs builders now use distinct
  job roles so they don't poach each other's work.
- `RunCoordinator` places a starter **Storage Yard** by the camp; the HUD shows
  **"Building Storage Yard: N/5"** and "complete".
- Tests: [test_build_site.gd](../tests/test_build_site.gd) (6, rewritten for the
  block model) + [test_builder_brain.gd](../tests/test_builder_brain.gd) (3):
  progress reads 1/5…5/5, materials consumed per block, the builder hauls and
  places to completion, and waits without materials then finishes when stocked.
  Full suite **198/198**.

**Live verification:** launched the game and watched the HUD climb
**"Building Storage Yard: 1/5 → 4/5 → complete"** as the builder hauled
materials and placed blocks one at a time — the block-built pillar, working in
the actual game.

### 🔜 Next

1. **Load real World Forge blueprints** so buildings raise as their authored
   block shapes/materials (not placeholder cubes) — needs your playtest.
2. **Stations inside completed buildings** (forge/smelter activate on
   completion); **watchtower → `RaidController.has_watchtower`**.
3. Difficulty tuning; threaded meshing.

---

## Iteration 14 — construction model: buildings cost materials over time (§5)

### ✅ Finished

Replaced the demo's "pay instantly, box appears" placeholder economics with a
real construction model: [build_site.gd](../scripts/buildings/build_site.gd) —
a building that **needs a material bill delivered, then builds over time, then
activates** (NEEDS_MATERIALS → BUILDING → COMPLETE), with signals for delivery
and completion.
- Integrated into [economy_controller.gd](../scripts/economy/economy_controller.gd):
  `register_build_site` + a tick pass that hauls owed materials from the central
  stockpile to each site (the same abstracted-haul pattern stations use), then
  advances the build and emits `building_completed`. So a placed building now
  *draws its cost from the stockpile over time* instead of vanishing instantly.
- Tests: [test_build_site.gd](../tests/test_build_site.gd) — **6 tests**: needs
  materials before building, partial→full delivery flips to building then
  completes, free buildings start at once, never overfills, and the economy
  delivers from stock incrementally as materials become available. Full suite
  **195/195**.

This is the *data model and economy plumbing* for real buildings. The live
payoff — placement creating a site, villagers physically hauling blocks, the
structure raising block-by-block from a World Forge blueprint, and stations
living inside the finished building — is the visual half that wants your
playtest (the existing `ConstructionSite`/blueprint path renders blocks; this
BuildSite gives it economy-backed material gating).

### 🔜 Next

1. **Wire BuildSite into placement** — HUD "build" creates a site (visible
   ghost → raising → active) instead of an instant box; watchtower feeds
   `RaidController.has_watchtower`. Needs your playtest for feel.
2. **Difficulty tuning** (raids currently too easy) — playtest.
3. **Threaded/optimized meshing** to cut the ~16s load — needs profiling.

---

## Iteration 13 — dev fast-forward + full-run live verification (§7/§13)

### ✅ Finished — and the whole demo loop verified live

Added a debug **fast-forward** (F toggles `Engine.time_scale` 1×⇄20×;
[game_main.gd](../scripts/core/game_main.gd)) — a genuine playtesting aid to
reach night/raids without waiting, and the vehicle for verifying the full run.
Marked for stripping at release (§13).

**Ran a complete run at 15× and watched every system work together in the live
game:**
1. Incremental world load (overlay → terrain) ✓
2. Villagers gathered; the production chain forged **40 swords** ✓
3. **3 swordsmen trained** (objective complete) ✓
4. Day→Night phase progression, day/night lighting ✓
5. **Night 1 raid** (3 raiders, "haulers") → defended ✓
6. **Night 2 raid** (5 raiders, "buildings") → defended — escalation exactly
   per RUN_RULES ✓
7. **Night 3 raid** (10 raiders, "town_hall") → survived ✓
8. **VICTORY results screen**: "Swords forged: 40 · Swordsmen trained: 3 ·
   Blueprint unlocked: Stone Walls" + New Run ✓
9. Reward banked into the profile ✓

So the whole vertical slice — generate → gather → produce → train → survive
three escalating raids → win → results → reward — is now proven working
together in the actual game, not just in unit tests. Full suite **189/189**.

### ⚠️ Balance observation (playtest territory)

The garrison (3 swordsmen + a 2-man base militia, all swordsman-stat) held all
three raids including night 3's 10 raiders, with villagers on full auto — so the
demo currently trends **too easy**. That's expected: combat stats and raid sizes
are first-pass numbers in `combat_catalog.gd` / `mission_director.gd`, meant to
be tuned in playtest. The *mechanism* is proven; the *difficulty curve* is a
knob for you.

### 🔜 Next

1. **Difficulty tuning pass** (with your playtest) — make raids a real threat.
2. **§5/§6 real buildings** — World Forge blueprints as construction sites.
3. **Threaded/optimized meshing** to cut the ~16s load.

---

## Iteration 12 — incremental world generation + loading screen (§2/§13)

### ✅ Finished — and verified live

Startup no longer freezes for ~16s. The initial terrain **meshes across frames**
instead of one synchronous block:
[world_runtime.gd](../scripts/world/world_runtime.gd) now creates the region
nodes and queues them, draining them in `_process` (faster during the initial
fill), and emits `generation_progress(done, total)` / `generation_ready`.
`world_generated` still fires up front with the chunk *data* ready, so unit
spawns, the minimap, and camera framing (all data-driven) work immediately while
the mesh fills in.
- [game_main.gd](../scripts/core/game_main.gd) shows a full-screen
  **"Generating world… N%"** overlay that clears on `generation_ready`
  (re-shown on regenerate) — DEMO_PLAN §13's "visible loading progress."
- Full suite **189/189** (no test regressions); boot verified: overlay showed
  live progress (9% → 100%), terrain materialized, overlay cleared, game fully
  playable with villagers gathering — zero run errors.

### Key profiling finding (from the boot test)

The startup cost is **terrain meshing, not data generation** (progress was ~9%
at 1.2s, i.e. ~0.2s per region × 64 regions ≈ the old ~16s). So the world is now
*responsive with visible progress* rather than frozen, but the total load
duration is unchanged. **Speeding it up is a distinct task**: thread the mesher
(WorkerThreadPool) or optimize `ChunkMesher`/trimesh-collision — deeper perf work
that wants on-device profiling, not a blind edit. Data-gen threading is *not*
where the time goes, so that's de-prioritized.

### 🔜 Next

1. **Threaded/optimized meshing** — cut the ~16s load (needs profiling).
2. **§5/§6 real buildings** — World Forge blueprints as construction sites.
3. **Live combat visuals + a "skip to night" debug** so raids can be seen/tuned.

---

## Iteration 11 — results screen + reward banking closes the meta-loop (§7/§9)

### ✅ Finished

**A win banks a blueprint into the profile; the results screen shows it.**
`RunCoordinator` now owns a `ProfileStore` (loaded on ready) and, on
`director.run_ended`, banks the result: a win unlocks the next locked blueprint
(from `UNLOCKABLES`) and records the win; a loss records the loss; the profile
saves atomically; then `run_resolved(outcome, unlock)` fires. Because the run
ends exactly once and `award_unlock` dedupes, the release gate **"reward banking
cannot duplicate or disappear"** holds.
- HUD ([rts_hud.gd](../scripts/ui/rts_hud.gd)) gets a centered results overlay
  (VICTORY/DEFEAT, swords/swordsmen tally, banked unlock) and a **New Run**
  button that emits `new_run_requested` → `GameMain._regenerate_world` (new
  seed, fresh run).
- Wiring in [game_main.gd](../scripts/core/game_main.gd),
  [run_coordinator.gd](../scripts/mission/run_coordinator.gd).
- Tests: [test_run_coordinator.gd](../tests/test_run_coordinator.gd) grows to
  **7 tests**: win banks + persists the first unlock, a second win unlocks the
  next (no duplication), a loss banks nothing but records the loss. Full suite
  **189/189**; game boots clean with the results/new-run wiring.

### The meta-loop is now closed

run → win/lose → **results screen → reward banked into the profile (once) →
New Run (new seed)** → repeat. Combined with the mechanical run loop from
iteration 10, the demo now has a complete, replayable core: seed → build →
produce → train → defend → resolve → reward → new seed.

### 🔜 Next

1. **§5/§6 real buildings** — World Forge blueprints as construction sites
   villagers build; stations + watchtower live inside them (largest remaining
   feature gap; needs your playtest for feel).
2. **§2 deterministic async generation** (boot-verified).
3. **A "skip to night" debug + live combat visuals** so raids can be seen and
   tuned (playtest).

---

## Iteration 10 — live raids: the run loop is mechanically complete (§6)

### ✅ Finished

**RaidController** ([raid_controller.gd](../scripts/mission/raid_controller.gd))
turns the director's `raid_incoming` into a real raid: it spawns raiders at the
raider camp, marches them to the settlement, and resolves the fight with the
combat core's skirmish simulator. A defended raid clears the raiders; a lost
one destroys the town hall (the director ends the run in defeat). Defenders =
trained swordsmen + a base town militia (so an unprepared camp still fights) +
a watchtower once buildings host one. Wired into `GameMain`;
`RunCoordinator` now exposes the raider-camp world position.
- Tests: [test_raid_controller.gd](../tests/test_raid_controller.gd) —
  **5 tests**: a prepared garrison repels the early raid, an unprepared camp
  falls to the night-3 wave, more swordsmen flip the outcome, `raid_incoming`
  arms the raid, and a hopeless raid ends the run in defeat. Full suite
  **186/186**; game boots clean with raids wired in.

### The run loop is now end-to-end

generate → scenario placement → gather (villagers) → smelt/forge (stations) →
train swordsmen → **raiders march in and are resolved by combat** → win
(survive night 3 / raze the camp) or lose (town hall falls). Every step is
tested and wired into the live game. Seeing an actual raid needs a ~3-minute
soak (night 1) — the mechanics are proven by tests; a debug "skip to night"
and the live combat *visuals* (melee, health bars) are playtest polish.

### 🔜 Next

1. **§5/§6 real buildings** — World Forge blueprints as construction sites the
   villagers build block-by-block; stations + watchtower live inside them
   (largest remaining feature gap; needs your playtest for feel).
2. **§2 deterministic async generation** (boot-verified).
3. **Results screen + reward banking** (§7/§9) — on run end, show the outcome
   and bank an unlocked blueprint into the profile (exactly once).

---

## Iteration 9 — combat core (§6/§14)

### ✅ Finished

The unit-testable foundation raids need (raids themselves can't be quickly
boot-verified — night 1 is 3 minutes into a run):
- [health.gd](../scripts/combat/health.gd) — HP with damage/heal and a
  fires-once `died` signal.
- [combat_stats.gd](../scripts/combat/combat_stats.gd) — data-driven per-unit
  profile (hp/damage/armor/range/interval), a Resource for later `.tres`.
- [combat_math.gd](../scripts/combat/combat_math.gd) — the armor-adjusted
  damage formula (floored at 1) and a **deterministic skirmish simulator** that
  fights two lines to the death and reports the winner + survivors. No RNG, so
  it's testable and save-safe; it also resolves a raid's outcome.
- [combat_catalog.gd](../scripts/combat/combat_catalog.gd) — tuned demo
  profiles (swordsman / raider / watchtower).
- Tests: [test_combat.gd](../tests/test_combat.gd) — **8 tests** proving the
  DEMO_PLAN §14 requirements: attributes/equipment change outcomes (numbers
  beat equal stats; better stats beat numbers; a watchtower swings a close
  fight), difficulty scales (garrison holds night-1's 3 raiders but falls to
  night-3's 12), and the sim is deterministic. Full suite **181/181**.

### 🔜 Next

1. **Live RaidController** — spawn raider units at the raider camp on the
   director's `raid_incoming`, march them to the camp, resolve the fight with
   the skirmish sim / live melee, and report the outcome to the director. (Seen
   live needs a long soak or a debug "skip to night" — flag for playtest.)
2. **§5/§6 real buildings** — World Forge blueprints as construction sites.
3. **§2 async generation.**

---

## Iteration 8 — swordsman training completes the objective loop (§7)

### ✅ Finished

**Auto-train swordsmen from forged swords.** `RunCoordinator` now turns each
banked `iron_sword` into a swordsman (up to the objective goal of 3): it
consumes the sword, calls `director.record_swordsman_trained`, and emits
`swordsman_trained`, which `GameMain` handles by spawning a real
sword-and-shield soldier at the camp. This closes the objective's second half
(the first — sword production — landed in iteration 7).
- [run_coordinator.gd](../scripts/mission/run_coordinator.gd),
  [game_main.gd](../scripts/core/game_main.gd).
- Tests: new [test_run_coordinator.gd](../tests/test_run_coordinator.gd) —
  **4 tests**: trains from a banked sword, no-sword no-op, caps at the goal,
  and objective completion after 3 swords + 3 swordsmen. Full suite **173/173**.
- **Live-verified:** the running game's objective panel reached
  **"Swords 1/3 · Swordsmen 1/3"** — a forged sword was consumed to train a
  swordsman and spawn a soldier at the camp. The whole core loop (gather →
  smelt/forge → sword → swordsman) now runs end to end in-engine.

**Console-noise cleanup.** `SaveIO` now parses with `JSON.new().parse()` instead
of `JSON.parse_string`, so the corrupt-file recovery test (and any real corrupt
save) recovers *quietly* instead of logging a scary "Parse JSON failed" every
run. Confirmed: the 173-test run produced no JSON error noise.

### 🔜 Next

1. **§5/§6 real buildings** — the largest remaining feature gap: World Forge
   blueprints placed as construction sites villagers build block-by-block, with
   stations living inside completed buildings (needs your playtest for feel).
2. **§2 deterministic async generation.**
3. **Combat / raids** — spawn raiders on the director's `raid_incoming`, let
   swordsmen and watchtowers fight them (§6).

---

## Iteration 7 — production stations wired into the live economy (§4/§6)

### ✅ Finished

**Stations feed off the central stockpile.** The gathered raw materials now
flow through the whole chain into swords. `EconomyController.tick`
([economy_controller.gd](../scripts/economy/economy_controller.gd)) treats the
central stockpile as the shared buffer: each station pulls a full craft's worth
of inputs from stock (only when affordable, so nothing is hoarded into a stalled
station), crafts, and drains its outputs back to stock. Reuses the tested
`ProductionStation`.

**RunCoordinator registers the demo chain** — smelter + two forges (handles and
swords, since a station runs one recipe) — and routes each finished
`craft_iron_sword` to `director.record_sword_produced`, so the objective tracker
climbs as swords are forged.

**Tests updated + added:** the two older station tests asserted outputs stayed
in the station; they now correctly assert outputs are *banked to central stock*.
Added `test_station_feeds_from_and_drains_to_central_stock` and
`test_stockpile_buffered_chain_produces_swords` (raw ore/coal/wood in stock →
iron sword out, with `production_finished` firing). economy_controller suite now
**10 tests**; full suite **169/169**.

**Live verification — the whole chain, in the running game:** launched the game
(clean boot, zero run errors) and watched the objective panel climb to
**"Swords 1/3"**. A sword was forged end to end from gathered raw materials:
villagers gathered ore/coal/wood into the stockpile → smelter made ingots →
forge made handles → forge made the sword → `record_sword_produced` incremented
the objective. The resource bar reflected it (Wood 338 from steady gathering,
Ore/Ingots 0 as fast as consumed, Coal 75). This is the complete "visible
production chain" pitch, proven live — not just in tests.

### 🔜 Next

1. **Swordsmen** — auto-train a swordsman when a sword is banked and a recruit
   is free, feeding the second half of the objective
   (`record_swordsman_trained`).
2. **§5/§6 real buildings** — World Forge blueprints as construction sites the
   villagers build; stations live inside them.
3. **§2 async generation.**

---

## Iteration 6 — objective HUD + brain-driven villagers (§4/§5/§7)

### ✅ Finished — and verified live in the running game

**Objective / phase / raid HUD** — [rts_hud.gd](../scripts/ui/rts_hud.gd) now
binds the run director: a centered panel shows the phase ("Day 1 — build &
gather"), objective progress ("Swords 0/3 · Swordsmen 0/3"), and a flashing
raid warning when a wave spawns; it turns to VICTORY/DEFEAT on run end.

**Autonomous villagers** — new
[villager_controller.gd](../scripts/workers/villager_controller.gd) spawns three
`WorkerBrain`-driven gatherers, keeps a standing supply of gather jobs on the
board (cycling wood/ore/coal for nodes that still have stock), and applies each
brain's intent to its `Unit` (move order + dig/carry stance). Rebinds cleanly on
regenerate.

**Bug fixed (found via the boot test):** the stockpile — where villagers spawn,
deposit, and the camera frames — was the map centre, ~130 cells from the camp
and its resource nodes, so villagers hiked across the whole map. Now it's the
planned camp ([run_coordinator.gd](../scripts/mission/run_coordinator.gd)), and
the camera frames the camp too ([game_main.gd](../scripts/core/game_main.gd)).

**Verification:** launched the game — booted live, zero run errors. After ~13 s
the resource bar had climbed from the seeded **Wood 250 / Ore 0 / Coal 0** to
**Wood 280 / Ore 30 / Coal 30**: villagers claimed jobs, walked to nodes,
gathered, carried loads back, and deposited into the economy, with the HUD
updating live — the core "visible production chain" pitch, working end to end.
Screenshot confirmed the camp framing, villager bodies, markers, and objective
panel. Test suite still **168/168**.

### 🔜 Next

1. **§5/§6 real buildings** — World Forge blueprints → runtime construction
   sites the villagers build block-by-block (the largest remaining feature gap;
   needs your playtest for feel).
2. **Wire stations into the economy** — place smelter/forge as stations so the
   gathered ore/coal/wood actually become ingots and swords (feeds the
   objective tracker: `record_sword_produced`).
3. **§2 async generation.**

---

## Iteration 5 — live-scene integration (§3/§4/§7 wired in)

### ✅ Finished — and boot-verified in the running game

**GameMain integration** → new [run_coordinator.gd](../scripts/mission/run_coordinator.gd)
plus edits to [game_main.gd](../scripts/core/game_main.gd) and
[rts_hud.gd](../scripts/ui/rts_hud.gd). The tested backend now runs inside the
actual game:
- `RunCoordinator` plans a scenario on each world generation, builds the
  `EconomyController` (seeded stock), starts the `MissionDirector`, advances
  both every frame, and drops emissive in-world markers for the camp, resource
  nodes, and raider camp so the scenario is legible before real props exist.
- The HUD now **reads its resource bar and pays building costs from the
  economy** (`bind_economy`), falling back to the old placeholder dict only if
  no economy is present — so nothing breaks if run setup is skipped.
- All additive and null-guarded; regenerate tears down and rebuilds cleanly.

**Verification (since visual playtest isn't available while you're away):**
- Launched the game via the editor — booted **live with zero run errors**.
- Game log confirms:
  `[RunCoordinator] seed=1337 scenario_valid=true nodes=7 camp=(33,17) raider=(255,255)`
  — valid scenario, 7 nodes (3 wood + 2 ore + 2 coal), camp + raider placed.
- Screenshot confirms the resource bar shows the economy's seeded stock
  (Wood 250 / Stone 180 / Food 120 / Ore 0 / Coal 0 / Ingots 0) and the
  scenario markers render in-world.
- Full test suite still **168/168** after the HUD/GameMain edits.

### ⚠️ Refinement noted (not a bug)

The raider camp is placed at the farthest reachable cell, which tends to hug a
map corner. It's within spec (outside safety radius, reachable) and defensible
(raiders march from the edge), but for variety it could later pick among the
farthest *band* of cells with seeded jitter. Left as-is — it's a feel-tuning
change that wants a playtest, not a blind edit.

### 🔜 Next

1. **Objective/phase HUD** — bind the director's `objective_updated` /
   `phase_changed` / `raid_incoming` / `run_ended` to on-screen readouts
   (day/night, objective progress, raid warnings, results). Boot-verified.
2. **Spawn brain-driven villagers** — a couple of `WorkerBrain` workers + a
   standing gather-job supply, so gathering is visible in-game (needs your
   playtest to judge feel).
3. **§2 async generation** and **§5/§6 real buildings** (largest remaining gap).

---

## Iteration 4 — worker execution brain (§4/§5)

### ✅ Finished

**Worker gather→haul brain** → [worker_brain.gd](../scripts/workers/worker_brain.gd)
A Unit-decoupled state machine (IDLE → TO_SOURCE → GATHERING → TO_DROPOFF)
that turns a job-board gather job into concrete behaviour: claim the job,
reserve capacity at the nearest available node, walk out, dig, carry the load
back to the stockpile, deposit into the economy, complete the job. Owns all the
economy interactions and recovers (release reservation, hand job back) if the
node is mined out mid-trip. Each tick returns an intent
`{state, move_target, stance}` the scene applies to a `Unit`
(`move_to`/`set_stance`) — so the whole thing is testable without a scene.
This is the visible logistics loop the pitch is built on.
Tests: [test_worker_brain.gd](../tests/test_worker_brain.gd) — **5 tests**:
full delivery, state progression, mid-trip depletion recovery, idle-with-no-work,
and two workers splitting two jobs with no double-claim.

### State of the backbone

The demo's **pure-logic systems are now built and tested end to end**:
seed determinism (§2 partial), scenario placement (§3), economy +
production chain + controller (§4), worker logistics (§5), run director (§7),
and persistence (§8) — **58 new tests, zero regressions**. What remains is
mostly *integration and presentation*, which needs the live scene:

### 🔜 Next (integration — boot-verified, not unit-tested)

1. **GameMain wiring** — instantiate EconomyController + MissionDirector +
   ScenarioPlanner in the scene; HUD reads stock from the controller; spawn
   workers driven by WorkerBrain; run director advances on the day/night clock.
   Verify by launching the game and reading logs (no visual playtest here).
2. **§2 async generation** — thread the pure-data chunk gen off the main
   thread with progress; defer spawns to `world_generated`.
3. **§5/§6 buildings** — World Forge blueprints → runtime construction sites
   (the biggest remaining feature gap; largely visual, needs your playtest).

---

## Iteration 3 — save/load integrity (§8)

### ✅ Finished

**§8 persistence** — three new tested modules under `scripts/persistence/`:
- [save_io.gd](../scripts/persistence/save_io.gd) — atomic JSON writes (temp +
  rename), `.bak` backup on every overwrite, and corruption recovery (falls
  back to the backup when the live file won't parse).
- [profile_store.gd](../scripts/persistence/profile_store.gd) — the cross-run
  profile (unlocks, stats, settings), versioned with a migration hook.
  `award_unlock` is idempotent, satisfying the release gate "reward banking
  cannot duplicate or disappear."
- [run_store.gd](../scripts/persistence/run_store.gd) — the separate run-save
  domain: seed + manifest + economy stock + node depletion + full director
  state, for exact resume after a force-close.
- Added JSON-safe `to_dict`/`from_dict` to the manifest and
  `capture_state`/`restore_state` to the director.
- Tests: [test_persistence.gd](../tests/test_persistence.gd) — **9 tests**:
  round-trips, backup-on-overwrite, corrupt-file recovery, profile migration,
  unlock-exactly-once, and an end-to-end save→fresh-boot→exact-resume.

### 🔜 Next

1. **Worker execution brain** — job-board jobs → gather/haul/craft intents.
2. **§2 deterministic async generation** (boot-verified).
3. **GameMain integration** — wire EconomyController + MissionDirector +
   ScenarioPlanner into the live scene, HUD reading from the controller
   (boot-verified, since it can't be playtested here).

---

## Iteration 2 — economy runtime coordinator + run director

### ✅ Finished

**§4 runtime wiring** → [economy_controller.gd](../scripts/economy/economy_controller.gd)
The authoritative runtime owner of the economy: central stockpile (HUD reads,
never owns), the job board, all resource nodes, all production stations. Ticks
stations and auto-starts any whose inputs are ready; exposes nearest-available-
node targeting for workers, `populate_from_manifest` to place nodes from a
scenario, and `diagnose` for the readability UI. Tests:
[test_economy_controller.gd](../tests/test_economy_controller.gd) — **8 tests**,
including a full ore→ingot→handle→sword chain integration driven by ticks.

**§7 run director** → [mission_director.gd](../scripts/mission/mission_director.gd)
The run's spine: phase/day-night state machine, objective tracker, raid
schedule (RUN_RULES sizes, difficulty-scaled), and every win/loss path
(survive night 3, raze the raider camp, lose the town hall, lose all workers).
Pure time-driven logic — `advance(delta)` steps it, so a full run simulates in
a test. Tests: [test_mission_director.gd](../tests/test_mission_director.gd) —
**10 tests**, simulating complete runs through each outcome.

### 🔜 Next

1. **§8 persistence** — profile (unlocks/stats/settings) + run save (manifest +
   economy snapshot + director state), atomic writes, backups, corruption
   recovery, unlock-awarded-exactly-once. A release gate; fully round-trip
   testable.
2. **Worker execution brain** — decoupled state machine turning job-board jobs
   into movement/gather/haul/craft intents the Unit layer applies.
3. **§2 async generation** (boot-verified).

---

## Iteration 1 — freeze rules, economy backend, scenario placement

### ✅ Finished

**§1 Freeze the run rules** → [RUN_RULES.md](RUN_RULES.md)
Fully specified the demo's rule surface with concrete numbers: run phases and
day/night length, the fixed objective, what persists across runs (only
unlocked blueprints, stats, settings — everything else run-scoped), economy
constants, construction/raid/scenario rules. Removing the meta-RPG layer
dissolved the expedition plan's three open questions; the three that remain
(ruin, chain depth, alt-win) are recorded with recommended defaults.

**§4 Production-chain backend** (the "heart of the game") — new, fully tested:
- [resource_node.gd](../scripts/economy/resource_node.gd) — finite-yield
  resource source with reserve/release/extract accounting so two workers can
  never claim the same units.
- [job_board.gd](../scripts/economy/job_board.gd) — central job pool with
  atomic claim, role-gating, priority ordering, and abandon/recovery
  (including `abandon_all_for` when a worker dies). The gameplan's Priority 2
  & 3 (generic jobs, shared movement).
- [production_station.gd](../scripts/economy/production_station.gd) —
  buildings-as-machines: consumes inputs at craft start, produces over time,
  and holds finished goods in a pending buffer if the output store is full so
  nothing is ever destroyed.
- [demo_chain.gd](../scripts/economy/demo_chain.gd) — the frozen recipe
  catalog **plus a bottleneck diagnoser** that traces a stalled sword back to
  its missing raw material ("why are swords slow → no ingots → no ore"). This
  is the gameplan's "Definition of Fun" made into a queryable function; it
  will drive the §4 readability UI.
- Tests: [test_economy.gd](../tests/test_economy.gd) — **19 tests**, covering
  reservations, double-claim prevention, job recovery, craft timing,
  no-loss output buffering, and three diagnoser trace cases.

**§3 Scenario placement pass** — new, fully tested:
- [scenario_manifest.gd](../scripts/mission/scenario_manifest.gd) — the
  recorded, serializable output (a Resource, ready for the §8 save).
- [scenario_planner.gd](../scripts/mission/scenario_planner.gd) — finds a dry
  flat camp, places finite resource nodes tied to **real biomes and ore
  veins** (miners dig where the metal actually is), puts a raider camp outside
  the safety radius, and validates every landmark is BFS-reachable from camp.
  Deterministic per seed; `plan_or_retry` bumps the seed until a valid
  scenario is found (the §3 retry/repair rule). `to_resource_nodes` bridges
  the manifest into live economy `ResourceNode`s.
- Tests: [test_scenario_planner.gd](../tests/test_scenario_planner.gd) —
  **7 tests** against real generated terrain across many seeds: all
  guarantees, reachability, raider-camp distance, determinism, and the
  §14 "no impossible start" property (most seeds valid + retry always
  recovers).

### 🔜 Next (in intended order)

1. **§4 wiring** — a runtime `EconomyController` node that owns the JobBoard,
   the placed ResourceNodes (from the manifest), station inventories, and a
   Town Hall / Storage Yard authoritative stock; HUD reads from it instead of
   owning resources. Then worker job execution (walk → gather → haul → craft)
   driving the existing `Unit`/worker agents.
2. **§2 deterministic async generation** — thread the pure-data chunk gen +
   presettle off the main thread, emit progress, defer `GameMain`'s unit/
   creature spawns to the `world_generated` signal. Determinism is already
   proven by `game_foundation` tests; this is the speed/memory/stall work.
   Verify via headless boot + logs, since it can't be visually playtested here.
3. **§7 run director skeleton** — day/night clock is present (SunMoonRig);
   add phase state machine, objective tracker, raid scheduler reading
   RUN_RULES constants, win/loss checks. Testable as a pure state machine.

### ⚠️ Notes / observations

- **Repo hygiene (§16) is real and pre-existing.** The working tree carries
  hundreds of untracked `.godot/imported/*.ctex` and
  `data/buildings/thumbnails/*.png.import` files, and the World Forge library
  throws ~250 "failed to load image" errors on load for thumbnail PNGs that
  are referenced but missing on disk. None of this is from this session's
  work, but it will need a cleanup pass and a decision on what belongs in Git.
- New `class_name` scripts require a `filesystem_manage(op="scan")` before the
  editor test runner sees them (known project gotcha).
- Indentation is mixed in the repo (economy stubs used spaces; most of the
  project uses tabs). New files use **tabs** to match the project majority and
  Godot convention; each file is internally consistent.
