class_name JobBoard
extends Node

signal balance_changed(amount: int)
signal job_completed(job: SnowJob)

@export var player: Node3D
@export var requests: Array[SnowJob]
@export_range(0.0, 10.0, 0.25) var marker_hide_distance := 2.25
@export_range(0.5, 15.0, 0.5) var next_job_delay := 4.0

@onready var hud: JobHUD = $JobHUD
@onready var marker: Node3D = $JobMarker
@onready var next_request: Timer = $NextRequest

var balance: int:
	get:
		return _balance

var _balance := 0
var _next_index := 0
var _sites: Dictionary[StringName, SnowJobSite] = {}
var _job: SnowJob
var _site: SnowJobSite
var _starting_volume := 0.0


func _ready() -> void:
	set_physics_process(false)
	hud.set_balance(balance)
	next_request.timeout.connect(_assign_next)
	_find_sites.call_deferred()


func _physics_process(_delta: float) -> void:
	_update_marker()


func try_spend(amount: int) -> bool:
	if amount <= 0 or amount > balance:
		return false
	_change_balance(-amount)
	return true


func _find_sites() -> void:
	for node in get_tree().get_nodes_in_group("snow_job_sites"):
		var site := node as SnowJobSite
		if site == null or site.site_id == &"" or not site.prepare():
			continue
		if _sites.has(site.site_id):
			push_warning("Duplicate snow job site: %s" % site.site_id)
			continue
		_sites[site.site_id] = site
	_assign_next()


func _assign_next() -> void:
	while _next_index < requests.size():
		var request := requests[_next_index]
		_next_index += 1
		if request == null:
			continue
		var site := _sites.get(request.site_id) as SnowJobSite
		if site == null:
			push_warning("Missing snow job site: %s" % request.site_id)
			continue
		var volume := site.snow_volume_m3()
		if volume > 0.01:
			_start_job(request, site, volume)
			return
	hud.show_no_requests()


func _start_job(request: SnowJob, site: SnowJobSite, volume: float) -> void:
	_job = request
	_site = site
	_starting_volume = volume
	for field in site.fields():
		# Read progress after every part of a snow edit has been applied.
		field.snow_amount_changed.connect(_refresh_progress, CONNECT_DEFERRED)
	marker.global_position = site.get_node("MarkerPosition").global_position
	$JobMarker/Address.text = request.address
	hud.show_assignment(request, site.lawn_area_m2(), site.chunk_count(), volume)
	_update_marker()
	set_physics_process(true)


func _update_marker() -> void:
	marker.visible = is_instance_valid(player) and _site.distance_to_lawn(player.global_position) > marker_hide_distance


func _refresh_progress() -> void:
	if _job == null:
		return
	var remaining := _site.snow_volume_m3()
	var cleared := clampf(1.0 - remaining / _starting_volume, 0.0, 1.0)
	hud.set_progress(cleared, remaining, _job.required_clear_percent)
	if cleared + 0.000001 >= _job.required_clear_percent / 100.0:
		_complete_job()


func _complete_job() -> void:
	var completed := _job
	for field in _site.fields():
		field.snow_amount_changed.disconnect(_refresh_progress)
	_job = null
	_site = null
	marker.hide()
	set_physics_process(false)

	_change_balance(completed.pay)
	hud.show_completed(completed)
	job_completed.emit(completed)
	next_request.start(next_job_delay)


func _change_balance(amount: int) -> void:
	_balance += amount
	hud.set_balance(balance)
	balance_changed.emit(balance)
