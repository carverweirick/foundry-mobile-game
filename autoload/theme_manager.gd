extends Node

## Small standalone settings/persistence layer for player-facing UI
## preferences - currently just which Theme resource is active (design doc
## Section 19's eventual Settings Menu; this is its first real setting,
## surfaced from the Settings overlay). Its own tiny user://settings.cfg
## rather than folded into GameData, since the game has no save/load system
## of its own yet and a UI preference like "which theme" shouldn't wait on
## one - it's a different kind of state than gameplay progress.
##
## Swapping only ever replaces the single project-wide Theme resource
## (project.godot's own gui/theme/custom sets the *initial* one before this
## autoload's _ready() runs; from then on this is the one source of truth).
## It deliberately does NOT touch the ~16 hardcoded per-node/per-script gold
## accent colors documented in ui_theme.tres's own header comment (header
## labels, risk badges, etc.) - those read the same gold literal under both
## themes, which is a fine match for either since gold/amber was already the
## accent color in the original parchment palette too, not just the dark one.

enum ThemeChoice { DARK, PARCHMENT }

const THEME_PATHS := {
	ThemeChoice.DARK: "res://resources/theme/ui_theme.tres",
	ThemeChoice.PARCHMENT: "res://resources/theme/ui_theme_parchment.tres",
}

const THEME_DISPLAY_NAMES := {
	ThemeChoice.DARK: "Dark Industrial",
	ThemeChoice.PARCHMENT: "Parchment",
}

const SETTINGS_PATH := "user://settings.cfg"

signal theme_changed(theme_choice: ThemeChoice)

var current_theme: ThemeChoice = ThemeChoice.DARK


func _ready() -> void:
	_load_settings()
	_apply_theme()


func set_theme(choice: ThemeChoice) -> void:
	if choice == current_theme:
		return
	current_theme = choice
	_apply_theme()
	_save_settings()
	theme_changed.emit(current_theme)


func _apply_theme() -> void:
	get_tree().root.theme = load(THEME_PATHS[current_theme])


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var saved: int = config.get_value("ui", "theme", ThemeChoice.DARK)
	if THEME_PATHS.has(saved):
		current_theme = saved


func _save_settings() -> void:
	# Load-then-set-then-save (rather than always writing a fresh file) so any
	# other future settings key in this same file survives untouched.
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("ui", "theme", current_theme)
	config.save(SETTINGS_PATH)
