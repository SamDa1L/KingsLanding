class_name WorldSemanticMapSave
extends RefCounted


const GridMapDataScript := preload("res://scripts/map/GridMapData.gd")
const ResourceRegionScript := preload("res://scripts/map/ResourceRegion.gd")
const WorldGenerationIdentityScript := preload("res://scripts/mapgen/world/WorldGenerationIdentity.gd")
const WorldSemanticChunkScript := preload("res://scripts/mapgen/world/WorldSemanticChunk.gd")
const WorldSemanticStoreScript := preload("res://scripts/mapgen/world/WorldSemanticStore.gd")

const LEGACY_SAVE_VERSION: int = 1
const SAVE_VERSION_WITH_BOOTSTRAP_CACHE: int = 2
const SAVE_VERSION: int = 3
const GAMEPLAY_STATE_VERSION: int = 1
const LEGACY_BOOTSTRAP_CACHE_VERSION: int = 1
const BOOTSTRAP_CACHE_VERSION: int = 2
const CHUNK_STORAGE_VERSION: int = 2
const DEFAULT_SAVE_PATH := "user://prewarmed_semantic_gameplay_map.save"


static func has_save(save_path: String = DEFAULT_SAVE_PATH) -> bool:
	return FileAccess.file_exists(save_path)


static func delete_save(save_path: String = DEFAULT_SAVE_PATH) -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)


static func save_world(
	identity: WorldGenerationIdentity,
	semantic_store: WorldSemanticStore,
	runtime_chunks: Dictionary,
	camera_cell: Vector2i,
	camera_zoom: float,
	governance_bootstrap_context: Dictionary = {},
	save_path: String = DEFAULT_SAVE_PATH,
	gameplay_state: Dictionary = {}
) -> bool:
	if identity == null or not identity.is_valid():
		return false
	if semantic_store == null or semantic_store.prewarm_state != WorldSemanticStoreScript.PrewarmState.READY:
		return false

	var save_data: Dictionary = {
		"save_version": SAVE_VERSION,
		"identity": _identity_to_data(identity),
		"prewarm_chunks": _chunks_to_compact_data(semantic_store.chunks),
		"runtime_chunks": _chunks_to_compact_data(runtime_chunks),
		"camera_cell": camera_cell,
		"camera_zoom": camera_zoom,
		"governance_bootstrap_cache": bootstrap_context_to_cache_dto(identity, governance_bootstrap_context),
		"gameplay_state": _sanitize_gameplay_state(gameplay_state),
	}

	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_var(save_data, true)
	return true


static func load_world(save_path: String = DEFAULT_SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}

	var save_data_variant: Variant = file.get_var(true)
	if typeof(save_data_variant) != TYPE_DICTIONARY:
		return {}
	var save_data: Dictionary = save_data_variant
	var save_version: int = int(save_data.get("save_version", 0))
	if not _is_supported_save_version(save_version):
		return {}

	var identity: WorldGenerationIdentity = _identity_from_data(save_data.get("identity", {}))
	if identity == null or not identity.is_valid():
		return {}

	var prewarm_chunks: Dictionary = _chunks_from_serialized_data(save_data.get("prewarm_chunks", []))
	if prewarm_chunks.is_empty():
		return {}

	var runtime_chunks: Dictionary = _chunks_from_serialized_data(save_data.get("runtime_chunks", []))
	var governance_bootstrap_cache: Dictionary = _sanitize_bootstrap_cache_dto(save_data.get("governance_bootstrap_cache", {}))
	var store: WorldSemanticStore = WorldSemanticStoreScript.new()
	if not store.restore_ready_from_chunks(identity, prewarm_chunks):
		return {}

	return {
		"identity": identity,
		"semantic_store": store,
		"runtime_chunks": runtime_chunks,
		"camera_cell": save_data.get("camera_cell", Vector2i.ZERO),
		"camera_zoom": float(save_data.get("camera_zoom", 1.0)),
		"governance_bootstrap_cache": governance_bootstrap_cache,
		"gameplay_state": _sanitize_gameplay_state(save_data.get("gameplay_state", {})),
	}


static func bootstrap_context_to_cache_dto(
	identity: WorldGenerationIdentity,
	bootstrap_context: Dictionary
) -> Dictionary:
	if identity == null or not identity.is_valid():
		return {}
	if bootstrap_context.is_empty():
		return {}

	var grid: GridMapData = bootstrap_context.get("grid", null)
	if grid == null:
		return {}
	if grid.width <= 0 or grid.height <= 0:
		return {}

	var used_rect: Rect2i = bootstrap_context.get("used_rect", Rect2i(Vector2i.ZERO, Vector2i.ZERO))
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return {}

	var cell_offset: Vector2i = bootstrap_context.get("cell_offset", used_rect.position)
	var bootstrap_tile_rect: Rect2i = bootstrap_context.get("bootstrap_tile_rect", used_rect)
	var terrain_ids: PackedInt32Array = _grid_to_terrain_ids(grid)
	if terrain_ids.size() != grid.width * grid.height:
		return {}

	var resource_region_payload: Dictionary = _build_compact_region_payload_from_resource_dictionary(
		bootstrap_context.get("resource_regions", {})
	)
	var farmable_region_payload: Dictionary = _build_compact_region_payload_from_array(
		bootstrap_context.get("farmable_regions", [])
	)
	if resource_region_payload.is_empty() or farmable_region_payload.is_empty():
		return {}

	var cache_dto: Dictionary = {
		"bootstrap_cache_version": BOOTSTRAP_CACHE_VERSION,
		"semantic_digest": int(identity.semantic_digest),
		"semantic_hash256": identity.semantic_hash256,
		"canonical_identity_bytes": identity.canonical_identity_bytes,
		"bootstrap_tile_rect": bootstrap_tile_rect,
		"used_rect": used_rect,
		"cell_offset": cell_offset,
		"ground_cells_read": int(bootstrap_context.get("ground_cells_read", 0)),
		"resource_cells_read": int(bootstrap_context.get("resource_cells_read", 0)),
		"terrain_counts": (bootstrap_context.get("terrain_counts", {}) as Dictionary).duplicate(true),
		"grid_width": int(grid.width),
		"grid_height": int(grid.height),
		"grid_terrain_ids": terrain_ids,
		"grid_blocks_movement": _grid_to_blocks_movement(grid),
	}
	_append_compact_region_payload(cache_dto, "resource_", resource_region_payload)
	_append_compact_region_payload(cache_dto, "farmable_", farmable_region_payload)
	return cache_dto


static func bootstrap_cache_dto_to_context(
	cache_dto: Dictionary,
	expected_identity: WorldGenerationIdentity = null,
	expected_bootstrap_tile_rect: Rect2i = Rect2i()
) -> Dictionary:
	var sanitized_cache: Dictionary = _sanitize_bootstrap_cache_dto(cache_dto)
	if sanitized_cache.is_empty():
		return {}
	if expected_identity != null:
		var validation_error := validate_bootstrap_cache_dto_identity(
			sanitized_cache,
			expected_identity,
			expected_bootstrap_tile_rect
		)
		if not validation_error.is_empty():
			return {}

	var grid: GridMapData = _grid_from_cache_dto(sanitized_cache)
	if grid == null:
		return {}

	return {
		"grid": grid,
		"resource_regions": _resource_regions_from_cache_dto(sanitized_cache),
		"farmable_regions": _farmable_regions_from_cache_dto(sanitized_cache),
		"bootstrap_tile_rect": sanitized_cache.get("bootstrap_tile_rect", Rect2i(Vector2i.ZERO, Vector2i.ZERO)),
		"used_rect": sanitized_cache.get("used_rect", Rect2i(Vector2i.ZERO, Vector2i.ZERO)),
		"cell_offset": sanitized_cache.get("cell_offset", Vector2i.ZERO),
		"ground_cells_read": int(sanitized_cache.get("ground_cells_read", 0)),
		"resource_cells_read": int(sanitized_cache.get("resource_cells_read", 0)),
		"terrain_counts": (sanitized_cache.get("terrain_counts", {}) as Dictionary).duplicate(true),
	}


static func validate_bootstrap_cache_dto_identity(
	cache_dto: Dictionary,
	expected_identity: WorldGenerationIdentity,
	expected_bootstrap_tile_rect: Rect2i = Rect2i()
) -> String:
	if expected_identity == null or not expected_identity.is_valid():
		return "bootstrap cache requires valid expected identity"

	var sanitized_cache: Dictionary = _sanitize_bootstrap_cache_dto(cache_dto)
	if sanitized_cache.is_empty():
		return "bootstrap cache dto is empty or invalid"
	var bootstrap_cache_version: int = int(sanitized_cache.get("bootstrap_cache_version", 0))
	if bootstrap_cache_version != LEGACY_BOOTSTRAP_CACHE_VERSION and bootstrap_cache_version != BOOTSTRAP_CACHE_VERSION:
		return "bootstrap cache version mismatch"
	if int(sanitized_cache.get("semantic_digest", 0)) != int(expected_identity.semantic_digest):
		return "bootstrap cache semantic digest mismatch"

	var cached_hash256: PackedByteArray = sanitized_cache.get("semantic_hash256", PackedByteArray())
	if cached_hash256 != expected_identity.semantic_hash256:
		return "bootstrap cache semantic hash256 mismatch"

	var cached_canonical_identity_bytes: PackedByteArray = sanitized_cache.get("canonical_identity_bytes", PackedByteArray())
	if cached_canonical_identity_bytes != expected_identity.canonical_identity_bytes:
		return "bootstrap cache canonical identity mismatch"

	if expected_bootstrap_tile_rect.size.x > 0 and expected_bootstrap_tile_rect.size.y > 0:
		var cached_bootstrap_tile_rect: Rect2i = sanitized_cache.get("bootstrap_tile_rect", Rect2i())
		if cached_bootstrap_tile_rect != expected_bootstrap_tile_rect:
			return "bootstrap cache bootstrap tile rect mismatch"

	return ""


static func _is_supported_save_version(save_version: int) -> bool:
	return (
		save_version == LEGACY_SAVE_VERSION
		or save_version == SAVE_VERSION_WITH_BOOTSTRAP_CACHE
		or save_version == SAVE_VERSION
	)


static func _sanitize_gameplay_state(gameplay_state_variant: Variant) -> Dictionary:
	if typeof(gameplay_state_variant) != TYPE_DICTIONARY:
		return {}
	var gameplay_state: Dictionary = gameplay_state_variant
	if gameplay_state.is_empty():
		return {}
	var gameplay_state_version: int = int(gameplay_state.get("gameplay_state_version", 0))
	if gameplay_state_version != GAMEPLAY_STATE_VERSION:
		return {}
	return gameplay_state.duplicate(true)


static func _identity_to_data(identity: WorldGenerationIdentity) -> Dictionary:
	return {
		"seed": int(identity.seed),
		"generator_version": String(identity.generator_version),
		"deterministic_hash_version": String(identity.deterministic_hash_version),
		"terrain_backend_id": String(identity.terrain_backend_id),
		"generator_parameter_profile": identity.generator_parameter_profile,
		"semantic_digest_version": int(identity.semantic_digest_version),
	}


static func _identity_from_data(data: Variant) -> WorldGenerationIdentity:
	if typeof(data) != TYPE_DICTIONARY:
		return null

	var dictionary: Dictionary = data
	return WorldGenerationIdentityScript.create(
		int(dictionary.get("seed", 0)),
		String(dictionary.get("generator_version", WorldGenerationIdentityScript.DEFAULT_GENERATOR_VERSION)),
		String(dictionary.get("deterministic_hash_version", WorldGenerationIdentityScript.DEFAULT_DETERMINISTIC_HASH_VERSION)),
		String(dictionary.get("terrain_backend_id", WorldGenerationIdentityScript.DEFAULT_TERRAIN_BACKEND_ID)),
		dictionary.get("generator_parameter_profile", {}),
		int(dictionary.get("semantic_digest_version", WorldGenerationIdentityScript.DEFAULT_SEMANTIC_DIGEST_VERSION))
	)


static func _chunks_to_compact_data(chunks: Dictionary) -> Dictionary:
	var chunk_coords_data := PackedInt32Array()
	var terrain_ids_list: Array = []
	var base_resource_ids_list: Array = []
	var flags_list: Array = []
	var base_resource_amounts_list: Array = []
	var base_patch_key_indices_list: Array = []
	var patch_key_table_data_list: Array = []

	for chunk_coords_variant in chunks.keys():
		if typeof(chunk_coords_variant) != TYPE_VECTOR2I:
			continue
		var chunk_coords: Vector2i = chunk_coords_variant
		var chunk: WorldSemanticChunk = chunks[chunk_coords_variant]
		if chunk == null:
			continue
		chunk_coords_data.append(chunk_coords.x)
		chunk_coords_data.append(chunk_coords.y)
		terrain_ids_list.append(chunk.terrain_ids)
		base_resource_ids_list.append(chunk.base_resource_ids)
		flags_list.append(chunk.flags)
		base_resource_amounts_list.append(chunk.base_resource_amounts)
		base_patch_key_indices_list.append(chunk.base_patch_key_indices)
		patch_key_table_data_list.append(chunk.patch_key_table_data)

	return {
		"chunk_storage_version": CHUNK_STORAGE_VERSION,
		"chunk_count": int(chunk_coords_data.size() / 2),
		"chunk_coords": chunk_coords_data,
		"terrain_ids_list": terrain_ids_list,
		"base_resource_ids_list": base_resource_ids_list,
		"flags_list": flags_list,
		"base_resource_amounts_list": base_resource_amounts_list,
		"base_patch_key_indices_list": base_patch_key_indices_list,
		"patch_key_table_data_list": patch_key_table_data_list,
	}


static func _chunks_from_serialized_data(chunks_data_variant: Variant) -> Dictionary:
	if typeof(chunks_data_variant) == TYPE_ARRAY:
		return _chunks_from_legacy_data(chunks_data_variant)
	if typeof(chunks_data_variant) == TYPE_DICTIONARY:
		return _chunks_from_compact_data(chunks_data_variant)
	return {}


static func _chunks_from_compact_data(chunks_data_variant: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(chunks_data_variant) != TYPE_DICTIONARY:
		return result

	var chunks_data: Dictionary = chunks_data_variant
	if int(chunks_data.get("chunk_storage_version", 0)) != CHUNK_STORAGE_VERSION:
		return result
	if typeof(chunks_data.get("chunk_coords", PackedInt32Array())) != TYPE_PACKED_INT32_ARRAY:
		return result
	if typeof(chunks_data.get("terrain_ids_list", [])) != TYPE_ARRAY:
		return result
	if typeof(chunks_data.get("base_resource_ids_list", [])) != TYPE_ARRAY:
		return result
	if typeof(chunks_data.get("flags_list", [])) != TYPE_ARRAY:
		return result
	if typeof(chunks_data.get("base_resource_amounts_list", [])) != TYPE_ARRAY:
		return result
	if typeof(chunks_data.get("base_patch_key_indices_list", [])) != TYPE_ARRAY:
		return result
	if typeof(chunks_data.get("patch_key_table_data_list", [])) != TYPE_ARRAY:
		return result

	var chunk_coords_data: PackedInt32Array = chunks_data.get("chunk_coords", PackedInt32Array())
	if chunk_coords_data.size() % 2 != 0:
		return result

	var expected_chunk_count: int = int(chunks_data.get("chunk_count", int(chunk_coords_data.size() / 2)))
	var terrain_ids_list: Array = chunks_data.get("terrain_ids_list", [])
	var base_resource_ids_list: Array = chunks_data.get("base_resource_ids_list", [])
	var flags_list: Array = chunks_data.get("flags_list", [])
	var base_resource_amounts_list: Array = chunks_data.get("base_resource_amounts_list", [])
	var base_patch_key_indices_list: Array = chunks_data.get("base_patch_key_indices_list", [])
	var patch_key_table_data_list: Array = chunks_data.get("patch_key_table_data_list", [])

	if int(chunk_coords_data.size() / 2) != expected_chunk_count:
		return result
	if terrain_ids_list.size() != expected_chunk_count or base_resource_ids_list.size() != expected_chunk_count:
		return result
	if flags_list.size() != expected_chunk_count or base_resource_amounts_list.size() != expected_chunk_count:
		return result
	if base_patch_key_indices_list.size() != expected_chunk_count or patch_key_table_data_list.size() != expected_chunk_count:
		return result

	for chunk_index in range(expected_chunk_count):
		var chunk_result: Dictionary = {
			"chunk_coords": Vector2i(
				int(chunk_coords_data[chunk_index * 2]),
				int(chunk_coords_data[chunk_index * 2 + 1])
			),
			"terrain_ids": terrain_ids_list[chunk_index],
			"base_resource_ids": base_resource_ids_list[chunk_index],
			"flags": flags_list[chunk_index],
			"base_resource_amounts": base_resource_amounts_list[chunk_index],
			"base_patch_key_indices": base_patch_key_indices_list[chunk_index],
			"patch_key_table_data": patch_key_table_data_list[chunk_index],
		}
		var validation_error: String = WorldSemanticChunkScript.validate_result(chunk_result)
		if not validation_error.is_empty():
			return {}
		var chunk: WorldSemanticChunk = WorldSemanticChunkScript.from_validated_result(chunk_result)
		if chunk == null:
			return {}
		result[chunk.chunk_coords] = chunk
	return result


static func _chunks_from_legacy_data(chunks_data: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(chunks_data) != TYPE_ARRAY:
		return result

	for chunk_data_variant in chunks_data:
		if typeof(chunk_data_variant) != TYPE_DICTIONARY:
			continue
		var chunk_data: Dictionary = chunk_data_variant
		var validation_error := WorldSemanticChunkScript.validate_result(chunk_data)
		if not validation_error.is_empty():
			continue
		var chunk: WorldSemanticChunk = WorldSemanticChunkScript.from_validated_result(chunk_data)
		if chunk == null:
			continue
		result[chunk.chunk_coords] = chunk
	return result


static func _sanitize_bootstrap_cache_dto(cache_dto_variant: Variant) -> Dictionary:
	if typeof(cache_dto_variant) != TYPE_DICTIONARY:
		return {}

	var cache_dto: Dictionary = cache_dto_variant
	var bootstrap_cache_version: int = int(cache_dto.get("bootstrap_cache_version", 0))
	if bootstrap_cache_version == LEGACY_BOOTSTRAP_CACHE_VERSION:
		return _sanitize_bootstrap_cache_dto_v1(cache_dto)
	if bootstrap_cache_version == BOOTSTRAP_CACHE_VERSION:
		return _sanitize_bootstrap_cache_dto_v2(cache_dto)
	return {}


static func _sanitize_bootstrap_cache_dto_v1(cache_dto: Dictionary) -> Dictionary:
	if typeof(cache_dto.get("bootstrap_tile_rect", Rect2i())) != TYPE_RECT2I:
		return {}
	if typeof(cache_dto.get("used_rect", Rect2i())) != TYPE_RECT2I:
		return {}
	if typeof(cache_dto.get("cell_offset", Vector2i.ZERO)) != TYPE_VECTOR2I:
		return {}
	if typeof(cache_dto.get("semantic_hash256", PackedByteArray())) != TYPE_PACKED_BYTE_ARRAY:
		return {}
	if typeof(cache_dto.get("canonical_identity_bytes", PackedByteArray())) != TYPE_PACKED_BYTE_ARRAY:
		return {}
	if typeof(cache_dto.get("grid_terrain_ids", PackedInt32Array())) != TYPE_PACKED_INT32_ARRAY:
		return {}
	if cache_dto.has("grid_blocks_movement") and typeof(cache_dto.get("grid_blocks_movement", PackedByteArray())) != TYPE_PACKED_BYTE_ARRAY:
		return {}
	if typeof(cache_dto.get("resource_region_dtos", [])) != TYPE_ARRAY:
		return {}
	if typeof(cache_dto.get("farmable_region_dtos", [])) != TYPE_ARRAY:
		return {}
	if typeof(cache_dto.get("terrain_counts", {})) != TYPE_DICTIONARY:
		return {}

	var grid_width: int = int(cache_dto.get("grid_width", 0))
	var grid_height: int = int(cache_dto.get("grid_height", 0))
	if grid_width <= 0 or grid_height <= 0:
		return {}
	var terrain_ids: PackedInt32Array = cache_dto.get("grid_terrain_ids", PackedInt32Array())
	if terrain_ids.size() != grid_width * grid_height:
		return {}
	if cache_dto.has("grid_blocks_movement"):
		var blocks_movement: PackedByteArray = cache_dto.get("grid_blocks_movement", PackedByteArray())
		if blocks_movement.size() != grid_width * grid_height:
			return {}
	return cache_dto.duplicate(true)


static func _sanitize_bootstrap_cache_dto_v2(cache_dto: Dictionary) -> Dictionary:
	if typeof(cache_dto.get("bootstrap_tile_rect", Rect2i())) != TYPE_RECT2I:
		return {}
	if typeof(cache_dto.get("used_rect", Rect2i())) != TYPE_RECT2I:
		return {}
	if typeof(cache_dto.get("cell_offset", Vector2i.ZERO)) != TYPE_VECTOR2I:
		return {}
	if typeof(cache_dto.get("semantic_hash256", PackedByteArray())) != TYPE_PACKED_BYTE_ARRAY:
		return {}
	if typeof(cache_dto.get("canonical_identity_bytes", PackedByteArray())) != TYPE_PACKED_BYTE_ARRAY:
		return {}
	if typeof(cache_dto.get("grid_terrain_ids", PackedInt32Array())) != TYPE_PACKED_INT32_ARRAY:
		return {}
	if cache_dto.has("grid_blocks_movement") and typeof(cache_dto.get("grid_blocks_movement", PackedByteArray())) != TYPE_PACKED_BYTE_ARRAY:
		return {}
	if typeof(cache_dto.get("terrain_counts", {})) != TYPE_DICTIONARY:
		return {}

	var grid_width: int = int(cache_dto.get("grid_width", 0))
	var grid_height: int = int(cache_dto.get("grid_height", 0))
	if grid_width <= 0 or grid_height <= 0:
		return {}
	var terrain_ids: PackedInt32Array = cache_dto.get("grid_terrain_ids", PackedInt32Array())
	if terrain_ids.size() != grid_width * grid_height:
		return {}
	if cache_dto.has("grid_blocks_movement"):
		var blocks_movement: PackedByteArray = cache_dto.get("grid_blocks_movement", PackedByteArray())
		if blocks_movement.size() != grid_width * grid_height:
			return {}
	if not _validate_compact_region_payload(cache_dto, "resource_"):
		return {}
	if not _validate_compact_region_payload(cache_dto, "farmable_"):
		return {}
	return cache_dto.duplicate(true)


static func _grid_to_terrain_ids(grid: GridMapData) -> PackedInt32Array:
	var terrain_ids := PackedInt32Array()
	if grid == null:
		return terrain_ids

	terrain_ids.resize(grid.width * grid.height)
	var write_index: int = 0
	for y in range(grid.height):
		for x in range(grid.width):
			terrain_ids[write_index] = int(grid.get_terrain(Vector2i(x, y)))
			write_index += 1
	return terrain_ids


static func _grid_to_blocks_movement(grid: GridMapData) -> PackedByteArray:
	var blocks_movement := PackedByteArray()
	if grid == null:
		return blocks_movement

	blocks_movement.resize(grid.width * grid.height)
	var write_index: int = 0
	for y in range(grid.height):
		for x in range(grid.width):
			blocks_movement[write_index] = 1 if grid.get_blocks_movement(Vector2i(x, y)) else 0
			write_index += 1
	return blocks_movement


static func _grid_from_cache_dto(cache_dto: Dictionary) -> GridMapData:
	var grid_width: int = int(cache_dto.get("grid_width", 0))
	var grid_height: int = int(cache_dto.get("grid_height", 0))
	var terrain_ids: PackedInt32Array = cache_dto.get("grid_terrain_ids", PackedInt32Array())
	var blocks_movement: PackedByteArray = cache_dto.get("grid_blocks_movement", PackedByteArray())
	if grid_width <= 0 or grid_height <= 0:
		return null
	if terrain_ids.size() != grid_width * grid_height:
		return null
	if blocks_movement.size() > 0 and blocks_movement.size() != grid_width * grid_height:
		return null

	var grid := GridMapDataScript.new()
	grid.resize(grid_width, grid_height)
	var read_index: int = 0
	for y in range(grid_height):
		for x in range(grid_width):
			var cell := Vector2i(x, y)
			grid.set_terrain(cell, int(terrain_ids[read_index]))
			if blocks_movement.size() > 0:
				grid.set_blocks_movement(cell, blocks_movement[read_index] != 0)
			read_index += 1
	return grid


static func _build_compact_region_payload_from_resource_dictionary(resource_regions_variant: Variant) -> Dictionary:
	if typeof(resource_regions_variant) != TYPE_DICTIONARY:
		return {}

	var flattened_regions: Array = []
	var resource_regions: Dictionary = resource_regions_variant
	for terrain_type_variant in resource_regions.keys():
		var regions_variant: Variant = resource_regions[terrain_type_variant]
		if typeof(regions_variant) != TYPE_ARRAY:
			continue
		for region_variant in regions_variant:
			flattened_regions.append(region_variant)
	return _build_compact_region_payload_from_array(flattened_regions)


static func _build_compact_region_payload_from_array(regions_variant: Variant) -> Dictionary:
	if typeof(regions_variant) != TYPE_ARRAY:
		return {}

	var region_ids := PackedInt32Array()
	var terrain_types := PackedInt32Array()
	var cell_starts := PackedInt32Array()
	var cell_counts := PackedInt32Array()
	var cells_flat := PackedInt32Array()
	var adjacent_starts := PackedInt32Array()
	var adjacent_counts := PackedInt32Array()
	var adjacent_cells_flat := PackedInt32Array()

	var regions: Array = regions_variant
	for region_variant in regions:
		if region_variant == null or not (region_variant is ResourceRegion):
			continue
		var region: ResourceRegion = region_variant
		region_ids.append(int(region.region_id))
		terrain_types.append(int(region.terrain_type))
		cell_starts.append(int(cells_flat.size() / 2))
		cell_counts.append(region.cells.size())
		for cell in region.cells:
			cell = cell as Vector2i
			cells_flat.append(cell.x)
			cells_flat.append(cell.y)
		adjacent_starts.append(int(adjacent_cells_flat.size() / 2))
		adjacent_counts.append(region.adjacent_empty_cells.size())
		for adjacent_cell in region.adjacent_empty_cells:
			adjacent_cell = adjacent_cell as Vector2i
			adjacent_cells_flat.append(adjacent_cell.x)
			adjacent_cells_flat.append(adjacent_cell.y)

	return {
		"region_ids": region_ids,
		"terrain_types": terrain_types,
		"cell_starts": cell_starts,
		"cell_counts": cell_counts,
		"cells_flat": cells_flat,
		"adjacent_starts": adjacent_starts,
		"adjacent_counts": adjacent_counts,
		"adjacent_cells_flat": adjacent_cells_flat,
	}


static func _append_compact_region_payload(target: Dictionary, field_prefix: String, payload: Dictionary) -> void:
	target["%sregion_ids" % field_prefix] = payload.get("region_ids", PackedInt32Array())
	target["%sterrain_types" % field_prefix] = payload.get("terrain_types", PackedInt32Array())
	target["%scell_starts" % field_prefix] = payload.get("cell_starts", PackedInt32Array())
	target["%scell_counts" % field_prefix] = payload.get("cell_counts", PackedInt32Array())
	target["%scells_flat" % field_prefix] = payload.get("cells_flat", PackedInt32Array())
	target["%sadjacent_starts" % field_prefix] = payload.get("adjacent_starts", PackedInt32Array())
	target["%sadjacent_counts" % field_prefix] = payload.get("adjacent_counts", PackedInt32Array())
	target["%sadjacent_cells_flat" % field_prefix] = payload.get("adjacent_cells_flat", PackedInt32Array())


static func _validate_compact_region_payload(cache_dto: Dictionary, field_prefix: String) -> bool:
	if typeof(cache_dto.get("%sregion_ids" % field_prefix, PackedInt32Array())) != TYPE_PACKED_INT32_ARRAY:
		return false
	if typeof(cache_dto.get("%sterrain_types" % field_prefix, PackedInt32Array())) != TYPE_PACKED_INT32_ARRAY:
		return false
	if typeof(cache_dto.get("%scell_starts" % field_prefix, PackedInt32Array())) != TYPE_PACKED_INT32_ARRAY:
		return false
	if typeof(cache_dto.get("%scell_counts" % field_prefix, PackedInt32Array())) != TYPE_PACKED_INT32_ARRAY:
		return false
	if typeof(cache_dto.get("%scells_flat" % field_prefix, PackedInt32Array())) != TYPE_PACKED_INT32_ARRAY:
		return false
	if typeof(cache_dto.get("%sadjacent_starts" % field_prefix, PackedInt32Array())) != TYPE_PACKED_INT32_ARRAY:
		return false
	if typeof(cache_dto.get("%sadjacent_counts" % field_prefix, PackedInt32Array())) != TYPE_PACKED_INT32_ARRAY:
		return false
	if typeof(cache_dto.get("%sadjacent_cells_flat" % field_prefix, PackedInt32Array())) != TYPE_PACKED_INT32_ARRAY:
		return false

	var region_ids: PackedInt32Array = cache_dto.get("%sregion_ids" % field_prefix, PackedInt32Array())
	var terrain_types: PackedInt32Array = cache_dto.get("%sterrain_types" % field_prefix, PackedInt32Array())
	var cell_starts: PackedInt32Array = cache_dto.get("%scell_starts" % field_prefix, PackedInt32Array())
	var cell_counts: PackedInt32Array = cache_dto.get("%scell_counts" % field_prefix, PackedInt32Array())
	var cells_flat: PackedInt32Array = cache_dto.get("%scells_flat" % field_prefix, PackedInt32Array())
	var adjacent_starts: PackedInt32Array = cache_dto.get("%sadjacent_starts" % field_prefix, PackedInt32Array())
	var adjacent_counts: PackedInt32Array = cache_dto.get("%sadjacent_counts" % field_prefix, PackedInt32Array())
	var adjacent_cells_flat: PackedInt32Array = cache_dto.get("%sadjacent_cells_flat" % field_prefix, PackedInt32Array())

	if region_ids.size() != terrain_types.size() or region_ids.size() != cell_starts.size():
		return false
	if region_ids.size() != cell_counts.size() or region_ids.size() != adjacent_starts.size():
		return false
	if region_ids.size() != adjacent_counts.size():
		return false
	if cells_flat.size() % 2 != 0 or adjacent_cells_flat.size() % 2 != 0:
		return false

	var flat_cell_count: int = int(cells_flat.size() / 2)
	var flat_adjacent_count: int = int(adjacent_cells_flat.size() / 2)
	for region_index in range(region_ids.size()):
		var cell_start: int = int(cell_starts[region_index])
		var cell_count: int = int(cell_counts[region_index])
		if cell_start < 0 or cell_count < 0 or cell_start + cell_count > flat_cell_count:
			return false
		var adjacent_start: int = int(adjacent_starts[region_index])
		var adjacent_count: int = int(adjacent_counts[region_index])
		if adjacent_start < 0 or adjacent_count < 0 or adjacent_start + adjacent_count > flat_adjacent_count:
			return false
	return true


static func _resource_regions_from_cache_dto(cache_dto: Dictionary) -> Dictionary:
	var bootstrap_cache_version: int = int(cache_dto.get("bootstrap_cache_version", 0))
	if bootstrap_cache_version == LEGACY_BOOTSTRAP_CACHE_VERSION:
		return _resource_region_dtos_to_regions(cache_dto.get("resource_region_dtos", []))

	var resource_regions: Dictionary = {}
	var regions: Array = _regions_from_compact_payload(cache_dto, "resource_")
	for region_variant in regions:
		var region: ResourceRegion = region_variant
		if region == null:
			continue
		if not resource_regions.has(region.terrain_type):
			resource_regions[region.terrain_type] = []
		var regions_for_type: Array = resource_regions[region.terrain_type]
		regions_for_type.append(region)
		resource_regions[region.terrain_type] = regions_for_type
	return resource_regions


static func _farmable_regions_from_cache_dto(cache_dto: Dictionary) -> Array:
	var bootstrap_cache_version: int = int(cache_dto.get("bootstrap_cache_version", 0))
	if bootstrap_cache_version == LEGACY_BOOTSTRAP_CACHE_VERSION:
		return _farmable_region_dtos_to_regions(cache_dto.get("farmable_region_dtos", []))
	return _regions_from_compact_payload(cache_dto, "farmable_")


static func _regions_from_compact_payload(cache_dto: Dictionary, field_prefix: String) -> Array:
	var regions: Array = []
	if not _validate_compact_region_payload(cache_dto, field_prefix):
		return regions

	var region_ids: PackedInt32Array = cache_dto.get("%sregion_ids" % field_prefix, PackedInt32Array())
	var terrain_types: PackedInt32Array = cache_dto.get("%sterrain_types" % field_prefix, PackedInt32Array())
	var cell_starts: PackedInt32Array = cache_dto.get("%scell_starts" % field_prefix, PackedInt32Array())
	var cell_counts: PackedInt32Array = cache_dto.get("%scell_counts" % field_prefix, PackedInt32Array())
	var cells_flat: PackedInt32Array = cache_dto.get("%scells_flat" % field_prefix, PackedInt32Array())
	var adjacent_starts: PackedInt32Array = cache_dto.get("%sadjacent_starts" % field_prefix, PackedInt32Array())
	var adjacent_counts: PackedInt32Array = cache_dto.get("%sadjacent_counts" % field_prefix, PackedInt32Array())
	var adjacent_cells_flat: PackedInt32Array = cache_dto.get("%sadjacent_cells_flat" % field_prefix, PackedInt32Array())

	for region_index in range(region_ids.size()):
		var region := ResourceRegionScript.new()
		region.setup(int(region_ids[region_index]), int(terrain_types[region_index]))

		var cell_start: int = int(cell_starts[region_index])
		var cell_count: int = int(cell_counts[region_index])
		for local_cell_index in range(cell_count):
			var flat_index: int = (cell_start + local_cell_index) * 2
			region.add_cell(Vector2i(int(cells_flat[flat_index]), int(cells_flat[flat_index + 1])))

		var adjacent_start: int = int(adjacent_starts[region_index])
		var adjacent_count: int = int(adjacent_counts[region_index])
		for local_adjacent_index in range(adjacent_count):
			var flat_adjacent_index: int = (adjacent_start + local_adjacent_index) * 2
			region.add_adjacent_empty_cell(
				Vector2i(int(adjacent_cells_flat[flat_adjacent_index]), int(adjacent_cells_flat[flat_adjacent_index + 1]))
			)

		regions.append(region)
	return regions


static func _resource_region_dtos_to_regions(region_dtos_variant: Variant) -> Dictionary:
	var resource_regions: Dictionary = {}
	if typeof(region_dtos_variant) != TYPE_ARRAY:
		return resource_regions

	var region_dtos: Array = region_dtos_variant
	for region_dto_variant in region_dtos:
		var region: ResourceRegion = _region_from_dto(region_dto_variant)
		if region == null:
			continue
		if not resource_regions.has(region.terrain_type):
			resource_regions[region.terrain_type] = []
		var regions_for_type: Array = resource_regions[region.terrain_type]
		regions_for_type.append(region)
		resource_regions[region.terrain_type] = regions_for_type
	return resource_regions


static func _farmable_region_dtos_to_regions(region_dtos_variant: Variant) -> Array:
	var farmable_regions: Array = []
	if typeof(region_dtos_variant) != TYPE_ARRAY:
		return farmable_regions

	var region_dtos: Array = region_dtos_variant
	for region_dto_variant in region_dtos:
		var region: ResourceRegion = _region_from_dto(region_dto_variant)
		if region == null:
			continue
		farmable_regions.append(region)
	return farmable_regions


static func _region_from_dto(region_dto_variant: Variant) -> ResourceRegion:
	if typeof(region_dto_variant) != TYPE_DICTIONARY:
		return null

	var region_dto: Dictionary = region_dto_variant
	var cells_variant: Variant = region_dto.get("cells", [])
	var adjacent_empty_cells_variant: Variant = region_dto.get("adjacent_empty_cells", [])
	if typeof(cells_variant) != TYPE_ARRAY or typeof(adjacent_empty_cells_variant) != TYPE_ARRAY:
		return null

	var region := ResourceRegionScript.new()
	region.setup(int(region_dto.get("region_id", -1)), int(region_dto.get("terrain_type", ResourceRegionScript.TERRAIN_EMPTY)))

	for cell_variant in cells_variant:
		if typeof(cell_variant) != TYPE_VECTOR2I:
			return null
		region.add_cell(cell_variant)

	for adjacent_cell_variant in adjacent_empty_cells_variant:
		if typeof(adjacent_cell_variant) != TYPE_VECTOR2I:
			return null
		region.add_adjacent_empty_cell(adjacent_cell_variant)

	return region
