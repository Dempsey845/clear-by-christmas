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
@onready var sky_material: ProceduralSkyMaterial = $WorldEnvironment.environment.sky.sky_material
@onready var home_marker: Label3D = $HomeMarker
@onready var doorway: Marker3D = $HomeDoor
@onready var entry: Marker3D = $HomeInterior/Entry
@onready var bed: Marker3D = $HomeInterior/Bedside
@onready var prompt: Label = $HomeHUD/Prompt

var _indoors := false
var _day_sky: Color
var _day_horizon: Color


func _ready() -> void:
	_day_sky = sky_material.sky_top_color
	_day_horizon = sky_material.sky_horizon_color
	board.prepare()
	board.job_completed.connect(func(_job: SnowJob) -> void: _update_lighting())
	board.hud.phone_toggled.connect(func(open: bool) -> void: movement.controls_locked = open)
	board.hud.save_requested.connect(_save_game)
	board.hud.load_requested.connect(_load_game)
	if FileAccess.file_exists(SAVE_PATH):
		_load_game()
	_update_lighting()


func _process(_delta: float) -> void:
	prompt.text = "" if board.hud.phone_open else _home_prompt()
	home_marker.visible = board.day_finished and board.day < JobBoard.LAST_DAY \
		and not _indoors and not _near(doorway)


func _unhandled_input(event: InputEvent) -> void:
	if board.hud.phone_open or not event.is_action_pressed("market_interact"):
		return
	if not _indoors and _near(doorway):
		_set_indoors(true)
		movement.place(entry.global_position, 0.0, 0.0)
	elif _indoors and _near(entry):
		_set_indoors(false)
		movement.place(doorway.global_position, PI, 0.0)
	elif _indoors and _near(bed) and board.day_finished and board.day < JobBoard.LAST_DAY:
		board.advance_day()
		tools.clear_carried_snow()
		movement.place(bed.global_position, PI, 0.0)
		_update_lighting()
	else:
		return
	get_viewport().set_input_as_handled()


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
	tools.set_indoors(indoors)


func _update_lighting() -> void:
	var night := board.day_finished
	sun.light_energy = 0.23 if night else 1.0
	sky_material.sky_top_color = Color(0.06, 0.09, 0.20) if night else _day_sky
	sky_material.sky_horizon_color = Color(0.18, 0.22, 0.36) if night else _day_horizon
	sky_material.ground_horizon_color = sky_material.sky_horizon_color


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
	_set_indoors(state.indoors)
	movement.place(state.position, state.yaw, state.pitch)
	board.restore_state(jobs)
	_update_lighting()
	board.hud.set_save_status("Save loaded.")


func _is_save(state: Variant) -> bool:
	return (state is Dictionary and state.get("version") == SAVE_VERSION
		and state.get("jobs") is Dictionary and state.get("snow") is Dictionary
		and state.get("owned") is Array and state.get("tools") is Dictionary
		and state.get("position") is Vector3 and state.position.is_finite()
		and state.get("yaw") is float and state.get("pitch") is float
		and state.get("indoors") is bool)
