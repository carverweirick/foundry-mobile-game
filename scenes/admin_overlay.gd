extends OverlayBase
class_name AdminOverlay

## Test/admin controls (user request, 2026-10-03: "a slider I can use to
## speed up the game so I can test easier... think about some nice admin
## controls"). Opened from the wrench in the Hud's top bar, which only exists
## in debug builds (OS.is_debug_build()) - an exported release never shows
## it. Everything here calls a GameData.debug_* helper or a normal public
## API, so a cheat never bypasses the signals the HUD and menus listen to.

const HEADER_COLOR := Color(0.85, 0.64, 0.16)
## Slider stops - indices, not a continuous range, so a thumb lands on a
## useful value instead of 13.7x.
const SPEEDS: Array[float] = [0.0, 1.0, 2.0, 5.0, 10.0, 25.0, 50.0]
## A second tap within this window confirms "Delete save".
const RESET_CONFIRM_SECONDS: float = 3.0

@onready var content: VBoxContainer = %Content

var _speed_label: Label
var _speed_slider: HSlider
var _defect_button: Button
var _reset_button: Button
var _status_label: Label
var _reset_armed_until: float = -1.0


func _on_ready() -> void:
	_add_header("Game speed")
	_speed_label = Label.new()
	content.add_child(_speed_label)
	_speed_slider = HSlider.new()
	_speed_slider.min_value = 0
	_speed_slider.max_value = SPEEDS.size() - 1
	_speed_slider.step = 1
	_speed_slider.tick_count = SPEEDS.size()
	_speed_slider.ticks_on_borders = true
	_speed_slider.custom_minimum_size = Vector2(0.0, 24.0)
	_speed_slider.value_changed.connect(_on_speed_changed)
	content.add_child(_speed_slider)
	var speed_row := _add_button_row()
	for speed in [0.0, 1.0, 10.0, 50.0]:
		_add_button(speed_row, "Pause" if speed == 0.0 else "%dx" % int(speed), _set_speed.bind(speed))

	_add_header("Time")
	var time_row := _add_button_row()
	_add_button(time_row, "+1 min", _skip.bind(60.0))
	_add_button(time_row, "+10 min", _skip.bind(600.0))
	_add_button(time_row, "+1 hr", _skip.bind(3600.0))
	_add_button(time_row, "Finish runs", func():
		GameData.debug_finish_running_stations()
		_report("Every running station will finish on the next tick."))

	_add_header("Economy")
	var money_row := _add_button_row()
	_add_button(money_row, "+1000g", func(): GameData.debug_add_currency(1000); _report("+1000 gold"))
	_add_button(money_row, "+10 gems", func(): GameData.debug_add_gems(10); _report("+10 gems"))
	_add_button(money_row, "+10 rep", func(): GameData.debug_add_reputation(10); _report("+10 reputation"))
	_add_button(money_row, "EXP to level", func(): GameData.debug_exp_to_next_level(); _report("Enough EXP for the next factory level"))

	_add_header("Contracts and defects")
	var contract_row := _add_button_row()
	_add_button(contract_row, "Accept an offer", _accept_offer)
	_defect_button = _add_button(contract_row, "", _cycle_defect_mode)

	_add_header("Save")
	var save_row := _add_button_row()
	_add_button(save_row, "Save now", func(): _report("Saved." if SaveManager.save_game() else "Save failed."))
	_reset_button = _add_button(save_row, "Delete save", _on_reset_pressed)
	_reset_button.tooltip_text = UiText.tip("Deletes the save file and quits, so the next launch is a fresh game. Tap twice.")

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0.0, 26.0)
	content.add_child(_status_label)


func _on_open() -> void:
	_refresh()


func _process(_delta: float) -> void:
	if panel.visible:
		_refresh()


func _refresh() -> void:
	var index := SPEEDS.find(GameData.debug_sim_speed)
	if index >= 0 and int(_speed_slider.value) != index:
		_speed_slider.set_value_no_signal(index)
	_speed_label.text = "Paused" if GameData.debug_sim_speed == 0.0 else "%sx real time" % _format_speed(GameData.debug_sim_speed)
	match GameData.debug_defect_mode:
		GameData.DebugDefectMode.NORMAL:
			_defect_button.text = "Defects: normal"
		GameData.DebugDefectMode.FORCE_NEXT:
			_defect_button.text = "Defects: next run"
		GameData.DebugDefectMode.NONE:
			_defect_button.text = "Defects: off"
	var armed := Time.get_ticks_msec() / 1000.0 < _reset_armed_until
	_reset_button.text = "Tap again to delete" if armed else "Delete save"


func _add_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HEADER_COLOR)
	content.add_child(label)


## HFlowContainer so the row wraps instead of running off the panel
## (CLAUDE.md UI rule 2).
func _add_button_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	content.add_child(row)
	return row


func _add_button(row: HFlowContainer, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	row.add_child(button)
	return button


func _on_speed_changed(value: float) -> void:
	_set_speed(SPEEDS[clampi(int(value), 0, SPEEDS.size() - 1)])


func _set_speed(speed: float) -> void:
	GameData.debug_sim_speed = speed
	_refresh()


func _skip(seconds: float) -> void:
	GameData.debug_skip_ahead(seconds)
	_report("Skipped ahead %s." % ("1 hour" if seconds >= 3600.0 else "%d min" % int(seconds / 60.0)))


func _accept_offer() -> void:
	if GameData.contract_offers.is_empty():
		_report("No offers waiting.")
		return
	var offer: Contract = GameData.contract_offers[0]
	GameData.accept_contract_offer(offer)
	_report("Accepted %s." % offer.customer_name)


func _cycle_defect_mode() -> void:
	var next: int = (int(GameData.debug_defect_mode) + 1) % GameData.DebugDefectMode.size()
	GameData.debug_defect_mode = next as GameData.DebugDefectMode
	_refresh()


func _on_reset_pressed() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _reset_armed_until:
		_reset_armed_until = now + RESET_CONFIRM_SECONDS
		_refresh()
		return
	SaveManager.delete_save_and_quit()


func _report(text: String) -> void:
	_status_label.text = text


func _format_speed(speed: float) -> String:
	return str(int(speed)) if is_equal_approx(speed, roundf(speed)) else "%.1f" % speed
