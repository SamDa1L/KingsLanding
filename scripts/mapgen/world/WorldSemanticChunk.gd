class_name WorldSemanticChunk
extends RefCounted


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
const VALID_FLAG_MASK: int = FLAG_BUILDABLE | FLAG_PASSABLE

const PATCH_KEY_STRIDE: int = 3
const INVALID_INDEX: int = -1
const REQUIRED_RESULT_FIELDS: Array[String] = [
	"chunk_coords",
	"terrain_ids",
	"base_resource_ids",
	"flags",
	"base_resource_amounts",
	"base_patch_key_indices",
	"patch_key_table_data",
]

var chunk_coords: Vector2i = Vector2i.ZERO
var terrain_ids: PackedByteArray = PackedByteArray()
var base_resource_ids: PackedByteArray = PackedByteArray()
var flags: PackedByteArray = PackedByteArray()
var base_resource_amounts: PackedByteArray = PackedByteArray()
var base_patch_key_indices: PackedInt32Array = PackedInt32Array()
var patch_key_table_data: PackedInt32Array = PackedInt32Array()


func _init(next_chunk_coords: Vector2i = Vector2i.ZERO) -> void:
	reset(next_chunk_coords)


func reset(next_chunk_coords: Vector2i = Vector2i.ZERO) -> void:
	chunk_coords = next_chunk_coords
	_initialize_fixed_arrays()


func get_tile_count() -> int:
	return WorldSemanticGridScript.TILES_PER_CHUNK


func get_patch_key_count() -> int:
	return patch_key_table_data.size() / PATCH_KEY_STRIDE


func has_local_index(local_index: int) -> bool:
	return local_index >= 0 and local_index < WorldSemanticGridScript.TILES_PER_CHUNK


func get_local_index(local_coords: Vector2i) -> int:
	if local_coords.x < 0 or local_coords.y < 0:
		return INVALID_INDEX
	if local_coords.x >= WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.x:
		return INVALID_INDEX
	if local_coords.y >= WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.y:
		return INVALID_INDEX
	return WorldSemanticGridScript.local_coords_to_index(local_coords)


func get_terrain_id(local_index: int) -> int:
	if not has_local_index(local_index):
		return INVALID_INDEX
	return int(terrain_ids[local_index])


func get_base_resource_id(local_index: int) -> int:
	if not has_local_index(local_index):
		return INVALID_INDEX
	return int(base_resource_ids[local_index])


func get_flags(local_index: int) -> int:
	if not has_local_index(local_index):
		return INVALID_INDEX
	return int(flags[local_index])


func get_base_resource_amount(local_index: int) -> int:
	if not has_local_index(local_index):
		return INVALID_INDEX
	return int(base_resource_amounts[local_index])


func get_base_patch_key_index(local_index: int) -> int:
	if not has_local_index(local_index):
		return INVALID_INDEX
	return int(base_patch_key_indices[local_index])


func get_patch_key_payload_at_index(patch_key_index: int) -> Vector3i:
	if patch_key_index < 0 or patch_key_index >= get_patch_key_count():
		return Vector3i(INVALID_INDEX, INVALID_INDEX, INVALID_INDEX)

	var offset := patch_key_index * PATCH_KEY_STRIDE
	return Vector3i(
		int(patch_key_table_data[offset]),
		int(patch_key_table_data[offset + 1]),
		int(patch_key_table_data[offset + 2])
	)


func get_validation_error() -> String:
	if terrain_ids.size() != WorldSemanticGridScript.TILES_PER_CHUNK:
		return "terrain_ids size must be %d" % WorldSemanticGridScript.TILES_PER_CHUNK
	if base_resource_ids.size() != WorldSemanticGridScript.TILES_PER_CHUNK:
		return "base_resource_ids size must be %d" % WorldSemanticGridScript.TILES_PER_CHUNK
	if flags.size() != WorldSemanticGridScript.TILES_PER_CHUNK:
		return "flags size must be %d" % WorldSemanticGridScript.TILES_PER_CHUNK
	if base_resource_amounts.size() != WorldSemanticGridScript.TILES_PER_CHUNK:
		return "base_resource_amounts size must be %d" % WorldSemanticGridScript.TILES_PER_CHUNK
	if base_patch_key_indices.size() != WorldSemanticGridScript.TILES_PER_CHUNK:
		return "base_patch_key_indices size must be %d" % WorldSemanticGridScript.TILES_PER_CHUNK
	if patch_key_table_data.size() % PATCH_KEY_STRIDE != 0:
		return "patch_key_table_data size must be a multiple of %d" % PATCH_KEY_STRIDE

	var patch_key_count := get_patch_key_count()
	if patch_key_count > WorldSemanticGridScript.TILES_PER_CHUNK:
		return "patch_key count must not exceed %d" % WorldSemanticGridScript.TILES_PER_CHUNK

	var patch_reference_counts: Array[int] = []
	patch_reference_counts.resize(patch_key_count)
	for patch_index in range(patch_key_count):
		patch_reference_counts[patch_index] = 0

	var seen_payloads: Dictionary = {}

	for tile_index in range(WorldSemanticGridScript.TILES_PER_CHUNK):
		var terrain_id := int(terrain_ids[tile_index])
		if not _is_valid_terrain_id(terrain_id):
			return "terrain_ids[%d] has invalid terrain id %d" % [tile_index, terrain_id]

		var resource_id := int(base_resource_ids[tile_index])
		if not _is_valid_resource_id(resource_id):
			return "base_resource_ids[%d] has invalid resource id %d" % [tile_index, resource_id]

		var tile_flags := int(flags[tile_index])
		if (tile_flags & ~VALID_FLAG_MASK) != 0:
			return "flags[%d] contains unsupported bits %d" % [tile_index, tile_flags]

		var resource_amount := int(base_resource_amounts[tile_index])
		var patch_key_index := int(base_patch_key_indices[tile_index])

		if resource_id == RESOURCE_NONE:
			if resource_amount != 0:
				return "base_resource_amounts[%d] must be 0 when resource is none" % tile_index
			if patch_key_index != INVALID_INDEX:
				return "base_patch_key_indices[%d] must be -1 when resource is none" % tile_index
			continue

		if resource_amount < 1 or resource_amount > 255:
			return "base_resource_amounts[%d] must be in 1..255 when resource exists" % tile_index
		if patch_key_index < 0 or patch_key_index >= patch_key_count:
			return "base_patch_key_indices[%d] points outside patch table" % tile_index

		var payload := get_patch_key_payload_at_index(patch_key_index)
		if payload.z != resource_id:
			return "base_patch_key_indices[%d] resource mismatch" % tile_index

		patch_reference_counts[patch_key_index] += 1

	var expected_patch_order: Array[String] = []
	var expected_patch_index_by_key: Dictionary = {}

	for tile_index in range(WorldSemanticGridScript.TILES_PER_CHUNK):
		var resource_id := int(base_resource_ids[tile_index])
		if resource_id == RESOURCE_NONE:
			continue

		var patch_key_index := int(base_patch_key_indices[tile_index])
		var payload := get_patch_key_payload_at_index(patch_key_index)
		var payload_key := "%d|%d|%d" % [payload.x, payload.y, payload.z]
		if expected_patch_index_by_key.has(payload_key):
			continue

		expected_patch_index_by_key[payload_key] = expected_patch_order.size()
		expected_patch_order.append(payload_key)

	for patch_index in range(patch_key_count):
		var offset := patch_index * PATCH_KEY_STRIDE
		var anchor_x := int(patch_key_table_data[offset])
		var anchor_y := int(patch_key_table_data[offset + 1])
		var resource_type := int(patch_key_table_data[offset + 2])

		if not _is_valid_resource_id(resource_type) or resource_type == RESOURCE_NONE:
			return "patch_key_table_data[%d] has invalid resource type %d" % [patch_index, resource_type]

		var payload_key := "%d|%d|%d" % [anchor_x, anchor_y, resource_type]
		if seen_payloads.has(payload_key):
			return "duplicate patch payload detected at table index %d" % patch_index
		seen_payloads[payload_key] = true

		if patch_reference_counts[patch_index] <= 0:
			return "patch payload at table index %d is unreferenced" % patch_index

		payload_key = "%d|%d|%d" % [anchor_x, anchor_y, resource_type]
		if not expected_patch_index_by_key.has(payload_key):
			return "patch payload at table index %d was never discovered by row-major scan" % patch_index
		if int(expected_patch_index_by_key[payload_key]) != patch_index:
			return "patch payload at table index %d violates row-major first-seen order" % patch_index

	return ""


func is_valid() -> bool:
	return get_validation_error().is_empty()


func get_terrain_id_by_index(local_index: int) -> int:
	return get_terrain_id(local_index)


func get_base_resource_id_by_index(local_index: int) -> int:
	return get_base_resource_id(local_index)


func get_flags_by_index(local_index: int) -> int:
	return get_flags(local_index)


func get_base_resource_amount_by_index(local_index: int) -> int:
	return get_base_resource_amount(local_index)


func copy_patch_payload_by_index(local_index: int, out_payload: PackedInt32Array) -> int:
	if out_payload.size() < PATCH_KEY_STRIDE:
		return INVALID_INDEX
	if not has_local_index(local_index):
		return INVALID_INDEX

	var patch_key_index := get_base_patch_key_index(local_index)
	if patch_key_index == INVALID_INDEX:
		return INVALID_INDEX

	var payload := get_patch_key_payload_at_index(patch_key_index)
	out_payload[0] = payload.x
	out_payload[1] = payload.y
	out_payload[2] = payload.z
	return patch_key_index


static func validate_result(chunk_result: Dictionary) -> String:
	for field_name in REQUIRED_RESULT_FIELDS:
		if not chunk_result.has(field_name):
			return "MISSING_FIELD: %s" % field_name

	if typeof(chunk_result["chunk_coords"]) != TYPE_VECTOR2I:
		return "INVALID_FIELD_TYPE: chunk_coords must be Vector2i"
	if typeof(chunk_result["terrain_ids"]) != TYPE_PACKED_BYTE_ARRAY:
		return "INVALID_FIELD_TYPE: terrain_ids must be PackedByteArray"
	if typeof(chunk_result["base_resource_ids"]) != TYPE_PACKED_BYTE_ARRAY:
		return "INVALID_FIELD_TYPE: base_resource_ids must be PackedByteArray"
	if typeof(chunk_result["flags"]) != TYPE_PACKED_BYTE_ARRAY:
		return "INVALID_FIELD_TYPE: flags must be PackedByteArray"
	if typeof(chunk_result["base_resource_amounts"]) != TYPE_PACKED_BYTE_ARRAY:
		return "INVALID_FIELD_TYPE: base_resource_amounts must be PackedByteArray"
	if typeof(chunk_result["base_patch_key_indices"]) != TYPE_PACKED_INT32_ARRAY:
		return "INVALID_FIELD_TYPE: base_patch_key_indices must be PackedInt32Array"
	if typeof(chunk_result["patch_key_table_data"]) != TYPE_PACKED_INT32_ARRAY:
		return "INVALID_FIELD_TYPE: patch_key_table_data must be PackedInt32Array"

	var chunk := WorldSemanticChunk.new(chunk_result["chunk_coords"])
	chunk.terrain_ids = chunk_result["terrain_ids"]
	chunk.base_resource_ids = chunk_result["base_resource_ids"]
	chunk.flags = chunk_result["flags"]
	chunk.base_resource_amounts = chunk_result["base_resource_amounts"]
	chunk.base_patch_key_indices = chunk_result["base_patch_key_indices"]
	chunk.patch_key_table_data = chunk_result["patch_key_table_data"]

	var validation_error := chunk.get_validation_error()
	if not validation_error.is_empty():
		if validation_error.contains("size must be "):
			var prefix := validation_error.get_slice(" ", 0)
			var actual_size := 0
			if prefix == "terrain_ids":
				actual_size = chunk.terrain_ids.size()
			elif prefix == "base_resource_ids":
				actual_size = chunk.base_resource_ids.size()
			elif prefix == "flags":
				actual_size = chunk.flags.size()
			elif prefix == "base_resource_amounts":
				actual_size = chunk.base_resource_amounts.size()
			elif prefix == "base_patch_key_indices":
				actual_size = chunk.base_patch_key_indices.size()
			return "INVALID_LENGTH: %s expected %d, got %d" % [
				prefix,
				WorldSemanticGridScript.TILES_PER_CHUNK,
				actual_size,
			]
		if validation_error.contains("multiple of"):
			return "INVALID_LENGTH: %s" % validation_error
		return validation_error

	return ""


static func from_validated_result(chunk_result: Dictionary) -> WorldSemanticChunk:
	var validation_error := validate_result(chunk_result)
	if not validation_error.is_empty():
		push_error("WorldSemanticChunk.from_validated_result rejected result: %s" % validation_error)
		return null

	var chunk := WorldSemanticChunk.new(chunk_result["chunk_coords"])
	chunk.terrain_ids = chunk_result["terrain_ids"]
	chunk.base_resource_ids = chunk_result["base_resource_ids"]
	chunk.flags = chunk_result["flags"]
	chunk.base_resource_amounts = chunk_result["base_resource_amounts"]
	chunk.base_patch_key_indices = chunk_result["base_patch_key_indices"]
	chunk.patch_key_table_data = chunk_result["patch_key_table_data"]
	return chunk


func _initialize_fixed_arrays() -> void:
	terrain_ids.resize(WorldSemanticGridScript.TILES_PER_CHUNK)
	base_resource_ids.resize(WorldSemanticGridScript.TILES_PER_CHUNK)
	flags.resize(WorldSemanticGridScript.TILES_PER_CHUNK)
	base_resource_amounts.resize(WorldSemanticGridScript.TILES_PER_CHUNK)
	base_patch_key_indices.resize(WorldSemanticGridScript.TILES_PER_CHUNK)
	patch_key_table_data.clear()

	for index in range(WorldSemanticGridScript.TILES_PER_CHUNK):
		terrain_ids[index] = TERRAIN_PLAIN
		base_resource_ids[index] = RESOURCE_NONE
		flags[index] = 0
		base_resource_amounts[index] = 0
		base_patch_key_indices[index] = INVALID_INDEX


static func _is_valid_terrain_id(terrain_id: int) -> bool:
	return terrain_id == TERRAIN_PLAIN or terrain_id == TERRAIN_WATER or terrain_id == TERRAIN_SHALLOW_WATER or terrain_id == TERRAIN_SAND


static func _is_valid_resource_id(resource_id: int) -> bool:
	return resource_id == RESOURCE_NONE or resource_id == RESOURCE_WOOD or resource_id == RESOURCE_STONE
