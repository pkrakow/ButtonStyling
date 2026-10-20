extends "res://tests/test_case.gd"

const Rules := preload("res://scripts/platform/achievement_rules.gd")
const D := preload("res://scripts/sim/sim_data.gd")
const PlatformServices := preload("res://scripts/platform/platform_services.gd")


func test_every_ending_has_achievement_and_stat() -> void:
	for e in D.ENDINGS:
		var r: Dictionary = Rules.on_run_end(e, 20, D.MAX_TURNS)
		for a in r.achievements:
			check(Rules.ACHIEVEMENTS.has(a), "undefined achievement %s" % a)
		for s in r.add:
			check(s in Rules.STATS, "undefined stat %s" % s)


func test_finish_run_only_at_max_turns() -> void:
	check("ACH_FINISH_RUN" in Rules.on_run_end("muddle", D.MAX_TURNS, D.MAX_TURNS).achievements, "finish at max")
	check(not ("ACH_FINISH_RUN" in Rules.on_run_end("runaway", 12, D.MAX_TURNS).achievements), "no finish on early end")


func test_decision_rules() -> void:
	var first: Dictionary = Rules.on_decision("card", "research", "", 2022, 1)
	check("ACH_FIRST_DECISION" in first.achievements, "first decision achievement")
	eq(first.add, {"STAT_PICKS_RESEARCH": 1}, "pick counter")
	check("ACH_TREATY" in Rules.on_decision("dilemma", "", "Sign the treaty", 2027, 9).achievements, "treaty")


func test_backend_selection() -> void:
	eq(PlatformServices.choose_backend_path(true, true, true), PlatformServices.GAME_CENTER_PATH, "iOS always uses Game Center, never Steam")
	eq(PlatformServices.choose_backend_path(false, false, true), PlatformServices.STUB_PATH, "Steam off by default")
	eq(PlatformServices.choose_backend_path(false, true, false), PlatformServices.STUB_PATH, "Steam script missing falls back to stub")
	eq(PlatformServices.choose_backend_path(false, true, true), PlatformServices.STEAM_PATH, "Steam when enabled and present")


func test_stub_backend_records_without_store() -> void:
	var svc = load(PlatformServices.STUB_PATH).new()
	svc.apply(Rules.on_run_start())
	svc.apply(Rules.on_run_start())
	svc.apply(Rules.on_decision("card", "policy", "", 2026, 1), true)
	eq(svc.stats.STAT_RUNS_STARTED, 2, "stat accumulates")
	eq(svc.stats.STAT_MAX_YEAR, 2026, "max stat")
	check(svc.unlocked.has("ACH_REACH_2025"), "achievement recorded in stub")
	check(svc.calls.has(["storeStats"]), "storeStats called")
	eq(svc.segment_info(), {"platform_services": "stub", "platform_services_live": false}, "segment info has no ids")
	svc.free()


func test_game_center_stays_stub_when_disabled() -> void:
	var gc = load(PlatformServices.GAME_CENTER_PATH).new()
	Engine.get_main_loop().root.add_child(gc)
	check(not gc.available, "Game Center is opt-in via project setting")
	gc.set_achievement("ACH_END_ABUNDANCE")
	check(gc.unlocked.has("ACH_END_ABUNDANCE"), "unlock recorded locally")
	eq(gc.game_center_id("ACH_END_ABUNDANCE"), "com.example.runtimetakeoff.ach_end_abundance", "Game Center id mapping")
	gc.queue_free()


func test_ios_preset_excludes_steam_and_sets_compliance() -> void:
	var cfg := ConfigFile.new()
	eq(cfg.load("res://export_presets.cfg"), OK, "export presets load")
	var ios := -1
	for i in 10:
		if cfg.get_value("preset.%d" % i, "platform", "") == "iOS":
			ios = i
	check(ios >= 0, "iOS preset exists")
	var sec := "preset.%d" % ios
	check(String(cfg.get_value(sec, "exclude_filter", "")).contains("steam_service.gd"), "Steam backend excluded from iOS")
	eq(cfg.get_value(sec + ".options", "application/targeted_device_family", -1), 0, "iPhone only")
	eq(cfg.get_value(sec + ".options", "application/export_project_only", false), true, "Xcode project export")
	# Godot's iOS template already writes ITSAppUsesNonExemptEncryption=false; adding it
	# again here would duplicate the key. tools/export_all.sh verifies the generated plist.
	check(not String(cfg.get_value(sec + ".options", "application/additional_plist_content", "")).contains("ITSAppUsesNonExemptEncryption"), "no duplicate compliance key")
	eq(cfg.get_value(sec + ".options", "privacy/tracking_enabled", true), false, "no tracking declared")


func test_ios_privacy_manifest_matches_telemetry_id_scope() -> void:
	var cfg := ConfigFile.new()
	cfg.load("res://export_presets.cfg")
	var sec := ""
	for i in 10:
		if cfg.get_value("preset.%d" % i, "platform", "") == "iOS":
			sec = "preset.%d.options" % i
	var per_install: bool = ProjectSettings.get_setting("ai_era/telemetry/id_scope", "install") == "install"
	eq(cfg.get_value(sec, "privacy/collected_data/product_interaction/collected", false), true, "product interaction declared")
	eq(cfg.get_value(sec, "privacy/collected_data/product_interaction/linked_to_user", null), per_install,
		"product interaction 'linked' must match id_scope (see docs/PRIVACY.md)")
	eq(cfg.get_value(sec, "privacy/collected_data/device_id/collected", false), per_install,
		"Device ID declared only with a persistent install id")
	eq(cfg.get_value(sec, "privacy/collected_data/product_interaction/used_for_tracking", true), false, "not tracking")
