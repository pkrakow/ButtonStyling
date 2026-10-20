extends SceneTree
## Headless test runner. Usage (from repo root):
##   godot --headless --path games/ai-era -s res://tests/run_tests.gd
## Prints one PASS/FAIL line per test and exits non-zero on any failure.

const SUITES := [
	"res://tests/test_simulation.gd",
	"res://tests/test_telemetry.gd",
	"res://tests/test_platform.gd",
	"res://tests/test_consent_flow.gd",
	"res://tests/test_persistence.gd",
	"res://tests/test_ui.gd",
]


func _init() -> void:
	# Defer so autoloads are in the tree before suites run.
	_run.call_deferred()


func _run() -> void:
	var passed := 0
	var failed := 0
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed += 1
			printerr("FAIL %s failed to load (parse error above)" % path)
			continue
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			var suite = script.new()
			var t0 := Time.get_ticks_msec()
			await suite.call(name)
			var ms := Time.get_ticks_msec() - t0
			if suite.failures.is_empty():
				passed += 1
				print("PASS %s::%s (%d ms)" % [path.get_file(), name, ms])
			else:
				failed += 1
				for f in suite.failures:
					printerr("FAIL %s::%s %s" % [path.get_file(), name, f])
	remove_tree("user://test-tmp")
	print("RESULT passed=%d failed=%d" % [passed, failed])
	quit(1 if failed > 0 else 0)


func remove_tree(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	for d in da.get_directories():
		remove_tree(path.path_join(d))
	for f in da.get_files():
		da.remove(f)
	DirAccess.remove_absolute(path)
