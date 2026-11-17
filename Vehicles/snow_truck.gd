class_name SnowTruck
extends RigidBody3D

enum Attachment { NONE, SCOOP, VACUUM }

const PRICE := 18
const SCOOP_PRICE := 12
const VACUUM_PRICE := 25
const CAPACITIES := [0.0, 0.65, 1.25]
const WHEEL_RADIUS := 0.40
const SPRING_LENGTH := 0.56
const TRAVEL := 0.30
const SPRING_RATE := 15500.0
const DAMPING := 2200.0
const PARK_SPEED := 0.7
const SNOW_INTERVAL := 0.10

## Visual scenes use +Y up and -Z forward. Their roots attach directly to the markers in the truck scene.
@export var body_visual: PackedScene
## Center the wheel at its axle and align the axle with local X.
@export var wheel_visual: PackedScene
@export var scoop_visual: PackedScene
@export var vacuum_nozzle_visual: PackedScene
@export var vacuum_tank_visual: PackedScene

@onready var camera: Camera3D = $ChaseCamera
@onready var _wheels: Array[Node] = $Suspension.get_children()

var owned := false
var driving := false
var controls_locked := false
var attachment := Attachment.NONE
var owns_scoop := false
var owns_vacuum := false
var cargo := 0.0
var feedback := ""

var _spawn: Transform3D
var _contacts: Array[Vector2] = []
var _steer := 0.0
var _collection_time := 0.0
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _orbit_delay := 0.0
var _scoop_model: Node3D
var _nozzle_model: Node3D
var _tank_model: Node3D
var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_spawn = global_transform
	_query.exclude = [get_rid()]
	_query.collision_mask = 3
	_mount_visual($BodyMount, body_visual)
	for wheel: Node3D in _wheels:
		_mount_visual(wheel.get_node("Steer/Roll"), wheel_visual)
		_contacts.append(Vector2(SPRING_LENGTH, 0.0))
	_scoop_model = _mount_visual($FrontMount/ScoopHinge, scoop_visual)
	_nozzle_model = _mount_visual($FrontMount, vacuum_nozzle_visual)
	_tank_model = _mount_visual($BedMount, vacuum_tank_visual)
	$ChaseCamera.top_level = true
	_update_attachment()


func _mount_visual(mount: Node3D, scene: PackedScene) -> Node3D:
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	mount.add_child(model)
	return model


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var active := driving and not controls_locked
	var throttle := Input.get_axis("move_backward", "move_forward") if active else 0.0
	var steering := Input.get_axis("move_right", "move_left") if active else 0.0
	var brake := not active or Input.is_action_pressed("jump")
	var basis := state.transform.basis
	var forward := -basis.z
	var speed := state.linear_velocity.dot(forward)
	var limit := lerpf(0.54, 0.24, clampf(absf(speed) / 12.0, 0.0, 1.0))
	_steer = move_toward(_steer, steering * limit, state.step * 2.7)

	for index in _wheels.size():
		var wheel := _wheels[index] as Node3D
		var anchor := state.transform * wheel.position
		var steer := _steer if wheel.position.z < 0.0 else 0.0
		var tire_forward := forward.rotated(basis.y, steer)
		_query.from = anchor
		_query.to = anchor - basis.y * (SPRING_LENGTH + TRAVEL + WHEEL_RADIUS)
		var hit := state.get_space_state().intersect_ray(_query)
		if hit.is_empty() or basis.y.dot(hit.normal) < 0.30:
			_contacts[index] = Vector2(SPRING_LENGTH + TRAVEL, speed)
			continue

		var contact: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		var length := maxf(0.0, anchor.distance_to(contact) - WHEEL_RADIUS)
		var lever := contact - state.transform.origin
		var velocity := state.get_velocity_at_local_position(lever)
		# Apply spring load and tire grip at each contact so they can pitch and roll the chassis.
		var load := clampf(
			(SPRING_LENGTH - length) * SPRING_RATE - velocity.dot(basis.y) * DAMPING,
			0.0, 13000.0
		)
		_contacts[index].x = length
		tire_forward = tire_forward.slide(normal).normalized()
		var tire_right := tire_forward.cross(normal).normalized()
		var rolling_speed := velocity.dot(tire_forward)
		_contacts[index].y = rolling_speed
		var motor := 3100.0 * throttle
		var top_speed := 14.0 if throttle >= 0.0 else 6.0
		motor *= 1.0 - smoothstep(top_speed * 0.55, top_speed, rolling_speed * signf(throttle))
		var rolling_drag := 125.0 if not is_zero_approx(throttle) else 420.0
		if brake:
			motor = 0.0
			rolling_drag = 3600.0
		var traction := tire_forward * (motor - rolling_speed * rolling_drag)
		traction -= tire_right * velocity.dot(tire_right) * 3000.0
		state.apply_force(basis.y * load + traction.limit_length(load * 1.35), lever)


func _physics_process(delta: float) -> void:
	for index in _wheels.size():
		var wheel := _wheels[index] as Node3D
		var hub: Node3D = wheel.get_node("Steer")
		hub.position.y = -move_toward(-hub.position.y, _contacts[index].x, delta * 8.0)
		hub.rotation.y = _steer if wheel.position.z < 0.0 else 0.0
		hub.get_node("Roll").rotate_x(-_contacts[index].y * delta / WHEEL_RADIUS)

	var hinge: Node3D = $FrontMount/ScoopHinge
	hinge.rotation.x = move_toward(hinge.rotation.x, 0.0, delta * 2.4)
	if not driving:
		return
	_update_camera(delta)
	if controls_locked or attachment == Attachment.NONE:
		_collection_time = 0.0
		return
	if Input.is_action_just_pressed("snow_dump"):
		_dump_snow()
		_collection_time = 0.0
	elif Input.is_action_pressed("snow_use"):
		_collection_time -= delta
		if _collection_time <= 0.0:
			_collection_time = SNOW_INTERVAL
			_collect_snow()
	else:
		_collection_time = 0.0


func can_park() -> bool:
	return linear_velocity.length() < PARK_SPEED and angular_velocity.length() < 0.9


func set_driving(active: bool) -> void:
	driving = active
	feedback = ""
	if active:
		sleeping = false
		_orbit_yaw = 0.0
		_orbit_pitch = 0.0
		_orbit_delay = 0.0
		camera.make_current()


func orbit_camera(relative: Vector2) -> void:
	_orbit_yaw = wrapf(_orbit_yaw - relative.x * 0.003, -PI, PI)
	_orbit_pitch = clampf(_orbit_pitch + relative.y * 0.003, -0.24, 0.62)
	_orbit_delay = 2.0


func _update_camera(delta: float) -> void:
	_orbit_delay = maxf(_orbit_delay - delta, 0.0)
	if _orbit_delay == 0.0 and linear_velocity.length() > 1.0:
		_orbit_yaw = lerp_angle(_orbit_yaw, 0.0, 1.0 - exp(-delta * 2.5))
		_orbit_pitch = lerpf(_orbit_pitch, 0.0, 1.0 - exp(-delta * 2.5))
	var back := Vector3(global_basis.z.x, 0.0, global_basis.z.z).normalized()
	if back.is_zero_approx():
		back = Vector3.BACK
	back = back.rotated(Vector3.UP, _orbit_yaw)
	var target := global_position + Vector3.UP * 1.25
	var direction := back * cos(0.31 + _orbit_pitch) + Vector3.UP * sin(0.31 + _orbit_pitch)
	_query.from = target
	_query.to = target + direction * 6.4
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	var distance := 6.4 if hit.is_empty() else maxf(0.1, target.distance_to(hit.position) - 0.20)
	camera.global_position = target + direction * distance
	camera.look_at(target)


func exit_position(player: CharacterBody3D) -> Variant:
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = 3
	ray.exclude = [get_rid(), player.get_rid()]
	var clearance := PhysicsShapeQueryParameters3D.new()
	clearance.shape = player.get_node("CollisionShape3D").shape
	clearance.exclude = [player.get_rid()]
	clearance.collision_mask = 7
	for offset in [Vector3(1.7, 0, 0), Vector3(-1.7, 0, 0), Vector3(0, 0, 2.9), Vector3(0, 0, -2.9)]:
		var side := to_global(offset)
		ray.from = side + Vector3.UP * 0.9
		ray.to = side + Vector3.DOWN * 1.6
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < 0.6:
			continue
		var point: Vector3 = hit.position + Vector3.UP * 0.04
		clearance.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP)
		if space.intersect_shape(clearance, 1).is_empty():
			return point
	return null


func equip(item: Attachment) -> void:
	attachment = item
	feedback = ""
	_update_attachment()


func _update_attachment() -> void:
	if _scoop_model != null:
		_scoop_model.visible = attachment == Attachment.SCOOP
	if _nozzle_model != null:
		_nozzle_model.visible = attachment == Attachment.VACUUM
	if _tank_model != null:
		_tank_model.visible = attachment == Attachment.VACUUM


func _collect_snow() -> void:
	var remaining := float(CAPACITIES[attachment]) - cargo
	if remaining <= 0.00001:
		feedback = "Full · RMB to dump"
		return
	var point := $Intake.global_position as Vector3
	if _ground_below(point, 1.1).is_empty():
		return
	var vacuum := attachment == Attachment.VACUUM
	var size := Vector2(2.35, 1.8) if vacuum else Vector2(2.30, 1.05)
	var depth := 0.095 if vacuum else 0.15
	for field: SnowField in get_tree().get_nodes_in_group("snow_fields"):
		var removed := field.cut(point, -global_basis.z, size, depth, vacuum, remaining)
		cargo += removed
		remaining -= removed
		if remaining <= 0.00001:
			break
	feedback = ""


func _dump_snow() -> void:
	if cargo <= 0.00001:
		feedback = "No snow to dump"
		return
	var outlet: Marker3D = $Intake if attachment == Attachment.SCOOP else $RearOutlet
	var ground := _ground_below(outlet.global_position, 2.0)
	if not ground.is_empty():
		var point: Vector3 = ground.position
		for field: SnowField in get_tree().get_nodes_in_group("snow_fields"):
			if field.contains_ground(point) and field.deposit(point, 0.85, cargo):
				cargo = 0.0
				feedback = "Snow dumped"
				if attachment == Attachment.SCOOP:
					$FrontMount/ScoopHinge.rotation.x = -0.85
				return
	feedback = "Position the %s over a snow pile or clearing area" % (
		"scoop" if attachment == Attachment.SCOOP else "rear outlet"
	)


func _ground_below(point: Vector3, reach: float) -> Dictionary:
	_query.from = point + Vector3.UP * 0.38
	_query.to = point + Vector3.DOWN * reach
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty() or hit.normal.y < 0.30:
		return {}
	return hit


func save_state() -> Dictionary:
	return {
		"owned": owned, "scoop": owns_scoop, "vacuum": owns_vacuum,
		"attachment": attachment, "cargo": cargo, "transform": global_transform,
		"driving": driving,
	}


func restore_state(state: Dictionary) -> void:
	owned = state.get("owned", false) == true
	owns_scoop = owned and state.get("scoop", false) == true
	owns_vacuum = owned and state.get("vacuum", false) == true
	var item: Variant = state.get("attachment")
	if item == Attachment.SCOOP and owns_scoop:
		equip(Attachment.SCOOP)
	elif item == Attachment.VACUUM and owns_vacuum:
		equip(Attachment.VACUUM)
	else:
		equip(Attachment.NONE)
	var volume: Variant = state.get("cargo", 0.0)
	cargo = clampf(volume, 0.0, CAPACITIES[attachment]) if volume is float and is_finite(volume) else 0.0
	var parked_at: Variant = state.get("transform")
	if owned and parked_at is Transform3D and parked_at.is_finite():
		_place_truck(parked_at)
	else:
		recall()


func recall() -> void:
	_place_truck(_spawn)
	feedback = ""


func _place_truck(location: Transform3D) -> void:
	freeze = location.origin.y < -5.0
	global_transform = location
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
