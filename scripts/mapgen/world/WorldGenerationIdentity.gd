class_name WorldGenerationIdentity
extends RefCounted


const WorldSemanticGridScript := preload("res://scripts/mapgen/world/WorldSemanticGrid.gd")

const DEFAULT_SEMANTIC_DIGEST_VERSION: int = 1
const DEFAULT_GENERATOR_VERSION := "stage0"
const DEFAULT_DETERMINISTIC_HASH_VERSION := "stage0"
const DEFAULT_TERRAIN_BACKEND_ID := "noise_based_map_generator"
const SEMANTIC_DIGEST_ALGORITHM := "SHA-256"
const INT64_MIN_VALUE: int = -9223372036854775807 - 1
const INT64_MAX_VALUE: int = 9223372036854775807

const PROFILE_BOOL_FALSE_TAG: int = 0x01
const PROFILE_BOOL_TRUE_TAG: int = 0x02
const PROFILE_INT_TAG: int = 0x03
const PROFILE_STRING_TAG: int = 0x04
const PROFILE_ARRAY_TAG: int = 0x05
const PROFILE_DICTIONARY_TAG: int = 0x06

var _validation_error: String = ""

var semantic_digest_version: int:
	get:
		return _semantic_digest_version
	set(value):
		_reject_frozen_write("semantic_digest_version")

var seed: int:
	get:
		return _seed
	set(value):
		_reject_frozen_write("seed")

var generator_version: String:
	get:
		return _generator_version
	set(value):
		_reject_frozen_write("generator_version")

var deterministic_hash_version: String:
	get:
		return _deterministic_hash_version
	set(value):
		_reject_frozen_write("deterministic_hash_version")

var terrain_backend_id: String:
	get:
		return _terrain_backend_id
	set(value):
		_reject_frozen_write("terrain_backend_id")

var generator_parameter_profile: Dictionary:
	get:
		return _generator_parameter_profile.duplicate(true)
	set(value):
		_reject_frozen_write("generator_parameter_profile")

var semantic_digest_algorithm: String:
	get:
		return SEMANTIC_DIGEST_ALGORITHM
	set(value):
		_reject_frozen_write("semantic_digest_algorithm")

var canonical_identity_bytes: PackedByteArray:
	get:
		return _canonical_identity_bytes.duplicate()
	set(value):
		_reject_frozen_write("canonical_identity_bytes")

var semantic_hash256: PackedByteArray:
	get:
		return _semantic_hash256.duplicate()
	set(value):
		_reject_frozen_write("semantic_hash256")

var semantic_digest: int:
	get:
		return _semantic_digest
	set(value):
		_reject_frozen_write("semantic_digest")

var chunk_size: Vector2i:
	get:
		return WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE
	set(value):
		_reject_frozen_write("chunk_size")

var prewarm_chunk_rect: Rect2i:
	get:
		return WorldSemanticGridScript.PREWARM_CHUNK_RECT
	set(value):
		_reject_frozen_write("prewarm_chunk_rect")

var prewarm_tile_rect: Rect2i:
	get:
		return WorldSemanticGridScript.PREWARM_TILE_RECT
	set(value):
		_reject_frozen_write("prewarm_tile_rect")

var _semantic_digest_version: int = DEFAULT_SEMANTIC_DIGEST_VERSION
var _seed: int = 0
var _generator_version: String = DEFAULT_GENERATOR_VERSION
var _deterministic_hash_version: String = DEFAULT_DETERMINISTIC_HASH_VERSION
var _terrain_backend_id: String = DEFAULT_TERRAIN_BACKEND_ID
var _generator_parameter_profile: Dictionary = {}
var _canonical_identity_bytes: PackedByteArray = PackedByteArray()
var _semantic_hash256: PackedByteArray = PackedByteArray()
var _semantic_digest: int = 0
var _is_frozen: bool = false


func _init(
	next_seed: int = 0,
	next_generator_version: String = DEFAULT_GENERATOR_VERSION,
	next_deterministic_hash_version: String = DEFAULT_DETERMINISTIC_HASH_VERSION,
	next_terrain_backend_id: String = DEFAULT_TERRAIN_BACKEND_ID,
	next_generator_parameter_profile: Dictionary = {},
	next_semantic_digest_version: int = DEFAULT_SEMANTIC_DIGEST_VERSION
) -> void:
	var validation_error := _build_validation_error(
		next_seed,
		next_generator_version,
		next_deterministic_hash_version,
		next_terrain_backend_id,
		next_generator_parameter_profile,
		next_semantic_digest_version
	)
	if not validation_error.is_empty():
		_validation_error = validation_error
		return

	_semantic_digest_version = next_semantic_digest_version
	_seed = next_seed
	_generator_version = next_generator_version
	_deterministic_hash_version = next_deterministic_hash_version
	_terrain_backend_id = next_terrain_backend_id
	_generator_parameter_profile = next_generator_parameter_profile.duplicate(true)

	_canonical_identity_bytes = _build_canonical_identity_bytes()
	_semantic_hash256 = _build_sha256(_canonical_identity_bytes)
	if _semantic_hash256.size() != 32:
		_validation_error = "semantic_hash256 must have 32 bytes"
		return
	_semantic_digest = decode_i64_little_endian(_semantic_hash256, 0)
	_is_frozen = true


static func create(
	next_seed: int = 0,
	next_generator_version: String = DEFAULT_GENERATOR_VERSION,
	next_deterministic_hash_version: String = DEFAULT_DETERMINISTIC_HASH_VERSION,
	next_terrain_backend_id: String = DEFAULT_TERRAIN_BACKEND_ID,
	next_generator_parameter_profile: Dictionary = {},
	next_semantic_digest_version: int = DEFAULT_SEMANTIC_DIGEST_VERSION
) -> WorldGenerationIdentity:
	return WorldGenerationIdentity.new(
		next_seed,
		next_generator_version,
		next_deterministic_hash_version,
		next_terrain_backend_id,
		next_generator_parameter_profile,
		next_semantic_digest_version
	)


func is_frozen() -> bool:
	return _is_frozen


func is_valid() -> bool:
	return _validation_error.is_empty() and _is_frozen


func get_validation_error() -> String:
	return _validation_error


static func is_valid_generator_parameter_profile(profile: Variant) -> bool:
	return get_profile_validation_error(profile).is_empty()


static func get_profile_validation_error(value: Variant, path: String = "generator_parameter_profile") -> String:
	var value_type := typeof(value)

	if value_type == TYPE_BOOL or value_type == TYPE_INT or value_type == TYPE_STRING:
		return ""

	if value_type == TYPE_ARRAY:
		var array_value: Array = value
		for index in range(array_value.size()):
			var child_error := get_profile_validation_error(array_value[index], "%s[%d]" % [path, index])
			if not child_error.is_empty():
				return child_error
		return ""

	if value_type == TYPE_DICTIONARY:
		var dictionary_value: Dictionary = value
		for key in dictionary_value.keys():
			if typeof(key) != TYPE_STRING:
				return "%s has non-String key %s" % [path, str(key)]
			var child_error := get_profile_validation_error(dictionary_value[key], "%s.%s" % [path, String(key)])
			if not child_error.is_empty():
				return child_error
		return ""

	return "%s has unsupported type %s" % [path, type_string(value_type)]


static func encode_i64_little_endian(value: int) -> PackedByteArray:
	var result := PackedByteArray()
	for byte_index in range(8):
		result.append((value >> (byte_index * 8)) & 0xff)
	return result


static func encode_u32_little_endian(value: int) -> PackedByteArray:
	var result := PackedByteArray()
	for byte_index in range(4):
		result.append((value >> (byte_index * 8)) & 0xff)
	return result


static func decode_i64_little_endian(bytes: PackedByteArray, offset: int = 0) -> int:
	if bytes.size() < offset + 8:
		push_error("decode_i64_little_endian requires at least 8 bytes from offset")
		return 0

	var result := 0
	for byte_index in range(7):
		result |= int(bytes[offset + byte_index]) << (byte_index * 8)

	var high_byte := int(bytes[offset + 7])
	if high_byte >= 128:
		result |= (high_byte - 256) << 56
	else:
		result |= high_byte << 56

	return result


static func encode_string(value: String) -> PackedByteArray:
	var utf8_bytes := value.to_utf8_buffer()
	var result := encode_u32_little_endian(utf8_bytes.size())
	result.append_array(utf8_bytes)
	return result


static func world_cell_to_chunk_coords(world_cell: Vector2i) -> Vector2i:
	return WorldSemanticGridScript.world_cell_to_chunk_coords(world_cell)


static func world_cell_to_local_coords(world_cell: Vector2i) -> Vector2i:
	return WorldSemanticGridScript.world_cell_to_local_coords(world_cell)


static func local_coords_to_index(local_coords: Vector2i) -> int:
	return WorldSemanticGridScript.local_coords_to_index(local_coords)


static func chunk_coords_to_origin_cell(chunk_coords: Vector2i) -> Vector2i:
	return WorldSemanticGridScript.chunk_coords_to_origin_cell(chunk_coords)


static func is_cell_in_prewarm_rect(world_cell: Vector2i) -> bool:
	return WorldSemanticGridScript.is_cell_in_prewarm_rect(world_cell)


static func is_chunk_in_prewarm_rect(chunk_coords: Vector2i) -> bool:
	return WorldSemanticGridScript.is_chunk_in_prewarm_rect(chunk_coords)


func _build_canonical_identity_bytes() -> PackedByteArray:
	var result := PackedByteArray()
	result.append_array(encode_i64_little_endian(_semantic_digest_version))
	result.append_array(encode_i64_little_endian(_seed))
	result.append_array(encode_string(_generator_version))
	result.append_array(encode_string(_deterministic_hash_version))
	result.append_array(encode_string(_terrain_backend_id))
	_append_profile_value(result, _generator_parameter_profile)
	return result


func _append_profile_value(target: PackedByteArray, value: Variant) -> void:
	var value_type := typeof(value)

	if value_type == TYPE_BOOL:
		target.append(PROFILE_BOOL_TRUE_TAG if bool(value) else PROFILE_BOOL_FALSE_TAG)
		return

	if value_type == TYPE_INT:
		target.append(PROFILE_INT_TAG)
		target.append_array(encode_i64_little_endian(int(value)))
		return

	if value_type == TYPE_STRING:
		target.append(PROFILE_STRING_TAG)
		target.append_array(encode_string(String(value)))
		return

	if value_type == TYPE_ARRAY:
		var array_value: Array = value
		target.append(PROFILE_ARRAY_TAG)
		target.append_array(encode_u32_little_endian(array_value.size()))
		for item in array_value:
			_append_profile_value(target, item)
		return

	var dictionary_value: Dictionary = value
	var keys := dictionary_value.keys()
	keys.sort_custom(_compare_string_utf8_bytes)
	target.append(PROFILE_DICTIONARY_TAG)
	target.append_array(encode_u32_little_endian(keys.size()))
	for key in keys:
		target.append_array(encode_string(String(key)))
		_append_profile_value(target, dictionary_value[key])


static func _compare_string_utf8_bytes(left: Variant, right: Variant) -> bool:
	var left_bytes := String(left).to_utf8_buffer()
	var right_bytes := String(right).to_utf8_buffer()
	var compare_length: int = mini(left_bytes.size(), right_bytes.size())

	for index in range(compare_length):
		var left_byte := int(left_bytes[index])
		var right_byte := int(right_bytes[index])
		if left_byte == right_byte:
			continue
		return left_byte < right_byte

	return left_bytes.size() < right_bytes.size()


func _build_sha256(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	var error := context.start(HashingContext.HASH_SHA256)
	if error != OK:
		push_error("Failed to start SHA-256 hashing context")
		return PackedByteArray()

	error = context.update(bytes)
	if error != OK:
		push_error("Failed to update SHA-256 hashing context")
		return PackedByteArray()

	return context.finish()


func _build_validation_error(
	next_seed: int,
	next_generator_version: String,
	next_deterministic_hash_version: String,
	next_terrain_backend_id: String,
	next_generator_parameter_profile: Dictionary,
	next_semantic_digest_version: int
) -> String:
	if next_semantic_digest_version <= 0:
		return "semantic_digest_version must be > 0"
	if next_generator_version.is_empty():
		return "generator_version must not be empty"
	if next_deterministic_hash_version.is_empty():
		return "deterministic_hash_version must not be empty"
	if next_terrain_backend_id.is_empty():
		return "terrain_backend_id must not be empty"

	var profile_validation_error := get_profile_validation_error(next_generator_parameter_profile)
	if not profile_validation_error.is_empty():
		return profile_validation_error

	if WorldSemanticGridScript.TILES_PER_CHUNK != WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.x * WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.y:
		return "TILES_PER_CHUNK does not match SEMANTIC_CHUNK_SIZE area"
	if WorldSemanticGridScript.PREWARM_CHUNK_RECT.size.x * WorldSemanticGridScript.PREWARM_CHUNK_RECT.size.y != WorldSemanticGridScript.PREWARM_TOTAL_CHUNKS:
		return "PREWARM_TOTAL_CHUNKS does not match PREWARM_CHUNK_RECT area"
	if WorldSemanticGridScript.PREWARM_TILE_RECT.size != Vector2i(
		WorldSemanticGridScript.PREWARM_CHUNK_RECT.size.x * WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.x,
		WorldSemanticGridScript.PREWARM_CHUNK_RECT.size.y * WorldSemanticGridScript.SEMANTIC_CHUNK_SIZE.y
	):
		return "PREWARM_TILE_RECT size does not match PREWARM_CHUNK_RECT × SEMANTIC_CHUNK_SIZE"

	return ""


func _reject_frozen_write(field_name: String) -> void:
	if _is_frozen:
		push_error("WorldGenerationIdentity is immutable after construction; rejected write to %s" % field_name)
