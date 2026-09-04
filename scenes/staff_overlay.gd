extends OverlayBase
class_name StaffOverlay

## Standalone entry point covering the old Shop overlay's Technicians and
## Specialists tabs (design request, this session: split the old Shop
## overlay's tabs into individually-labeled buttons - Technicians and
## Specialists specifically got regrouped into one "Staff" button rather than
## two separate ones, since both are hiring actions - a station technician
## vs. a one-time specialist engineer - distinct from Printers, which is
## buying equipment rather than hiring someone). Content and refresh logic
## are otherwise unchanged from the old ShopOverlay.
##
## Hiring a technician doesn't happen at an individual station; it happens
## here, and assigning them to a station (or several) is a separate step done
## from the same roster row. Specialists (design doc Section 9's third defect
## fix path) are a much simpler one-time-hire-per-type list underneath, on
## their own tab, since a specialist isn't assigned anywhere or ever un-hired.
##
## Hiring itself is a rotating applicant pool now, not "any tier, any time"
## (design request, this session: "build the rotating applicant pool") - see
## GameData.applicant_pool/hire_applicant()/refresh_applicant_pool(). Each
## candidate is either a Technician (Patching/Post Process skill) or an
## Engineer (Printing/Shelling/Pour skill - Technician.StaffRole, this
## session's own staff rework), with randomly-rolled per-department stars
## shown right on the card.

const REFRESH_INTERVAL: float = 0.25

## Persistent per-technician roster row (mirrors StationDetailMenu's
## persistent rack-slot Buttons) - built once per technician and updated in
## place from then on rather than torn down and rebuilt every refresh (see
## _create_roster_row()/_update_roster_row() for why that used to matter).
## Technicians are never un-hired in this game, so a row only ever needs to
## be added, never removed.
class RosterRow:
	var container: VBoxContainer
	var header: Label
	var carrying_label: Label
	var strategy_option: OptionButton
	var station_toggles: GridContainer
	var station_checks: Dictionary = {} # station_id -> CheckBox


## Persistent per-applicant card in the rotating pool (design request, this
## session: "build the rotating applicant pool") - same persistent-widget
## reasoning as RosterRow and ContractsOverlay's OfferRow: hiring/refreshing
## churns this list, but tearing every card down on the unconditional
## refresh would risk the same click-eating race those fixes were for.
class ApplicantRow:
	var container: VBoxContainer
	var header: Label
	var skill_row: HBoxContainer
	var skill_labels: Dictionary = {} # department name -> Label, built once
	var cost_label: Label
	var hire_button: Button
	var applicant: Technician = null

## Department id -> display text, for the skill-row labels below.
const DEPARTMENT_LABEL := {
	"printing": "Printing",
	"shelling": "Shelling",
	"pour": "Pour",
	"patching": "Patching",
	"post_process": "Post Process",
}

@onready var hire_list: VBoxContainer = %HireList
@onready var roster_list: VBoxContainer = %RosterList
@onready var specialist_list: VBoxContainer = %SpecialistList
@onready var refresh_applicants_button: Button = %RefreshApplicantsButton
@onready var refresh_countdown_label: Label = %RefreshCountdownLabel
@onready var payroll_label: Label = %PayrollLabel

## Set by main.gd right after all Station nodes are spawned - needed to list
## which stations a technician can be assigned to and to read/write their
## live assigned_technicians state.
var station_by_id: Dictionary = {}

var _refresh_elapsed: float = 0.0
var _roster_rows: Dictionary = {} # Technician -> RosterRow
var _roster_empty_label: Label = null
var _applicant_rows: Dictionary = {} # Technician -> ApplicantRow
var _applicants_empty_label: Label = null


func _on_ready() -> void:
	# Deferred, not direct: technician_updated can fire from inside a
	# checkbox's own toggled handler (assign_technician() emits it
	# synchronously), and _refresh_live_only() tears down/rebuilds every
	# checkbox, including the one still mid-click. Freeing a Control while
	# Godot is still processing its own input event confuses subsequent
	# clicks on the rebuilt nodes - call_deferred lets this frame's input
	# finish first. technician_updated specifically routes to
	# _refresh_live_only() (Roster only), not the full _refresh() - it fires
	# routinely (every ~8-10s per technician just from normal movement) and
	# has nothing to do with Hire/Specialists, so routing it through the full
	# rebuild would reintroduce the exact same-timer click race on those
	# sections that _refresh_live_only() exists to avoid.
	GameData.currency_changed.connect(func(_c): _refresh.call_deferred())
	# Hiring can now spend gems too (can_afford_with_gems()), so a gems-only
	# change can flip a Hire button's affordability independent of currency.
	GameData.gems_changed.connect(func(_g): _refresh.call_deferred())
	GameData.technician_updated.connect(func(_t): _refresh_live_only.call_deferred())
	# Rotating applicant pool (this session) - a hire, a paid reroll, or the
	# passive auto-refill all fire this.
	GameData.applicant_pool_changed.connect(func(): _refresh.call_deferred())
	refresh_applicants_button.pressed.connect(_on_refresh_applicants_pressed)
	# Wage economy tick - roster hires/fires nobody automatically, so a full
	# _refresh() would be overkill here; _refresh_live_only() already updates
	# the payroll label every poll, this just gets that update onto the
	# screen the instant a payday actually lands instead of up to 0.25s late.
	GameData.payday.connect(func(_total, _debt): _refresh_live_only.call_deferred())


func _process(delta: float) -> void:
	if not panel.visible:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed < REFRESH_INTERVAL:
		return
	_refresh_elapsed = 0.0
	_refresh_live_only()


func _on_open() -> void:
	_refresh_elapsed = 0.0
	_refresh()


## Full rebuild, including the Hire and Specialists sections - only called on
## open and from the reactive currency_changed/technician_updated handlers
## below, NOT from the unconditional 0.25s poll (see _refresh_live_only()).
func _refresh() -> void:
	if _any_strategy_popup_open() or _click_in_progress():
		return
	_refresh_hire_list()
	_refresh_specialist_list()
	_refresh_live_only()


## A strategy OptionButton is a two-step interaction (open the dropdown,
## then click an item), unlike a single-click checkbox or button - there's a
## real time gap where the popup just sits open waiting on the user. The
## regular 0.25s poll (or a technician_updated firing from some OTHER
## technician's own movement, unrelated to what the user's doing here) would
## otherwise tear down and rebuild the whole roster mid-gap, destroying the
## very OptionButton whose popup is still open - so a click on an item in
## that now-orphaned popup silently does nothing. Skip refreshing entirely
## while any strategy dropdown is open; the deferred refresh from
## _on_strategy_selected() picks it up correctly once the popup closes.
##
## Rebuilds only the Roster section - the one part of this panel that
## legitimately changes on its own over time (a technician's position/status
## as they walk and work). The Hire and Specialists sections deliberately do
## NOT rebuild here: they only ever change in response to a specific hire
## action (which already triggers a reactive _refresh() via currency_changed),
## so tearing their buttons down and recreating them on this same blind timer
## served no purpose except occasionally eating a click.
func _refresh_live_only() -> void:
	if _any_strategy_popup_open() or _click_in_progress():
		return
	_refresh_roster_list()
	_update_refresh_countdown()
	_update_payroll_label()


## The "new applicants in: X" countdown is a continuously-ticking number, not
## a rebuild - safe to touch every poll same as the Roster list, no risk of
## eating a click since this only ever assigns .text on an existing Label.
func _update_refresh_countdown() -> void:
	refresh_countdown_label.text = "New applicants in: %s" % _format_time(GameData.applicant_pool_refresh_seconds_left())


## Wage economy tick (this session) - every hired technician/engineer draws
## their wage every payday regardless of assignment (GameData._process_wages()).
## Turns red in wage debt (currency negative) as the same visible-consequence
## cue as the HUD CurrencyLabel's own red tint (main.gd._on_currency_changed()).
func _update_payroll_label() -> void:
	var total := GameData.total_wage_payroll()
	payroll_label.text = "Payroll: %dg every payday (next in %s)" % [
		total, _format_time(GameData.wage_payment_seconds_left())
	]
	if GameData.is_in_wage_debt():
		payroll_label.add_theme_color_override("font_color", Color(0.85, 0.2, 0.2))
	else:
		payroll_label.remove_theme_color_override("font_color")


func _any_strategy_popup_open() -> bool:
	for option: OptionButton in roster_list.find_children("*", "OptionButton", true, false):
		if option.get_popup().visible:
			return true
	return false


## Rotating applicant pool (design request, this session: "build the
## rotating applicant pool" - replaces the old flat "hire any tier, any
## time" list). Persistent-widget pattern, same reasoning as the Roster
## list below and ContractsOverlay's OfferRow - hiring/refreshing churns
## this list, so rows are built once and updated in place, never torn down
## except when the underlying applicant actually leaves the pool.
func _refresh_hire_list() -> void:
	var pool_ids: Dictionary = {}
	for a in GameData.applicant_pool:
		pool_ids[a] = true

	for applicant in _applicant_rows.keys().duplicate():
		if not pool_ids.has(applicant):
			var stale: ApplicantRow = _applicant_rows[applicant]
			stale.container.queue_free()
			_applicant_rows.erase(applicant)

	if GameData.applicant_pool.is_empty():
		if _applicants_empty_label == null:
			_applicants_empty_label = Label.new()
			_applicants_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_applicants_empty_label.text = "No applicants right now - check back shortly, or refresh below."
			hire_list.add_child(_applicants_empty_label)
	elif _applicants_empty_label != null:
		_applicants_empty_label.queue_free()
		_applicants_empty_label = null

	for applicant in GameData.applicant_pool:
		var row: ApplicantRow = _applicant_rows.get(applicant)
		if row == null:
			row = _create_applicant_row()
			_applicant_rows[applicant] = row
			hire_list.add_child(row.container)
		_update_applicant_row(row, applicant)

	refresh_applicants_button.text = "Refresh Applicants (%d gems)" % GameData.APPLICANT_REFRESH_COST
	refresh_applicants_button.disabled = not GameData.can_afford_applicant_refresh()
	_update_refresh_countdown()


func _create_applicant_row() -> ApplicantRow:
	var row := ApplicantRow.new()
	row.container = VBoxContainer.new()

	row.header = Label.new()
	row.header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.container.add_child(row.header)

	row.skill_row = HBoxContainer.new()
	row.container.add_child(row.skill_row)

	var bottom_row := HBoxContainer.new()
	row.cost_label = Label.new()
	row.cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.cost_label.custom_minimum_size = Vector2(160.0, 0.0)
	bottom_row.add_child(row.cost_label)

	row.hire_button = Button.new()
	row.hire_button.text = "Hire"
	row.hire_button.pressed.connect(_on_hire_applicant_pressed.bind(row))
	bottom_row.add_child(row.hire_button)
	row.container.add_child(bottom_row)

	row.container.add_child(HSeparator.new())
	return row


## A given Technician resource's role (and therefore departments()) never
## changes after it's generated, so the skill_row's labels only ever need
## building once per row, the first time it's paired with a real applicant -
## same lazy-build-once pattern as RosterRow's station checkboxes below.
func _update_applicant_row(row: ApplicantRow, applicant: Technician) -> void:
	row.applicant = applicant
	# Not "%s %s" % [tier_label, role_label] - Technician.SkillTier.TECHNICIAN's
	# own label ("Technician") collides with StaffRole.TECHNICIAN's, producing
	# genuinely ambiguous text like "Technician Engineer" for an Engineer at
	# the Technician skill tier (caught by a headless UI test, not assumed).
	row.header.text = "%s - %s, %s Tier" % [applicant.technician_name, applicant.role_label, applicant.tier_label]

	if row.skill_labels.is_empty():
		for department in applicant.departments():
			var label := Label.new()
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size = Vector2(90.0, 0.0)
			row.skill_row.add_child(label)
			row.skill_labels[department] = label
	for department in row.skill_labels:
		var stars: int = applicant.department_skill.get(department, 0)
		row.skill_labels[department].text = "%s %d/5" % [DEPARTMENT_LABEL.get(department, department), stars]

	row.cost_label.text = "Hire %dg (wage %dg)" % [applicant.hire_cost, applicant.wage]
	row.hire_button.disabled = not GameData.can_afford_with_gems(applicant.hire_cost)


func _on_hire_applicant_pressed(row: ApplicantRow) -> void:
	GameData.hire_applicant(row.applicant)
	_refresh.call_deferred()


func _on_refresh_applicants_pressed() -> void:
	GameData.refresh_applicant_pool()
	_refresh.call_deferred()


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]


## Bug fix (carried over from ShopOverlay): the roster used to be torn down
## and rebuilt from scratch every 0.25s poll - fine for avoiding the
## click-eating race once guarded, but a freshly created Control needs at
## least one layout pass to reach its final size, so destroying and
## recreating everything every 250ms caused a visible "pop"/reflow every
## single poll even when nothing had actually changed. Each technician gets a
## persistent RosterRow, built once (_create_roster_row()) and updated in
## place from then on (_update_roster_row()) - text/visibility/checkbox state
## changes, no destroying and recreating Controls on a blind timer.
func _refresh_roster_list() -> void:
	if GameData.technicians.is_empty():
		if _roster_empty_label == null:
			_roster_empty_label = Label.new()
			_roster_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_roster_empty_label.text = "No technicians hired yet."
			roster_list.add_child(_roster_empty_label)
		return
	if _roster_empty_label != null:
		_roster_empty_label.queue_free()
		_roster_empty_label = null

	for tech in GameData.technicians:
		var row: RosterRow = _roster_rows.get(tech)
		if row == null:
			row = _create_roster_row(tech)
			_roster_rows[tech] = row
			roster_list.add_child(row.container)
		_update_roster_row(row, tech)


## Builds one technician's row structure ONCE - see _refresh_roster_list()'s
## comment for why this never gets torn down again. A checkbox per assignable
## station (Ship is automatic and never needs staffing, so it's excluded) -
## checking a box assigns tech there, unchecking frees it, this is also how a
## technician ends up working more than one station at once. Station
## checkboxes themselves are added lazily in _update_roster_row() below, not
## here, since a printer bought after this row already exists needs its own
## checkbox to show up without the whole row being rebuilt.
func _create_roster_row(tech: Technician) -> RosterRow:
	var row := RosterRow.new()
	row.container = VBoxContainer.new()

	# Fixed 2-line minimum height on both - a technician's status text length
	# varies a lot ("Idle" vs "Working 2 station(s), 85% productivity -
	# walking to Clean, interacting"), and without a fixed height, crossing a
	# line-wrap threshold changed this row's own height and shifted every
	# roster row below it. carrying_label is worse: toggling `.visible` gave
	# it a footprint of literally zero when not carrying anything, popping
	# the row's height between two very different values constantly for an
	# active technician. Both now reserve the same vertical space always,
	# whether their text is short, long, or blank.
	row.header = Label.new()
	row.header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.header.custom_minimum_size = Vector2(0, 40)
	row.container.add_child(row.header)

	row.carrying_label = Label.new()
	row.carrying_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.carrying_label.custom_minimum_size = Vector2(0, 40)
	row.container.add_child(row.carrying_label)

	var strategy_row := HBoxContainer.new()
	var strategy_label := Label.new()
	strategy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Without an explicit minimum width, an autowrapping Label reports almost
	# no minimum size of its own, so the HBoxContainer squeezes it down to
	# whatever sliver is left after the OptionButton claims what it wants,
	# and it wraps one character per line instead of sitting on one line to
	# the OptionButton's left.
	strategy_label.custom_minimum_size = Vector2(70.0, 0.0)
	strategy_label.text = "Strategy:"
	strategy_row.add_child(strategy_label)

	row.strategy_option = OptionButton.new()
	for strategy in Technician.RoutingStrategy.values():
		row.strategy_option.add_item(Technician.ROUTING_STRATEGY_LABEL[strategy])
	row.strategy_option.select(tech.routing_strategy)
	row.strategy_option.item_selected.connect(_on_strategy_selected.bind(tech))
	strategy_row.add_child(row.strategy_option)
	row.container.add_child(strategy_row)

	row.station_toggles = GridContainer.new()
	row.station_toggles.columns = 2
	row.container.add_child(row.station_toggles)

	row.container.add_child(HSeparator.new())
	return row


## Updates an existing row's live fields in place - text, the carrying
## label's visibility, and every station checkbox's pressed state (via
## set_pressed_no_signal() so re-syncing an already-correct checkbox doesn't
## fire its own toggled handler and needlessly re-assign/unassign). Doesn't
## touch strategy_option's selection - the only thing that ever changes
## tech.routing_strategy is this exact dropdown, so the OptionButton's own
## displayed selection is already correct the instant the player picks one.
func _update_roster_row(row: RosterRow, tech: Technician) -> void:
	var assignment_text := "Idle"
	if tech.is_assigned:
		assignment_text = "Working %d station(s), %d%% productivity" % [
			tech.real_assigned_station_ids().size(), roundi(tech.productivity_multiplier * 100.0)
		]
		if tech.is_traveling:
			assignment_text += " - walking to %s" % _display_name_for(tech.travel_target_station_id)
		else:
			assignment_text += " - at %s" % _display_name_for(tech.current_station_id)
			if tech.is_interacting:
				assignment_text += ", interacting"
	# Same tier/role-label collision fix as the applicant card above. Wage
	# shown here too now (this session's wage economy tick) - it's an ongoing
	# cost for as long as they're on the roster, not just a one-time hire fee,
	# so it belongs on the persistent row, not only the pre-hire applicant card.
	row.header.text = "%s (%s, %s Tier, wage %dg) - %s" % [
		tech.technician_name, tech.role_label, tech.tier_label, tech.wage, assignment_text
	]

	# Always visible now - blank rather than hidden when not carrying
	# anything, so the row's height never pops.
	row.carrying_label.text = "Carrying: %s" % _carried_parts_summary(tech) if not tech.carried_parts.is_empty() else ""

	# Design request (carried over): "i don't want printer #2 to be a
	# separate responsibility i want the print station responsibility to
	# cover all the printers not individual ones." GameData.assignable_station_group_ids()
	# collapses every printer instance into one virtual "printing" checkbox
	# instead of listing "Printing #1"/"Printing #2" separately.
	for id in GameData.assignable_station_group_ids():
		if id == "printing":
			if not row.station_checks.has(id):
				_add_printer_group_check(row, tech)
			var group_check: CheckBox = row.station_checks.get(id)
			if group_check != null:
				group_check.set_pressed_no_signal(tech.assigned_station_ids.has("printing"))
			continue
		if not row.station_checks.has(id):
			_add_station_check(row, tech, id)
		var check: CheckBox = row.station_checks.get(id)
		if check != null:
			check.set_pressed_no_signal(tech.assigned_station_ids.has(id))


func _add_station_check(row: RosterRow, tech: Technician, id: String) -> void:
	var def := GameData.get_station(id)
	if def.station_type == Station.StationType.AUTOMATIC:
		return
	var station: Station = station_by_id.get(id)
	if station == null:
		return
	var check := CheckBox.new()
	check.text = station.station_name
	check.button_pressed = tech.assigned_station_ids.has(id)
	check.toggled.connect(_on_station_toggled.bind(tech, station))
	row.station_toggles.add_child(check)
	row.station_checks[id] = check


## One checkbox covering every currently-owned printer at once - see
## GameData.assign_technician_to_printer_group() for what checking it
## actually does (including automatically covering a printer bought later,
## with no need to touch this checkbox again).
func _add_printer_group_check(row: RosterRow, tech: Technician) -> void:
	var check := CheckBox.new()
	check.text = "Printing (all)"
	check.button_pressed = tech.assigned_station_ids.has("printing")
	check.toggled.connect(_on_printer_group_toggled.bind(tech))
	row.station_toggles.add_child(check)
	row.station_checks["printing"] = check


func _on_printer_group_toggled(pressed: bool, tech: Technician) -> void:
	if pressed:
		GameData.assign_technician_to_printer_group(tech)
	else:
		GameData.unassign_technician_from_printer_group(tech)
	_refresh.call_deferred()


## Design doc Section 9's third fix path - "a hire distinct from station
## technicians, tied to a defect category rather than a station." A one-time
## permanent hire per type (no assignment, no roster row with checkboxes -
## see GameData.hire_specialist()), so this is a much simpler list than the
## Technicians tab's: once hired, a type just shows "Hired" instead of a
## Hire button, forever.
func _refresh_specialist_list() -> void:
	_clear_list(specialist_list)
	for type in GameData.SpecialistType.values():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(280.0, 0.0)
		var categories: Array = GameData.SPECIALIST_CATEGORIES.get(type, [])
		var category_names: Array[String] = []
		for category in categories:
			category_names.append(GameData.DEFECT_CATEGORY_LABEL[category])
		label.text = "%s - %s (%dg)" % [
			GameData.SPECIALIST_LABEL[type],
			", ".join(PackedStringArray(category_names)),
			GameData.SPECIALIST_HIRE_COST,
		]
		row.add_child(label)

		if GameData.is_specialist_hired(type):
			var hired_label := Label.new()
			hired_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hired_label.text = "Hired"
			row.add_child(hired_label)
		else:
			var hire_button := Button.new()
			hire_button.text = "Hire"
			hire_button.disabled = not GameData.can_afford_with_gems(GameData.SPECIALIST_HIRE_COST)
			hire_button.pressed.connect(_on_hire_specialist_pressed.bind(type))
			row.add_child(hire_button)

		specialist_list.add_child(row)


func _on_hire_specialist_pressed(type: int) -> void: # GameData.SpecialistType
	GameData.hire_specialist(type)
	_refresh.call_deferred()


## Prefers the live Station's own station_name (e.g. "Printing #2" for a
## specific printer instance) over the shared StationDef.display_name, which
## can't tell printer instances apart from each other.
func _display_name_for(station_id: String) -> String:
	var station: Station = station_by_id.get(station_id)
	if station != null:
		return station.station_name
	var def := GameData.get_station(station_id)
	return def.display_name if def != null else station_id


## Same summary format as StationDetailMenu's - "Part #3 (Acme Co.) -> Deplate".
func _carried_parts_summary(tech: Technician) -> String:
	var pieces: Array[String] = []
	for part in tech.carried_parts:
		var contract := GameData.get_contract(part.contract_id)
		var dest := _display_name_for(GameData.next_station_id_for(part))
		pieces.append("#%d (%s) -> %s" % [
			part.part_id, contract.customer_name if contract != null else "no contract", dest
		])
	return "%s [%d/%d]" % [", ".join(PackedStringArray(pieces)), tech.carried_parts.size(), Technician.CARRY_CAPACITY]


## RoutingStrategy.values() is a plain 0..N-1 int enum added to the
## OptionButton in that exact order with no custom ids, so the selected
## index maps directly onto the enum value - no lookup table needed.
func _on_strategy_selected(index: int, tech: Technician) -> void:
	tech.routing_strategy = index as Technician.RoutingStrategy
	GameData.technician_updated.emit(tech)


func _on_station_toggled(pressed: bool, tech: Technician, station: Station) -> void:
	if pressed:
		GameData.assign_technician(tech, station)
	else:
		GameData.unassign_technician(tech, station)
	_refresh.call_deferred()


func _clear_list(list: VBoxContainer) -> void:
	for child in list.get_children():
		child.queue_free()
