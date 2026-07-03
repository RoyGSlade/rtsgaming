class_name TerrainMaterialResolver
extends RefCounted

static func make_debug_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.45, 0.65, 0.35)
    return material
