# Demo Plan: "The First Sword" (realigned)

This replaces the "First Light" expedition demo plan. That plan had excellent
production discipline (frozen rules, seed testing, save integrity, mobile
performance, release gates) but it was a plan for a different game — an
extraction roguelite with attribute sheets, skill trees, artifact carries, and
a lore-deciphering meta-library. None of that exists in this repo's docs,
data, or code, and all of it competes with what the docs say the game *is*:

> The magic is not just that buildings exist. The magic is that the player can
> see how the world works. — `voxel_rts_overall_gameplan.md`

The demo should be the **Iron Sword Vertical Slice** (gameplan Phase 9) made
shippable and replayable, powered by the two most mature things in the repo:
the world generator (biomes, rivers, live water, day/night, weather, fog,
minimap) and World Forge (blueprints, components, ports, markers, part scale).

What survives from the expedition plan is its *skeleton*, which fits this game
perfectly: **seeded run → build up → survive the night → visible reward → new
seed**. What gets swapped out are its organs: the meta-RPG systems are
replaced by the production chain, block-by-block construction, and
buildings-as-machines.

---

## The demo product

### Shape

One seeded, replayable scenario, 30–45 minutes, on a single fixed-size map.
Main menu offers: New Run (seed + difficulty), Continue, Blueprint Gallery
(World Forge exports the player has unlocked, viewable in 3D), Settings,
Feedback, Quit. Campaign/multiplayer listed as clearly labeled future modes.

### The run

1. Seeded world generates asynchronously with a progress bar and a short
   flyover reveal. A scenario-placement pass guarantees: viable camp site,
   forest, stone, iron and coal veins, a huntable/scavengeable ruin (optional
   flavor, authored in World Forge with its existing ruin purpose and
   resource/patrol markers), and a raider camp outside the safety radius.
2. Briefing: **"Produce 3 iron swords, train 3 swordsmen, and survive the
   raid on the third night — or destroy the raider camp."**
3. Player assigns workers to gather; places World Forge blueprints; workers
   haul materials to construction sites and build them **block by block**.
4. The chain runs visibly: ore leaves the mine, coal and ore enter the
   smelter, ingots and handles enter the forge, the blacksmith works the
   anvil, swords appear on the rack. Selecting a building fades the roof —
   the cutaway pillar, on camera, in the demo.
5. Recruits grab swords from the rack and become swordsmen.
6. Small probing raids on nights one and two (they target haulers and supply
   routes — logistics *is* the strategy), the real raid on night three.
7. Win/loss → results screen built around the chain: ore mined, ingots
   smelted, time to first sword, blocks built, workers lost. Winning unlocks
   one new blueprint for future runs (see Progression).
8. New seed remixes terrain, vein placement, ruin layout, and raid direction.

### Terminology

- **Run:** one seeded scenario, start to win/loss.
- **Blueprint:** a World Forge document the player can place in a run.
- **Unlock:** a blueprint earned by winning, persisted in the profile.

---

## Backlog (ordered)

### 1. Freeze the run rules

Freeze these before building the director — the demo's actual rule surface,
much smaller than the expedition plan's:

- Exact phases: generation → briefing → build/produce (day 1–3, raids at
  night) → resolution.
- The production chain (see §4): recipes, quantities, timings.
- Construction: material list per blueprint, build stages, what "active"
  means (sockets live, recipe available).
- Raid schedule, sizes, and targeting rules per difficulty.
- Win: survive night 3 or destroy the raider camp. Loss: Town Hall destroyed
  or all workers dead.
- Worker death is run-scoped. No cross-run citizen permanence in the demo.
- What persists across runs: unlocked blueprints, stats, settings. Nothing
  else. (This deletes the 24-minute-timer question, the surrender-inventory
  question, and the multiplayer-normalization question entirely.)

### 2. World generation: seeds and async, not streaming

[world_runtime.gd](../scripts/world/world_runtime.gd) generates one map
synchronously (~16 s, ~680 MB on desktop). The fix the demo needs is **speed,
determinism, and memory** — not infinite streaming. Defer the full
load/unload chunk architecture to post-demo; the gameplan's own scope armor
says one map first.

- Deterministic generation from an explicit seed; same seed → same map, on
  every platform. Test ≥100 seeds.
- Move generation to background threads with real progress reporting; first
  visible progress within one second.
- Budget mesh/collision construction so nothing stalls multi-second.
- Keep `ChunkManager` as the storage/meshing unit it already is; make chunk
  *meshing* incremental. Full streaming lands with the campaign map.
- Memory pass to fit the mobile target.

### 3. Scenario placement pass

After terrain, before play:

- Find a dry, flat camp area; reserve construction space; place starter
  resources within reach.
- Stamp World Forge ruin/encounter exports into terrain, rotated/varied,
  with their existing resource-node, unit-spawn, and patrol markers driving
  runtime spawns.
- Place raider camp outside the safety radius; validate paths between camp,
  veins, ruin, and raider camp; retry/repair failing seeds.
- Record the full mission manifest (for resume and reproducibility).

### 4. The production chain (the heart — not a footnote)

The expedition plan compressed this to "wood + ore → forged weapon." That
one-hop chain kills the definition of fun — there is no bottleneck to trace
through a one-hop chain. Demo chain, straight from the gameplan with its own
sanctioned concession (handles at the forge, tannery deferred):

```text
mine        → raw_ore, coal
lumber camp → wood
smelter     → raw_ore x2 + coal → iron_ingot
forge       → wood → wood_handle
forge       → iron_ingot x2 + wood_handle → iron_sword
barracks    → recruit + iron_sword → swordsman
```

Two production buildings is the minimum that still teaches "why are swords
slow → the forge has no ingots → the smelter has no coal." Requirements:

- Authoritative storage inventories (grow
  [storage_inventory.gd](../scripts/economy/storage_inventory.gd)); the HUD
  reads, never owns.
- Resource nodes with finite yields.
- Job board with reservations: gather, haul, construct, craft, repair. One
  worker per job, one claim per item, graceful recovery when a job dies.
- Visible carried items, visible storage stock, visible rack.
- Worker priorities and a simple assignment UI.
- The debug tools the gameplan demands early: job board view, worker state
  inspector, reservation inspector, bottleneck report. (Bob will stand in a
  barrel. Build the tools that find Bob.)

### 5. Buildings for real (World Forge → runtime)

[building_placement_controller.gd](../scripts/buildings/building_placement_controller.gd)
still places colored boxes. This is the single highest-value feature gap,
because it's the pitch on camera:

- Load World Forge blueprints as the building catalog
  ([blueprint_structure_renderer.gd](../scripts/buildings/blueprint_structure_renderer.gd)
  is the seed of this).
- Ghost placement with terrain/water/overlap/path validation, rotation,
  cancel.
- Construction sites with material requirements, reservations, and **staged
  block-by-block builds** by workers.
- Activation only when complete: entrance/worker/storage sockets live.
- Cutaway (roof fade + interior visible) on selection —
  [layer_visibility_controller.gd](../scripts/buildings/layer_visibility_controller.gd)
  plus World Forge visibility layers.
- Damage, repair, destruction.

Demo set (tannery cut with the leather step): Town Hall, Storage Yard,
Lumber Camp, Mine, Smelter, Forge, Barracks (tent), Watchtower, Walls, Gate.

### 6. Units, selection, combat — RTS basics, not an RTS engine

Enough to command workers and fight three raids; formations, stances, and
control groups wait:

- Multi-select (tap + box), move, attack-move, stop; contextual commands on
  touch.
- Recruit training and equip-from-rack.
- Raider AI: approach, prefer haulers/supply targets on probe nights, siege
  on night three.
- Health/damage/attack timing; unit death; building damage; watchtower fire.
- Feedback: selection response, hit reactions, readable health, offscreen
  attack alerts, impact audio.

### 7. Run director

Briefing → objective tracker → day/night clock (the sun/moon rig exists) →
raid warnings and spawns → win/loss checks → results screen → unlock award →
new-run flow. Anti-soft-lock checks (chain can always restart: veins
guaranteed, town hall rebuildable? — decide in §1).

### 8. Persistence (small, but bulletproof)

- Profile: unlocks, stats, settings. Run save: full mid-run resume.
- Atomic writes, backups, version numbers, corruption recovery.
- Autosave on Android pause/background; exact resume after force-close;
  deterministic RNG restoration; unlocks awarded exactly once.

### 9. Progression: blueprints, not attribute sheets

The reward loop stays in the game's own language:

- Winning a run unlocks a new World Forge blueprint (better watchtower,
  stone walls, decorated hall…). Unlocks visible in the Blueprint Gallery.
- **Stretch, not release-blocking:** if crafting-plan Phases 5–6 land
  (kinetics, thermal/casting — see `WORLD_FORGE_CRAFTING_PLAN.md`), one
  crafted *machine* unlock — a working catapult, or a bloomery run as a
  forge upgrade — becomes the demo's signature clip. Gate it on those phases
  actually shipping; do not let the demo wait on them.

### 10. Phone-first UI

Unchanged from the expedition plan — this section was right, and the touch
controls + dynamic resolution work is already in. Landscape, safe areas,
large targets, pinch/pan, collapsible panels, no giant dock, one-tap pause,
back-button behavior, text scaling, colorblind-safe feedback, controller and
keyboard/mouse parity retained.

### 11. Mobile performance

Unchanged in substance: 30 FPS floor on an agreed 4 GB Android device, 60 FPS
option, no thermal collapse over 45 minutes, no multi-second stalls, reliable
resume. Mobile/Compatibility renderer decision, pooled enemies/effects,
MultiMesh vegetation, sim/animation LOD, shadow budget, low/med/high presets,
water sim reduced on low. One addition: the **water simulator and
block-by-block construction are the two most demo-distinctive systems — they
get performance budgets, not disablement.**

### 12. Presentation and feel

As in the expedition plan, retargeted at this loop: real title treatment,
loading flyover, cohesive UI, music states (day/build, night/raid, victory,
defeat), unit acknowledgements, construction/forge/combat audio, ambience,
dawn transition, sword-on-rack moment, team-readable silhouettes, no debug
UI in release.

### 13. Tutorial

Teach inside the first run via the objective tracker: camera → assign
gatherers → place blueprint → watch construction → chain → train → defend.
Explain what persists (blueprints) and what doesn't (this run's citizens).
Contextual, dismissible, observation-only playtests.

### 14. Testing and QA

Keep the expedition plan's matrix, retargeted: seed determinism and placement
guarantees; construction and reservation invariants; job recovery; combat
math; raid progression; win/loss; unlock-exactly-once; save round-trips and
migrations; Android pause/resume; aspect ratios; exported-build smoke tests.
Manual: 100 seeds, 20 full runs without blockers, low/mid/high Android,
Windows + Linux, force-close resume, storage-full, battery saver.

### 15. Repo, builds, Android publishing, marketing

Sections 16–19 of the expedition plan carry over essentially unchanged (they
were game-agnostic and correct): working-tree cleanup, godot_ai addon out of
release builds, export presets + templates, versioning, JDK/SDK setup,
signed AAB, API-level check at submission time, closed-testing requirements,
**no ads in the demo**. Marketing clips come from this loop's natural
moments: world reveal, block-by-block construction timelapse, cutaway forge
crafting a sword, night raid hitting a supply line, dawn victory, new seed.

---

## Cut or deferred (and why)

- **Grand Library, lore deciphering, 24-minute timers** — no doc/code
  support; real-time meta timers fit a live-service loop, not this game. The
  Blueprint Gallery is the demo's trophy room instead.
- **Eight attributes, three skill trees, unique items** — a full RPG layer
  invented by the old plan. The gameplan's progression is eras and better
  machines. Post-demo, profession experience (§ gameplan Phase 10) is the
  natural first step, not D&D sheets.
- **Artifact recovery/carry, evacuation, escalating night-wave survival** —
  replaced by the raid-defense payoff the gameplan already specifies. If the
  expedition fantasy still appeals, it returns later as a *mission archetype*
  on top of these same systems (a run whose objective is scavenging a ruin
  instead of surviving a raid) — cheap then, identity-distorting now.
- **Full chunk streaming** — deferred; demo needs seeded async generation on
  one map, not infinite worlds.
- **Squad formations, stances, control-group depth** — post-demo.
- Campaign, diplomacy, multiplayer, eras, automation — unchanged from both
  plans: deferred.

## Release gates (unchanged in spirit)

Do not release until: a new player completes a run unaided; three consecutive
seeds are fun; force-close resume works; unlocks can't dupe or vanish; no
seed produces an impossible start; 30 FPS holds on the minimum phone for 45
minutes; placeholders and dev UI are gone; 20 external playtests show no
blockers; Android closed-test requirements met; trailer captured from the
shipping build.

## Three decisions to make now

1. **Ruin in or out of demo v1?** Recommend: in, as optional scavenge flavor
   (it exercises World Forge encounter authoring and adds a clip), with no
   carry mechanic.
2. **Chain depth:** two production buildings (smelter + forge) or three
   (+ tannery/leather)? Recommend two for the demo; tannery is the first
   post-demo content patch.
3. **Raider camp assault as alternate win condition** — in v1, or
   survive-only? Recommend in (it's the gameplan's own win condition and
   rewards aggressive logistics), but it costs raider-camp defense AI.
