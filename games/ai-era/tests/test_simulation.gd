extends "res://tests/test_case.gd"

const Sim := preload("res://scripts/sim/simulation.gd")
const D := preload("res://scripts/sim/sim_data.gd")
const Strategies := preload("res://scripts/sim/strategies.gd")


func _trace(seed_value: int, strategy: String) -> Array:
	var sim = Strategies.play(seed_value, strategy)
	return [sim.history, sim.news, sim.ending_id, sim.picked_cards]


func test_same_seed_same_run() -> void:
	for strategy in ["random", "humane", "reckless"]:
		var a := _trace(4242, strategy)
		var b := _trace(4242, strategy)
		check(JSON.stringify(a) == JSON.stringify(b), "run with seed 4242 / %s is not reproducible" % strategy)


func test_same_seed_same_offers_regardless_of_order_of_queries() -> void:
	var a = Sim.new()
	var b = Sim.new()
	a.start(77)
	b.start(77)
	b.snapshot()
	b.summary()
	eq(a.offer_ids(), b.offer_ids(), "read-only queries must not consume rng")


func test_different_seeds_differ() -> void:
	var seen := {}
	for s in 20:
		seen[JSON.stringify(_trace(s + 1, "random"))] = true
	check(seen.size() >= 18, "expected nearly all of 20 seeds to differ, got %d distinct" % seen.size())


func test_run_length_bounds() -> void:
	for strategy in Strategies.WEIGHTS:
		for s in 40:
			var sim = Strategies.play(500 + s, strategy)
			check(sim.is_over(), "run %d/%s did not end" % [500 + s, strategy])
			check(sim.turn <= D.MAX_TURNS, "run %d/%s exceeded max turns (%d)" % [500 + s, strategy, sim.turn])
			check(sim.turn >= D.MIN_TURN_FOR_EARLY_END, "run %d/%s ended before turn %d" % [500 + s, strategy, D.MIN_TURN_FOR_EARLY_END])
			check(sim.ending_id in D.ENDINGS, "unknown ending '%s'" % sim.ending_id)


func test_every_ending_reachable() -> void:
	var reached := {}
	for strategy in Strategies.WEIGHTS:
		for s in 120:
			reached[Strategies.play(9000 + s, strategy).ending_id] = true
	for e in D.ENDINGS:
		check(reached.has(e), "ending '%s' unreachable across scripted strategies" % e)


func test_final_date_is_2030_q3() -> void:
	var d := Sim.date_for_turn(D.MAX_TURNS - 1)
	eq(d, {"year": 2030, "quarter": 3}, "last playable quarter")
	eq(Sim.date_for_turn(0), {"year": 2022, "quarter": 4}, "first quarter")


func test_offers_one_of_each_type_and_targets_resolved() -> void:
	var sim = Sim.new()
	sim.start(5)
	for i in 10:
		var types := []
		for c in sim.offers:
			types.append(c.type)
			check(not String(c.text).contains("{region}"), "unresolved region in '%s'" % c.text)
		eq(types, ["policy", "research", "invest"], "offer types on turn %d" % sim.turn)
		sim.choose_card(0)
		if sim.phase == sim.Phase.DILEMMA:
			sim.choose_dilemma(0)


func test_invalid_actions_rejected() -> void:
	var sim = Sim.new()
	sim.start(1)
	check(not sim.choose_card(3), "out-of-range card accepted")
	check(not sim.choose_dilemma(0), "dilemma choice accepted in card phase")
	eq(sim.turn, 0, "turn must not advance on invalid input")


func test_stats_stay_in_bounds() -> void:
	for s in 10:
		var sim = Strategies.play(70 + s, "chaos")
		for r in sim.regions:
			for stat in D.REGION_STATS:
				check(r[stat] >= 0.0 and r[stat] <= 100.0, "%s.%s out of bounds: %f" % [r.id, stat, r[stat]])
			check(r.pop > 0.0, "population collapsed to zero in %s" % r.id)


func test_opening_event_is_chatbot_launch_without_real_names() -> void:
	var sim = Sim.new()
	sim.start(3)
	eq(sim.news[0].id, "e_launch", "first news item")
	var blob := JSON.stringify([D.CARDS, D.EVENTS, D.ENDINGS]).to_lower()
	for banned in ["openai", "chatgpt", "anthropic", "google", "altman", "nvidia", "deepmind", "microsoft"]:
		check(not blob.contains(banned), "content mentions real name '%s'" % banned)


func test_epilogue_and_summary_present() -> void:
	var sim = Strategies.play(11, "random")
	var s: Dictionary = sim.summary()
	check(s.ending != "", "summary has ending")
	check(sim.epilogue().size() >= 3, "epilogue has several lines")
	eq(sim.history.size(), sim.turn + 1, "one snapshot per turn plus start")
