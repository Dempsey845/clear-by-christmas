class_name SnowChunk
extends MeshInstance3D

@export_range(0.0, 1.5, 0.01) var initial_depth := 0.32

const MATERIAL = preload("res://Snow/snow_material.tres")

var depths := PackedFloat32Array()
var editable := PackedByteArray()
var weights := PackedFloat32Array()
var initial_depths := PackedFloat32Array()
var tile: Vector2i

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()


func initialize(field: SnowField, noise: FastNoiseLite) -> void:
	var side := field.cells_per_chunk + 1
	var count := side * side
	depths.resize(count)
	editable.resize(count)
	weights.resize(count)
	_vertices.resize(count)
	_normals.resize(count)
	_colors.resize(count)
	_uvs.resize(count)
	material_override = MATERIAL

	for z in side:
		for x in side:
			var index := z * side + x
			var sample := tile * field.cells_per_chunk + Vector2i(x, z)
			var point := Vector2(sample) * field.spacing
			var expected := field.expected_owners(sample)
			var base_depth := initial_depth
			editable[index] = 1
			if expected > 1:
				var owners := field.sample_owners(sample)
				editable[index] = int(owners.size() == expected)
				base_depth = 0.0
				for owner in owners:
					base_depth += owner.initial_depth / float(expected)
			# Shared edge samples contribute only their share of the represented volume.
			weights[index] = field.spacing * field.spacing / float(expected)
			depths[index] = maxf(0.0, base_depth * (1.0 + 0.45 * noise.get_noise_2dv(point)))
			if not editable[index]:
				depths[index] = 0.0
			_vertices[index] = Vector3(x * field.spacing, 0.0, z * field.spacing)
			_uvs[index] = point
	initial_depths = depths.duplicate()


func rebuild(field: SnowField) -> void:
	var cells := field.cells_per_chunk
	var side := cells + 1
	var has_snow := false
	for index in depths.size():
		if depths[index] >= 0.006:
			has_snow = true
			break
	if not has_snow:
		mesh = null
		return

	var origin := tile * cells
	for z in side:
		for x in side:
			var index := z * side + x
			var point := origin + Vector2i(x, z)
			var left := depths[index - 1] if x > 0 else field.grid_depth(point - Vector2i(1, 0))
			var right := depths[index + 1] if x < cells else field.grid_depth(point + Vector2i(1, 0))
			var back := depths[index - side] if z > 0 else field.grid_depth(point - Vector2i(0, 1))
			var front := depths[index + side] if z < cells else field.grid_depth(point + Vector2i(0, 1))
			var normal := Vector3(left - right, 2.0 * field.spacing, back - front).normalized()
			_vertices[index].y = depths[index] + 0.002
			_normals[index] = normal
			_colors[index] = Color(minf(depths[index] * 2.0, 1.0), normal.y, 0.0)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = field.indices
	var surface := ArrayMesh.new()
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = surface
