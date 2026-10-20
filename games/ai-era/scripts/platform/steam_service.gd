extends Node
## Steamworks integration point. Uses the GodotSteam GDExtension when it is installed
## in addons/godotsteam/ (it registers an engine singleton named "Steam"); otherwise
## runs as a stub that records calls in memory so the game plays normally.
## Never reads or forwards the SteamID or persona name.

const Rules := preload("res://scripts/platform/steam_rules.gd")

var available := false
var unlocked: Dictionary = {}
var stats: Dictionary = {}
var calls: Array = [] # stub call log, handy in tests and debugging
var _steam: Object


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var app_id: int = ProjectSettings.get_setting("ai_era/steam/app_id", 480)
	if Engine.has_singleton("Steam"):
		_steam = Engine.get_singleton("Steam")
		var res: Dictionary = _steam.steamInitEx(app_id, true)
		available = int(res.get("status", -1)) == 0
		if available:
			_log("info", {"mode": "steamworks", "app_id": app_id})
			for s in Rules.STATS:
				stats[s] = _steam.getStatInt(s)
		else:
			_log("warn", {"mode": "stub", "status": res.get("status"), "msg": str(res.get("verbal", "init failed"))})
	else:
		_log("info", {"mode": "stub", "msg": "GodotSteam not installed"})


func _process(_delta: float) -> void:
	if available:
		_steam.run_callbacks()


## Segmentation fields that are safe to attach to telemetry (no personal data).
func segment_info() -> Dictionary:
	if not available:
		return {"steam": false}
	return {"steam": true, "steam_build_id": _steam.getAppBuildId(), "steam_deck": _steam.isSteamRunningOnSteamDeck(),
		"steam_language": _steam.getCurrentGameLanguage()}


## Applies a Rules result: {"achievements": [], "add": {}, "max": {}}.
func apply(result: Dictionary, store: bool = false) -> void:
	for a in result.get("achievements", []):
		set_achievement(a)
	var add: Dictionary = result.get("add", {})
	for s in add:
		set_stat(s, int(stats.get(s, 0)) + int(add[s]))
	var mx: Dictionary = result.get("max", {})
	for s in mx:
		if int(mx[s]) > int(stats.get(s, 0)):
			set_stat(s, int(mx[s]))
	if store:
		store_stats()


func set_achievement(api_name: String) -> void:
	if unlocked.has(api_name):
		return
	unlocked[api_name] = true
	calls.append(["setAchievement", api_name])
	if available:
		_steam.setAchievement(api_name)


func set_stat(api_name: String, value: int) -> void:
	stats[api_name] = value
	calls.append(["setStatInt", api_name, value])
	if available:
		_steam.setStatInt(api_name, value)


func store_stats() -> void:
	calls.append(["storeStats"])
	if available:
		_steam.storeStats()


func _log(level: String, fields: Dictionary) -> void:
	var gl := get_node_or_null("/root/GameLog")
	if gl:
		gl.call(level, "steam.init", fields)
