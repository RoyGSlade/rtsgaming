extends Node3D

## Dev-only preview: spawns every creature model walking toward +X (screen
## right from the default camera) so facing offsets and visual glitches can
## be checked in isolation (no terrain). Run via the custom-scene launcher;
## not part of the shipping game.

const MODELS := [
	"res://assets/models/deer.glb",
	"res://assets/models/rabbit.glb",
	"res://assets/models/evilwolf.glb",
	"res://assets/models/zombie.glb",
	"res://assets/models/slime.glb",
]
const SPACING := 1.6
## Facing offsets under test - mirror of CREATURE_SPAWNS in game_main.gd.
## With correct values every creature walks head-first to screen right.
const OFFSETS := [PI, PI, PI, PI, 0.0]


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.72)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	add_child(light)

	for i in MODELS.size():
		var creature := Creature.new()
		creature.model_path = MODELS[i]
		creature.facing_offset = OFFSETS[i]
		creature.move_speed = 0.4  # slow crawl: stays in frame for screenshots
		creature.wander_radius = 0.0
		add_child(creature)
		creature.global_position = Vector3(-1.0, 0.0, (i - MODELS.size() * 0.5) * SPACING + SPACING * 0.5)
		creature.walk_to(creature.global_position + Vector3(100.0, 0.0, 0.0))

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 6.0, 5.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	cam.make_current()
