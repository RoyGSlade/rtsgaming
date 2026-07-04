@tool
class_name PartProfile
extends Resource

## A stock part usable in the part-scale "Workshop" (fine-grid component
## crafting) - a steel rod, a wood beam, a wheel. The part-scale sibling of
## BlockShapeProfile. Geometry is parametric like block shapes today so parts
## don't require modeled meshes before the Workshop viewport exists; a
## PartGeometryFactory (Phase 3) builds previews from geometry_kind/params the
## same way ShapeGeometryFactory builds block previews.
## See docs/WORLD_FORGE_CRAFTING_PLAN.md section 3.

enum Category { STRUCTURAL, MECHANICAL, FLEXIBLE, VESSEL, TOOL }
enum GeometryKind { BOX, CYLINDER, SPHERE, CUSTOM }

@export var id: StringName = &""
@export var display_name := "Part"
@export var category := Category.STRUCTURAL
@export var geometry_kind := GeometryKind.BOX
## Parametric dimensions read by the (future) PartGeometryFactory, e.g.
## {"size": Vector3(0.05, 0.05, 1.0)} for a rod or {"radius": 0.4, "height": 0.08}
## for a wheel. Ignored when geometry_kind == CUSTOM.
@export var geometry_params: Dictionary = {}
## For CYLINDER parts: which local axis the cylinder's height runs along.
## Rod/axle/wheel-like parts point their functional axis along Z (matching
## their end/bore sockets); a vessel that stands upright (a crucible) uses Y
## instead. PartGeometryFactory and occupancy_for_cylinder() both read this
## so a part's rendered orientation and its occupied cells always agree.
## Ignored for BOX/SPHERE/CUSTOM.
@export var long_axis := Vector3(0.0, 0.0, 1.0)
@export var custom_mesh: Mesh
## Placeholder render tint until real per-material textures exist (mirrors
## FunctionalComponentDefinition.color, added for the same reason).
@export var color := Color.LIGHT_GRAY
@export var collision_boxes: Array[AABB] = [AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)]
@export var material_id: StringName = &""
## Fine-grid cells (1/8 block each) this part occupies, for overlap checks.
@export var occupancy: Array[Vector3i] = [Vector3i.ZERO]
## Typed attach points: {id, position, axis, kinds: [...], accepts: [...]}.
## kinds/accepts use the socket vocabulary from plan section 5 (weld, hinge,
## bearing, slider, rope_anchor, power_shaft, item_port, heat_contact).
@export var sockets: Array[Dictionary] = []
## 0 = derive from material density * bounds volume via resolved_mass_kg().
@export var mass_kg := 0.0
## Which recipe produces this stock (rolling, sawing, casting...).
@export var stock_recipe_id: StringName = &""


func bounds_volume_m3() -> float:
	var total := 0.0
	for box: AABB in collision_boxes:
		total += absf(box.size.x * box.size.y * box.size.z)
	return total


func resolved_mass_kg(material: MaterialProperties) -> float:
	if mass_kg > 0.0:
		return mass_kg
	if material == null:
		return 0.0
	return material.mass_for_volume(bounds_volume_m3())


func sockets_of_kind(kind: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for socket: Dictionary in sockets:
		var kinds: Array = socket.get("kinds", [])
		if kind in kinds:
			matches.append(socket)
	return matches


## Fine-grid cells a box of the given metric size would occupy, cell-aligned
## from its minimum corner. Used to derive occupancy from geometry_params
## instead of hand-authoring it.
static func occupancy_for_box(size: Vector3, cell_size: float = 0.125) -> Array[Vector3i]:
	var counts := Vector3i(
		maxi(1, ceili(size.x / cell_size)),
		maxi(1, ceili(size.y / cell_size)),
		maxi(1, ceili(size.z / cell_size)),
	)
	var cells: Array[Vector3i] = []
	for x in counts.x:
		for y in counts.y:
			for z in counts.z:
				cells.append(Vector3i(x, y, z))
	return cells


## Fine-grid cells a cylinder of the given radius/height would occupy, using
## its bounding box (a true disc rasterization is future polish - nothing
## consumes occupancy for overlap-checking yet, so the approximation used to
## hand-author parts/wheel.tres etc. in Step 1 is reproduced here exactly).
## long_axis picks which of the box's three dimensions gets `height`; the
## other two get the diameter. Only the dominant component of long_axis is
## used (parts are axis-aligned - no diagonal cylinders in this system).
static func occupancy_for_cylinder(radius: float, height: float, long_axis := Vector3(0.0, 0.0, 1.0), cell_size: float = 0.125) -> Array[Vector3i]:
	var diameter := radius * 2.0
	var size := Vector3(diameter, diameter, diameter)
	var ax := absf(long_axis.x)
	var ay := absf(long_axis.y)
	var az := absf(long_axis.z)
	if ax >= ay and ax >= az:
		size.x = height
	elif ay >= az:
		size.y = height
	else:
		size.z = height
	return occupancy_for_box(size, cell_size)
