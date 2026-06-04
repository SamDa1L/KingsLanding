class_name WorldSemanticGovernanceAdapter
extends RefCounted


const GridMapDataScript := preload("res://scripts/map/GridMapData.gd")
const MapTypes := preload("res://scripts/map/MapTypes.gd")
const ResourceRegionScannerScript := preload("res://scripts/map/ResourceRegionScanner.gd")
const WorldGenerationIdentityScript := preload("res://scripts/mapgen/world/WorldGenerationIdentity.gd")
const WorldSemanticChunkScript := preload("res://scripts/mapgen/world/WorldSemanticChunk.gd")
const WorldSemanticGridScript := preload("res://scripts/mapgen/world/WorldSemanticGrid.gd")
const WorldSemanticStoreScript := preload("res://scripts/mapgen/world/WorldSemanticStore.gd")

const DEFAULT_BOOTSTRAP_TILE_RECT := Rect2i(Vector2i(-256, -256), Vector2i(512, 512))

var last_error: String = ""
var last_metrics: Dictionary = {}


func build_governance_bootstrap_context(
	identity: WorldGenerationIdentity,
	semantic_store: WorldSemanticStore,
	bootstrap_tile_rect: Rect2i = DEFAULT_BOOTSTRAP_TILE_RECT,
	runtime_chunks: Dictionary = {}
) -> Dictionary:
	last_error = ""
	last_metrics = {}

	var validation_error := _validate_inputs(identity, semantic_store, bootstrap_tile_rect, runtime_chunks)
	if not validation_error.is_empty():
		last_error = validation_error
		return {}

	var grid := GridMapDataScript.new()
	grid.resize(bootstrap_tile_rect.size.x, bootstrap_tile_rect.size.y)
	grid.fill_terrain(MapTypes.TerrainType.EMPTY)

	var terrain_counts := _create_terrain_counts()
	var ground_cells_read := 0
	var resource_cells_read := 0

	var min_chunk := WorldSemanticGridScript.world_cell_to_chunk_coords(bootstrap_tile_rect.position)
	var max_chunk := WorldSemanticGridScript.world_cell_to_chunk_coords(bootstrap_tile_rect.end - Vector2i.ONE)

	for chunk_y in range(min_chunk.y, max_chunk.y + 1):
		for chunk_x in range(min_chunk.x, max_chunk.x + 1):
			var chunk_coords := Vector2i(chunk_x, chunk_y)
			var chunk: WorldSemanticChunk = _borrow_semantic_chunk(chunk_coords, identity, semantic_store, runtime_chunks)
			if chunk == null:
				last_error = "Missing semantic chunk at %s for governance bootstrap rect %s" % [str(chunk_coords), str(bootstrap_tile_rect)]
				return {}

			var chunk_origin := WorldSemanticGridScript.chunk_coords_to_origin_cell(chunk_coords)
			var write_start_x := maxi(bootstrap_tile_rect.position.x, chunk_origin.x)
			var write_end_x := mini(bootstrap_tile_rect.end.x, chunk_origin.x + WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.x)
			var write_start_y := maxi(bootstrap_tile_rect.position.y, chunk_origin.y)
			var write_end_y := mini(bootstrap_tile_rect.end.y, chunk_origin.y + WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.y)

			for world_y in range(write_start_y, write_end_y):
				for world_x in range(write_start_x, write_end_x):
					var world_cell := Vector2i(world_x, world_y)
					var local_coords := world_cell - chunk_origin
					var local_index := WorldSemanticGridScript.local_coords_to_index(local_coords)
					var terrain_id := chunk.get_terrain_id_by_index(local_index)
					var resource_id := chunk.get_base_resource_id_by_index(local_index)
					var governance_terrain := _map_to_governance_terrain(terrain_id, resource_id)
					var grid_cell := world_cell - bootstrap_tile_rect.position

					grid.set_terrain(grid_cell, governance_terrain)
					terrain_counts[governance_terrain] = int(terrain_counts.get(governance_terrain, 0)) + 1
					ground_cells_read += 1
					if resource_id != WorldSemanticChunkScript.RESOURCE_NONE:
						resource_cells_read += 1

	var scanner := ResourceRegionScannerScript.new()
	var resource_regions: Dictionary = scanner.scan_all_resource_regions(grid)
	var farmable_regions: Array = scanner.scan_farmable_regions(grid)

	last_metrics = {
		"bootstrap_tile_rect": bootstrap_tile_rect,
		"ground_cells_read": ground_cells_read,
		"resource_cells_read": resource_cells_read,
		"forest_region_count": (resource_regions.get(MapTypes.TerrainType.FOREST, []) as Array).size(),
		"stone_region_count": (resource_regions.get(MapTypes.TerrainType.STONE, []) as Array).size(),
		"farmable_region_count": farmable_regions.size(),
	}

	return {
		"grid": grid,
		"resource_regions": resource_regions,
		"farmable_regions": farmable_regions,
		"used_rect": bootstrap_tile_rect,
		"cell_offset": bootstrap_tile_rect.position,
		"ground_cells_read": ground_cells_read,
		"resource_cells_read": resource_cells_read,
		"terrain_counts": terrain_counts,
	}


func _validate_inputs(
	identity: WorldGenerationIdentity,
	semantic_store: WorldSemanticStore,
	bootstrap_tile_rect: Rect2i,
	runtime_chunks: Dictionary
) -> String:
	if identity == null:
		return "WorldSemanticGovernanceAdapter requires non-null identity"
	if not identity.is_valid():
		return "WorldSemanticGovernanceAdapter requires valid identity"
	if semantic_store == null:
		return "WorldSemanticGovernanceAdapter requires non-null semantic store"
	if semantic_store.prewarm_state != WorldSemanticStoreScript.PrewarmState.READY:
		return "WorldSemanticGovernanceAdapter requires READY semantic store"
	if bootstrap_tile_rect.size.x <= 0 or bootstrap_tile_rect.size.y <= 0:
		return "WorldSemanticGovernanceAdapter requires positive bootstrap rect size"
	if int(semantic_store.expected_semantic_digest) != int(identity.semantic_digest):
		return "WorldSemanticGovernanceAdapter identity digest does not match store"
	if semantic_store.expected_semantic_hash256 != identity.semantic_hash256:
		return "WorldSemanticGovernanceAdapter identity hash does not match store"
	if semantic_store.expected_canonical_identity_bytes != identity.canonical_identity_bytes:
		return "WorldSemanticGovernanceAdapter canonical identity does not match store"

	for chunk_coords_variant in runtime_chunks.keys():
		if typeof(chunk_coords_variant) != TYPE_VECTOR2I:
			return "WorldSemanticGovernanceAdapter runtime_chunks keys must be Vector2i"
		var runtime_chunk = runtime_chunks[chunk_coords_variant]
		if runtime_chunk != null and not (runtime_chunk is WorldSemanticChunk):
			return "WorldSemanticGovernanceAdapter runtime_chunks values must be WorldSemanticChunk or null"

	return ""


func _borrow_semantic_chunk(
	chunk_coords: Vector2i,
	identity: WorldGenerationIdentity,
	semantic_store: WorldSemanticStore,
	runtime_chunks: Dictionary
) -> WorldSemanticChunk:
	if identity.prewarm_chunk_rect.has_point(chunk_coords):
		return semantic_store.borrow_readonly_chunk(chunk_coords)
	if runtime_chunks.has(chunk_coords):
		return runtime_chunks[chunk_coords] as WorldSemanticChunk
	return null


func _map_to_governance_terrain(terrain_id: int, resource_id: int) -> int:
	match resource_id:
		WorldSemanticChunkScript.RESOURCE_WOOD:
			return MapTypes.TerrainType.FOREST
		WorldSemanticChunkScript.RESOURCE_STONE:
			return MapTypes.TerrainType.STONE

	match terrain_id:
		WorldSemanticChunkScript.TERRAIN_PLAIN:
			return MapTypes.TerrainType.PLAIN
		WorldSemanticChunkScript.TERRAIN_SAND:
			return MapTypes.TerrainType.PLAIN
		WorldSemanticChunkScript.TERRAIN_WATER:
			return MapTypes.TerrainType.WATER
		WorldSemanticChunkScript.TERRAIN_SHALLOW_WATER:
			return MapTypes.TerrainType.WATER
		_:
			return MapTypes.TerrainType.EMPTY


func _create_terrain_counts() -> Dictionary:
	return {
		MapTypes.TerrainType.TOWN_CENTER: 0,
		MapTypes.TerrainType.FOREST: 0,
		MapTypes.TerrainType.STONE: 0,
		MapTypes.TerrainType.PLAIN: 0,
		MapTypes.TerrainType.ROAD: 0,
		MapTypes.TerrainType.EMPTY: 0,
		MapTypes.TerrainType.WATER: 0,
		MapTypes.TerrainType.MOUNTAIN: 0,
	}
