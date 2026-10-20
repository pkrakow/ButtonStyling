extends Node
## Persistent player settings (user://settings.cfg). Emits `changed` for every value change
## so callers can log settings_changed telemetry.

signal changed(key: String, old_value: Variant, new_value: Variant)

const DEFAULTS := {
	"privacy/consent": "unset", # unset | granted | denied
	"privacy/install_id": "",
	"ui/scale": 1.0,
	"ui/reduced_motion": false,
	"display/fullscreen": false,
}

var path := "user://settings.cfg"
var _cfg := ConfigFile.new()


func _ready() -> void:
	load_from(path)
	apply_display()


func load_from(p_path: String) -> void:
	path = p_path
	_cfg = ConfigFile.new()
	if FileAccess.file_exists(path):
		var err := _cfg.load(path)
		if err != OK:
			_log_error("settings.load", {"err": err, "path": path})


func get_value(key: String) -> Variant:
	var parts := key.split("/")
	return _cfg.get_value(parts[0], parts[1], DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	var old: Variant = get_value(key)
	if typeof(old) == typeof(value) and old == value:
		return
	var parts := key.split("/")
	_cfg.set_value(parts[0], parts[1], value)
	var err := _cfg.save(path)
	if err != OK:
		_log_error("settings.save", {"err": err, "path": path})
	changed.emit(key, old, value)
	if key.begins_with("ui/") or key.begins_with("display/"):
		apply_display()


func consent() -> String:
	return get_value("privacy/consent")


func apply_display() -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	get_tree().root.content_scale_factor = float(get_value("ui/scale"))
	var fs: bool = get_value("display/fullscreen")
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func _log_error(component: String, fields: Dictionary) -> void:
	var gl := get_node_or_null("/root/GameLog")
	if gl:
		gl.error(component, fields)
