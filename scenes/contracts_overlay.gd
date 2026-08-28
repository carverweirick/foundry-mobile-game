extends OverlayBase
class_name ContractsOverlay

## Entry point covering both halves of a contract's lifecycle: browsing and
## accepting new offers, and tracking work already accepted. Reworked this
## session (design doc Section 24.9, following a UI mockup the user liked
## and asked to have implemented) to add a real "Contract Offers" screen -
## previously a rolled contract went straight into the active/working list
## with no player choice at all (see GameData.contract_offers/
## accept_contract_offer()). Two tabs now instead of one flat list:
##
## - Offers: every contract GameData has rolled but the player hasn't
##   accepted yet. A compact row per offer (customer/payout/deadline/average
##   familiarity), and tapping "View" pins a full detail card below - line
##   items with per-geometry familiarity, a difficulty/alloy/volume tag row,
##   a familiarity-based risk badge, and an Accept button.
## - Active: the original read-only list of already-accepted contracts in
##   progress (customer/relationship/progress/time), unchanged from before
##   this session except for the rename.
##
## Deliberately kept as ONE overlay with two tabs rather than splitting
## "Offers" out to its own HUD button, unlike this session's earlier Menu/
## Shop split - these two tabs are the same underlying lifecycle object
## (an offer becomes an active contract), not "unrelated categories" bundled
## together for no reason, which was the specific complaint that split
## drove. The already-tight two-row, six-button HUD was also a real factor.

const REFRESH_INTERVAL: float = 0.25

@onready var contracts_list: VBoxContainer = %ContractsList
@onready var offers_root: VBoxContainer = %OffersRoot

var _refresh_elapsed: float = 0.0


func _on_ready() -> void:
	GameData.contract_updated.connect(func(_c): _on_contract_updated())
	GameData.contract_offers_changed.connect(func(): _on_offers_changed())
	_build_offer_detail_section()


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
		_refresh_contracts_tab()


func _on_offers_changed() -> void:
	if not _click_in_progress():
		_refresh_offers_tab()


func _refresh() -> void:
	_refresh_offers_tab()
	_refresh_contracts_tab()


# ---------------------------------------------------------------------------
# Offers tab (new this session)
# ---------------------------------------------------------------------------

## Persistent per-offer collapsed row - customer/payout/deadline/familiarity
## at a glance, same persistent-widget pattern as the Active tab's
## ContractRow below (built once, updated in place, never torn down except
## when the underlying offer itself is gone - accepted or, in the future,
## rerolled).
class OfferRow:
	var container: HBoxContainer
	var customer_label: Label
	var payout_label: Label
	var deadline_label: Label
	var familiarity_label: Label
	var select_button: Button
	var offer: Contract = null

var _offer_rows: Dictionary = {} # contract_id -> OfferRow
var _offers_empty_label: Label = null
var _selected_offer_id: int = -1

## The one detail section (not per-offer - there's only ever one selected
## offer at a time), built once in _on_ready() and always kept as the last
## child of offers_root regardless of how many offer rows come and go above
## it (see _refresh_offer_rows()'s move_child call).
var _detail_section: VBoxContainer = null
var _detail_empty_label: Label = null
var _detail_header_label: Label = null
var _detail_badge_label: Label = null
var _detail_info_label: Label = null
var _detail_line_items_header: Label = null
var _detail_line_items_list: VBoxContainer = null
var _detail_footer_label: Label = null
var _detail_accept_button: Button = null


func _refresh_offers_tab() -> void:
	_refresh_offer_rows()
	_refresh_offer_detail()


func _refresh_offer_rows() -> void:
	var offer_ids: Dictionary = {}
	for o in GameData.contract_offers:
		offer_ids[o.contract_id] = true

	for cid in _offer_rows.keys().duplicate():
		if not offer_ids.has(cid):
			var stale: OfferRow = _offer_rows[cid]
			stale.container.queue_free()
			_offer_rows.erase(cid)
			if _selected_offer_id == cid:
				_selected_offer_id = -1

	if GameData.contract_offers.is_empty():
		if _offers_empty_label == null:
			_offers_empty_label = Label.new()
			_offers_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_offers_empty_label.text = "No contract offers right now - check back shortly."
			offers_root.add_child(_offers_empty_label)
			offers_root.move_child(_offers_empty_label, 0)
	elif _offers_empty_label != null:
		_offers_empty_label.queue_free()
		_offers_empty_label = null

	for o in GameData.contract_offers:
		var row: OfferRow = _offer_rows.get(o.contract_id)
		if row == null:
			row = _create_offer_row()
			_offer_rows[o.contract_id] = row
			offers_root.add_child(row.container)
		_update_offer_row(row, o)

	# The detail section always renders last, no matter how many rows were
	# just added/removed above it.
	offers_root.move_child(_detail_section, offers_root.get_child_count() - 1)


func _create_offer_row() -> OfferRow:
	var row := OfferRow.new()
	row.container = HBoxContainer.new()

	row.customer_label = Label.new()
	row.customer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.customer_label.custom_minimum_size = Vector2(140.0, 24.0)
	row.container.add_child(row.customer_label)

	row.payout_label = Label.new()
	row.payout_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.payout_label.custom_minimum_size = Vector2(60.0, 24.0)
	row.container.add_child(row.payout_label)

	row.deadline_label = Label.new()
	row.deadline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.deadline_label.custom_minimum_size = Vector2(90.0, 24.0)
	row.container.add_child(row.deadline_label)

	row.familiarity_label = Label.new()
	row.familiarity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.familiarity_label.custom_minimum_size = Vector2(45.0, 24.0)
	row.container.add_child(row.familiarity_label)

	row.select_button = Button.new()
	row.select_button.text = "View"
	row.select_button.pressed.connect(_on_offer_row_selected.bind(row))
	row.container.add_child(row.select_button)

	return row


func _update_offer_row(row: OfferRow, offer: Contract) -> void:
	row.offer = offer
	row.customer_label.text = "%s (%s)" % [offer.customer_name, offer.tier_label]
	row.payout_label.text = "%dg" % offer.payout
	row.deadline_label.text = "%s to complete" % _format_time(offer.deadline_seconds)
	row.familiarity_label.text = "%d/5" % _offer_average_familiarity_stars(offer)


func _on_offer_row_selected(row: OfferRow) -> void:
	_selected_offer_id = row.offer.contract_id
	_refresh_offer_detail()


func _build_offer_detail_section() -> void:
	_detail_section = VBoxContainer.new()
	offers_root.add_child(_detail_section)
	_detail_section.add_child(HSeparator.new())

	_detail_empty_label = Label.new()
	_detail_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_empty_label.text = "Tap \"View\" on an offer above to see its full detail before accepting."
	_detail_section.add_child(_detail_empty_label)

	_detail_header_label = Label.new()
	_detail_header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_header_label.add_theme_font_size_override("font_size", 18)
	_detail_header_label.add_theme_color_override("font_color", Color(0.55, 0.2, 0.08))
	_detail_section.add_child(_detail_header_label)

	_detail_badge_label = Label.new()
	_detail_badge_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_section.add_child(_detail_badge_label)

	_detail_info_label = Label.new()
	_detail_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_section.add_child(_detail_info_label)

	_detail_line_items_header = Label.new()
	_detail_line_items_header.text = "Line Items:"
	_detail_line_items_header.add_theme_color_override("font_color", Color(0.55, 0.2, 0.08))
	_detail_section.add_child(_detail_line_items_header)

	_detail_line_items_list = VBoxContainer.new()
	_detail_section.add_child(_detail_line_items_list)

	_detail_footer_label = Label.new()
	_detail_footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_section.add_child(_detail_footer_label)

	_detail_accept_button = Button.new()
	_detail_accept_button.text = "Accept Contract"
	_detail_accept_button.pressed.connect(_on_accept_offer_pressed)
	_detail_section.add_child(_detail_accept_button)


func _refresh_offer_detail() -> void:
	var offer := _find_offer(_selected_offer_id)
	if offer == null:
		_selected_offer_id = -1
		_detail_empty_label.visible = true
		_detail_header_label.visible = false
		_detail_badge_label.visible = false
		_detail_info_label.visible = false
		_detail_line_items_header.visible = false
		_detail_line_items_list.visible = false
		_detail_footer_label.visible = false
		_detail_accept_button.visible = false
		return

	_detail_empty_label.visible = false
	_detail_header_label.visible = true
	_detail_badge_label.visible = true
	_detail_info_label.visible = true
	_detail_line_items_header.visible = true
	_detail_line_items_list.visible = true
	_detail_footer_label.visible = true
	_detail_accept_button.visible = true

	_detail_header_label.text = "%s - %s" % [offer.customer_name, offer.tier_label]

	var weakest_percent := _offer_weakest_familiarity_percent(offer)
	var badge_text: String
	var badge_color: Color
	var footer_text: String
	# Only ever two tags, both backed by real game state (familiarity/risk).
	# An earlier version also appended "BONUS QUALITY"/"FIRST ARTICLE" to the
	# safe/risky ends of this line - real manufacturing-sounding terms, but
	# neither tied to an actual mechanic (there's no quality-bonus system,
	# Section 24.2, or first-article-inspection step built), which is exactly
	# what surfaced as player confusion ("what does first article mean on the
	# contract?") - dropped rather than explained, since there was nothing
	# real behind them to explain.
	if weakest_percent >= 80:
		badge_text = "MASTERED - SAFE CONTRACT"
		badge_color = Color(0.25, 0.6, 0.3)
		footer_text = "HIGH FAMILIARITY • LOW RISK"
	elif weakest_percent >= 40:
		badge_text = "MODERATE RISK"
		badge_color = Color(0.75, 0.55, 0.15)
		footer_text = "MODERATE FAMILIARITY • MODERATE RISK"
	else:
		badge_text = "UNFAMILIAR - HIGH RISK"
		badge_color = Color(0.75, 0.25, 0.15)
		footer_text = "LOW FAMILIARITY • HIGH RISK"
	_detail_badge_label.text = badge_text
	_detail_badge_label.add_theme_color_override("font_color", badge_color)
	_detail_footer_label.text = footer_text
	_detail_footer_label.add_theme_color_override("font_color", badge_color)

	var alloy := offer.line_items[0].alloy_name if not offer.line_items.is_empty() else ""
	var exp: int = GameData.FACTORY_EXP_PER_CONTRACT_TIER.get(offer.tier, 0)
	_detail_info_label.text = "%s to complete  |  Payout %dg  |  +%d Factory EXP\n%s complexity • %s • Investment Casting • %s" % [
		_format_time(offer.deadline_seconds), offer.payout, exp,
		_offer_complexity_label(offer), alloy, _offer_volume_label(offer),
	]

	_clear_list(_detail_line_items_list)
	for li in offer.line_items:
		_detail_line_items_list.add_child(_build_line_item_row(li))


func _on_accept_offer_pressed() -> void:
	var offer := _find_offer(_selected_offer_id)
	if offer == null:
		return
	GameData.accept_contract_offer(offer)
	_selected_offer_id = -1
	_refresh_offers_tab.call_deferred()


func _find_offer(contract_id: int) -> Contract:
	for o in GameData.contract_offers:
		if o.contract_id == contract_id:
			return o
	return null


func _build_line_item_row(li: Contract.LineItem) -> Control:
	var row := HBoxContainer.new()

	row.add_child(_make_geometry_icon(li.geometry_name))

	var name_label := Label.new()
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(160.0, 0.0)
	name_label.text = "%s x%d" % [li.geometry_name, li.quantity_required]
	row.add_child(name_label)

	var familiarity_label := Label.new()
	familiarity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Same one-character-per-line wrap bug documented elsewhere in this
	# codebase (CLAUDE.md: "short inline labels next to a wide sibling
	# control could wrap vertically") - without an explicit minimum width,
	# this label had none of its own and got squeezed down to a sliver next
	# to name_label's wider fixed width, wrapping "0/5" onto three lines.
	familiarity_label.custom_minimum_size = Vector2(45.0, 24.0)
	familiarity_label.text = "%d/5" % GameData.average_familiarity_stars(li.geometry_name)
	row.add_child(familiarity_label)

	return row


## Placeholder geometry icon (design doc Section 24.3/24.11 - real per-
## geometry art is a future task, same "not built yet" gap as every other
## station's placeholder art). A small tinted bordered box (same shape
## language as Station._get_placeholder_texture()'s station placeholder,
## just built from Controls here instead of a generated Texture2D, since
## this only ever needs to be ~28x28 UI-space, not a world-space sprite)
## with a short abbreviation - tinted per geometry family
## (GameData.family_for_geometry()) so at least the FAMILY reads at a
## glance even before real art exists.
const FAMILY_ICON_COLOR := {
	"Decorative": Color(0.75, 0.65, 0.3),
	"Bracket": Color(0.55, 0.55, 0.6),
	"Valve": Color(0.35, 0.5, 0.65),
	"Housing": Color(0.5, 0.5, 0.55),
	"Seal": Color(0.45, 0.45, 0.5),
	"Impeller": Color(0.3, 0.55, 0.7),
	"Manifold": Color(0.5, 0.42, 0.32),
	"Strut": Color(0.4, 0.4, 0.45),
	"Turbine": Color(0.7, 0.32, 0.18),
	"HotSection": Color(0.75, 0.22, 0.15),
}

func _make_geometry_icon(geometry_name: String) -> Control:
	var family := GameData.family_for_geometry(geometry_name)
	var color: Color = FAMILY_ICON_COLOR.get(family, Color(0.5, 0.5, 0.5))

	var box := Panel.new()
	box.custom_minimum_size = Vector2(28.0, 28.0)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.15, 0.1, 0.05)
	style.anti_aliasing = false
	box.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = _abbreviation_for(geometry_name)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(label)

	return box


## "Turbine Blades" -> "TB", "Nozzle Guide Vanes" -> "NGV", "Blisks" -> "BL" -
## first letter of up to 3 words, or the first 2 letters of a single-word name.
func _abbreviation_for(geometry_name: String) -> String:
	var words := geometry_name.split(" ", false)
	if words.size() >= 2:
		var abbr := ""
		for w in words:
			if abbr.length() >= 3:
				break
			abbr += w.substr(0, 1)
		return abbr.to_upper()
	return geometry_name.substr(0, 2).to_upper()


func _offer_average_familiarity_stars(offer: Contract) -> int:
	if offer.line_items.is_empty():
		return 0
	var total := 0
	for li in offer.line_items:
		total += GameData.average_familiarity_stars(li.geometry_name)
	return int(round(float(total) / offer.line_items.size()))


func _offer_weakest_familiarity_percent(offer: Contract) -> int:
	var weakest := 100
	for li in offer.line_items:
		weakest = mini(weakest, GameData.weakest_familiarity_percent(li.geometry_name))
	return weakest


const COMPLEXITY_RANK := {"Low": 0, "Medium": 1, "High": 2, "Very High": 3}
const COMPLEXITY_BY_RANK: Array[String] = ["Low", "Medium", "High", "Very High"]

## The highest complexity among a multi-line-item offer's geometries -
## a contract asking for even one Very-High-complexity part is a Very-High-
## complexity contract overall, not averaged down by easier line items also
## on the same order.
func _offer_complexity_label(offer: Contract) -> String:
	var rank := 0
	for li in offer.line_items:
		var label: String = GameData.complexity_label_for_geometry(li.geometry_name)
		rank = maxi(rank, COMPLEXITY_RANK.get(label, 1))
	return COMPLEXITY_BY_RANK[rank]


func _offer_volume_label(offer: Contract) -> String:
	var range: Vector2i = GameData.CONTRACT_QUANTITY_RANGE[offer.tier]
	var total := offer.quantity_required
	var mid := (range.x + range.y) / 2.0
	if total >= mid * 1.3:
		return "High Volume"
	if total <= mid * 0.7:
		return "Low Volume"
	return "Medium Volume"


func _clear_list(list: Container) -> void:
	for child in list.get_children():
		child.queue_free()


# ---------------------------------------------------------------------------
# Active tab (unchanged from before this session, aside from the rename)
# ---------------------------------------------------------------------------

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
