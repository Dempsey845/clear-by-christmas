class_name MarketToolCard
extends PanelContainer

signal chosen(tool: SnowToolData)

var tool: SnowToolData


func _ready() -> void:
	%Action.pressed.connect(func() -> void: chosen.emit(tool))


func display(data: SnowToolData) -> void:
	tool = data
	%Name.text = data.display_name
	%Name.add_theme_color_override("font_color", data.color.lightened(0.55))
	var depth_text := "%.0f cm / sec" % (data.depth * 100.0) if data.kind == SnowToolData.Kind.SUCTION else "%.0f cm / scoop" % (data.depth * 100.0)
	%Stats.text = "%.2f × %.2f m  ·  %s  ·  %.0f L" % [
		data.area.x, data.area.y, depth_text, data.capacity_litres
	]


func update_action(owned: bool, equipped: bool, balance: int) -> void:
	%Action.disabled = equipped or (not owned and balance < tool.price)
	if equipped:
		%Action.text = "Equipped"
	elif owned:
		%Action.text = "Equip"
	else:
		%Action.text = "Buy  £%d" % tool.price
