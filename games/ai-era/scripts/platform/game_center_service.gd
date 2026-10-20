extends "res://scripts/platform/achievement_service.gd"
## Optional Game Center backend (iOS). Stays a stub unless BOTH are true:
##  - project setting ai_era/game_center/enabled is true, and
##  - the godot-ios-plugins GameCenter plugin is bundled (engine singleton "GameCenter").
## Only achievements are reported; Game Center has no equivalent of Steam stats,
## so stats stay local. Achievement ids are "<prefix>.<api_name lowercased>".

var _gc: Object
var prefix := ""


func _ready() -> void:
	backend_name = "game_center"
	prefix = ProjectSettings.get_setting("ai_era/game_center/achievement_prefix", "com.example.runtimetakeoff")
	if not ProjectSettings.get_setting("ai_era/game_center/enabled", false):
		_log("info", "platform.game_center", {"mode": "stub", "msg": "disabled in project settings"})
		return
	if not Engine.has_singleton("GameCenter"):
		_log("info", "platform.game_center", {"mode": "stub", "msg": "GameCenter plugin not bundled"})
		return
	_gc = Engine.get_singleton("GameCenter")
	_gc.authenticate()
	available = true
	_log("info", "platform.game_center", {"mode": "live"})


func _process(_delta: float) -> void:
	if _gc == null:
		return
	while _gc.get_pending_event_count() > 0:
		var ev: Dictionary = _gc.pop_pending_event()
		if ev.get("result", "ok") != "ok":
			_log("error", "platform.game_center", {"type": ev.get("type", ""), "error_code": ev.get("error_code", ""),
				"msg": str(ev.get("error_description", "request failed"))})


func game_center_id(api_name: String) -> String:
	return "%s.%s" % [prefix, api_name.to_lower()]


func _platform_unlock(api_name: String) -> void:
	_gc.award_achievement({"name": game_center_id(api_name), "progress": 100.0, "show_completion_banner": true})
