@tool
extends Node3D

@export var junction := false:
	set(value):
		junction = value
		if is_node_ready():
			$Markings.visible = not value


func _ready() -> void:
	$Markings.visible = not junction
