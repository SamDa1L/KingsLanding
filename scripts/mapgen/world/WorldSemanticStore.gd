class_name WorldSemanticStore
extends RefCounted


const WorldGenerationIdentityScript := preload("res://scripts/mapgen/world/WorldGenerationIdentity.gd")
const WorldSemanticChunkScript := preload("res://scripts/mapgen/world/WorldSemanticChunk.gd")
const WorldSemanticGridScript := preload("res://scripts/mapgen/world/WorldSemanticGrid.gd")

const QUERY_MISS: int = -1
const PATCH_PAYLOAD_STRIDE: int = 3

enum PrewarmState {
	ACCEPTING,
	READY,
	INVALID,
}

enum SubmitStatus {
	OK,
	REJECT_NOT_ACCEPTING,
	REJECT_RUN_ID,
	REJECT_DIGEST,
	REJECT_FULL_HASH,
	REJECT_CANONICAL_IDENTITY,
	REJECT_RECT,
	REJECT_OUT_OF_RANGE,
	REJECT_DUPLICATE_CHUNK,
	REJECT_INVALID_PACKED_DATA,
}

enum PatchLookupResult {
	MISS = -1,
	NONE = 0,
	FOUND = 1,
}

var prewarm_state: PrewarmState = PrewarmState.INVALID
var expected_prewarm_run_id: int = 0
var expected_semantic_digest: int = 0
var expected_semantic_hash256: PackedByteArray = PackedByteArray()
var expected_canonical_identity_bytes: PackedByteArray = PackedByteArray()
var expected_prewarm_chunk_rect: Rect2i = Rect2i()
var chunks: Dictionary = {}
var submitted_chunk_count: int = 0
var last_submit_error: String = ""

var _is_bound: bool = false


func bind_prewarm_batch(identity: WorldGenerationIdentity, run_id: int) -> bool:
	if identity == null:
		last_submit_error = "bind_prewarm_batch requires a non-null identity"
		return false
	if not identity.is_valid():
		last_submit_error = "bind_prewarm_batch requires a valid identity"
		return false
	if _is_bound:
		last_submit_error = "Store is already bound to a prewarm batch"
		return false
	if not chunks.is_empty():
		last_submit_error = "Store must be empty before binding"
		return false

	expected_prewarm_run_id = run_id
	expected_semantic_digest = int(identity.semantic_digest)
	expected_semantic_hash256 = identity.semantic_hash256.duplicate()
	expected_canonical_identity_bytes = identity.canonical_identity_bytes.duplicate()
	expected_prewarm_chunk_rect = identity.prewarm_chunk_rect
	submitted_chunk_count = 0
	prewarm_state = PrewarmState.ACCEPTING
	last_submit_error = ""
	_is_bound = true
	return true


func submit_prewarm_chunk(
	chunk_result: Dictionary,
	expected_run_id: int,
	expected_digest: int,
	expected_chunk_rect: Rect2i
) -> SubmitStatus:
	last_submit_error = ""

	if prewarm_state != PrewarmState.ACCEPTING:
		return _reject(SubmitStatus.REJECT_NOT_ACCEPTING, "Store is not accepting prewarm submissions")

	if expected_run_id != expected_prewarm_run_id:
		return _reject(SubmitStatus.REJECT_RUN_ID, "Expected run id does not match bound run id")

	if expected_digest != expected_semantic_digest:
		return _reject(SubmitStatus.REJECT_DIGEST, "Expected semantic digest does not match bound digest")

	if expected_chunk_rect != expected_prewarm_chunk_rect:
		return _reject(SubmitStatus.REJECT_RECT, "Expected chunk rect does not match bound prewarm rect")

	if not chunk_result.has("prewarm_run_id") or typeof(chunk_result["prewarm_run_id"]) != TYPE_INT:
		return _reject(SubmitStatus.REJECT_INVALID_PACKED_DATA, "chunk_result.prewarm_run_id must be int")
	if int(chunk_result["prewarm_run_id"]) != expected_prewarm_run_id:
		return _reject(SubmitStatus.REJECT_RUN_ID, "chunk_result.prewarm_run_id does not match bound run id")

	if not chunk_result.has("semantic_digest") or typeof(chunk_result["semantic_digest"]) != TYPE_INT:
		return _reject(SubmitStatus.REJECT_INVALID_PACKED_DATA, "chunk_result.semantic_digest must be int")
	if int(chunk_result["semantic_digest"]) != expected_semantic_digest:
		return _reject(SubmitStatus.REJECT_DIGEST, "chunk_result.semantic_digest does not match bound digest")

	if not chunk_result.has("semantic_hash256") or typeof(chunk_result["semantic_hash256"]) != TYPE_PACKED_BYTE_ARRAY:
		return _reject(SubmitStatus.REJECT_INVALID_PACKED_DATA, "chunk_result.semantic_hash256 must be PackedByteArray")
	if chunk_result["semantic_hash256"] != expected_semantic_hash256:
		return _reject(SubmitStatus.REJECT_FULL_HASH, "chunk_result.semantic_hash256 does not match bound hash")

	if not chunk_result.has("canonical_identity_bytes") or typeof(chunk_result["canonical_identity_bytes"]) != TYPE_PACKED_BYTE_ARRAY:
		return _reject(SubmitStatus.REJECT_INVALID_PACKED_DATA, "chunk_result.canonical_identity_bytes must be PackedByteArray")
	if chunk_result["canonical_identity_bytes"] != expected_canonical_identity_bytes:
		return _reject(SubmitStatus.REJECT_CANONICAL_IDENTITY, "chunk_result.canonical_identity_bytes does not match bound canonical identity")

	if not chunk_result.has("chunk_coords") or typeof(chunk_result["chunk_coords"]) != TYPE_VECTOR2I:
		return _reject(SubmitStatus.REJECT_INVALID_PACKED_DATA, "chunk_result.chunk_coords must be Vector2i")

	var chunk_coords: Vector2i = chunk_result["chunk_coords"]
	if not expected_prewarm_chunk_rect.has_point(chunk_coords):
		return _reject(SubmitStatus.REJECT_OUT_OF_RANGE, "chunk_result.chunk_coords is outside bound prewarm rect")

	if chunks.has(chunk_coords):
		return _reject(SubmitStatus.REJECT_DUPLICATE_CHUNK, "chunk_result.chunk_coords was already submitted")

	var validation_error := WorldSemanticChunkScript.validate_result(chunk_result)
	if not validation_error.is_empty():
		return _reject(SubmitStatus.REJECT_INVALID_PACKED_DATA, validation_error)

	var chunk := WorldSemanticChunkScript.from_validated_result(chunk_result)
	if chunk == null:
		return _reject(SubmitStatus.REJECT_INVALID_PACKED_DATA, "WorldSemanticChunk.from_validated_result returned null")

	chunks[chunk_coords] = chunk
	submitted_chunk_count += 1
	return SubmitStatus.OK


func seal_prewarm_success() -> bool:
	last_submit_error = ""
	if prewarm_state != PrewarmState.ACCEPTING:
		last_submit_error = "seal_prewarm_success requires ACCEPTING state"
		return false

	var expected_chunk_count := expected_prewarm_chunk_rect.size.x * expected_prewarm_chunk_rect.size.y
	if submitted_chunk_count != expected_chunk_count:
		last_submit_error = "seal_prewarm_success requires full chunk coverage"
		return false
	if chunks.size() != expected_chunk_count:
		last_submit_error = "seal_prewarm_success requires exact stored chunk count"
		return false

	for chunk_coords_variant in chunks.keys():
		var chunk_coords: Vector2i = chunk_coords_variant
		if not expected_prewarm_chunk_rect.has_point(chunk_coords):
			last_submit_error = "seal_prewarm_success found out-of-range chunk"
			return false

	for chunk_y in range(expected_prewarm_chunk_rect.position.y, expected_prewarm_chunk_rect.end.y):
		for chunk_x in range(expected_prewarm_chunk_rect.position.x, expected_prewarm_chunk_rect.end.x):
			var required_coords := Vector2i(chunk_x, chunk_y)
			if not chunks.has(required_coords):
				last_submit_error = "seal_prewarm_success missing required chunk %s" % str(required_coords)
				return false

	prewarm_state = PrewarmState.READY
	return true


func invalidate_prewarm() -> void:
	prewarm_state = PrewarmState.INVALID


func restore_ready_from_chunks(identity: WorldGenerationIdentity, restored_chunks: Dictionary) -> bool:
	last_submit_error = ""
	if identity == null or not identity.is_valid():
		last_submit_error = "restore_ready_from_chunks requires valid identity"
		return false
	if restored_chunks.is_empty():
		last_submit_error = "restore_ready_from_chunks requires chunks"
		return false
	if _is_bound or not chunks.is_empty():
		last_submit_error = "restore_ready_from_chunks requires an empty unbound store"
		return false

	expected_prewarm_run_id = 0
	expected_semantic_digest = int(identity.semantic_digest)
	expected_semantic_hash256 = identity.semantic_hash256.duplicate()
	expected_canonical_identity_bytes = identity.canonical_identity_bytes.duplicate()
	expected_prewarm_chunk_rect = identity.prewarm_chunk_rect
	chunks = restored_chunks.duplicate()
	submitted_chunk_count = chunks.size()
	prewarm_state = PrewarmState.READY
	_is_bound = true
	return true


func has_chunk(chunk_coords: Vector2i) -> bool:
	return chunks.has(chunk_coords)


func borrow_readonly_chunk(chunk_coords: Vector2i) -> WorldSemanticChunk:
	if prewarm_state != PrewarmState.READY:
		return null
	if not chunks.has(chunk_coords):
		return null
	return chunks[chunk_coords]


func get_terrain_id(world_cell: Vector2i) -> int:
	if prewarm_state != PrewarmState.READY:
		return QUERY_MISS
	var chunk_coords := WorldSemanticGridScript.world_cell_to_chunk_coords(world_cell)
	if not chunks.has(chunk_coords):
		return QUERY_MISS
	var chunk: WorldSemanticChunk = chunks[chunk_coords]
	return chunk.get_terrain_id_by_index(WorldSemanticGridScript.world_cell_to_local_index(world_cell))


func get_base_resource_id(world_cell: Vector2i) -> int:
	if prewarm_state != PrewarmState.READY:
		return QUERY_MISS
	var chunk_coords := WorldSemanticGridScript.world_cell_to_chunk_coords(world_cell)
	if not chunks.has(chunk_coords):
		return QUERY_MISS
	var chunk: WorldSemanticChunk = chunks[chunk_coords]
	return chunk.get_base_resource_id_by_index(WorldSemanticGridScript.world_cell_to_local_index(world_cell))


func get_flags(world_cell: Vector2i) -> int:
	if prewarm_state != PrewarmState.READY:
		return QUERY_MISS
	var chunk_coords := WorldSemanticGridScript.world_cell_to_chunk_coords(world_cell)
	if not chunks.has(chunk_coords):
		return QUERY_MISS
	var chunk: WorldSemanticChunk = chunks[chunk_coords]
	return chunk.get_flags_by_index(WorldSemanticGridScript.world_cell_to_local_index(world_cell))


func get_base_resource_amount(world_cell: Vector2i) -> int:
	if prewarm_state != PrewarmState.READY:
		return QUERY_MISS
	var chunk_coords := WorldSemanticGridScript.world_cell_to_chunk_coords(world_cell)
	if not chunks.has(chunk_coords):
		return QUERY_MISS
	var chunk: WorldSemanticChunk = chunks[chunk_coords]
	return chunk.get_base_resource_amount_by_index(WorldSemanticGridScript.world_cell_to_local_index(world_cell))


func get_patch_key_payload(world_cell: Vector2i, out_payload: PackedInt32Array) -> PatchLookupResult:
	if prewarm_state != PrewarmState.READY:
		return PatchLookupResult.MISS
	if out_payload.size() < PATCH_PAYLOAD_STRIDE:
		push_error("WorldSemanticStore.get_patch_key_payload requires out_payload size >= 3")
		return PatchLookupResult.MISS

	var chunk_coords := WorldSemanticGridScript.world_cell_to_chunk_coords(world_cell)
	if not chunks.has(chunk_coords):
		return PatchLookupResult.MISS

	var chunk: WorldSemanticChunk = chunks[chunk_coords]
	var local_index := WorldSemanticGridScript.world_cell_to_local_index(world_cell)
	if chunk.get_base_resource_id_by_index(local_index) == WorldSemanticChunkScript.RESOURCE_NONE:
		return PatchLookupResult.NONE

	if chunk.copy_patch_payload_by_index(local_index, out_payload) == WorldSemanticChunkScript.INVALID_INDEX:
		return PatchLookupResult.MISS

	return PatchLookupResult.FOUND


func get_cached_base_semantic_for_cell(world_cell: Vector2i) -> Dictionary:
	var terrain_id := get_terrain_id(world_cell)
	if terrain_id == QUERY_MISS:
		return {}

	var resource_id := get_base_resource_id(world_cell)
	var payload: Variant = null
	var payload_buffer := PackedInt32Array([0, 0, 0])
	var patch_lookup := get_patch_key_payload(world_cell, payload_buffer)
	if patch_lookup == PatchLookupResult.FOUND:
		payload = [int(payload_buffer[0]), int(payload_buffer[1]), int(payload_buffer[2])]

	return {
		"terrain_id": terrain_id,
		"base_resource_id": resource_id,
		"flags": get_flags(world_cell),
		"base_resource_amount": get_base_resource_amount(world_cell),
		"base_patch_key_payload": payload,
	}


func _reject(status: SubmitStatus, error_message: String) -> SubmitStatus:
	last_submit_error = error_message
	return status
