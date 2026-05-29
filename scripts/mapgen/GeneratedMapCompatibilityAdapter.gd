class_name GeneratedMapCompatibilityAdapter
extends RefCounted


const GeneratedTileDataScript := preload("res://scripts/mapgen/GeneratedTileData.gd")
const GridMapDataScript := preload("res://scripts/map/GridMapData.gd")
const MapTypes := preload("res://scripts/map/MapTypes.gd")
const ResourceRegionScannerScript := preload("res://scripts/map/ResourceRegionScanner.gd")


func build_legacy_grid(map_data) -> RefCounted:
	var grid := GridMapDataScript.new()
	if map_data == null:
		return grid

	grid.setup(map_data.width, map_data.height)

	for cell in map_data.get_all_cells():
		var tile = map_data.get_tile(cell)
		if tile == null:
			continue
		grid.set_terrain(cell, _to_legacy_terrain(tile))

	return grid


func build_legacy_context(map_data) -> Dictionary:
	var legacy_grid: RefCounted = build_legacy_grid(map_data)
	var scanner := ResourceRegionScannerScript.new()

	return {
		"grid": legacy_grid,
		"resource_regions": scanner.scan_all_resource_regions(legacy_grid),
		"farmable_regions": scanner.scan_farmable_regions(legacy_grid),
	}


func _to_legacy_terrain(tile) -> int:
	if tile == null:
		return MapTypes.TerrainType.EMPTY

	if tile.base_terrain == GeneratedTileDataScript.TERRAIN_WATER or tile.base_terrain == GeneratedTileDataScript.TERRAIN_SHALLOW_WATER:
		return MapTypes.TerrainType.WATER

	if tile.resource_type == GeneratedTileDataScript.RESOURCE_WOOD:
		return MapTypes.TerrainType.FOREST

	if tile.resource_type == GeneratedTileDataScript.RESOURCE_STONE:
		return MapTypes.TerrainType.STONE

	if tile.base_terrain == GeneratedTileDataScript.TERRAIN_PLAIN:
		return MapTypes.TerrainType.PLAIN

	if bool(tile.buildable):
		return MapTypes.TerrainType.EMPTY

	return MapTypes.TerrainType.WATER
