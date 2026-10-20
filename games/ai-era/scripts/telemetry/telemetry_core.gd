class_name TelemetryCore
extends RefCounted
## Behavioral analytics: builds structured events, appends them to a local JSONL file,
## and keeps an offline upload queue that a pluggable sink drains in batches.
## Nothing is recorded unless the player has opted in (consent == true).
## Schema: docs/EVENT_SCHEMA.md. Never put SteamID, names, or free text in props.

const LogCore := preload("res://scripts/core/game_log.gd")
const SCHEMA_VERSION := 1
const MAX_QUEUE := 5000
const MAX_ATTEMPTS := 5
const BASE_BACKOFF_SEC := 30.0
const MAX_BACKOFF_SEC := 600.0

var dir: String
var game_version: String
var build_type: String
var platform: String
var batch_size: int
var logger: LogCore

var enabled := false
var install_id := ""
var session_id := ""
var run_id := ""
var run_seed: Variant = null
var seq := 0

var queue: Array[String] = []
var inflight := 0
var attempts := 0
var offline_streak := 0
var next_attempt_at := 0.0 # unix seconds
var sent_total := 0
var dropped_total := 0
var last_status := 0


func _init(p_dir: String, p_log: LogCore, opts: Dictionary = {}) -> void:
	dir = p_dir
	logger = p_log
	game_version = opts.get("game_version", "0.0.0")
	build_type = opts.get("build_type", "debug")
	platform = opts.get("platform", OS.get_name())
	batch_size = opts.get("batch_size", 50)
	session_id = new_uuid()
	DirAccess.make_dir_recursive_absolute(dir)
	_load_queue()


static func new_uuid() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


func queue_path() -> String:
	return dir.path_join("queue.jsonl")


func events_path() -> String:
	var d := Time.get_date_dict_from_system(true)
	return dir.path_join("events-%04d-%02d-%02d.jsonl" % [d.year, d.month, d.day])


## Opt in with an install id (a random UUID owned by Settings).
func enable(p_install_id: String) -> void:
	enabled = true
	install_id = p_install_id


## Opt out: stop recording and delete everything recorded so far on this device.
func disable_and_purge() -> void:
	enabled = false
	install_id = ""
	queue.clear()
	inflight = 0
	var da := DirAccess.open(dir)
	if da:
		for f in da.get_files():
			if f.ends_with(".jsonl"):
				da.remove(f)


func begin_run(p_run_id: String, p_seed: int) -> void:
	run_id = p_run_id
	run_seed = p_seed


func end_run() -> void:
	run_id = ""
	run_seed = null


## Records one event. Returns the envelope, or {} when telemetry is off.
func track(event_name: String, props: Dictionary = {}) -> Dictionary:
	if not enabled:
		return {}
	seq += 1
	var now := Time.get_unix_time_from_system()
	var ev := {
		"schema": SCHEMA_VERSION,
		"event": event_name,
		"event_id": new_uuid(),
		"seq": seq,
		"ts": LogCore.iso_now(),
		"ts_ms": int(now * 1000.0),
		"install_id": install_id,
		"session_id": session_id,
		"run_id": run_id if run_id != "" else null,
		"seed": run_seed,
		"game_version": game_version,
		"build": build_type,
		"platform": platform,
		"props": props,
	}
	var line := JSON.stringify(ev)
	_append(events_path(), line)
	queue.append(line)
	if queue.size() > MAX_QUEUE:
		var over := queue.size() - MAX_QUEUE
		queue = queue.slice(over)
		inflight = maxi(0, inflight - over)
		dropped_total += over
		logger.warn("telemetry.queue", {"dropped_oldest": over, "cap": MAX_QUEUE})
	_append(queue_path(), line)
	return ev


func ready_to_flush(now: float) -> bool:
	return enabled and inflight == 0 and not queue.is_empty() and now >= next_attempt_at


## Starts sending the next batch. `sink.send(batch: Array, done: Callable)`;
## done(status: int) with status 0 meaning no connection.
func flush(sink, now: float = Time.get_unix_time_from_system()) -> bool:
	if not ready_to_flush(now):
		return false
	inflight = mini(batch_size, queue.size())
	var batch := []
	for i in inflight:
		batch.append(JSON.parse_string(queue[i]))
	sink.send(batch, _on_sent.bind(now))
	return true


func _on_sent(status: int, started_at: float) -> void:
	last_status = status
	var n := inflight
	inflight = 0
	if status >= 200 and status < 300:
		queue = queue.slice(n)
		_rewrite_queue()
		sent_total += n
		attempts = 0
		offline_streak = 0
		next_attempt_at = 0.0
		return
	if status == 0:
		offline_streak += 1
		next_attempt_at = started_at + minf(MAX_BACKOFF_SEC, BASE_BACKOFF_SEC * pow(2.0, offline_streak - 1))
		logger.warn("telemetry.send", {"status": 0, "queued": queue.size(), "msg": "offline, will retry"})
		return
	var retryable := status >= 500 or status == 408 or status == 429 or status == 401 or status == 403
	attempts += 1
	if retryable and attempts < MAX_ATTEMPTS:
		next_attempt_at = started_at + minf(MAX_BACKOFF_SEC, BASE_BACKOFF_SEC * pow(2.0, attempts - 1))
		logger.error("telemetry.send", {"status": status, "attempt": attempts, "batch": n, "msg": "upload failed, will retry"})
		return
	queue = queue.slice(n)
	_rewrite_queue()
	dropped_total += n
	attempts = 0
	next_attempt_at = 0.0
	logger.error("telemetry.send", {"status": status, "attempt": MAX_ATTEMPTS if retryable else 1, "batch": n,
		"dropped": true, "msg": "upload failed, batch dropped"})


func _append(p: String, line: String) -> void:
	var f := FileAccess.open(p, FileAccess.READ_WRITE if FileAccess.file_exists(p) else FileAccess.WRITE)
	if f == null:
		logger.error("telemetry.write", {"path": p, "err": FileAccess.get_open_error()})
		return
	f.seek_end()
	f.store_line(line)
	f.close()


func _rewrite_queue() -> void:
	var f := FileAccess.open(queue_path(), FileAccess.WRITE)
	if f == null:
		logger.error("telemetry.write", {"path": queue_path(), "err": FileAccess.get_open_error()})
		return
	for line in queue:
		f.store_line(line)
	f.close()


func _load_queue() -> void:
	queue.clear()
	if not FileAccess.file_exists(queue_path()):
		return
	var f := FileAccess.open(queue_path(), FileAccess.READ)
	while f and not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line != "":
			queue.append(line)
