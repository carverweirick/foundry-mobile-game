extends Node

## Owns the save file itself, the autosave cadence, and offline catch-up.
## GameData owns "what my state is, as a Dictionary" (see its to_save_dict()/
## load_from_dict()); this file owns the disk, the clock, and the boot
## sequence. Split that way so GameData doesn't also grow file I/O, and so
## state can be round-tripped through a dict in a test without touching disk.
##
## Why this exists at all: before it, closing the app lost the entire shop -
## every contract, the roster, reputation, factory level, every in-flight Part.
## Nothing was persisted but the UI theme (ThemeManager's own settings.cfg,
## deliberately kept separate from this file - a display preference shouldn't
## be entangled with, or lost alongside, a gameplay save).
##
## Boot sequence, and why it's split across three calls rather than one
## (main.gd drives it, see its _ready()):
##   1. read_save_file()      - pulls the file off disk into _pending_save.
##      Has to happen before stations spawn, because owned_printer_count
##      lives in the save and decides how many printer instances main.gd
##      spawns in the first place.
##   2. apply_pending_save()  - hands the dict to GameData once station_by_id
##      is populated, so per-station state has live Stations to land on.
##   3. run_offline_catchup() - steps the sim forward by however long the
##      player was away.

const SAVE_PATH := "user://savegame.json"

## Seconds of real time between autosaves while playing. Frequent enough that
## a crash costs little, rare enough that the write itself is unnoticeable.
const AUTOSAVE_INTERVAL_SECONDS: float = 30.0

## Hard ceiling on how much time away is actually simulated, regardless of how
## long the player was really gone.
##
## This number matters more than it looks, and is the main tuning knob for how
## "idle" the game is. At the session-sim timescale
## (GameData.SECONDS_PER_GAME_MINUTE), one real hour is roughly 6 full
## passes of the pipeline - so an uncapped overnight absence would hand back
## hundreds of finished parts and trivialize the active game. Capped here
## instead: time away is a helpful head start, never the main way to progress.
## First-pass placeholder, same spirit as every other invented number in
## GameData - tune once the game has actually been played across real sessions.
const MAX_OFFLINE_CATCHUP_SECONDS: float = 3600.0

## Slice size the catch-up loop steps the sim with. Deliberately small: a
## technician walks at Technician.walk_speed() and stations sit
## hundreds of pixels apart, so a coarse slice would let them overshoot
## destinations and skip the arrival logic entirely. Small enough to stay
## faithful, large enough that a full catch-up is a few thousand steps rather
## than tens of thousands.
const CATCHUP_SLICE_SECONDS: float = 0.25

## Emitted after a catch-up actually ran, for a "here's what happened while you
## were away" summary. away_seconds is the real time gone (before capping);
## simulated_seconds is what was actually applied.
signal offline_catchup_finished(away_seconds: float, simulated_seconds: float, summary: Dictionary)

signal game_saved()
signal game_loaded()

var _pending_save: Dictionary = {}
var _autosave_elapsed: float = 0.0
## False until the boot sequence has run, so the autosave timer can't write an
## empty shop over a real save before main.gd has finished loading it.
var _ready_to_autosave: bool = false


func _process(delta: float) -> void:
	if not _ready_to_autosave:
		return
	_autosave_elapsed += delta
	if _autosave_elapsed >= AUTOSAVE_INTERVAL_SECONDS:
		_autosave_elapsed = 0.0
		save_game()


## Mobile backgrounding (NOTIFICATION_APPLICATION_PAUSED) is the one that
## actually matters on the target platform - on a phone the app is far more
## likely to be swiped away or backgrounded than cleanly quit, and the OS may
## kill it without any further warning. WM_CLOSE_REQUEST covers a desktop dev
## run closing the window.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			if _ready_to_autosave:
				save_game()


# --- boot sequence -------------------------------------------------------


## Step 1. Reads the file into memory without applying it. Returns true if
## there's a real save waiting.
func read_save_file() -> bool:
	_pending_save = {}
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Save file exists but couldn't be opened: %s" % FileAccess.get_open_error())
		return false
	var raw := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file isn't valid JSON - starting a fresh game rather than guessing.")
		return false

	_pending_save = parsed
	return true


## How many printers the pending save expects. main.gd needs this before it
## spawns anything, since printer instances are spawned per
## GameData.owned_printer_count and a Station can't be loaded into that doesn't
## exist yet. Falls back to whatever GameData already defaults to.
func pending_printer_count() -> int:
	return int(_pending_save.get("owned_printer_count", GameData.owned_printer_count))


func has_pending_save() -> bool:
	return not _pending_save.is_empty()


## Step 2. Applies the pending save to GameData. Call once station_by_id is
## populated. Returns false if there was nothing to apply or the file was
## rejected (e.g. a newer format version).
func apply_pending_save() -> bool:
	if _pending_save.is_empty():
		_ready_to_autosave = true
		return false
	var loaded := GameData.load_from_dict(_pending_save)
	_ready_to_autosave = true
	if loaded:
		game_loaded.emit()
	return loaded


## Step 3. Steps the simulation forward by however long the player was away,
## capped at MAX_OFFLINE_CATCHUP_SECONDS. No-op when there's no save, when the
## save predates this field, or when the clock says no meaningful time passed
## (including a negative delta - a device clock that moved backwards must never
## rewind the shop).
func run_offline_catchup() -> void:
	if _pending_save.is_empty():
		return
	var saved_at := float(_pending_save.get("saved_at_unix", 0.0))
	if saved_at <= 0.0:
		return

	var away := Time.get_unix_time_from_system() - saved_at
	if away < CATCHUP_SLICE_SECONDS:
		return

	var to_simulate: float = minf(away, MAX_OFFLINE_CATCHUP_SECONDS)
	var before := _progress_snapshot()

	# is_catching_up suppresses every Station's visual work for the duration -
	# there's nobody watching a timer bar that's about to be rewritten
	# thousands of times for a single visible frame - and stops GameData's own
	# _process() from double-stepping the sim on top of this loop.
	GameData.is_catching_up = true
	var remaining := to_simulate
	while remaining > 0.0:
		var slice: float = minf(CATCHUP_SLICE_SECONDS, remaining)
		GameData.simulate(slice)
		remaining -= slice
	GameData.is_catching_up = false

	var summary := _progress_delta(before)
	offline_catchup_finished.emit(away, to_simulate, summary)


## What changed across a catch-up, for the returning-player summary. Kept to
## things a player would actually want reported rather than every field that
## moved.
func _progress_snapshot() -> Dictionary:
	var shipped := 0
	for c in GameData.contracts:
		shipped += c.quantity_shipped
	return {
		"currency": GameData.currency,
		"reputation": GameData.reputation,
		"parts_shipped": shipped,
		"defects": GameData.count_unresolved_defects(),
	}


func _progress_delta(before: Dictionary) -> Dictionary:
	var after := _progress_snapshot()
	return {
		"currency_earned": after["currency"] - before["currency"],
		"reputation_change": after["reputation"] - before["reputation"],
		"parts_shipped": after["parts_shipped"] - before["parts_shipped"],
		"defects_now": after["defects"],
	}


# --- writing -------------------------------------------------------------


func save_game() -> bool:
	var data := GameData.to_save_dict()
	# Wall-clock stamp, deliberately NOT one of GameData's own accumulators:
	# this is the one place the game legitimately needs real-world time, to
	# measure how long the player was actually gone. Every in-game clock is an
	# accumulator precisely so it doesn't depend on this.
	data["saved_at_unix"] = Time.get_unix_time_from_system()

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Couldn't open save file for writing: %s" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	game_saved.emit()
	return true


## Admin overlay's "Delete save": wipes the save and quits WITHOUT the
## on-close autosave writing the current shop straight back, so the next
## launch is a genuinely fresh game. (GameData is an autoload, so reloading
## the scene alone would keep the old shop in memory.)
func delete_save_and_quit() -> void:
	_ready_to_autosave = false
	delete_save()
	get_tree().quit()


## Wipes the save. The Settings overlay's "reset save" option (design doc
## Section 19) would call this behind a confirmation step.
func delete_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	return err == OK
