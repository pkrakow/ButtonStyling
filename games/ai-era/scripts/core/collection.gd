extends RefCounted
## Local, permanent record of endings found and years reached across all runs.
## Shown on the Endings screen; never uploaded.

var path: String
var _cfg := ConfigFile.new()


func _init(p_path: String = "user://collection.cfg") -> void:
	path = p_path
	if FileAccess.file_exists(path):
		_cfg.load(path)


## Returns true when this ending is new.
func record_ending(ending_id: String, seed_value: int) -> bool:
	var is_new := not _cfg.has_section_key("endings", ending_id)
	var entry: Dictionary = _cfg.get_value("endings", ending_id, {"count": 0, "first_seed": seed_value,
		"first_found": Time.get_date_string_from_system(true)})
	entry.count = int(entry.count) + 1
	_cfg.set_value("endings", ending_id, entry)
	_save()
	return is_new


func record_year(year: int) -> void:
	if year > max_year():
		_cfg.set_value("eras", "max_year", year)
		_save()


func ending(ending_id: String) -> Dictionary:
	return _cfg.get_value("endings", ending_id, {})


func found_count() -> int:
	return _cfg.get_section_keys("endings").size() if _cfg.has_section("endings") else 0


func max_year() -> int:
	return int(_cfg.get_value("eras", "max_year", 0))


func _save() -> void:
	var err := _cfg.save(path)
	if err != OK:
		var gl = Engine.get_main_loop().root.get_node_or_null("GameLog") if Engine.get_main_loop() else null
		if gl:
			gl.error("collection.save", {"err": err, "path": path})
