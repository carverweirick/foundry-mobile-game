class_name Attention

## Everything on the shop floor that needs the player right now, most urgent
## first - the list behind the Hud's Attention ("!") button (design doc
## 27.6: "each tap pans to the next station that needs input - this was the
## Dashboard's real job"). Per-station needs come from
## Station.attention_need(); the two shop-wide ones (parts stuck in Awaiting
## Transfer, no active contract) are added here.
##
## Each item is a Dictionary:
##   key      - stable id, so repeated taps can step past the last target
##   priority - 0 = most urgent (defect), shared with attention_need()
##   label    - short text shown in the Hud's toast
##   station  - Station to pan to, or null
##   overlay  - "nc" / "transfer" / "contracts" / "contracts_active" to open
##              instead, or ""

const PRIORITY_NC_SHELF := 0
const PRIORITY_NO_ENGINEER := 1
const PRIORITY_AWAITING_TRANSFER := 2
const PRIORITY_NO_CONTRACT := 4


static func collect() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var station_by_id: Dictionary = GameData.station_by_id
	var order := 0
	for id: String in GameData.all_real_station_ids():
		var station: Station = station_by_id.get(id)
		if station == null:
			continue
		var need := station.attention_need()
		if need.is_empty():
			continue
		items.append({
			"key": "station:" + id,
			"priority": need.priority,
			"label": "%s: %s" % [station.station_name, need.label],
			"station": station,
			"overlay": "",
			"order": order,
		})
		order += 1

	# Held parts whose next station has nobody assigned - a staffed station
	# auto-claims its own held parts, so only these truly wait on the player.
	var stranded := 0
	for part in GameData.held_parts:
		var next: Station = station_by_id.get(GameData.next_station_id_for(part))
		if next == null or next.assigned_technicians.is_empty():
			stranded += 1
	if stranded > 0:
		items.append({
			"key": "transfer",
			"priority": PRIORITY_AWAITING_TRANSFER,
			"label": "%d part%s awaiting transfer" % [stranded, "" if stranded == 1 else "s"],
			"station": null,
			"overlay": "transfer",
			"order": order,
		})
		order += 1

	# The NC shelf (design doc 28.1): a part needs the player once it's been
	# diagnosed (time to choose a disposition), or if nobody can diagnose it
	# (its contract has no Engineer). A part mid-diagnosis needs nothing yet.
	var shelf_waiting := 0
	for part in GameData.nc_shelf:
		if part.nc_diagnosed or GameData.engineer_for_contract(part.contract_id) == null:
			shelf_waiting += 1
	if shelf_waiting > 0:
		items.append({
			"key": "nc",
			"priority": PRIORITY_NC_SHELF,
			"label": "NC shelf: %d part%s need%s you" % [shelf_waiting, "" if shelf_waiting == 1 else "s", "s" if shelf_waiting == 1 else ""],
			"station": null,
			"overlay": "nc",
			"order": order,
		})
		order += 1

	# Every contract should have an Engineer (design doc 28.2) - only nagged
	# once there's an Engineer to assign.
	if not GameData.engineers().is_empty():
		for contract in GameData.get_active_contracts():
			if GameData.engineer_for_contract(contract.contract_id) == null:
				items.append({
					"key": "engineer:%d" % contract.contract_id,
					"priority": PRIORITY_NO_ENGINEER,
					"label": "%s: assign an engineer" % contract.customer_name,
					"station": null,
					"overlay": "contracts_active",
					"order": order,
				})
				order += 1

	if GameData.get_active_contracts().is_empty() and not GameData.contract_offers.is_empty():
		items.append({
			"key": "contracts",
			"priority": PRIORITY_NO_CONTRACT,
			"label": "No active contract - pick an offer",
			"station": null,
			"overlay": "contracts",
			"order": order,
		})

	# sort_custom isn't stable, so pipeline order is an explicit tiebreak.
	items.sort_custom(func(a, b):
		if a.priority != b.priority:
			return a.priority < b.priority
		return a.order < b.order)
	return items
