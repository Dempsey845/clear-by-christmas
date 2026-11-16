class_name SnowTools
extends Node3D

enum Tool { SHOVEL, SUCTION }

const FIELDS_GROUP := "snow_fields"
const SUCTION_STEP := 0.05
const SNOW_OFFSET := 0.002
const TANK_EPSILON := 0.000001

@export var reach := 3.5
@export var starter_scoop: SnowToolData = preload("res://Tools/Catalog/starter_scoop.tres")

var equipped_scoop: SnowToolData
var equipped_suction: SnowToolData

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
var _suction_volume := 0.0
var _particle_cooldown := 0.0
var _aim_field: SnowField
var _aim_point := Vector3.ZERO
var _stroke: Tween
var _held_position: Vector3
var _aim_query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	equipped_scoop = starter_scoop
	_held_position = $HeldTool.position
	_update_tool_appearance()
	_select_tool(Tool.SHOVEL)
	var ancestor := camera.get_parent()
	while ancestor != null:
		if ancestor is CollisionObject3D:
			_aim_query.exclude = [ancestor.get_rid()]
			break
		ancestor = ancestor.get_parent()


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

	var had_target := _aim_field != null
	_update_aim()
	if _tool == Tool.SUCTION and had_target != (_aim_field != null):
		_update_status()
	marker.visible = _aim_field != null
	if _aim_field != null:
		marker.global_basis = _aim_field.global_basis.orthonormalized()
		marker.global_position = _aim_point + _aim_field.global_basis.y.normalized() * 0.018
	_particle_cooldown = maxf(0.0, _particle_cooldown - delta)

	if _tool == Tool.SHOVEL:
		if Input.is_action_just_pressed("snow_use") and _aim_field != null:
			_use_shovel()
	elif Input.is_action_just_pressed("snow_dump"):
		_suction_elapsed = 0.0
		_dump_suction()
	elif Input.is_action_pressed("snow_use") and _aim_field != null:
		_use_suction(delta)
	else:
		_suction_elapsed = 0.0


func set_indoors(indoors: bool) -> void:
	set_physics_process(not indoors)
	$HeldTool.visible = not indoors
	status.visible = not indoors
	crosshair.visible = not indoors and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if indoors:
		marker.hide()
		powder.emitting = false
		_aim_field = null
		_suction_elapsed = 0.0


func save_state() -> Dictionary:
	return {
		"scoop": String(equipped_scoop.id),
		"suction": String(equipped_suction.id) if equipped_suction != null else "",
		"selected": _tool,
		"carried": _carried_volume,
		"tank": _suction_volume,
	}


func restore_state(state: Dictionary, scoop_tool: SnowToolData, suction_tool: SnowToolData) -> void:
	equipped_scoop = scoop_tool if scoop_tool != null else starter_scoop
	equipped_suction = suction_tool
	_carried_volume = clampf(state.get("carried", 0.0), 0.0, equipped_scoop.capacity_m3())
	_suction_volume = 0.0
	if equipped_suction != null:
		_suction_volume = clampf(state.get("tank", 0.0), 0.0, equipped_suction.capacity_m3())
	_update_tool_appearance()
	_select_tool(Tool.SUCTION if state.get("selected", Tool.SHOVEL) == Tool.SUCTION else Tool.SHOVEL)


func clear_carried_snow() -> void:
	_carried_volume = 0.0
	_suction_volume = 0.0
	_suction_elapsed = 0.0
	_update_status()


func _use_suction(delta: float) -> void:
	var free_volume := _suction_free_volume()
	if free_volume <= TANK_EPSILON:
		return
	_suction_elapsed += delta
	if _suction_elapsed < SUCTION_STEP:
		return
	var amount := _aim_field.cut(
		_aim_point, -camera.global_basis.z, equipped_suction.area,
		equipped_suction.depth * _suction_elapsed, true, free_volume
	)
	_suction_elapsed = 0.0
	if amount > 0.0:
		_suction_volume += amount
		_update_status()
		if _particle_cooldown <= 0.0:
			_emit_powder((suction.global_position - _aim_point).normalized(), true)


func _suction_free_volume() -> float:
	return maxf(0.0, equipped_suction.capacity_m3() - _suction_volume)


func _dump_suction() -> void:
	if _suction_volume <= 0.0 or _aim_field == null:
		return
	if not _aim_field.contains_ground(_aim_point):
		return
	if _aim_field.deposit(_aim_point, equipped_suction.dump_radius, _suction_volume):
		_suction_volume = 0.0
		_emit_powder(Vector3.UP, false)
		_update_status()


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
		if not _aim_field.deposit(_aim_point, equipped_scoop.dump_radius, _carried_volume):
			return
		_carried_volume = 0.0
		_emit_powder(Vector3.UP, false)
	else:
		_carried_volume = _aim_field.cut(
			_aim_point, -camera.global_basis.z, equipped_scoop.area, equipped_scoop.depth,
			false, equipped_scoop.capacity_m3()
		)
		if _carried_volume > 0.0:
			_emit_powder(Vector3.UP + camera.global_basis.z * 0.6, false)
	_animate_shovel()
	_update_status()


func try_equip(tool: SnowToolData) -> bool:
	if tool.kind == SnowToolData.Kind.SCOOP:
		if _carried_volume > 0.0:
			return false
		equipped_scoop = tool
	else:
		if _suction_volume > 0.0:
			return false
		equipped_suction = tool
		_suction_elapsed = 0.0
	_update_tool_appearance()
	_update_status()
	return true


func _update_tool_appearance() -> void:
	_tint_tool($HeldTool/Shovel/Blade, equipped_scoop.color)
	if equipped_suction != null:
		_tint_tool($HeldTool/Suction/Housing, equipped_suction.color)


func _tint_tool(part: MeshInstance3D, color: Color) -> void:
	var material := part.get_active_material(0).duplicate() as StandardMaterial3D
	material.albedo_color = color
	part.material_override = material


func _select_tool(tool: Tool) -> void:
	if tool == Tool.SUCTION and equipped_suction == null:
		tool = Tool.SHOVEL
	_tool = tool
	_suction_elapsed = 0.0
	shovel.visible = tool == Tool.SHOVEL
	suction.visible = tool == Tool.SUCTION
	_update_status()


func _update_status() -> void:
	scoop.visible = _carried_volume > 0.0
	var action := "Click to scoop"
	if _tool == Tool.SUCTION:
		var controls := "LMB Vacuum  ·  RMB Dump"
		if _suction_free_volume() <= TANK_EPSILON:
			controls = "Tank full  ·  RMB Dump" if _aim_field != null else "Tank full  ·  Aim at a snow chunk"
		action = "%.0f / %.0f L  ·  %s" % [_suction_volume * 1000.0, equipped_suction.capacity_litres, controls]
	elif _carried_volume > 0.0:
		action = "Click to dump  ·  %.0f L on shovel" % (_carried_volume * 1000.0)
	var tools := "1  %s" % equipped_scoop.display_name
	if equipped_suction != null:
		tools += "     2  %s" % equipped_suction.display_name
	status.text = "%s\n%s" % [tools, action]


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
