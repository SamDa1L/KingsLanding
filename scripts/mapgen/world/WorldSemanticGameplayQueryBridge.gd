class_name WorldSemanticGameplayQueryBridge
extends RefCounted


const MapTypes := preload("res://scripts/map/MapTypes.gd")
const ResourcePatchGeneratorScript := preload("res://scripts/mapgen/ResourcePatchGenerator.gd")
const ResourceRegionScript := preload("res://scripts/map/ResourceRegion.gd")
const WorldSemanticChunkScript := preload("res://scripts/mapgen/world/WorldSemanticChunk.gd")
const WorldSemanticGridScript := preload("res://scripts/mapgen/world/WorldSemanticGrid.gd")
const WorldSemanticStoreScript := preload("res://scripts/mapgen/world/WorldSemanticStore.gd")

const DYNAMIC_REGION_ID_START: int = 1000000

var current_identity: RefCounted = null
var semantic_store: RefCounted = null
var gameplay_cell_offset: Vector2i = Vector2i.ZERO
var last_error: String = ""

var _generator: RefCounted = ResourcePatchGeneratorScript.new()
var _runtime_semantic_chunks: Dictionary = {}
var _resource_region_cache_by_key: Dictionary = {}
var _resource_region_id_by_key: Dictionary = {}
var _next_dynamic_region_id: int = DYNAMIC_REGION_ID_START


func setup(
	next_identity: RefCounted,
	next_store: RefCounted,
	next_gameplay_cell_offset: Vector2i
) -> bool:
	last_error = ""
	_runtime_semantic_chunks.clear()
	_resource_region_cache_by_key.clear()
	_resource_region_id_by_key.clear()
	_next_dynamic_region_id = DYNAMIC_REGION_ID_START

	if next_identity == null or not next_identity.is_valid():
		last_error = "WorldSemanticGameplayQueryBridge.setup requires a valid identity"
		return false
	if next_store == null or next_store.prewarm_state != WorldSemanticStoreScript.PrewarmState.READY:
		last_error = "WorldSemanticGameplayQueryBridge.setup requires a READY semantic store"
		return false
	if int(next_store.expected_semantic_digest) != int(next_identity.semantic_digest):
		last_error = "WorldSemanticGameplayQueryBridge.setup identity digest does not match store"
		return false
	if next_store.expected_semantic_hash256 != next_identity.semantic_hash256:
		last_error = "WorldSemanticGameplayQueryBridge.setup identity hash does not match store"
		return false
	if next_store.expected_canonical_identity_bytes != next_identity.canonical_identity_bytes:
		last_error = "WorldSemanticGameplayQueryBridge.setup canonical identity does not match store"
		return false

	current_identity = next_identity
	semantic_store = next_store
	gameplay_cell_offset = next_gameplay_cell_offset
	return true


func local_cell_to_world_cell(local_cell: Vector2i) -> Vector2i:
	return local_cell + gameplay_cell_offset


func get_terrain(local_cell: Vector2i) -> int:
	var sample: Dictionary = _get_semantic_sample(local_cell_to_world_cell(local_cell))
	if sample.is_empty():
		return WorldSemanticStoreScript.QUERY_MISS
	return _map_to_governance_terrain(
		int(sample.get("terrain_id", WorldSemanticStoreScript.QUERY_MISS)),
		int(sample.get("base_resource_id", WorldSemanticChunkScript.RESOURCE_NONE))
	)


func find_resource_region_for_building_cell(local_cell: Vector2i, resource_terrain: int) -> RefCounted:
	var world_cell: Vector2i = local_cell_to_world_cell(local_cell)
	for direction in MapTypes.get_cardinal_directions():
		var neighbor_world_cell: Vector2i = world_cell + direction
		var neighbor_sample: Dictionary = _get_semantic_sample(neighbor_world_cell)
		if neighbor_sample.is_empty():
			continue
		var neighbor_governance_terrain: int = _map_to_governance_terrain(
			int(neighbor_sample.get("terrain_id", WorldSemanticStoreScript.QUERY_MISS)),
			int(neighbor_sample.get("base_resource_id", WorldSemanticChunkScript.RESOURCE_NONE))
		)
		if neighbor_governance_terrain != resource_terrain:
			continue

		var payload_variant: Variant = neighbor_sample.get("base_patch_key_payload", null)
		if typeof(payload_variant) != TYPE_ARRAY:
			continue
		var payload_array: Array = payload_variant
		if payload_array.size() != WorldSemanticStoreScript.PATCH_PAYLOAD_STRIDE:
			continue

		var payload: PackedInt32Array = PackedInt32Array([
			int(payload_array[0]),
			int(payload_array[1]),
			int(payload_array[2]),
		])
		return _get_or_build_resource_region(neighbor_world_cell, payload, resource_terrain)
	return null


func find_farmable_region_for_cell(local_cell: Vector2i) -> RefCounted:
	if get_terrain(local_cell) != MapTypes.TerrainType.PLAIN:
		return null
	var region: RefCounted = ResourceRegionScript.new()
	region.setup(_build_farm_region_id(local_cell), MapTypes.TerrainType.PLAIN)
	region.add_cell(local_cell)
	return region


func build_regions_by_id_for_buildings(base_regions_by_id: Dictionary, buildings: Array) -> Dictionary:
	var merged_regions_by_id: Dictionary = base_regions_by_id.duplicate(true)
	for building_variant in buildings:
		var building: RefCounted = building_variant
		if building == null:
			continue
		if not bool(building.get("is_active")):
			continue
		var terrain_type: int = _get_required_region_terrain(int(building.get("building_type")))
		if terrain_type < 0:
			continue
		if _has_region_in_dictionary(merged_regions_by_id, terrain_type, int(building.get("linked_region_id"))):
			continue
		var region: RefCounted = find_resource_region_for_building_cell(building.get("position"), terrain_type)
		if region == null:
			continue
		var regions_for_terrain: Dictionary = {}
		if merged_regions_by_id.has(terrain_type) and merged_regions_by_id[terrain_type] is Dictionary:
			regions_for_terrain = merged_regions_by_id[terrain_type]
		regions_for_terrain[int(region.get("region_id"))] = region
		merged_regions_by_id[terrain_type] = regions_for_terrain
	return merged_regions_by_id


func get_runtime_cached_chunk_count() -> int:
	return _runtime_semantic_chunks.size()


func _get_or_build_resource_region(
	seed_world_cell: Vector2i,
	payload: PackedInt32Array,
	resource_terrain: int
) -> RefCounted:
	var cache_key: String = _build_resource_region_cache_key(payload)
	if _resource_region_cache_by_key.has(cache_key):
		return _resource_region_cache_by_key[cache_key]

	var region: RefCounted = ResourceRegionScript.new()
	region.setup(_allocate_dynamic_region_id(cache_key), resource_terrain)

	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [seed_world_cell]

	while not queue.is_empty():
		var current_world_cell: Vector2i = queue.pop_back()
		if visited.has(current_world_cell):
			continue
		visited[current_world_cell] = true

		if not _world_cell_matches_resource_payload(current_world_cell, payload, resource_terrain):
			continue

		region.add_cell(current_world_cell - gameplay_cell_offset)

		for direction in MapTypes.get_cardinal_directions():
			var neighbor_world_cell: Vector2i = current_world_cell + direction
			if visited.has(neighbor_world_cell):
				continue
			if _world_cell_matches_resource_payload(neighbor_world_cell, payload, resource_terrain):
				queue.append(neighbor_world_cell)
				continue
			var neighbor_terrain: int = get_terrain(neighbor_world_cell - gameplay_cell_offset)
			if MapTypes.is_buildable_terrain(neighbor_terrain):
				region.add_adjacent_empty_cell(neighbor_world_cell - gameplay_cell_offset)
	_resource_region_cache_by_key[cache_key] = region
	return region


func _world_cell_matches_resource_payload(world_cell: Vector2i, payload: PackedInt32Array, resource_terrain: int) -> bool:
	var sample: Dictionary = _get_semantic_sample(world_cell)
	if sample.is_empty():
		return false
	var terrain_type: int = _map_to_governance_terrain(
		int(sample.get("terrain_id", WorldSemanticStoreScript.QUERY_MISS)),
		int(sample.get("base_resource_id", WorldSemanticChunkScript.RESOURCE_NONE))
	)
	if terrain_type != resource_terrain:
		return false
	var payload_variant: Variant = sample.get("base_patch_key_payload", null)
	if typeof(payload_variant) != TYPE_ARRAY:
		return false
	var payload_array: Array = payload_variant
	if payload_array.size() != WorldSemanticStoreScript.PATCH_PAYLOAD_STRIDE:
		return false
	return (
		int(payload_array[0]) == int(payload[0])
		and int(payload_array[1]) == int(payload[1])
		and int(payload_array[2]) == int(payload[2])
	)


func _get_semantic_sample(world_cell: Vector2i) -> Dictionary:
	var chunk: RefCounted = _borrow_semantic_chunk(world_cell)
	if chunk == null:
		return {}
	var local_index: int = WorldSemanticGridScript.world_cell_to_local_index(world_cell)
	var payload_variant: Variant = null
	var patch_payload: PackedInt32Array = PackedInt32Array([0, 0, 0])
	var patch_lookup: int = _copy_patch_payload(chunk, local_index, patch_payload)
	if patch_lookup == WorldSemanticStoreScript.PatchLookupResult.FOUND:
		payload_variant = [
			int(patch_payload[0]),
			int(patch_payload[1]),
			int(patch_payload[2]),
		]
	return {
		"terrain_id": chunk.get_terrain_id_by_index(local_index),
		"base_resource_id": chunk.get_base_resource_id_by_index(local_index),
		"flags": chunk.get_flags_by_index(local_index),
		"base_resource_amount": chunk.get_base_resource_amount_by_index(local_index),
		"base_patch_key_payload": payload_variant,
	}


func _borrow_semantic_chunk(world_cell: Vector2i) -> RefCounted:
	if current_identity == null or semantic_store == null:
		return null
	var chunk_coords: Vector2i = WorldSemanticGridScript.world_cell_to_chunk_coords(world_cell)
	if semantic_store.has_chunk(chunk_coords):
		return semantic_store.borrow_readonly_chunk(chunk_coords)
	if _runtime_semantic_chunks.has(chunk_coords):
		return _runtime_semantic_chunks[chunk_coords]

	var chunk_result: Dictionary = _generator.build_base_semantics_for_chunk_packed(chunk_coords, current_identity)
	if chunk_result.is_empty():
		last_error = "WorldSemanticGameplayQueryBridge failed to build chunk %s" % str(chunk_coords)
		return null
	var validation_error: String = WorldSemanticChunkScript.validate_result(chunk_result)
	if not validation_error.is_empty():
		last_error = validation_error
		return null
	var chunk: RefCounted = WorldSemanticChunkScript.from_validated_result(chunk_result)
	if chunk == null:
		last_error = "WorldSemanticGameplayQueryBridge failed to instantiate chunk %s" % str(chunk_coords)
		return null
	_runtime_semantic_chunks[chunk_coords] = chunk
	return chunk


func _copy_patch_payload(chunk: RefCounted, local_index: int, out_payload: PackedInt32Array) -> int:
	if chunk.get_base_resource_id_by_index(local_index) == WorldSemanticChunkScript.RESOURCE_NONE:
		return WorldSemanticStoreScript.PatchLookupResult.NONE
	if chunk.copy_patch_payload_by_index(local_index, out_payload) == WorldSemanticChunkScript.INVALID_INDEX:
		return WorldSemanticStoreScript.PatchLookupResult.MISS
	return WorldSemanticStoreScript.PatchLookupResult.FOUND


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


func _get_required_region_terrain(building_type: int) -> int:
	match building_type:
		MapTypes.BuildingType.LUMBER_CAMP:
			return MapTypes.TerrainType.FOREST
		MapTypes.BuildingType.QUARRY:
			return MapTypes.TerrainType.STONE
		_:
			return -1


func _has_region_in_dictionary(regions_by_id: Dictionary, terrain_type: int, region_id: int) -> bool:
	if region_id < 0:
		return false
	if not regions_by_id.has(terrain_type):
		return false
	if not (regions_by_id[terrain_type] is Dictionary):
		return false
	var regions_for_terrain: Dictionary = regions_by_id[terrain_type]
	return regions_for_terrain.has(region_id)


func _build_resource_region_cache_key(payload: PackedInt32Array) -> String:
	return "%d:%d:%d" % [int(payload[0]), int(payload[1]), int(payload[2])]


func _allocate_dynamic_region_id(cache_key: String) -> int:
	if _resource_region_id_by_key.has(cache_key):
		return int(_resource_region_id_by_key[cache_key])
	var region_id: int = _next_dynamic_region_id
	_next_dynamic_region_id += 1
	_resource_region_id_by_key[cache_key] = region_id
	return region_id


func _build_farm_region_id(local_cell: Vector2i) -> int:
	var normalized_x: int = local_cell.x & 0x7fff
	var normalized_y: int = local_cell.y & 0x7fff
	return (normalized_x << 15) ^ normalized_y
