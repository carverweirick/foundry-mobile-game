extends CanvasLayer
class_name OverlayBase

## Shared open/close/backdrop/toggle-button chrome for every top-level HUD
## overlay panel. Introduced this session when the entry-point split (one
## button per category instead of tabs bundled under one "Menu"/"Shop"
## button) took the overlay count from 3 to 6 - at that point hand-
## duplicating this exact boilerplate (toggle wiring, backdrop-click-to-
## close, the opened() signal, _click_in_progress()) in every single script
## stopped being "a few similar lines" and became a real risk that one copy
## would subtly drift from the others and reintroduce one of this project's
## already-fixed click-eating/UI-jumping races. Every subclass just needs
## %ToggleButton/%Backdrop/%Panel present in its own scene, and overrides
## _on_ready()/_on_open() instead of _ready()/part of _set_open() directly.
##
## StationDetailMenu deliberately does NOT use this base - it's opened via
## open_for(station) from a floor tap rather than its own persistent toggle
## button, so the toggle-button half of this shape doesn't apply to it; it
## keeps its own near-identical copy of the rest.
signal opened()

@onready var toggle_button: Button = %ToggleButton
@onready var backdrop: Control = %Backdrop
@onready var panel: Panel = %Panel


func _ready() -> void:
	toggle_button.pressed.connect(_on_toggle_pressed)
	backdrop.gui_input.connect(_on_backdrop_gui_input)
	_on_ready()


## Subclasses override this instead of _ready() directly, so the toggle/
## backdrop wiring above always happens no matter what a subclass adds.
func _on_ready() -> void:
	pass


func _on_toggle_pressed() -> void:
	_set_open(not panel.visible)


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_open(false)


## Public - called by main.gd's overlay-exclusivity wiring and its Escape
## handler, so any open overlay closes no matter which one it is.
func close() -> void:
	_set_open(false)


func _set_open(open: bool) -> void:
	panel.visible = open
	backdrop.visible = open
	if open:
		_on_open()
		opened.emit()


## Subclasses override this to reset their refresh timer and do a full
## refresh whenever they open - called before opened.emit() so content is
## already correct the instant the panel becomes visible.
func _on_open() -> void:
	pass


## Whether the mouse/touch button is currently held down anywhere - shared by
## every subclass's own refresh guard, so a poll or reactive signal handler
## never rebuilds a list out from under a button the player is mid-click on.
## See this project's earlier StationDetailMenu/ShopOverlay bug-fix history
## for the full rationale (a rebuild landing between a click's press and
## release silently eats it).
func _click_in_progress() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
