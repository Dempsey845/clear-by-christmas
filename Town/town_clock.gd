class_name TownClock
extends Node

const MORNING := 8.0

@export_range(1.0, 90.0, 0.5) var cycle_minutes := 20.0

var hour := MORNING
var _environment: Environment
var _sky: ShaderMaterial
var _sun: DirectionalLight3D
var _hud: JobHUD
var _lamps: Array[Node] = []
var _last_minute := -1
var _lighting_time := 0.0


func configure(environment: Environment, sun: DirectionalLight3D, hud: JobHUD) -> void:
	_environment = environment
	_sky = environment.sky.sky_material as ShaderMaterial
	_sun = sun
	_hud = hud
	_lamps = get_tree().get_nodes_in_group("street_lights")
	set_hour(MORNING)


func _process(delta: float) -> void:
	if _sky == null:
		return
	hour = fposmod(hour + delta * 24.0 / (cycle_minutes * 60.0), 24.0)
	_lighting_time += delta
	if _lighting_time >= 0.08:
		_lighting_time = 0.0
		_update_lighting()


func set_hour(value: float) -> void:
	hour = fposmod(value, 24.0)
	_update_lighting()


func _update_lighting() -> void:
	var angle := (hour - 6.0) * TAU / 24.0
	var direction := Vector3(cos(angle) * 0.88, sin(angle) * 0.55, -0.47).normalized()
	var daylight := smoothstep(-0.11, 0.26, direction.y)
	var direct := smoothstep(-0.03, 0.46, direction.y)
	_sky.set_shader_parameter("sun_direction", direction)
	_sky.set_shader_parameter("daylight", daylight)
	_sun.basis = Basis.looking_at(-direction)
	_sun.light_energy = direct * 1.18
	_sun.light_color = Color(1.0, 0.61, 0.39).lerp(Color(1.0, 0.94, 0.82), direct)
	_environment.ambient_light_color = Color(0.28, 0.42, 0.74).lerp(Color(0.78, 0.86, 1.0), daylight)
	_environment.ambient_light_energy = lerpf(0.32, 0.64, daylight)
	for lamp: OmniLight3D in _lamps:
		lamp.light_energy = 1.12 * (1.0 - daylight)
		lamp.visible = daylight < 0.99
	var minutes := floori(hour * 60.0)
	if minutes != _last_minute:
		_last_minute = minutes
		@warning_ignore("integer_division")
		_hud.set_clock("%02d:%02d" % [minutes / 60, minutes % 60])
