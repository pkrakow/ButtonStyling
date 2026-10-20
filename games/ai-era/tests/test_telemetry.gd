extends "res://tests/test_case.gd"

const Core := preload("res://scripts/telemetry/telemetry_core.gd")
const LogCore := preload("res://scripts/core/game_log.gd")
const Sinks := preload("res://scripts/telemetry/sinks.gd")

const REQUIRED := ["schema", "event", "event_id", "seq", "ts", "ts_ms", "install_id", "session_id",
	"run_id", "seed", "game_version", "build", "platform", "props"]


func _make(name: String) -> Array:
	var d := tmp_dir(name)
	var lg = LogCore.new(d.path_join("test.log"))
	lg.echo = false
	var t = Core.new(d, lg, {"game_version": "9.9.9", "batch_size": 3})
	return [t, lg, d]


func _read_lines(path: String) -> Array:
	var out := []
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	while not f.eof_reached():
		var l := f.get_line()
		if l != "":
			out.append(l)
	return out


func test_off_by_default_records_nothing() -> void:
	var t = _make("off")[0]
	eq(t.track("app_start", {}), {}, "track must return {} without consent")
	eq(t.queue.size(), 0, "queue empty without consent")
	check(not FileAccess.file_exists(t.events_path()), "no local event file without consent")


func test_envelope_has_required_fields() -> void:
	var t = _make("env")[0]
	t.enable("install-abc")
	t.begin_run("run-1", 123)
	var ev: Dictionary = t.track("decision", {"options_shown": ["a", "b"], "chosen": "a", "decision_ms": 1500})
	for k in REQUIRED:
		check(ev.has(k), "missing field %s" % k)
	eq(ev.install_id, "install-abc", "install id")
	eq(ev.run_id, "run-1", "run id")
	eq(ev.seed, 123, "seed")
	eq(ev.game_version, "9.9.9", "game version")
	check(String(ev.ts).ends_with("Z"), "ts is UTC ISO-8601")
	eq(String(ev.event_id).length(), 36, "event id is a uuid")
	t.end_run()
	var ev2: Dictionary = t.track("app_exit", {})
	eq(ev2.run_id, null, "run id cleared after run")
	eq(ev2.seq, 2, "seq increments")


func test_jsonl_written_and_parseable() -> void:
	var t = _make("jsonl")[0]
	t.enable("i")
	for i in 5:
		t.track("ui_interaction", {"element": "btn_%d" % i, "action": "press"})
	var lines := _read_lines(t.events_path())
	eq(lines.size(), 5, "local jsonl lines")
	for l in lines:
		var obj = JSON.parse_string(l)
		check(obj is Dictionary and obj.event == "ui_interaction", "line parses as event")
	eq(_read_lines(t.queue_path()).size(), 5, "queue file mirrors events")


func test_batch_upload_success_drains_queue() -> void:
	var t = _make("drain")[0]
	t.enable("i")
	for i in 7:
		t.track("e", {})
	var sink = Sinks.MemorySink.new()
	check(t.flush(sink, 0.0), "first flush starts")
	eq(sink.batches[0].size(), 3, "batch size respected")
	t.flush(sink, 0.0)
	t.flush(sink, 0.0)
	eq(t.queue.size(), 0, "queue drained")
	eq(t.sent_total, 7, "all sent")
	eq(_read_lines(t.queue_path()).size(), 0, "queue file emptied")


func test_offline_keeps_queue_and_survives_restart() -> void:
	var made := _make("offline")
	var t = made[0]
	t.enable("i")
	for i in 4:
		t.track("e", {})
	var sink = Sinks.MemorySink.new()
	sink.status = 0
	t.flush(sink, 100.0)
	eq(t.queue.size(), 4, "offline keeps events")
	check(not t.ready_to_flush(101.0), "backoff after offline")
	check(t.ready_to_flush(100.0 + Core.BASE_BACKOFF_SEC), "retry after backoff")
	var t2 = Core.new(made[2], made[1], {"batch_size": 3})
	eq(t2.queue.size(), 4, "queue reloaded from disk on next launch")


func test_server_errors_retry_then_drop_with_grepable_error() -> void:
	var made := _make("5xx")
	var t = made[0]
	t.enable("i")
	t.track("e", {})
	var sink = Sinks.MemorySink.new()
	sink.status = 503
	var now := 0.0
	for i in Core.MAX_ATTEMPTS:
		check(t.flush(sink, now), "attempt %d starts" % (i + 1))
		now += Core.MAX_BACKOFF_SEC
	eq(t.queue.size(), 0, "batch dropped after max attempts")
	eq(t.dropped_total, 1, "drop counted")
	var log_lines := _read_lines(made[2].path_join("test.log"))
	var errors := log_lines.filter(func(l): return l.contains(" ERROR telemetry.send status=503"))
	eq(errors.size(), Core.MAX_ATTEMPTS, "one ERROR line per failed attempt")
	check(errors[-1].contains("dropped=true"), "final line marks the drop")


func test_client_error_dropped_immediately() -> void:
	var t = _make("4xx")[0]
	t.enable("i")
	t.track("e", {})
	var sink = Sinks.MemorySink.new()
	sink.status = 400
	t.flush(sink, 0.0)
	eq(t.queue.size(), 0, "400 is not retried")


func test_opt_out_purges_local_data() -> void:
	var t = _make("purge")[0]
	t.enable("i")
	t.track("e", {})
	t.disable_and_purge()
	eq(t.queue.size(), 0, "queue cleared")
	check(not FileAccess.file_exists(t.events_path()), "local events deleted")
	check(not FileAccess.file_exists(t.queue_path()), "queue file deleted")
	eq(t.track("e", {}), {}, "nothing recorded after opt-out")


func test_null_sink_is_noop_success() -> void:
	var t = _make("null")[0]
	t.enable("i")
	t.track("e", {})
	t.flush(Sinks.NullSink.new(), 0.0)
	eq(t.queue.size(), 0, "null sink acknowledges")
	eq(_read_lines(t.events_path()).size(), 1, "local jsonl kept")


func test_log_line_format() -> void:
	var line: String = LogCore.format_line("ERROR", "telemetry.send", {"status": 503, "msg": "server error"})
	var re := RegEx.create_from_string("^\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d\\.\\d{3}Z ERROR telemetry\\.send status=503 msg=\"server error\"$")
	check(re.search(line) != null, "unexpected log format: " + line)


func test_uuid_v4_format() -> void:
	var re := RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	for i in 20:
		check(re.search(Core.new_uuid()) != null, "bad uuid")


func test_per_run_id_scope_drops_install_and_session_ids() -> void:
	var made := _make("scope")
	var t = Core.new(made[2].path_join("run-scope"), made[1], {"id_scope": "run"})
	t.enable("install-abc")
	t.begin_run("run-1", 5)
	var ev: Dictionary = t.track("decision", {})
	eq(ev.install_id, null, "no install id in per-run scope")
	eq(ev.session_id, null, "no session id in per-run scope")
	eq(ev.run_id, "run-1", "run id kept")
	var t2 = _make("scope2")[0]
	t2.enable("install-abc")
	eq(t2.track("e", {}).install_id, "install-abc", "per-install is the default")
