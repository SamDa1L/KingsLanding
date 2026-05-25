class_name ResourceRegionScanner
extends RefCounted

const ResourceRegionScript := preload("res://scripts/map/ResourceRegion.gd")
const ORTHOGONAL_DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


func scan_regions(grid: RefCounted, terrain_type: int) -> Array:
	var regions: Array = []
	if grid == null or grid.width <= 0 or grid.height <= 0:
		return regions

	var visited: Dictionary = {}
	var region_id := 0

	for cell in grid.get_all_cells():
		if visited.has(cell):
			continue
		if grid.get_terrain(cell) != terrain_type:
			continue

		var region: RefCounted = ResourceRegionScript.new()
		region.setup(region_id, terrain_type)
		region_id += 1
		var queue: Array[Vector2i] = [cell]
		visited[cell] = true

		while not queue.is_empty():
			var current: Vector2i = queue.pop_back()
			region.add_cell(current)

			for direction in ORTHOGONAL_DIRECTIONS:
				var neighbor: Vector2i = current + direction
				if not grid.is_inside(neighbor):
					continue
				var neighbor_terrain: int = grid.get_terrain(neighbor)
				if neighbor_terrain == terrain_type:
					if not visited.has(neighbor):
						visited[neighbor] = true
						queue.append(neighbor)
				elif MapTypes.is_buildable_terrain(neighbor_terrain):
					region.add_adjacent_empty_cell(neighbor)

		regions.append(region)

	return regions


func scan_all_resource_regions(grid: RefCounted) -> Dictionary:
	return {
		MapTypes.TerrainType.FOREST: scan_regions(grid, MapTypes.TerrainType.FOREST),
		MapTypes.TerrainType.STONE: scan_regions(grid, MapTypes.TerrainType.STONE),
	}


func scan_farmable_regions(grid: RefCounted) -> Array:
	return scan_regions(grid, MapTypes.TerrainType.PLAIN)


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
