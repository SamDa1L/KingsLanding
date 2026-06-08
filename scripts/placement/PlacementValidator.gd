class_name PlacementValidator
extends RefCounted

const MapTypes := preload("res://scripts/map/MapTypes.gd")
const PlacementResultScript := preload("res://scripts/placement/PlacementResult.gd")
const BuildingFootprintRulesScript := preload("res://scripts/buildings/BuildingFootprintRules.gd")

var grid: RefCounted = null
var resource_regions: Dictionary = {}
var farmable_regions: Array = []
var occupied_cells: Dictionary = {}
var castle_cell: Vector2i = Vector2i(-1, -1)
var semantic_query_bridge: RefCounted = null
var _reachable_cells: Dictionary = {}
var _reachable_cells_ready: bool = false


func setup(
	next_grid: RefCounted,
	next_resource_regions: Dictionary,
	next_farmable_regions: Array,
	next_occupied_cells: Dictionary = {},
	next_castle_cell: Vector2i = Vector2i(-1, -1),
	next_semantic_query_bridge: RefCounted = null
) -> void:
	grid = next_grid
	resource_regions = next_resource_regions
	farmable_regions = next_farmable_regions
	occupied_cells = next_occupied_cells
	castle_cell = next_castle_cell
	semantic_query_bridge = next_semantic_query_bridge
	invalidate_reachability_cache()


func invalidate_reachability_cache() -> void:
	_reachable_cells.clear()
	_reachable_cells_ready = false


func validate(building_type: int, cell: Vector2i) -> RefCounted:
	if grid == null and semantic_query_bridge == null:
		return _result(false, "网格缺失。", cell, null, building_type)
	if semantic_query_bridge == null and not grid.is_inside(cell):
		return _result(false, "目标格子超出地图范围。", cell, null, building_type)
	if building_type != MapTypes.BuildingType.TOWN_CENTER and occupied_cells.has(cell):
		return _result(false, "目标格子已被占用。", cell, null, building_type)

	var terrain_type: int = _get_terrain_type(cell)
	if terrain_type < 0:
		return _result(false, "目标格子语义未就绪。", cell, null, building_type)
	match building_type:
		MapTypes.BuildingType.TOWN_CENTER:
			return _validate_castle(cell, terrain_type)
		MapTypes.BuildingType.LUMBER_CAMP:
			return _validate_resource_building(cell, terrain_type, MapTypes.TerrainType.FOREST, resource_regions.get(MapTypes.TerrainType.FOREST, []), "伐木场")
		MapTypes.BuildingType.QUARRY:
			return _validate_resource_building(cell, terrain_type, MapTypes.TerrainType.STONE, resource_regions.get(MapTypes.TerrainType.STONE, []), "采石场")
		MapTypes.BuildingType.FARM:
			return _validate_farm(cell, terrain_type)
		MapTypes.BuildingType.HOUSE:
			return _validate_house(cell, terrain_type)
		_:
			return _result(false, "未知建筑类型。", cell, null, building_type)


func _validate_castle(cell: Vector2i, terrain_type: int) -> RefCounted:
	if not _is_castle_terrain(terrain_type):
		return _result(false, "城堡中心必须放置在空地、平原或城堡地块上。", cell, null, MapTypes.BuildingType.TOWN_CENTER)
	if not _is_castle_footprint_valid(cell):
		return _result(false, "城堡需要 9x9 空地，占地范围内不能有森林、石材、水域或山地。", cell, null, MapTypes.BuildingType.TOWN_CENTER)
	if not BuildingFootprintRulesScript.is_castle_footprint_unoccupied(occupied_cells, cell):
		return _result(false, "城堡 9x9 占地范围内已有建筑。", cell, null, MapTypes.BuildingType.TOWN_CENTER)
	return _result(true, "", cell, null, MapTypes.BuildingType.TOWN_CENTER)


func _validate_resource_building(cell: Vector2i, terrain_type: int, resource_terrain: int, regions: Array, label: String) -> RefCounted:
	if terrain_type != MapTypes.TerrainType.EMPTY and terrain_type != MapTypes.TerrainType.PLAIN:
		return _result(false, "%s必须放置在可建造的空地或平原格子上。" % label, cell, null, -1)
	var region: RefCounted = null
	if semantic_query_bridge != null and semantic_query_bridge.has_method("find_resource_region_for_building_cell"):
		region = semantic_query_bridge.call("find_resource_region_for_building_cell", cell, resource_terrain)
	else:
		region = _find_region_for_cell_or_adjacency(regions, cell)
	if region == null:
		return _result(false, "%s必须贴近%s板块。" % [label, MapTypes.get_terrain_label(resource_terrain)], cell, null, -1)
	if not _is_worker_accessible_cell(cell):
		return _result(false, "工人无法到达建筑位置。", cell, null, -1)
	return _result(true, "", cell, region, -1)


func _validate_farm(cell: Vector2i, terrain_type: int) -> RefCounted:
	if terrain_type != MapTypes.TerrainType.PLAIN:
		return _result(false, "农场必须放置在平原地块上。", cell, null, MapTypes.BuildingType.FARM)
	var region: RefCounted = null
	if semantic_query_bridge != null and semantic_query_bridge.has_method("find_farmable_region_for_cell"):
		region = semantic_query_bridge.call("find_farmable_region_for_cell", cell)
	else:
		region = _find_region_containing_cell(farmable_regions, cell)
	if not _is_worker_accessible_cell(cell):
		return _result(false, "工人无法到达建筑位置。", cell, null, MapTypes.BuildingType.FARM)
	return _result(true, "", cell, region, MapTypes.BuildingType.FARM)


func _validate_house(cell: Vector2i, terrain_type: int) -> RefCounted:
	if terrain_type == MapTypes.TerrainType.WATER or terrain_type == MapTypes.TerrainType.MOUNTAIN:
		return _result(false, "住宅不能放置在水域或山地上。", cell, null, MapTypes.BuildingType.HOUSE)
	if terrain_type == MapTypes.TerrainType.FOREST or terrain_type == MapTypes.TerrainType.STONE:
		return _result(false, "住宅不能放置在资源地块上。", cell, null, MapTypes.BuildingType.HOUSE)
	return _result(true, "", cell, null, MapTypes.BuildingType.HOUSE)


func _find_region_for_cell_or_adjacency(regions: Array, cell: Vector2i) -> RefCounted:
	for region in regions:
		if region.contains_cell(cell) or region.adjacent_empty_cells.has(cell):
			return region
	return null


func _find_region_containing_cell(regions: Array, cell: Vector2i) -> RefCounted:
	for region in regions:
		if region.contains_cell(cell):
			return region
	return null


func _is_castle_terrain(terrain_type: int) -> bool:
	return BuildingFootprintRulesScript.is_castle_terrain(terrain_type)


func _is_castle_footprint_valid(center_cell: Vector2i) -> bool:
	for footprint_cell in BuildingFootprintRulesScript.get_castle_footprint_cells(center_cell):
		if semantic_query_bridge == null:
			if grid == null or not grid.is_inside(footprint_cell):
				return false
		var terrain_type: int = _get_terrain_type(footprint_cell)
		if terrain_type < 0 or not _is_castle_terrain(terrain_type):
			return false
	return true


func _is_worker_accessible_cell(cell: Vector2i) -> bool:
	if not _is_navigation_walkable_cell(cell):
		return false
	if castle_cell.x < 0 or castle_cell.y < 0:
		return true
	if grid != null and grid.is_inside(cell) and grid.is_inside(castle_cell):
		_ensure_reachable_cells()
		return _reachable_cells.has(cell)
	return _has_open_worker_entry_near_cell(cell)


func _ensure_reachable_cells() -> void:
	if _reachable_cells_ready:
		return
	_reachable_cells.clear()
	_reachable_cells_ready = true
	if grid == null or not grid.is_inside(castle_cell):
		return
	if not _is_navigation_walkable_cell(castle_cell):
		return

	var queue: Array[Vector2i] = [castle_cell]
	_reachable_cells[castle_cell] = true
	var queue_read_index: int = 0
	while queue_read_index < queue.size():
		var current_cell: Vector2i = queue[queue_read_index]
		queue_read_index += 1
		for direction_variant in MapTypes.get_eight_directions():
			var direction: Vector2i = direction_variant
			var neighbor_cell: Vector2i = current_cell + direction
			if _reachable_cells.has(neighbor_cell):
				continue
			if not grid.is_inside(neighbor_cell):
				continue
			if not _is_navigation_walkable_cell(neighbor_cell):
				continue
			if _is_diagonal_direction(direction) and not _can_move_diagonally(current_cell, direction):
				continue
			_reachable_cells[neighbor_cell] = true
			queue.append(neighbor_cell)


func _has_open_worker_entry_near_cell(cell: Vector2i) -> bool:
	for direction_variant in MapTypes.get_cardinal_directions():
		var direction: Vector2i = direction_variant
		var neighbor_cell: Vector2i = cell + direction
		if _is_navigation_walkable_cell(neighbor_cell):
			return true
	return false


func _is_diagonal_direction(direction: Vector2i) -> bool:
	return direction.x != 0 and direction.y != 0


func _can_move_diagonally(from_cell: Vector2i, direction: Vector2i) -> bool:
	var horizontal_neighbor: Vector2i = from_cell + Vector2i(direction.x, 0)
	var vertical_neighbor: Vector2i = from_cell + Vector2i(0, direction.y)
	return _is_navigation_walkable_cell(horizontal_neighbor) and _is_navigation_walkable_cell(vertical_neighbor)


func _is_navigation_walkable_cell(cell: Vector2i) -> bool:
	if grid != null and grid.is_inside(cell) and grid.has_method("get_blocks_movement"):
		return not bool(grid.call("get_blocks_movement", cell, true))
	var terrain_type: int = _get_terrain_type(cell)
	if terrain_type < 0:
		return false
	return MapTypes.is_villager_walkable_terrain(terrain_type)


func _get_terrain_type(cell: Vector2i) -> int:
	if semantic_query_bridge != null and semantic_query_bridge.has_method("get_terrain"):
		return int(semantic_query_bridge.call("get_terrain", cell))
	if grid == null:
		return -1
	return grid.get_terrain(cell)


func _result(can_place: bool, reason: String, cell: Vector2i, region: RefCounted, building_type: int) -> RefCounted:
	var result := PlacementResultScript.new()
	result.setup(can_place, reason, cell, region, building_type)
	return result
