extends Node
## Platform-neutral achievements/stats sink. On its own it is the stub backend:
## it records unlocks and stats in memory so the game behaves the same everywhere.
## Store backends (Game Center, Steam) extend it and override the _platform_* hooks.

var backend_name := "stub"
var available := false
var unlocked: Dictionary = {}
var stats: Dictionary = {}
var calls: Array = []


## Fields safe to attach to telemetry. Never includes player or account ids.
func segment_info() -> Dictionary:
	return {"platform_services": backend_name, "platform_services_live": available}


## Applies an AchievementRules result: {"achievements": [], "add": {}, "max": {}}.
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
		_platform_unlock(api_name)


func set_stat(api_name: String, value: int) -> void:
	stats[api_name] = value
	calls.append(["setStatInt", api_name, value])
	if available:
		_platform_set_stat(api_name, value)


func store_stats() -> void:
	calls.append(["storeStats"])
	if available:
		_platform_store()


func _platform_unlock(_api_name: String) -> void:
	pass


func _platform_set_stat(_api_name: String, _value: int) -> void:
	pass


func _platform_store() -> void:
	pass


func _log(level: String, component: String, fields: Dictionary) -> void:
	var gl := get_node_or_null("/root/GameLog")
	if gl:
		gl.call(level, component, fields)
