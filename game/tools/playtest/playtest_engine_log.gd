class_name PlaytestEngineLog
extends Logger
## Records the engine errors and warnings a playtest run raises that are not GDScript runtime errors (push_error,
## push_warning, ERR_FAIL_* in built-in methods). The runner reports them as non-fatal "engine_errors"; GDScript runtime
## errors are ScriptErrorGuard's and fail the run. Logger callbacks may come from any thread (mutex).

## Entries kept at most (the rest are only counted).
const MAX_ENTRIES := 2000

var _mutex := Mutex.new()
var _entries: Array = []
var _dropped: int = 0
var _attached: bool = false


func attach() -> void:
	if not _attached:
		_attached = true
		OS.add_logger(self)


func detach() -> void:
	if _attached:
		_attached = false
		OS.remove_logger(self)


## Takes the entries recorded so far ({kind ("error" | "warning" | "shader"), message}) and forgets them.
func take() -> Array:
	_mutex.lock()
	var out := _entries
	if _dropped > 0:
		out.append({"kind": "warning", "message": "%d more engine errors/warnings not kept" % _dropped})
	_entries = []
	_dropped = 0
	_mutex.unlock()
	return out


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
		error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == Logger.ERROR_TYPE_SCRIPT:
		return
	var kind := "warning" if error_type == Logger.ERROR_TYPE_WARNING else ("shader" if error_type == Logger.ERROR_TYPE_SHADER else "error")
	var message := code if rationale == "" else "%s (%s)" % [code, rationale]
	_mutex.lock()
	if _entries.size() < MAX_ENTRIES:
		_entries.append({"kind": kind, "message": "%s:%d in %s: %s" % [file, line, function, message]})
	else:
		_dropped += 1
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass
