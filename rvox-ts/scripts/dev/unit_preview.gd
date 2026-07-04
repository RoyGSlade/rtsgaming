extends Node3D

## Dev-only preview: spawns the soldier Unit up close with a front camera and
## light so item-attachment offsets can be tuned in isolation (no terrain).
## Run via the custom-scene launcher; not part of the shipping game.

const SOLDIER_ATTACHMENTS := [
	{"scene": "res://assets/models/items/sword.glb", "bone": "mixamorig:RightHand",
	 "position": Vector3(0.0, 0.0, 0.0), "rotation_deg": Vector3(0.0, 0.0, 0.0), "scale": 1.0},
	{"scene": "res://assets/models/items/shield.glb", "bone": "mixamorig:LeftForeArm",
	 "position": Vector3(0.0, 0.16, -0.10), "rotation_deg": Vector3(-90.0, 0.0, 0.0), "scale": 1.0},
]


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

	var soldier := Unit.new()
	soldier.model_path = "res://assets/models/soldier.glb"
	soldier.idle_clip = "Idle"
	soldier.walk_clip = "Walk"
	soldier.run_clip = "Run"
	soldier.loop_clips = PackedStringArray(["Idle", "Walk", "Run", "BlockIdle"])
	soldier.attachments = SOLDIER_ATTACHMENTS
	add_child(soldier)

	var cam := Camera3D.new()
	cam.position = Vector3(-2.0, 1.3, 1.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.make_current()
