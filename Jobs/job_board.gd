class_name JobBoard
extends Node

signal balance_changed(amount: int)
signal job_completed(job: SnowJob)

const LAST_DAY := 25

@export var player: Node3D
@export var requests: Array[SnowJob]
@export_range(0.0, 10.0, 0.25) var marker_hide_distance := 2.25

@onready var hud: JobHUD = $JobHUD
@onready var marker: Node3D = $JobMarker

var balance := 0
var day := 1
var player_indoors := false
var day_finished: bool:
	get:
		return _request_index >= requests.size()

var _request_index := 0
var _history: Array[Dictionary] = []
var _sites: Dictionary[StringName, SnowJobSite] = {}
var _job: SnowJob
var _site: SnowJobSite
var _starting_volume := 0.0


func _ready() -> void:
	set_physics_process(false)
	hud.accept_requested.connect(accept_job)


func prepare() -> void:
	for node in get_tree().get_nodes_in_group("snow_job_sites"):
		var site := node as SnowJobSite
		if site == null or site.site_id == &"" or not site.prepare():
			continue
		if _sites.has(site.site_id):
			push_warning("Duplicate snow job site: %s" % site.site_id)
			continue
		_sites[site.site_id] = site
	_show_request()


func _physics_process(_delta: float) -> void:
	_update_marker()


func try_spend(amount: int) -> bool:
	if amount <= 0 or amount > balance:
		return false
	_change_balance(-amount)
	return true


func accept_job() -> void:
	if _job != null or day_finished:
		return
	var request := requests[_request_index]
	var site := _sites.get(request.site_id) as SnowJobSite
	if site == null:
		return
	_job = request
	_site = site
	_starting_volume = site.fresh_snow_volume_m3(snow_multiplier())
	for field in site.fields():
		field.snow_amount_changed.connect(_refresh_progress, CONNECT_DEFERRED)
	marker.global_position = site.get_node("MarkerPosition").global_position
	$JobMarker/Address.text = request.address
	hud.show_assignment(request, site.lawn_area_m2(), _starting_volume)
	_update_marker()
	set_physics_process(true)
	_refresh_progress()


func advance_day() -> void:
	if not day_finished or day >= LAST_DAY:
		return
	day += 1
	_request_index = 0
	for field: SnowField in get_tree().get_nodes_in_group("snow_fields"):
		field.reset_snow(snow_multiplier())
	_show_request()


func snow_multiplier() -> float:
	return snow_multiplier_for_day(day)


static func snow_multiplier_for_day(date: int) -> float:
	return 1.0 + (date - 1) * 0.04


func save_state() -> Dictionary:
	return {
		"balance": balance, "day": day, "request_index": _request_index,
		"accepted": _job != null, "history": _history,
	}


func restore_state(state: Dictionary) -> void:
	_clear_assignment()
	day = clampi(state.get("day", 1), 1, LAST_DAY)
	_request_index = clampi(state.get("request_index", 0), 0, requests.size())
	_history.assign(state.get("history", []))
	_change_balance(int(state.get("balance", 0)) - balance)
	hud.clear_notice()
	_show_request()
	if state.get("accepted", false):
		accept_job()


func _show_request() -> void:
	hud.set_day(day, day_finished, LAST_DAY)
	hud.set_history(_history)
	if day_finished:
		hud.show_day_finished(day == LAST_DAY)
		return
	var request := requests[_request_index]
	var site := _sites.get(request.site_id) as SnowJobSite
	if site != null:
		hud.show_offer(request, site.lawn_area_m2(), site.fresh_snow_volume_m3(snow_multiplier()))


func _update_marker() -> void:
	marker.visible = not player_indoors \
		and _site.distance_to_lawn(player.global_position) > marker_hide_distance


func _refresh_progress() -> void:
	if _job == null:
		return
	var remaining := _site.snow_volume_m3()
	var cleared := clampf(1.0 - remaining / _starting_volume, 0.0, 1.0)
	hud.set_progress(cleared, remaining, _job.required_clear_percent)
	if cleared + 0.000001 >= _job.required_clear_percent / 100.0:
		_complete_job()


func _clear_assignment() -> void:
	if _site != null:
		for field in _site.fields():
			field.snow_amount_changed.disconnect(_refresh_progress)
	_job = null
	_site = null
	marker.hide()
	set_physics_process(false)


func _complete_job() -> void:
	var completed := _job
	_clear_assignment()
	_history.append({"day": day, "address": completed.address, "pay": completed.pay})
	_request_index += 1
	_change_balance(completed.pay)
	_show_request()
	hud.notify_payment(completed)
	job_completed.emit(completed)


func _change_balance(amount: int) -> void:
	balance += amount
	hud.set_balance(balance)
	balance_changed.emit(balance)
