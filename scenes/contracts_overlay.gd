extends OverlayBase
class_name ContractsOverlay

## Contracts (rail tile "Contracts"): both halves of a contract's life, in
## the "Operator Console" style of the user's mockup (assets/inspo/UI/
## contract_UI.png) built from UiKit widgets.
##
## Offers tab - a compact card per rolled-but-unaccepted offer (part-family
## icon, customer, tier pill, payout, time, familiarity meter, risk pill).
## Tapping a card expands a detail card directly beneath it (accordion; one
## open at a time): each line item's part type, quantity, familiarity, alloy
## and per-part payment, the payment split, and Accept. A tap is a press and
## release that moves less than ROW_TAP_MOVE_THRESHOLD - a drag scrolls.
##
## Active tab - reputation and revert metal, the Queue amount (x1/x5/x10/MAX,
## AdVenture Capitalist style) and Trial metal (Revert/Virgin) toggles, then a
## card per active contract: an On track / Behind / Overdue pill, progress
## bar, its Engineer (tap to cycle), and per line item a familiarity meter
## and Trial / Production queue buttons (Production locked below 85%).
##
## Both tabs keep persistent cards updated in place on the 0.25s poll -
## rebuilding would make the list jump (CLAUDE.md UI rule 5).

const REFRESH_INTERVAL: float = 0.25
const QUEUE_AMOUNTS: Array[int] = [1, 5, 10, 0]   # 0 = MAX
const QUEUE_MAX_WANTED: int = 9999
## Press-to-release movement under this is a tap; more is a scroll drag.
const ROW_TAP_MOVE_THRESHOLD: float = 24.0
const TAB_OFFERS := 0
const TAB_ACTIVE := 1

@onready var tabs: TabContainer = $Panel/TabContainer
@onready var contracts_list: VBoxContainer = %ContractsList
@onready var offers_root: VBoxContainer = %OffersRoot

var _refresh_elapsed: float = 0.0


func _on_ready() -> void:
	GameData.contract_updated.connect(func(_c): _on_data_changed())
	GameData.contract_offers_changed.connect(func(): _on_data_changed())
	_build_offers_header()
	_build_offer_detail()
	_build_active_header()


func _process(delta: float) -> void:
	if not panel.visible:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed < REFRESH_INTERVAL or _click_in_progress():
		return
	_refresh_elapsed = 0.0
	_refresh()


func _on_open() -> void:
	_refresh_elapsed = 0.0
	_refresh()


func _on_data_changed() -> void:
	if panel.visible and not _click_in_progress():
		_refresh()


func _refresh() -> void:
	_refresh_offers_tab()
	_refresh_contracts_tab()
	tabs.set_tab_title(TAB_OFFERS, "Offers (%d)" % GameData.contract_offers.size())
	tabs.set_tab_title(TAB_ACTIVE, "Active (%d)" % GameData.get_active_contracts().size())


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]


func _tier_pill_text(contract: Contract) -> String:
	return "T%d" % int(contract.tier) # ContractTier is 1-based


## Familiarity colors: green once production unlocks, gold in between, red low.
func _familiarity_color(percent: float) -> String:
	if percent >= GameData.PRODUCTION_FAMILIARITY_PERCENT:
		return "good"
	if percent >= 40.0:
		return "gold"
	return "bad"


func _offer_familiarity_percent(offer: Contract) -> float:
	if offer.line_items.is_empty():
		return 0.0
	var total := 0.0
	for li in offer.line_items:
		total += GameData.geometry_familiarity_percent(li.geometry_name)
	return total / offer.line_items.size()


## Risk comes from the WEAKEST line item, so one hard part can't hide behind
## easy ones on the same order.
func _offer_risk(offer: Contract) -> Array:
	var weakest := 100.0
	for li in offer.line_items:
		weakest = minf(weakest, GameData.geometry_familiarity_percent(li.geometry_name))
	if weakest >= 80.0:
		return ["Low", "good"]
	if weakest >= 40.0:
		return ["Med", "warn"]
	return ["High", "bad"]


func _offer_icon(offer: Contract) -> String:
	return UiKit.part_icon(offer.line_items[0].geometry_name) if not offer.line_items.is_empty() else "contracts"


# ---------------------------------------------------------------------------
# Offers tab
# ---------------------------------------------------------------------------

class OfferRow:
	var box: PanelContainer
	var icon: TextureRect
	var customer: Label
	var tier_label: Label
	var tier_pill: PanelContainer
	var payout: Label
	var time: Label
	var familiarity: SegMeter
	var risk: PanelContainer
	var chevron: Label
	var offer: Contract = null
	var press_position: Vector2 = Vector2.ZERO

var _offer_rows: Dictionary = {} # contract_id -> OfferRow
var _offers_empty_label: Label = null
var _selected_offer_id: int = -1

var _detail: PanelContainer = null
var _detail_title: Label
var _detail_meta: Label
var _detail_risk: PanelContainer
var _detail_items: VBoxContainer
var _detail_payment: Label


func _build_offers_header() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	for spec in [["Customer", 0, true], ["Tier", 18, false], ["Payout", 38, false], ["Time", 40, false], ["Familiar", 46, false], ["Risk", 30, false]]:
		var l := UiKit.label(spec[0], UiKit.FONT_SMALL, "text_dim")
		if spec[2]:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.custom_minimum_size = Vector2(spec[1], 0)
		header.add_child(l)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(8, 0)
	header.add_child(spacer)
	offers_root.add_child(header)


func _refresh_offers_tab() -> void:
	var offer_ids: Dictionary = {}
	for o in GameData.contract_offers:
		offer_ids[o.contract_id] = true
	for cid in _offer_rows.keys().duplicate():
		if not offer_ids.has(cid):
			MenuLayout.remove_and_free(_offer_rows[cid].box)
			_offer_rows.erase(cid)
			if _selected_offer_id == cid:
				_selected_offer_id = -1

	if GameData.contract_offers.is_empty():
		if _offers_empty_label == null:
			_offers_empty_label = UiKit.label("No contract offers right now - new ones arrive shortly.", UiKit.FONT_BODY, "text_dim")
			_offers_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			offers_root.add_child(_offers_empty_label)
	elif _offers_empty_label != null:
		MenuLayout.remove_and_free(_offers_empty_label)
		_offers_empty_label = null

	for o in GameData.contract_offers:
		var row: OfferRow = _offer_rows.get(o.contract_id)
		if row == null:
			row = _create_offer_row()
			_offer_rows[o.contract_id] = row
			offers_root.add_child(row.box)
		_update_offer_row(row, o)

	_refresh_offer_detail()
	_place_detail()


func _create_offer_row() -> OfferRow:
	var row := OfferRow.new()
	row.box = UiKit.card()
	row.box.gui_input.connect(_on_offer_row_gui_input.bind(row))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.box.add_child(line)

	row.icon = UiKit.icon("contracts")
	line.add_child(row.icon)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(names)
	row.customer = UiKit.label("")
	row.customer.clip_text = true
	names.add_child(row.customer)
	row.tier_label = UiKit.label("", UiKit.FONT_SMALL, "text_dim")
	row.tier_label.clip_text = true
	names.add_child(row.tier_label)

	row.tier_pill = UiKit.pill("T1", "info")
	row.tier_pill.custom_minimum_size = Vector2(18, 0)
	row.tier_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(row.tier_pill)
	row.payout = UiKit.label("")
	row.payout.custom_minimum_size = Vector2(38, 0)
	row.payout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(row.payout)
	row.time = UiKit.label("")
	row.time.custom_minimum_size = Vector2(40, 0)
	row.time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(row.time)
	row.familiarity = UiKit.meter(0.0, "gold", 8)
	row.familiarity.custom_minimum_size.x = 46
	line.add_child(row.familiarity)
	row.risk = UiKit.pill("Low", "good")
	row.risk.custom_minimum_size = Vector2(30, 0)
	row.risk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(row.risk)
	row.chevron = UiKit.label(">", UiKit.FONT_BODY, "header_text")
	row.chevron.custom_minimum_size = Vector2(8, 0)
	row.chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(row.chevron)
	return row


func _update_offer_row(row: OfferRow, offer: Contract) -> void:
	row.offer = offer
	row.icon.texture = UiIcons.get_icon(_offer_icon(offer))
	row.customer.text = offer.customer_name
	row.tier_label.text = offer.tier_label
	UiKit.set_pill(row.tier_pill, _tier_pill_text(offer), "info")
	row.payout.text = "%dg" % offer.payout
	row.time.text = _format_time(offer.deadline_seconds)
	var familiarity := _offer_familiarity_percent(offer)
	row.familiarity.value = familiarity / 100.0
	row.familiarity.color_key = _familiarity_color(familiarity)
	var risk := _offer_risk(offer)
	UiKit.set_pill(row.risk, risk[0], risk[1])
	var selected := offer.contract_id == _selected_offer_id
	row.chevron.text = "v" if selected else ">"
	UiKit.set_card_border(row.box, "gold" if selected else "card_border")


func _on_offer_row_gui_input(event: InputEvent, row: OfferRow) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		row.press_position = event.global_position
	elif event.global_position.distance_to(row.press_position) < ROW_TAP_MOVE_THRESHOLD:
		_selected_offer_id = -1 if _selected_offer_id == row.offer.contract_id else row.offer.contract_id
		_refresh_offers_tab.call_deferred()


func _build_offer_detail() -> void:
	_detail = UiKit.card("gold")
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	_detail.add_child(body)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	body.add_child(top)
	_detail_title = UiKit.label("", UiKit.FONT_TITLE, "header_text")
	_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_title.clip_text = true
	top.add_child(_detail_title)
	_detail_risk = UiKit.pill("Low", "good")
	_detail_risk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_detail_risk)
	_detail_meta = UiKit.label("", UiKit.FONT_SMALL, "text_dim")
	_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_detail_meta)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	body.add_child(header)
	for spec in [["Part type", 0, true], ["Qty", 22, false], ["Familiarity", 64, false], ["Alloy", 64, false], ["Each", 26, false]]:
		var l := UiKit.label(spec[0], UiKit.FONT_SMALL, "text_dim")
		if spec[2]:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.custom_minimum_size = Vector2(spec[1], 0)
		header.add_child(l)
	_detail_items = VBoxContainer.new()
	_detail_items.add_theme_constant_override("separation", 2)
	body.add_child(_detail_items)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	body.add_child(bottom)
	_detail_payment = UiKit.label("", UiKit.FONT_SMALL, "text")
	_detail_payment.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_payment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_detail_payment)
	var accept := UiKit.button("Accept", "st_check", "primary")
	accept.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	accept.pressed.connect(_on_accept_offer_pressed)
	bottom.add_child(accept)
	offers_root.add_child(_detail)


func _refresh_offer_detail() -> void:
	var offer := _find_offer(_selected_offer_id)
	_detail.visible = offer != null
	if offer == null:
		_selected_offer_id = -1
		return
	_detail_title.text = "%s" % offer.customer_name
	var risk := _offer_risk(offer)
	UiKit.set_pill(_detail_risk, "%s risk" % risk[0], risk[1])
	var exp: int = GameData.FACTORY_EXP_PER_CONTRACT_TIER.get(offer.tier, 0)
	_detail_meta.text = "%s  |  Payout %dg  |  %s to complete  |  +%d Factory EXP" % [
		offer.tier_label, offer.payout, _format_time(offer.deadline_seconds), exp]
	_detail_payment.text = "Pays %dg up front, %dg per good part shipped, +%dg if finished on time" % [
		GameData.contract_upfront_amount(offer), GameData.contract_per_part_amount(offer), GameData.contract_early_bonus(offer)]
	# The selected offer's items only change when the selection does.
	if _detail.get_meta("shown_offer", -1) != offer.contract_id:
		_detail.set_meta("shown_offer", offer.contract_id)
		MenuLayout.clear(_detail_items)
		for li in offer.line_items:
			_detail_items.add_child(_build_detail_item(li, offer))


func _build_detail_item(li: Contract.LineItem, offer: Contract) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(UiKit.icon(UiKit.part_icon(li.geometry_name)))
	var name := UiKit.label(li.geometry_name)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	row.add_child(name)
	var qty := UiKit.label("%d" % li.quantity_required)
	qty.custom_minimum_size = Vector2(22, 0)
	row.add_child(qty)
	var percent := GameData.geometry_familiarity_percent(li.geometry_name)
	var meter := UiKit.meter(percent / 100.0, _familiarity_color(percent), 8)
	meter.custom_minimum_size.x = 64
	row.add_child(meter)
	var alloy := UiKit.label(li.alloy_name, UiKit.FONT_SMALL, "text_dim")
	alloy.custom_minimum_size = Vector2(64, 0)
	alloy.clip_text = true
	row.add_child(alloy)
	var each := UiKit.label("%dg" % GameData.contract_per_part_amount(offer))
	each.custom_minimum_size = Vector2(26, 0)
	row.add_child(each)
	return row


## The detail card sits right under the selected offer's card. move_child's
## index is counted with the moved node already removed, hence skipping it.
func _place_detail() -> void:
	var selected: OfferRow = _offer_rows.get(_selected_offer_id)
	if selected == null:
		offers_root.move_child(_detail, offers_root.get_child_count() - 1)
		return
	var index := 0
	for child in offers_root.get_children():
		if child == _detail:
			continue
		if child == selected.box:
			break
		index += 1
	offers_root.move_child(_detail, index + 1)


func _on_accept_offer_pressed() -> void:
	var offer := _find_offer(_selected_offer_id)
	if offer == null:
		return
	GameData.accept_contract_offer(offer)
	_selected_offer_id = -1
	_refresh.call_deferred()


func _find_offer(contract_id: int) -> Contract:
	for o in GameData.contract_offers:
		if o.contract_id == contract_id:
			return o
	return null


# ---------------------------------------------------------------------------
# Active tab
# ---------------------------------------------------------------------------

class ContractRow:
	var box: PanelContainer
	var icon: TextureRect
	var customer: Label
	var tier_label: Label
	var tier_pill: PanelContainer
	var status_pill: PanelContainer
	var time: Label
	var progress_label: Label
	var relationship: Label
	var progress_bar: ProgressBar
	var engineer_button: Button
	var contract_id: int = -1
	## Per line item: {name, progress, percent, meter, alloy, trial, production}.
	var items: Array[Dictionary] = []

var _contract_rows: Dictionary = {} # contract_id -> ContractRow
var _contracts_empty_label: Label = null
var _reputation_label: Label
var _revert_label: Label
var _amount_buttons: Array[Button] = []
var _metal_buttons: Array[Button] = []
var _queue_amount_index: int = 0
## Pour trials in revert (cheap, uses revert stock) or virgin metal
## (production price, uses none - and each becomes revert when remelted).
var _trial_in_virgin: bool = false


func _queue_wanted() -> int:
	var amount := QUEUE_AMOUNTS[_queue_amount_index]
	return QUEUE_MAX_WANTED if amount == 0 else amount


func _build_active_header() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	contracts_list.add_child(top)
	top.add_child(UiKit.icon("reputation"))
	_reputation_label = UiKit.label("", UiKit.FONT_BODY)
	_reputation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reputation_label.clip_text = true
	_reputation_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_reputation_label)
	top.add_child(UiKit.icon("room_vim"))
	_revert_label = UiKit.label("", UiKit.FONT_BODY)
	_revert_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_revert_label.tooltip_text = UiText.tip("Revert is remelted metal. Trial parts are poured in it; every trial and every casting under 90% quality is remelted back into it.")
	_revert_label.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(_revert_label)

	# Segmented toggles - one fixed row (~290px at 12px text, inside the
	# ~356px list on every supported screen), so it never re-wraps.
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 2)
	contracts_list.add_child(toggles)
	var queue_caption := UiKit.label("Queue:", UiKit.FONT_SMALL, "text_dim")
	queue_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggles.add_child(queue_caption)
	for i in QUEUE_AMOUNTS.size():
		var amount := QUEUE_AMOUNTS[i]
		var b := UiKit.button("MAX" if amount == 0 else "x%d" % amount)
		b.custom_minimum_size = Vector2(26, 0)
		b.tooltip_text = UiText.tip("How many parts each Trial/Production button queues per tap")
		b.pressed.connect(func():
			_queue_amount_index = i
			_refresh_contracts_tab.call_deferred())
		toggles.add_child(b)
		_amount_buttons.append(b)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(6, 0)
	toggles.add_child(gap)
	var metal_caption := UiKit.label("Trial metal:", UiKit.FONT_SMALL, "text_dim")
	metal_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggles.add_child(metal_caption)
	for virgin in [false, true]:
		var b := UiKit.button("Virgin" if virgin else "Revert")
		b.tooltip_text = UiText.tip("Virgin: production price, uses no revert, and each trial becomes revert when remelted - a way to build revert up." if virgin else "Revert: cheap, uses one revert per trial part.")
		b.pressed.connect(func():
			_trial_in_virgin = virgin
			_refresh_contracts_tab.call_deferred())
		toggles.add_child(b)
		_metal_buttons.append(b)


func _refresh_contracts_tab() -> void:
	_reputation_label.text = _reputation_summary_text()
	_revert_label.text = "Revert: %d" % GameData.revert_stock
	for i in _amount_buttons.size():
		UiKit.set_button_kind(_amount_buttons[i], "primary" if i == _queue_amount_index else "neutral")
	for i in _metal_buttons.size():
		UiKit.set_button_kind(_metal_buttons[i], "primary" if (i == 1) == _trial_in_virgin else "neutral")

	var active := GameData.get_active_contracts()
	var active_ids: Dictionary = {}
	for c in active:
		active_ids[c.contract_id] = true
	for contract_id in _contract_rows.keys().duplicate():
		if not active_ids.has(contract_id):
			MenuLayout.remove_and_free(_contract_rows[contract_id].box)
			_contract_rows.erase(contract_id)

	if active.is_empty():
		if _contracts_empty_label == null:
			_contracts_empty_label = UiKit.label("No active contracts - accept one from Offers.", UiKit.FONT_BODY, "text_dim")
			_contracts_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			contracts_list.add_child(_contracts_empty_label)
		return
	if _contracts_empty_label != null:
		MenuLayout.remove_and_free(_contracts_empty_label)
		_contracts_empty_label = null

	for c in active:
		var row: ContractRow = _contract_rows.get(c.contract_id)
		if row == null:
			row = _create_contract_row(c)
			_contract_rows[c.contract_id] = row
			contracts_list.add_child(row.box)
		_update_contract_row(row, c)


func _create_contract_row(contract: Contract) -> ContractRow:
	var row := ContractRow.new()
	row.contract_id = contract.contract_id
	row.box = UiKit.card()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	row.box.add_child(body)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	body.add_child(head)
	row.icon = UiKit.icon(_offer_icon(contract))
	head.add_child(row.icon)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	row.customer = UiKit.label(contract.customer_name)
	row.customer.clip_text = true
	names.add_child(row.customer)
	row.tier_label = UiKit.label(contract.tier_label, UiKit.FONT_SMALL, "text_dim")
	row.tier_label.clip_text = true
	names.add_child(row.tier_label)
	row.tier_pill = UiKit.pill(_tier_pill_text(contract), "info")
	row.tier_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(row.tier_pill)
	row.status_pill = UiKit.pill("On track", "good")
	row.status_pill.custom_minimum_size = Vector2(46, 0)
	row.status_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(row.status_pill)
	var clock := UiKit.icon("st_clock")
	head.add_child(clock)
	row.time = UiKit.label("")
	row.time.custom_minimum_size = Vector2(42, 0)
	row.time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(row.time)

	var progress := HBoxContainer.new()
	progress.add_theme_constant_override("separation", 4)
	body.add_child(progress)
	row.progress_label = UiKit.label("", UiKit.FONT_SMALL)
	row.progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.progress_label.clip_text = true
	progress.add_child(row.progress_label)
	row.relationship = UiKit.label("", UiKit.FONT_SMALL, "text_dim")
	progress.add_child(row.relationship)
	row.progress_bar = UiKit.bar("good", 6)
	body.add_child(row.progress_bar)

	var engineer_line := HBoxContainer.new()
	engineer_line.add_theme_constant_override("separation", 4)
	body.add_child(engineer_line)
	engineer_line.add_child(UiKit.icon("role_engineer"))
	var engineer_caption := UiKit.label("Engineer:", UiKit.FONT_SMALL, "text_dim")
	engineer_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	engineer_line.add_child(engineer_caption)
	row.engineer_button = UiKit.button("")
	row.engineer_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.engineer_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.engineer_button.tooltip_text = UiText.tip("The Engineer who diagnoses this contract's defects and runs its trials. Tap to change.")
	row.engineer_button.pressed.connect(_on_engineer_pressed.bind(row))
	engineer_line.add_child(row.engineer_button)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	body.add_child(header)
	for spec in [["Part type", 0, true], ["Shipped", 44, false], ["Familiarity", 70, false], ["Alloy", 60, false]]:
		var l := UiKit.label(spec[0], UiKit.FONT_SMALL, "text_dim")
		if spec[2]:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.custom_minimum_size = Vector2(spec[1], 0)
		header.add_child(l)

	for i in contract.line_items.size():
		var li: Contract.LineItem = contract.line_items[i]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		body.add_child(line)
		line.add_child(UiKit.icon(UiKit.part_icon(li.geometry_name)))
		var name := UiKit.label(li.geometry_name)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.clip_text = true
		line.add_child(name)
		var shipped := UiKit.label("")
		shipped.custom_minimum_size = Vector2(44, 0)
		line.add_child(shipped)
		var percent := UiKit.label("", UiKit.FONT_SMALL)
		percent.custom_minimum_size = Vector2(26, 0)
		line.add_child(percent)
		var meter := UiKit.meter(0.0, "gold", 8)
		line.add_child(meter)
		var alloy := UiKit.label(li.alloy_name, UiKit.FONT_SMALL, "text_dim")
		alloy.custom_minimum_size = Vector2(60, 0)
		alloy.clip_text = true
		line.add_child(alloy)
		# Button widths change with price/count - HFlowContainer (UI rule 2).
		var actions := HFlowContainer.new()
		actions.add_theme_constant_override("h_separation", 3)
		actions.alignment = FlowContainer.ALIGNMENT_END
		body.add_child(actions)
		var trial := UiKit.button("", "act_queue")
		trial.pressed.connect(_on_queue_pressed.bind(row, i, true))
		actions.add_child(trial)
		var production := UiKit.button("", "act_lock", "primary")
		production.pressed.connect(_on_queue_pressed.bind(row, i, false))
		actions.add_child(production)
		row.items.append({"shipped": shipped, "percent": percent, "meter": meter, "trial": trial, "production": production})
	return row


func _update_contract_row(row: ContractRow, contract: Contract) -> void:
	row.time.text = _format_time(contract.time_remaining)
	var status := _contract_status(contract)
	UiKit.set_pill(row.status_pill, status[0], status[1])
	var in_pipeline := GameData.count_parts_in_pipeline(contract.contract_id)
	var fraction := float(contract.quantity_shipped) / maxf(contract.quantity_required, 1.0)
	row.progress_label.text = "%d/%d shipped (%d%%)  -  %d in production" % [
		contract.quantity_shipped, contract.quantity_required, roundi(fraction * 100.0), in_pipeline]
	row.relationship.text = "%d/5 rel." % roundi(GameData.relationship_stars_for(contract.customer_name))
	row.progress_bar.value = fraction
	UiKit.set_bar_color(row.progress_bar, status[1])

	var engineer := GameData.engineer_for_contract(contract.contract_id)
	if engineer != null:
		row.engineer_button.text = engineer.technician_name
		UiKit.set_button_kind(row.engineer_button, "neutral")
	elif GameData.engineers().is_empty():
		row.engineer_button.text = "None - hire one in Team"
		UiKit.set_button_kind(row.engineer_button, "neutral")
	else:
		row.engineer_button.text = "Assign an Engineer"
		UiKit.set_button_kind(row.engineer_button, "warn")
	row.engineer_button.disabled = GameData.engineers().is_empty()

	for i in row.items.size():
		var w: Dictionary = row.items[i]
		var li: Contract.LineItem = contract.line_items[i]
		var percent := GameData.geometry_familiarity_percent(li.geometry_name)
		w.shipped.text = "%d/%d" % [li.quantity_shipped, li.quantity_required]
		w.percent.text = "%d%%" % roundi(percent)
		w.meter.value = percent / 100.0
		w.meter.color_key = _familiarity_color(percent)
		_update_queue_button(w.trial, contract, i, true, "Trial",
			"Poured in revert - never shipped. Teaches the shop this part and carries your Engineer's latest fix.")
		_update_queue_button(w.production, contract, i, false, "Production",
			"Poured in virgin metal for the customer. Unlocks at %d%% familiarity; ships only at %d%%+ quality." % [
				int(GameData.PRODUCTION_FAMILIARITY_PERCENT), int(GameData.SHIP_QUALITY_THRESHOLD)])


## "On track" compares shipped-plus-half-of-in-production against the share
## of the deadline used; overdue is its own state.
func _contract_status(contract: Contract) -> Array:
	if contract.is_overdue:
		return ["Overdue", "bad"]
	var done := (contract.quantity_shipped + 0.5 * GameData.count_parts_in_pipeline(contract.contract_id)) / maxf(contract.quantity_required, 1.0)
	var time_used := 1.0 - contract.time_remaining / maxf(contract.deadline_seconds, 1.0)
	if done + 0.1 >= time_used:
		return ["On track", "good"]
	return ["Behind", "warn"]


## Shows how many this tap will really queue at the current multiplier and
## the total price; a locked Production button keeps its lock icon.
func _update_queue_button(button: Button, contract: Contract, index: int, is_trial: bool, kind: String, about: String) -> void:
	var virgin := is_trial and _trial_in_virgin
	var blocker := GameData.print_order_blocker(contract, index, is_trial, virgin)
	var count := GameData.queueable_count(contract, index, is_trial, _queue_wanted(), virgin)
	var unit := GameData.part_cost_for(contract, is_trial, virgin)
	var locked := not is_trial and not GameData.can_run_production(contract.line_items[index].geometry_name)
	if count > 0:
		button.text = "%s x%d  %dg" % [kind, count, unit * count]
	else:
		button.text = "%s  %dg each" % [kind, unit]
	button.disabled = count == 0
	if not is_trial:
		button.icon = UiIcons.get_icon("act_lock" if locked else "act_start")
	button.tooltip_text = UiText.tip(about if blocker == "" else "%s\n%s" % [blocker, about])


func _on_queue_pressed(row: ContractRow, index: int, is_trial: bool) -> void:
	var contract := GameData.get_contract(row.contract_id)
	if contract != null:
		GameData.queue_print_orders(contract, index, is_trial, _queue_wanted(), is_trial and _trial_in_virgin)
	_refresh_contracts_tab.call_deferred()


func _on_engineer_pressed(row: ContractRow) -> void:
	var options: Array = [null]
	options.append_array(GameData.engineers())
	var current := GameData.engineer_for_contract(row.contract_id)
	var next: Technician = options[(options.find(current) + 1) % options.size()]
	GameData.assign_engineer_to_contract(row.contract_id, next)
	_refresh_contracts_tab.call_deferred()


## Next-tier-threshold text mirrors GameData.REPUTATION_TIER_THRESHOLD.
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
		return "Reputation %d - every tier unlocked" % reputation
	return "Reputation %d - %d more unlocks %s" % [reputation, next_gap - reputation, next_label]
