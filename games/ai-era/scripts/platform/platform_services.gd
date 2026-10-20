extends Node
## Autoload "Platform": picks the achievements backend for this build.
##  - iOS: Game Center (optional, stub by default).
##  - Desktop with ai_era/steam/enabled: Steam (script excluded from the iOS export).
##  - Otherwise: the in-memory stub.
## Backends load by path so a build can omit the scripts it does not use.

const STEAM_PATH := "res://scripts/platform/steam_service.gd"
const GAME_CENTER_PATH := "res://scripts/platform/game_center_service.gd"
const STUB_PATH := "res://scripts/platform/achievement_service.gd"

var backend: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	backend = load(choose_backend_path(OS.has_feature("ios"), ProjectSettings.get_setting("ai_era/steam/enabled", false),
		ResourceLoader.exists(STEAM_PATH))).new()
	backend.name = "Backend"
	add_child(backend)


static func choose_backend_path(is_ios: bool, steam_enabled: bool, steam_present: bool) -> String:
	if is_ios:
		return GAME_CENTER_PATH
	if steam_enabled and steam_present:
		return STEAM_PATH
	return STUB_PATH


func apply(result: Dictionary, store: bool = false) -> void:
	backend.apply(result, store)


func segment_info() -> Dictionary:
	return backend.segment_info()
