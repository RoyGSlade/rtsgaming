# Voxel RTS Overall Gameplan

## Working Title

**Crown & Circuit**

Alternative labels:
- Voxel RTS
- Visible Supply Chain RTS
- Block-Built Civilization RTS
- Stronghold + Satisfactory + Cities: Skylines, but with workers physically building and using block-based structures

---

# Core Pitch

A block-built civilization RTS where players gather resources, design and place building blueprints, watch workers physically construct those buildings block by block, and manage visible production chains from raw materials to finished goods.

The player starts with a small fantasy settlement and grows through eras toward industry, modern systems, and eventually sci-fi civilization.

The magic is not just that buildings exist. The magic is that the player can see how the world works.

```text
Miner extracts raw ore
↓
Hauler carries ore to smelter
↓
Smelter makes iron ingots
↓
Tanner delivers leather wraps
↓
Woodworker delivers handles
↓
Blacksmith crafts sword at forge
↓
Sword appears on rack
↓
Soldier equips sword
↓
Army defends the settlement
```

That is the heart of the game.

---

# Design Pillars

## 1. Visible Production Chains

Resources physically move through the world.

The player should be able to see:
- raw ore leaving mines
- ingots entering forges
- leather wraps leaving tanneries
- swords appearing on racks
- food going to homes
- stone going to construction sites
- damaged buildings requesting repair materials

The economy should be readable through motion, not only UI numbers.

---

## 2. Block-Built Construction

Buildings are not spawned instantly from abstract costs.

They are:
- designed as blueprints in the building editor
- placed as ghost structures by the player
- broken into required blocks/materials
- constructed by workers in stages
- damaged and repaired block by block

This makes building placement, logistics, roads, storage, and worker assignment matter.

---

## 3. Buildings Are Machines

Every building has interior logic.

A building blueprint contains:
- blocks
- roof/wall/interior layers
- worker sockets
- internal pathing
- storage points
- recipes
- production timing
- output locations
- animations
- effects
- damage behavior

A forge is not just a forge mesh. It is a working machine.

---

## 4. Cutaway Interiors

Players can inspect buildings.

When a building is selected:
- roof can hide or fade
- front walls can hide
- workers become visible
- storage can be highlighted
- production steps can be shown
- bottlenecks can be explained

This lets the player watch a blacksmith make a sword, a tanner prepare leather, a medic treat a patient, or a scientist research an upgrade.

---

## 5. Logistics Create Strategy

The player wins by understanding flow.

Questions the player constantly answers:
- Where are resources coming from?
- Where are they stored?
- Who is carrying them?
- What road do they use?
- What building is waiting on them?
- What is the bottleneck?
- What breaks if enemies attack this route?

That is where the game becomes more than another RTS with a fake economy and a tiny angry man yelling at a barracks.

---

## 6. Era Progression

The game starts fantasy/medieval and grows into future technology.

Example era path:

```text
Survival Camp
↓
Village
↓
Kingdom
↓
Arcane/Renaissance
↓
Industrial
↓
Modern
↓
Sci-Fi
```

The same systems continue across eras.

Example:

```text
Basic Forge
↓
Ironworks
↓
Industrial Foundry
↓
Automated Factory
↓
Nanoforge
```

No system gets thrown away. It evolves.

---

# MVP Target

## MVP Name

**The Iron Sword Vertical Slice**

## MVP Goal

Prove the full core loop with one production chain and one combat payoff.

The player should be able to:

1. Gather raw materials.
2. Build production buildings from block blueprints.
3. Watch workers carry resources through the chain.
4. Produce an iron sword.
5. Equip a soldier with that sword.
6. Defend against a small raid.

If this works, the game is real.

---

# MVP Systems

## Buildings

Required MVP buildings:

```text
Town Hall
House
Storage Yard
Mine
Lumber Camp
Tannery
Smelter
Forge
Barracks
Watchtower
```

## Resources

Required MVP resources:

```text
wood
stone
raw_ore
coal
iron_ingot
raw_hide
leather_wrap
wood_handle
iron_sword
food
```

## Workers

Required MVP workers:

```text
builder
hauler
miner
woodcutter
tanner
smelter
blacksmith
recruit/soldier
```

## Production Chain

Primary MVP chain:

```text
Mine → raw_ore
Mine/coal node → coal
Smelter → iron_ingot
Hunter/Ranch/Tannery source → raw_hide
Tannery → leather_wrap
Lumber Camp → wood
Carpenter or Forge sub-step → wood_handle
Forge → iron_sword
Barracks → swordsman
```

For the first playable version, `wood_handle` can be produced directly at the forge or from a simple woodworker station. Do not overbuild the chain before proving the loop. Civilization can tolerate one abstraction. Barely.

---

# Core Gameplay Loop

```text
Explore
↓
Gather
↓
Store
↓
Build
↓
Produce
↓
Equip
↓
Defend
↓
Expand
↓
Research
↓
Repeat at larger scale
```

---

# Development Phases

## Phase 0: Project Foundation

Goal:
Create the Godot project, folder layout, base architecture, and developer rules.

Deliverables:
- Godot project created
- Git repo initialized
- modular folder layout created
- base scenes created
- style guide written
- debug overlay stubbed
- test map created

Success criteria:
- Project opens cleanly.
- Main test scene runs.
- Camera can move around a simple grid.

---

## Phase 1: Block Building Editor Prototype

Goal:
Build the first version of the editor that creates a building blueprint.

Deliverables:
- editor plugin loads
- 3D grid viewport
- camera movement/orbit/zoom
- block palette
- place/remove blocks
- save/load blueprint
- export blueprint data

Test building:

```text
Basic Forge Shell
```

Success criteria:
- Designer can make a simple forge from blocks.
- Blueprint saves and reloads.
- Runtime can read the blueprint.

---

## Phase 2: Layers and Cutaway

Goal:
Let buildings support roof hiding and interior inspection.

Deliverables:
- layer assignment tool
- roof/wall/interior tags
- cutaway profiles
- runtime layer hiding/fading
- selected building cutaway view

Success criteria:
- Forge roof can hide when selected in-game.
- Interior blocks and workstations remain visible.

---

## Phase 3: Sockets, Storage, and Internal Paths

Goal:
Make the building blueprint functional, not just visual.

Deliverables:
- socket placement tool
- worker stand sockets
- entrance sockets
- material dropoff sockets
- output pickup sockets
- storage slots
- internal path graph
- path validation

Success criteria:
- A worker can enter the forge, walk to the anvil socket, and exit.
- Storage slots can display fake resources.

---

## Phase 4: Construction System

Goal:
Workers build placed blueprints block by block.

Deliverables:
- building placement ghost
- construction site runtime object
- required block/material list
- construction jobs
- worker builder behavior
- material reservation
- staged visual construction

Success criteria:
- Player places forge blueprint.
- Workers carry wood/stone/etc. to site.
- Workers build blocks in valid order.
- Forge becomes active when complete.

---

## Phase 5: Resource Gathering and Storage

Goal:
Create the basic economy foundation.

Deliverables:
- resource nodes
- worker gathering
- storage yard
- storage inventory
- hauling jobs
- visible carried items
- resource bar UI

Success criteria:
- Workers gather wood, stone, raw ore, coal, and hide.
- Haulers move resources to storage.
- Construction can consume stored resources.

---

## Phase 6: Production Chains

Goal:
Make resources flow through buildings into finished goods.

Deliverables:
- recipe runtime
- production queues
- input/output storage mapping
- worker crafting behavior
- production timing
- visual storage updates
- bottleneck detection

MVP chain:

```text
raw_ore + coal → iron_ingot
raw_hide → leather_wrap
wood → wood_handle
iron_ingot + leather_wrap + wood_handle → iron_sword
```

Success criteria:
- Player can watch ingots/leather/handles enter forge.
- Blacksmith crafts sword at anvil.
- Sword appears on weapon rack/output storage.

---

## Phase 7: Units, Equipment, and Combat

Goal:
Turn produced goods into military power.

Deliverables:
- recruit unit
- soldier/swordsman unit
- equipment component
- armory/barracks storage
- unit training
- basic combat
- enemy raider
- watchtower defense

Success criteria:
- Sword from forge goes to barracks/armory.
- Recruit equips sword.
- Recruit becomes swordsman.
- Swordsman can fight raiders.

---

## Phase 8: UI and Player Readability

Goal:
Make the system understandable.

Deliverables:
- production chain view
- building inspector
- bottleneck panel
- worker inspector
- resource flow highlights
- alert panel
- construction progress UI

Success criteria:
- Player can click Iron Sword and see what inputs are missing.
- Player can click forge and see current storage, workers, recipe, and output.
- Player can understand why production stopped.

---

## Phase 9: First Playable Scenario

Goal:
Build a small playable scenario around the sword chain.

Scenario:

```text
You start with a Town Hall, a few workers, and nearby resources.
You must build a forge economy and produce enough swordsmen before raiders attack.
```

Win condition:
- Survive 3 raids, or destroy the raider camp.

Loss condition:
- Town Hall destroyed, or population collapses.

Success criteria:
- The game has a beginning, middle, and end.
- A player can understand and complete the scenario without developer explanation, because apparently users hate telepathy.

---

## Phase 10: Expansion Toward Real Game

Goal:
Expand from vertical slice into full game systems.

Next additions:
- farms and food chain
- housing and population
- roads and carts
- research
- AI enemy camps
- diplomacy/trade stub
- building upgrades
- damage/repair by blocks
- more weapons/tools
- first era transition

Success criteria:
- The game is no longer just a prototype.
- The systems can support multiple chains and larger settlement planning.

---

# First Vertical Slice Detail

## Scenario Name

**The First Sword**

## Player Start

```text
Buildings:
- Town Hall
- Storage Yard
- 2 Houses

Workers:
- 4 generic workers

Nearby Resources:
- forest
- stone
- iron ore
- coal
- deer/hide source
```

## Player Objective

```text
Produce 3 iron swords and train 3 swordsmen before the raid arrives.
```

## Required Player Actions

1. Assign workers to gather wood and stone.
2. Build mine.
3. Build smelter.
4. Build tannery.
5. Build forge.
6. Produce iron ingots.
7. Produce leather wraps.
8. Produce iron swords.
9. Build barracks.
10. Train/equip swordsmen.
11. Defend raid.

## Player Learning

This scenario teaches:
- gathering
- storage
- construction
- production chains
- worker jobs
- bottlenecks
- equipment-based unit creation
- defense

---

# MVP Data Set

## Blocks

```text
stone_foundation
wood_floor
wood_wall
stone_wall
roof_thatch
roof_tile
anvil
forge_furnace
crate
weapon_rack
ingot_shelf
leather_hook
coal_bin
```

## Buildings

```text
town_hall
house
storage_yard
mine
smelter
tannery
forge
barracks
watchtower
```

## Resources

```text
wood
stone
raw_ore
coal
iron_ingot
raw_hide
leather_wrap
wood_handle
iron_sword
food
```

## Recipes

```text
smelt_iron_ingot:
  inputs: raw_ore x2, coal x1
  output: iron_ingot x1
  building: smelter

make_leather_wrap:
  inputs: raw_hide x1
  output: leather_wrap x2
  building: tannery

make_wood_handle:
  inputs: wood x1
  output: wood_handle x2
  building: forge or carpenter

craft_iron_sword:
  inputs: iron_ingot x2, leather_wrap x1, wood_handle x1
  output: iron_sword x1
  building: forge
```

## Worker Roles

```text
builder
hauler
miner
smelter
tanner
blacksmith
soldier
```

---

# Architecture Priorities

## Priority 1: Data-Driven Buildings

Do not hardcode building logic unless absolutely necessary.

Buildings should load:
- blocks
- layers
- sockets
- recipes
- workers
- storage
- paths
- construction rules

from blueprint data.

---

## Priority 2: Generic Job System

Most worker behavior should be driven by jobs:

```text
gather_job
haul_job
construct_job
repair_job
craft_job
train_job
fight_job
```

The worker should not need custom code for every building.

---

## Priority 3: Shared Resource Movement

Construction and production both use the logistics system.

A worker carrying a stone block to a construction site and a worker carrying leather wraps to a forge are the same class of problem:

```text
move item from source to destination
```

Solve it once.

---

## Priority 4: Debug Tools Early

This game will become hard to debug quickly.

Build these early:
- pathing debug view
- worker state inspector
- job board view
- storage/reservation inspector
- production bottleneck report
- construction site inspector

Otherwise you will spend hours wondering why Bob refuses to deliver leather, only to discover Bob reserved the item, forgot the route, and is standing inside a barrel. Classic Bob.

---

# Major Risks

## Risk 1: Too Many Systems Too Early

The idea is big.

Do not start with:
- multiplayer
- AI cities
- sci-fi era
- giant maps
- complex citizens
- advanced diplomacy
- full voxel terrain destruction

Start with one chain and one scenario.

---

## Risk 2: Node Count and Performance

Block-built buildings can create too many nodes.

Solution:
- keep editor blocks individual
- bake runtime visual blocks by layer
- keep only interactable blocks as separate nodes
- group visual-only blocks into meshes

---

## Risk 3: Pathing Complexity

Workers need external and internal pathing.

Solution:
- world grid pathing outside buildings
- simplified internal path graphs inside buildings
- connect them through entrance sockets

---

## Risk 4: Player Readability

Visible systems can become visual noise.

Solution:
- strong UI filters
- production chain view
- bottleneck explanations
- cutaway mode
- resource flow highlighting

---

## Risk 5: Scope Creep

The project naturally wants to become Stronghold, Satisfactory, RimWorld, Cities: Skylines, Factorio, Minecraft, and a light snack.

Solution:
- vertical slice first
- one chain first
- one map first
- one enemy first
- one win condition first

---

# Development Order

## Sprint 1: Godot Foundation

- create project
- create folder layout
- add main test scene
- add RTS camera
- add grid floor
- add debug overlay stub

Output:
- camera moves over test grid

---

## Sprint 2: Building Editor Block Placement

- plugin bootstraps
- editor viewport exists
- block palette exists
- place/remove blocks
- save/load simple blueprint

Output:
- make a simple forge shell

---

## Sprint 3: Blueprint Runtime Placement

- load blueprint in game
- preview ghost building
- validate placement
- place construction site

Output:
- place forge blueprint in runtime map

---

## Sprint 4: Worker Movement and Jobs

- spawn workers
- job board
- worker state machine
- movement/pathing
- basic hauling job

Output:
- worker can move item from storage to target

---

## Sprint 5: Block Construction

- construction site reads blueprint blocks
- material requirements generated
- worker builds block by block
- staged construction visuals

Output:
- workers build the forge

---

## Sprint 6: Layers and Cutaway

- tag roof blocks
- hide roof when building selected
- show inside building

Output:
- click forge, roof hides, interior visible

---

## Sprint 7: Storage and Visible Items

- storage zones
- storage reservations
- visual resource slots
- haulers deliver resources

Output:
- ingots/supplies appear in forge storage

---

## Sprint 8: Recipes and Production

- recipe runtime
- worker sockets
- production timing
- output resource creation

Output:
- blacksmith crafts sword inside forge

---

## Sprint 9: Equipment and Soldiers

- barracks
- recruit
- armory/sword storage
- equip sword
- create swordsman

Output:
- sword becomes usable military equipment

---

## Sprint 10: Raid Scenario

- raider enemy
- combat
- watchtower
- simple win/loss

Output:
- first complete playable scenario

---

# Release Path

## Prototype

Goal:
Prove systems.

Content:
- ugly placeholder assets
- one chain
- one scenario
- one enemy type

## Vertical Slice

Goal:
Prove fun and readability.

Content:
- polished forge chain
- cutaway interiors
- visible logistics
- raid defense
- bottleneck UI

## Alpha

Goal:
Expand systems.

Content:
- food chain
- more buildings
- more resources
- road logistics
- research
- basic AI towns

## Early Access Candidate

Goal:
Create replayable game.

Content:
- multiple maps
- several enemy types
- trade
- diplomacy stub
- multiple win/loss conditions
- first era transition

---

# Definition of Fun

The game is working when the player can say:

```text
I need more swords.
Why are swords slow?
The forge has no leather wraps.
Why no leather wraps?
The tannery has no hide.
Why no hide?
Hunters are too far away.
I need a road, more hunters, or a ranch.
```

Then the player makes a physical change to the world and sees the chain improve.

That is the whole game.

---

# Final Target Experience

The player should be able to zoom into their settlement and see:

- builders placing blocks
- roofs hiding on selected buildings
- blacksmiths crafting swords
- tanners preparing leather
- miners delivering ore
- smelters producing ingots
- haulers moving goods
- soldiers grabbing weapons
- roads filling with commerce
- enemies disrupting supply chains
- damaged buildings requesting repairs
- cities evolving across eras

The world should feel like a working machine made of people, blocks, roads, storage, and decisions.

That is the game.
