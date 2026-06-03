class_name WorldPrewarmBuilder
extends RefCounted


signal progress_changed(submitted_count: int, total_count: int)
signal prewarm_completed(run_id: int, store)
signal prewarm_failed(run_id: int, first_error: String)
signal prewarm_cancelled(run_id: int)


const ResourcePatchGeneratorScript := preload("res://scripts/mapgen/ResourcePatchGenerator.gd")
const WorldSemanticGridScript := preload("res://scripts/mapgen/world/WorldSemanticGrid.gd")
const WorldSemanticStoreScript := preload("res://scripts/mapgen/world/WorldSemanticStore.gd")

enum BuilderState {
	IDLE,
	RUNNING,
	CANCELLING,
	CANCELLED,
	FAILING,
	FAILED,
	SUCCEEDED,
}

const INVALID_GROUP_ID: int = -1

var state: BuilderState = BuilderState.IDLE
var identity = null
var semantic_store = null
var prewarm_run_id: int = 0

var group_id: int = INVALID_GROUP_ID
var worker_count: int = 0
var max_in_flight_results: int = 0

var result_queue: Array = []
var in_flight_result_count: int = 0
var submitted_chunk_count: int = 0
var first_error: String = ""

var cancelled: bool = false
var failed: bool = false

var queue_mutex = null
var queue_writable_semaphore = null

var total_chunk_count: int = 0
var queue_peak_size: int = 0
var start_time_usec: int = 0
var successful_worker_generation_duration_usec_sum: int = 0
var successful_generated_count: int = 0
var last_submission_duration_usec: int = 0
var total_submission_duration_usec: int = 0
var max_submission_frame_duration_usec: int = 0
var total_submission_frame_duration_usec: int = 0
var submission_frame_duration_samples_usec: Array[int] = []

var test_chunk_result_provider: Callable = Callable()
var test_worker_count_override: int = -1
var test_max_in_flight_results_override: int = -1

var _group_waited: bool = false
var _terminal_signal_emitted: bool = false


func _init() -> void:
	queue_mutex = Mutex.new()
	queue_writable_semaphore = Semaphore.new()


func start(next_identity, next_store, run_id: int) -> bool:
	if state != BuilderState.IDLE:
		return false
	if next_identity == null or not next_identity.is_valid():
		return false
	if next_store == null:
		return false
	if next_store.prewarm_state != WorldSemanticStoreScript.PrewarmState.ACCEPTING:
		return false
	if next_store.expected_prewarm_run_id != run_id:
		return false
	if int(next_store.expected_semantic_digest) != int(next_identity.semantic_digest):
		return false
	if next_store.expected_semantic_hash256 != next_identity.semantic_hash256:
		return false
	if next_store.expected_canonical_identity_bytes != next_identity.canonical_identity_bytes:
		return false
	if next_store.expected_prewarm_chunk_rect != next_identity.prewarm_chunk_rect:
		return false

	identity = next_identity
	semantic_store = next_store
	prewarm_run_id = run_id
	total_chunk_count = identity.prewarm_chunk_rect.size.x * identity.prewarm_chunk_rect.size.y
	worker_count = _compute_worker_count()
	max_in_flight_results = _compute_max_in_flight_results()
	result_queue.clear()
	in_flight_result_count = 0
	submitted_chunk_count = 0
	first_error = ""
	cancelled = false
	failed = false
	queue_peak_size = 0
	start_time_usec = Time.get_ticks_usec()
	successful_worker_generation_duration_usec_sum = 0
	successful_generated_count = 0
	last_submission_duration_usec = 0
	total_submission_duration_usec = 0
	max_submission_frame_duration_usec = 0
	total_submission_frame_duration_usec = 0
	submission_frame_duration_samples_usec.clear()
	group_id = INVALID_GROUP_ID
	_group_waited = false
	_terminal_signal_emitted = false

	queue_mutex = Mutex.new()
	queue_writable_semaphore = Semaphore.new()
	for _slot_index in range(max_in_flight_results):
		queue_writable_semaphore.post()

	state = BuilderState.RUNNING
	group_id = WorkerThreadPool.add_group_task(
		Callable(self, "_worker_build_chunk_by_task_index"),
		total_chunk_count,
		worker_count,
		false,
		"World semantic prewarm"
	)
	return true


func process_submission_budget(submission_budget_usec: int) -> void:
	if state != BuilderState.RUNNING:
		return

	var frame_start_usec := Time.get_ticks_usec()
	var processed_any := false

	while true:
		var chunk_result = _take_next_result_from_queue()
		if chunk_result == null:
			break

		processed_any = true
		var submit_start_usec := Time.get_ticks_usec()
		var identity_error := _validate_result_identity(chunk_result)
		var store_status := WorldSemanticStoreScript.SubmitStatus.OK

		if identity_error.is_empty():
			store_status = semantic_store.submit_prewarm_chunk(
				chunk_result,
				prewarm_run_id,
				int(identity.semantic_digest),
				identity.prewarm_chunk_rect
			)
			if store_status == WorldSemanticStoreScript.SubmitStatus.OK:
				submitted_chunk_count += 1
				progress_changed.emit(submitted_chunk_count, total_chunk_count)
			else:
				identity_error = "submit_prewarm_chunk failed with status=%s error=%s" % [
					str(store_status),
					String(semantic_store.last_submit_error),
				]

		_release_in_flight_result_slot()
		chunk_result = null

		last_submission_duration_usec = Time.get_ticks_usec() - submit_start_usec
		total_submission_duration_usec += last_submission_duration_usec

		if not identity_error.is_empty():
			fail_prewarm(identity_error)
			break

		if submission_budget_usec > 0 and processed_any:
			var elapsed_usec := Time.get_ticks_usec() - frame_start_usec
			if elapsed_usec >= submission_budget_usec:
				break

	if processed_any:
		_record_submission_frame_duration(Time.get_ticks_usec() - frame_start_usec)

	if state == BuilderState.RUNNING and group_id != INVALID_GROUP_ID:
		var queue_empty := _get_queue_size() == 0
		if queue_empty and WorkerThreadPool.is_group_task_completed(group_id):
			_wait_for_group_completion_if_needed()
			if submitted_chunk_count != total_chunk_count:
				fail_prewarm(
					"processed all tasks but submitted_chunk_count=%d expected=%d"
					% [submitted_chunk_count, total_chunk_count]
				)
				return
			if not semantic_store.seal_prewarm_success():
				fail_prewarm("seal_prewarm_success failed: %s" % String(semantic_store.last_submit_error))
				return

			state = BuilderState.SUCCEEDED
			if not _terminal_signal_emitted:
				_terminal_signal_emitted = true
				prewarm_completed.emit(prewarm_run_id, semantic_store)


func request_cancel() -> void:
	if state != BuilderState.RUNNING:
		return
	state = BuilderState.CANCELLING
	cancelled = true
	_close_and_wake_result_queue()


func cancel_and_wait() -> void:
	if is_terminal():
		return
	if state == BuilderState.IDLE:
		return

	if state == BuilderState.RUNNING:
		state = BuilderState.CANCELLING
		cancelled = true
		_close_and_wake_result_queue()
	elif state == BuilderState.FAILING:
		cancelled = true
		_close_and_wake_result_queue()

	_discard_queued_results()
	_wait_for_group_completion_if_needed()

	if failed or state == BuilderState.FAILING:
		state = BuilderState.FAILED
		if not _terminal_signal_emitted:
			_terminal_signal_emitted = true
			prewarm_failed.emit(prewarm_run_id, first_error)
		return

	state = BuilderState.CANCELLED
	if not _terminal_signal_emitted:
		_terminal_signal_emitted = true
		prewarm_cancelled.emit(prewarm_run_id)


func fail_prewarm(error_message: String) -> void:
	queue_mutex.lock()
	if state != BuilderState.RUNNING:
		queue_mutex.unlock()
		return
	state = BuilderState.FAILING
	failed = true
	cancelled = true
	if first_error.is_empty():
		first_error = error_message
	queue_mutex.unlock()
	_close_and_wake_result_queue()


func is_terminal() -> bool:
	return state == BuilderState.CANCELLED \
		or state == BuilderState.FAILED \
		or state == BuilderState.SUCCEEDED


func _chunk_coords_from_task_index(task_index: int) -> Vector2i:
	var width: int = int(identity.prewarm_chunk_rect.size.x)
	var local_x: int = task_index % width
	var local_y := int(task_index / width)
	return identity.prewarm_chunk_rect.position + Vector2i(local_x, local_y)


func _worker_build_chunk_by_task_index(task_index: int) -> void:
	if _should_worker_exit():
		return

	var chunk_coords := _chunk_coords_from_task_index(task_index)
	var generation_start_usec := Time.get_ticks_usec()
	var chunk_result = _build_chunk_result_for_task(task_index, chunk_coords)
	var generation_duration_usec := Time.get_ticks_usec() - generation_start_usec

	if _should_worker_exit():
		return

	if typeof(chunk_result) != TYPE_DICTIONARY or chunk_result.is_empty():
		fail_prewarm("worker produced empty result for task_index=%d chunk=%s" % [task_index, str(chunk_coords)])
		return
	if chunk_result.has("error"):
		fail_prewarm("worker error for task_index=%d chunk=%s: %s" % [task_index, str(chunk_coords), String(chunk_result["error"])])
		return

	queue_mutex.lock()
	successful_worker_generation_duration_usec_sum += generation_duration_usec
	successful_generated_count += 1
	queue_mutex.unlock()

	queue_writable_semaphore.wait()
	if _should_worker_exit():
		return

	queue_mutex.lock()
	if cancelled or failed or state != BuilderState.RUNNING:
		queue_mutex.unlock()
		return
	result_queue.append(chunk_result)
	in_flight_result_count += 1
	if in_flight_result_count > queue_peak_size:
		queue_peak_size = in_flight_result_count
	queue_mutex.unlock()


func _build_chunk_result_for_task(task_index: int, chunk_coords: Vector2i):
	if test_chunk_result_provider.is_valid():
		return test_chunk_result_provider.call(task_index, chunk_coords, identity, prewarm_run_id)

	var generator = ResourcePatchGeneratorScript.new()
	var chunk_result: Dictionary = generator.build_base_semantics_for_chunk_packed(chunk_coords, identity)
	if chunk_result.is_empty():
		return {
			"error": "generator returned empty chunk_result",
		}
	chunk_result["prewarm_run_id"] = prewarm_run_id
	return chunk_result


func _validate_result_identity(chunk_result: Dictionary) -> String:
	if not chunk_result.has("prewarm_run_id") or typeof(chunk_result["prewarm_run_id"]) != TYPE_INT:
		return "chunk_result.prewarm_run_id must be int"
	if int(chunk_result["prewarm_run_id"]) != prewarm_run_id:
		return "chunk_result.prewarm_run_id mismatch"
	if not chunk_result.has("semantic_digest") or typeof(chunk_result["semantic_digest"]) != TYPE_INT:
		return "chunk_result.semantic_digest must be int"
	if int(chunk_result["semantic_digest"]) != int(identity.semantic_digest):
		return "chunk_result.semantic_digest mismatch"
	if not chunk_result.has("semantic_hash256") or typeof(chunk_result["semantic_hash256"]) != TYPE_PACKED_BYTE_ARRAY:
		return "chunk_result.semantic_hash256 must be PackedByteArray"
	if chunk_result["semantic_hash256"] != identity.semantic_hash256:
		return "chunk_result.semantic_hash256 mismatch"
	if not chunk_result.has("canonical_identity_bytes") or typeof(chunk_result["canonical_identity_bytes"]) != TYPE_PACKED_BYTE_ARRAY:
		return "chunk_result.canonical_identity_bytes must be PackedByteArray"
	if chunk_result["canonical_identity_bytes"] != identity.canonical_identity_bytes:
		return "chunk_result.canonical_identity_bytes mismatch"
	return ""


func _take_next_result_from_queue():
	queue_mutex.lock()
	if result_queue.is_empty():
		queue_mutex.unlock()
		return null
	var chunk_result = result_queue.pop_front()
	queue_mutex.unlock()
	return chunk_result


func _release_in_flight_result_slot() -> void:
	queue_mutex.lock()
	if in_flight_result_count > 0:
		in_flight_result_count -= 1
	queue_mutex.unlock()
	queue_writable_semaphore.post()


func _discard_queued_results() -> void:
	queue_mutex.lock()
	var discarded_count := result_queue.size()
	result_queue.clear()
	in_flight_result_count = max(in_flight_result_count - discarded_count, 0)
	queue_mutex.unlock()

	for _discard_index in range(discarded_count):
		queue_writable_semaphore.post()


func _close_and_wake_result_queue() -> void:
	for _wake_index in range(max(worker_count, 1) + max_in_flight_results + 1):
		queue_writable_semaphore.post()


func _should_worker_exit() -> bool:
	queue_mutex.lock()
	var should_exit := cancelled or failed or state == BuilderState.CANCELLING or state == BuilderState.FAILING
	queue_mutex.unlock()
	return should_exit


func _wait_for_group_completion_if_needed() -> void:
	if group_id == INVALID_GROUP_ID or _group_waited:
		return
	WorkerThreadPool.wait_for_group_task_completion(group_id)
	_group_waited = true


func _compute_worker_count() -> int:
	if test_worker_count_override > 0:
		return test_worker_count_override
	return clampi(OS.get_processor_count() - 1, 1, 8)


func _compute_max_in_flight_results() -> int:
	if test_max_in_flight_results_override > 0:
		return test_max_in_flight_results_override
	return max(worker_count * 2, 1)


func _get_queue_size() -> int:
	queue_mutex.lock()
	var queue_size := result_queue.size()
	queue_mutex.unlock()
	return queue_size


func _record_submission_frame_duration(duration_usec: int) -> void:
	submission_frame_duration_samples_usec.append(duration_usec)
	total_submission_frame_duration_usec += duration_usec
	if duration_usec > max_submission_frame_duration_usec:
		max_submission_frame_duration_usec = duration_usec
