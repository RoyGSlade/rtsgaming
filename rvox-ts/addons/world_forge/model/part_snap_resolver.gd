@tool
class_name PartSnapResolver
extends RefCounted

## Finds a compatible socket on an already-placed part near a candidate
## part's socket and returns the position that would align them - the
## part-scale generalization of ComponentSnapResolver's port snapping (plan
## section 5). Two differences from the component version, both following
## from parts living in full 3D rather than a cell-aligned, 90-degree-step
## grid:
##  - a socket carries a LIST of `kinds` (a rod's end can weld, hinge, or
##    drive a power shaft - several simultaneously valid roles for one
##    physical junction) rather than one `type`, so matching checks for a
##    shared kind/accepts pair in both directions instead of exact type
##    equality;
##  - positions/axes are metric Vector3, not Vector3i, so "sockets face each
##    other" is a dot-product threshold instead of exact negation.
## Deliberately does NOT solve full socket-to-socket auto-orientation - it
## only proposes a POSITION snap; the candidate keeps whatever
## rotation_steps it already has. Auto-orienting to align two arbitrary
## socket axes needs a real orientation solve (find the yaw/pitch/roll that
## points axis A opposite axis B), which is meaningfully harder than the
## position-only case and is left for when a Workshop viewport with live
## placement feedback exists to make that UX legible. See
## docs/WORLD_FORGE_CRAFTING_PLAN.md section 5 and reporting.md Step 6.

const DEFAULT_TOLERANCE := 0.3
## cos(~135 deg): generous rather than requiring near-exact alignment, since
## a placed part's yaw is only ever a multiple of 90 degrees today.
const AXIS_ALIGNMENT_THRESHOLD := 0.7
## Socket kinds where the connection MOUNTS one part onto another's shaft
## (a wheel's bore slides onto an axle end, coaxial - same direction) rather
## than EXTENDING a line of parts tip-to-tip (two rods, or two shaft
## segments, should point away from each other even when the shared kind is
## power_shaft - a driveshaft is still a straight line of opposing tips, not
## a same-direction stack). Only "bearing" belongs here: it was tempting to
## also list "power_shaft" since both are rotation concepts, but that
## breaks rod-to-rod coupling by wrongly allowing overlapping, same-facing
## placements (caught by test_part_snap_resolver_rejects_same_direction_
## rod_ends). Discovered by tracing a concrete wheel-on-axle mount through
## find_snap before trusting it: a wheel's bore axis and the axle end it
## mounts on point the *same* way, so the plain "must oppose" rule silently
## rejected every valid bearing connection until this list existed. See
## reporting.md Step 6.
const COAXIAL_KINDS := ["bearing"]


## Computes every socket's world-space position/axis for a part placed at
## `position` with a yaw of `rotation_steps` quarter-turns (matching
## PartGeometryFactory/_add_placed_part_visual's rotation convention).
static func world_sockets(part: PartProfile, position: Vector3, rotation_steps: int) -> Array[Dictionary]:
	var basis := Basis(Vector3.UP, -float(posmod(rotation_steps, 4)) * PI * 0.5)
	var results: Array[Dictionary] = []
	for socket: Dictionary in part.sockets:
		var local_position: Vector3 = socket.get("position", Vector3.ZERO)
		var local_axis: Vector3 = socket.get("axis", Vector3.ZERO)
		results.append({
			"id": socket.get("id", ""),
			"kinds": socket.get("kinds", []),
			"accepts": socket.get("accepts", []),
			"position": position + basis * local_position,
			"axis": basis * local_axis,
		})
	return results


## Searches every already-placed part's sockets for the nearest one that is
## both kind-compatible with and axis-opposing one of the candidate's own
## sockets, within `tolerance` meters. `placed_lookup` is a Callable
## (part_id: StringName) -> PartProfile so callers can pass a PartRegistry
## without this file depending on its concrete type. Returns
## {"found": false} when nothing in range matches.
static func find_snap(
	document: ForgeDocument,
	placed_lookup: Callable,
	candidate: PartProfile,
	candidate_position: Vector3,
	candidate_rotation_steps: int,
	tolerance: float = DEFAULT_TOLERANCE
) -> Dictionary:
	var best := {"found": false, "position": candidate_position, "distance": tolerance}
	var candidate_sockets := world_sockets(candidate, candidate_position, candidate_rotation_steps)
	if candidate_sockets.is_empty():
		return best
	for key: String in document.placed_parts:
		var placed: Dictionary = document.placed_parts[key]
		var placed_part: PartProfile = placed_lookup.call(StringName(str(placed.get("part_id", ""))))
		if placed_part == null:
			continue
		var placed_position := ForgeDocument.placed_part_world_position(placed)
		var placed_sockets := world_sockets(placed_part, placed_position, int(placed.get("rotation_steps", 0)))
		for candidate_socket: Dictionary in candidate_sockets:
			for target_socket: Dictionary in placed_sockets:
				var shared_kinds := matching_kinds(candidate_socket, target_socket)
				if shared_kinds.is_empty():
					continue
				var candidate_axis: Vector3 = candidate_socket.get("axis", Vector3.ZERO)
				var target_axis: Vector3 = target_socket.get("axis", Vector3.ZERO)
				if candidate_axis.is_zero_approx() or target_axis.is_zero_approx():
					continue
				if not _axes_compatible(shared_kinds, candidate_axis, target_axis):
					continue
				var candidate_pos: Vector3 = candidate_socket.get("position", Vector3.ZERO)
				var target_pos: Vector3 = target_socket.get("position", Vector3.ZERO)
				var distance := candidate_pos.distance_to(target_pos)
				if distance < float(best.get("distance", tolerance)):
					best = {
						"found": true,
						"position": candidate_position + (target_pos - candidate_pos),
						"distance": distance,
						"candidate_socket": candidate_socket.get("id", ""),
						"target_socket": target_socket.get("id", ""),
						"target_part_key": key,
					}
	return best


## Whether two facing sockets' axes make physical sense, given which kinds
## actually connect them. Checked per shared kind, not per whole socket,
## because a real part's socket can mix kinds with different axis rules (a
## rod's end is weld+hinge+power_shaft at once): welding two rods should
## still require them to point away from each other even though the same
## sockets could ALSO couple coaxially as a power shaft. Either reading
## being geometrically valid is enough to accept the placement.
static func _axes_compatible(shared_kinds: Array, first_axis: Vector3, second_axis: Vector3) -> bool:
	var dot := first_axis.normalized().dot(second_axis.normalized())
	var allow_opposing := false
	var allow_coaxial := false
	for kind: Variant in shared_kinds:
		if kind in COAXIAL_KINDS:
			allow_coaxial = true
		else:
			allow_opposing = true
	if allow_opposing and dot <= -AXIS_ALIGNMENT_THRESHOLD:
		return true
	if allow_coaxial and absf(dot) >= AXIS_ALIGNMENT_THRESHOLD:
		return true
	return false


## Kinds that genuinely connect two sockets: offered by both (in both
## `kinds` lists) AND accepted by both (in both `accepts` lists) - the
## strictest reading, and the one that lets _axes_compatible reason about a
## single, unambiguous kind rather than "some kind from A matched some
## other kind from B". Mirrors ComponentSnapResolver._ports_match's
## bidirectional type check, generalized from one type to kind lists.
static func matching_kinds(first: Dictionary, second: Dictionary) -> Array:
	var first_kinds: Array = first.get("kinds", [])
	var second_kinds: Array = second.get("kinds", [])
	var first_accepts: Array = first.get("accepts", first_kinds)
	var second_accepts: Array = second.get("accepts", second_kinds)
	var matches: Array = []
	for kind: Variant in first_kinds:
		if kind in second_kinds and kind in first_accepts and kind in second_accepts:
			matches.append(kind)
	return matches
