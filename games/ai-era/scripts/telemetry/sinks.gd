extends RefCounted
## Upload sinks for TelemetryCore. A sink implements send(batch: Array, done: Callable)
## and calls done(status_code) exactly once (0 = no connection).


## Default when no endpoint is configured: accepts everything, sends nothing.
## Events still land in the local JSONL file.
class NullSink:
	extends RefCounted
	func send(_batch: Array, done: Callable) -> void:
		done.call(204)


## Test double: records batches and replies with a scripted status.
class MemorySink:
	extends RefCounted
	var batches: Array = []
	var status := 200
	func send(batch: Array, done: Callable) -> void:
		batches.append(batch)
		done.call(status)


## POSTs {"schema": 1, "events": [...]} as JSON. Needs to live in the scene tree.
class HttpSink:
	extends Node
	var url: String
	var _http: HTTPRequest
	var _done: Callable

	func _init(p_url: String) -> void:
		url = p_url
		name = "HttpSink"

	func _ready() -> void:
		_http = HTTPRequest.new()
		_http.timeout = 15.0
		add_child(_http)
		_http.request_completed.connect(_on_completed)

	func send(batch: Array, done: Callable) -> void:
		_done = done
		var body := JSON.stringify({"schema": 1, "events": batch})
		var err := _http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
		if err != OK:
			_finish(0)

	func _on_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		_finish(code if result == HTTPRequest.RESULT_SUCCESS else 0)

	func _finish(code: int) -> void:
		var d := _done
		_done = Callable()
		if d.is_valid():
			d.call(code)
