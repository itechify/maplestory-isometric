class_name ScriptErrorGuard
extends Logger
## Records the GDScript runtime errors raised while it is attached.
##
## In Godot 4.7 a runtime error does not stop the program. It aborts only the current function, which returns its
## default value (null, 0, false), and the caller carries on. Inside the validator, one such error silently skips the
## rest of a check, so the report would look clean (fewer errors, a missing stat) and the run would "pass". The tool
## (tools/validate_data.gd) and the validation tests attach this guard around DataValidator.validate() and treat any
## recorded script error as a crashed validator: exit 2, or a failing test.
##
##   var guard := ScriptErrorGuard.new()
##   guard.attach()
##   var report := DataValidator.validate(db)
##   guard.detach()
##   if guard.count() > 0: ...   # the report is incomplete
##
## Only ERROR_TYPE_SCRIPT counts. Engine errors (ERR_FAIL_* in built-in methods, push_error) do not abort GDScript,
## and some are expected while validating broken data (e.g. JSON parse errors). Logger callbacks may come from any
## thread, so the list is guarded by a mutex.

var _mutex := Mutex.new()
var _errors: PackedStringArray = []
var _attached := false


## Starts recording (OS.add_logger). Calling it twice is harmless.
func attach() -> void:
	if _attached:
		return
	_attached = true
	OS.add_logger(self)


## Stops recording (OS.remove_logger). Calling it twice is harmless.
func detach() -> void:
	if not _attached:
		return
	_attached = false
	OS.remove_logger(self)


## True while attached.
func is_attached() -> bool:
	return _attached


## The recorded script errors, one line each: "<file>:<line> in <function>: <message>".
func errors() -> PackedStringArray:
	_mutex.lock()
	var out := _errors.duplicate()
	_mutex.unlock()
	return out


## How many script errors were recorded.
func count() -> int:
	_mutex.lock()
	var n := _errors.size()
	_mutex.unlock()
	return n


## Forgets the recorded errors.
func clear() -> void:
	_mutex.lock()
	_errors.clear()
	_mutex.unlock()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
		error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type != Logger.ERROR_TYPE_SCRIPT:
		return
	var message := code if rationale == "" else "%s (%s)" % [code, rationale]
	_mutex.lock()
	_errors.append("%s:%d in %s: %s" % [file, line, function, message])
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass
