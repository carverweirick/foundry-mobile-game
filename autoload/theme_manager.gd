extends Node

## Small standalone settings/persistence layer for player-facing UI
## preferences - currently just which Theme resource is active (design doc
## Section 19's eventual Settings Menu; this is its first real setting,
## surfaced from the Settings overlay). Its own tiny user://settings.cfg
## rather than folded into GameData, since the game has no save/load system
## of its own yet and a UI preference like "which theme" shouldn't wait on
## one - it's a different kind of state than gameplay progress.
##
## It deliberately does NOT touch the ~16 hardcoded per-node/per-script gold
## accent colors documented in ui_theme.tres's own header comment (header
## labels, risk badges, etc.) - those read the same gold literal under both
## themes, which is a fine match for either since gold/amber was already the
## accent color in the original parchment palette too, not just the dark one.
##
## Bug fix, confirmed with a real (non-headless) rendered run: a naive
## `get_tree().root.theme = new_theme` alone does NOT actually restyle
## anything in this project. project.godot's gui/theme/custom sets Godot's
## *project default theme* (ThemeDB.get_project_theme()) once at boot - a
## completely separate mechanism from Window.theme, with no runtime setter
## exposed to scripts. A Control only falls back to its nearest ancestor
## Window's .theme if it can reach that Window by walking actual Control
## ancestors (get_parent_control()); every overlay panel/button here is a
## direct child of a CanvasLayer (not a Control), which breaks that chain
## immediately - so every one of them was resolving straight to the frozen
## project default theme regardless of what Window.theme was reassigned to,
## confirmed by directly comparing a live Button's queried
## get_theme_stylebox() color against Window.theme's own resource_path
## across a real switch (they never matched). The actual fix: apply_theme_to()
## below sets .theme directly on each overlay's own top-level Panel/Button -
## once a Control's own .theme is set, it becomes the theme owner for its
## whole Control-descendant subtree, sidestepping the CanvasLayer break
## entirely. Every OverlayBase subclass, StationDetailMenu, and main.gd's HUD
## labels call this on their own top-level Controls, both once at startup and
## on every theme_changed.

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


## Kept as a harmless default-theme assignment (correct practice, and covers
## any future Control that's a genuine Control-ancestor descendant of the
## root rather than sitting under a CanvasLayer) - see this file's own header
## comment for why it alone is NOT sufficient for this project's actual
## overlay structure. apply_theme_to() below is what real callers need.
func _apply_theme() -> void:
	get_tree().root.theme = get_current_theme_resource()


func get_current_theme_resource() -> Theme:
	return load(THEME_PATHS[current_theme])


## Sets the currently-active Theme directly on one Control, making it the
## theme owner for its own Control-descendant subtree - the real mechanism
## that reaches every overlay's Panel/Button (see this file's header
## comment). Callers connect to theme_changed and call this again on switch.
func apply_theme_to(control: Control) -> void:
	control.theme = get_current_theme_resource()


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
