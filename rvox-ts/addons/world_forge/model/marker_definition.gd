@tool
class_name MarkerDefinition
extends Resource

## A placeable scene marker (worker position, entrance, resource node...).
## Deliberately thin - the editor only reads id/display_name/color today;
## richer per-marker behavior lives on the placed instance's `properties`
## dictionary (see ForgeDocument.markers), not on this catalog entry.

@export var id: StringName = &""
@export var display_name := "Marker"
@export var color := Color.GREEN
## Palette display order (ascending); ties break on id. Not simulation state.
@export var sort_order := 0
