class_name BuildingFootprintRules
extends RefCounted

const MapTypes := preload("res://scripts/map/MapTypes.gd")

const CASTLE_FOOTPRINT_RADIUS: int = 4
const CASTLE_FOOTPRINT_SIZE: int = CASTLE_FOOTPRINT_RADIUS * 2 + 1


static func get_castle_footprint_cells(center_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y_offset in range(-CASTLE_FOOTPRINT_RADIUS, CASTLE_FOOTPRINT_RADIUS + 1):
		for x_offset in range(-CASTLE_FOOTPRINT_RADIUS, CASTLE_FOOTPRINT_RADIUS + 1):
			cells.append(center_cell + Vector2i(x_offset, y_offset))
	return cells


static func get_building_footprint_cells(building_type: int, center_cell: Vector2i) -> Array[Vector2i]:
	if building_type == MapTypes.BuildingType.TOWN_CENTER:
		return get_castle_footprint_cells(center_cell)
	return [center_cell]


static func is_castle_terrain(terrain_type: int) -> bool:
	return terrain_type == MapTypes.TerrainType.EMPTY or terrain_type == MapTypes.TerrainType.PLAIN or terrain_type == MapTypes.TerrainType.TOWN_CENTER


static func is_castle_footprint_valid(grid: RefCounted, center_cell: Vector2i) -> bool:
	if grid == null:
		return false
	for footprint_cell in get_castle_footprint_cells(center_cell):
		if not _is_grid_cell_inside(grid, footprint_cell):
			return false
		if not is_castle_terrain(_get_grid_terrain(grid, footprint_cell)):
			return false
	return true


static func is_castle_footprint_valid_and_unblocked(grid: RefCounted, center_cell: Vector2i, blocked_cells: Dictionary) -> bool:
	if not is_castle_footprint_valid(grid, center_cell):
		return false
	return is_castle_footprint_unoccupied(blocked_cells, center_cell)


static func is_castle_footprint_unoccupied(occupied_cells: Dictionary, center_cell: Vector2i) -> bool:
	for footprint_cell in get_castle_footprint_cells(center_cell):
		if occupied_cells.has(footprint_cell):
			return false
	return true


static func register_building_footprint(occupied_cells: Dictionary, building_type: int, center_cell: Vector2i) -> void:
	for footprint_cell in get_building_footprint_cells(building_type, center_cell):
		occupied_cells[footprint_cell] = true


static func find_nearest_valid_castle_cell(grid: RefCounted, preferred_cell: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	if grid == null or int(grid.get("width")) <= 0 or int(grid.get("height")) <= 0:
		return Vector2i(-1, -1)

	var search_start: Vector2i = preferred_cell
	if search_start.x < 0 or search_start.y < 0 or not _is_grid_cell_inside(grid, search_start):
		search_start = Vector2i(int(grid.get("width")) / 2, int(grid.get("height")) / 2)

	if is_castle_footprint_valid(grid, search_start):
		return search_start

	var visited: Dictionary = {search_start: true}
	var queue: Array[Vector2i] = [search_start]
	var queue_index: int = 0
	while queue_index < queue.size():
		var current_cell: Vector2i = queue[queue_index]
		queue_index += 1
		for direction_variant in MapTypes.get_cardinal_directions():
			var direction: Vector2i = direction_variant
			var neighbor_cell: Vector2i = current_cell + direction
			if visited.has(neighbor_cell) or not _is_grid_cell_inside(grid, neighbor_cell):
				continue
			visited[neighbor_cell] = true
			if is_castle_footprint_valid(grid, neighbor_cell):
				return neighbor_cell
			queue.append(neighbor_cell)

	return Vector2i(-1, -1)


static func find_nearest_valid_castle_cell_avoiding(grid: RefCounted, blocked_cells: Dictionary, preferred_cell: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	if grid == null or int(grid.get("width")) <= 0 or int(grid.get("height")) <= 0:
		return Vector2i(-1, -1)

	var search_start: Vector2i = preferred_cell
	if search_start.x < 0 or search_start.y < 0 or not _is_grid_cell_inside(grid, search_start):
		search_start = Vector2i(int(grid.get("width")) / 2, int(grid.get("height")) / 2)

	if is_castle_footprint_valid_and_unblocked(grid, search_start, blocked_cells):
		return search_start

	var visited: Dictionary = {search_start: true}
	var queue: Array[Vector2i] = [search_start]
	var queue_index: int = 0
	while queue_index < queue.size():
		var current_cell: Vector2i = queue[queue_index]
		queue_index += 1
		for direction_variant in MapTypes.get_cardinal_directions():
			var direction: Vector2i = direction_variant
			var neighbor_cell: Vector2i = current_cell + direction
			if visited.has(neighbor_cell) or not _is_grid_cell_inside(grid, neighbor_cell):
				continue
			visited[neighbor_cell] = true
			if is_castle_footprint_valid_and_unblocked(grid, neighbor_cell, blocked_cells):
				return neighbor_cell
			queue.append(neighbor_cell)

	return Vector2i(-1, -1)


static func _is_grid_cell_inside(grid: RefCounted, cell: Vector2i) -> bool:
	if grid == null or not grid.has_method("is_inside"):
		return false
	return bool(grid.call("is_inside", cell))


static func _get_grid_terrain(grid: RefCounted, cell: Vector2i) -> int:
	if grid == null or not grid.has_method("get_terrain"):
		return -1
	return int(grid.call("get_terrain", cell))
