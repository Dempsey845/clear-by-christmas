class_name TruckGarage
extends Node3D

@onready var _panel: PanelContainer = %Panel
@onready var _feedback: Label = %Feedback

const ATTACHMENTS := {
	SnowTruck.Attachment.NONE: {"node": "Stock", "name": "Standard truck", "price": 0, "jobs": 0},
	SnowTruck.Attachment.SCOOP: {"node": "Scoop", "name": "Front scoop · 650 L", "price": SnowTruck.SCOOP_PRICE, "jobs": 9},
	SnowTruck.Attachment.VACUUM: {"node": "Vacuum", "name": "Truck vacuum", "price": SnowTruck.VACUUM_PRICE, "jobs": 14, "requires_scoop": true},
	SnowTruck.Attachment.BLOWER: {"node": "Blower", "name": "Side-discharge blower", "price": SnowTruck.BLOWER_PRICE, "jobs": 18, "requires_scoop": true},
	SnowTruck.Attachment.WIDE_BUCKET: {"node": "WideBucket", "name": "Wide bucket · 1,050 L", "price": SnowTruck.WIDE_BUCKET_PRICE, "jobs": 23, "requires_scoop": true},
}

const UPGRADES := {
	SnowTruck.Upgrade.WINTER_TYRES: {"node": "WinterTyres", "name": "Winter tyres · More grip", "price": 30, "jobs": 12},
	SnowTruck.Upgrade.EXTENDED_TANK: {"node": "ExtendedTank", "name": "Extended vacuum tank · 2,000 L", "price": 65, "jobs": 21},
	SnowTruck.Upgrade.HEATED_WHEELS: {"node": "HeatedWheels", "name": "Heated wheels · H to toggle", "price": 110, "jobs": 26},
}

var truck: SnowTruck
var board: JobBoard
var _prior_mouse_mode := Input.MOUSE_MODE_CAPTURED

var is_open: bool:
	get:
		return _panel.visible


func configure(vehicle: SnowTruck, job_board: JobBoard) -> void:
	truck = vehicle
	board = job_board
	for item in ATTACHMENTS:
		_button(ATTACHMENTS[item]).pressed.connect(_select.bind(item))
	for upgrade in UPGRADES:
		_button(UPGRADES[upgrade]).pressed.connect(_buy_upgrade.bind(upgrade))
	%Close.pressed.connect(close)


func contains_truck() -> bool:
	for x in [-1.1, 1.1]:
		for z in [-2.15, 2.15]:
			var corner := to_local(truck.to_global(Vector3(x, 0.0, z)))
			if absf(corner.x) > 2.70 or absf(corner.z) > 3.48 or corner.y > 2.0:
				return false
	return true


func open() -> void:
	_prior_mouse_mode = Input.mouse_mode
	truck.controls_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_feedback.text = "Dump the current load before changing equipment." if truck.cargo > 0.00001 else ""
	_refresh()
	_panel.show()
	%Close.grab_focus()


func close() -> void:
	if not is_open:
		return
	_panel.hide()
	truck.controls_locked = false
	Input.mouse_mode = _prior_mouse_mode


func _select(item: SnowTruck.Attachment) -> void:
	if not is_open or not contains_truck() or not truck.can_park() or truck.cargo > 0.00001:
		return
	var purchased := not truck.owns_attachment(item)
	if purchased:
		if not _attachment_requirement(item).is_empty() or not board.try_spend(ATTACHMENTS[item].price):
			return
		truck.unlock_attachment(item)
	truck.equip(item)
	_feedback.text = "Purchased and fitted." if purchased else "Equipment fitted."
	_refresh()


func _refresh() -> void:
	%Balance.text = "Balance  £%d" % board.balance
	for item in ATTACHMENTS:
		var entry: Dictionary = ATTACHMENTS[item]
		var owned := truck.owns_attachment(item)
		var fitted: bool = truck.attachment == item
		var locked := "" if owned else _attachment_requirement(item)
		var effect := "Fitted" if fitted else "Fit"
		_update_button(entry, effect if owned else _purchase_label(entry.price, locked),
			fitted or truck.cargo > 0.00001 or (not owned and (entry.price > board.balance or not locked.is_empty())))
	for upgrade in UPGRADES:
		var entry: Dictionary = UPGRADES[upgrade]
		var owned := truck.has_upgrade(upgrade)
		var locked := _upgrade_requirement(upgrade)
		_update_button(entry, "Installed" if owned else _purchase_label(entry.price, locked),
			owned or entry.price > board.balance or not locked.is_empty())


func _buy_upgrade(upgrade: SnowTruck.Upgrade) -> void:
	if not is_open or not contains_truck() or not truck.can_park() or truck.has_upgrade(upgrade):
		return
	if not _upgrade_requirement(upgrade).is_empty() or not board.try_spend(UPGRADES[upgrade].price):
		return
	truck.upgrades.append(upgrade)
	_feedback.text = "%s installed." % String(UPGRADES[upgrade].name).get_slice(" · ", 0)
	_refresh()


func _attachment_requirement(item: SnowTruck.Attachment) -> String:
	var entry: Dictionary = ATTACHMENTS[item]
	if entry.get("requires_scoop", false) and not truck.owns_scoop:
		return "Requires front scoop"
	return _jobs_requirement(entry.jobs)


func _upgrade_requirement(upgrade: SnowTruck.Upgrade) -> String:
	if upgrade == SnowTruck.Upgrade.HEATED_WHEELS and not truck.has_upgrade(SnowTruck.Upgrade.WINTER_TYRES):
		return "Requires winter tyres"
	if upgrade == SnowTruck.Upgrade.EXTENDED_TANK and not truck.owns_vacuum:
		return "Requires truck vacuum"
	return _jobs_requirement(UPGRADES[upgrade].jobs)


func _jobs_requirement(count: int) -> String:
	return "After %d jobs" % count if board.completed_jobs() < count else ""


func _purchase_label(price: int, locked: String) -> String:
	return "Buy £%d" % price if locked.is_empty() else locked


func _update_button(entry: Dictionary, action: String, disabled: bool) -> void:
	var button := _button(entry)
	button.text = "%s  ·  %s" % [entry.name, action]
	button.disabled = disabled


func _button(entry: Dictionary) -> Button:
	return get_node("%" + String(entry.node))
