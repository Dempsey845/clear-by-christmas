extends Node3D

const SAVE_PATH := "user://clear_by_christmas.save"
const SAVE_VERSION := 1
const INTERACTION_DISTANCE := 1.65

@onready var player: CharacterBody3D = $Player
@onready var movement = $Player/PlayerMovement
@onready var tools: SnowTools = $Player/Head/Camera3D/SnowTools
@onready var board: JobBoard = $JobBoard
@onready var market: ToolMarket = $ToolMarket
@onready var sun: DirectionalLight3D = $DirectionalLight3D
@onready var clock: TownClock = $TownClock
@onready var home_marker: Label3D = $HomeMarker
@onready var doorway: Marker3D = $HomeDoor
@onready var entry: Marker3D = $HomeInterior/Entry
@onready var bed: Marker3D = $HomeInterior/Bedside
@onready var prompt: Label = $HomeHUD/Prompt
@onready var truck: SnowTruck = $SnowTruck
@onready var garage: TruckGarage = $TruckGarage
@onready var call_point: Marker3D = $TelephoneBox/CallPoint

var _indoors := false
var _exit_requested := false
var _truck_cursor_released := false
var _recall_requested := false
var _recall_notice := 0.0


func _ready() -> void:
	board.prepare()
	garage.configure(truck, board)
	clock.configure($WorldEnvironment.environment, sun, board.hud)
	board.hud.phone_toggled.connect(_set_phone_open)
	board.hud.save_requested.connect(_save_game)
	board.hud.load_requested.connect(_load_game)
	if FileAccess.file_exists(SAVE_PATH):
		_load_game()


func _process(delta: float) -> void:
	_recall_notice = maxf(0.0, _recall_notice - delta)
	prompt.text = "" if board.hud.phone_open or garage.is_open else _interaction_prompt()
	home_marker.visible = board.day_finished and board.day < JobBoard.LAST_DAY \
		and not _indoors and not _near(doorway)


func _input(event: InputEvent) -> void:
	if not garage.is_open:
		return
	if event.is_action_pressed("market_interact") or event.is_action_pressed("pause"):
		garage.close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("job_phone"):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if board.hud.phone_open or garage.is_open:
		return
	if truck.driving and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		truck.orbit_camera(event.relative)
	if truck.driving and event.is_action_pressed("pause"):
		_set_truck_cursor_released(not _truck_cursor_released)
		get_viewport().set_input_as_handled()
		return
	if truck.driving and _truck_cursor_released and event.is_action_pressed("snow_use"):
		_set_truck_cursor_released(false)
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("market_interact"):
		return
	if truck.driving:
		if truck.can_park():
			if garage.contains_truck():
				if not _truck_cursor_released:
					garage.open()
			else:
				_exit_requested = true
		else:
			truck.feedback = "Stop the truck before getting out"
		get_viewport().set_input_as_handled()
		return
	if not _indoors and _near(call_point):
		_recall_requested = truck.owned
		get_viewport().set_input_as_handled()
		return
	if _near_truck():
		if truck.owned or board.try_spend(SnowTruck.PRICE):
			truck.owned = true
			_set_driving(true)
		get_viewport().set_input_as_handled()
		return
	if not _indoors and _near(doorway):
		_set_indoors(true)
		movement.place(entry.global_position, 0.0, 0.0)
	elif _indoors and _near(entry):
		_set_indoors(false)
		movement.place(doorway.global_position, PI, 0.0)
	elif _indoors and _near(bed) and board.day_finished and board.day < JobBoard.LAST_DAY:
		board.advance_day()
		clock.set_hour(TownClock.MORNING)
		tools.clear_carried_snow()
		movement.place(bed.global_position, PI, 0.0)
	else:
		return
	get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if truck.global_position.y < -5.0 and not truck.freeze:
		truck.freeze = true
		if truck.driving:
			_set_driving(false)
			movement.place(call_point.global_position, 0.0, 0.0)
	if _recall_requested:
		_recall_requested = false
		if truck.owned and not truck.driving:
			truck.recall()
			_recall_notice = 2.75
	if not _exit_requested:
		return
	_exit_requested = false
	if not truck.driving or not truck.can_park():
		return
	var position: Variant = truck.exit_position(player)
	if position is Vector3:
		_set_driving(false)
		movement.place(position, truck.global_rotation.y, 0.0)
	else:
		truck.feedback = "Park where there’s room to get out"


func _set_driving(active: bool) -> void:
	var collision: CollisionShape3D = $Player/CollisionShape3D
	collision.set_deferred("disabled", active)
	player.visible = not active
	player.velocity = Vector3.ZERO
	movement.set_physics_process(not active)
	movement.controls_locked = active or board.hud.phone_open
	tools.set_available(not active and not _indoors)
	truck.set_driving(active)
	_truck_cursor_released = false
	truck.controls_locked = board.hud.phone_open
	board.player = truck if active else player
	if active and not board.hud.phone_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not active:
		movement.camera.make_current()


func _set_phone_open(open: bool) -> void:
	movement.controls_locked = open or truck.driving
	truck.controls_locked = open or _truck_cursor_released


func _set_truck_cursor_released(released: bool) -> void:
	_truck_cursor_released = released
	truck.controls_locked = released
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if released else Input.MOUSE_MODE_CAPTURED


func _near_truck() -> bool:
	if _indoors:
		return false
	var local := truck.to_local(player.global_position)
	var side := Vector2(absf(local.x), local.z)
	return absf(local.y) < 1.4 and side.distance_to(Vector2(0.95, -0.45)) < 2.0


func _interaction_prompt() -> String:
	if truck.driving:
		var controls := "WASD  Drive  ·  Space  Brake"
		if truck.can_park():
			controls += "  ·  E  Garage" if garage.contains_truck() else "  ·  E  Exit"
		if truck.attachment == SnowTruck.Attachment.NONE:
			controls += "\nPark inside the garage to fit equipment"
		else:
			var action := "Scoop" if truck.attachment == SnowTruck.Attachment.SCOOP else "Vacuum"
			var capacity := float(SnowTruck.CAPACITIES[truck.attachment])
			controls += "\nLMB  %s  ·  RMB  Dump  ·  %.0f / %.0f L" % [
				action, truck.cargo * 1000.0, capacity * 1000.0,
			]
		if not truck.feedback.is_empty():
			controls += "\n" + truck.feedback
		return controls
	if not _indoors and _near(call_point):
		if _recall_notice > 0.0:
			return "Truck returned to the garage"
		return "E   Recall truck to the garage" if truck.owned else "Telephone  ·  Buy the truck to use recovery"
	if _near_truck():
		if truck.owned:
			return "E   Enter truck"
		if board.balance >= SnowTruck.PRICE:
			return "E   Buy and enter truck  ·  £%d" % SnowTruck.PRICE
		return "Truck for sale  ·  £%d  ·  Balance £%d" % [SnowTruck.PRICE, board.balance]
	return _home_prompt()


func _near(marker: Marker3D) -> bool:
	return player.global_position.distance_to(marker.global_position) <= INTERACTION_DISTANCE


func _home_prompt() -> String:
	if not _indoors:
		return "E   Enter your house" if _near(doorway) else ""
	if _near(entry):
		return "E   Go outside"
	if _near(bed):
		if board.day == JobBoard.LAST_DAY and board.day_finished:
			return "Christmas jobs complete"
		return "E   Sleep until morning" if board.day_finished else "Finish today’s jobs before going to sleep"
	return ""


func _set_indoors(indoors: bool) -> void:
	_indoors = indoors
	board.player_indoors = indoors
	tools.set_available(not indoors and not truck.driving)


func _save_game() -> void:
	var snow := {}
	for field: SnowField in get_tree().get_nodes_in_group("snow_fields"):
		snow[String(get_path_to(field))] = field.save_state()
	var state := {
		"version": SAVE_VERSION,
		"jobs": board.save_state(),
		"snow": snow,
		"owned": market.owned_items(),
		"tools": tools.save_state(),
		"position": player.global_position,
		"yaw": player.rotation.y,
		"pitch": movement.camera_pitch,
		"indoors": _indoors,
		"truck": truck.save_state(),
		"hour": clock.hour,
	}
	var temporary_path := SAVE_PATH + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		board.hud.set_save_status("Couldn’t open the save file.")
		return
	var written := file.store_var(state)
	file.close()
	if not written or DirAccess.rename_absolute(temporary_path, SAVE_PATH) != OK:
		board.hud.set_save_status("Couldn’t write the save file.")
		return
	board.hud.set_save_status("Game saved.")


func _load_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		board.hud.set_save_status("No saved game found.")
		return
	var state: Variant = file.get_var()
	if not _is_save(state):
		board.hud.set_save_status("This save couldn’t be loaded.")
		return
	var jobs: Dictionary = state.jobs
	var day := clampi(jobs.get("day", 1), 1, JobBoard.LAST_DAY)
	var multiplier := JobBoard.snow_multiplier_for_day(day)
	for field: SnowField in get_tree().get_nodes_in_group("snow_fields"):
		field.restore_state(state.snow.get(String(get_path_to(field)), {}), multiplier)
	market.restore_items(state.owned, state.tools)
	_set_driving(false)
	_exit_requested = false
	_recall_requested = false
	_recall_notice = 0.0
	_set_indoors(state.indoors)
	movement.place(state.position, state.yaw, state.pitch)
	board.restore_state(jobs)
	var vehicle_save: Variant = state.get("truck")
	var truck_state: Dictionary = vehicle_save if vehicle_save is Dictionary else {}
	truck.restore_state(truck_state)
	if truck.owned and not _indoors and truck_state.get("driving", false) == true:
		_set_driving(true)
	var hour: Variant = state.get("hour", TownClock.MORNING)
	clock.set_hour(hour if hour is float and is_finite(hour) else TownClock.MORNING)
	board.hud.set_save_status("Save loaded.")


func _is_save(state: Variant) -> bool:
	return (state is Dictionary and state.get("version") == SAVE_VERSION
		and state.get("jobs") is Dictionary and state.get("snow") is Dictionary
		and state.get("owned") is Array and state.get("tools") is Dictionary
		and state.get("position") is Vector3 and state.position.is_finite()
		and state.get("yaw") is float and state.get("pitch") is float
		and state.get("indoors") is bool)
