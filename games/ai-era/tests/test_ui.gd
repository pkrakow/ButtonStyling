extends "res://tests/test_case.gd"
## Headless smoke test of the real main scene in a portrait phone viewport:
## tap-target sizes, screen flow, backgrounding, and save/resume.

const Core := preload("res://scripts/telemetry/telemetry_core.gd")
const RunSave := preload("res://scripts/core/run_save.gd")
const Collection := preload("res://scripts/core/collection.gd")

var root: Window
var main: Control
var _restore := {}


func _setup() -> void:
	root = Engine.get_main_loop().root
	var settings = root.get_node("Settings")
	var telemetry = root.get_node("Telemetry")
	var d := tmp_dir("ui")
	_restore = {"path": settings.path, "core": telemetry.core}
	settings.load_from(d.path_join("settings.cfg"))
	telemetry.core = Core.new(d.path_join("telemetry"), telemetry.core.logger, {"batch_size": 1000})
	root.size = Vector2i(390, 844)
	main = load("res://scenes/main.tscn").instantiate()
	main.save = RunSave.new(d.path_join("run.json"))
	main.collection = Collection.new(d.path_join("collection.cfg"))
	root.add_child(main)
	await _frames(3)


func _teardown() -> void:
	main.queue_free()
	await _frames(1)
	root.get_node("Settings").load_from(_restore.path)
	root.get_node("Telemetry").core = _restore.core


func _frames(n: int) -> void:
	for i in n:
		await Engine.get_main_loop().process_frame


func _events() -> Array:
	# The upload queue drains on flush (app_background flushes), so read the local log.
	var out := []
	var f := FileAccess.open(root.get_node("Telemetry").core.events_path(), FileAccess.READ)
	if f == null:
		return out
	for line in f.get_as_text().split("\n", false):
		out.append(JSON.parse_string(line))
	return out


func _check_tap_targets(where: String) -> void:
	var n := 0
	for b in main.find_children("*", "BaseButton", true, false):
		if not b.is_visible_in_tree():
			continue
		n += 1
		check(b.size.y >= 44.0 and b.size.x >= 44.0, "%s: '%s' is %s, below 44pt" % [where, b.get("text"), str(b.size)])
	check(n > 0, "%s: found buttons" % where)


func _press(text_prefix: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and String(b.text).begins_with(text_prefix):
			b.pressed.emit()
			return
	failures.append("button '%s' not found" % text_prefix)


func test_portrait_flow_tap_targets_background_and_resume() -> void:
	await _setup()
	eq(main.current_screen, "consent", "fresh install shows consent")
	_check_tap_targets("consent")
	_press("Share anonymous")
	await _frames(3)
	eq(main.current_screen, "title", "title after consent")
	_check_tap_targets("title")

	_press("New run")
	await _frames(3)
	eq(main.current_screen, "game", "game screen")
	_check_tap_targets("game")
	var vp: Vector2 = main.get_viewport_rect().size
	for b in main.option_buttons:
		var r: Rect2 = b.get_global_rect()
		check(r.position.x >= 0.0 and r.end.x <= vp.x + 0.5, "option fits portrait width: %s" % str(r))
	main.input_lock_until = 0
	main._choose(0)
	await _frames(2)
	check(main.save.exists(), "run saved after a decision")

	main.on_app_background()
	await _frames(2)
	check(main.paused, "backgrounding pauses the run")
	eq(main._layer_name(), "pause", "pause menu shown")
	_check_tap_targets("pause")
	main.on_app_foreground()
	var names := _events().map(func(e): return e.event)
	check("app_background" in names and "app_foreground" in names, "background/foreground tracked: %s" % str(names))
	var pause_ev: Array = _events().filter(func(e): return e.event == "pause")
	eq(pause_ev[-1].props.reason, "app_background", "pause reason")

	var turn_before: int = main.sim.turn
	var offers_before: Array = main.sim.offer_ids()
	var run_before: String = main.run_id
	_press("Save and go to title")
	await _frames(3)
	eq(main.current_screen, "title", "back on title")
	_press("Continue")
	await _frames(3)
	eq(main.current_screen, "game", "resumed into game")
	eq(main.sim.turn, turn_before, "same turn after resume")
	eq(main.sim.offer_ids(), offers_before, "same cards after resume")
	eq(main.run_id, run_before, "same run id after resume")
	check("run_suspend" in _events().map(func(e): return e.event), "suspend tracked")
	check("run_resume" in _events().map(func(e): return e.event), "resume tracked")

	main._set_paused(true, "button")
	await _frames(1)
	_press("Settings")
	await _frames(3)
	_check_tap_targets("settings")
	main._show_collection()
	await _frames(3)
	_check_tap_targets("collection")
	await _teardown()


func test_end_screen_records_collection() -> void:
	await _setup()
	main._decide_consent(false)
	main._start_run(4242, "custom")
	await _frames(2)
	var guard := 0
	while not main.sim.is_over() and guard < 200:
		main.input_lock_until = 0
		main._choose(0)
		guard += 1
	await _frames(3)
	eq(main.current_screen, "end", "end screen")
	_check_tap_targets("end")
	eq(main.collection.found_count(), 1, "ending recorded in collection")
	check(not main.save.exists(), "save cleared after the run ends")
	await _teardown()


func test_phone_layout_on_mobile_or_simulated_phone() -> void:
	var Main = load("res://scripts/ui/main.gd")
	check(Main.phone_layout(true, PackedStringArray()), "mobile feature means phone layout")
	check(Main.phone_layout(false, PackedStringArray(["--sim-safe-area=59,34"])), "simulated safe area means phone layout")
	check(not Main.phone_layout(false, PackedStringArray(["--autoplay"])), "plain desktop keeps desktop controls")
