# Best answer: make **one blocky humanoid rig**, then reuse it forever

You do **not** want to hand-animate every worker/unit. That path ends with you keyframing “tanner scratches nose #4” at 3 AM like a cursed little Pixar intern.

For your game, the best system is:

```text id="51np8w"
One shared blocky humanoid skeleton
↓
One reusable animation library
↓
Data-driven worker/unit roles
↓
Modular clothing/equipment layers
↓
Bone attachments for tools, weapons, backpacks, cloaks
↓
Simple AnimationTree state machine
```

This fits your current plan because your docs already separate workers, units, equipment, roles, storage, recipes, and animations into data-driven modules. The modular layout specifically calls for `worker_animation_controller.gd`, `worker_role_component.gd`, `unit_equipment_component.gd`, `unit_training_component.gd`, and `worker_animation_mapper.gd`, which is exactly where this belongs. 

---

# 1. The visual style I’d use

Not full Minecraft cubes. Use **Minecraft-adjacent block characters**, but with layered detail.

## Character shape

```text id="xfu8vg"
Head       cube/slightly beveled cube
Torso      rectangular cuboid
Upper arms cuboids
Forearms   cuboids
Hands      small cuboids
Legs       cuboids
Feet       small cuboids
```

But add:

```text id="iyxej7"
hair layer
hat layer
shirt/tunic layer
belt layer
cloak layer
tool layer
backpack layer
armor layer
weapon layer
profession badge/color
```

That gives you the readability of Minecraft, but avoids the “everybody is a refrigerator with opinions” problem.

---

# 2. Use one master rig

Make one base scene:

```text id="m8gvkj"
res://scenes/units/base/BlockHumanoid.tscn

BlockHumanoid : CharacterBody3D or Node3D
├── VisualRoot : Node3D
│   ├── Skeleton3D
│   ├── BodyMesh : MeshInstance3D
│   ├── HeadMesh : MeshInstance3D
│   ├── ClothingRoot : Node3D
│   ├── EquipmentRoot : Node3D
│   └── AttachmentRoot : Node3D
├── AnimationPlayer
├── AnimationTree
├── CollisionShape3D
└── WorkerAnimationController.gd
```

Godot’s `Skeleton3D` is the node for a 3D bone hierarchy used by skeletal animation, and `BoneAttachment3D` can dynamically copy a selected bone transform, which is exactly what you want for swords, tools, shields, backpacks, helmets, and carried resources. ([Godot Engine documentation][1]) ([Godot Engine documentation][2])

---

# 3. Minimum animation set

You only need a small library at first.

## Core movement

```text id="3znvqx"
idle
walk
run
turn
carry_walk
carry_idle
```

## Work actions

```text id="qrpuah"
mine
chop
hammer
saw
dig
build
craft
lift
place
pickup
dropoff
```

## Combat

```text id="9m8jbk"
attack_1
attack_2
block
hit_react
die
bow_aim
bow_shoot
```

## Interior actions

```text id="63dxej"
workstation_idle
anvil_hammer
furnace_operate
tanning_work
storage_sort
eat
sleep
sit
```

That is enough for the vertical slice. Your gameplan already says the MVP needs builder, hauler, miner, woodcutter, tanner, smelter, blacksmith, and recruit/soldier roles, so the first animation library should serve those roles before you add fifty medieval freaks with bespoke emotional walks. 

---

# 4. Animation system in Godot

Use:

```text id="tbhn57"
AnimationPlayer = stores/imports animation clips
AnimationTree = controls transitions/blending
WorkerAnimationController = tells AnimationTree what state to play
```

Godot’s docs describe `AnimationPlayer` as a general-purpose animation playback node with animation libraries and blend times, while `AnimationTree` is for advanced transitions. When `AnimationTree` is linked to an `AnimationPlayer`, playback and transitions should be handled through the `AnimationTree`, not by fighting both systems like a raccoon with two steering wheels. ([Godot Engine documentation][3]) ([Godot Engine documentation][4])

## Animation states

```text id="yjj3i5"
idle
walk
carry
work
combat
dead
```

Then jobs map to animations:

```text id="ngfko4"
gather_wood   → chop
mine_ore      → mine
build_block   → build
craft_sword   → hammer
haul_item      → carry_walk
fight_melee    → attack_1
```

This matches your planned `worker_animation_mapper.gd`, which is supposed to map work actions like hammering, carrying, sawing, tanning, reading, healing, repairing, welding, typing, and operating controls to animations. 

---

# 5. Data-driven animation mapper

Make this as a Resource:

```gdscript id="f53ywe"
# res://core_game/workers/worker_animation_mapper.gd
class_name WorkerAnimationMapper
extends Resource

@export var action_to_animation := {
	"idle": "idle",
	"walk": "walk",
	"haul": "carry_walk",
	"pickup": "pickup",
	"dropoff": "dropoff",
	"mine": "mine",
	"chop": "chop",
	"build": "build",
	"hammer": "hammer",
	"saw": "saw",
	"tanning": "tanning_work",
	"fight_melee": "attack_1",
	"die": "die"
}

func get_animation_for_action(action_id: String) -> String:
	return action_to_animation.get(action_id, "idle")
```

Then:

```gdscript id="6gt4p5"
# res://core_game/workers/worker_animation_controller.gd
extends Node

@export var animation_mapper: WorkerAnimationMapper

@onready var animation_tree: AnimationTree = $"../AnimationTree"

var playback: AnimationNodeStateMachinePlayback

func _ready() -> void:
	animation_tree.active = true
	playback = animation_tree.get("parameters/playback")

func play_action(action_id: String) -> void:
	var animation_name := animation_mapper.get_animation_for_action(action_id)
	playback.travel(animation_name)
```

Godot’s state machine transitions can use conditions and expressions, and state machine playback can travel between states, so this style fits Godot’s intended animation workflow instead of building an animation bureaucracy in GDScript. ([Godot Engine documentation][5])

---

# 6. Clothing layers

Do not make a unique model for every worker. Make **modular body slots**.

```text id="omj44o"
Body base
├── skin material
├── hair mesh
├── hat mesh
├── shirt/tunic mesh
├── belt mesh
├── pants mesh
├── boot mesh
├── cloak mesh
├── backpack mesh
├── left hand item
├── right hand item
└── back item
```

## Unit visual definition

```gdscript id="7yeveg"
# res://data/units/unit_visual_definition.gd
class_name UnitVisualDefinition
extends Resource

@export var body_scene: PackedScene
@export var skin_material: Material
@export var hair_scene: PackedScene
@export var hat_scene: PackedScene
@export var torso_layer_scene: PackedScene
@export var cloak_scene: PackedScene
@export var backpack_scene: PackedScene
@export var right_hand_item_scene: PackedScene
@export var left_hand_item_scene: PackedScene
@export var profession_color: Color = Color.WHITE
```

Example:

```text id="lk3e0q"
miner:
  hat = mining_cap
  torso = dirty_tunic
  right_hand_item = pickaxe
  backpack = ore_sack

blacksmith:
  hat = none
  torso = apron
  right_hand_item = hammer
  belt = tool_belt

hauler:
  torso = plain_tunic
  backpack = crate_frame
  carried_item = dynamic

soldier:
  torso = gambeson
  cloak = faction_cloak
  right_hand_item = sword
  left_hand_item = shield
```

This gives you dozens of unit looks from a handful of assets.

---

# 7. How to attach tools and gear

Use `BoneAttachment3D`.

```text id="4tsh3q"
Skeleton3D
├── RightHandAttachment : BoneAttachment3D
│   └── Hammer
├── LeftHandAttachment : BoneAttachment3D
│   └── Shield
├── BackAttachment : BoneAttachment3D
│   └── Backpack
└── HeadAttachment : BoneAttachment3D
    └── Helmet
```

Godot’s `BoneAttachment3D` selects a bone in a `Skeleton3D` and copies or overrides that bone transform, so it is the clean way to make tools follow hands without manually updating transforms every frame like a goblin accountant. ([Godot Engine documentation][2])

---

# 8. Cloaks without pain

For cloaks, start dumb.

## Early cloak

```text id="rrobbx"
A slightly offset rectangular mesh behind the torso
Parented to chest/spine bone
Uses a simple wind/wiggle shader
No cloth physics
```

Use a shader like:

```glsl id="7fq7wb"
shader_type spatial;

uniform float sway_strength = 0.04;
uniform float sway_speed = 3.0;

void vertex() {
	float top_weight = clamp(UV.y, 0.0, 1.0);
	float bottom_weight = 1.0 - top_weight;

	float sway = sin(TIME * sway_speed + VERTEX.y * 2.0) * sway_strength;

	VERTEX.x += sway * bottom_weight;
}
```

Later you can add proper cloth or bone chains. Do not start there. Your game needs workers hauling ore, not one cape auditioning for a tech demo.

---

# 9. Simple procedural walk animation option

For blocky characters, you can avoid some authored animations by procedurally rotating limbs.

This works well for:

```text id="iofjq6"
idle
walk
carry_walk
tool swing variations
look-at head turns
tiny work loops
```

Example:

```gdscript id="10ghxy"
# SimpleBlockWalker.gd
extends Node3D

@export var speed := 6.0
@export var arm_swing_degrees := 28.0
@export var leg_swing_degrees := 32.0

@onready var left_arm: Node3D = $"../VisualRoot/LeftArm"
@onready var right_arm: Node3D = $"../VisualRoot/RightArm"
@onready var left_leg: Node3D = $"../VisualRoot/LeftLeg"
@onready var right_leg: Node3D = $"../VisualRoot/RightLeg"

var t := 0.0

func update_walk(delta: float, movement_speed: float) -> void:
	t += delta * speed * movement_speed

	var swing := sin(t)
	var opposite := sin(t + PI)

	left_arm.rotation_degrees.x = swing * arm_swing_degrees
	right_arm.rotation_degrees.x = opposite * arm_swing_degrees
	left_leg.rotation_degrees.x = opposite * leg_swing_degrees
	right_leg.rotation_degrees.x = swing * leg_swing_degrees
```

This is the fastest “not terrible” method if your characters are built from separate cuboid parts instead of skinned meshes.

## My recommendation

Use both:

```text id="fsmlw1"
Nearby important units:
  Skeleton3D + AnimationTree + proper reusable animations

Distant/background workers:
  procedural limb swing or low-rate animation updates
```

---

# 10. Interiors: fake them first

You are right: early on, workers do **not** need fully simulated interiors.

For MVP:

```text id="prgpd1"
Worker walks to building entrance
↓
Worker disappears or enters simplified interior mode
↓
Timer/action runs
↓
Optional visible worker appears at socket if building selected
↓
Output appears in storage
↓
Worker exits or next hauler arrives
```

Your docs already point toward this by treating buildings as machines with worker sockets, internal paths, storage points, recipes, production timing, output locations, animations, and effects. They also explicitly call for cutaway interiors where roofs/walls hide and workers/storage/production steps become visible. 

So build this in stages:

## Stage 1: Door-only interior

```text id="3gqi8h"
entrance_socket
worker enters
hidden production timer
worker exits
```

## Stage 2: Fake socket preview

```text id="q5jntu"
worker enters
if building selected:
  show worker standing at anvil/tanning rack/storage shelf
else:
  keep hidden
```

## Stage 3: Real internal path graph

```text id="5vuvlm"
entrance → storage → workstation → output rack → exit
```

Your project plan already says Phase 3 should add sockets, storage, and internal paths, with a success condition that a worker can enter the forge, walk to the anvil socket, and exit. 

---

# 11. Entity type system

Use one base entity, then specialize through components.

```text id="2g9l0z"
Entity
├── MovementComponent
├── AnimationComponent
├── InventoryComponent
├── JobComponent
├── EquipmentComponent
├── HealthComponent
├── VisualCustomizationComponent
└── SelectionComponent
```

## Entity categories

```text id="jlye3a"
Worker
  builder
  hauler
  miner
  woodcutter
  tanner
  smelter
  blacksmith
  farmer

Military
  recruit
  swordsman
  archer
  guard
  scout

Animal
  deer
  wolf
  horse
  livestock

Weird stuff
  golem
  slime
  machine drone
  summoned worker
  ghost courier
  rat swarm
```

The trick is: **all of them use the same animation vocabulary where possible.**

```text id="58y4vf"
walk
idle
carry
attack
work
die
```

A golem and a worker can both use `walk`. A blacksmith and a dwarf engineer can both use `hammer`. A slime can use its own simple squash shader/animation later.

---

# 12. Folder additions I’d make now

Your layout already has workers/units/assets folders. I’d add these:

```text id="0e3hhs"
res://data/visuals/
├── unit_visual_definitions/
│   ├── worker_basic.tres
│   ├── miner_basic.tres
│   ├── blacksmith_basic.tres
│   ├── hauler_basic.tres
│   └── swordsman_basic.tres
├── clothing_definitions/
├── equipment_visual_definitions/
└── color_palettes/

res://assets/unit_meshes/block_humanoid/
├── base_body.glb
├── base_skeleton.glb
├── clothing/
├── hair/
├── hats/
├── armor/
├── cloaks/
└── tools/

res://assets/animations/block_humanoid/
├── movement/
├── work/
├── combat/
└── interior/

res://core_game/visuals/
├── unit_visual_builder.gd
├── equipment_attachment_controller.gd
├── clothing_layer_controller.gd
├── unit_palette_randomizer.gd
└── lod_visual_controller.gd
```

Your current `assets/` plan already includes `unit_meshes`, `building_props`, `materials`, `shaders`, and `animations`, so this is not a new architecture. It is just making the unit side less vague before it becomes a pile of “temporary” scenes that survive until release like mold in drywall. 

---

# 13. Practical MVP animation stack

For the first playable version, make only these:

```text id="86v68j"
idle
walk
carry_walk
pickup
dropoff
mine
chop
hammer
build
attack
hit
die
```

Then map roles:

| Role       | Uses                                      |
| ---------- | ----------------------------------------- |
| Builder    | walk, carry, pickup, dropoff, build       |
| Hauler     | walk, carry, pickup, dropoff              |
| Miner      | walk, carry, mine                         |
| Woodcutter | walk, carry, chop                         |
| Tanner     | walk, carry, tanning_work or generic_work |
| Smelter    | walk, carry, furnace_operate              |
| Blacksmith | walk, carry, hammer                       |
| Recruit    | walk, idle                                |
| Swordsman  | walk, attack, hit, die                    |

That gets your settlement alive without requiring an animation department, which sadly you do not appear to have hidden under the desk.

---

# 14. The cleanest build order

## Step 1: Make the block humanoid

```text id="xnr4e9"
base body
skeleton
idle animation
walk animation
AnimationPlayer
AnimationTree
```

## Step 2: Add role visuals

```text id="nf8j2v"
miner hat + pickaxe
blacksmith apron + hammer
hauler backpack/crate
swordsman sword + shield
```

## Step 3: Add animation mapper

```text id="p78jkj"
job action → animation name
```

## Step 4: Connect to worker state machine

```text id="n75a0h"
Idle state       → idle
Moving state     → walk
Hauling state    → carry_walk
Crafting state   → hammer/tanning/sawing
Combat state     → attack
```

## Step 5: Add building sockets

```text id="8fjqqd"
entrance_socket
work_socket
storage_socket
output_socket
```

## Step 6: Add fake interiors

```text id="8er35g"
worker enters
worker appears at socket only when building selected
recipe runs
output appears
```

## Step 7: Add real interiors later

```text id="kbdisq"
internal path graph
cutaway
worker routes
storage visualization
```

---

# 15. The rule that will save you

Every unit should be:

```text id="78ilx0"
logic identity ≠ visual identity
```

Meaning:

```text id="tg8wy6"
Worker role:
  blacksmith

Visual:
  body type A
  skin 3
  hair 7
  apron 2
  hammer 1
  cloak none
  faction color red

Animation:
  humanoid_basic
```

Do **not** make:

```text id="pfb82f"
BlacksmithScene
MinerScene
HaulerScene
TannerScene
SmelterScene
BuilderScene
SoldierScene
```

That way lies duplicated scripts, broken fixes, and the quiet sobbing of future-you.

Make:

```text id="a5r58p"
UnitAgent.tscn
+ UnitDefinition
+ UnitVisualDefinition
+ WorkerRoleDefinition
+ EquipmentDefinition
```

That matches the system you already planned: generic workers, units, roles, equipment, training, and data definitions instead of hardcoded creature soup. 

---

# Final recommendation

Build a **modular block-humanoid character system**:

```text id="81414f"
One rig
One animation library
One AnimationTree
Many visual layer combinations
Many roles
Many equipment attachments
Few actual authored animations
```

For the vertical slice:

```text id="6t5gpe"
Do:
  workers walking
  carrying items
  mining/chopping/building/hammering
  swordsman combat
  tools attached to hands
  profession clothing layers

Do not:
  full interiors yet
  cloth physics
  unique animations per profession
  unique rig per unit
  complex civilian needs
  hundreds of entity types
```

The goal is not “perfect little people.” The goal is a readable working machine: miners extract, haulers carry, blacksmiths hammer, soldiers equip swords, and the player can see why the settlement works or fails. Your own plan says that is the heart of the game. 

[1]: https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html "Skeleton3D — Godot Engine (stable) documentation in English"
[2]: https://docs.godotengine.org/en/stable/classes/class_boneattachment3d.html "BoneAttachment3D — Godot Engine (stable) documentation in English"
[3]: https://docs.godotengine.org/en/4.7/classes/class_animationplayer.html "AnimationPlayer — Godot Engine (4.7) documentation in English"
[4]: https://docs.godotengine.org/en/4.7/classes/class_animationtree.html "AnimationTree — Godot Engine (4.7) documentation in English"
[5]: https://docs.godotengine.org/en/4.7/classes/class_animationnodestatemachinetransition.html "AnimationNodeStateMachineTransition — Godot Engine (4.7) documentation in English"
