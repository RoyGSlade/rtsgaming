class_name TreeProfile
extends Resource

## Parameters for TreeMeshBuilder's recursive branch generation — the same
## degree-based knobs as tree.md's reference implementation (pitch angle,
## angle randomness, child count, length/radius shrink, leaf density),
## just resolved in 3D instead of a single 2D drawing-plane angle.

@export var profile_seed: int = 12345
@export_range(1, 10) var depth: int = 6
@export_range(5.0, 85.0) var pitch_degrees: float = 32.0
@export_range(0.0, 45.0) var randomness_degrees: float = 12.0
@export_range(1, 5) var children: int = 2
@export_range(0.4, 0.9) var length_shrink: float = 0.72
@export_range(0.45, 0.85) var radius_shrink: float = 0.68
@export_range(0, 20) var leaf_density: int = 8
@export var trunk_length: float = 3.2
@export var trunk_radius: float = 0.22
