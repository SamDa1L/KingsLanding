class_name ResourceLayerRegionScanner
extends RefCounted


const GeneratedTileDataScript := preload("res://scripts/mapgen/GeneratedTileData.gd")
const MapTypes := preload("res://scripts/map/MapTypes.gd")
const ResourceRegionScript := preload("res://scripts/map/ResourceRegion.gd")

const ORTHOGONAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
]


func scan_regions(map_data, resource_type: StringName) -> Array:
	var regions: Array = []
	if map_data == null or map_data.width <= 0 or map_data.height <= 0:
		return regions

	var patch_cells_by_id: Dictionary = _group_cells_by_patch_id(map_data, resource_type)
	var patch_ids: Array[int] = []
	for patch_id in patch_cells_by_id.keys():
		patch_ids.append(int(patch_id))
	patch_ids.sort()

	for patch_id in patch_ids:
		var region: RefCounted = ResourceRegionScript.new()
		region.setup(patch_id, _resource_type_to_terrain(resource_type))
		var patch_cells: Array = patch_cells_by_id.get(patch_id, [])

		for cell in patch_cells:
			region.add_cell(cell)

		_collect_adjacent_buildable_cells(map_data, region)
		regions.append(region)

	return regions


func scan_all_resource_regions(map_data) -> Dictionary:
	return {
		GeneratedTileDataScript.RESOURCE_WOOD: scan_regions(map_data, GeneratedTileDataScript.RESOURCE_WOOD),
		GeneratedTileDataScript.RESOURCE_STONE: scan_regions(map_data, GeneratedTileDataScript.RESOURCE_STONE),
	}


func get_region_summaries(regions: Array) -> Array:
	var summaries: Array = []
	for region in regions:
		if region == null:
			continue
		summaries.append(region.get_summary())
	return summaries


func get_total_area(regions: Array) -> int:
	var total_area := 0
	for region in regions:
		if region == null:
			continue
		total_area += int(region.area)
	return total_area


func _group_cells_by_patch_id(map_data, resource_type: StringName) -> Dictionary:
	var patch_cells_by_id: Dictionary = {}

	for cell in map_data.get_all_cells():
		var tile = map_data.get_tile(cell)
		if tile == null:
			continue
		if tile.resource_type != resource_type:
			continue
		if tile.resource_patch_id < 0:
			continue

		if not patch_cells_by_id.has(tile.resource_patch_id):
			patch_cells_by_id[tile.resource_patch_id] = []

		var patch_cells: Array = patch_cells_by_id[tile.resource_patch_id]
		patch_cells.append(cell)

	return patch_cells_by_id


func _collect_adjacent_buildable_cells(map_data, region: RefCounted) -> void:
	if region == null:
		return

	for cell in region.cells:
		for direction in ORTHOGONAL_DIRECTIONS:
			var neighbor: Vector2i = cell + direction
			if not map_data.is_inside(neighbor):
				continue

			var neighbor_tile = map_data.get_tile(neighbor)
			if not _is_buildable_neighbor(neighbor_tile):
				continue

			region.add_adjacent_empty_cell(neighbor)


func _is_buildable_neighbor(tile) -> bool:
	if tile == null:
		return false
	if tile.has_resource():
		return false
	return bool(tile.buildable)


func _resource_type_to_terrain(resource_type: StringName) -> int:
	if resource_type == GeneratedTileDataScript.RESOURCE_WOOD:
		return MapTypes.TerrainType.FOREST
	if resource_type == GeneratedTileDataScript.RESOURCE_STONE:
		return MapTypes.TerrainType.STONE
	return MapTypes.TerrainType.EMPTY
