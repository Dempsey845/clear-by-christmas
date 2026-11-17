class_name SnowTruck
extends RigidBody3D

enum Attachment { NONE, SCOOP, VACUUM, BLOWER, WIDE_BUCKET }
enum Upgrade { WINTER_TYRES, HEATED_WHEELS, EXTENDED_TANK }

const PRICE := 18
const PURCHASE_JOBS := 9
const SCOOP_PRICE := 12
const VACUUM_PRICE := 25
const BLOWER_PRICE := 48
const WIDE_BUCKET_PRICE := 72
const CAPACITIES := [0.0, 0.65, 1.25, 0.0, 1.05]
const EXTENDED_CAPACITY := 2.0
const WHEEL_RADIUS := 0.40
const SPRING_LENGTH := 0.56
const TRAVEL := 0.30
const SPRING_RATE := 15500.0
const DAMPING := 2200.0
const PARK_SPEED := 0.7
const SNOW_INTERVAL := 0.10
const HEAT_INTERVAL := 0.15
const MELT_DEPTH_PER_SECOND := 0.055

## Visual scenes use +Y up and -Z forward. Their roots attach directly to the markers in the truck scene.
@export var body_visual: PackedScene
## Center the wheel at its axle and align the axle with local X.
@export var wheel_visual: PackedScene
@export var scoop_visual: PackedScene
@export var vacuum_nozzle_visual: PackedScene
@export var vacuum_tank_visual: PackedScene
@export var blower_visual: PackedScene
@export var wide_bucket_visual: PackedScene
@export var heated_wheel_visual: PackedScene

@onready var camera: Camera3D = $ChaseCamera
@onready var _wheels: Array[Node] = $Suspension.get_children()

var owned := false
var driving := false
var controls_locked := false
var attachment := Attachment.NONE
var owns_scoop := false
var owns_vacuum := false
var owns_blower := false
var owns_wide_bucket := false
var upgrades: Array[int] = []
var heating := false
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
var _blower_model: Node3D
var _wide_bucket_model: Node3D
var _heater_models: Array[Node3D] = []
var _wheel_ground := PackedVector3Array()
var _wheel_loaded := PackedByteArray()
var _heat_elapsed := 0.0
var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_spawn = global_transform
	_query.exclude = [get_rid()]
	_query.collision_mask = 3
	_mount_visual($BodyMount, body_visual)
	for wheel: Node3D in _wheels:
		var hub: Node3D = wheel.get_node("Steer/Roll")
		_mount_visual(hub, wheel_visual)
		_heater_models.append(_mount_visual(hub, heated_wheel_visual))
		_contacts.append(Vector2(SPRING_LENGTH, 0.0))
	_wheel_ground.resize(_wheels.size())
	_wheel_loaded.resize(_wheels.size())
	_scoop_model = _mount_visual($FrontMount/ScoopHinge, scoop_visual)
	_nozzle_model = _mount_visual($FrontMount, vacuum_nozzle_visual)
	_tank_model = _mount_visual($BedMount, vacuum_tank_visual)
	_blower_model = _mount_visual($FrontMount, blower_visual)
	_wide_bucket_model = _mount_visual($FrontMount/ScoopHinge, wide_bucket_visual)
	$ChaseCamera.top_level = true
	_update_attachment()
	_update_heat_visuals()


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
	var winter_tyres := has_upgrade(Upgrade.WINTER_TYRES)
	var grip := 1.68 if winter_tyres else 1.35
	var cornering_grip := 3600.0 if winter_tyres else 3000.0

	for index in _wheels.size():
		_wheel_loaded[index] = 0
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
		if driving and heating and load > 80.0:
			_wheel_ground[index] = contact
			_wheel_loaded[index] = 1
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
		traction -= tire_right * velocity.dot(tire_right) * cornering_grip
		state.apply_force(basis.y * load + traction.limit_length(load * grip), lever)


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
	if controls_locked:
		_collection_time = 0.0
		_heat_elapsed = 0.0
		return
	if has_upgrade(Upgrade.HEATED_WHEELS) and Input.is_action_just_pressed("toggle_wheel_heat"):
		set_heating(not heating)
	if heating:
		_melt_under_wheels(delta)
	if attachment == Attachment.NONE:
		return
	if attachment != Attachment.BLOWER and Input.is_action_just_pressed("snow_dump"):
		_dump_snow()
		_collection_time = 0.0
	elif Input.is_action_pressed("snow_use"):
		_collection_time -= delta
		if _collection_time <= 0.0:
			_collection_time = SNOW_INTERVAL
			if attachment == Attachment.BLOWER:
				_blow_snow()
			else:
				_collect_snow()
	else:
		_collection_time = 0.0


func can_park() -> bool:
	return linear_velocity.length() < PARK_SPEED and angular_velocity.length() < 0.9


func set_driving(active: bool) -> void:
	driving = active
	feedback = ""
	_heat_elapsed = 0.0
	_wheel_loaded.fill(0)
	_update_heat_visuals()
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


func owns_attachment(item: Attachment) -> bool:
	match item:
		Attachment.SCOOP: return owns_scoop
		Attachment.VACUUM: return owns_vacuum
		Attachment.BLOWER: return owns_blower
		Attachment.WIDE_BUCKET: return owns_wide_bucket
	return item == Attachment.NONE


func unlock_attachment(item: Attachment) -> void:
	match item:
		Attachment.SCOOP: owns_scoop = true
		Attachment.VACUUM: owns_vacuum = true
		Attachment.BLOWER: owns_blower = true
		Attachment.WIDE_BUCKET: owns_wide_bucket = true


func has_upgrade(item: Upgrade) -> bool:
	return item in upgrades


func cargo_capacity() -> float:
	if attachment == Attachment.VACUUM and has_upgrade(Upgrade.EXTENDED_TANK):
		return EXTENDED_CAPACITY
	return CAPACITIES[attachment]


func set_heating(enabled: bool) -> void:
	heating = enabled and has_upgrade(Upgrade.HEATED_WHEELS)
	_heat_elapsed = 0.0
	_wheel_loaded.fill(0)
	_update_heat_visuals()


func _update_heat_visuals() -> void:
	for model in _heater_models:
		if model != null:
			model.visible = heating and driving


func _update_attachment() -> void:
	if _scoop_model != null:
		_scoop_model.visible = attachment == Attachment.SCOOP
	if _nozzle_model != null:
		_nozzle_model.visible = attachment == Attachment.VACUUM
	if _tank_model != null:
		_tank_model.visible = attachment == Attachment.VACUUM
	if _blower_model != null:
		_blower_model.visible = attachment == Attachment.BLOWER
	if _wide_bucket_model != null:
		_wide_bucket_model.visible = attachment == Attachment.WIDE_BUCKET


func _melt_under_wheels(delta: float) -> void:
	_heat_elapsed += delta
	if _heat_elapsed < HEAT_INTERVAL:
		return
	var depth := MELT_DEPTH_PER_SECOND * _heat_elapsed
	_heat_elapsed = 0.0
	for field: SnowField in get_tree().get_nodes_in_group("snow_fields"):
		for index in _wheel_ground.size():
			var contact := _wheel_ground[index]
			if _wheel_loaded[index] != 0 and field.contains_ground(contact):
				field.cut(contact, -global_basis.z, Vector2(0.47, 0.72), depth, true)


func _blow_snow() -> void:
	var intake: Vector3 = $Intake.global_position
	var outlet: Vector3 = $BlowerOutlet.global_position
	if _ground_below(intake, 1.1).is_empty() or _ground_below(outlet, 1.6).is_empty():
		return
	var fields := get_tree().get_nodes_in_group("snow_fields")
	for target: SnowField in fields:
		if not target.can_deposit(outlet, 1.05):
			continue
		var removed := 0.0
		for source: SnowField in fields:
			removed += source.cut(intake, -global_basis.z, Vector2(2.60, 1.20), 0.12, false)
		if removed > 0.0:
			target.deposit(outlet, 1.05, removed)
		feedback = ""
		return
	feedback = "Keep the right chute over snowy ground"


func _collect_snow() -> void:
	var remaining := cargo_capacity() - cargo
	if remaining <= 0.00001:
		feedback = "Full · RMB to dump"
		return
	var point := $Intake.global_position as Vector3
	if _ground_below(point, 1.1).is_empty():
		return
	var vacuum := attachment == Attachment.VACUUM
	var size := Vector2(2.35, 1.8) if vacuum else Vector2(2.30, 1.05)
	var depth := 0.095 if vacuum else 0.15
	if attachment == Attachment.WIDE_BUCKET:
		size = Vector2(2.85, 1.35)
		depth = 0.19
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
	var front_dump := attachment == Attachment.SCOOP or attachment == Attachment.WIDE_BUCKET
	var outlet: Marker3D = $Intake if front_dump else $RearOutlet
	var ground := _ground_below(outlet.global_position, 2.0)
	if not ground.is_empty():
		var point: Vector3 = ground.position
		for field: SnowField in get_tree().get_nodes_in_group("snow_fields"):
			if field.contains_ground(point) and field.deposit(point, 0.85, cargo):
				cargo = 0.0
				feedback = "Snow dumped"
				if front_dump:
					$FrontMount/ScoopHinge.rotation.x = -0.85
				return
	feedback = "Position the %s over a snow pile or clearing area" % (
		"bucket" if front_dump else "rear outlet"
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
		"driving": driving, "blower": owns_blower, "wide_bucket": owns_wide_bucket,
		"upgrades": upgrades.duplicate(), "heating": heating,
	}


func restore_state(state: Dictionary) -> void:
	owned = state.get("owned", false) == true
	owns_scoop = owned and state.get("scoop", false) == true
	owns_vacuum = owned and state.get("vacuum", false) == true
	owns_blower = owned and state.get("blower", false) == true
	owns_wide_bucket = owned and state.get("wide_bucket", false) == true
	upgrades.clear()
	var saved_upgrades: Variant = state.get("upgrades", [])
	if owned and saved_upgrades is Array:
		for upgrade: int in Upgrade.values():
			if upgrade in saved_upgrades:
				upgrades.append(upgrade)
	set_heating(state.get("heating", false) == true)
	var item: Variant = state.get("attachment")
	if item == Attachment.SCOOP and owns_scoop:
		equip(Attachment.SCOOP)
	elif item == Attachment.VACUUM and owns_vacuum:
		equip(Attachment.VACUUM)
	elif item == Attachment.BLOWER and owns_blower:
		equip(Attachment.BLOWER)
	elif item == Attachment.WIDE_BUCKET and owns_wide_bucket:
		equip(Attachment.WIDE_BUCKET)
	else:
		equip(Attachment.NONE)
	var volume: Variant = state.get("cargo", 0.0)
	cargo = clampf(volume, 0.0, cargo_capacity()) if volume is float and is_finite(volume) else 0.0
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
