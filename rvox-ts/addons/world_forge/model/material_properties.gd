@tool
class_name MaterialProperties
extends Resource

## Physical/thermal properties for a single material (oak, steel, bronze...).
## One table drives mass, thermal simulation, and flammability so a part's
## behavior always follows from what it's made of rather than per-part
## special-casing. See docs/WORLD_FORGE_CRAFTING_PLAN.md section 4.

@export var id: StringName = &""
@export var display_name := "Material"
@export var density_kg_m3 := 1000.0
## J/(kg*K) - lumped-capacitance heat capacity used by the thermal sim.
@export var specific_heat := 500.0
## Relative 0..1 contact-transfer factor between touching parts.
@export var conductivity := 0.5
## Negative = never ignites.
@export var ignition_temp_c := -1.0
## Negative = never melts within the simulated range.
@export var melting_temp_c := -1.0
## Negative = never becomes workable/forgeable by heat alone.
@export var working_temp_c := -1.0
## Break-impulse basis for joints/beams built from this material.
@export var strength := 1000.0
## What this material becomes once melted (&"" if it has no molten form).
@export var molten_material_id: StringName = &""


func is_flammable() -> bool:
	return ignition_temp_c >= 0.0


func can_melt() -> bool:
	return melting_temp_c >= 0.0


func can_forge() -> bool:
	return working_temp_c >= 0.0


func mass_for_volume(volume_m3: float) -> float:
	return density_kg_m3 * volume_m3
