class_name ToolMarket
extends Node3D

@export var player: Node3D
@export var snow_tools: SnowTools
@export var job_board: JobBoard
@export var catalog: Array[SnowToolData]
@export_range(1.0, 6.0, 0.25) var interaction_distance := 2.75

const CARD = preload("res://Market/tool_card.tscn")

var _owned: Dictionary[StringName, bool] = {}
var _cards: Array[MarketToolCard] = []
var _open := false
var _prior_mouse_mode := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	%Close.pressed.connect(_close)
	job_board.balance_changed.connect(_refresh_cards)
	_add_card(snow_tools.starter_scoop, true)
	for tool in catalog:
		_add_card(tool, false)
	_refresh_cards(job_board.balance)


func _process(_delta: float) -> void:
	%Prompt.visible = not _open and not get_tree().paused and not job_board.hud.phone_open and _in_range()


func _input(event: InputEvent) -> void:
	if _open and (event.is_action_pressed("market_interact") or event.is_action_pressed("pause")):
		_close()
		get_viewport().set_input_as_handled()
	elif not _open and not get_tree().paused and event.is_action_pressed("market_interact") and not job_board.hud.phone_open and _in_range():
		_show_market()
		get_viewport().set_input_as_handled()


func _in_range() -> bool:
	return is_instance_valid(player) and player.is_visible_in_tree() \
		and player.global_position.distance_to(global_position) <= interaction_distance


func _show_market() -> void:
	_open = true
	_prior_mouse_mode = Input.mouse_mode
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%Prompt.hide()
	%Shop.show()
	%Feedback.text = ""
	%Close.grab_focus()


func _close() -> void:
	%Shop.hide()
	_open = false
	get_tree().paused = false
	Input.mouse_mode = _prior_mouse_mode


func _add_card(tool: SnowToolData, owned: bool) -> void:
	if tool == null or tool.id == &"" or _owned.has(tool.id):
		return
	_owned[tool.id] = owned
	var card := CARD.instantiate() as MarketToolCard
	var list: VBoxContainer = %Scoops if tool.kind == SnowToolData.Kind.SCOOP else %Suction
	list.add_child(card)
	card.display(tool)
	card.chosen.connect(_choose_tool)
	_cards.append(card)


func _choose_tool(tool: SnowToolData) -> void:
	if not _open:
		return
	if not _owned[tool.id]:
		if tool.price > 0 and not job_board.try_spend(tool.price):
			return
		_owned[tool.id] = true
		%Feedback.text = "%s purchased. Select Equip to use it." % tool.display_name
	elif snow_tools.try_equip(tool):
		%Feedback.text = "%s equipped." % tool.display_name
	else:
		%Feedback.text = "Dump the snow from your equipped tool before swapping it."
	_refresh_cards(job_board.balance)


func _refresh_cards(balance: int) -> void:
	%Balance.text = "Balance  £%d" % balance
	for card in _cards:
		var equipped := card.tool == snow_tools.equipped_scoop or card.tool == snow_tools.equipped_suction
		card.update_action(_owned[card.tool.id], equipped, balance)


func owned_items() -> Array[String]:
	var items: Array[String] = []
	for id in _owned:
		if _owned[id]:
			items.append(String(id))
	return items


func restore_items(items: Array, tools: Dictionary) -> void:
	var scoop_tool: SnowToolData
	var suction_tool: SnowToolData
	for card in _cards:
		var tool := card.tool
		var id := String(tool.id)
		_owned[tool.id] = tool == snow_tools.starter_scoop or id in items
		if not _owned[tool.id]:
			continue
		if id == tools.get("scoop", "") and tool.kind == SnowToolData.Kind.SCOOP:
			scoop_tool = tool
		if id == tools.get("suction", "") and tool.kind == SnowToolData.Kind.SUCTION:
			suction_tool = tool
	snow_tools.restore_state(tools, scoop_tool, suction_tool)
	_refresh_cards(job_board.balance)
