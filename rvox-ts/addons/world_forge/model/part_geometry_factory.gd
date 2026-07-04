@tool
class_name PartGeometryFactory
extends RefCounted

## Builds a preview mesh for a PartProfile from its geometry_kind/
## geometry_params - the part-scale sibling of ShapeGeometryFactory. Parts
## have no neighbor-connection concept (that's a block-shape thing), so this
## is simpler: one procedural primitive (or the authored custom_mesh) per
## part, oriented so PartProfile.long_axis - not always local Z - is where
## the cylinder's height points; a vessel's long_axis is Y (it stands
## upright), while rod/axle/wheel-like parts default to Z (their end/bore
## sockets are authored along Z). See PartProfile.occupancy_for_cylinder,
## which reads the same field so a part's rendered shape and its occupied
## cells never disagree.


static func create_part(part: PartProfile, material: Material) -> Node3D:
	var root := Node3D.new()
	match part.geometry_kind:
		PartProfile.GeometryKind.BOX:
			var size: Vector3 = part.geometry_params.get("size", Vector3.ONE)
			_add_box(root, size, material)
		PartProfile.GeometryKind.CYLINDER:
			var radius: float = float(part.geometry_params.get("radius", 0.1))
			var height: float = float(part.geometry_params.get("height", 1.0))
			_add_cylinder(root, radius, height, part.long_axis, material)
		PartProfile.GeometryKind.SPHERE:
			var radius: float = float(part.geometry_params.get("radius", 0.1))
			_add_sphere(root, radius, material)
		PartProfile.GeometryKind.CUSTOM:
			if part.custom_mesh != null:
				_add_mesh(root, part.custom_mesh, material)
	return root


static func _add_box(root: Node3D, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add_mesh(root, mesh, material)


static func _add_cylinder(root: Node3D, radius: float, height: float, long_axis: Vector3, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var instance := _add_mesh(root, mesh, material)
	# CylinderMesh's height runs along local +Y by default; rotate so it
	# runs along long_axis instead. Quaternion(from, to) is the shortest-arc
	# rotation mapping `from` onto `to`; a zero-length axis (misconfigured
	# data) falls back to the untouched +Y default rather than dividing by
	# zero inside Quaternion's normalization.
	if not long_axis.is_zero_approx():
		instance.quaternion = Quaternion(Vector3.UP, long_axis.normalized())


static func _add_sphere(root: Node3D, radius: float, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	_add_mesh(root, mesh, material)


static func _add_mesh(root: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	root.add_child(instance)
	return instance
