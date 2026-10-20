extends "res://scripts/platform/achievement_service.gd"
## Steamworks backend (desktop only, currently unused: Steam is on hold).
## Loaded by Platform only when ai_era/steam/enabled is true and the GodotSteam
## GDExtension is installed. Excluded from the iOS export. Never reads the SteamID.

var _steam: Object


func _ready() -> void:
	backend_name = "steam"
	var app_id: int = ProjectSettings.get_setting("ai_era/steam/app_id", 480)
	if not Engine.has_singleton("Steam"):
		_log("info", "platform.steam", {"mode": "stub", "msg": "GodotSteam not installed"})
		return
	_steam = Engine.get_singleton("Steam")
	var res: Dictionary = _steam.steamInitEx(app_id, true)
	available = int(res.get("status", -1)) == 0
	if available:
		_log("info", "platform.steam", {"mode": "live", "app_id": app_id})
		for s in preload("res://scripts/platform/achievement_rules.gd").STATS:
			stats[s] = _steam.getStatInt(s)
	else:
		_log("warn", "platform.steam", {"mode": "stub", "status": res.get("status"), "msg": str(res.get("verbal", "init failed"))})


func _process(_delta: float) -> void:
	if available:
		_steam.run_callbacks()


func segment_info() -> Dictionary:
	var info := super.segment_info()
	if available:
		info["steam_build_id"] = _steam.getAppBuildId()
		info["steam_deck"] = _steam.isSteamRunningOnSteamDeck()
	return info


func _platform_unlock(api_name: String) -> void:
	_steam.setAchievement(api_name)


func _platform_set_stat(api_name: String, value: int) -> void:
	_steam.setStatInt(api_name, value)


func _platform_store() -> void:
	_steam.storeStats()
