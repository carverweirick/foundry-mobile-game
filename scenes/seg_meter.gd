extends Control
class_name SegMeter

## A segmented meter (the mockups' familiarity/busy bars): `segments`
## blocks, filled up to `value` (0-1) in color_key, the rest in the track
## color. Built via UiKit.meter(); colors follow the current theme.

@export var segments: int = 8:
	set(v):
		segments = maxi(v, 1)
		update_minimum_size()
		queue_redraw()
@export var value: float = 0.0:
	set(v):
		var clamped := clampf(v, 0.0, 1.0)
		if not is_equal_approx(clamped, value):
			value = clamped
			queue_redraw()
var color_key: String = "gold":
	set(v):
		color_key = v
		queue_redraw()

const SEGMENT_WIDTH: float = 4.0
const GAP: float = 1.0
const HEIGHT: float = 7.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(UiKit.GROUP)


func _get_minimum_size() -> Vector2:
	return Vector2(segments * (SEGMENT_WIDTH + GAP) - GAP + 2.0, HEIGHT)


func _draw() -> void:
	var y := (size.y - HEIGHT) * 0.5
	draw_rect(Rect2(0, y, _get_minimum_size().x, HEIGHT), Color(0.03, 0.03, 0.03))
	var filled := roundi(value * segments)
	for i in segments:
		var r := Rect2(1.0 + i * (SEGMENT_WIDTH + GAP), y + 1.0, SEGMENT_WIDTH, HEIGHT - 2.0)
		draw_rect(r, UiKit.c(color_key) if i < filled else UiKit.c("track"))
