class_name SnowJob
extends Resource

@export var site_id: StringName
@export var client_name: String
@export var address: String
@export_range(1, 10000) var pay: int = 25
@export_range(50, 100) var required_clear_percent: int = 95
