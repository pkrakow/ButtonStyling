extends "res://tests/test_case.gd"

const Rules := preload("res://scripts/platform/steam_rules.gd")
const D := preload("res://scripts/sim/sim_data.gd")


func test_every_ending_has_achievement_and_stat() -> void:
	for e in D.ENDINGS:
		var r: Dictionary = Rules.on_run_end(e, 20, D.MAX_TURNS)
		for a in r.achievements:
			check(Rules.ACHIEVEMENTS.has(a), "undefined achievement %s" % a)
		for s in r.add:
			check(s in Rules.STATS, "undefined stat %s" % s)


func test_finish_run_only_at_max_turns() -> void:
	check("ACH_FINISH_RUN" in Rules.on_run_end("muddle", D.MAX_TURNS, D.MAX_TURNS).achievements, "finish at max")
	check(not ("ACH_FINISH_RUN" in Rules.on_run_end("runaway", 12, D.MAX_TURNS).achievements), "no finish on early end")


func test_decision_rules() -> void:
	var first: Dictionary = Rules.on_decision("card", "research", "", 2022, 1)
	check("ACH_FIRST_DECISION" in first.achievements, "first decision achievement")
	eq(first.add, {"STAT_PICKS_RESEARCH": 1}, "pick counter")
	check("STAT_PICKS_RESEARCH" in Rules.STATS, "pick stat defined")
	check("ACH_TREATY" in Rules.on_decision("dilemma", "", "Sign the treaty", 2027, 9).achievements, "treaty")


func test_stub_service_applies_without_steam() -> void:
	var svc = load("res://scripts/platform/steam_service.gd").new()
	svc.apply(Rules.on_run_start())
	svc.apply(Rules.on_run_start())
	svc.apply(Rules.on_decision("card", "policy", "", 2026, 1), true)
	eq(svc.stats.STAT_RUNS_STARTED, 2, "stat accumulates")
	eq(svc.stats.STAT_MAX_YEAR, 2026, "max stat")
	check(svc.unlocked.has("ACH_REACH_2025"), "achievement recorded in stub")
	check(svc.calls.has(["storeStats"]), "storeStats called")
	svc.free()
