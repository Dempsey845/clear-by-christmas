extends SnowField

# Road tiles cover two snow chunks in each direction.
const HALF_ROAD := Vector2(4.0, 4.0)
const TILE_BOUNDS := Rect2i(-8, -34, 25, 44)
const SERVICE_PAVEMENT := [Rect2(-28, 24, 16, 16), Rect2(8, 24, 12, 8)]
const BLANKET_DEPTH := 0.034
# This grid area previously excluded samples occupied by the prototype snow fields.
const PROTOTYPE_TILES := Rect2i(-3, -4, 9, 4)

@export var opening_lawns: Array[SnowJobSite]


func _ready() -> void:
	var paved: Array[Rect2] = []
	paved.assign(SERVICE_PAVEMENT)
	for road: Node3D in get_tree().get_nodes_in_group("town_roads"):
		var point := to_local(road.global_position)
		paved.append(Rect2(Vector2(point.x, point.z) - HALF_ROAD, HALF_ROAD * 2.0))

	var lawns: Dictionary[Vector2i, ResidentialLot] = {}
	var introductory: Dictionary[Vector2i, SnowJobSite] = {}
	var mounds: Dictionary[Vector2i, bool] = {}
	for site in opening_lawns:
		introductory[_lawn_tile(site)] = site
	for lot: ResidentialLot in get_tree().get_nodes_in_group("residential_lots"):
		var tile := _lawn_tile(lot.site)
		lawns[tile] = lot
		mounds[tile + Vector2i.RIGHT] = true

	# Build near the starting area first so the initial mesh budget fills the foreground.
	for z in range(TILE_BOUNDS.end.y - 1, TILE_BOUNDS.position.y - 1, -1):
		for x in range(TILE_BOUNDS.position.x, TILE_BOUNDS.end.x):
			var tile := Vector2i(x, z)
			var origin := Vector2(tile) * chunk_size
			var footprint := Rect2(origin, Vector2.ONE * chunk_size)
			if _is_paved(footprint.get_center(), paved):
				continue
			var chunk := SnowChunk.new()
			chunk.name = "Tile_%d_%d" % [x, z]
			chunk.position = Vector3(origin.x, 0.0, origin.y)
			chunk.initial_depth = BLANKET_DEPTH
			if lawns.has(tile):
				var lot := lawns[tile]
				chunk.initial_depth = lot.lawn_depth
				lot.site.lawn_chunks = [chunk]
			elif introductory.has(tile):
				var site := introductory[tile]
				chunk.lawn_depth_bonus = site.lawn_depth_bonus
				site.lawn_chunks = [chunk]
			elif mounds.has(tile):
				chunk.pile_height = 0.31
			add_child(chunk)
	super._ready()


func _is_paved(point: Vector2, areas: Array[Rect2]) -> bool:
	for area in areas:
		if area.has_point(point):
			return true
	return false


func _lawn_tile(site: SnowJobSite) -> Vector2i:
	var center := to_local(site.global_position)
	return Vector2i((Vector2(center.x, center.z) / chunk_size).floor())


func upgrade_legacy_state(state: Dictionary) -> Dictionary:
	var updated := state.duplicate()
	for z in range(PROTOTYPE_TILES.position.y, PROTOTYPE_TILES.end.y):
		for x in range(PROTOTYPE_TILES.position.x, PROTOTYPE_TILES.end.x):
			updated.erase("Tile_%d_%d" % [x, z])
	return updated
