class_name WorldSemanticPrewarmMetrics
extends RefCounted


const WorldSemanticChunkScript := preload("res://scripts/mapgen/world/WorldSemanticChunk.gd")
const WorldSemanticGridScript := preload("res://scripts/mapgen/world/WorldSemanticGrid.gd")
const WorldSemanticStoreScript := preload("res://scripts/mapgen/world/WorldSemanticStore.gd")


static func collect_store_metrics(store: WorldSemanticStore) -> Dictionary:
	if store == null:
		return {}

	var chunk_count: int = 0
	var patch_key_table_entries: int = 0
	var terrain_bytes: int = 0
	var resource_bytes: int = 0
	var flags_bytes: int = 0
	var amount_bytes: int = 0
	var patch_index_bytes: int = 0
	var patch_table_bytes: int = 0

	for chunk_value in store.chunks.values():
		var chunk: WorldSemanticChunk = chunk_value
		chunk_count += 1
		patch_key_table_entries += chunk.patch_key_table_data.size()
		terrain_bytes += chunk.terrain_ids.size()
		resource_bytes += chunk.base_resource_ids.size()
		flags_bytes += chunk.flags.size()
		amount_bytes += chunk.base_resource_amounts.size()
		patch_index_bytes += chunk.base_patch_key_indices.size() * 4
		patch_table_bytes += chunk.patch_key_table_data.size() * 4

	var resident_packed_bytes: int = terrain_bytes + resource_bytes + flags_bytes + amount_bytes + patch_index_bytes + patch_table_bytes
	return {
		"chunk_count": chunk_count,
		"submitted_chunk_count": int(store.submitted_chunk_count),
		"patch_key_table_entries": patch_key_table_entries,
		"terrain_bytes": terrain_bytes,
		"resource_bytes": resource_bytes,
		"flags_bytes": flags_bytes,
		"amount_bytes": amount_bytes,
		"patch_index_bytes": patch_index_bytes,
		"patch_table_bytes": patch_table_bytes,
		"resident_packed_bytes": resident_packed_bytes,
		"resident_packed_mib": float(resident_packed_bytes) / 1048576.0,
		"tile_count": chunk_count * WorldSemanticGridScript.TILES_PER_CHUNK,
	}


static func collect_builder_metrics(builder: WorldPrewarmBuilder) -> Dictionary:
	if builder == null:
		return {}

	var average_submit_usec: float = 0.0
	if builder.submitted_chunk_count > 0:
		average_submit_usec = float(builder.total_submission_duration_usec) / float(builder.submitted_chunk_count)

	var average_worker_generation_usec: float = 0.0
	if builder.successful_generated_count > 0:
		average_worker_generation_usec = float(builder.successful_worker_generation_duration_usec_sum) / float(builder.successful_generated_count)

	var average_submission_frame_usec: float = 0.0
	if builder.submission_frame_duration_samples_usec.size() > 0:
		average_submission_frame_usec = float(builder.total_submission_frame_duration_usec) / float(builder.submission_frame_duration_samples_usec.size())

	var sorted_frame_samples: Array[int] = []
	sorted_frame_samples.assign(builder.submission_frame_duration_samples_usec)
	sorted_frame_samples.sort()

	return {
		"worker_count": int(builder.worker_count),
		"max_in_flight_results": int(builder.max_in_flight_results),
		"queue_peak_size": int(builder.queue_peak_size),
		"in_flight_result_count": int(builder.in_flight_result_count),
		"submitted_chunk_count": int(builder.submitted_chunk_count),
		"successful_generated_count": int(builder.successful_generated_count),
		"average_submit_usec": average_submit_usec,
		"average_worker_generation_usec": average_worker_generation_usec,
		"last_submission_duration_usec": int(builder.last_submission_duration_usec),
		"total_submission_duration_usec": int(builder.total_submission_duration_usec),
		"max_submission_frame_duration_usec": int(builder.max_submission_frame_duration_usec),
		"average_submission_frame_duration_usec": average_submission_frame_usec,
		"submission_frame_duration_p95_usec": _compute_percentile(sorted_frame_samples, 0.95),
		"submission_frame_duration_samples": sorted_frame_samples.duplicate(),
		"submission_frame_count": sorted_frame_samples.size(),
		"estimated_worker_temp_peak_bytes": _estimate_worker_temp_peak_bytes(builder),
	}


static func collect_loading_metrics(loading: RandomGovernanceWorldLoading) -> Dictionary:
	if loading == null:
		return {}

	var builder_metrics: Dictionary = {}
	if loading.builder != null:
		builder_metrics = collect_builder_metrics(loading.builder)

	var store_metrics: Dictionary = {}
	if loading.current_store != null:
		store_metrics = collect_store_metrics(loading.current_store)

	return {
		"run_id": int(loading.current_run_id),
		"elapsed_usec": int(loading.get_elapsed_usec()),
		"average_submit_usec_from_loading": float(loading.get_average_submit_usec()),
		"submitted_chunk_count": int(loading.submitted_chunk_count),
		"total_chunk_count": int(loading.total_chunk_count),
		"stage0_baseline_metrics": loading.get_stage0_baseline_metrics(),
		"builder_metrics": builder_metrics,
		"store_metrics": store_metrics,
	}


static func _estimate_worker_temp_peak_bytes(builder: WorldPrewarmBuilder) -> int:
	var active_results: int = maxi(builder.max_in_flight_results, builder.worker_count)
	var per_chunk_result_bytes: int = (
		WorldSemanticGridScript.TILES_PER_CHUNK * 4
		+ WorldSemanticGridScript.TILES_PER_CHUNK * 4
		+ WorldSemanticGridScript.TILES_PER_CHUNK * 4
		+ WorldSemanticGridScript.TILES_PER_CHUNK * 4
		+ WorldSemanticGridScript.TILES_PER_CHUNK * 12
	)
	return active_results * per_chunk_result_bytes


static func _compute_percentile(sorted_values: Array[int], percentile: float) -> float:
	if sorted_values.is_empty():
		return 0.0

	var clamped_percentile := clampf(percentile, 0.0, 1.0)
	var sample_index := maxi(int(ceil(clamped_percentile * float(sorted_values.size()))) - 1, 0)
	return float(sorted_values[sample_index])
