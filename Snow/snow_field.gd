class_name SnowField
extends Node3D

const COLLISION_LAYER := 1 << 1

@export var collision_enabled := true
@export_range(1.0, 16.0, 0.25) var chunk_size := 4.0
@export_range(8, 64, 1) var cells_per_chunk := 32
@export_range(1, 16, 1) var mesh_updates_per_frame := 4
@export var drift_seed := 28

var spacing: float
var indices := PackedInt32Array()

var _chunks: Dictionary[Vector2i, SnowChunk] = {}
var _dirty: Dictionary[Vector2i, SnowChunk] = {}
var _collision_dirty: Dictionary[Vector2i, bool] = {}
var _bounds: AABB


func _ready() -> void:
	spacing = chunk_size / cells_per_chunk
	_build_indices()
	for child in get_children():
		if child is not SnowChunk:
			continue
		var tile := Vector2i(roundi(child.position.x / chunk_size), roundi(child.position.z / chunk_size))
		if _chunks.has(tile):
			push_warning("Duplicate snow tile at %s" % tile)
			child.hide()
			continue
		child.tile = tile
		child.transform = Transform3D(Basis.IDENTITY, Vector3(tile.x * chunk_size, 0.0, tile.y * chunk_size))
		_chunks[tile] = child

	for chunk in _chunks.values():
		var tile_bounds := AABB(chunk.position - Vector3.UP, Vector3(chunk_size, 2.0, chunk_size))
		_bounds = tile_bounds if not _bounds.has_volume() else _bounds.merge(tile_bounds)

	var noise := FastNoiseLite.new()
	noise.seed = drift_seed
	noise.frequency = 0.45
	for chunk in _chunks.values():
		chunk.initialize(self, noise)
		_dirty[chunk.tile] = chunk
	set_process(not _dirty.is_empty())


func _process(_delta: float) -> void:
	var pending: Array[Vector2i] = []
	for tile in _dirty:
		pending.append(tile)
		if pending.size() == mesh_updates_per_frame:
			break
	for tile in pending:
		var chunk := _dirty[tile]
		_dirty.erase(tile)
		chunk.rebuild(self)
		if _collision_dirty.erase(tile):
			chunk.rebuild_collision(self)
	if _dirty.is_empty():
		set_process(false)


func _build_indices() -> void:
	var side := cells_per_chunk + 1
	indices.resize(cells_per_chunk * cells_per_chunk * 6)
	var index := 0
	for z in cells_per_chunk:
		for x in cells_per_chunk:
			var corner := z * side + x
			indices[index] = corner
			indices[index + 1] = corner + 1
			indices[index + 2] = corner + side
			indices[index + 3] = corner + 1
			indices[index + 4] = corner + side + 1
			indices[index + 5] = corner + side
			index += 6


func expected_owners(sample: Vector2i) -> int:
	var count := 1
	if sample.x % cells_per_chunk == 0:
		count *= 2
	if sample.y % cells_per_chunk == 0:
		count *= 2
	return count


func sample_owners(sample: Vector2i) -> Array[SnowChunk]:
	var tile := _sample_tile(sample)
	var owners: Array[SnowChunk] = []
	var offsets_x := 2 if sample.x % cells_per_chunk == 0 else 1
	var offsets_z := 2 if sample.y % cells_per_chunk == 0 else 1
	for z in offsets_z:
		for x in offsets_x:
			var chunk := _chunks.get(tile - Vector2i(x, z)) as SnowChunk
			if chunk != null:
				owners.append(chunk)
	return owners


func grid_surface_depth(sample: Vector2i) -> float:
	var tile := _sample_tile(sample)
	var chunk := _chunks.get(tile) as SnowChunk
	if chunk == null:
		return 0.0
	var local := sample - tile * cells_per_chunk
	return chunk.surface_depth(local.y * (cells_per_chunk + 1) + local.x)


func depth_at(point: Vector3) -> float:
	var local := to_local(point)
	var scaled := Vector2(local.x, local.z) / spacing
	var start := Vector2i(scaled.floor())
	var fraction := scaled - Vector2(start)
	var a := grid_surface_depth(start)
	var b := grid_surface_depth(start + Vector2i(1, 0))
	var c := grid_surface_depth(start + Vector2i(0, 1))
	var d := grid_surface_depth(start + Vector2i(1, 1))
	# Match the two triangles used by the rendered mesh.
	if fraction.x + fraction.y <= 1.0:
		return a + (b - a) * fraction.x + (c - a) * fraction.y
	return d + (c - d) * (1.0 - fraction.x) + (b - d) * (1.0 - fraction.y)


func cut(point: Vector3, forward: Vector3, size: Vector2, depth: float, rounded: bool) -> float:
	var brush := _brush(point, forward, size, rounded)
	var removed := 0.0
	for sample in brush:
		var chunk: SnowChunk = sample[0]
		var index: int = sample[1]
		var strength: float = sample[2]
		var amount := minf(chunk.depths[index], depth * strength)
		if amount <= 0.0:
			continue
		chunk.depths[index] -= amount
		chunk.clear_footprint(index)
		removed += amount * chunk.weights[index]
		_queue_edit(chunk, index, true)
	if removed > 0.0:
		set_process(true)
	return removed


func deposit(point: Vector3, radius: float, volume: float) -> bool:
	var brush := _brush(point, Vector3.FORWARD, Vector2.ONE * radius * 2.0, true)
	var area := 0.0
	for sample in brush:
		var chunk: SnowChunk = sample[0]
		var index: int = sample[1]
		area += float(sample[2]) * chunk.weights[index]
	if area <= 0.0:
		return false
	for sample in brush:
		var chunk: SnowChunk = sample[0]
		var index: int = sample[1]
		chunk.depths[index] += volume * float(sample[2]) / area
		chunk.clear_footprint(index)
		_queue_edit(chunk, index, true)
	set_process(true)
	return true


func stamp_footprint(point: Vector3, forward: Vector3, size: Vector2, depth: float) -> void:
	# Keep a bootprint wide enough to reach vertices on coarser grids.
	size = size.max(Vector2.ONE * spacing * 1.9)
	for sample in _brush(point, forward, size, true):
		var chunk: SnowChunk = sample[0]
		var index: int = sample[1]
		if chunk.depths[index] >= 0.025 and chunk.stamp_footprint(index, depth * float(sample[2])):
			_queue_edit(chunk, index, false)
	if not _dirty.is_empty():
		set_process(true)


func reset_snow() -> void:
	for chunk in _chunks.values():
		chunk.reset_depths()
		if collision_enabled:
			_collision_dirty[chunk.tile] = true
		_dirty[chunk.tile] = chunk
	set_process(not _dirty.is_empty())


func _queue_edit(chunk: SnowChunk, index: int, update_collision: bool) -> void:
	_dirty[chunk.tile] = chunk
	if update_collision and collision_enabled:
		_collision_dirty[chunk.tile] = true
	var side := cells_per_chunk + 1
	var x := index % side
	@warning_ignore("integer_division")
	var z := index / side
	# Border normals also read the first row of samples from the adjoining tile.
	if x == 1:
		_queue_neighbor(chunk.tile + Vector2i.LEFT)
	elif x == cells_per_chunk - 1:
		_queue_neighbor(chunk.tile + Vector2i.RIGHT)
	if z == 1:
		_queue_neighbor(chunk.tile + Vector2i.UP)
	elif z == cells_per_chunk - 1:
		_queue_neighbor(chunk.tile + Vector2i.DOWN)


func _queue_neighbor(tile: Vector2i) -> void:
	if _chunks.has(tile):
		_dirty[tile] = _chunks[tile]


func _brush(point: Vector3, forward: Vector3, size: Vector2, rounded: bool) -> Array[Array]:
	var local := to_local(point)
	var center := Vector2(local.x, local.z)
	var direction := global_basis.inverse() * forward
	var axis := Vector2(direction.x, direction.z).normalized()
	if axis.is_zero_approx():
		axis = Vector2.UP
	var right := Vector2(-axis.y, axis.x)
	var half := size * 0.5
	var extent := right.abs() * half.x + axis.abs() * half.y
	var first := Vector2i(((center - extent) / spacing).ceil())
	var last := Vector2i(((center + extent) / spacing).floor())
	var first_tile := _sample_tile(first - Vector2i.ONE)
	var last_tile := _sample_tile(last)
	var samples: Array[Array] = []
	var side := cells_per_chunk + 1
	for tile_z in range(first_tile.y, last_tile.y + 1):
		for tile_x in range(first_tile.x, last_tile.x + 1):
			var tile := Vector2i(tile_x, tile_z)
			var chunk := _chunks.get(tile) as SnowChunk
			if chunk == null:
				continue
			var origin := tile * cells_per_chunk
			var start := (first - origin).max(Vector2i.ZERO)
			var end := (last - origin).min(Vector2i.ONE * cells_per_chunk)
			for z in range(start.y, end.y + 1):
				for x in range(start.x, end.x + 1):
					var index := z * side + x
					if not chunk.editable[index]:
						continue
					var offset := Vector2(origin + Vector2i(x, z)) * spacing - center
					var normalized := Vector2(offset.dot(right), offset.dot(axis)) / half
					var edge := normalized.length() if rounded else maxf(absf(normalized.x), absf(normalized.y))
					if edge < 1.0:
						samples.append([chunk, index, 1.0 - smoothstep(0.58, 1.0, edge)])
	return samples


func _sample_tile(sample: Vector2i) -> Vector2i:
	return Vector2i((Vector2(sample) / float(cells_per_chunk)).floor())


func contains_ground(point: Vector3) -> bool:
	var local := to_local(point)
	var tile := Vector2i((Vector2(local.x, local.z) / chunk_size).floor())
	return _chunks.has(tile)


func overlaps_ray_footprint(local_from: Vector3, local_to: Vector3) -> bool:
	local_from.y = 0.0
	local_to.y = 0.0
	return _bounds.has_volume() and _bounds.intersects_segment(local_from, local_to) != null
