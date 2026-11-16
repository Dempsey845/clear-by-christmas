class_name SnowToolData
extends Resource

enum Kind { SCOOP, SUCTION }

@export var id: StringName
@export var display_name: String
@export var kind: Kind
@export_range(0, 10000) var price: int
@export var area := Vector2(0.55, 0.64)
## Metres per scoop, or metres per second for suction.
@export_range(0.01, 4.0, 0.01) var depth := 0.18
@export_range(1.0, 2000.0, 1.0, "or_greater") var capacity_litres := 70.0
@export_range(0.25, 3.0, 0.05, "or_greater") var dump_radius := 0.44
@export var color := Color.WHITE


func capacity_m3() -> float:
	return capacity_litres * 0.001
