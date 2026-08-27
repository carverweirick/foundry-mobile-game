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
@onready var buy_printer_button: Button = %BuyPrinterButton

var _refresh_elapsed: float = 0.0


func _on_ready() -> void:
	buy_printer_button.pressed.connect(_on_buy_printer_pressed)
	GameData.currency_changed.connect(func(_c): _refresh.call_deferred())


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
	if GameData.can_buy_printer():
		var cost := GameData.printer_purchase_cost()
		buy_printer_button.text = "Buy Printer (%dg)" % cost
		buy_printer_button.disabled = not GameData.can_afford(cost)
	else:
		buy_printer_button.text = "Factory level cap reached"
		buy_printer_button.disabled = true


func _on_buy_printer_pressed() -> void:
	GameData.buy_printer()
	_refresh.call_deferred()
