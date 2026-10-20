extends Node
## Autoload: owns the TelemetryCore, follows the consent setting, and drains the
## upload queue on a timer. Endpoint: env AI_ERA_TELEMETRY_ENDPOINT, else project
## setting ai_era/telemetry/endpoint; empty means the no-op NullSink.

const Core := preload("res://scripts/telemetry/telemetry_core.gd")
const Sinks := preload("res://scripts/telemetry/sinks.gd")

var core: Core
var sink
var endpoint := ""
var flush_interval := 30.0
var _since_flush := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var gl = get_node("/root/GameLog").core
	core = Core.new("user://telemetry", gl, {
		"game_version": ProjectSettings.get_setting("application/config/version", "0.0.0"),
		"build_type": "debug" if OS.is_debug_build() else "release",
		"platform": OS.get_name(),
		"batch_size": ProjectSettings.get_setting("ai_era/telemetry/batch_size", 50),
	})
	flush_interval = ProjectSettings.get_setting("ai_era/telemetry/flush_interval_sec", 30.0)
	endpoint = OS.get_environment("AI_ERA_TELEMETRY_ENDPOINT")
	if endpoint == "":
		endpoint = ProjectSettings.get_setting("ai_era/telemetry/endpoint", "")
	if endpoint == "":
		sink = Sinks.NullSink.new()
	else:
		sink = Sinks.HttpSink.new(endpoint)
		add_child(sink)
	if Settings.consent() == "granted":
		core.enable(_ensure_install_id())
	Settings.changed.connect(_on_setting_changed)
	gl.info("telemetry.init", {"enabled": core.enabled, "sink": "http" if endpoint != "" else "null", "queued": core.queue.size()})


func track(event_name: String, props: Dictionary = {}) -> Dictionary:
	return core.track(event_name, props)


func is_enabled() -> bool:
	return core.enabled


func set_consent(granted: bool, source: String) -> void:
	if granted:
		Settings.set_value("privacy/consent", "granted")
		core.enable(_ensure_install_id())
		track("consent_changed", {"granted": true, "source": source})
	else:
		core.disable_and_purge()
		Settings.set_value("privacy/consent", "denied")
		Settings.set_value("privacy/install_id", "")


## New identity; data recorded under the old id is deleted from this device.
func reset_install_id() -> void:
	var was_enabled: bool = core.enabled
	core.disable_and_purge()
	var id := Core.new_uuid()
	Settings.set_value("privacy/install_id", id)
	if was_enabled:
		core.enable(id)
		track("install_id_reset", {})


func install_id() -> String:
	return Settings.get_value("privacy/install_id")


func flush_now() -> void:
	core.flush(sink)


func _process(delta: float) -> void:
	_since_flush += delta
	if _since_flush >= flush_interval or core.queue.size() >= core.batch_size:
		if core.flush(sink):
			_since_flush = 0.0
		elif _since_flush >= flush_interval:
			_since_flush = 0.0


func _ensure_install_id() -> String:
	var id: String = Settings.get_value("privacy/install_id")
	if id == "":
		id = Core.new_uuid()
		Settings.set_value("privacy/install_id", id)
	return id


func _on_setting_changed(key: String, old_value: Variant, new_value: Variant) -> void:
	if key.begins_with("privacy/"):
		return
	track("settings_changed", {"key": key, "old": old_value, "new": new_value})
