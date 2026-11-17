class_name TruckGarage
extends Node3D

@onready var _panel: PanelContainer = %Panel
@onready var _standard: Button = %Stock
@onready var _scoop: Button = %Scoop
@onready var _vacuum: Button = %Vacuum
@onready var _feedback: Label = %Feedback

var truck: SnowTruck
var board: JobBoard
var _prior_mouse_mode := Input.MOUSE_MODE_CAPTURED

var is_open: bool:
	get:
		return _panel.visible


func configure(vehicle: SnowTruck, job_board: JobBoard) -> void:
	truck = vehicle
	board = job_board
	_standard.pressed.connect(_select.bind(SnowTruck.Attachment.NONE))
	_scoop.pressed.connect(_select.bind(SnowTruck.Attachment.SCOOP))
	_vacuum.pressed.connect(_select.bind(SnowTruck.Attachment.VACUUM))
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
	var purchased := false
	if item == SnowTruck.Attachment.SCOOP and not truck.owns_scoop:
		if not board.try_spend(SnowTruck.SCOOP_PRICE):
			return
		truck.owns_scoop = true
		purchased = true
	elif item == SnowTruck.Attachment.VACUUM and not truck.owns_vacuum:
		if not board.try_spend(SnowTruck.VACUUM_PRICE):
			return
		truck.owns_vacuum = true
		purchased = true
	truck.equip(item)
	_feedback.text = "Purchased and fitted." if purchased else "Equipment fitted."
	_refresh()


func _refresh() -> void:
	%Balance.text = "Balance  £%d" % board.balance
	_update_button(_standard, "Standard truck", SnowTruck.Attachment.NONE, true, 0)
	_update_button(_scoop, "Front scoop  ·  650 L", SnowTruck.Attachment.SCOOP, truck.owns_scoop, SnowTruck.SCOOP_PRICE)
	_update_button(_vacuum, "Vacuum and bed tank  ·  1,250 L", SnowTruck.Attachment.VACUUM, truck.owns_vacuum, SnowTruck.VACUUM_PRICE)


func _update_button(button: Button, title: String, item: SnowTruck.Attachment, owned: bool, price: int) -> void:
	var fitted := truck.attachment == item
	var action := "Fitted" if fitted else ("Fit" if owned else "Buy  £%d" % price)
	button.text = "%s  ·  %s" % [title, action]
	button.disabled = fitted or truck.cargo > 0.00001 or (not owned and price > board.balance)
