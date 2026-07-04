@tool
class_name PartKineticsCompiler
extends RefCounted

## Compiles a Workshop document's placed_parts + recorded joints (see
## world_forge_main.gd's _place_part_at_fine_cell, which records a joint
## entry whenever PartSnapResolver finds a snap at placement time) into
## rigid-body groups and physics joints - the plan's "weld-merge is the
## golden rule; joints only where something actually moves" (plan section
## 9). Parts connected via a shared "weld" kind merge into ONE group (no
## physics joint, no ongoing cost - a fully-welded chair compiles to a
## single body); hinge/bearing/slider produce a real joint BETWEEN two
## separate groups. power_shaft/item_port/heat_contact/rope_anchor
## connections are recorded as logical_connections instead of physics
## joints - those are later phases (power network, thermal graph, rope)
## per the plan's phased roadmap; this compiler's job is only the kinetics
## slice (Phase 5).
##
## Output is plain data (a Dictionary), not yet Godot physics nodes, so the
## grouping/joint-classification logic - the part worth getting right - is
## testable without a live SceneTree or physics server.

## Kinds that become a real Godot physics joint between two groups.
## Everything else that connects two groups (power_shaft, item_port,
## heat_contact, rope_anchor) is recorded in logical_connections instead.
const PHYSICS_JOINT_KINDS := ["hinge", "bearing", "slider"]


## part_lookup: Callable(part_id: StringName) -> PartProfile
## material_lookup: Callable(material_id: StringName) -> MaterialProperties
## Returns {"groups": Array[Dictionary], "joints": Array[Dictionary],
## "logical_connections": Array[Dictionary]}. A group is
## {"id", "member_keys": Array[String], "mass_kg": float}. A joint/
## logical_connection is {"kind", "group_a", "group_b", "position", "axis"}.
static func compile(document: ForgeDocument, part_lookup: Callable, material_lookup: Callable) -> Dictionary:
	var keys: Array = document.placed_parts.keys()
	var group_of := {} # placed-part key -> union-find parent key
	for key: String in keys:
		group_of[key] = key

	# Pass 1: walk every recorded joint, union weld-connected parts, and
	# collect every non-weld connection for pass 2 (grouping must finish
	# before joints can be expressed in terms of final group ids).
	var pending: Array[Dictionary] = []
	for key: String in keys:
		var placed: Dictionary = document.placed_parts[key]
		var own_part: PartProfile = part_lookup.call(StringName(str(placed.get("part_id", ""))))
		if own_part == null:
			continue
		var own_position := ForgeDocument.placed_part_world_position(placed)
		var own_steps := int(placed.get("rotation_steps", 0))
		var own_world_sockets := PartSnapResolver.world_sockets(own_part, own_position, own_steps)
		for joint: Dictionary in placed.get("joints", []):
			var target_key := str(joint.get("target_key", ""))
			if not document.placed_parts.has(target_key):
				continue
			var target_placed: Dictionary = document.placed_parts[target_key]
			var target_part: PartProfile = part_lookup.call(StringName(str(target_placed.get("part_id", ""))))
			if target_part == null:
				continue
			var target_position := ForgeDocument.placed_part_world_position(target_placed)
			var target_steps := int(target_placed.get("rotation_steps", 0))
			var target_world_sockets := PartSnapResolver.world_sockets(target_part, target_position, target_steps)
			var own_socket := _find_socket(own_world_sockets, str(joint.get("own_socket", "")))
			var target_socket := _find_socket(target_world_sockets, str(joint.get("target_socket", "")))
			if own_socket.is_empty() or target_socket.is_empty():
				continue
			var shared := PartSnapResolver.matching_kinds(own_socket, target_socket)
			if shared.is_empty():
				continue
			if "weld" in shared:
				_union(group_of, key, target_key)
			for kind: String in shared:
				if kind == "weld":
					continue
				pending.append({
					"kind": kind,
					"key_a": key,
					"key_b": target_key,
					"position": own_socket.get("position", Vector3.ZERO),
					"axis": own_socket.get("axis", Vector3.ZERO),
					"own_socket_id": str(joint.get("own_socket", "")),
				})

	# Pass 2: finalize groups (mass sums over every member) now that every
	# weld union has been applied.
	var groups_by_root := {}
	for key: String in keys:
		var root := _find(group_of, key)
		if not groups_by_root.has(root):
			groups_by_root[root] = {"member_keys": [], "mass_kg": 0.0}
		var placed: Dictionary = document.placed_parts[key]
		var part: PartProfile = part_lookup.call(StringName(str(placed.get("part_id", ""))))
		if part == null:
			continue
		var material: MaterialProperties = material_lookup.call(part.material_id)
		var entry: Dictionary = groups_by_root[root]
		(entry["member_keys"] as Array).append(key)
		entry["mass_kg"] = float(entry["mass_kg"]) + part.resolved_mass_kg(material)

	var group_list: Array[Dictionary] = []
	var group_id_of_root := {}
	var root_keys: Array = groups_by_root.keys()
	root_keys.sort() # deterministic group ids across runs of the same document
	for root: String in root_keys:
		var id := "group_%d" % group_list.size()
		group_id_of_root[root] = id
		var entry: Dictionary = groups_by_root[root]
		entry["id"] = id
		group_list.append(entry)

	# Pass 3: express each pending non-weld connection in terms of final
	# group ids, dropping any that ended up inside the same welded group,
	# and de-duplicating (every joint was recorded once per participating
	# part, so it appears twice here - once from each side).
	var physics_joints: Array[Dictionary] = []
	var logical_connections: Array[Dictionary] = []
	var seen := {}
	for spec: Dictionary in pending:
		var root_a: String = _find(group_of, str(spec["key_a"]))
		var root_b: String = _find(group_of, str(spec["key_b"]))
		if root_a == root_b:
			continue
		var group_a: String = group_id_of_root[root_a]
		var group_b: String = group_id_of_root[root_b]
		var ordered := [group_a, group_b]
		ordered.sort()
		var dedupe_key := "%s|%s|%s" % [spec["kind"], ordered[0], ordered[1]]
		if seen.has(dedupe_key):
			continue
		seen[dedupe_key] = true
		var record := {
			"kind": spec["kind"],
			"group_a": group_a,
			"group_b": group_b,
			"position": spec["position"],
			"axis": spec["axis"],
		}
		if spec["kind"] in PHYSICS_JOINT_KINDS:
			physics_joints.append(record)
		else:
			logical_connections.append(record)

	return {"groups": group_list, "joints": physics_joints, "logical_connections": logical_connections}


static func _find_socket(world_sockets: Array[Dictionary], id: String) -> Dictionary:
	for socket: Dictionary in world_sockets:
		if str(socket.get("id", "")) == id:
			return socket
	return {}


static func _find(group_of: Dictionary, key: String) -> String:
	var current := key
	while group_of.get(current, current) != current:
		current = group_of[current]
	# Path compression: point every visited node straight at the root so
	# repeated lookups on a long assembly chain stay cheap.
	var walk := key
	while group_of.get(walk, walk) != current:
		var next: String = group_of[walk]
		group_of[walk] = current
		walk = next
	return current


static func _union(group_of: Dictionary, a: String, b: String) -> void:
	var root_a := _find(group_of, a)
	var root_b := _find(group_of, b)
	if root_a != root_b:
		group_of[root_b] = root_a
