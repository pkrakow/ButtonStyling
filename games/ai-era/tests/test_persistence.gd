extends "res://tests/test_case.gd"

const Sim := preload("res://scripts/sim/simulation.gd")
const Strategies := preload("res://scripts/sim/strategies.gd")
const RunSave := preload("res://scripts/core/run_save.gd")
const Collection := preload("res://scripts/core/collection.gd")


func test_restore_mid_run_matches_original() -> void:
	var sim = Sim.new()
	sim.start(31337)
	var tie := RandomNumberGenerator.new()
	tie.seed = 5
	for i in 15:
		var idx := Strategies.pick(sim, "random", tie)
		if sim.phase == sim.Phase.DILEMMA:
			sim.choose_dilemma(idx)
		else:
			sim.choose_card(idx)
	var restored = Sim.restore(31337, JSON.parse_string(JSON.stringify(sim.actions)))
	check(restored != null, "restores")
	eq(JSON.stringify(restored.history), JSON.stringify(sim.history), "history identical after replay")
	eq(restored.offer_ids(), sim.offer_ids(), "same offers on screen")
	eq(restored.phase, sim.phase, "same phase (card or dilemma)")


func test_restore_then_continue_equals_uninterrupted() -> void:
	var full = Strategies.play(777, "humane")
	var half = Sim.restore(777, full.actions.slice(0, 10))
	for a in full.actions.slice(10):
		if a[0] == "c":
			half.choose_card(a[1])
		else:
			half.choose_dilemma(a[1])
	eq(half.ending_id, full.ending_id, "same ending")
	eq(JSON.stringify(half.snapshot()), JSON.stringify(full.snapshot()), "same final state")


func test_restore_rejects_bad_actions() -> void:
	eq(Sim.restore(1, [["c", 7]]), null, "invalid index")
	eq(Sim.restore(1, [["d", 0]]), null, "dilemma when none pending")
	eq(Sim.restore(1, ["junk"]), null, "malformed entry")


func test_run_save_roundtrip_and_clear() -> void:
	var s = RunSave.new(tmp_dir("save").path_join("run.json"))
	eq(s.read(), {}, "empty when missing")
	eq(s.write({"seed": 9, "actions": [["c", 1]], "run_id": "r"}), "", "write ok")
	var d: Dictionary = s.read()
	eq(int(d.seed), 9, "seed saved")
	eq(d.run_id, "r", "run id saved")
	s.clear()
	check(not s.exists(), "cleared")


func test_run_save_ignores_corrupt_file() -> void:
	var p := tmp_dir("corrupt").path_join("run.json")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	eq(RunSave.new(p).read(), {}, "corrupt save is ignored")


func test_collection_persists_endings_and_years() -> void:
	var p := tmp_dir("coll").path_join("c.cfg")
	var c = Collection.new(p)
	eq(c.found_count(), 0, "starts empty")
	check(c.record_ending("divide", 42), "first find is new")
	check(not c.record_ending("divide", 43), "second find is not new")
	c.record_ending("winter", 44)
	c.record_year(2027)
	c.record_year(2025)
	var again = Collection.new(p)
	eq(again.found_count(), 2, "two endings persisted")
	eq(int(again.ending("divide").count), 2, "count persisted")
	eq(int(again.ending("divide").first_seed), 42, "first seed kept")
	eq(again.max_year(), 2027, "max year persisted")
