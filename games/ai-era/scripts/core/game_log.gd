class_name GameLogCore
extends RefCounted
## Plain-text failure/debug log. One event per line, grep-friendly:
##   2026-10-20T02:00:00.123Z ERROR telemetry.send status=503 attempts=5 msg="server error"
## Runs regardless of telemetry consent: it never leaves the device and holds no gameplay data.

const MAX_BYTES := 1_000_000

var path: String
var echo := true


func _init(p_path: String = "user://logs/runtime-takeoff.log") -> void:
	path = p_path
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())


static func iso_now() -> String:
	var t := Time.get_unix_time_from_system()
	return "%s.%03dZ" % [Time.get_datetime_string_from_unix_time(int(t), false), int(fmod(t, 1.0) * 1000.0)]


static func format_line(level: String, component: String, fields: Dictionary) -> String:
	var parts := PackedStringArray([iso_now(), level, component])
	for k in fields:
		var v = fields[k]
		var s := str(v)
		if v is String and (s.contains(" ") or s.contains("\"") or s.is_empty()):
			s = "\"%s\"" % s.replace("\"", "'")
		parts.append("%s=%s" % [k, s])
	return " ".join(parts)


func write(level: String, component: String, fields: Dictionary = {}) -> String:
	var line := format_line(level, component, fields)
	_rotate_if_needed()
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()
	if echo:
		if level == "ERROR":
			printerr(line)
		else:
			print(line)
	return line


func info(component: String, fields: Dictionary = {}) -> String:
	return write("INFO", component, fields)


func warn(component: String, fields: Dictionary = {}) -> String:
	return write("WARN", component, fields)


func error(component: String, fields: Dictionary = {}) -> String:
	return write("ERROR", component, fields)


func _rotate_if_needed() -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f and f.get_length() > MAX_BYTES:
		f.close()
		DirAccess.rename_absolute(path, path + ".1")
