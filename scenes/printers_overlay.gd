extends OverlayBase
class_name PrintersOverlay

## Standalone entry point covering the old Shop overlay's Printers tab
## (design request, this session: split the old Shop overlay's tabs into
## individually-labeled buttons). Content and refresh logic are otherwise
## unchanged.
##
## Design doc Section 21.2: printers are purchased individually, capped by
## factory level. This is a simple standing status + one buy button - no
## per-printer roster here, since individual printer tiers are managed from
## each printer's own Station Detail Menu (they're just ordinary Stations
## once spawned) exactly like every other station's Upgrade/Upgrade Rack
## buttons, not from here.

const REFRESH_INTERVAL: float = 0.25

@onready var printer_status_label: Label = %PrinterStatusLabel
@onready var factory_exp_label: Label = %FactoryExpLabel
@onready var buy_printer_button: Button = %BuyPrinterButton

var _refresh_elapsed: float = 0.0


func _on_ready() -> void:
	buy_printer_button.pressed.connect(_on_buy_printer_pressed)
	GameData.currency_changed.connect(func(_c): _refresh.call_deferred())
	# Factory Level EXP (this session) doesn't move currency at all, so it
	# needs its own signal for an immediate refresh rather than waiting on
	# the next 0.25s poll.
	GameData.factory_progress_changed.connect(func(): _refresh.call_deferred())
	# Buying a printer can now spend gems too (can_afford_with_gems()), so a
	# gems-only change (e.g. a Factory Level-up reward) can flip the Buy
	# button's affordability on its own, independent of currency.
	GameData.gems_changed.connect(func(_g): _refresh.call_deferred())


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


func _refresh() -> void:
	if _click_in_progress():
		return
	var cap := GameData.printer_cap()
	printer_status_label.text = "%d/%d printers owned (Factory Level %d)" % [
		GameData.owned_printer_count, cap, GameData.factory_level
	]
	if GameData.is_factory_level_maxed():
		factory_exp_label.text = "Factory Level %d (max) - %d EXP earned" % [GameData.factory_level, GameData.factory_exp]
	else:
		var next_level := GameData.factory_level + 1
		factory_exp_label.text = "%d/%d EXP to Factory Level %d - completing contracts earns EXP" % [
			GameData.factory_exp, GameData.factory_exp_for_level(next_level), next_level
		]
	if GameData.can_buy_printer():
		var cost := GameData.printer_purchase_cost()
		buy_printer_button.text = "Buy Printer (%dg)" % cost
		buy_printer_button.disabled = not GameData.can_afford_with_gems(cost)
	else:
		buy_printer_button.text = "Factory level cap reached"
		buy_printer_button.disabled = true


func _on_buy_printer_pressed() -> void:
	GameData.buy_printer()
	_refresh.call_deferred()
