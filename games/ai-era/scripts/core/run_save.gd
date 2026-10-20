extends RefCounted
## Single-slot save for the run in progress. A run is stored as its seed plus the
## list of actions taken, and restored by replaying them (the sim is deterministic).
## This is gameplay data kept on the device; it is not telemetry and is never uploaded.

const VERSION := 1

var path: String


func _init(p_path: String = "user://run_save.json") -> void:
	path = p_path


func exists() -> bool:
	return FileAccess.file_exists(path)


## Returns an error string, or "" on success.
func write(data: Dictionary) -> String:
	var payload := data.duplicate()
	payload["save_version"] = VERSION
	payload["saved_at_unix"] = int(Time.get_unix_time_from_system())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "open failed err=%d" % FileAccess.get_open_error()
	f.store_string(JSON.stringify(payload))
	f.close()
	var err := DirAccess.rename_absolute(tmp, path)
	return "" if err == OK else "rename failed err=%d" % err


## Returns {} when there is no usable save.
func read() -> Dictionary:
	if not exists():
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary) or int(data.get("save_version", 0)) != VERSION or not data.has("seed") or not data.has("actions"):
		return {}
	return data


func clear() -> void:
	if exists():
		DirAccess.remove_absolute(path)
