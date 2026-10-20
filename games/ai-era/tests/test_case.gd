extends RefCounted
## Minimal assertion base for the headless test runner (no third-party addon).

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(actual: Variant, expected: Variant, msg: String) -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: expected %s, got %s" % [msg, str(expected), str(actual)])


func tmp_dir(name: String) -> String:
	var d := "user://test-tmp/%s-%d" % [name, Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(d)
	return d
