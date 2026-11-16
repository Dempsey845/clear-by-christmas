extends Node

@export_category("Movement")
@export var move_speed: float = 7.0
@export var ground_acceleration: float = 35.0
@export var ground_deceleration: float = 30.0
@export var air_acceleration: float = 10.0

@export_category("Snow")
@export_range(0.0, 0.6, 0.01) var max_snow_step_height := 0.34
@export_range(0.0, 1.0, 0.01) var snow_step_reach := 0.50
@export_range(0.2, 1.5, 0.01) var footprint_stride := 0.63
@export var footprint_size := Vector2(0.30, 0.42)
@export_range(0.0, 0.12, 0.005) var footprint_depth := 0.055

@export_category("Jump")
@export var jump_velocity: float = 7.0
@export var gravity: float = 22.0
@export var fall_gravity_multiplier: float = 1.4
@export var jump_cut_multiplier: float = 2.5

@export_category("Camera")
@export var mouse_sensitivity: float = 0.0025
@export var controller_look_sensitivity: float = 2.5
@export var minimum_pitch: float = -85.0
@export var maximum_pitch: float = 85.0

@onready var camera: Camera3D = %Camera3D
@onready var head: Node3D = %Head
@onready var body: CharacterBody3D = get_parent()

@export var camera_offset_speed: float = 6.0

var default_camera_position: Vector3

var camera_pitch: float = 0.0
var controls_locked := false

var _head_rest_position: Vector3
var _step_camera_offset := Vector3.ZERO
var _step_collision := KinematicCollision3D.new()
var _footprint_ray := PhysicsRayQueryParameters3D.new()
var _distance_since_print := 0.0
var _foot_side := -1.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	default_camera_position = camera.position
	_head_rest_position = head.position
	_footprint_ray.exclude = [body.get_rid()]
	_footprint_ray.collision_mask = body.collision_mask


func _unhandled_input(event: InputEvent) -> void:
	if controls_locked:
		return
	if (
		OS.has_feature("web")
		and not get_tree().paused
		and event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera(
			event.relative.x * mouse_sensitivity,
			event.relative.y * mouse_sensitivity
			)
	if event.is_action_pressed("pause"):
		_toggle_mouse_capture()


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_update_camera_offset(delta)
	if not controls_locked:
		_apply_controller_look(delta)
		_handle_jump()
	_handle_movement(delta)

	var start := body.global_position
	if not _try_snow_step(delta):
		body.move_and_slide()
	_leave_footprint(start)

	_step_camera_offset *= exp(-camera_offset_speed * delta)
	head.position = _head_rest_position + body.global_basis.inverse() * _step_camera_offset


func _try_snow_step(delta: float) -> bool:
	if not body.is_on_floor() or body.velocity.y > 0.0 or max_snow_step_height <= 0.0:
		return false

	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z) * delta
	if horizontal.length_squared() < 0.000001:
		return false
	var start := body.global_transform
	if not body.test_move(start, horizontal, _step_collision):
		return false
	if _snow_field_for(_step_collision.get_collider()) == null:
		return false
	if _step_collision.get_angle(0, Vector3.UP) <= body.floor_max_angle:
		return false

	# Sweep the whole player up, across, then down so steps respect walls and ceilings.
	var lift := Vector3.UP * (max_snow_step_height + body.safe_margin)
	if body.test_move(start, lift):
		return false
	var landing := start.translated(lift)
	var approach := horizontal + horizontal.normalized() * snow_step_reach
	if body.test_move(landing, approach):
		return false
	landing.origin += approach
	if not body.test_move(landing, -lift, _step_collision):
		return false
	if _step_collision.get_angle(0, Vector3.UP) > body.floor_max_angle:
		return false

	landing.origin += _step_collision.get_travel()
	var rise := landing.origin.y - start.origin.y
	if rise <= body.safe_margin or rise > max_snow_step_height:
		return false

	body.global_position = landing.origin
	var velocity := body.velocity
	body.velocity = Vector3.DOWN * 0.5
	body.move_and_slide()
	body.velocity.x = velocity.x
	body.velocity.z = velocity.z
	_step_camera_offset += start.origin - body.global_position
	return true


func _leave_footprint(start: Vector3) -> void:
	if not body.is_on_floor() or footprint_depth <= 0.0:
		_distance_since_print = 0.0
		return

	var travel := body.global_position - start
	travel.y = 0.0
	var distance := travel.length()
	if distance < 0.001:
		return
	_distance_since_print += distance
	if _distance_since_print < footprint_stride:
		return
	_distance_since_print -= footprint_stride

	var forward := travel / distance
	var foot := body.global_position + forward.cross(Vector3.UP) * (_foot_side * 0.16)
	_foot_side *= -1.0
	_footprint_ray.from = foot + Vector3.UP * 0.12
	_footprint_ray.to = foot + Vector3.DOWN * 0.22
	var hit := body.get_world_3d().direct_space_state.intersect_ray(_footprint_ray)
	if hit.is_empty():
		return
	var field := _snow_field_for(hit.collider)
	if field != null:
		field.stamp_footprint(hit.position, forward, footprint_size, footprint_depth)


func _snow_field_for(collider: Object) -> SnowField:
	if collider is not StaticBody3D:
		return null
	var chunk := collider.get_parent() as SnowChunk
	return chunk.get_parent() as SnowField if chunk != null else null


func _handle_movement(delta: float) -> void:
	var input_direction: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	) if not controls_locked else Vector2.ZERO

	var local_direction: Vector3 = Vector3(
		input_direction.x,
		0.0,
		input_direction.y
	)

	var move_direction: Vector3 = (
		body.global_basis * local_direction
	).normalized()

	var current_move_speed: float = move_speed

	var target_velocity: Vector3 = move_direction * current_move_speed

	var acceleration: float

	if not body.is_on_floor():
		acceleration = air_acceleration
	elif move_direction.length_squared() > 0.0:
		acceleration = ground_acceleration
	else:
		acceleration = ground_deceleration

	body.velocity.x = move_toward(
		body.velocity.x,
		target_velocity.x,
		acceleration * delta
	)

	body.velocity.z = move_toward(
		body.velocity.z,
		target_velocity.z,
		acceleration * delta
	)


func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and body.is_on_floor():
		body.velocity.y = jump_velocity

	if (
		Input.is_action_just_released("jump")
		and body.velocity.y > 0.0
	):
		body.velocity.y /= jump_cut_multiplier


func _apply_gravity(delta: float) -> void:
	if body.is_on_floor():
		body.velocity.y = minf(body.velocity.y, -0.5)

		return

	var current_gravity: float = gravity

	if body.velocity.y < 0.0:
		current_gravity *= fall_gravity_multiplier

	body.velocity.y -= current_gravity * delta


func _apply_controller_look(delta: float) -> void:
	var look_input: Vector2 = Input.get_vector(
		"look_left",
		"look_right",
		"look_up",
		"look_down"
	)

	if look_input.length_squared() <= 0.0:
		return

	_rotate_camera(
		look_input.x * controller_look_sensitivity * delta,
		look_input.y * controller_look_sensitivity * delta
	)


func _rotate_camera(
	yaw_amount: float,
	pitch_amount: float
) -> void:
	body.rotate_y(-yaw_amount)

	camera_pitch -= pitch_amount
	camera_pitch = clamp(
		camera_pitch,
		deg_to_rad(minimum_pitch),
		deg_to_rad(maximum_pitch)
	)

	head.rotation.x = camera_pitch

func _update_camera_offset(delta: float) -> void:
	var target_position := default_camera_position

	var weight := 1.0 - exp(-camera_offset_speed * delta)

	camera.position = camera.position.lerp(
		target_position,
		weight
	)

func _toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED



func place(position: Vector3, yaw: float, pitch: float) -> void:
	body.global_position = position
	body.rotation.y = yaw
	body.velocity = Vector3.ZERO
	camera_pitch = pitch
	head.rotation.x = pitch
	_step_camera_offset = Vector3.ZERO
	_distance_since_print = 0.0
	head.position = _head_rest_position
	body.reset_physics_interpolation()
