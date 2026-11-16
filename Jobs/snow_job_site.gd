class_name SnowJobSite
extends Node3D

@export var site_id: StringName
@export var lawn_chunks: Array[SnowChunk]

var _chunks: Array[SnowChunk] = []
var _fields: Array[SnowField] = []


func prepare() -> bool:
	_chunks.clear()
	_fields.clear()
	for chunk in lawn_chunks:
		if chunk == null or chunk.depths.is_empty() or chunk in _chunks:
			continue
		var field := chunk.get_parent() as SnowField
		if field == null:
			continue
		_chunks.append(chunk)
		if field not in _fields:
			_fields.append(field)
	return not _chunks.is_empty()


func fields() -> Array[SnowField]:
	return _fields


func chunk_count() -> int:
	return _chunks.size()


func snow_volume_m3() -> float:
	var volume := 0.0
	for chunk in _chunks:
		volume += chunk.snow_volume_m3
	return volume


func lawn_area_m2() -> float:
	var area := 0.0
	for chunk in _chunks:
		var field := chunk.get_parent() as SnowField
		area += field.chunk_size * field.chunk_size
	return area


func distance_to_lawn(point: Vector3) -> float:
	var nearest := INF
	for chunk in _chunks:
		var field := chunk.get_parent() as SnowField
		var local := chunk.to_local(point)
		var closest := Vector3(
			clampf(local.x, 0.0, field.chunk_size), 0.0,
			clampf(local.z, 0.0, field.chunk_size)
		)
		var offset := point - chunk.to_global(closest)
		nearest = minf(nearest, Vector2(offset.x, offset.z).length())
	return nearest
