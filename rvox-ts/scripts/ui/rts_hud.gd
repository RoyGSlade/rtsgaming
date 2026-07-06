class_name RtsHud
extends Control

## First-pass RTS management HUD (gameplan Phase 8 seed, built early so there
## is a home for everything as systems land):
##   - top center: resource stock bar (player stock is a plain dictionary here
##     until the economy runtime owns it)
##   - bottom dock: preview/info panel + Buildings and Units tabs
##   - right side: MVP checklist overview ("what's still needed" at a glance)
## Building buttons start ghost placement via building_chosen; GameMain wires
## that to BuildingPlacementController and reports back through
## on_building_placed so costs are only paid for confirmed placements.
## Everything is built in code — no scene file — so GameMain.tscn stays small.

signal building_chosen(entry: Dictionary)
signal unit_train_requested(entry: Dictionary)
## Emitted when the player clicks "New Run" on the results screen.
signal new_run_requested

const BuildingCatalogScript := preload("res://scripts/buildings/building_catalog.gd")
const BuildingPreviewScript := preload("res://scripts/ui/building_preview.gd")

const PANEL_COLOR := Color(0.09, 0.10, 0.14, 0.88)
const CATEGORY_COLORS := {
	"core": Color(0.85, 0.78, 0.58),
	"economy": Color(0.62, 0.78, 0.60),
	"military": Color(0.85, 0.58, 0.58),
}

## Placeholder starting stock; replaced by StorageInventory-backed state once
## gathering exists. Keys follow the MVP resource ids from the gameplan.
const STARTING_STOCK := {
	"wood": 250, "stone": 180, "food": 120,
	"raw_ore": 0, "coal": 0, "iron_ingot": 0,
}
const RESOURCE_NAMES := {
	"wood": "Wood", "stone": "Stone", "food": "Food",
	"raw_ore": "Ore", "coal": "Coal", "iron_ingot": "Ingots",
}
const RESOURCE_ORDER := ["wood", "stone", "food", "raw_ore", "coal", "iron_ingot"]
const RESOURCE_SWATCHES := {
	"wood": Color(0.55, 0.38, 0.20), "stone": Color(0.55, 0.55, 0.58),
	"food": Color(0.80, 0.62, 0.25), "raw_ore": Color(0.42, 0.36, 0.40),
	"coal": Color(0.16, 0.16, 0.18), "iron_ingot": Color(0.72, 0.74, 0.80),
}

## MVP unit roster. worker/soldier spawn today (GameMain handles the request);
## the rest are the gameplan's worker roles, listed as disabled placeholders so
## the roster is visible before the job system exists.
const UNIT_ENTRIES := [
	{"id": "worker", "name": "Worker", "cost": {"food": 10}, "ready": true,
		"description": "General villager. Will split into gather/haul/build jobs."},
	{"id": "soldier", "name": "Swordsman", "cost": {"food": 25}, "ready": true,
		"description": "Sword-and-shield fighter. Will require a forged iron sword."},
	{"id": "builder", "name": "Builder", "cost": {}, "ready": false,
		"description": "Constructs placed blueprints block by block."},
	{"id": "hauler", "name": "Hauler", "cost": {}, "ready": false,
		"description": "Moves resources between storage and buildings."},
	{"id": "miner", "name": "Miner", "cost": {}, "ready": false,
		"description": "Works the mine for raw ore and coal."},
	{"id": "woodcutter", "name": "Woodcutter", "cost": {}, "ready": false,
		"description": "Fells trees at the lumber camp."},
	{"id": "tanner", "name": "Tanner", "cost": {}, "ready": false,
		"description": "Turns hides into leather wraps."},
	{"id": "blacksmith", "name": "Blacksmith", "cost": {}, "ready": false,
		"description": "Crafts iron swords at the forge anvil."},
]

## Assigned by GameMain so the dock can show the current unit selection.
var command_controller: RtsCommandController

## The authoritative economy, once RunCoordinator builds it. Untyped and
## duck-typed on purpose so a fresh checkout parses this script before the new
## EconomyController class_name is registered. While null the HUD falls back to
## its own placeholder `stock` dict, so nothing breaks if the run setup is
## skipped. See DEMO_PLAN.md §4 ("HUD reads, never owns").
var economy = null

## The run director, once RunCoordinator builds it. Untyped/duck-typed for the
## same fresh-checkout reason as `economy`. Drives the objective/phase panel.
var director = null

var stock := {}
var placed_counts := {}
var trained_counts := {}

var _catalog: BuildingCatalog
var _resource_labels := {}
var _preview: BuildingPreview
var _info_name: Label
var _info_description: Label
var _info_cost: Label
var _status_label: Label
var _selection_label: Label
var _overview_rows := {}
var _overview_units_label: Label
var _phase_label: Label
var _objective_label: Label
var _raid_label: Label
var _raid_flash := 0.0
var _construction_label: Label
var _results_panel: PanelContainer
var _results_title: Label
var _results_body: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stock = STARTING_STOCK.duplicate()
	_catalog = BuildingCatalogScript.new()
	_catalog.load_catalog()
	_build_resource_bar()
	_build_objective_panel()
	_build_bottom_dock()
	_build_overview_panel()
	_refresh_resource_bar()
	_refresh_overview()


func _process(delta: float) -> void:
	# Blink the raid warning for a few seconds after it fires, then hold steady.
	if _raid_flash > 0.0 and _raid_label != null:
		_raid_flash -= delta
		_raid_label.visible = _raid_flash <= 0.0 or fmod(_raid_flash, 0.5) > 0.25

	if command_controller == null or _selection_label == null:
		return
	var selected := command_controller.get_selected()
	if selected == null:
		_selection_label.text = "Selected: —"
	else:
		var kind := "Swordsman" if "soldier" in selected.model_path else "Worker"
		var state := "moving" if selected.is_moving() else "idle"
		_selection_label.text = "Selected: %s (%s)" % [kind, state]


## Switch the resource bar and cost checks over to the authoritative economy.
## Called by GameMain once RunCoordinator has built the controller.
func bind_economy(new_economy) -> void:
	economy = new_economy
	if economy != null:
		if not economy.stock_changed.is_connected(_on_economy_stock_changed):
			economy.stock_changed.connect(_on_economy_stock_changed)
		if not economy.build_site_added.is_connected(_on_build_site_added):
			economy.build_site_added.connect(_on_build_site_added)
		if not economy.building_completed.is_connected(_on_building_completed):
			economy.building_completed.connect(_on_building_completed)
		for site in economy.build_sites():
			_on_build_site_added(site)
	_refresh_resource_bar()


## Show block-by-block construction progress ("Building Storage Yard: 3/5").
func _on_build_site_added(site) -> void:
	site.block_placed.connect(func(placed: int, total: int) -> void:
		if _construction_label != null:
			_construction_label.text = "Building %s: %d/%d" % [String(site.building_id).capitalize(), placed, total])


func _on_building_completed(building_id: StringName) -> void:
	if _construction_label != null:
		_construction_label.text = "%s complete" % String(building_id).capitalize()


func _on_economy_stock_changed(_item_id: StringName, _amount: int) -> void:
	_refresh_resource_bar()


## Bind the run director so the objective panel shows phase, day/night, and
## objective progress, and raid warnings flash when a wave spawns.
func bind_director(new_director) -> void:
	director = new_director
	if director == null:
		return
	if not director.phase_changed.is_connected(_on_phase_changed):
		director.phase_changed.connect(_on_phase_changed)
	if not director.objective_updated.is_connected(_on_objective_updated):
		director.objective_updated.connect(_on_objective_updated)
	if not director.raid_incoming.is_connected(_on_raid_incoming):
		director.raid_incoming.connect(_on_raid_incoming)
	if not director.run_ended.is_connected(_on_run_ended):
		director.run_ended.connect(_on_run_ended)
	_on_phase_changed(director.phase, director.day, director.is_night)
	_on_objective_updated(director.swords_produced, director.swordsmen_trained)


func _phase_text(phase: int, day: int, is_night: bool) -> String:
	match phase:
		0: return "Generating world…"     # Phase.GENERATION
		1: return "Briefing"              # Phase.BRIEFING
		2: return "Day %d — build & gather" % day   # Phase.DAY
		3: return "Night %d — hold the line" % day  # Phase.NIGHT
		4: return "Run over"              # Phase.RESOLUTION
	return ""


func _on_phase_changed(phase: int, day: int, is_night: bool) -> void:
	if _phase_label == null:
		return
	_phase_label.text = _phase_text(phase, day, is_night)
	_phase_label.add_theme_color_override("font_color",
		Color(0.6, 0.7, 1.0) if is_night else Color(1.0, 0.9, 0.6))


func _on_objective_updated(swords: int, swordsmen: int) -> void:
	if _objective_label == null:
		return
	_objective_label.text = "Objective: Swords %d/3 · Swordsmen %d/3" % [swords, swordsmen]


func _on_raid_incoming(night: int, size: int, target: StringName) -> void:
	if _raid_label == null:
		return
	_raid_label.text = "⚔ RAID %d — %d raiders inbound (%s)" % [night, size, target]
	_raid_flash = 3.0


func _on_run_ended(outcome: int) -> void:
	if _phase_label == null:
		return
	# Outcome.WIN == 1, Outcome.LOSS == 2.
	var won := outcome == 1
	_phase_label.text = "VICTORY — dawn holds" if won else "DEFEAT"
	_phase_label.add_theme_color_override("font_color",
		Color(0.5, 1.0, 0.6) if won else Color(1.0, 0.45, 0.45))


## Show the end-of-run results overlay with the outcome, the run's tally, and
## any banked blueprint unlock. Called by GameMain from RunCoordinator.run_resolved.
func show_results(outcome: int, unlock_id: StringName) -> void:
	if _results_panel == null:
		_build_results_panel()
	var won := outcome == 1
	_results_title.text = "VICTORY" if won else "DEFEAT"
	_results_title.add_theme_color_override("font_color",
		Color(0.5, 1.0, 0.6) if won else Color(1.0, 0.45, 0.45))
	var swords: int = director.swords_produced if director != null else 0
	var swordsmen: int = director.swordsmen_trained if director != null else 0
	var body := "Swords forged: %d\nSwordsmen trained: %d" % [swords, swordsmen]
	if won:
		body += "\n\nBlueprint unlocked: %s" % (String(unlock_id).capitalize() if unlock_id != &"" else "— (all earned)")
	else:
		body += "\n\nThe settlement fell. Try a new seed."
	_results_body.text = body
	_results_panel.visible = true


func _on_new_run_pressed() -> void:
	if _results_panel != null:
		_results_panel.visible = false
	new_run_requested.emit()


func _build_results_panel() -> void:
	_results_panel = PanelContainer.new()
	var style := _panel_style()
	style.bg_color = Color(0.06, 0.07, 0.10, 0.96)
	_results_panel.add_theme_stylebox_override("panel", style)
	add_child(_results_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(320, 0)
	_results_panel.add_child(col)

	_results_title = Label.new()
	_results_title.add_theme_font_size_override("font_size", 28)
	_results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_results_title)

	_results_body = Label.new()
	_results_body.add_theme_font_size_override("font_size", 15)
	_results_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_results_body)

	var new_run := Button.new()
	new_run.text = "New Run"
	new_run.custom_minimum_size = Vector2(0, 40)
	new_run.pressed.connect(_on_new_run_pressed)
	col.add_child(new_run)

	_results_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_results_panel.visible = false


## Called by GameMain when the placement controller confirms a placement.
func on_building_placed(entry: Dictionary, _world_position: Vector3) -> void:
	_pay(entry.get("cost", {}))
	var id := String(entry.get("id", ""))
	placed_counts[id] = int(placed_counts.get(id, 0)) + 1
	_set_status("%s site placed." % entry.get("name", "Building"), false)
	_refresh_resource_bar()
	_refresh_overview()


# --- resource stock -----------------------------------------------------------


func _can_afford(cost: Dictionary) -> bool:
	if economy != null:
		return economy.can_afford(cost)
	for resource in cost:
		if int(stock.get(resource, 0)) < int(cost[resource]):
			return false
	return true


func _pay(cost: Dictionary) -> void:
	if economy != null:
		economy.pay(cost)
		return
	for resource in cost:
		stock[resource] = int(stock.get(resource, 0)) - int(cost[resource])


func _cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "Free"
	var parts: PackedStringArray = []
	for resource in RESOURCE_ORDER:
		if cost.has(resource):
			parts.append("%s %d" % [RESOURCE_NAMES.get(resource, resource), int(cost[resource])])
	return " · ".join(parts)


# --- button handlers ------------------------------------------------------------


func _on_building_button(entry: Dictionary) -> void:
	_show_entry_info(entry, true)
	if not _can_afford(entry.get("cost", {})):
		_set_status("Not enough resources.", true)
		return
	_set_status("Placing — left-click to build, right-click to cancel.", false)
	building_chosen.emit(entry)


func _on_unit_button(entry: Dictionary) -> void:
	_show_entry_info(entry, false)
	if not entry.get("ready", false):
		_set_status("Planned role — arrives with the job system.", true)
		return
	if not _can_afford(entry.get("cost", {})):
		_set_status("Not enough resources.", true)
		return
	_pay(entry.get("cost", {}))
	var id := String(entry.get("id", ""))
	trained_counts[id] = int(trained_counts.get(id, 0)) + 1
	unit_train_requested.emit(entry)
	_set_status("%s trained." % entry.get("name", "Unit"), false)
	_refresh_resource_bar()
	_refresh_overview()


func _show_entry_info(entry: Dictionary, is_building: bool) -> void:
	_info_name.text = String(entry.get("name", ""))
	_info_description.text = String(entry.get("description", ""))
	_info_cost.text = _cost_text(entry.get("cost", {}))
	if is_building:
		_preview.show_entry(entry)
	else:
		_preview.clear()


func _set_status(message: String, is_error: bool) -> void:
	_status_label.text = message
	_status_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.45, 0.45) if is_error else Color(0.75, 0.85, 0.75))


# --- UI construction ------------------------------------------------------------


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_corner_radius_all(6)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _build_resource_bar() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	for resource: String in RESOURCE_ORDER:
		var swatch := ColorRect.new()
		swatch.color = RESOURCE_SWATCHES[resource]
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 14)
		row.add_child(label)
		_resource_labels[resource] = label

	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_top = 10.0


func _refresh_resource_bar() -> void:
	for resource in _resource_labels:
		var amount := int(stock.get(resource, 0))
		if economy != null:
			amount = economy.get_stock(StringName(resource))
		_resource_labels[resource].text = "%s %d" % [RESOURCE_NAMES[resource], amount]


## Phase / objective / raid readout, centered just under the resource bar.
func _build_objective_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	_phase_label = Label.new()
	_phase_label.add_theme_font_size_override("font_size", 15)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.text = "Briefing"
	col.add_child(_phase_label)

	_objective_label = Label.new()
	_objective_label.add_theme_font_size_override("font_size", 13)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.text = "Objective: Swords 0/3 · Swordsmen 0/3"
	col.add_child(_objective_label)

	_raid_label = Label.new()
	_raid_label.add_theme_font_size_override("font_size", 13)
	_raid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_raid_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	col.add_child(_raid_label)

	_construction_label = Label.new()
	_construction_label.add_theme_font_size_override("font_size", 13)
	_construction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_construction_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.7))
	col.add_child(_construction_label)

	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_top = 44.0


func _build_bottom_dock() -> void:
	var dock := PanelContainer.new()
	dock.add_theme_stylebox_override("panel", _panel_style())
	add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dock.offset_left = 12.0
	dock.offset_right = -12.0
	dock.offset_top = -212.0
	dock.offset_bottom = -10.0

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	dock.add_child(row)

	# Left: preview + info column.
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(260, 0)
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)

	_preview = BuildingPreviewScript.new()
	_preview.custom_minimum_size = Vector2(240, 96)
	info.add_child(_preview)

	_info_name = Label.new()
	_info_name.add_theme_font_size_override("font_size", 16)
	_info_name.text = "Select a building or unit"
	info.add_child(_info_name)

	_info_description = Label.new()
	_info_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_description.add_theme_font_size_override("font_size", 12)
	_info_description.modulate = Color(0.8, 0.8, 0.85)
	info.add_child(_info_description)

	_info_cost = Label.new()
	_info_cost.add_theme_font_size_override("font_size", 12)
	info.add_child(_info_cost)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	info.add_child(_status_label)

	_selection_label = Label.new()
	_selection_label.add_theme_font_size_override("font_size", 12)
	_selection_label.modulate = Color(0.75, 0.8, 0.9)
	_selection_label.text = "Selected: —"
	info.add_child(_selection_label)

	# Right: build/train tabs.
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(tabs)

	var buildings := ScrollContainer.new()
	buildings.name = "Buildings"
	tabs.add_child(buildings)
	var building_flow := HFlowContainer.new()
	building_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_flow.add_theme_constant_override("h_separation", 8)
	building_flow.add_theme_constant_override("v_separation", 8)
	buildings.add_child(building_flow)
	for entry: Dictionary in _catalog.entries:
		building_flow.add_child(_make_entry_button(
			String(entry.get("name", "?")) + "\n" + _cost_text(entry.get("cost", {})),
			String(entry.get("description", "")),
			CATEGORY_COLORS.get(String(entry.get("category", "")), Color.WHITE),
			_on_building_button.bind(entry)))

	var units := ScrollContainer.new()
	units.name = "Units"
	tabs.add_child(units)
	var unit_flow := HFlowContainer.new()
	unit_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_flow.add_theme_constant_override("h_separation", 8)
	unit_flow.add_theme_constant_override("v_separation", 8)
	units.add_child(unit_flow)
	for entry: Dictionary in UNIT_ENTRIES:
		var ready: bool = entry.get("ready", false)
		var text: String = String(entry.get("name", "?")) \
			+ ("\n" + _cost_text(entry.get("cost", {})) if ready else "\n(planned)")
		unit_flow.add_child(_make_entry_button(
			text,
			String(entry.get("description", "")),
			Color.WHITE if ready else Color(0.6, 0.6, 0.6),
			_on_unit_button.bind(entry)))


# Planned entries stay clickable (dimmed, not disabled) so their info still
# shows in the preview panel; the handler decides whether anything happens.
func _make_entry_button(text: String, tooltip: String, tint: Color, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(128, 52)
	button.self_modulate = tint
	button.pressed.connect(handler)
	return button


func _build_overview_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -176.0
	panel.offset_right = -16.0
	panel.offset_top = 368.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)

	var title := Label.new()
	title.text = "MVP CHECKLIST"
	title.add_theme_font_size_override("font_size", 13)
	column.add_child(title)

	for entry: Dictionary in _catalog.entries:
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 12)
		column.add_child(row)
		_overview_rows[String(entry.get("id", ""))] = row

	_overview_units_label = Label.new()
	_overview_units_label.add_theme_font_size_override("font_size", 12)
	column.add_child(_overview_units_label)


func _refresh_overview() -> void:
	for entry: Dictionary in _catalog.entries:
		var id := String(entry.get("id", ""))
		var count := int(placed_counts.get(id, 0))
		var row: Label = _overview_rows[id]
		row.text = "%s %s%s" % [
			"✔" if count > 0 else "·",
			entry.get("name", id),
			" ×%d" % count if count > 1 else "",
		]
		row.modulate = Color(0.85, 1.0, 0.85) if count > 0 else Color(0.65, 0.65, 0.7)
	_overview_units_label.text = "Workers %d · Swordsmen %d" % [
		int(trained_counts.get("worker", 0)) + 1,
		int(trained_counts.get("soldier", 0)) + 1,
	]
