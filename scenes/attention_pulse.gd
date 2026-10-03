extends Node2D
class_name AttentionPulse

## A gold outline that blinks a few times around a station and then frees
## itself - added by main.gd when the Attention button pans the camera to a
## station, so the eye lands on the right one in a crowded room.

const COLOR := Color(0.95, 0.72, 0.2)
const LINE_WIDTH: float = 4.0
const PULSES: int = 3
const PULSE_SECONDS: float = 0.35

var rect: Rect2


## Adds a pulse as a child of station, outlining rect (station-local).
static func spawn(station: Node2D, outline: Rect2) -> void:
	var pulse := AttentionPulse.new()
	pulse.rect = outline
	pulse.z_index = 10
	station.add_child(pulse)


func _ready() -> void:
	var tween := create_tween()
	for i in PULSES:
		tween.tween_property(self, "modulate:a", 0.15, PULSE_SECONDS)
		tween.tween_property(self, "modulate:a", 1.0, PULSE_SECONDS)
	tween.tween_callback(queue_free)


func _draw() -> void:
	draw_rect(rect, COLOR, false, LINE_WIDTH)
