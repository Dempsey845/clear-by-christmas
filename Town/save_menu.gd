class_name SaveMenu
extends CanvasLayer

signal save_requested(slot: int)
signal load_requested(slot: int)
signal restart_requested

@onready var _screen: ColorRect = %Screen
@onready var _list: ItemList = %Slots
@onready var _status: Label = %Status
@onready var _confirmation: VBoxContainer = %Confirmation

var _available: Array[bool] = []
var _selected := 1
var _startup := false
var _pending: Callable
var _previous_mouse := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	_list.item_selected.connect(_select)
	%Load.pressed.connect(func() -> void: load_requested.emit(_selected))
	%Save.pressed.connect(_request_save)
	%Delete.pressed.connect(_request_delete)
	%Restart.pressed.connect(_request_restart)
	%Back.pressed.connect(close)
	%Cancel.pressed.connect(_dismiss_confirmation)
	%Confirm.pressed.connect(_confirm_action)


func _input(event: InputEvent) -> void:
	if not _screen.visible:
		return
	if event.is_action_pressed("pause"):
		if _confirmation.visible:
			_dismiss_confirmation()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("job_phone") or event.is_action_pressed("market_interact"):
		get_viewport().set_input_as_handled()


func open(startup := false) -> void:
	_startup = startup
	_previous_mouse = Input.mouse_mode
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = ""
	%Back.text = "Play without loading" if startup else "Back"
	%Restart.visible = not startup
	_screen.show()
	_dismiss_confirmation()
	refresh()
	_list.grab_focus()


func close() -> void:
	_dismiss_confirmation()
	_screen.hide()
	Input.mouse_mode = _previous_mouse
	get_tree().paused = false


func refresh(message := "") -> void:
	_list.clear()
	_available.clear()
	for slot in range(1, SaveSlots.COUNT + 1):
		var state := SaveSlots.read(slot)
		_available.append(not state.is_empty())
		_list.add_item("Slot %d   ·   %s" % [slot, _summary(state, SaveSlots.exists(slot))])
	_list.select(_selected - 1)
	_status.text = message
	_update_actions()


func _summary(state: Dictionary, exists: bool) -> String:
	if state.is_empty():
		return "Unreadable save" if exists else "Empty"
	var jobs: Dictionary = state.jobs
	var count: Variant = jobs.get("daily_sites", [])
	var total: int = count.size() if count is Array and not count.is_empty() else 4
	var hour: Variant = state.get("hour", TownClock.MORNING)
	var minutes := floori(hour * 60.0) if hour is float and is_finite(hour) else 480
	@warning_ignore("integer_division")
	return "Dec %d, %02d:%02d   ·   %d/%d jobs   ·   £%d" % [
		jobs.get("day", 1), minutes / 60, minutes % 60, jobs.get("request_index", 0), total, jobs.get("balance", 0),
	]


func _select(index: int) -> void:
	_selected = index + 1
	_status.text = ""
	_update_actions()


func _update_actions() -> void:
	var confirming := _confirmation.visible
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if confirming else Control.MOUSE_FILTER_STOP
	_list.focus_mode = Control.FOCUS_NONE if confirming else Control.FOCUS_ALL
	%Load.disabled = confirming or _selected > _available.size() or not _available[_selected - 1]
	%Save.disabled = confirming or _startup
	%Delete.disabled = confirming or not SaveSlots.exists(_selected)
	%Restart.disabled = confirming
	%Back.disabled = confirming


func _request_save() -> void:
	if SaveSlots.exists(_selected):
		_ask("Replace the save in slot %d?" % _selected, "Replace save", save_requested.emit.bind(_selected))
	else:
		save_requested.emit(_selected)


func _request_delete() -> void:
	_ask("Delete the save in slot %d?" % _selected, "Delete save", _delete_slot.bind(_selected))


func _request_restart() -> void:
	_ask("Restart from December 1? Unsaved progress will be lost. Saved slots are kept.",
		"Restart game", restart_requested.emit)


func _delete_slot(slot: int) -> void:
	var result := SaveSlots.delete(slot)
	refresh("Slot %d deleted." % slot if result == OK else "Couldn’t delete slot %d." % slot)


func _ask(message: String, verb: String, action: Callable) -> void:
	_pending = action
	%Question.text = message
	%Confirm.text = verb
	_confirmation.show()
	_update_actions()
	%Cancel.grab_focus()


func _dismiss_confirmation() -> void:
	_pending = Callable()
	_confirmation.hide()
	_update_actions()
	if _screen.visible:
		_list.grab_focus()


func _confirm_action() -> void:
	var action := _pending
	_dismiss_confirmation()
	if action.is_valid():
		action.call()
