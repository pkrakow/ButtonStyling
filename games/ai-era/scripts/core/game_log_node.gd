extends Node
## Autoload wrapper around GameLogCore. Use GameLog.error("component", {...}) for real
## failures only; WARN for recoverable conditions (offline), INFO for lifecycle.

const Core := preload("res://scripts/core/game_log.gd")

var core: Core = Core.new()


func info(component: String, fields: Dictionary = {}) -> void:
	core.info(component, fields)


func warn(component: String, fields: Dictionary = {}) -> void:
	core.warn(component, fields)


func error(component: String, fields: Dictionary = {}) -> void:
	core.error(component, fields)


func log_path() -> String:
	return ProjectSettings.globalize_path(core.path)
