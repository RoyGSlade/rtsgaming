@tool
extends McpTestSuite

## Combat core (DEMO_PLAN.md §6/§14): health, the damage formula, and the
## deterministic skirmish simulator — including that stats/equipment actually
## change outcomes, and that bigger raids beat smaller garrisons.


func suite_name() -> String:
	return "combat"


# ----- Health -----

func test_health_takes_damage_and_dies_once() -> void:
	var h := Health.new(10)
	var deaths := [0]
	h.died.connect(func() -> void: deaths[0] += 1)
	assert_eq(h.take_damage(4), 4, "Full damage applied while alive")
	assert_eq(h.hp, 6, "HP reduced")
	assert_true(h.is_alive(), "Still alive")
	assert_eq(h.take_damage(100), 6, "Overkill only deals remaining HP")
	assert_false(h.is_alive(), "Dead now")
	assert_eq(h.take_damage(5), 0, "No damage once dead")
	assert_eq(deaths[0], 1, "died fires exactly once")


func test_health_heal_clamps_to_max() -> void:
	var h := Health.new(20)
	h.take_damage(15)
	h.heal(100)
	assert_eq(h.hp, 20, "Healing never exceeds max")


# ----- damage formula -----

func test_resolve_hit_applies_armor_with_floor() -> void:
	assert_eq(CombatMath.resolve_hit(10, 3), 7, "Armor subtracts from damage")
	assert_eq(CombatMath.resolve_hit(3, 10), 1, "Damage never drops below 1")


# ----- skirmish simulation -----

func test_equal_stats_larger_side_wins() -> void:
	var result := CombatMath.simulate_skirmish(
		CombatCatalog.line_of(&"raider", 5),
		CombatCatalog.line_of(&"raider", 2))
	assert_eq(result["winner"], "attackers", "5 beats 2 with identical stats")
	assert_gt(int(result["attacker_survivors"]), 0, "Winner keeps survivors")
	assert_eq(int(result["defender_survivors"]), 0, "Loser is wiped")


func test_better_stats_beat_numbers() -> void:
	# Two swordsmen (24hp/6dmg/2armor) vs four raiders (14hp/4dmg/0armor).
	var result := CombatMath.simulate_skirmish(
		CombatCatalog.line_of(&"swordsman", 2),
		CombatCatalog.line_of(&"raider", 4))
	assert_eq(result["winner"], "attackers", "Better-equipped swordsmen beat a larger raider band")


func test_watchtower_swings_a_close_fight() -> void:
	# Three swordsmen alone fall to eight raiders; add a watchtower and they hold.
	var without_tower := CombatMath.simulate_skirmish(
		CombatCatalog.line_of(&"swordsman", 3),
		CombatCatalog.line_of(&"raider", 8))
	var with_tower := CombatCatalog.line_of(&"swordsman", 3)
	with_tower.append(CombatCatalog.watchtower())
	var tower_result := CombatMath.simulate_skirmish(
		with_tower,
		CombatCatalog.line_of(&"raider", 8))
	assert_eq(without_tower["winner"], "defenders", "8 raiders overrun 3 lone swordsmen")
	assert_eq(tower_result["winner"], "attackers", "A watchtower turns the same fight")


func test_skirmish_is_deterministic() -> void:
	var a := CombatMath.simulate_skirmish(
		CombatCatalog.line_of(&"swordsman", 3), CombatCatalog.line_of(&"raider", 5))
	var b := CombatMath.simulate_skirmish(
		CombatCatalog.line_of(&"swordsman", 3), CombatCatalog.line_of(&"raider", 5))
	assert_eq(a, b, "Same forces -> identical result, every time")


func _garrison() -> Array:
	var g := CombatCatalog.line_of(&"swordsman", 3)
	g.append(CombatCatalog.watchtower())
	return g


func test_raid_difficulty_scaling_matters() -> void:
	# A garrison that holds the night-1 raid should fall to the night-3 wave.
	var night1 := CombatMath.simulate_skirmish(_garrison(), CombatCatalog.line_of(&"raider", 3))
	var night3 := CombatMath.simulate_skirmish(_garrison(), CombatCatalog.line_of(&"raider", 12))
	assert_eq(night1["winner"], "attackers", "Garrison holds the small early raid")
	assert_eq(night3["winner"], "defenders", "The night-3 wave overruns the same garrison")
