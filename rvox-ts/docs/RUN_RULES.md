# Frozen Run Rules — "The First Sword" demo

This freezes DEMO_PLAN.md §1: the exact, numeric rule surface the mission
director and systems build against. Numbers are demo defaults, tuned later in
playtesting, but the *shape* of the rules is fixed. Where the old expedition
plan left three open questions (library clock, death permanence, surrender
inventory), removing the meta-RPG layer dissolves them; the decisions that
remain are recorded here.

## Run shape

| Phase          | Trigger → end                                             |
|----------------|-----------------------------------------------------------|
| Generation     | seed chosen → world + scenario manifest ready             |
| Briefing       | manifest ready → player dismisses briefing                |
| Day 1–3        | build, gather, produce; probe raids at night 1 & 2        |
| Night 3 (raid) | dusk of day 3 → the main raid resolves                    |
| Resolution     | win/loss check → results → unlock award → new-run offer   |

- **Day/night length:** 4 real minutes per day (≈3 min day, ≈1 min night),
  ~13–14 min for a full 3-day run plus setup and resolution. Sits inside the
  30–45 min session target with room for a slower first playthrough.
- **Win:** survive the night-3 raid, OR destroy the raider camp any time.
- **Loss:** Town Hall destroyed, OR every worker dead with no means to rebuild.

## Objective (fixed)

> Produce **3 iron swords**, train **3 swordsmen**, and survive the night-3
> raid — or destroy the raider camp.

Swords/swordsmen are the *readable goal*; survival is the *win check*. A player
who kills the raider camp early wins without the full quota (rewards aggression,
per the gameplan's own alternate win condition).

## Persistence (fixed)

Only three things cross runs:

- **Unlocked blueprints** (the trophy — DEMO_PLAN §9).
- **Run statistics** (records, bests).
- **Settings.**

Everything else — this run's citizens, their gear, gathered resources,
buildings — is **run-scoped**. Worker death is permanent *within the run* and
carries no cross-run penalty. No citizen roster persists. No real-time meta
timer exists (the deciphering clock is cut). This deletes the expedition
plan's three open questions outright.

## Economy constants

Resource-node yields (finite; DEMO_PLAN §4):

| Node        | Resource   | Yield per node | Nodes placed |
|-------------|------------|----------------|--------------|
| Forest      | `wood`     | 60             | 3            |
| Iron vein   | `raw_ore`  | 80             | 2            |
| Coal seam   | `coal`     | 40             | 2            |

Recipes (frozen in `scripts/economy/demo_chain.gd`):

| Recipe            | Station | Inputs                          | Output           | Time |
|-------------------|---------|---------------------------------|------------------|------|
| Smelt Iron Ingot  | smelter | `raw_ore` ×2 + `coal` ×1        | `iron_ingot` ×1  | 6 s  |
| Carve Wood Handle | forge   | `wood` ×1                       | `wood_handle` ×2 | 3 s  |
| Forge Iron Sword  | forge   | `iron_ingot` ×2 + `wood_handle` ×1 | `iron_sword` ×1 | 8 s  |

Cost of the 3-sword goal in raw materials: 12 `raw_ore`, 6 `coal`,
2 `wood` (rounded up per handle craft) — comfortably inside the placed yields,
leaving slack for a botched first attempt.

## Construction (fixed)

- Buildings are placed as ghosts, become **construction sites**, and are built
  block-by-block by workers hauling the site's material bill.
- A building is **active** (sockets live, recipe available) only when complete.
- Buildings take damage and can be repaired; destruction removes the building
  and frees its footprint.
- Demo building set: Town Hall, Storage Yard, Lumber Camp, Mine, Smelter,
  Forge, Barracks (tent), Watchtower, Walls, Gate. (Tannery/leather deferred.)

## Raids (fixed)

| Night | Raiders | Target priority        | Purpose                     |
|-------|---------|------------------------|-----------------------------|
| 1     | 2–3     | haulers / supply route | teach that logistics is soft |
| 2     | 4–6     | haulers, then buildings| escalation                  |
| 3     | 8–12    | Town Hall / defenders  | the win check               |

Sizes scale with a difficulty multiplier (Easy 0.7, Normal 1.0, Hard 1.4) and
with elapsed time. Watchtowers fire on raiders in range. All spawns are
validated against the scenario manifest (never inside the safety radius, always
path-reachable to the camp).

## Scenario guarantees (fixed — enforced by the placement pass, §3)

Every shippable seed must provide, all mutually path-reachable:

- A dry, flat camp site with reserved construction space.
- ≥1 of each resource node type within a gather ring of the camp.
- A raider camp **outside** the safety radius (default 24 cells) but reachable.

A seed that cannot satisfy these is rejected and the seed is bumped until one
does (retry/repair). The satisfied manifest is recorded for save/resume.

## Open decisions (recommended defaults, override in playtest)

1. **Ruin in demo v1?** → *In*, as optional scavenge flavor, no carry mechanic.
2. **Chain depth?** → *Two* production buildings (smelter + forge). Tannery is
   the first post-demo content patch.
3. **Raider-camp assault as alt win?** → *In* (gameplan's own condition).
