class_name SaveSlots
extends RefCounted

const COUNT := 4
const VERSION := 2


static func _path(slot: int) -> String:
	# The old single-save filename is slot 1.
	return "user://clear_by_christmas.save" if slot == 1 else "user://clear_by_christmas_%d.save" % slot


static func exists(slot: int) -> bool:
	return slot >= 1 and slot <= COUNT and FileAccess.file_exists(_path(slot))


static func has_any() -> bool:
	for slot in range(1, COUNT + 1):
		if exists(slot):
			return true
	return false


static func read(slot: int) -> Dictionary:
	if not exists(slot):
		return {}
	var file := FileAccess.open(_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var state: Variant = file.get_var()
	if not _is_valid(state):
		return {}
	return state


static func write(slot: int, state: Dictionary) -> Error:
	if slot < 1 or slot > COUNT:
		return ERR_INVALID_PARAMETER
	var path := _path(slot)
	var staging := path + ".tmp"
	var file := FileAccess.open(staging, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var stored := file.store_var(state)
	file.close()
	if not stored:
		DirAccess.remove_absolute(staging)
		return ERR_FILE_CANT_WRITE
	var result := DirAccess.rename_absolute(staging, path)
	if result != OK:
		DirAccess.remove_absolute(staging)
	return result


static func delete(slot: int) -> Error:
	return DirAccess.remove_absolute(_path(slot)) if exists(slot) else ERR_FILE_NOT_FOUND


static func _is_valid(state: Variant) -> bool:
	return (state is Dictionary and state.get("version") in [1, VERSION]
		and state.get("jobs") is Dictionary and state.get("snow") is Dictionary
		and state.get("owned") is Array and state.get("tools") is Dictionary
		and state.get("position") is Vector3 and state.position.is_finite()
		and state.get("yaw") is float and is_finite(state.yaw)
		and state.get("pitch") is float and is_finite(state.pitch)
		and state.get("indoors") is bool)
