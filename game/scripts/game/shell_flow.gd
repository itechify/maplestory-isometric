class_name ShellFlow
extends RefCounted
## The game shell's screen-flow state machine (pure: no scene tree). The main scene (MainShell) fires events and
## shows the screen that belongs to the new state; tests drive it directly.
##
##   BOOT --boot--> TITLE --new_game--> CREATE --start--> LOADING --ready--> PLAYING
##                  TITLE --continue | load | start--> LOADING  CREATE --back--> TITLE   (start: quick start)
##   LOADING --failed--> TITLE
##   PLAYING --pause--> PAUSED --resume | load--> PLAYING      (load in the pause menu reloads in place)
##   PLAYING | PAUSED --died--> DEAD --respawned--> PLAYING
##   PLAYING | PAUSED --quit_to_title--> TITLE
##   any state --quit--> QUITTING
##
## Events not listed for the current state are refused (fire() returns false) and change nothing.

signal changed(new_state: State, old_state: State, event: String)
## An event was refused in the current state.
signal refused(event: String, state: State)

enum State { BOOT, TITLE, CREATE, LOADING, PLAYING, PAUSED, DEAD, QUITTING }

const EV_BOOT := "boot"
const EV_NEW_GAME := "new_game"
const EV_BACK := "back"
const EV_START := "start"
const EV_CONTINUE := "continue"
const EV_LOAD := "load"
const EV_READY := "ready"
const EV_FAILED := "failed"
const EV_PAUSE := "pause"
const EV_RESUME := "resume"
const EV_DIED := "died"
const EV_RESPAWNED := "respawned"
const EV_QUIT_TO_TITLE := "quit_to_title"
const EV_QUIT := "quit"

## state -> {event: next state}. EV_QUIT is accepted in every state but QUITTING (see can()).
const TRANSITIONS := {
	State.BOOT: {EV_BOOT: State.TITLE},
	State.TITLE: {EV_NEW_GAME: State.CREATE, EV_CONTINUE: State.LOADING, EV_LOAD: State.LOADING,
		EV_START: State.LOADING},
	State.CREATE: {EV_BACK: State.TITLE, EV_START: State.LOADING},
	State.LOADING: {EV_READY: State.PLAYING, EV_FAILED: State.TITLE},
	State.PLAYING: {EV_PAUSE: State.PAUSED, EV_DIED: State.DEAD, EV_QUIT_TO_TITLE: State.TITLE},
	State.PAUSED: {EV_RESUME: State.PLAYING, EV_LOAD: State.PLAYING, EV_DIED: State.DEAD,
		EV_QUIT_TO_TITLE: State.TITLE},
	State.DEAD: {EV_RESPAWNED: State.PLAYING},
	State.QUITTING: {},
}

var state: State = State.BOOT
## The last refused event ("" when the last fire() succeeded).
var last_refused: String = ""
## (event, from, to) of every accepted event, oldest first (for the checks and the debug overlay).
var history: Array[Dictionary] = []


## True when `event` is accepted in the current state.
func can(event: String) -> bool:
	if event == EV_QUIT:
		return state != State.QUITTING
	return (TRANSITIONS.get(state, {}) as Dictionary).has(event)


## The state `event` leads to from the current state, or -1 when it is refused.
func target(event: String) -> int:
	if not can(event):
		return -1
	if event == EV_QUIT:
		return State.QUITTING
	return int((TRANSITIONS[state] as Dictionary)[event])


## Applies `event`. Returns false (and changes nothing) when the current state does not accept it.
func fire(event: String) -> bool:
	var to := target(event)
	if to < 0:
		last_refused = event
		refused.emit(event, state)
		return false
	last_refused = ""
	var old := state
	state = to as State
	history.append({"event": event, "from": state_name(old), "to": state_name(state)})
	changed.emit(state, old, event)
	return true


func is_in(s: State) -> bool:
	return state == s


## True while a game session exists (loading, playing, paused or dead).
func in_game() -> bool:
	return state in [State.LOADING, State.PLAYING, State.PAUSED, State.DEAD]


static func state_name(s: int) -> String:
	return State.keys()[s] if s >= 0 and s < State.size() else "?"
