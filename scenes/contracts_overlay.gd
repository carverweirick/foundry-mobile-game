extends OverlayBase
class_name ContractsOverlay

## Standalone entry point (design request, this session: split each of the
## old Menu overlay's three tabs into its own clearly separated HUD button).
## Content and refresh logic are otherwise unchanged from the old
## MenuOverlay's Contracts tab.
##
## One row per active contract: customer, quantity required, quantity
## shipped, quantity currently somewhere in the pipeline assigned to it, and
## time left on the deadline (design doc Section 6), plus the per-company
## Relationship column and shop-wide Reputation summary added in a later
## session (design doc Section 8).

const REFRESH_INTERVAL: float = 0.25

@onready var contracts_list: VBoxContainer = %ContractsList

var _refresh_elapsed: float = 0.0


func _on_ready() -> void:
	GameData.contract_updated.connect(func(_c): _on_contract_updated())


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


func _on_contract_updated() -> void:
	if not _click_in_progress():
		_refresh()


func _refresh() -> void:
	_refresh_contracts_tab()


## Persistent per-contract row - real Customer/Relationship/Progress/Time
## columns instead of one run-on text string. Contracts are few and rarely
## change structurally (only when one completes), so this is worth doing the
## same persistent-widget way as the Overview overlay's rows.
class ContractRow:
	var container: HBoxContainer
	var customer_label: Label
	var relationship_label: Label
	var progress_label: Label
	var time_label: Label

var _contract_rows: Dictionary = {} # contract_id -> ContractRow
var _contracts_empty_label: Label = null

## Persistent shop-wide summary line, always the first child of
## contracts_list (design doc Section 8's Reputation gating) - same
## persistent-widget-updated-in-place pattern as every row below, kept
## separate from the HUD's own ReputationLabel since this one also surfaces
## the next tier threshold, which the HUD doesn't have room for.
var _reputation_header_label: Label = null

func _refresh_contracts_tab() -> void:
	if _reputation_header_label == null:
		_reputation_header_label = Label.new()
		_reputation_header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		contracts_list.add_child(_reputation_header_label)
	_reputation_header_label.text = _reputation_summary_text()
	contracts_list.move_child(_reputation_header_label, 0)

	var active := GameData.get_active_contracts()
	var active_ids: Dictionary = {}
	for c in active:
		active_ids[c.contract_id] = true

	for contract_id in _contract_rows.keys().duplicate():
		if not active_ids.has(contract_id):
			var stale_row: ContractRow = _contract_rows[contract_id]
			stale_row.container.queue_free()
			_contract_rows.erase(contract_id)

	if active.is_empty():
		if _contracts_empty_label == null:
			_contracts_empty_label = Label.new()
			_contracts_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_contracts_empty_label.text = "No active contracts."
			contracts_list.add_child(_contracts_empty_label)
		return
	if _contracts_empty_label != null:
		_contracts_empty_label.queue_free()
		_contracts_empty_label = null

	for c in active:
		var row: ContractRow = _contract_rows.get(c.contract_id)
		if row == null:
			row = _create_contract_row()
			_contract_rows[c.contract_id] = row
			contracts_list.add_child(row.container)
		var in_pipeline := GameData.count_parts_in_pipeline(c.contract_id)
		var relationship := GameData.relationship_stars_for(c.customer_name)
		row.customer_label.text = "%s (%s)" % [c.customer_name, c.tier_label]
		row.relationship_label.text = "%d/5 rel." % int(round(relationship))
		row.progress_label.text = "%d/%d shipped (%d in pipe)" % [c.quantity_shipped, c.quantity_required, in_pipeline]
		row.time_label.text = "%s left" % _format_time(c.time_remaining)


## Next-tier-threshold text mirrors GameData.REPUTATION_TIER_THRESHOLD
## directly rather than duplicating the numbers here, so this stays correct
## if those constants are ever retuned.
func _reputation_summary_text() -> String:
	var reputation := GameData.reputation
	var next_label := ""
	var next_gap := -1
	for tier in GameData.REPUTATION_TIER_THRESHOLD.keys():
		var threshold: int = GameData.REPUTATION_TIER_THRESHOLD[tier]
		if threshold > reputation and (next_gap < 0 or threshold < next_gap):
			next_gap = threshold
			next_label = Contract.TIER_LABEL[tier]
	if next_label == "":
		return "Shop Reputation: %d/%d (every contract tier unlocked)" % [reputation, GameData.REPUTATION_MAX]
	return "Shop Reputation: %d/%d (%d more unlocks %s)" % [reputation, GameData.REPUTATION_MAX, next_gap - reputation, next_label]


func _create_contract_row() -> ContractRow:
	var row := ContractRow.new()
	row.container = HBoxContainer.new()

	row.customer_label = Label.new()
	row.customer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.customer_label.custom_minimum_size = Vector2(120.0, 40.0)
	row.container.add_child(row.customer_label)

	row.relationship_label = Label.new()
	row.relationship_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.relationship_label.custom_minimum_size = Vector2(70.0, 40.0)
	row.container.add_child(row.relationship_label)

	row.progress_label = Label.new()
	row.progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.progress_label.custom_minimum_size = Vector2(130.0, 0.0)
	row.container.add_child(row.progress_label)

	row.time_label = Label.new()
	row.time_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.time_label.custom_minimum_size = Vector2(90.0, 0.0)
	row.container.add_child(row.time_label)

	return row


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]
