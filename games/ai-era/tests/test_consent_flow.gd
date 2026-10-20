extends "res://tests/test_case.gd"
## Exercises the Settings + Telemetry autoloads together, pointed at temp storage.

const Core := preload("res://scripts/telemetry/telemetry_core.gd")


func _with_temp_autoloads(body: Callable) -> void:
	var root: Window = Engine.get_main_loop().root
	var settings = root.get_node("Settings")
	var telemetry = root.get_node("Telemetry")
	var old_path: String = settings.path
	var old_core = telemetry.core
	var d := tmp_dir("consent")
	settings.load_from(d.path_join("settings.cfg"))
	var lg = old_core.logger
	telemetry.core = Core.new(d.path_join("telemetry"), lg, {"batch_size": 50})
	body.call(settings, telemetry)
	settings.load_from(old_path)
	telemetry.core = old_core


func test_fresh_install_is_opted_out() -> void:
	_with_temp_autoloads(func(settings, telemetry):
		eq(settings.consent(), "unset", "consent starts unset")
		check(not telemetry.is_enabled(), "telemetry off before a choice")
		eq(telemetry.track("app_start", {}), {}, "nothing recorded before consent")
		eq(settings.get_value("privacy/install_id"), "", "no install id before consent"))


func test_opt_in_creates_id_then_opt_out_purges() -> void:
	_with_temp_autoloads(func(settings, telemetry):
		telemetry.set_consent(true, "first_launch")
		eq(settings.consent(), "granted", "consent saved")
		var id: String = settings.get_value("privacy/install_id")
		eq(id.length(), 36, "install id created on opt-in")
		check(telemetry.core.queue.size() == 1 and telemetry.core.queue[0].contains("consent_changed"), "consent_changed recorded")
		telemetry.reset_install_id()
		check(settings.get_value("privacy/install_id") != id, "reset gives a new id")
		telemetry.set_consent(false, "settings")
		eq(settings.consent(), "denied", "opt-out saved")
		eq(settings.get_value("privacy/install_id"), "", "install id deleted on opt-out")
		eq(telemetry.core.queue.size(), 0, "queue purged on opt-out")
		eq(telemetry.track("decision", {}), {}, "nothing recorded after opt-out"))


func test_settings_change_is_tracked_without_privacy_values() -> void:
	_with_temp_autoloads(func(settings, telemetry):
		telemetry.set_consent(true, "settings")
		settings.set_value("ui/reduced_motion", true)
		var last: Dictionary = JSON.parse_string(telemetry.core.queue[-1])
		eq(last.event, "settings_changed", "settings change tracked")
		eq(last.props, {"key": "ui/reduced_motion", "old": false, "new": true}, "settings props")
		for line in telemetry.core.queue:
			check(not String(line).contains("privacy/install_id"), "install id changes are not tracked as settings"))
