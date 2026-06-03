class_name WorldSemanticMapSave
extends RefCounted


const WorldGenerationIdentityScript := preload("res://scripts/mapgen/world/WorldGenerationIdentity.gd")
const WorldSemanticChunkScript := preload("res://scripts/mapgen/world/WorldSemanticChunk.gd")
const WorldSemanticStoreScript := preload("res://scripts/mapgen/world/WorldSemanticStore.gd")

const SAVE_VERSION: int = 1
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
	save_path: String = DEFAULT_SAVE_PATH
) -> bool:
	if identity == null or not identity.is_valid():
		return false
	if semantic_store == null or semantic_store.prewarm_state != WorldSemanticStoreScript.PrewarmState.READY:
		return false

	var save_data := {
		"save_version": SAVE_VERSION,
		"identity": _identity_to_data(identity),
		"prewarm_chunks": _chunks_to_data(semantic_store.chunks),
		"runtime_chunks": _chunks_to_data(runtime_chunks),
		"camera_cell": camera_cell,
		"camera_zoom": camera_zoom,
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

	var save_data: Variant = file.get_var(true)
	if typeof(save_data) != TYPE_DICTIONARY:
		return {}
	if int(save_data.get("save_version", 0)) != SAVE_VERSION:
		return {}

	var identity: WorldGenerationIdentity = _identity_from_data(save_data.get("identity", {}))
	if identity == null or not identity.is_valid():
		return {}

	var prewarm_chunks: Dictionary = _chunks_from_data(save_data.get("prewarm_chunks", []))
	if prewarm_chunks.is_empty():
		return {}

	var runtime_chunks: Dictionary = _chunks_from_data(save_data.get("runtime_chunks", []))
	var store: WorldSemanticStore = WorldSemanticStoreScript.new()
	if not store.restore_ready_from_chunks(identity, prewarm_chunks):
		return {}

	return {
		"identity": identity,
		"semantic_store": store,
		"runtime_chunks": runtime_chunks,
		"camera_cell": save_data.get("camera_cell", Vector2i.ZERO),
		"camera_zoom": float(save_data.get("camera_zoom", 1.0)),
	}


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


static func _chunks_to_data(chunks: Dictionary) -> Array:
	var result: Array = []
	for chunk_coords_variant in chunks.keys():
		var chunk: WorldSemanticChunk = chunks[chunk_coords_variant]
		if chunk == null:
			continue
		result.append({
			"chunk_coords": chunk.chunk_coords,
			"terrain_ids": chunk.terrain_ids,
			"base_resource_ids": chunk.base_resource_ids,
			"flags": chunk.flags,
			"base_resource_amounts": chunk.base_resource_amounts,
			"base_patch_key_indices": chunk.base_patch_key_indices,
			"patch_key_table_data": chunk.patch_key_table_data,
		})
	return result


static func _chunks_from_data(chunks_data: Variant) -> Dictionary:
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
