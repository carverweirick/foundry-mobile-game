extends OverlayBase
class_name StaffOverlay

## Team (rail tile "Team"): hiring and the crew, in the "Foundry Crew Ledger"
## style of the user's mockup (assets/inspo/UI/team_UI.png). Three tabs:
##
## Hire - the rotating applicant pool (GameData.applicant_pool): a card per
## candidate with a procedural portrait (Portraits), role pill, skill tier,
## per-department skill meters, hire cost/wage and Hire. A gems-only full
## reroll and the passive refill countdown sit underneath.
##
## Roster - payroll (paid out at each factory level-up, see
## GameData.level_up_factory()), the one crew-wide routing strategy, and a
## card per hired worker: what they're doing right now, what they're
## carrying, wage and tenure. There is no per-station assignment any more -
## every technician covers every station (GameData.cover_all_stations()),
## and engineers own contracts instead (assigned from Contracts).
##
## Specialists - one card per SpecialistType, a one-time hire that's
## permanent and passive (design doc Section 9's third defect fix path).
##
## Role is visible at a glance everywhere: technicians get an orange card
## border and pill, engineers blue.
##
## Refresh discipline: the 0.25s poll only touches the Roster (the one part
## that changes on its own as people walk and work) and the countdown, never
## the Hire/Specialist cards; every section uses persistent cards updated in
## place, and nothing refreshes mid-click or while the strategy dropdown is
## open (rebuilding under an open popup orphans it).

const REFRESH_INTERVAL: float = 0.25
const TAB_HIRE := 0
const TAB_ROSTER := 1

## Department id -> short label for the skill meters.
const DEPARTMENT_LABEL := {
	"printing": "Print",
	"shelling": "Shell",
	"pour": "Pour",
	"patching": "Patch",
	"post_process": "Post",
}
const SKILL_COLUMN_WIDTH: float = 34.0
const RIGHT_COLUMN_WIDTH: float = 68.0

@onready var tabs: TabContainer = %TabContainer
@onready var hire_content: VBoxContainer = %HireContent
@onready var roster_content: VBoxContainer = %RosterContent
@onready var specialist_content: VBoxContainer = %SpecialistContent

## Set by main.gd right after all Station nodes are spawned - used for
## station names in the roster's "walking to X" lines.
var station_by_id: Dictionary = {}

var _refresh_elapsed: float = 0.0


func _on_ready() -> void:
	_build_hire_tab()
	_build_roster_tab()
	_build_specialists_tab()
	# Deferred so a click finishes before anything it caused is refreshed.
	GameData.currency_changed.connect(func(_c): _refresh.call_deferred())
	# Hiring can spend gems too, so a gems change can flip affordability.
	GameData.gems_changed.connect(func(_g): _refresh.call_deferred())
	GameData.technician_updated.connect(func(_t): _refresh_live_only.call_deferred())
	GameData.applicant_pool_changed.connect(func(): _refresh.call_deferred())
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


func _refresh() -> void:
	if not panel.visible or _strategy_popup_open() or _click_in_progress():
		return
	_refresh_hire_list()
	_refresh_specialists()
	_refresh_live_only()


func _refresh_live_only() -> void:
	if not panel.visible or _strategy_popup_open() or _click_in_progress():
		return
	_refresh_roster()
	_refresh_countdown.text = "New applicants in %s" % _format_time(GameData.applicant_pool_refresh_seconds_left())
	tabs.set_tab_title(TAB_ROSTER, "Roster (%d)" % GameData.technicians.size())


func _strategy_popup_open() -> bool:
	return _strategy_option != null and _strategy_option.get_popup().visible


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]


func _role_key(tech: Technician) -> String:
	return "info" if tech.is_engineer else "warn"


## Name + role pill on one line (the pill keeps its natural width; the name
## clips - UI rule 1), tier underneath.
func _name_block(parent: Container) -> Array:
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 1)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(names)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	names.add_child(top)
	var name_label := UiKit.label("")
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var pill := UiKit.pill("", "warn")
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(pill)
	return [names, name_label, pill]


# ---------------------------------------------------------------------------
# Hire tab - the rotating applicant pool
# ---------------------------------------------------------------------------

class ApplicantRow:
	var box: PanelContainer
	var portrait: TextureRect
	var name_label: Label
	var role_pill: PanelContainer
	var tier_label: Label
	var skills: HBoxContainer
	var cost_label: Label
	var wage_label: Label
	var hire_button: Button
	var applicant: Technician = null

var _hire_list: VBoxContainer
var _applicant_rows: Dictionary = {} # Technician -> ApplicantRow
var _applicants_empty_label: Label = null
var _refresh_button: Button
var _refresh_countdown: Label


func _build_hire_tab() -> void:
	_hire_list = VBoxContainer.new()
	_hire_list.add_theme_constant_override("separation", 4)
	hire_content.add_child(_hire_list)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	hire_content.add_child(bottom)
	_refresh_button = UiKit.button("", "act_refresh", "neutral")
	_refresh_button.tooltip_text = UiText.tip("Replace every applicant with a fresh set. Costs gems only.")
	_refresh_button.pressed.connect(_on_refresh_applicants_pressed)
	bottom.add_child(_refresh_button)
	_refresh_countdown = UiKit.label("", UiKit.FONT_SMALL, "text_dim")
	_refresh_countdown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_refresh_countdown)


func _refresh_hire_list() -> void:
	var in_pool: Dictionary = {}
	for a in GameData.applicant_pool:
		in_pool[a] = true
	for applicant in _applicant_rows.keys().duplicate():
		if not in_pool.has(applicant):
			MenuLayout.remove_and_free(_applicant_rows[applicant].box)
			_applicant_rows.erase(applicant)

	if GameData.applicant_pool.is_empty():
		if _applicants_empty_label == null:
			_applicants_empty_label = UiKit.label("No applicants right now - new ones arrive shortly, or refresh below.", UiKit.FONT_BODY, "text_dim")
			_applicants_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_hire_list.add_child(_applicants_empty_label)
	elif _applicants_empty_label != null:
		MenuLayout.remove_and_free(_applicants_empty_label)
		_applicants_empty_label = null

	for applicant in GameData.applicant_pool:
		var row: ApplicantRow = _applicant_rows.get(applicant)
		if row == null:
			row = _create_applicant_row(applicant)
			_applicant_rows[applicant] = row
			_hire_list.add_child(row.box)
		_update_applicant_row(row)

	_refresh_button.text = "Refresh applicants (%d gems)" % GameData.APPLICANT_REFRESH_COST
	_refresh_button.disabled = not GameData.can_afford_applicant_refresh()


## A Technician's name, role and departments never change after it's
## generated, so the portrait and skill columns are built once.
func _create_applicant_row(applicant: Technician) -> ApplicantRow:
	var row := ApplicantRow.new()
	row.applicant = applicant
	row.box = UiKit.card(_role_key(applicant))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
	row.box.add_child(line)
	row.portrait = Portraits.view(Portraits.for_staff(applicant))
	line.add_child(row.portrait)

	var block := _name_block(line)
	row.name_label = block[1]
	row.role_pill = block[2]
	row.tier_label = UiKit.label("", UiKit.FONT_SMALL, "text_dim")
	block[0].add_child(row.tier_label)
	row.skills = HBoxContainer.new()
	row.skills.add_theme_constant_override("separation", 3)
	block[0].add_child(row.skills)
	for department in applicant.departments():
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 1)
		column.custom_minimum_size.x = SKILL_COLUMN_WIDTH
		column.add_child(UiKit.label(DEPARTMENT_LABEL.get(department, department), UiKit.FONT_SMALL, "text_dim"))
		var stars: int = applicant.department_skill.get(department, 0)
		column.add_child(UiKit.meter(stars / 5.0, "gold", 5))
		row.skills.add_child(column)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 1)
	right.custom_minimum_size.x = RIGHT_COLUMN_WIDTH
	line.add_child(right)
	row.cost_label = UiKit.label("", UiKit.FONT_SMALL)
	row.cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(row.cost_label)
	row.wage_label = UiKit.label("", UiKit.FONT_SMALL, "text_dim")
	row.wage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(row.wage_label)
	row.hire_button = UiKit.button("Hire", "act_hire", "warn")
	row.hire_button.pressed.connect(_on_hire_applicant_pressed.bind(row))
	right.add_child(row.hire_button)
	return row


func _update_applicant_row(row: ApplicantRow) -> void:
	var applicant := row.applicant
	row.name_label.text = applicant.technician_name
	UiKit.set_pill(row.role_pill, applicant.role_label, _role_key(applicant))
	# "Engineer, Technician Tier" - not "Technician Engineer": the skill tier
	# and the role share the word "Technician".
	row.tier_label.text = "%s Tier" % applicant.tier_label
	row.cost_label.text = "Hire %dg" % applicant.hire_cost
	row.wage_label.text = "Wage %dg" % applicant.wage
	row.hire_button.disabled = not GameData.can_afford_with_gems(applicant.hire_cost)


func _on_hire_applicant_pressed(row: ApplicantRow) -> void:
	GameData.hire_applicant(row.applicant)
	_refresh.call_deferred()


func _on_refresh_applicants_pressed() -> void:
	GameData.refresh_applicant_pool()
	_refresh.call_deferred()


# ---------------------------------------------------------------------------
# Roster tab
# ---------------------------------------------------------------------------

class RosterRow:
	var box: PanelContainer
	var name_label: Label
	var role_pill: PanelContainer
	var status_label: Label
	var carrying_label: Label
	var wage_label: Label
	var tier_label: Label
	var tenure_label: Label

var _payroll_label: Label
var _strategy_option: OptionButton
var _roster_list: VBoxContainer
var _roster_rows: Dictionary = {} # Technician -> RosterRow
var _roster_empty_label: Label = null


func _build_roster_tab() -> void:
	var payroll := HBoxContainer.new()
	payroll.add_theme_constant_override("separation", 4)
	roster_content.add_child(payroll)
	payroll.add_child(UiKit.icon("gold"))
	_payroll_label = UiKit.label("", UiKit.FONT_BODY, "header_text")
	_payroll_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_payroll_label.clip_text = true
	_payroll_label.tooltip_text = UiText.tip("Every hired worker's wage is paid out in one lump sum each time you level up the factory. If gold can't cover it, you go into debt.")
	_payroll_label.mouse_filter = Control.MOUSE_FILTER_PASS
	payroll.add_child(_payroll_label)

	var strategy := HBoxContainer.new()
	strategy.add_theme_constant_override("separation", 6)
	roster_content.add_child(strategy)
	var caption := UiKit.label("Crew strategy:", UiKit.FONT_BODY, "text_dim")
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strategy.add_child(caption)
	_strategy_option = OptionButton.new()
	_strategy_option.focus_mode = Control.FOCUS_NONE
	_strategy_option.add_theme_font_size_override("font_size", UiKit.FONT_BODY)
	_strategy_option.get_popup().add_theme_font_size_override("font_size", UiKit.FONT_BODY)
	_strategy_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# RoutingStrategy is a plain 0..N-1 enum, added in order - index == value.
	for value in Technician.RoutingStrategy.values():
		_strategy_option.add_item(Technician.ROUTING_STRATEGY_LABEL[value])
	_strategy_option.select(GameData.crew_routing_strategy)
	_strategy_option.item_selected.connect(_on_strategy_selected)
	_strategy_option.tooltip_text = UiText.tip("Maximize Machines: keep every machine loaded. Push Through: move finished parts on first.")
	strategy.add_child(_strategy_option)

	var note := UiKit.label("Every technician works every station. Engineers own contracts - assign them in Contracts.", UiKit.FONT_SMALL, "text_dim")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	roster_content.add_child(note)

	_roster_list = VBoxContainer.new()
	_roster_list.add_theme_constant_override("separation", 4)
	roster_content.add_child(_roster_list)


func _refresh_roster() -> void:
	var total := GameData.total_wage_payroll()
	_payroll_label.text = "Payroll %dg - paid at each factory level-up" % total
	UiKit.set_label_color(_payroll_label, "bad" if GameData.is_in_wage_debt() else "header_text")
	if _strategy_option.selected != int(GameData.crew_routing_strategy):
		_strategy_option.select(GameData.crew_routing_strategy)

	if GameData.technicians.is_empty():
		if _roster_empty_label == null:
			_roster_empty_label = UiKit.label("Nobody hired yet - see the Hire tab.", UiKit.FONT_BODY, "text_dim")
			_roster_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_roster_list.add_child(_roster_empty_label)
		return
	if _roster_empty_label != null:
		MenuLayout.remove_and_free(_roster_empty_label)
		_roster_empty_label = null

	# Workers are never un-hired, so rows are only ever added.
	for tech in GameData.technicians:
		var row: RosterRow = _roster_rows.get(tech)
		if row == null:
			row = _create_roster_row(tech)
			_roster_rows[tech] = row
			_roster_list.add_child(row.box)
		_update_roster_row(row, tech)


func _create_roster_row(tech: Technician) -> RosterRow:
	var row := RosterRow.new()
	row.box = UiKit.card(_role_key(tech))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
	row.box.add_child(line)
	line.add_child(Portraits.view(Portraits.for_staff(tech)))

	var block := _name_block(line)
	row.name_label = block[1]
	row.role_pill = block[2]
	# Single-line, clipped: these change every few seconds, so they must
	# never re-wrap (UI rules 1 and 3) - the tooltip has the full text.
	row.status_label = UiKit.label("", UiKit.FONT_SMALL)
	row.status_label.clip_text = true
	block[0].add_child(row.status_label)
	row.carrying_label = UiKit.label("", UiKit.FONT_SMALL, "text_dim")
	row.carrying_label.clip_text = true
	block[0].add_child(row.carrying_label)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 1)
	right.custom_minimum_size.x = RIGHT_COLUMN_WIDTH
	line.add_child(right)
	row.wage_label = UiKit.label("", UiKit.FONT_SMALL)
	row.wage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(row.wage_label)
	row.tier_label = UiKit.label("", UiKit.FONT_SMALL, "text_dim")
	row.tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(row.tier_label)
	row.tenure_label = UiKit.label("", UiKit.FONT_SMALL, "text_dim")
	row.tenure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(row.tenure_label)
	return row


func _update_roster_row(row: RosterRow, tech: Technician) -> void:
	row.name_label.text = tech.technician_name
	# Role in the pill, skill tier on its own line - "Technician - Technician"
	# was ambiguous (role and tier share the word).
	UiKit.set_pill(row.role_pill, tech.role_label, _role_key(tech))
	row.tier_label.text = "%s Tier" % tech.tier_label
	row.status_label.text = _status_text(tech)
	row.box.tooltip_text = row.status_label.text
	row.carrying_label.text = "Carrying %s" % _carried_parts_summary(tech) if not tech.carried_parts.is_empty() else ""
	row.wage_label.text = "Wage %dg" % tech.wage
	var levels := tech.factory_levels_stuck_with_you
	row.tenure_label.text = "%d level-up%s" % [levels, "" if levels == 1 else "s"]


func _status_text(tech: Technician) -> String:
	if tech.is_engineer:
		# Engineers own contracts and diagnose defects, not stations.
		var owned := tech.assigned_contract_ids.size()
		var text := "Owns %d contract%s" % [owned, "" if owned == 1 else "s"] if owned > 0 else "No contracts - assign in Contracts"
		var target := GameData.diagnosis_target_for(tech)
		if target != null:
			text += " - diagnosing #%d" % target.part_id
		return text
	if not tech.is_assigned:
		return "Idle"
	if tech.is_traveling:
		return "Walking to %s" % _display_name_for(tech.travel_target_station_id)
	if tech.is_interacting:
		return "Working at %s" % _display_name_for(tech.current_station_id)
	return "At %s" % _display_name_for(tech.current_station_id)


func _on_strategy_selected(index: int) -> void:
	GameData.set_crew_routing_strategy(index as Technician.RoutingStrategy)
	_refresh_live_only.call_deferred()


## Prefers the live Station's own name ("Printing #2") over the shared
## StationDef display name, which can't tell printer instances apart.
func _display_name_for(station_id: String) -> String:
	var station: Station = station_by_id.get(station_id)
	if station != null:
		return station.station_name
	var def := GameData.get_station(station_id)
	return def.display_name if def != null else station_id


## "#3 (Acme Co.) -> Shelling [1/2]".
func _carried_parts_summary(tech: Technician) -> String:
	var pieces: Array[String] = []
	for part in tech.carried_parts:
		var contract := GameData.get_contract(part.contract_id)
		pieces.append("#%d (%s) -> %s" % [
			part.part_id, contract.customer_name if contract != null else "no contract",
			_display_name_for(GameData.next_station_id_for(part))])
	return "%s [%d/%d]" % [", ".join(PackedStringArray(pieces)), tech.carried_parts.size(), Technician.CARRY_CAPACITY]


# ---------------------------------------------------------------------------
# Specialists tab
# ---------------------------------------------------------------------------

class SpecialistRow:
	var box: PanelContainer
	var cost: HBoxContainer
	var hire_button: Button
	var hired: HBoxContainer
	var type: int = 0

var _specialist_rows: Array[SpecialistRow] = []


func _build_specialists_tab() -> void:
	var intro := UiKit.label("A one-time hire: half of new defects in their categories never happen, and any part on the NC shelf with one is diagnosed at once.", UiKit.FONT_SMALL, "text_dim")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	specialist_content.add_child(intro)
	for type in GameData.SpecialistType.values():
		var row := SpecialistRow.new()
		row.type = type
		row.box = UiKit.card()
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 5)
		row.box.add_child(line)
		line.add_child(Portraits.view(Portraits.make(GameData.SPECIALIST_LABEL[type], Portraits.Style.SPECIALIST)))

		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", 1)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(names)
		var title := UiKit.label(GameData.SPECIALIST_LABEL[type])
		title.clip_text = true
		names.add_child(title)
		var category_names: Array[String] = []
		for category in GameData.SPECIALIST_CATEGORIES.get(type, []):
			category_names.append(GameData.DEFECT_CATEGORY_LABEL[category])
		var covers := UiKit.label("Reduces: %s" % ", ".join(PackedStringArray(category_names)), UiKit.FONT_SMALL, "text_dim")
		covers.clip_text = true
		names.add_child(covers)

		row.cost = HBoxContainer.new()
		row.cost.add_theme_constant_override("separation", 2)
		row.cost.add_child(UiKit.icon("gold"))
		var price := UiKit.label("%dg" % GameData.SPECIALIST_HIRE_COST)
		price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.cost.add_child(price)
		row.cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(row.cost)
		row.hire_button = UiKit.button("Hire", "act_hire", "warn")
		row.hire_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.hire_button.pressed.connect(_on_hire_specialist_pressed.bind(type))
		line.add_child(row.hire_button)
		row.hired = HBoxContainer.new()
		row.hired.add_theme_constant_override("separation", 2)
		row.hired.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.hired.add_child(UiKit.icon("st_check"))
		var hired_label := UiKit.label("Hired", UiKit.FONT_BODY, "good")
		hired_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.hired.add_child(hired_label)
		line.add_child(row.hired)
		specialist_content.add_child(row.box)
		_specialist_rows.append(row)


func _refresh_specialists() -> void:
	for row in _specialist_rows:
		var hired := GameData.is_specialist_hired(row.type)
		row.hired.visible = hired
		row.cost.visible = not hired
		row.hire_button.visible = not hired
		row.hire_button.disabled = not GameData.can_afford_with_gems(GameData.SPECIALIST_HIRE_COST)
		UiKit.set_card_border(row.box, "good" if hired else "card_border")


func _on_hire_specialist_pressed(type: int) -> void: # GameData.SpecialistType
	GameData.hire_specialist(type)
	_refresh.call_deferred()
