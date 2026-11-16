extends Node3D

enum Tool { SHOVEL, SUCTION }

const FIELDS_GROUP := "snow_fields"
const SUCTION_STEP := 0.05
const SNOW_OFFSET := 0.002

@export var reach := 3.5
@export var shovel_size := Vector2(0.55, 0.64)
@export var scoop_depth := 0.18
@export var dump_radius := 0.44
@export var suction_size := Vector2(0.85, 1.05)
@export var suction_depth_per_second := 0.65

@onready var camera := get_parent() as Camera3D
@onready var shovel: Node3D = $HeldTool/Shovel
@onready var suction: Node3D = $HeldTool/Suction
@onready var scoop: MeshInstance3D = $HeldTool/Shovel/Scoop
@onready var marker: MeshInstance3D = $Target
@onready var powder: CPUParticles3D = $Powder
@onready var status: Label = $HUD/Status
@onready var crosshair: Label = $HUD/Crosshair

var _tool := Tool.SHOVEL
var _carried_volume := 0.0
var _suction_elapsed := 0.0
var _particle_cooldown := 0.0
var _aim_field: SnowField
var _aim_point := Vector3.ZERO
var _stroke: Tween
var _held_position: Vector3
var _aim_query := PhysicsRayQueryParameters3D.new()
var _player: CharacterBody3D
var _spawn_position: Vector3


func _ready() -> void:
	_held_position = $HeldTool.position
	var ancestor := camera.get_parent()
	while ancestor != null:
		if ancestor is CollisionObject3D:
			_aim_query.exclude = [ancestor.get_rid()]
			_player = ancestor as CharacterBody3D
			if _player != null:
				_spawn_position = _player.global_position
			break
		ancestor = ancestor.get_parent()
	_update_status()


func _physics_process(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	crosshair.visible = captured
	if not captured:
		_suction_elapsed = 0.0
		marker.hide()
		return

	if Input.is_action_just_pressed("snow_shovel"):
		_select_tool(Tool.SHOVEL)
	if Input.is_action_just_pressed("snow_suction"):
		_select_tool(Tool.SUCTION)
	if Input.is_action_just_pressed("snow_reset"):
		_reset_snow()

	_update_aim()
	marker.visible = _aim_field != null
	if _aim_field != null:
		marker.global_basis = _aim_field.global_basis.orthonormalized()
		marker.global_position = _aim_point + _aim_field.global_basis.y.normalized() * 0.018
	_particle_cooldown = maxf(0.0, _particle_cooldown - delta)

	if _tool == Tool.SHOVEL:
		if Input.is_action_just_pressed("snow_use") and _aim_field != null:
			_use_shovel()
	elif Input.is_action_pressed("snow_use") and _aim_field != null:
		_use_suction(delta)
	else:
		_suction_elapsed = 0.0


func _reset_snow() -> void:
	var buried := false
	for field: SnowField in get_tree().get_nodes_in_group(FIELDS_GROUP):
		field.reset_snow()
		if _player != null and field.collision_enabled:
			var feet := field.to_local(_player.global_position)
			buried = buried or (feet.y >= -0.02 and field.depth_at(_player.global_position) > feet.y + 0.05)
	if buried:
		_player.global_position = _spawn_position
		_player.reset_physics_interpolation()
		_player.velocity = Vector3.ZERO
	_carried_volume = 0.0
	_suction_elapsed = 0.0
	_update_status()


func _use_suction(delta: float) -> void:
	_suction_elapsed += delta
	if _suction_elapsed < SUCTION_STEP:
		return
	var amount := _aim_field.cut(
		_aim_point, -camera.global_basis.z, suction_size,
		suction_depth_per_second * _suction_elapsed, true
	)
	_suction_elapsed = 0.0
	if amount > 0.00001 and _particle_cooldown <= 0.0:
		_emit_powder((suction.global_position - _aim_point).normalized(), true)


func _update_aim() -> void:
	_aim_field = null
	var start := camera.global_position
	var direction := -camera.global_basis.z
	_aim_query.from = start
	_aim_query.to = start + direction * reach
	var hit := get_world_3d().direct_space_state.intersect_ray(_aim_query)
	var limit := reach
	if not hit.is_empty():
		limit = start.distance_to(hit.position)

	for field: SnowField in get_tree().get_nodes_in_group(FIELDS_GROUP):
		var local_start := field.to_local(start)
		var local_ray := field.global_basis.inverse() * direction
		if local_ray.y >= -0.01 or local_start.y < 0.0:
			continue
		var ground_distance := -local_start.y / local_ray.y
		var tolerance := 0.003 if _aim_field == null and not hit.is_empty() else 0.0
		var end := minf(ground_distance, limit + tolerance)
		if not field.overlaps_ray_footprint(local_start, local_start + local_ray * end):
			continue
		var step := field.spacing * 0.5
		var distance := 0.0
		var previous := 0.0
		while distance <= end:
			var point := start + direction * distance
			var depth := field.depth_at(point)
			if depth >= 0.006 and local_start.y + local_ray.y * distance <= depth + SNOW_OFFSET:
				var low := previous
				var high := distance
				for pass_index in 5:
					var middle := (low + high) * 0.5
					var sample := start + direction * middle
					var sample_depth := field.depth_at(sample)
					if sample_depth >= 0.006 and local_start.y + local_ray.y * middle <= sample_depth + SNOW_OFFSET:
						high = middle
					else:
						low = middle
				limit = high
				_aim_field = field
				_aim_point = start + direction * high
				break
			if distance == end:
				break
			previous = distance
			distance = minf(distance + step, end)

		if _aim_field == field:
			continue
		if ground_distance <= end and field.contains_ground(start + direction * ground_distance):
			limit = ground_distance
			_aim_field = field
			_aim_point = start + direction * ground_distance


func _use_shovel() -> void:
	if _carried_volume > 0.0:
		if not _aim_field.deposit(_aim_point, dump_radius, _carried_volume):
			return
		_carried_volume = 0.0
		_emit_powder(Vector3.UP, false)
	else:
		_carried_volume = _aim_field.cut(_aim_point, -camera.global_basis.z, shovel_size, scoop_depth, false)
		if _carried_volume > 0.0:
			_emit_powder(Vector3.UP + camera.global_basis.z * 0.6, false)
	_animate_shovel()
	_update_status()


func _select_tool(tool: Tool) -> void:
	_tool = tool
	_suction_elapsed = 0.0
	shovel.visible = tool == Tool.SHOVEL
	suction.visible = tool == Tool.SUCTION
	_update_status()


func _update_status() -> void:
	scoop.visible = _carried_volume > 0.0
	var action := "Click to scoop"
	if _tool == Tool.SUCTION:
		action = "Hold left click to vacuum"
	elif _carried_volume > 0.0:
		action = "Click to dump  ·  %.0f L on shovel" % (_carried_volume * 1000.0)
	status.text = "1  Shovel     2  Suction     R  Reset snow\n" + action


func _animate_shovel() -> void:
	if _stroke != null:
		_stroke.kill()
	_stroke = create_tween()
	_stroke.tween_property($HeldTool, "position", _held_position + Vector3(0.0, -0.07, -0.23), 0.08)
	_stroke.tween_property($HeldTool, "position", _held_position, 0.20).set_ease(Tween.EASE_OUT)


func _emit_powder(direction: Vector3, is_suction: bool) -> void:
	powder.global_position = _aim_point + Vector3.UP * 0.025
	powder.direction = direction.normalized()
	powder.spread = 13.0 if is_suction else 46.0
	powder.gravity = Vector3.ZERO if is_suction else Vector3.DOWN * 6.0
	powder.initial_velocity_min = 3.0 if is_suction else 0.7
	powder.initial_velocity_max = 5.0 if is_suction else 2.0
	powder.lifetime = minf(0.45, _aim_point.distance_to(suction.global_position) / 5.0) if is_suction else 0.48
	powder.lifetime = maxf(0.08, powder.lifetime)
	powder.restart()
	powder.emitting = true
	_particle_cooldown = 0.16
