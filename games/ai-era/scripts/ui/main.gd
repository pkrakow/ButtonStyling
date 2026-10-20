extends Control
## Screen flow and HUD, portrait-first (base 390x844 points, so 1 unit ~ 1 pt on iPhone).
## Every screen is built in code from standard controls so keyboard focus, touch,
## tooltips and accessibility names work out of the box. Tap targets are >= 44 pt.
## Dev flags (after `--`): --autoplay, --capture=<dir>, --seed=<n>,
##   --sim-safe-area=<top>,<bottom> (phone mode: notch, home indicator, no desktop-only controls),
##   --dev-keys (F8 = background/foreground).

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const Sim := preload("res://scripts/sim/simulation.gd")
const D := preload("res://scripts/sim/sim_data.gd")
const WorldMap := preload("res://scripts/ui/world_map.gd")
const MiniChart := preload("res://scripts/ui/mini_chart.gd")
const Rules := preload("res://scripts/platform/achievement_rules.gd")
const RunSave := preload("res://scripts/core/run_save.gd")
const Collection := preload("res://scripts/core/collection.gd")

const TAP := 48 # minimum tap target height (Apple HIG: 44 pt)
const STAT_LABELS := {
	"capability": "AI capability", "safety": "Safety", "trust": "Public trust", "inequality": "Inequality",
	"prosperity": "Prosperity", "jobs": "Jobs", "unrest": "Unrest", "compute": "Compute", "adoption": "AI adoption",
}
const LEVER_LABELS := {
	"research": "research speed", "alignment": "safety research", "safety_net": "safety net",
	"retraining": "retraining", "regulation": "regulation", "openness": "openness", "health": "health research",
}
const HIGHER_IS_WORSE := ["inequality", "unrest"]
const TYPE_LABELS := {"policy": "POLICY", "research": "RESEARCH", "invest": "INVESTMENT"}
const OVERLAY_KEYS := {KEY_P: "prosperity", KEY_J: "jobs", KEY_U: "unrest", KEY_C: "compute", KEY_A: "adoption"}

var screen: Control
var layer: Control
var current_screen := ""
var _focus_before_layer: Control
var _safe_nodes: Array[MarginContainer] = []

var sim: Sim
var run_id := ""
var run_active := false
var paused := false
var active_ms := 0.0
var pause_started_ms := 0
var pause_total_ms := 0
var background_started_ms := 0
var decision_shown_at := 0.0
var focus_changes := 0
var hover_changes := 0
var input_lock_until := 0
var last_input := "unknown"
var app_start_tracked := false
var session_start_ms := 0
var title_notice := ""

var save := RunSave.new()
var collection := Collection.new()
var map: WorldMap
var hud := {}
var option_buttons: Array[Button] = []
var overlay_buttons := {}

var dev_autoplay := false
var dev_capture := ""
var dev_seed := -1
var dev_keys := false
var dev_safe := {}
var _dev_rng := RandomNumberGenerator.new()
var _captured := {}


func _ready() -> void:
	session_start_ms = Time.get_ticks_msec()
	theme = UITheme.build()
	get_tree().set_auto_accept_quit(false)
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_parse_dev_args()
	get_viewport().size_changed.connect(_apply_safe_area)
	if Settings.consent() == "unset":
		_show_consent()
	else:
		_track_app_start(false)
		_show_title()
	if not dev_safe.is_empty():
		add_child(DevNotch.new())
	if dev_autoplay:
		var t := Timer.new()
		t.wait_time = 0.9
		t.autostart = true
		t.timeout.connect(_autoplay_step)
		add_child(t)


func _parse_dev_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay":
			dev_autoplay = true
		elif a == "--dev-keys":
			dev_keys = true
		elif a.begins_with("--capture="):
			dev_capture = a.trim_prefix("--capture=")
			DirAccess.make_dir_recursive_absolute(dev_capture)
		elif a.begins_with("--seed="):
			dev_seed = int(a.trim_prefix("--seed="))
		elif a.begins_with("--sim-safe-area="):
			var p := a.trim_prefix("--sim-safe-area=").split(",")
			dev_safe = {"top": float(p[0]), "bottom": float(p[1]) if p.size() > 1 else 0.0, "left": 0.0, "right": 0.0}
	_dev_rng.seed = 99


## True on iOS/Android, and on desktop when simulating a phone with --sim-safe-area
## (hides desktop-only controls such as Quit and Fullscreen).
static func is_mobile() -> bool:
	return phone_layout(OS.has_feature("mobile"), OS.get_cmdline_user_args())


static func phone_layout(mobile_feature: bool, user_args: PackedStringArray) -> bool:
	if mobile_feature:
		return true
	for a in user_args:
		if a.begins_with("--sim-safe-area="):
			return true
	return false


# ------------------------------------------------------------------ safe area

## Insets in viewport units (points). Real values on iOS/Android; zero on desktop
## unless simulated with --sim-safe-area.
func safe_insets() -> Dictionary:
	if not dev_safe.is_empty():
		return dev_safe
	if not is_mobile():
		return {"top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0}
	var safe := DisplayServer.get_display_safe_area()
	var win := Vector2(DisplayServer.window_get_size())
	var vp := get_viewport_rect().size
	if win.x <= 0 or win.y <= 0:
		return {"top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0}
	var s := vp / win
	return {"top": safe.position.y * s.y, "bottom": maxf(0.0, (win.y - safe.end.y) * s.y),
		"left": safe.position.x * s.x, "right": maxf(0.0, (win.x - safe.end.x) * s.x)}


func _safe_margin(pad: int = 10) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.set_meta("pad", pad)
	_safe_nodes.append(m)
	_apply_safe_to(m)
	return m


func _apply_safe_to(m: MarginContainer) -> void:
	var ins := safe_insets()
	var pad: int = m.get_meta("pad", 10)
	m.add_theme_constant_override("margin_top", int(ins.top) + pad)
	m.add_theme_constant_override("margin_bottom", int(ins.bottom) + pad)
	m.add_theme_constant_override("margin_left", int(ins.left) + pad)
	m.add_theme_constant_override("margin_right", int(ins.right) + pad)


func _apply_safe_area() -> void:
	_safe_nodes = _safe_nodes.filter(func(n): return is_instance_valid(n))
	for m in _safe_nodes:
		_apply_safe_to(m)


func content_width() -> float:
	var ins := safe_insets()
	return minf(560.0, get_viewport_rect().size.x - ins.left - ins.right - 20.0)


# ------------------------------------------------------------------ helpers

func _track(event_name: String, props: Dictionary = {}) -> void:
	Telemetry.track(event_name, props)


func _track_app_start(first_launch: bool) -> void:
	if app_start_tracked or not Telemetry.is_enabled():
		return
	app_start_tracked = true
	var ss := DisplayServer.screen_get_size()
	var props := {
		"first_launch": first_launch, "locale": OS.get_locale_language(),
		"screen_w": ss.x, "screen_h": ss.y, "ui_scale": Settings.get_value("ui/scale"),
		"reduced_motion": Settings.get_value("ui/reduced_motion"), "has_saved_run": save.exists(),
		"endings_found": collection.found_count(),
	}
	props.merge(Platform.segment_info())
	_track("app_start", props)


func _set_screen(name: String, node: Control) -> void:
	if screen:
		screen.queue_free()
	_close_layer(false)
	screen = node
	add_child(screen)
	move_child(screen, 1)
	current_screen = name
	_track("screen_view", {"screen": name})
	_capture_once(name)


func _label(text: String, size: int = 16, color: Color = UITheme.TEXT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, element: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(TAP, TAP)
	b.pressed.connect(func():
		_track("ui_interaction", {"element": element, "action": "press", "screen": _layer_name() if layer else current_screen, "input": last_input})
		cb.call())
	return b


func _accessible(c: Control, text: String) -> void:
	if "accessibility_name" in c:
		c.set("accessibility_name", text)


## Full-screen scrolling column inside the safe area: returns [root, vbox].
func _column_screen(center_vertically: bool) -> Array:
	var root := _safe_margin(10)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(outer)
	scroll.resized.connect(func(): outer.custom_minimum_size.y = scroll.size.y)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.custom_minimum_size.x = content_width()
	if center_vertically:
		var top := Control.new()
		top.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var bottom := Control.new()
		bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer.add_child(top)
		outer.add_child(vb)
		outer.add_child(bottom)
	else:
		outer.add_child(vb)
	return [root, vb]


func _panel_column(vb: VBoxContainer) -> VBoxContainer:
	var panel := PanelContainer.new()
	vb.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	panel.add_child(inner)
	return inner


func _fmt_delta(v: float) -> String:
	if absf(v) < 0.05:
		return "0.0"
	return ("+%.1f" % v) if v >= 0.0 else ("−%.1f" % absf(v))


func fx_summary(fx: Dictionary, target_code: String = "") -> String:
	var parts := []
	var ongoing := []
	for k in fx:
		var v := float(fx[k])
		var key := String(k)
		var amount := ("+%s" % str(v)) if v > 0 else ("−%s" % str(absf(v)))
		amount = amount.replace(".0", "")
		if key.begins_with("lever."):
			ongoing.append("%s %s" % [LEVER_LABELS[key.trim_prefix("lever.")], amount])
		elif key.begins_with("all."):
			parts.append("%s %s (all)" % [STAT_LABELS[key.trim_prefix("all.")], amount])
		elif key.begins_with("target."):
			parts.append("%s %s (%s)" % [STAT_LABELS[key.trim_prefix("target.")], amount, target_code])
		else:
			parts.append("%s %s" % [STAT_LABELS[key], amount])
	var s := ", ".join(parts)
	if not ongoing.is_empty():
		s += ("\n" if s != "" else "") + "Ongoing: " + ", ".join(ongoing)
	return s


# ------------------------------------------------------------------ consent

func _show_consent() -> void:
	var parts := _column_screen(true)
	var vb := _panel_column(parts[1])
	vb.add_child(_label("Help improve Runtime: Takeoff?", 24, UITheme.TEXT, true))
	vb.add_child(_label("You can share anonymous play data with the developers. It records gameplay only: the choices you make, how long they take, pauses, settings, and how runs end. It uses random IDs, never your Apple ID, advertising ID, name, or anything you type.", 15, UITheme.TEXT, true))
	vb.add_child(_label("Sharing is off unless you turn it on. You can change this any time in Settings, and turning it off deletes what was recorded on this device.", 15, UITheme.TEXT_DIM, true))
	var yes := _button("Share anonymous play data", "consent_share", func(): _decide_consent(true))
	var no := _button("Don't share", "consent_decline", func(): _decide_consent(false))
	vb.add_child(yes)
	vb.add_child(no)
	var more := _button("Read the privacy notice", "consent_privacy", func(): _open_privacy())
	more.flat = true
	vb.add_child(more)
	_set_screen("consent", parts[0])
	more.grab_focus.call_deferred()


func _decide_consent(granted: bool) -> void:
	Telemetry.set_consent(granted, "first_launch")
	_track_app_start(true)
	_show_title()


# ------------------------------------------------------------------ title

func _show_title() -> void:
	var parts := _column_screen(true)
	var vb: VBoxContainer = parts[1]
	vb.add_child(_label("RUNTIME:\nTAKEOFF", 34, UITheme.FOCUS))
	vb.add_child(_label("Fall 2022. A chatbot goes viral. Steer the next eight years of AI, one quarter at a time, and see what it does to the world.", 16, UITheme.TEXT, true))
	vb.add_child(_label("About 15–25 minutes per run, saved as you go. Every seed plays differently.", 14, UITheme.TEXT_DIM, true))
	if title_notice != "":
		vb.add_child(_label(title_notice, 14, UITheme.BAD, true))
		title_notice = ""
	var first: Button
	var saved := save.read()
	if not saved.is_empty():
		first = _button("Continue · %s · seed %d" % [saved.get("date", "?"), int(saved.seed)], "title_continue", func(): _resume_run())
		vb.add_child(first)
	var held := {}
	held.new = _button("New run", "title_new_run", func():
		if save.exists() and held.new.text == "New run":
			held.new.text = "Tap again to replace your saved run"
			return
		_start_run(_random_seed(), "random"))
	vb.add_child(held.new)
	if first == null:
		first = held.new
	var seed_row := HBoxContainer.new()
	var seed_edit := LineEdit.new()
	seed_edit.placeholder_text = "Seed (numbers or words)"
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.custom_minimum_size.y = TAP
	seed_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_accessible(seed_edit, "Seed")
	var seed_err := _label("", 14, UITheme.BAD, true)
	var go_seed := func():
		var txt := seed_edit.text.strip_edges()
		if txt == "":
			seed_err.text = "Enter a seed first, or choose New run for a random one."
			seed_edit.grab_focus()
			return
		_start_run(seed_from_text(txt), "custom")
	seed_edit.text_submitted.connect(func(_t): go_seed.call())
	seed_row.add_child(seed_edit)
	seed_row.add_child(_button("Play seed", "title_play_seed", go_seed))
	vb.add_child(seed_row)
	vb.add_child(seed_err)
	vb.add_child(_button("Endings found: %d of %d" % [collection.found_count(), D.ENDINGS.size()], "title_endings", func(): _show_collection()))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var row_buttons := [_button("Settings", "title_settings", func(): _open_settings()),
		_button("Privacy", "title_privacy", func(): _open_privacy())]
	if not is_mobile():
		row_buttons.append(_button("Quit", "title_quit", func(): _quit("title")))
	for b in row_buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	vb.add_child(row)
	var status := "Play data: %s · v%s" % ["shared" if Telemetry.is_enabled() else "not shared", ProjectSettings.get_setting("application/config/version")]
	vb.add_child(_label(status, 13, UITheme.TEXT_DIM))
	_set_screen("title", parts[0])
	first.grab_focus.call_deferred()


static func seed_from_text(txt: String) -> int:
	if txt.is_valid_int():
		return absi(int(txt)) % 1000000000
	return absi(hash(txt.to_lower())) % 1000000000


func _random_seed() -> int:
	if dev_seed >= 0:
		return dev_seed
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r.randi_range(1, 999999999)


# ------------------------------------------------------------------ collection

func _show_collection() -> void:
	var parts := _column_screen(false)
	var vb: VBoxContainer = parts[1]
	vb.add_child(_label("Endings", 28))
	vb.add_child(_label("%d of %d found. Furthest year reached: %s." % [collection.found_count(), D.ENDINGS.size(),
		str(collection.max_year()) if collection.max_year() > 0 else "none yet"], 15, UITheme.TEXT_DIM, true))
	var eras := HBoxContainer.new()
	eras.add_theme_constant_override("separation", 2)
	for y in range(D.START_YEAR, 2031):
		var reached := collection.max_year() >= y
		var l := _label(("%d" % (y % 100)).pad_zeros(2), 13, UITheme.FOCUS if reached else UITheme.TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.tooltip_text = "%d %s" % [y, "reached" if reached else "not reached"]
		if reached:
			l.text = "■" + l.text
		else:
			l.text = "□" + l.text
		eras.add_child(l)
	vb.add_child(_label("Eras (■ reached, □ not yet)", 13, UITheme.TEXT_DIM))
	vb.add_child(eras)
	for id in ["abundance", "careful", "muddle", "divide", "winter", "collapse", "runaway"]:
		var e: Dictionary = D.ENDINGS[id]
		var got := collection.ending(id)
		var panel := PanelContainer.new()
		var col := VBoxContainer.new()
		panel.add_child(col)
		if got.is_empty():
			col.add_child(_label("□ Not found yet", 13, UITheme.TEXT_DIM))
			col.add_child(_label("???", 18, UITheme.TEXT_DIM))
			col.add_child(_label("Hint: " + e.hint, 14, UITheme.TEXT_DIM, true))
		else:
			col.add_child(_label("■ Found %d× · first on %s, seed %d" % [int(got.count), got.first_found, int(got.first_seed)], 13, UITheme.ACCENT, true))
			col.add_child(_label(e.title, 18, UITheme.FOCUS))
			col.add_child(_label(e.summary, 14, UITheme.TEXT, true))
		vb.add_child(panel)
	var back := _button("Back", "collection_back", func(): _show_title())
	vb.add_child(back)
	_set_screen("collection", parts[0])
	back.grab_focus.call_deferred()


# ------------------------------------------------------------------ run lifecycle

func _start_run(seed_value: int, source: String) -> void:
	_discard_saved_run("replaced_by_new_run")
	sim = Sim.new()
	sim.start(seed_value)
	run_id = Telemetry.core.new_uuid()
	run_active = true
	paused = false
	active_ms = 0.0
	pause_total_ms = 0
	Telemetry.core.begin_run(run_id, seed_value)
	_track("run_start", {"seed_source": source, "max_turns": D.MAX_TURNS, "start_date": sim.date_label()})
	Platform.apply(Rules.on_run_start())
	_save_run()
	_build_game_screen()
	_refresh_game()


func _resume_run() -> void:
	var data := save.read()
	var restored = Sim.restore(int(data.get("seed", 0)), data.get("actions", [])) if not data.is_empty() else null
	if restored == null or restored.is_over():
		GameLog.warn("save.restore", {"msg": "saved run could not be replayed", "game_version": str(data.get("game_version", ""))})
		_discard_saved_run("save_invalid")
		title_notice = "Your saved run was made with a different version and couldn't be restored."
		_show_title()
		return
	sim = restored
	run_id = str(data.get("run_id", Telemetry.core.new_uuid()))
	run_active = true
	paused = false
	active_ms = float(data.get("active_ms", 0.0))
	pause_total_ms = int(data.get("pause_ms", 0))
	Telemetry.core.begin_run(run_id, sim.seed_value)
	_track("run_resume", {"turn": sim.turn, "date": sim.date_label(),
		"saved_age_s": int(Time.get_unix_time_from_system()) - int(data.get("saved_at_unix", 0))})
	_build_game_screen()
	_refresh_game()


func _save_run() -> void:
	if not run_active or sim == null:
		return
	var err := save.write({"seed": sim.seed_value, "actions": sim.actions, "run_id": run_id, "active_ms": int(active_ms),
		"pause_ms": pause_total_ms, "turn": sim.turn, "date": sim.date_label(),
		"game_version": ProjectSettings.get_setting("application/config/version")})
	if err != "":
		GameLog.error("save.write", {"msg": err, "path": save.path})


## Leaving an active run without ending it: it stays saved and resumable.
func _suspend(reason: String) -> void:
	if not run_active:
		return
	_save_run()
	_track("run_suspend", {"reason": reason, "turn": sim.turn, "date": sim.date_label(), "active_ms": int(active_ms)})
	run_active = false
	Telemetry.core.end_run()


func _discard_saved_run(reason: String) -> void:
	var data := save.read()
	if data.is_empty():
		save.clear()
		return
	Telemetry.core.begin_run(str(data.get("run_id", "")), int(data.seed))
	_track("run_abandon", {"reason": reason, "turn": int(data.get("turn", 0)), "date": str(data.get("date", "")),
		"active_ms": int(data.get("active_ms", 0))})
	Platform.apply(Rules.on_run_abandon(), true)
	Telemetry.core.end_run()
	save.clear()


func _finish_run() -> void:
	run_active = false
	save.clear()
	var s: Dictionary = sim.summary()
	s["active_ms"] = int(active_ms)
	s["pause_ms"] = pause_total_ms
	var is_new := collection.record_ending(sim.ending_id, sim.seed_value)
	s["new_ending"] = is_new
	s["endings_found"] = collection.found_count()
	_track("run_end", s)
	Platform.apply(Rules.on_run_end(sim.ending_id, sim.turn, D.MAX_TURNS), true)
	Telemetry.core.end_run()
	Telemetry.flush_now()
	_show_end(is_new)


func _abandon_current(reason: String) -> void:
	if not run_active:
		return
	run_active = false
	_track("run_abandon", {"reason": reason, "turn": sim.turn, "date": sim.date_label(), "active_ms": int(active_ms),
		"pause_ms": pause_total_ms, "state": sim.snapshot()})
	Platform.apply(Rules.on_run_abandon(), true)
	Telemetry.core.end_run()
	save.clear()


func _quit(source: String) -> void:
	_suspend("quit_game" if source != "window_close" else "window_close")
	_track("app_exit", {"source": source, "session_ms": Time.get_ticks_msec() - session_start_ms})
	Telemetry.flush_now()
	GameLog.info("app.exit", {"source": source})
	get_tree().quit()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_quit("window_close")
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if current_screen == "game" and run_active and not paused and not dev_autoplay:
				_set_paused(true, "focus_lost")
		NOTIFICATION_APPLICATION_PAUSED:
			on_app_background()
		NOTIFICATION_APPLICATION_RESUMED:
			on_app_foreground()


## iOS/Android moved the app to the background. The OS may kill it without further
## notice, so pause, save and flush now.
func on_app_background() -> void:
	background_started_ms = Time.get_ticks_msec()
	if current_screen == "game" and run_active:
		_set_paused(true, "app_background")
		_save_run()
	_track("app_background", {"screen": current_screen, "run_active": run_active, "turn": sim.turn if sim and run_active else -1})
	Telemetry.flush_now()


func on_app_foreground() -> void:
	var ms := Time.get_ticks_msec() - background_started_ms if background_started_ms > 0 else 0
	background_started_ms = 0
	_track("app_foreground", {"screen": current_screen, "background_ms": ms})


func _process(delta: float) -> void:
	if current_screen == "game" and run_active and not paused and background_started_ms == 0:
		active_ms += delta * 1000.0


# ------------------------------------------------------------------ game screen

func _build_game_screen() -> void:
	hud = {}
	var parts := _column_screen(false)
	var outer: VBoxContainer = parts[1]
	outer.add_theme_constant_override("separation", 6)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var date_col := VBoxContainer.new()
	date_col.add_theme_constant_override("separation", 0)
	hud.date = _label("", 24, UITheme.FOCUS)
	hud.turn = _label("", 13, UITheme.TEXT_DIM)
	date_col.add_child(hud.date)
	date_col.add_child(hud.turn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.seed = _label("", 13, UITheme.TEXT_DIM)
	hud.seed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hud.seed.tooltip_text = "Enter this seed on the title screen to replay the same world."
	hud.seed.mouse_filter = Control.MOUSE_FILTER_PASS
	var pause := _button("Pause", "hud_pause", func(): _set_paused(true, "button"))
	pause.custom_minimum_size = Vector2(80, TAP)
	pause.focus_mode = Control.FOCUS_CLICK
	pause.tooltip_text = "Pause (Esc)"
	for c in [date_col, spacer, hud.seed, pause]:
		top.add_child(c)
	hud.progress = ProgressBar.new()
	hud.progress.max_value = D.MAX_TURNS
	hud.progress.show_percentage = false
	hud.progress.custom_minimum_size = Vector2(0, 6)
	_accessible(hud.progress, "Run progress")

	# Date, turn and Pause stay pinned above the scrolling content.
	var root: Control = parts[0]
	var scroll: ScrollContainer = root.get_child(0)
	root.remove_child(scroll)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 6)
	root.add_child(frame)
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	header.custom_minimum_size.x = content_width()
	header.add_child(top)
	header.add_child(hud.progress)
	frame.add_child(header)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(scroll)

	map = WorldMap.new()
	map.custom_minimum_size = Vector2(0, 178)
	map.tooltip_text = " "
	map.reduced_motion = Settings.get_value("ui/reduced_motion")
	map.region_tapped.connect(_on_region_tapped)
	outer.add_child(map)
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	overlay_buttons = {}
	for key in OVERLAY_KEYS:
		var ov: String = OVERLAY_KEYS[key]
		var b := _button(WorldMap.OVERLAY_SHORT[ov], "overlay_" + ov, func(): _set_overlay(ov))
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_CLICK
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(44, 44)
		b.add_theme_font_size_override("font_size", 12)
		b.tooltip_text = "Show %s on the map (%s)" % [WorldMap.OVERLAY_NAMES[ov], OS.get_keycode_string(key)]
		for st in ["normal", "hover", "pressed"]:
			var sb: StyleBoxFlat = b.get_theme_stylebox(st).duplicate()
			sb.content_margin_left = 2
			sb.content_margin_right = 2
			b.add_theme_stylebox_override(st, sb)
		overlay_buttons[ov] = b
		orow.add_child(b)
	outer.add_child(orow)
	hud.legend = _label("", 12, UITheme.TEXT_DIM, true)
	outer.add_child(hud.legend)

	var stats_panel := PanelContainer.new()
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	stats_panel.add_child(sv)
	hud.pop = _label("", 15)
	sv.add_child(hud.pop)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	hud.rows = {}
	for stat in ["capability", "safety", "trust", "inequality", "prosperity", "jobs", "unrest"]:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 1)
		var line := HBoxContainer.new()
		var name_l := _label(STAT_LABELS[stat], 13)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val := _label("", 13)
		line.add_child(name_l)
		line.add_child(val)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 4)
		cell.add_child(line)
		cell.add_child(bar)
		grid.add_child(cell)
		hud.rows[stat] = [bar, val]
	sv.add_child(grid)
	sv.add_child(_label("Prosperity, jobs and unrest are world averages.", 11, UITheme.TEXT_DIM))
	hud.warnings = _label("", 13, UITheme.FOCUS, true)
	sv.add_child(hud.warnings)
	outer.add_child(stats_panel)
	hud.news = _label("", 13, UITheme.TEXT, true)
	outer.add_child(hud.news)
	hud.prompt = _label("", 15, UITheme.TEXT, true)
	outer.add_child(hud.prompt)
	hud.options = VBoxContainer.new()
	hud.options.add_theme_constant_override("separation", 8)
	outer.add_child(hud.options)

	_set_screen("game", parts[0])
	_set_overlay("prosperity", false)


func _set_overlay(ov: String, log_it: bool = true) -> void:
	if map == null:
		return
	map.overlay = ov
	overlay_buttons[ov].button_pressed = true
	hud.legend.text = "%s: brighter, fuller squares = higher. Labels show each region's value and ▲/▼ change. ▣ datacenter · ! unrest. Tap a region for details." % WorldMap.OVERLAY_NAMES[ov]
	if log_it:
		_track("overlay_changed", {"overlay": ov, "turn": sim.turn if sim else -1, "input": last_input})


func _on_region_tapped(index: int) -> void:
	var r: Dictionary = sim.regions[index]
	hud.legend.text = "%s: population %.0f M · prosperity %d · jobs %d · unrest %d · compute %d · AI adoption %d" % [
		r.name, r.pop, r.prosperity, r.jobs, r.unrest, r.compute, r.adoption]
	_track("ui_interaction", {"element": "map_region_" + String(r.id), "action": "tap", "screen": "game", "input": last_input})


func _refresh_game() -> void:
	hud.date.text = sim.date_label()
	hud.turn.text = "Quarter %d of %d" % [mini(sim.turn + 1, D.MAX_TURNS), D.MAX_TURNS]
	hud.progress.value = sim.turn
	hud.seed.text = "Seed %d" % sim.seed_value
	map.set_state(sim.regions)
	var prev: Dictionary = sim.history[-2] if sim.history.size() >= 2 else sim.history[-1]
	var now: Dictionary = sim.history[-1]
	hud.pop.text = "Population %.2f B (%s M this quarter)" % [now.population_m / 1000.0, _fmt_delta(now.population_m - prev.population_m)]
	for stat in hud.rows:
		var v: float = now[stat]
		var dv: float = v - prev[stat]
		var bar: ProgressBar = hud.rows[stat][0]
		var val: Label = hud.rows[stat][1]
		bar.value = v
		var arrow := "▲" if dv >= 0.5 else ("▼" if dv <= -0.5 else "■")
		val.text = "%d %s%s" % [int(round(v)), arrow, _fmt_delta(dv)]
		var worse: bool = (dv > 0.5) == (stat in HIGHER_IS_WORSE) and absf(dv) >= 0.5
		val.add_theme_color_override("font_color", UITheme.BAD if worse else (UITheme.GOOD if absf(dv) >= 0.5 else UITheme.TEXT))
		_accessible(bar, "%s %d" % [STAT_LABELS[stat], int(round(v))])
	var warns := []
	var gap: float = sim.g.capability - sim.g.safety
	if gap >= 25.0:
		warns.append("⚠ Capability is outpacing safety by %d. At 40+ (with capability 75+) the run ends badly." % int(gap))
	if sim.avg("unrest") >= 55.0:
		warns.append("⚠ Unrest is high (%d). Three quarters at 70+ ends the run." % int(sim.avg("unrest")))
	hud.warnings.text = "\n".join(warns)
	hud.warnings.visible = not warns.is_empty()
	var lines := []
	for i in range(sim.news.size() - 1, maxi(-1, sim.news.size() - 3), -1):
		var n: Dictionary = sim.news[i]
		lines.append("%s · %s: %s" % [Sim.date_for_turn(n.turn).year, n.title, n.text])
	hud.news.text = "\n".join(lines)
	for n in sim.turn_news:
		if n.region != "":
			map.pulse(n.region)
	_build_options()


func _build_options() -> void:
	for c in hud.options.get_children():
		c.queue_free()
	option_buttons = []
	focus_changes = 0
	hover_changes = 0
	if sim.phase == Sim.Phase.DILEMMA:
		var ev: Dictionary = sim.pending_event
		hud.prompt.text = "%s: %s Choose a response." % [ev.title, ev.text]
		for i in ev.options.size():
			var opt: Dictionary = ev.options[i]
			option_buttons.append(_option_button(i, "RESPONSE", opt.label, "", fx_summary(opt.fx)))
	else:
		hud.prompt.text = "Choose one action for %s:" % sim.date_label()
		for i in sim.offers.size():
			var c: Dictionary = sim.offers[i]
			var code := ""
			if c.has("target_index"):
				code = sim.regions[c.target_index].code
			option_buttons.append(_option_button(i, TYPE_LABELS[c.type], c.title, c.text, fx_summary(c.fx, code)))
	for i in option_buttons.size():
		var b := option_buttons[i]
		var up_i := (i - 1 + option_buttons.size()) % option_buttons.size()
		var down_i := (i + 1) % option_buttons.size()
		b.focus_neighbor_top = b.get_path_to(option_buttons[up_i])
		b.focus_neighbor_bottom = b.get_path_to(option_buttons[down_i])
	decision_shown_at = active_ms
	input_lock_until = Time.get_ticks_msec() + 350
	if not paused and not option_buttons.is_empty() and last_input != "touch":
		option_buttons[0].grab_focus.call_deferred()


func _option_button(index: int, tag: String, title: String, text: String, effects: String) -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 64
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 2)
	m.add_child(vb)
	b.add_child(m)
	var parts := [_label("%d · %s" % [index + 1, tag], 12, UITheme.ACCENT), _label(title, 17, UITheme.TEXT, true)]
	if text != "":
		parts.append(_label(text, 13, UITheme.TEXT, true))
	parts.append(_label(effects, 12, UITheme.TEXT_DIM, true))
	for l in parts:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(l)
	# Buttons don't size to custom children; grow the button to fit its content.
	vb.minimum_size_changed.connect(func(): b.custom_minimum_size.y = maxf(64.0, vb.get_combined_minimum_size().y + 20.0))
	var full := "%d. %s: %s. %s Effects: %s" % [index + 1, tag, title, text, effects.replace("\n", ". ")]
	b.tooltip_text = full
	_accessible(b, full)
	b.pressed.connect(_choose.bind(index))
	b.focus_entered.connect(func(): focus_changes += 1)
	b.mouse_entered.connect(func(): hover_changes += 1)
	hud.options.add_child(b)
	return b


func _choose(index: int) -> void:
	if paused or not run_active or Time.get_ticks_msec() < input_lock_until:
		return
	var kind := "dilemma" if sim.phase == Sim.Phase.DILEMMA else "card"
	var shown := []
	var chosen := {}
	var props := {"turn": sim.turn, "date": sim.date_label(), "kind": kind, "chosen_index": index,
		"decision_ms": int(active_ms - decision_shown_at), "input": last_input,
		"focus_changes": maxi(0, focus_changes - 1), "hover_changes": hover_changes}
	if kind == "card":
		for c in sim.offers:
			shown.append({"id": c.id, "type": c.type, "target": c.get("target_id", "")})
		chosen = shown[index]
		props["chosen_id"] = chosen.id
		props["chosen_type"] = chosen.type
	else:
		var ev: Dictionary = sim.pending_event
		props["event_id"] = ev.id
		for i in ev.options.size():
			shown.append({"id": "%s:%d" % [ev.id, i], "label": ev.options[i].label})
		chosen = shown[index]
		props["chosen_id"] = chosen.id
	props["options_shown"] = shown
	var turn_before := sim.turn
	var ok := sim.choose_card(index) if kind == "card" else sim.choose_dilemma(index)
	if not ok:
		GameLog.error("sim.choose", {"kind": kind, "index": index, "turn": turn_before})
		return
	_track("decision", props)
	Platform.apply(Rules.on_decision(kind, chosen.get("type", ""), chosen.get("label", ""), Sim.date_for_turn(turn_before).year,
		sim.picked_cards.size() + (1 if kind == "dilemma" else 0)))
	collection.record_year(Sim.date_for_turn(turn_before).year)
	if sim.turn != turn_before:
		var events := []
		for n in sim.news:
			if n.turn == turn_before and n.id != "e_launch":
				events.append(n.id)
		_track("turn_resolved", {"turn": turn_before, "date": Sim.date_for_turn(turn_before), "state": sim.history[-1], "events": events})
		if sim.date().quarter == 1 or sim.turn in [1, 12, 24]:
			_capture_once("turn_%02d" % sim.turn)
	if sim.is_over():
		_finish_run()
		return
	_save_run()
	_refresh_game()
	if sim.phase == Sim.Phase.DILEMMA:
		_capture_once("dilemma")


# ------------------------------------------------------------------ pause / layers

func _set_paused(on: bool, reason: String) -> void:
	if on == paused or current_screen != "game":
		return
	paused = on
	if on:
		pause_started_ms = Time.get_ticks_msec()
		_track("pause", {"reason": reason, "turn": sim.turn})
		_show_pause_menu()
	else:
		var ms := Time.get_ticks_msec() - pause_started_ms
		pause_total_ms += ms
		_track("resume", {"pause_ms": ms, "turn": sim.turn})
		_close_layer(true)
		input_lock_until = Time.get_ticks_msec() + 250
		if not option_buttons.is_empty() and last_input != "touch":
			option_buttons[0].grab_focus()


func _open_layer(name: String, build: Callable) -> void:
	_close_layer(false)
	_focus_before_layer = get_viewport().gui_get_focus_owner()
	layer = Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	add_child(layer)
	if screen:
		move_child(layer, screen.get_index() + 1)
	var parts := _column_screen(true)
	layer.add_child(parts[0])
	build.call(_panel_column(parts[1]))
	layer.set_meta("name", name)
	_track("screen_view", {"screen": name})
	_capture_once(name)


func _close_layer(restore_focus: bool) -> void:
	if layer:
		layer.queue_free()
		layer = null
		if restore_focus and is_instance_valid(_focus_before_layer) and last_input != "touch":
			_focus_before_layer.grab_focus()


func _layer_name() -> String:
	return layer.get_meta("name") if layer else ""


func _show_pause_menu() -> void:
	_open_layer("pause", func(vb: VBoxContainer):
		vb.add_child(_label("Paused", 28))
		vb.add_child(_label("%s · Seed %d · progress is saved" % [sim.date_label(), sim.seed_value], 14, UITheme.TEXT_DIM, true))
		var resume := _button("Resume", "pause_resume", func(): _set_paused(false, "button"))
		resume.tooltip_text = "Resume (Esc)"
		vb.add_child(resume)
		vb.add_child(_button("Settings", "pause_settings", func(): _open_settings()))
		vb.add_child(_button("Privacy notice", "pause_privacy", func(): _open_privacy()))
		vb.add_child(_button("Save and go to title", "pause_save_title", func():
			paused = false
			_suspend("quit_to_title")
			_show_title()))
		var held := {}
		held.abandon = _button("Abandon run", "pause_abandon", func():
			if held.abandon.text == "Abandon run":
				held.abandon.text = "Tap again to delete this run"
				return
			paused = false
			_abandon_current("abandoned")
			_show_title())
		vb.add_child(held.abandon)
		if not is_mobile():
			vb.add_child(_button("Save and quit game", "pause_quit_game", func(): _quit("pause_menu")))
		resume.grab_focus.call_deferred())


func _open_settings() -> void:
	var back_to := _layer_name()
	_open_layer("settings", func(vb: VBoxContainer):
		vb.add_child(_label("Settings", 28))
		vb.add_child(_label("Privacy", 18, UITheme.ACCENT))
		var share := CheckButton.new()
		share.text = "Share anonymous play data"
		share.custom_minimum_size.y = TAP
		share.button_pressed = Telemetry.is_enabled()
		vb.add_child(share)
		vb.add_child(_label("Off by default. When on, the game records gameplay events (choices, timings, pauses, endings) with random IDs and uploads them in batches. Turning it off stops recording and deletes everything recorded on this device.", 13, UITheme.TEXT_DIM, true))
		var per_install: bool = Telemetry.id_scope() == "install"
		var id_edit := LineEdit.new()
		id_edit.editable = false
		id_edit.custom_minimum_size.y = TAP
		_accessible(id_edit, "Install ID")
		var copy := _button("Copy ID", "settings_copy_id", func(): DisplayServer.clipboard_set(Telemetry.install_id()))
		var reset := _button("Reset ID", "settings_reset_id", func():
			Telemetry.reset_install_id()
			id_edit.text = Telemetry.install_id())
		if per_install:
			vb.add_child(_label("Install ID", 13))
			vb.add_child(id_edit)
			var id_row := HBoxContainer.new()
			for b in [copy, reset]:
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				id_row.add_child(b)
			vb.add_child(id_row)
			vb.add_child(_label("To ask for your uploaded data to be deleted, send us this ID. See the privacy notice.", 12, UITheme.TEXT_DIM, true))
		else:
			vb.add_child(_label("Each run gets a new random ID, so uploaded data can't be linked across runs or to this device.", 12, UITheme.TEXT_DIM, true))
		var refresh_id := func():
			id_edit.text = Telemetry.install_id() if Telemetry.is_enabled() else "None (sharing is off)"
			copy.disabled = not Telemetry.is_enabled()
			reset.disabled = not Telemetry.is_enabled()
		refresh_id.call()
		share.toggled.connect(func(on: bool):
			_track("ui_interaction", {"element": "settings_share_toggle", "action": "toggle", "screen": "settings", "input": last_input})
			Telemetry.set_consent(on, "settings")
			if on:
				_track_app_start(false)
			refresh_id.call())
		vb.add_child(HSeparator.new())
		vb.add_child(_label("Display", 18, UITheme.ACCENT))
		var scale_row := HBoxContainer.new()
		var sl := _label("Interface size", 15)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scale_row.add_child(sl)
		var scale := OptionButton.new()
		scale.custom_minimum_size = Vector2(100, TAP)
		var scales := [1.0, 1.15, 1.3]
		for s in scales:
			scale.add_item("%d%%" % int(round(s * 100)))
		scale.selected = maxi(0, scales.find(float(Settings.get_value("ui/scale"))))
		scale.item_selected.connect(func(i): Settings.set_value("ui/scale", scales[i]))
		_accessible(scale, "Interface size")
		scale_row.add_child(scale)
		vb.add_child(scale_row)
		var motion := CheckButton.new()
		motion.text = "Reduce motion"
		motion.custom_minimum_size.y = TAP
		motion.button_pressed = Settings.get_value("ui/reduced_motion")
		motion.toggled.connect(func(on):
			Settings.set_value("ui/reduced_motion", on)
			if is_instance_valid(map):
				map.reduced_motion = on)
		vb.add_child(motion)
		if not is_mobile():
			var fs := CheckButton.new()
			fs.text = "Fullscreen"
			fs.custom_minimum_size.y = TAP
			fs.button_pressed = Settings.get_value("display/fullscreen")
			fs.toggled.connect(func(on): Settings.set_value("display/fullscreen", on))
			vb.add_child(fs)
			vb.add_child(_button("Open data folder", "settings_open_folder", func(): OS.shell_open(ProjectSettings.globalize_path("user://"))))
		var back := _button("Back", "settings_back", func(): _back_from_layer(back_to))
		back.tooltip_text = "Back (Esc)"
		vb.add_child(back)
		share.grab_focus.call_deferred())


func _open_privacy() -> void:
	var back_to := _layer_name()
	_open_layer("privacy", func(vb: VBoxContainer):
		vb.add_child(_label("Privacy notice", 26))
		var url: String = ProjectSettings.get_setting("ai_era/privacy_policy_url", "")
		if url != "":
			vb.add_child(_button("Open full policy in browser", "privacy_open_web", func(): OS.shell_open(url)))
		vb.add_child(_label(_privacy_text(), 13, UITheme.TEXT, true))
		var back := _button("Back", "privacy_back", func(): _back_from_layer(back_to))
		vb.add_child(back)
		back.grab_focus.call_deferred())


func _privacy_text() -> String:
	var f := FileAccess.open("res://docs/PRIVACY.md", FileAccess.READ)
	if f == null:
		GameLog.error("privacy.load", {"path": "res://docs/PRIVACY.md", "err": FileAccess.get_open_error()})
		return "The privacy notice could not be loaded. Please contact us using the support link on the App Store page."
	var out := []
	var skip := false
	for line in f.get_as_text().split("\n"):
		if line.begins_with("# "):
			continue
		# The App Store label mapping is for the publisher, not players.
		if line.begins_with("## "):
			skip = line.contains("App Store privacy label")
		if skip:
			continue
		out.append(line.trim_prefix("## ").replace("**", "").replace("`", ""))
	return "\n".join(out)


func _back_from_layer(back_to: String) -> void:
	if back_to == "pause":
		_show_pause_menu()
	else:
		_close_layer(true)
		if current_screen == "game" and paused:
			_show_pause_menu()


# ------------------------------------------------------------------ end screen

func _show_end(is_new: bool) -> void:
	var e: Dictionary = D.ENDINGS[sim.ending_id]
	var parts := _column_screen(false)
	var vb: VBoxContainer = parts[1]
	vb.add_child(_label("NEW ENDING FOUND" if is_new else "ENDING", 13, UITheme.ACCENT))
	vb.add_child(_label(e.title, 30, UITheme.FOCUS, true))
	var early := sim.turn < D.MAX_TURNS
	var s: Dictionary = sim.summary()
	vb.add_child(_label("2022 Q4 → %s%s · %d quarters · seed %d" % [s.final_date, " (ended early)" if early else "", sim.turn, sim.seed_value], 13, UITheme.TEXT_DIM, true))
	vb.add_child(_label("\n".join(sim.epilogue()), 15, UITheme.TEXT, true))
	vb.add_child(_label("Endings found: %d of %d." % [collection.found_count(), D.ENDINGS.size()], 14, UITheme.ACCENT))
	vb.add_child(_label("Your choices: %d policy, %d research, %d investment. Active play time %d min %d s." % [
		s.picks_by_type.policy, s.picks_by_type.research, s.picks_by_type.invest,
		int(active_ms / 60000.0), int(active_ms / 1000.0) % 60], 13, UITheme.TEXT, true))
	vb.add_child(_label("How the world changed", 17, UITheme.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var series := {"population_m": [], "prosperity": [], "unrest": [], "jobs": [], "capability": [], "safety": []}
	for h in sim.history:
		for k in series:
			series[k].append(h[k] / 1000.0 if k == "population_m" else h[k])
	var specs := [["Population (B)", "population_m", "%.2f", Color("eef1f7")],
		["Prosperity", "prosperity", "%.0f", Color("e8c547")], ["Jobs", "jobs", "%.0f", Color("7ee08a")],
		["Unrest", "unrest", "%.0f", Color("ff8a7a")], ["AI capability", "capability", "%.0f", Color("6ec6ff")],
		["Safety", "safety", "%.0f", Color("d58cff")]]
	for sp in specs:
		var ch := MiniChart.new()
		ch.setup(sp[0], series[sp[1]], sp[2], sp[3])
		ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(ch)
	vb.add_child(grid)
	var seed_value := sim.seed_value
	var again := _button("Replay this seed", "end_replay", func(): _start_run(seed_value, "replay"))
	vb.add_child(again)
	vb.add_child(_button("New run", "end_new_run", func(): _start_run(_random_seed(), "random")))
	vb.add_child(_button("Endings", "end_endings", func(): _show_collection()))
	vb.add_child(_button("Title screen", "end_title", func(): _show_title()))
	_set_screen("end", parts[0])
	again.grab_focus.call_deferred()


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		last_input = "touch"
	elif event is InputEventKey and event.pressed:
		last_input = "keyboard"
	elif event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
		last_input = "mouse"
	elif event is InputEventJoypadButton and event.pressed:
		last_input = "gamepad"


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.keycode
	if dev_keys and k == KEY_F8:
		if background_started_ms == 0:
			on_app_background()
		else:
			on_app_foreground()
		return
	if k == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		var ln := _layer_name()
		if ln == "pause":
			_set_paused(false, "esc")
		elif ln == "settings" or ln == "privacy":
			_back_from_layer("pause" if paused else "")
		elif current_screen == "game" and run_active:
			_set_paused(true, "esc")
		elif current_screen == "collection":
			_show_title()
		return
	if current_screen != "game" or layer or paused:
		return
	if k >= KEY_1 and k <= KEY_3:
		var i := k - KEY_1
		if i < option_buttons.size():
			get_viewport().set_input_as_handled()
			last_input = "keyboard"
			_choose(i)
	elif OVERLAY_KEYS.has(k):
		get_viewport().set_input_as_handled()
		_set_overlay(OVERLAY_KEYS[k])


# ------------------------------------------------------------------ dev autoplay / capture

func _autoplay_step() -> void:
	if layer:
		return
	match current_screen:
		"consent":
			_decide_consent(true)
		"title":
			_start_run(_random_seed(), "random")
		"game":
			if Time.get_ticks_msec() >= input_lock_until and not option_buttons.is_empty():
				if _dev_rng.randf() < 0.15:
					_set_overlay(OVERLAY_KEYS.values()[_dev_rng.randi_range(0, 4)])
				_choose(_dev_rng.randi_range(0, option_buttons.size() - 1))
		"end":
			if dev_capture != "" and _captured.has("end") and not _captured.has("quit"):
				_captured["quit"] = true
				await get_tree().create_timer(2.5).timeout
				_quit("autoplay")


func _capture_once(name: String) -> void:
	if dev_capture == "" or _captured.has(name) or DisplayServer.get_name() == "headless":
		return
	_captured[name] = true
	await get_tree().create_timer(0.7).timeout
	var img := get_viewport().get_texture().get_image()
	if img == null:
		GameLog.warn("capture.save", {"msg": "no rendered image"})
		return
	img.convert(Image.FORMAT_RGB8) # App Store screenshots must not have alpha
	var path := dev_capture.path_join("%02d-%s.png" % [_captured.size(), name])
	var err := img.save_png(path)
	if err != OK:
		GameLog.error("capture.save", {"path": path, "err": err})
	else:
		GameLog.info("capture.save", {"path": path})


## Dev-only overlay that mimics an iPhone Dynamic Island and home indicator, so the
## safe-area layout can be checked on desktop with --sim-safe-area.
class DevNotch:
	extends Control
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 100
	func _draw() -> void:
		var w := size.x
		draw_rect(Rect2(Vector2(w / 2 - 44.5, 11), Vector2(89, 37)), Color.BLACK)
		draw_circle(Vector2(w / 2 - 44.5, 29.5), 18.5, Color.BLACK)
		draw_circle(Vector2(w / 2 + 44.5, 29.5), 18.5, Color.BLACK)
		draw_rect(Rect2(Vector2(w / 2 - 67, size.y - 13), Vector2(134, 5)), Color(1, 1, 1, 0.85))
