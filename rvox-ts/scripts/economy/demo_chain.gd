class_name DemoChain
extends RefCounted

## The frozen demo production chain (DEMO_PLAN.md §4) plus a bottleneck
## diagnoser. Recipes are defined in code here for the demo; the architecture
## intends them to migrate to `.tres` (WORLD_FORGE_ARCHITECTURE.md) — this is
## the single place that changes when they do.
##
##   mine        -> raw_ore, coal        (ResourceNode, not a recipe)
##   lumber camp -> wood                 (ResourceNode, not a recipe)
##   smelter     -> raw_ore x2 + coal    => iron_ingot
##   forge       -> wood                 => wood_handle x2
##   forge       -> iron_ingot x2 + wood_handle => iron_sword
##   barracks    -> recruit + iron_sword => swordsman
##
## The diagnoser answers the gameplan's "Definition of Fun" question — trace a
## stalled sword back to the missing raw material — and powers the readability
## UI in DEMO_PLAN.md §4.

## Raw materials that come from ResourceNodes, not from a station recipe.
const RAW_RESOURCES: Array[StringName] = [&"wood", &"raw_ore", &"coal"]


static func _recipe(id: StringName, display: String, inputs: Dictionary, outputs: Dictionary, station: StringName, duration: float, role: StringName) -> RecipeDefinition:
	var r := RecipeDefinition.new()
	r.id = id
	r.display_name = display
	r.inputs = inputs
	r.outputs = outputs
	r.required_station = station
	r.duration_seconds = duration
	r.worker_role = role
	return r


## Every craftable recipe in the demo chain, in dependency order.
static func recipes() -> Array[RecipeDefinition]:
	return [
		_recipe(&"smelt_iron_ingot", "Smelt Iron Ingot",
			{&"raw_ore": 2, &"coal": 1}, {&"iron_ingot": 1},
			&"smelter", 6.0, &"smelter"),
		_recipe(&"make_wood_handle", "Carve Wood Handle",
			{&"wood": 1}, {&"wood_handle": 2},
			&"forge", 3.0, &"blacksmith"),
		_recipe(&"craft_iron_sword", "Forge Iron Sword",
			{&"iron_ingot": 2, &"wood_handle": 1}, {&"iron_sword": 1},
			&"forge", 8.0, &"blacksmith"),
	]


static func recipe_by_id(id: StringName) -> RecipeDefinition:
	for r in recipes():
		if r.id == id:
			return r
	return null


## Map every producible output item -> the recipe that makes it.
static func recipes_by_output() -> Dictionary:
	var out: Dictionary = {}
	for r in recipes():
		for item_key in r.outputs.keys():
			out[StringName(item_key)] = r
	return out


static func is_raw(item_id: StringName) -> bool:
	return RAW_RESOURCES.has(item_id)


## Trace why `target_item` can't be produced from current `stock`
## (item_id -> amount on hand). Walks the chain depth-first; returns the first
## shortage that blocks the whole thing plus a readable reason. When the target
## is already makeable, returns { "producible": true }.
##
## Result: {
##   producible: bool,
##   missing: StringName,     # the item actually short (a raw material, usually)
##   needed: int, have: int,  # of that item, for the full target
##   reason: String,          # e.g. "iron_sword needs iron_ingot needs raw_ore (have 1, need 4)"
## }
static func diagnose(target_item: StringName, stock: Dictionary, count: int = 1) -> Dictionary:
	var by_output := recipes_by_output()
	var trail: Array[StringName] = []
	return _shortfall(target_item, count, stock, by_output, {}, trail)


static func _shortfall(item: StringName, count: int, stock: Dictionary, by_output: Dictionary, visited: Dictionary, trail: Array[StringName]) -> Dictionary:
	trail.append(item)
	var have := int(stock.get(item, 0))
	if have >= count:
		return {"producible": true}

	# Raw material (or anything with no recipe): this is the real bottleneck.
	if is_raw(item) or not by_output.has(item):
		return {
			"producible": false,
			"missing": item,
			"needed": count,
			"have": have,
			"reason": _format_trail(trail, item, have, count),
		}

	# Craftable: we can cover `have` from stock; the rest must be produced.
	if visited.has(item):
		# Cyclic recipe graph — treat as an unmakeable leaf rather than loop.
		return {
			"producible": false,
			"missing": item,
			"needed": count,
			"have": have,
			"reason": _format_trail(trail, item, have, count),
		}
	visited[item] = true

	var deficit := count - have
	var recipe: RecipeDefinition = by_output[item]
	var per_craft_out := int(recipe.outputs.get(item, 1))
	var crafts_needed := int(ceil(float(deficit) / float(maxi(1, per_craft_out))))

	# Check each input; return the first that's short (with its own sub-trail).
	for input_key in recipe.inputs.keys():
		var input_id := StringName(input_key)
		var input_need := int(recipe.inputs[input_key]) * crafts_needed
		var sub_trail: Array[StringName] = trail.duplicate()
		var sub := _shortfall(input_id, input_need, stock, by_output, visited.duplicate(), sub_trail)
		if not bool(sub.get("producible", false)):
			return sub

	# All inputs are available in enough quantity — nothing is truly blocking;
	# the item just hasn't been crafted yet.
	return {"producible": true}


static func _format_trail(trail: Array[StringName], missing: StringName, have: int, need: int) -> String:
	var parts: PackedStringArray = []
	for i in trail.size():
		var link := String(trail[i])
		if i == 0:
			parts.append(link)
		else:
			parts.append("needs %s" % link)
	return "%s (have %d, need %d)" % [" ".join(parts), have, need]
