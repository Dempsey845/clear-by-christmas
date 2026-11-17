@tool
class_name ResidentialLot
extends Node3D

@export var site_id: StringName
@export var address: String:
	set(value):
		address = value
		if is_node_ready():
			$Address.text = value
@export var resident: String
@export_range(1, 100) var pay := 14
@export_range(0.03, 0.5, 0.01) var lawn_depth := 0.09

@onready var site: SnowJobSite = $Site


func _ready() -> void:
	$Address.text = address
	if Engine.is_editor_hint():
		return
	site.site_id = site_id
	site.request = SnowJob.new()
	site.request.site_id = site_id
	site.request.address = address
	site.request.client_name = resident
	site.request.pay = pay
	site.request.required_clear_percent = 85
