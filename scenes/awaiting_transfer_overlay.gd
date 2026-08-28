extends OverlayBase
class_name AwaitingTransferOverlay

## Standalone entry point (design request, this session: split each of the
## old Menu overlay's three tabs into its own clearly separated HUD button).
## Content and refresh logic are otherwise unchanged from the old
## MenuOverlay's Awaiting Transfer tab.
##
## Parts that have been manually collected off an unstaffed station and are
## now sitting in a holding inventory, waiting for a player decision on where
## they go next. A staffed station's technician collects and routes a Part in
## one motion the instant it's ready, so a staffed station's output never
## appears here - this tab is specifically the "only a human needs to deal
## with this" list.

const REFRESH_INTERVAL: float = 0.25

@onready var transfer_list: VBoxContainer = %TransferList
@onready var transfer_defects_only_check: CheckBox = %TransferDefectsOnlyCheck

## Set by main.gd right after every Station is spawned - needed to route a
## held Part to its next live Station.
var station_by_id: Dictionary = {}

var _refresh_elapsed: float = 0.0


func _on_ready() -> void:
	transfer_defects_only_check.toggled.connect(func(_p): _refresh.call_deferred())
	GameData.held_parts_changed.connect(_on_held_parts_changed)


func _process(delta: float) -> void:
	if not panel.visible:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed < REFRESH_INTERVAL:
		return
	if _click_in_progress():
		return
	_refresh_elapsed = 0.0
	_refresh()


func _on_open() -> void:
	_refresh_elapsed = 0.0
	_refresh()


## held_parts_changed used to call straight through to _refresh() - fine most
## of the time, but a rebuild triggered this way while the player is
## mid-click on some other button in this same list (e.g. tapping "Send to
## X" on one row while a different Part becomes held elsewhere) could still
## eat that click. Skipping here isn't a permanent miss either - the regular
## 0.25s poll above also refreshes this tab, so anything skipped here catches
## up within one poll cycle.
func _on_held_parts_changed() -> void:
	if not _click_in_progress():
		_refresh()


## Grouped by contract (a subheader per contract with held Parts, e.g. "Local
## Hardware Co. (3)"), a "Defects only" filter, and real Part#/Familiarity/
## Defect/Action columns instead of one run-on text string. Within each
## contract group, defective Parts sort first, then by part number, so
## anything needing attention isn't buried. Held Parts churn more than
## stations or contracts do, so unlike the Overview overlay this still does a
## full rebuild each refresh rather than persistent widgets - its actual
## *contents* genuinely change shape often enough that there's a real,
## unavoidable "reflow" most of the time anyway.
func _refresh() -> void:
	_clear_list(transfer_list)

	var defects_only := transfer_defects_only_check.button_pressed
	var by_contract: Dictionary = {} # contract_id -> Array[Part]
	for part in GameData.held_parts:
		if defects_only and not part.is_defective:
			continue
		if not by_contract.has(part.contract_id):
			by_contract[part.contract_id] = []
		(by_contract[part.contract_id] as Array).append(part)

	if by_contract.is_empty():
		var empty_label := Label.new()
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.text = "No defective parts awaiting transfer." if defects_only else "Nothing awaiting transfer."
		transfer_list.add_child(empty_label)
		return

	for contract_id in by_contract.keys():
		var parts: Array = by_contract[contract_id]
		parts.sort_custom(func(a: Part, b: Part) -> bool:
			if a.is_defective != b.is_defective:
				return a.is_defective
			return a.part_id < b.part_id
		)
		var contract := GameData.get_contract(contract_id)
		var header := Label.new()
		header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header.add_theme_color_override("font_color", Color(0.85, 0.64, 0.16))
		header.add_theme_font_size_override("font_size", 16)
		header.text = "%s (%d)" % [contract.customer_name if contract != null else "No Contract", parts.size()]
		transfer_list.add_child(header)

		for part in parts:
			_add_transfer_row(part)


func _add_transfer_row(part: Part) -> void:
	var row := HBoxContainer.new()
	transfer_list.add_child(row)

	var id_label := Label.new()
	id_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	id_label.custom_minimum_size = Vector2(45.0, 0.0)
	id_label.text = "#%d" % part.part_id
	row.add_child(id_label)

	var familiarity_label := Label.new()
	familiarity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	familiarity_label.custom_minimum_size = Vector2(40.0, 0.0)
	familiarity_label.text = "%d/5" % GameData.average_familiarity_stars(
		GameData.geometry_name_for_part(part)
	)
	row.add_child(familiarity_label)

	if part.is_defective:
		var defect_label := Label.new()
		defect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		defect_label.custom_minimum_size = Vector2(70.0, 0.0)
		defect_label.add_theme_color_override("font_color", Color(0.88, 0.35, 0.22))
		defect_label.text = GameData.DEFECT_CATEGORY_LABEL[part.defect_category]
		row.add_child(defect_label)

	var next_id := GameData.next_station_id_for(part)
	var next_station: Station = station_by_id.get(next_id)
	var send_button := Button.new()
	if next_station == null:
		send_button.text = "No next station"
		send_button.disabled = true
	else:
		send_button.text = "Send to %s" % next_station.station_name
		send_button.disabled = not next_station.can_accept_part()
		send_button.pressed.connect(_on_send_held_part.bind(part, next_station))
	row.add_child(send_button)


## Hands a held Part directly to a Station via the same receive_part() path a
## staffed technician or a manual Send-to-Next tap already uses, then drops
## it out of the holding inventory.
func _on_send_held_part(part: Part, target: Station) -> void:
	if not target.can_accept_part():
		_refresh() # station filled up since the tab was drawn; re-sync
		return
	GameData.release_held_part(part)
	target.receive_part(part)
	_refresh.call_deferred()


func _clear_list(list: VBoxContainer) -> void:
	for child in list.get_children():
		child.queue_free()
