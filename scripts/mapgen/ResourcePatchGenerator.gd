class_name ResourcePatchGenerator
extends RefCounted


const GeneratedTileDataScript := preload("res://scripts/mapgen/GeneratedTileData.gd")
const WorldGenerationIdentityScript := preload("res://scripts/mapgen/world/WorldGenerationIdentity.gd")
const WorldSemanticChunkScript := preload("res://scripts/mapgen/world/WorldSemanticChunk.gd")
const WorldSemanticGridScript := preload("res://scripts/mapgen/world/WorldSemanticGrid.gd")

const TERRAIN_PLAIN: int = 0
const TERRAIN_WATER: int = 1
const TERRAIN_SHALLOW_WATER: int = 2
const TERRAIN_SAND: int = 3

const RESOURCE_NONE: int = 0
const RESOURCE_WOOD: int = 1
const RESOURCE_STONE: int = 2

const FLAG_BUILDABLE: int = 1
const FLAG_PASSABLE: int = 2

const WATER_HEIGHT_THRESHOLD := -0.42
const SHALLOW_WATER_HEIGHT_THRESHOLD := -0.26
const SAND_HEIGHT_THRESHOLD := -0.18
const PATCH_NOISE_SCALE := 0.072
const WOOD_PATCH_THRESHOLD := 0.28
const STONE_PATCH_THRESHOLD := 0.34
const MIN_WOOD_PATCH_SIZE := 10
const MIN_STONE_PATCH_SIZE := 8
const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]

var _height_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _wood_noise: FastNoiseLite
var _stone_noise: FastNoiseLite
var _configured_seed: int = 0
var _is_configured: bool = false


func _init() -> void:
	_setup_noise()


func sample_base_semantic_for_cell(world_cell: Vector2i, identity: WorldGenerationIdentity) -> Dictionary:
	if identity == null:
		return {}
	if not identity.is_valid():
		return {}

	var map_seed := int(identity.seed)
	_ensure_configured(map_seed)

	var terrain_id := _sample_terrain_id(world_cell)
	var base_resource_id := _sample_base_resource_id(world_cell, map_seed, terrain_id)
	var base_resource_amount := 0
	var base_patch_key_payload: Variant = null

	if base_resource_id != RESOURCE_NONE:
		base_resource_amount = 255
		base_patch_key_payload = _build_base_patch_key_payload(world_cell, map_seed, base_resource_id, terrain_id)

	return {
		"terrain_id": terrain_id,
		"base_resource_id": base_resource_id,
		"flags": _flags_for_terrain_id(terrain_id),
		"base_resource_amount": base_resource_amount,
		"base_patch_key_payload": base_patch_key_payload,
	}


func _fill_base_semantics_for_chunk_packed(
	chunk_coords: Vector2i,
	identity: WorldGenerationIdentity,
	terrain_ids: PackedByteArray,
	base_resource_ids: PackedByteArray,
	flags: PackedByteArray,
	base_resource_amounts: PackedByteArray,
	temp_patch_key_payloads: PackedInt32Array
) -> void:
	var map_seed := int(identity.seed)
	_ensure_configured(map_seed)

	var chunk_origin_cell := WorldSemanticGridScript.chunk_coords_to_origin_cell(chunk_coords)
	var chunk_width := WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.x
	var chunk_height := WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.y
	var local_index := 0

	for local_y in range(chunk_height):
		var world_y := chunk_origin_cell.y + local_y
		for local_x in range(chunk_width):
			var world_cell := Vector2i(chunk_origin_cell.x + local_x, world_y)
			var terrain_id := _sample_terrain_id(world_cell)
			var base_resource_id := _sample_base_resource_id(world_cell, map_seed, terrain_id)
			var payload_offset := local_index * WorldSemanticChunkScript.PATCH_KEY_STRIDE

			terrain_ids[local_index] = terrain_id
			base_resource_ids[local_index] = base_resource_id
			flags[local_index] = _flags_for_terrain_id(terrain_id)

			if base_resource_id == RESOURCE_NONE:
				base_resource_amounts[local_index] = 0
				temp_patch_key_payloads[payload_offset] = 0
				temp_patch_key_payloads[payload_offset + 1] = 0
				temp_patch_key_payloads[payload_offset + 2] = 0
			else:
				base_resource_amounts[local_index] = 255
				var anchor := _find_resource_patch_anchor(world_cell, map_seed, base_resource_id, terrain_id)
				temp_patch_key_payloads[payload_offset] = anchor.x
				temp_patch_key_payloads[payload_offset + 1] = anchor.y
				temp_patch_key_payloads[payload_offset + 2] = base_resource_id

			local_index += 1


func build_base_semantics_for_chunk_packed(chunk_coords: Vector2i, identity: WorldGenerationIdentity) -> Dictionary:
	if identity == null:
		return {}
	if not identity.is_valid():
		return {}

	var terrain_ids := PackedByteArray()
	var base_resource_ids := PackedByteArray()
	var flags := PackedByteArray()
	var base_resource_amounts := PackedByteArray()
	var base_patch_key_indices := PackedInt32Array()
	var temp_patch_key_payloads := PackedInt32Array()

	terrain_ids.resize(WorldSemanticGridScript.TILES_PER_CHUNK)
	base_resource_ids.resize(WorldSemanticGridScript.TILES_PER_CHUNK)
	flags.resize(WorldSemanticGridScript.TILES_PER_CHUNK)
	base_resource_amounts.resize(WorldSemanticGridScript.TILES_PER_CHUNK)
	base_patch_key_indices.resize(WorldSemanticGridScript.TILES_PER_CHUNK)
	temp_patch_key_payloads.resize(WorldSemanticGridScript.TILES_PER_CHUNK * WorldSemanticChunkScript.PATCH_KEY_STRIDE)

	for tile_index in range(WorldSemanticGridScript.TILES_PER_CHUNK):
		base_patch_key_indices[tile_index] = WorldSemanticChunkScript.INVALID_INDEX

	_fill_base_semantics_for_chunk_packed(
		chunk_coords,
		identity,
		terrain_ids,
		base_resource_ids,
		flags,
		base_resource_amounts,
		temp_patch_key_payloads
	)

	var patch_key_table_data := PackedInt32Array()
	var patch_index_by_payload: Dictionary = {}

	for tile_index in range(WorldSemanticGridScript.TILES_PER_CHUNK):
		var base_resource_id := int(base_resource_ids[tile_index])
		if base_resource_id == RESOURCE_NONE:
			continue

		var payload_offset := tile_index * WorldSemanticChunkScript.PATCH_KEY_STRIDE
		var payload := Vector3i(
			int(temp_patch_key_payloads[payload_offset]),
			int(temp_patch_key_payloads[payload_offset + 1]),
			int(temp_patch_key_payloads[payload_offset + 2])
		)
		var patch_index: int = WorldSemanticChunkScript.INVALID_INDEX
		if patch_index_by_payload.has(payload):
			patch_index = int(patch_index_by_payload[payload])
		else:
			patch_index = patch_key_table_data.size() / WorldSemanticChunkScript.PATCH_KEY_STRIDE
			patch_index_by_payload[payload] = patch_index
			patch_key_table_data.append(payload.x)
			patch_key_table_data.append(payload.y)
			patch_key_table_data.append(payload.z)

		base_patch_key_indices[tile_index] = patch_index

	var result := {
		"chunk_coords": chunk_coords,
		"terrain_ids": terrain_ids,
		"base_resource_ids": base_resource_ids,
		"flags": flags,
		"base_resource_amounts": base_resource_amounts,
		"base_patch_key_indices": base_patch_key_indices,
		"patch_key_table_data": patch_key_table_data,
		"semantic_digest": identity.semantic_digest,
		"semantic_hash256": identity.semantic_hash256,
		"canonical_identity_bytes": identity.canonical_identity_bytes,
	}

	if OS.is_debug_build():
		var validation_error := WorldSemanticChunkScript.validate_result(result)
		if not validation_error.is_empty():
			push_error(
				"ResourcePatchGenerator.build_base_semantics_for_chunk_packed invalid result at %s: %s"
				% [str(chunk_coords), validation_error]
			)
			return {}

	return result


func apply_resource_patches(map_data, map_seed: int) -> Dictionary:
	if map_data == null:
		return _empty_summary()

	_ensure_configured(map_seed)
	_clear_existing_resources(map_data)

	var summary := {
		GeneratedTileDataScript.RESOURCE_WOOD: {
			"patch_count": 0,
			"tile_count": 0,
		},
		GeneratedTileDataScript.RESOURCE_STONE: {
			"patch_count": 0,
			"tile_count": 0,
		},
	}

	var visited: Dictionary = {}
	var next_patch_id := 0

	for cell in map_data.get_all_cells():
		if visited.has(cell):
			continue

		var tile = map_data.get_tile(cell)
		if not _can_host_resource(tile):
			visited[cell] = true
			continue

		var resource_type := _sample_resource_type(cell, map_seed)
		if resource_type == GeneratedTileDataScript.RESOURCE_NONE:
			visited[cell] = true
			continue

		var patch_cells := _collect_patch_cells(map_data, cell, resource_type, visited, map_seed)
		if patch_cells.is_empty():
			continue

		var min_size := _get_min_patch_size(resource_type)
		if patch_cells.size() < min_size:
			_clear_patch(map_data, patch_cells)
			continue

		for patch_cell in patch_cells:
			var patch_tile = map_data.get_tile(patch_cell)
			if patch_tile == null:
				continue
			patch_tile.set_resource(resource_type, next_patch_id, 1.0)

		var resource_summary: Dictionary = summary[resource_type]
		resource_summary["patch_count"] = int(resource_summary["patch_count"]) + 1
		resource_summary["tile_count"] = int(resource_summary["tile_count"]) + patch_cells.size()
		next_patch_id += 1

	return summary


func sample_resource_for_cell(cell: Vector2i, map_seed: int, base_terrain: StringName) -> StringName:
	_ensure_configured(map_seed)
	if base_terrain != GeneratedTileDataScript.TERRAIN_PLAIN and base_terrain != GeneratedTileDataScript.TERRAIN_SAND:
		return GeneratedTileDataScript.RESOURCE_NONE
	return _sample_resource_type(cell, map_seed)


func apply_runtime_resource_to_tile(tile, map_seed: int) -> void:
	if tile == null:
		return
	if not _can_host_resource(tile):
		tile.clear_resource()
		return

	var resource_type := sample_resource_for_cell(tile.cell, map_seed, tile.base_terrain)
	if resource_type == GeneratedTileDataScript.RESOURCE_NONE:
		tile.clear_resource()
		return

	tile.set_resource(resource_type, -1, 1.0)


func _empty_summary() -> Dictionary:
	return {
		GeneratedTileDataScript.RESOURCE_WOOD: {
			"patch_count": 0,
			"tile_count": 0,
		},
		GeneratedTileDataScript.RESOURCE_STONE: {
			"patch_count": 0,
			"tile_count": 0,
		},
	}


func _setup_noise() -> void:
	_height_noise = FastNoiseLite.new()
	_height_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_height_noise.frequency = 0.010
	_height_noise.fractal_octaves = 4
	_height_noise.fractal_gain = 0.5
	_height_noise.fractal_lacunarity = 2.0

	_detail_noise = FastNoiseLite.new()
	_detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_detail_noise.frequency = 0.045
	_detail_noise.fractal_octaves = 2
	_detail_noise.fractal_gain = 0.5
	_detail_noise.fractal_lacunarity = 2.0

	_wood_noise = FastNoiseLite.new()
	_wood_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_wood_noise.frequency = PATCH_NOISE_SCALE
	_wood_noise.fractal_octaves = 3
	_wood_noise.fractal_gain = 0.55
	_wood_noise.fractal_lacunarity = 2.0

	_stone_noise = FastNoiseLite.new()
	_stone_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_stone_noise.frequency = PATCH_NOISE_SCALE * 0.82
	_stone_noise.fractal_octaves = 3
	_stone_noise.fractal_gain = 0.5
	_stone_noise.fractal_lacunarity = 2.2


func _configure_noise(map_seed: int) -> void:
	_height_noise.seed = map_seed + 100
	_detail_noise.seed = map_seed + 400
	_wood_noise.seed = map_seed + 1000
	_stone_noise.seed = map_seed + 2000
	_configured_seed = map_seed
	_is_configured = true


func _ensure_configured(map_seed: int) -> void:
	if _is_configured and _configured_seed == map_seed:
		return
	_configure_noise(map_seed)


func _clear_existing_resources(map_data) -> void:
	for cell in map_data.get_all_cells():
		var tile = map_data.get_tile(cell)
		if tile == null:
			continue
		tile.clear_resource()


func _can_host_resource(tile) -> bool:
	if tile == null:
		return false
	return tile.base_terrain == GeneratedTileDataScript.TERRAIN_PLAIN or tile.base_terrain == GeneratedTileDataScript.TERRAIN_SAND


func _sample_terrain_id(world_cell: Vector2i) -> int:
	var world_pos := Vector2(float(world_cell.x), float(world_cell.y))
	var height_value := _sample_height(world_pos)

	if height_value <= WATER_HEIGHT_THRESHOLD:
		return TERRAIN_WATER
	if height_value <= SHALLOW_WATER_HEIGHT_THRESHOLD:
		return TERRAIN_SHALLOW_WATER
	if height_value <= SAND_HEIGHT_THRESHOLD:
		return TERRAIN_SAND
	return TERRAIN_PLAIN


func _sample_height(world_pos: Vector2) -> float:
	var large := _height_noise.get_noise_2d(world_pos.x, world_pos.y)
	var detail := _detail_noise.get_noise_2d(world_pos.x * 1.8, world_pos.y * 1.8) * 0.18
	return clamp(large + detail, -1.0, 1.0)


func _sample_base_resource_id(world_cell: Vector2i, map_seed: int, terrain_id: int) -> int:
	if not _terrain_id_can_host_resource(terrain_id):
		return RESOURCE_NONE

	var resource_type := _sample_resource_type(world_cell, map_seed)
	return _resource_id_from_type(resource_type)


func _terrain_id_can_host_resource(terrain_id: int) -> bool:
	return terrain_id == TERRAIN_PLAIN or terrain_id == TERRAIN_SAND


func _flags_for_terrain_id(terrain_id: int) -> int:
	if terrain_id == TERRAIN_WATER or terrain_id == TERRAIN_SHALLOW_WATER:
		return 0
	return FLAG_BUILDABLE | FLAG_PASSABLE


func _resource_id_from_type(resource_type: StringName) -> int:
	if resource_type == GeneratedTileDataScript.RESOURCE_WOOD:
		return RESOURCE_WOOD
	if resource_type == GeneratedTileDataScript.RESOURCE_STONE:
		return RESOURCE_STONE
	return RESOURCE_NONE


func _build_base_patch_key_payload(world_cell: Vector2i, map_seed: int, resource_id: int, terrain_id: int) -> Array[int]:
	var anchor := _find_resource_patch_anchor(world_cell, map_seed, resource_id, terrain_id)
	return [anchor.x, anchor.y, resource_id]


func _find_resource_patch_anchor(world_cell: Vector2i, map_seed: int, resource_id: int, terrain_id: int) -> Vector2i:
	var visited: Dictionary = {}
	var stack: Array[Vector2i] = [world_cell]
	var anchor := world_cell

	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		if visited.has(cell):
			continue
		visited[cell] = true

		var cell_terrain_id := _sample_terrain_id(cell)
		if cell_terrain_id != terrain_id:
			continue
		if _sample_base_resource_id(cell, map_seed, cell_terrain_id) != resource_id:
			continue

		if cell.x < anchor.x or (cell.x == anchor.x and cell.y < anchor.y):
			anchor = cell

		for offset in CARDINAL_DIRECTIONS:
			var neighbor: Vector2i = cell + offset
			if visited.has(neighbor):
				continue
			stack.append(neighbor)

	return anchor


func _sample_resource_type(cell: Vector2i, map_seed: int) -> StringName:
	var world_pos := Vector2(float(cell.x), float(cell.y))
	var wood_value := _wood_noise.get_noise_2d(world_pos.x, world_pos.y)
	var stone_value := _stone_noise.get_noise_2d(world_pos.x + 137.0, world_pos.y - 91.0)
	var selector := _hash01(cell, map_seed, 17)

	if wood_value >= WOOD_PATCH_THRESHOLD and wood_value >= stone_value + 0.06 and selector >= 0.18:
		return GeneratedTileDataScript.RESOURCE_WOOD

	if stone_value >= STONE_PATCH_THRESHOLD and stone_value >= wood_value + 0.03 and selector >= 0.24:
		return GeneratedTileDataScript.RESOURCE_STONE

	return GeneratedTileDataScript.RESOURCE_NONE


func _collect_patch_cells(map_data, start_cell: Vector2i, resource_type: StringName, visited: Dictionary, map_seed: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var stack: Array[Vector2i] = [start_cell]

	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		if visited.has(cell):
			continue
		visited[cell] = true

		var tile = map_data.get_tile(cell)
		if not _can_host_resource(tile):
			continue
		if _sample_resource_type(cell, map_seed) != resource_type:
			continue

		result.append(cell)

		for offset in CARDINAL_DIRECTIONS:
			var neighbor: Vector2i = cell + offset
			if not map_data.is_inside(neighbor):
				continue
			if visited.has(neighbor):
				continue
			stack.append(neighbor)

	return result


func _clear_patch(map_data, patch_cells: Array[Vector2i]) -> void:
	for cell in patch_cells:
		var tile = map_data.get_tile(cell)
		if tile == null:
			continue
		tile.clear_resource()


func _get_min_patch_size(resource_type: StringName) -> int:
	if resource_type == GeneratedTileDataScript.RESOURCE_WOOD:
		return MIN_WOOD_PATCH_SIZE
	if resource_type == GeneratedTileDataScript.RESOURCE_STONE:
		return MIN_STONE_PATCH_SIZE
	return 1


func _hash01(cell: Vector2i, map_seed: int, salt: int) -> float:
	var value := int(cell.x) * 92821
	value += int(cell.y) * 68917
	value += map_seed * 31
	value += salt * 131
	value = abs(value)
	return float(value % 1000) / 999.0
