extends Node3D

@export var config: WorldGenConfig
@export var preview_size: int = 16
@export var cube_size: float = 1.0
@export var show_only_surface: bool = true

var generator := WorldGenerator.new()
var water_simulator := WaterFlowSimulator.new()

const PRESETTLE_TICKS := 200

func _ready() -> void:
    if config == null:
        config = WorldGenConfig.new()
        config.chunk_size = preview_size
        config.max_height = 32
        config.water_level = 10
        config.world_seed = 1337
    _generate_debug_preview()

func _generate_debug_preview() -> void:
    var chunk := generator.generate_chunk(Vector2i.ZERO, config, water_simulator)
    for i in PRESETTLE_TICKS:
        water_simulator.tick(chunk)

    var min_h := 999999
    var max_h := -999999
    for x in chunk.chunk_size:
        for z in chunk.chunk_size:
            var h := chunk.get_surface_height(x, z)
            min_h = min(min_h, h)
            max_h = max(max_h, h)

    print("WorldDebugViewer chunk generated")
    print("min height: %s, max height: %s" % [min_h, max_h])
    print("grass: %s, stone: %s, water: %s, iron: %s" % [
        chunk.count_block(&"grass"),
        chunk.count_block(&"stone"),
        chunk.count_block(&"water"),
        chunk.count_block(&"iron_ore")
    ])

    _draw_tiny_preview(chunk)

func _draw_tiny_preview(chunk: ChunkData) -> void:
    var mesh := BoxMesh.new()
    mesh.size = Vector3.ONE * cube_size

    for x in min(preview_size, chunk.chunk_size):
        for z in min(preview_size, chunk.chunk_size):
            if show_only_surface:
                var y := chunk.get_surface_height(x, z)
                _spawn_cube(mesh, Vector3(x, y, z), chunk.get_block(x, y, z))
                var spans := water_simulator.get_column_spans(chunk, x, z)
                if not spans.is_empty():
                    var span: WaterSpan = spans[0]
                    _spawn_cube(mesh, Vector3(x, span.surface_y, z), &"water")
            else:
                for y in chunk.max_height:
                    var id := chunk.get_block(x, y, z)
                    if id != &"air":
                        _spawn_cube(mesh, Vector3(x, y, z), id)

func _spawn_cube(mesh: Mesh, pos: Vector3, block_id: StringName) -> void:
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.position = pos * cube_size
    mi.material_override = _make_material(block_id)
    add_child(mi)

func _make_material(block_id: StringName) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    match block_id:
        &"grass": material.albedo_color = Color(0.25, 0.65, 0.2)
        &"dirt": material.albedo_color = Color(0.36, 0.22, 0.12)
        &"stone": material.albedo_color = Color(0.45, 0.45, 0.45)
        &"deep_stone": material.albedo_color = Color(0.25, 0.25, 0.28)
        &"sand": material.albedo_color = Color(0.82, 0.74, 0.45)
        &"snow": material.albedo_color = Color(0.9, 0.93, 0.95)
        &"water":
            material.albedo_color = Color(0.1, 0.35, 0.85, 0.55)
            material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        &"iron_ore": material.albedo_color = Color(0.55, 0.36, 0.25)
        &"coal_ore": material.albedo_color = Color(0.08, 0.08, 0.08)
        &"copper_ore": material.albedo_color = Color(0.75, 0.35, 0.15)
        _: material.albedo_color = Color(0.8, 0.2, 0.8)
    return material
