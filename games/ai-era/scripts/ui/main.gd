extends Control
## Screen flow and HUD. Every screen is built in code from standard controls so
## keyboard focus, tooltips and accessibility names work out of the box.
## Dev flags (after `--`): --autoplay, --capture=<dir>, --seed=<n>.

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const Sim := preload("res://scripts/sim/simulation.gd")
const D := preload("res://scripts/sim/sim_data.gd")
const WorldMap := preload("res://scripts/ui/world_map.gd")
const MiniChart := preload("res://scripts/ui/mini_chart.gd")
const Rules := preload("res://scripts/platform/steam_rules.gd")

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

var sim: Sim
var run_id := ""
var run_active := false
var paused := false
var active_ms := 0.0
var pause_started_ms := 0
var pause_total_ms := 0
var decision_shown_at := 0.0
var focus_changes := 0
var hover_changes := 0
var input_lock_until := 0
var last_input := "unknown"
var app_start_tracked := false
var session_start_ms := 0

var map: WorldMap
var hud := {}
var option_buttons: Array[Button] = []
var overlay_buttons := {}

var dev_autoplay := false
var dev_capture := ""
var dev_seed := -1
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
	if Settings.consent() == "unset":
		_show_consent()
	else:
		_track_app_start(false)
		_show_title()
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
		elif a.begins_with("--capture="):
			dev_capture = a.trim_prefix("--capture=")
			DirAccess.make_dir_recursive_absolute(dev_capture)
		elif a.begins_with("--seed="):
			dev_seed = int(a.trim_prefix("--seed="))
	_dev_rng.seed = 99


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
		"reduced_motion": Settings.get_value("ui/reduced_motion"), "fullscreen": Settings.get_value("display/fullscreen"),
	}
	props.merge(SteamService.segment_info())
	_track("app_start", props)


func _set_screen(name: String, node: Control) -> void:
	if screen:
		screen.queue_free()
	_close_layer(false)
	screen = node
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
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
	b.pressed.connect(func():
		_track("ui_interaction", {"element": element, "action": "press", "screen": _layer_name() if layer else current_screen, "input": last_input})
		cb.call())
	return b


func _accessible(c: Control, text: String) -> void:
	if "accessibility_name" in c:
		c.set("accessibility_name", text)


func _center_panel(min_width: int) -> Array:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = min_width
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	return [center, vb]


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
	var root := Control.new()
	var parts := _center_panel(720)
	root.add_child(parts[0])
	var vb: VBoxContainer = parts[1]
	vb.add_child(_label("Help improve Runtime: Takeoff?", 28))
	vb.add_child(_label("You can share anonymous play data with the developers. It records gameplay only: the choices you make, how long they take, pauses, settings, and how runs end. It uses a random install ID and never your Steam account, name, or anything you type.", 16, UITheme.TEXT, true))
	vb.add_child(_label("Sharing is off unless you turn it on. You can change this any time in Settings, and turning it off deletes what was recorded on this device.", 16, UITheme.TEXT_DIM, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var yes := _button("Share anonymous play data", "consent_share", func(): _decide_consent(true))
	var no := _button("Don't share", "consent_decline", func(): _decide_consent(false))
	for b in [yes, no]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 48
		row.add_child(b)
	vb.add_child(row)
	var more := _button("Read the privacy notice", "consent_privacy", func(): _open_privacy())
	more.flat = true
	vb.add_child(more)
	vb.add_child(_label("Tab moves between options. Enter selects.", 14, UITheme.TEXT_DIM))
	_set_screen("consent", root)
	more.grab_focus.call_deferred()


func _decide_consent(granted: bool) -> void:
	Telemetry.set_consent(granted, "first_launch")
	_track_app_start(true)
	_show_title()


# ------------------------------------------------------------------ title

func _show_title() -> void:
	var root := Control.new()
	var parts := _center_panel(560)
	root.add_child(parts[0])
	var vb: VBoxContainer = parts[1]
	vb.add_child(_label("RUNTIME: TAKEOFF", 36, UITheme.FOCUS))
	vb.add_child(_label("Fall 2022. A chatbot goes viral. Steer the next eight years of AI, one quarter at a time, and see what it does to the world.", 16, UITheme.TEXT, true))
	vb.add_child(_label("About 15–25 minutes per run. Every seed plays differently.", 14, UITheme.TEXT_DIM, true))
	var start := _button("New run", "title_new_run", func(): _start_run(_random_seed(), "random"))
	start.custom_minimum_size.y = 48
	vb.add_child(start)
	var seed_row := HBoxContainer.new()
	var seed_edit := LineEdit.new()
	seed_edit.placeholder_text = "Seed (numbers or words)"
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for b in [_button("Settings", "title_settings", func(): _open_settings()),
			_button("Privacy", "title_privacy", func(): _open_privacy()),
			_button("Quit", "title_quit", func(): _quit("title"))]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	vb.add_child(row)
	var status := "Anonymous play data: %s (change in Settings)" % ("shared" if Telemetry.is_enabled() else "not shared")
	vb.add_child(_label(status + "   ·   v" + ProjectSettings.get_setting("application/config/version"), 13, UITheme.TEXT_DIM))
	_set_screen("title", root)
	start.grab_focus.call_deferred()


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


# ------------------------------------------------------------------ run lifecycle

func _start_run(seed_value: int, source: String) -> void:
	sim = Sim.new()
	sim.start(seed_value)
	run_id = Telemetry.core.new_uuid()
	run_active = true
	paused = false
	active_ms = 0.0
	pause_total_ms = 0
	Telemetry.core.begin_run(run_id, seed_value)
	_track("run_start", {"seed_source": source, "max_turns": D.MAX_TURNS, "start_date": sim.date_label()})
	SteamService.apply(Rules.on_run_start())
	_build_game_screen()
	_refresh_game()


func _finish_run() -> void:
	run_active = false
	var s: Dictionary = sim.summary()
	s["active_ms"] = int(active_ms)
	s["pause_ms"] = pause_total_ms
	_track("run_end", s)
	SteamService.apply(Rules.on_run_end(sim.ending_id, sim.turn, D.MAX_TURNS), true)
	Telemetry.core.end_run()
	Telemetry.flush_now()
	_show_end()


func _abandon(reason: String) -> void:
	if not run_active:
		return
	run_active = false
	_track("run_abandon", {"reason": reason, "turn": sim.turn, "date": sim.date_label(), "active_ms": int(active_ms),
		"pause_ms": pause_total_ms, "state": sim.snapshot()})
	SteamService.apply(Rules.on_run_abandon(), true)
	Telemetry.core.end_run()


func _quit(source: String) -> void:
	_abandon("quit_game" if source != "window_close" else "window_close")
	_track("app_exit", {"source": source, "session_ms": Time.get_ticks_msec() - session_start_ms})
	Telemetry.flush_now()
	GameLog.info("app.exit", {"source": source})
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit("window_close")
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if current_screen == "game" and run_active and not paused and not dev_autoplay:
			_set_paused(true, "focus_lost")


func _process(delta: float) -> void:
	if current_screen == "game" and run_active and not paused:
		active_ms += delta * 1000.0


# ------------------------------------------------------------------ game screen

func _build_game_screen() -> void:
	hud = {}
	var root := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 12)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	root.add_child(outer)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	hud.date = _label("", 26, UITheme.FOCUS)
	hud.turn = _label("", 16, UITheme.TEXT_DIM)
	hud.progress = ProgressBar.new()
	hud.progress.max_value = D.MAX_TURNS
	hud.progress.show_percentage = false
	hud.progress.custom_minimum_size = Vector2(200, 12)
	hud.progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_accessible(hud.progress, "Run progress")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.seed = _label("", 14, UITheme.TEXT_DIM)
	hud.seed.tooltip_text = "Enter this seed on the title screen to replay the same world."
	hud.seed.mouse_filter = Control.MOUSE_FILTER_PASS
	var pause := _button("Pause (Esc)", "hud_pause", func(): _set_paused(true, "button"))
	pause.focus_mode = Control.FOCUS_CLICK
	for c in [hud.date, hud.turn, hud.progress, spacer, hud.seed, pause]:
		top.add_child(c)
	outer.add_child(top)

	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	outer.add_child(mid)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.0
	map = WorldMap.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.custom_minimum_size = Vector2(480, 220)
	map.tooltip_text = " "
	map.reduced_motion = Settings.get_value("ui/reduced_motion")
	left.add_child(map)
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 6)
	orow.add_child(_label("Map shows:", 14, UITheme.TEXT_DIM))
	var group := ButtonGroup.new()
	overlay_buttons = {}
	for key in OVERLAY_KEYS:
		var ov: String = OVERLAY_KEYS[key]
		var b := _button("%s [%s]" % [WorldMap.OVERLAY_NAMES[ov], OS.get_keycode_string(key)], "overlay_" + ov, func(): _set_overlay(ov))
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_CLICK
		b.add_theme_font_size_override("font_size", 14)
		overlay_buttons[ov] = b
		orow.add_child(b)
	left.add_child(orow)
	hud.legend = _label("", 13, UITheme.TEXT_DIM, true)
	left.add_child(hud.legend)
	mid.add_child(left)

	var right := PanelContainer.new()
	right.custom_minimum_size.x = 360
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 4)
	right.add_child(rv)
	rv.add_child(_label("World", 18, UITheme.ACCENT))
	hud.pop = _label("", 16)
	rv.add_child(hud.pop)
	hud.rows = {}
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	for stat in ["capability", "safety", "trust", "inequality", "prosperity", "jobs", "unrest"]:
		var name_l := _label(STAT_LABELS[stat] + (" (avg)" if stat in ["prosperity", "jobs", "unrest"] else ""), 14)
		name_l.custom_minimum_size.x = 130
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(90, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val := _label("", 14)
		val.custom_minimum_size.x = 92
		grid.add_child(name_l)
		grid.add_child(bar)
		grid.add_child(val)
		hud.rows[stat] = [bar, val]
	rv.add_child(grid)
	hud.warnings = _label("", 14, UITheme.FOCUS, true)
	rv.add_child(hud.warnings)
	rv.add_child(HSeparator.new())
	rv.add_child(_label("News", 18, UITheme.ACCENT))
	hud.news = _label("", 14, UITheme.TEXT, true)
	hud.news.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hud.news.clip_text = true
	rv.add_child(hud.news)
	mid.add_child(right)

	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	hud.prompt = _label("", 18, UITheme.TEXT, true)
	bottom.add_child(hud.prompt)
	hud.options = HBoxContainer.new()
	hud.options.add_theme_constant_override("separation", 10)
	hud.options.custom_minimum_size.y = 150
	bottom.add_child(hud.options)
	outer.add_child(bottom)

	_set_screen("game", root)
	_set_overlay("prosperity", false)


func _set_overlay(ov: String, log_it: bool = true) -> void:
	if map == null:
		return
	map.overlay = ov
	overlay_buttons[ov].button_pressed = true
	var r: Array = WorldMap.RAMPS[ov]
	hud.legend.text = "%s: brighter and more filled-in squares mean higher. Labels show each region's value; ▲/▼ is the change since last quarter. Icons: ▣ datacenters, · city lights, ! unrest." % WorldMap.OVERLAY_NAMES[ov]
	if log_it:
		_track("overlay_changed", {"overlay": ov, "turn": sim.turn if sim else -1, "input": last_input})


func _refresh_game() -> void:
	var d := sim.date()
	hud.date.text = sim.date_label()
	hud.turn.text = "Quarter %d of %d" % [mini(sim.turn + 1, D.MAX_TURNS), D.MAX_TURNS]
	hud.progress.value = sim.turn
	hud.seed.text = "Seed %d" % sim.seed_value
	map.set_state(sim.regions)
	var prev: Dictionary = sim.history[-2] if sim.history.size() >= 2 else sim.history[-1]
	var now: Dictionary = sim.history[-1]
	hud.pop.text = "Population %.2f B  (%s M this quarter)" % [now.population_m / 1000.0, _fmt_delta(now.population_m - prev.population_m)]
	for stat in hud.rows:
		var v: float = now[stat]
		var dv: float = v - prev[stat]
		var bar: ProgressBar = hud.rows[stat][0]
		var val: Label = hud.rows[stat][1]
		bar.value = v
		var arrow := "▲" if dv >= 0.5 else ("▼" if dv <= -0.5 else "■")
		val.text = "%d %s %s" % [int(round(v)), arrow, _fmt_delta(dv)]
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
	var lines := []
	for i in range(sim.news.size() - 1, maxi(-1, sim.news.size() - 5), -1):
		var n: Dictionary = sim.news[i]
		lines.append("%s · %s: %s" % [Sim.date_for_turn(n.turn).year, n.title, n.text])
	hud.news.text = "\n\n".join(lines)
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
		hud.prompt.text = "%s — %s. %s Choose a response:" % [sim.date_label(), ev.title, ev.text]
		for i in ev.options.size():
			var opt: Dictionary = ev.options[i]
			option_buttons.append(_option_button(i, "RESPONSE", opt.label, "", fx_summary(opt.fx)))
	else:
		hud.prompt.text = "%s — choose one action for this quarter (keys 1–3, or arrows and Enter):" % sim.date_label()
		for i in sim.offers.size():
			var c: Dictionary = sim.offers[i]
			var code := ""
			if c.has("target_index"):
				code = sim.regions[c.target_index].code
			option_buttons.append(_option_button(i, TYPE_LABELS[c.type], c.title, c.text, fx_summary(c.fx, code)))
	for i in option_buttons.size():
		var b := option_buttons[i]
		var left_i := (i - 1 + option_buttons.size()) % option_buttons.size()
		var right_i := (i + 1) % option_buttons.size()
		b.focus_neighbor_left = b.get_path_to(option_buttons[left_i])
		b.focus_neighbor_right = b.get_path_to(option_buttons[right_i])
	decision_shown_at = active_ms
	input_lock_until = Time.get_ticks_msec() + 350
	if not paused and not option_buttons.is_empty():
		option_buttons[0].grab_focus.call_deferred()


func _option_button(index: int, tag: String, title: String, text: String, effects: String) -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 150
	b.clip_contents = true
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	m.add_child(vb)
	b.add_child(m)
	var parts := [_label("%d · %s" % [index + 1, tag], 13, UITheme.ACCENT), _label(title, 19, UITheme.TEXT, true)]
	if text != "":
		parts.append(_label(text, 14, UITheme.TEXT, true))
	parts.append(_label(effects, 13, UITheme.TEXT_DIM, true))
	for l in parts:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(l)
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
	SteamService.apply(Rules.on_decision(kind, chosen.get("type", ""), chosen.get("label", ""), Sim.date_for_turn(turn_before).year,
		sim.picked_cards.size() + (1 if kind == "dilemma" else 0)))
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
		if not option_buttons.is_empty():
			option_buttons[0].grab_focus()


func _open_layer(name: String, build: Callable) -> void:
	_close_layer(false)
	_focus_before_layer = get_viewport().gui_get_focus_owner()
	layer = Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	add_child(layer)
	build.call(layer)
	layer.set_meta("name", name)
	_track("screen_view", {"screen": name})
	_capture_once(name)


func _close_layer(restore_focus: bool) -> void:
	if layer:
		layer.queue_free()
		layer = null
		if restore_focus and is_instance_valid(_focus_before_layer):
			_focus_before_layer.grab_focus()


func _layer_name() -> String:
	return layer.get_meta("name") if layer else ""


func _show_pause_menu() -> void:
	_open_layer("pause", func(l: Control):
		var parts := _center_panel(420)
		l.add_child(parts[0])
		var vb: VBoxContainer = parts[1]
		vb.add_child(_label("Paused", 28))
		vb.add_child(_label("%s · Seed %d" % [sim.date_label(), sim.seed_value], 14, UITheme.TEXT_DIM))
		var resume := _button("Resume (Esc)", "pause_resume", func(): _set_paused(false, "button"))
		vb.add_child(resume)
		vb.add_child(_button("Settings", "pause_settings", func(): _open_settings()))
		vb.add_child(_button("Privacy notice", "pause_privacy", func(): _open_privacy()))
		var held := {}
		held.title = _button("Quit to title", "pause_quit_title", func():
			if held.title.text == "Quit to title":
				held.title.text = "Press again to end this run"
				return
			paused = false
			_abandon("quit_to_title")
			_show_title())
		vb.add_child(held.title)
		held.quit = _button("Quit game", "pause_quit_game", func():
			if held.quit.text == "Quit game":
				held.quit.text = "Press again to quit (run ends)"
				return
			_quit("pause_menu"))
		vb.add_child(held.quit)
		vb.add_child(_label("Your run is not saved when you quit.", 13, UITheme.TEXT_DIM))
		resume.grab_focus.call_deferred())


func _open_settings() -> void:
	var back_to := _layer_name()
	_open_layer("settings", func(l: Control):
		var parts := _center_panel(640)
		l.add_child(parts[0])
		var vb: VBoxContainer = parts[1]
		vb.add_child(_label("Settings", 28))
		vb.add_child(_label("Privacy", 18, UITheme.ACCENT))
		var share := CheckButton.new()
		share.text = "Share anonymous play data"
		share.button_pressed = Telemetry.is_enabled()
		vb.add_child(share)
		vb.add_child(_label("Off by default. When on, the game records gameplay events (choices, timings, pauses, endings) with a random install ID and uploads them in batches. Turning it off stops recording and deletes everything recorded on this device.", 14, UITheme.TEXT_DIM, true))
		var id_row := HBoxContainer.new()
		id_row.add_child(_label("Install ID:", 14))
		var id_edit := LineEdit.new()
		id_edit.editable = false
		id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_accessible(id_edit, "Install ID")
		id_row.add_child(id_edit)
		var copy := _button("Copy", "settings_copy_id", func(): DisplayServer.clipboard_set(Telemetry.install_id()))
		var reset := _button("Reset ID", "settings_reset_id", func():
			Telemetry.reset_install_id()
			id_edit.text = Telemetry.install_id())
		id_row.add_child(copy)
		id_row.add_child(reset)
		vb.add_child(id_row)
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
		vb.add_child(_label("To ask for your data to be deleted, send us this ID. See the privacy notice.", 13, UITheme.TEXT_DIM, true))
		vb.add_child(HSeparator.new())
		vb.add_child(_label("Display", 18, UITheme.ACCENT))
		var scale_row := HBoxContainer.new()
		scale_row.add_child(_label("Interface size", 14))
		var scale := OptionButton.new()
		var scales := [1.0, 1.25, 1.5]
		for s in scales:
			scale.add_item("%d%%" % int(s * 100))
		scale.selected = maxi(0, scales.find(float(Settings.get_value("ui/scale"))))
		scale.item_selected.connect(func(i): Settings.set_value("ui/scale", scales[i]))
		_accessible(scale, "Interface size")
		scale_row.add_child(scale)
		vb.add_child(scale_row)
		var motion := CheckButton.new()
		motion.text = "Reduce motion (no blinking or waves)"
		motion.button_pressed = Settings.get_value("ui/reduced_motion")
		motion.toggled.connect(func(on):
			Settings.set_value("ui/reduced_motion", on)
			if is_instance_valid(map):
				map.reduced_motion = on)
		vb.add_child(motion)
		var fs := CheckButton.new()
		fs.text = "Fullscreen"
		fs.button_pressed = Settings.get_value("display/fullscreen")
		fs.toggled.connect(func(on): Settings.set_value("display/fullscreen", on))
		vb.add_child(fs)
		vb.add_child(HSeparator.new())
		var files := HBoxContainer.new()
		files.add_child(_button("Open data folder", "settings_open_folder", func(): OS.shell_open(ProjectSettings.globalize_path("user://"))))
		files.add_child(_label("Error log: " + GameLog.log_path(), 12, UITheme.TEXT_DIM, true))
		files.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(files)
		var back := _button("Back (Esc)", "settings_back", func(): _back_from_layer(back_to))
		vb.add_child(back)
		share.grab_focus.call_deferred())


func _open_privacy() -> void:
	var back_to := _layer_name()
	_open_layer("privacy", func(l: Control):
		var parts := _center_panel(760)
		l.add_child(parts[0])
		var vb: VBoxContainer = parts[1]
		vb.add_child(_label("Privacy notice", 28))
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(720, 430)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.focus_mode = Control.FOCUS_ALL
		var text := _label(_privacy_text(), 14, UITheme.TEXT, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(text)
		vb.add_child(scroll)
		var back := _button("Back (Esc)", "privacy_back", func(): _back_from_layer(back_to))
		vb.add_child(back)
		back.grab_focus.call_deferred())


func _privacy_text() -> String:
	var f := FileAccess.open("res://docs/PRIVACY.md", FileAccess.READ)
	if f == null:
		GameLog.error("privacy.load", {"path": "res://docs/PRIVACY.md", "err": FileAccess.get_open_error()})
		return "The privacy notice could not be loaded. Find it at docs/PRIVACY.md in the game folder."
	var out := []
	for line in f.get_as_text().split("\n"):
		if line.begins_with("# "):
			continue
		out.append(line.trim_prefix("# ").trim_prefix("## ").replace("**", "").replace("`", ""))
	return "\n".join(out)


func _back_from_layer(back_to: String) -> void:
	if back_to == "pause":
		_show_pause_menu()
	else:
		_close_layer(true)
		if current_screen == "game" and paused:
			_show_pause_menu()


# ------------------------------------------------------------------ end screen

func _show_end() -> void:
	var e: Dictionary = D.ENDINGS[sim.ending_id]
	var root := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 24)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 24)
	root.add_child(hb)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	hb.add_child(left)
	left.add_child(_label("ENDING", 14, UITheme.ACCENT))
	left.add_child(_label(e.title, 34, UITheme.FOCUS))
	var early := sim.turn < D.MAX_TURNS
	left.add_child(_label("2022 Q4 → %s%s · %d quarters · seed %d" % [
		sim.summary().final_date, " (ended early)" if early else "", sim.turn, sim.seed_value], 14, UITheme.TEXT_DIM))
	var epi := _label("\n".join(sim.epilogue()), 16, UITheme.TEXT, true)
	left.add_child(epi)
	left.add_child(HSeparator.new())
	var s: Dictionary = sim.summary()
	left.add_child(_label("Your choices: %d policy, %d research, %d investment. Active play time %d min %d s." % [
		s.picks_by_type.policy, s.picks_by_type.research, s.picks_by_type.invest,
		int(active_ms / 60000.0), int(active_ms / 1000.0) % 60], 14, UITheme.TEXT, true))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var seed_value := sim.seed_value
	var again := _button("Replay this seed", "end_replay", func(): _start_run(seed_value, "replay"))
	row.add_child(again)
	row.add_child(_button("New run", "end_new_run", func(): _start_run(_random_seed(), "random")))
	row.add_child(_button("Title screen", "end_title", func(): _show_title()))
	left.add_child(row)

	var right := VBoxContainer.new()
	right.add_child(_label("How the world changed", 18, UITheme.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var series := {"population_m": [], "prosperity": [], "unrest": [], "jobs": [], "capability": [], "safety": []}
	for h in sim.history:
		for k in series:
			series[k].append(h[k] / 1000.0 if k == "population_m" else h[k])
	var specs := [["World population (B)", "population_m", "%.2f", Color("eef1f7")],
		["Prosperity (avg)", "prosperity", "%.0f", Color("e8c547")], ["Jobs (avg)", "jobs", "%.0f", Color("7ee08a")],
		["Unrest (avg)", "unrest", "%.0f", Color("ff8a7a")], ["AI capability", "capability", "%.0f", Color("6ec6ff")],
		["Safety", "safety", "%.0f", Color("d58cff")]]
	for sp in specs:
		var ch := MiniChart.new()
		ch.setup(sp[0], series[sp[1]], sp[2], sp[3])
		grid.add_child(ch)
	right.add_child(grid)
	hb.add_child(right)
	_set_screen("end", root)
	again.grab_focus.call_deferred()


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		last_input = "keyboard"
	elif event is InputEventMouseButton and event.pressed:
		last_input = "mouse"
	elif event is InputEventJoypadButton and event.pressed:
		last_input = "gamepad"


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.keycode
	if k == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		var ln := _layer_name()
		if ln == "pause":
			_set_paused(false, "esc")
		elif ln == "settings" or ln == "privacy":
			_back_from_layer("pause" if paused else "")
		elif current_screen == "game" and run_active:
			_set_paused(true, "esc")
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
		GameLog.warn("capture.save", {"msg": "no rendered image (headless?)"})
		return
	var path := dev_capture.path_join("%02d-%s.png" % [_captured.size(), name])
	var err := img.save_png(path)
	if err != OK:
		GameLog.error("capture.save", {"path": path, "err": err})
	else:
		GameLog.info("capture.save", {"path": path})
